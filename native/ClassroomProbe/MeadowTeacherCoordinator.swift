import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport
import MeadowClassroomSupport

/// Teacher-owned authority and one production renderer, attached to exactly one
/// output host. The teacher's controls and private sheets are separate siblings.
@MainActor
final class MeadowTeacherCoordinator:ObservableObject {
    let backend=ClassroomGameBackend()
    let frameMirror=MeadowFrameMirror()
    private var mirrorTimer:Timer?
    private var previewObservers=Set<UUID>()
    private struct UIState:Equatable {
        let gameID:String?,surface:ClassroomPublicSurface,historyID:String?,historyCount:Int,movement:Int,current:String?,pauses:Set<GamePause>,busy:Bool,ready:Bool,moving:Bool,travel:Bool,player:String?
    }
    private var lastUIState:UIState?
    private func publishChanges(){
        let c=campaign,state=c?.engine.state
        let next=UIState(gameID:state?.gameID,surface:surface,historyID:c?.engine.history.last?.id,historyCount:c?.engine.history.count ?? 0,movement:Int(ceil(c?.movementRemaining ?? 0)),current:state?.battle?.current,pauses:state?.pauseReasons ?? [],busy:busy,ready:ready,moving:c?.isMoving ?? false,travel:c?.travel != nil,player:c?.selectedPlayerID)
        if next != lastUIState {lastUIState=next;revision += 1}
    }
    private func updateMirrorDemand(){
        let enabled=ClassroomPreviewPolicy.enabled(external:externalConnected,visible:!previewObservers.isEmpty,foreground:UIApplication.shared.applicationState == .active,privateModal:modalOpen,surface:surface)
        if renderer?.classroomMirrorEnabled != enabled {renderer?.classroomMirrorEnabled=enabled}
    }
    func previewVisibility(_ id:UUID,visible:Bool){
        if visible{previewObservers.insert(id)}else{previewObservers.remove(id)}
        updateMirrorDemand()
    }
    @Published private(set) var revision=0
    @Published private(set) var externalIDs=Set<String>()
    @Published private(set) var message="先在教师后台生成地图，或继续已保存的行程。"
    @Published var selectedNode:Int?
    @Published var selectedTarget="p1"
    var localOutputPreview=false
    private(set) var renderer:GameViewController?
    weak var privatePresenter:UIViewController? {didSet{renderer?.classroomPrivatePresenter=privatePresenter}}
    private var timer:Timer?
    private var installed=false
    private var enemyWork:DispatchWorkItem?
    private var lastTick=ProcessInfo.processInfo.systemUptime
    private var aiKey:String?
    private func tick(){
        let now=ProcessInfo.processInfo.systemUptime,delta=min(0.5,max(0,now-lastTick));lastTick=now
        defer{publishChanges();updateMirrorDemand()}
        renderer?.classroomFinishBattleIfReady()
        guard UIApplication.shared.applicationState == .active,ready,!modalOpen,let c=campaign,c.engine.state.battle != nil,surface != .book,c.engine.state.pauseReasons.isEmpty else{enemyWork?.cancel();enemyWork=nil;aiKey=nil;return}
        guard !busy else{return}
        do{
            if try c.engine.advanceClock(by:delta) != nil {renderer?.classroomRefresh()}
            guard let actor=c.engine.state.battle?.current,c.engine.state.units[actor]?.kind == .monster else{enemyWork?.cancel();enemyWork=nil;aiKey=nil;return}
            let key=c.engine.state.gameID+":"+actor+":"+String(c.engine.history.count)
            guard aiKey != key else{return};enemyWork?.cancel();aiKey=key
            let task=DispatchWorkItem{[weak self,weak c] in
                guard let self,let c,self.campaign === c,!self.busy,!self.modalOpen,c.engine.state.pauseReasons.isEmpty,self.surface != .book else{return}
                self.renderer?.classroomEnemyStep()
            }
            enemyWork=task;DispatchQueue.main.asyncAfter(deadline:.now()+0.65,execute:task)
        }catch{message=error.localizedDescription;enemyWork?.cancel();enemyWork=nil}
    }
    var campaign:MeadowCampaignSession? {backend.campaign}
    var surface:ClassroomPublicSurface {backend.surface}
    var busy:Bool {renderer?.classroomBusy ?? false}
    var ready:Bool {renderer?.classroomReady ?? false}
    var actions:[PartyAction] {
        guard let c=campaign,let actor=c.engine.state.battle?.current,c.engine.state.units[actor]?.kind == .player else{return []}
        return renderer?.classroomActions ?? []
    }
    var externalConnected:Bool {!externalIDs.isEmpty}
    var modalOpen:Bool {
        guard let first=privatePresenter?.presentedViewController else{return false}
        return !localOutputPreview || first.presentedViewController != nil
    }
    private var presentationHost:UIViewController? {
        var top=privatePresenter
        while let next=top?.presentedViewController {top=next}
        return top
    }
    init(){
        mirrorTimer=Timer.scheduledTimer(withTimeInterval:1/ClassroomPreviewPolicy.framesPerSecond,repeats:true){[weak self] _ in
            Task{@MainActor in
                self?.publishMirrorFrame()
            }
        }
        timer=Timer.scheduledTimer(withTimeInterval:0.15,repeats:true){[weak self] _ in Task{@MainActor in self?.tick()}}
    }
    private func publishMirrorFrame(){
        guard renderer?.classroomMirrorEnabled==true,let frame=renderer?.classroomCaptureFrame() else{return}
        frameMirror.frame=frame
    }
    func install(_ session:MeadowCampaignSession){
        do{
            enemyWork?.cancel();enemyWork=nil;aiKey=nil
            try backend.install(session,role:.teacher)
            if let old=renderer {old.willMove(toParent:nil);old.view.removeFromSuperview();old.removeFromParent()}
            let controller=GameViewController(campaign:session,classroomMode:true)
            controller.classroomPrivatePresenter=privatePresenter
            controller.classroomMirrorEnabled=false
            controller.classroomFrameAvailable={ [weak self] in self?.publishMirrorFrame() }
            frameMirror.frame=nil
            controller.classroomAdvanceTravel={ [backend] distance in try backend.advanceTravel(distance:distance,role:.teacher) }
            controller.classroomBattleModel={ [backend] in try backend.battleModel(role:.teacher) }
            controller.classroomStatus={ [weak self] text in guard let self,self.message != text else{return};self.message=text;self.revision += 1 }
            controller.classroomInventoryChanged={ [weak self] id in self?.project(id.map{.inventory($0)} ?? .exploration) }
            controller.classroomReload={ [weak self,weak session] in if let session{self?.install(session)} }
            renderer=controller;installed=true;selectedNode=nil;selectedTarget=session.selectedPlayerID
            message="地图已由后台准备，投放端只显示游戏。";updateMirrorDemand();revision += 1
        }catch{message=error.localizedDescription}
    }
    static var slotStore:MeadowSlotStore {MeadowSlotStore(directory:MeadowMapSettingsViewController.campaignStore().url.deletingLastPathComponent().appendingPathComponent("Slots",isDirectory:true))}
    func openArchives(){
        guard !busy,!modalOpen,let presenter=presentationHost else{return}
        let screen=UIHostingController(rootView:TeacherArchiveConsole(game:self,onClose:{[weak self] in self?.presentationHost?.dismiss(animated:true)}))
        screen.modalPresentationStyle = .formSheet;screen.preferredContentSize=CGSize(width:900,height:720)
        presenter.present(screen,animated:true)
    }
    func loadJourney(_ save:MeadowCampaignSave)throws {
        guard !busy else{throw GameError("请等待动作结束。")}
        try save.validate()
        let wasBook=surface == .book,store=MeadowMapSettingsViewController.campaignStore()
        // Construct and validate without writing, then back up the live working copy.
        _=try MeadowCampaignSession(save:save)
        if let campaign{try Self.slotStore.backup(campaign.snapshot)}
        try store.write(save.encoded())
        install(try MeadowCampaignSession(save:save,persist:store.write))
        if wasBook{project(.book)}
        message="行程已读取；原进度已留在自动备份。";revision += 1
    }
    func rollback(to id:String)throws {
        guard let campaign else{throw GameError("尚未开始行程。")}
        try loadJourney(campaign.snapshot.rollingBack(after:id,book:surface == .book))
        message="已回退到所选操作之后，当前已暂停。";revision += 1
    }
    func applyProfile(_ profile:MeadowPlayerProfile,to id:String)throws {
        guard !busy,let campaign,!campaign.isCompleted else{throw GameError("请等待动作结束，或开始未结算行程。")}
        try profile.validate()
        let wasBook=surface == .book
        try backend.apply(.applyPlayerProfile(unit:id,name:profile.name,appearance:profile.appearance),role:.teacher)
        install(campaign);if wasBook{project(.book)}
        message="已更新姓名和外观，数值与装备保持。";revision += 1
    }
    func joinTeacher(name:String,classID:String,team:String,appearance:PlayerAppearance?)throws {
        guard !busy,let campaign else{throw GameError("请先开始行程。")}
        let wasBook=surface == .book
        try backend.joinTeacher(name:name,classID:classID,team:team,appearance:appearance,role:.teacher)
        install(campaign);if wasBook{project(.book)}
        message="老师已加入独立P7席位。";revision += 1
    }
    func restore(){
        guard !busy,campaign?.engine.state.battle==nil else{message="请先结束当前战斗。";return}
        do{let store=MeadowMapSettingsViewController.campaignStore();guard let save=try store.read() else{message="还没有已保存的行程。";return};try loadJourney(save)}
        catch{message="存档读取失败，原文件保留："+error.localizedDescription}
    }
    func settings(){
        guard !busy,campaign?.engine.state.battle==nil,let presenter=presentationHost else{message="请先结束战斗，再调整随机地图。";return}
        do{try renderer?.classroomSuspend()}catch{message=error.localizedDescription;return}
        let screen=MeadowMapSettingsViewController()
        screen.classroomGenerated={ [backend] config in try backend.generate(config,role:.teacher) }
        screen.classroomCampaignReady={ [weak self] session in self?.install(session) }
        screen.classroomSettingsClosed={ [weak self] in self?.renderer?.classroomResumeRenderer() }
        screen.modalPresentationStyle = .formSheet;screen.preferredContentSize=CGSize(width:1100,height:780)
        presenter.present(screen,animated:true)
    }
    func operation(_ operation:GameViewController.TeacherOperation){
        do{try renderer?.classroomPerform(operation,role:.teacher);revision += 1}catch{message=error.localizedDescription}
    }
    func project(_ value:ClassroomPublicSurface){
        do{
            if value == .book {try renderer?.classroomSuspend();try campaign?.engine.setPause(.book,enabled:true)}
            else if backend.surface == .book {try campaign?.engine.setPause(.book,enabled:false);renderer?.classroomResumeRenderer()}
            try backend.project(value,role:.teacher)
            if case .encounter(let id)=value {renderer?.classroomPreviewEncounter(id)}else{renderer?.classroomPreviewEncounter(nil)}
            revision += 1
        }catch{message=error.localizedDescription}
    }
    func select(_ id:String){do{try backend.selectPlayer(id,role:.teacher);selectedTarget=id;renderer?.classroomRefresh();revision += 1}catch{message=error.localizedDescription}}
    func canTapCanvas(_ point:CGPoint)->Bool {
        guard ready,!busy,!modalOpen,surface != .book else{return false}
        if campaign?.engine.state.battle != nil {return (try? renderer?.classroomBattleHit(at:point,role:.teacher)) != nil}
        return canBeginMapGesture(point)
    }
    func chooseBattleTarget(_ id:String){
        guard !busy,!modalOpen else{return}
        selectedTarget=id;hoveredCanvasAction=nil
        try? renderer?.classroomFocus(nil,target:id,role:.teacher)
        revision += 1
    }
    private var hoveredCanvasAction:PartyAction?
    func canvasHover(_ point:CGPoint?){
        var action:PartyAction?
        if let point,ready,!busy,!modalOpen,case .action(let value)?=try? renderer?.classroomBattleHit(at:point,role:.teacher),canUse(value){action=value}
        guard action != hoveredCanvasAction else{return}
        hoveredCanvasAction=action;focus(action)
    }
    func canvasTap(_ point:CGPoint,selectingNode:Bool){
        guard ready else{message="画面还在准备，请稍候。";return}
        guard !busy,!modalOpen else{message="请等待当前动作结束或关闭后台对话框。";return}
        if campaign?.engine.state.battle != nil {
            if let hit=try? renderer?.classroomBattleHit(at:point,role:.teacher) {
                switch hit {case .action(let action):battle(action);case .target(let id):chooseBattleTarget(id);case .toggleMap:try? renderer?.classroomToggleBattleMap(role:.teacher)}
            }
            return
        }
        guard surface.acceptsMapInput,let c=campaign,c.engine.state.battle==nil,!c.isCompleted else{message="请先收起当前面板或返回探索地图。";return}
        do {
            guard let world=try renderer?.classroomWorldPoint(at:point,role:.teacher) else{message="请点击预览面板外的道路，或收起预览。";return}
            let wx=Double(world.x),wy=Double(world.y)
            let closest=c.engine.state.map.nodes.min{hypot($0.x*1280-wx,$0.y*c.snapshot.layout.coordinateHeight-wy)<hypot($1.x*1280-wx,$1.y*c.snapshot.layout.coordinateHeight-wy)}
            let hitID=try renderer?.classroomNode(atWorldPoint:world,role:.teacher)
            let hit=hitID.flatMap{id in c.engine.state.map.nodes.first{$0.id==id}}
            if selectingNode {selectedNode=hit?.id;message=hit == nil ? "请点击画面中的建筑或节点标记。":"已在实际画面中选中地点，编辑表单仅在后台打开。";revision += 1;return}
            let destination=hit.map{c.point(at:$0.id)} ?? .init(wx,wy)
            try backend.travel(to:destination,role:.teacher)
            renderer?.classroomPreviewEncounter(nil);renderer?.classroomRefresh();message="已指定道路目标，移动条按实际距离扣除。"
            if let node=hit ?? closest,(hit != nil || hypot(node.x*1280-wx,node.y*c.snapshot.layout.coordinateHeight-wy)<80),(node.kind == .combat || node.kind == .boss){selectedNode=node.id;project(.encounter(node.id))}
            revision += 1
        }catch{message=error.localizedDescription}
    }
    var canManipulateMap:Bool {ready && !busy && !modalOpen && surface.acceptsMapInput && campaign?.engine.state.battle==nil && campaign?.isCompleted==false}
    func canBeginMapGesture(_ point:CGPoint)->Bool {
        guard canManipulateMap else{return false}
        return (try? renderer?.classroomWorldPoint(at:point,role:.teacher)) != nil
    }
    func canvasPan(_ delta:CGPoint){
        guard canManipulateMap else{return}
        do{try renderer?.classroomPerform(.pan(delta),role:.teacher)}catch{message=error.localizedDescription}
    }
    func canvasZoom(_ scale:CGFloat,anchor:CGPoint){
        guard canManipulateMap else{return}
        do{try renderer?.classroomZoom(by:scale,anchor:anchor,role:.teacher)}catch{message=error.localizedDescription}
    }
    func canUse(_ action:PartyAction)->Bool {
        guard ready,!busy,!modalOpen else{return false}
        return (try? backend.battleTarget(for:action,selected:selectedTarget,role:.teacher)) != nil
    }
    func battle(_ action:PartyAction){
        guard !busy,!modalOpen,campaign?.engine.state.pauseReasons.isEmpty==true else{message="请先关闭后台对话框并继续战斗。";return}
        do{let target=try backend.battleTarget(for:action,selected:selectedTarget,role:.teacher);try renderer?.classroomAction(action,target:target,role:.teacher);revision += 1}catch{message=error.localizedDescription}
    }
    func focus(_ action:PartyAction?){
        guard campaign?.engine.state.pauseReasons.isEmpty==true else{return}
        if let action {guard canUse(action),let target=try? backend.battleTarget(for:action,selected:selectedTarget,role:.teacher) else{return};try? renderer?.classroomFocus(action,target:target,role:.teacher)}
        else{try? renderer?.classroomFocus(nil,target:selectedTarget,role:.teacher)}
    }
    func openTeamConsole(){
        guard !busy,!modalOpen,let presenter=presentationHost else{return}
        let screen=UIHostingController(rootView:MeadowTeamConsole(game:self,onClose:{[weak self] in self?.presentationHost?.dismiss(animated:true)}))
        screen.modalPresentationStyle = .formSheet;screen.preferredContentSize=CGSize(width:900,height:740)
        presenter.present(screen,animated:true)
    }
    func teamCommand(_ command:GameCommand){
        guard !busy,let c=campaign,c.travel==nil else{message="请先抵达道路目的地，再调整组队或仓库。";return}
        do{try c.checkpoint();try backend.apply(command,role:.teacher);renderer?.classroomRefresh();message="组队操作已保存。";revision += 1}catch{message=error.localizedDescription}
    }
    func award(){
        guard !busy,let c=campaign else{return}
        do{try backend.apply(.reward(actors:[c.selectedPlayerID],value:ResourceReward(coins:10)),role:.teacher);renderer?.classroomRefresh();message="已向选中成员发放10金币。";revision += 1}catch{message=error.localizedDescription}
    }
    func toggleBattlePause(){
        guard !busy,let c=campaign,c.engine.state.battle != nil else{return}
        do{
            let paused=c.engine.state.pauseReasons.contains(.manual)
            if !paused {try renderer?.classroomSuspend()}
            try c.engine.setPause(.manual,enabled:!paused)
            if paused {renderer?.classroomResumeRenderer()}
            revision += 1
        }catch{message=error.localizedDescription}
    }
    func editResources(){openGM()}
    func openGM(){
        guard ready,!busy,!modalOpen,campaign != nil,let presenter=presentationHost else{return}
        let screen=UIHostingController(rootView:TeacherGMConsole(game:self,onClose:{[weak self] in self?.presentationHost?.dismiss(animated:true)}))
        screen.modalPresentationStyle = .formSheet;screen.preferredContentSize=CGSize(width:980,height:780)
        presenter.present(screen,animated:true)
    }
    @discardableResult func undoTeacherAction()->Bool {
        guard !busy else{message="请等待当前动作结束。";return false}
        do{try backend.undoTeacherAction(role:.teacher);renderer?.classroomRefresh();message="已撤销最近一次玩家修改或发放。";revision += 1;return true}
        catch{message=error.localizedDescription;return false}
    }
    @discardableResult func saveGM(_ id:String,value:TeacherPlayerEdit)->Bool {
        guard !busy else{message="请等待当前动作结束。";return false}
        do{try backend.editPlayer(id,value:value,role:.teacher);renderer?.classroomRefresh();message="玩家数值与背包已保存。";revision += 1;return true}
        catch{message=error.localizedDescription;return false}
    }
    @discardableResult func grantBookPlayers(_ ids:[String],ap:Int,coins:Int)->Bool {
        guard !busy else{message="请等待当前动作结束。";return false}
        do{try backend.grantPlayers(ids,ap:ap,coins:coins,role:.teacher);renderer?.classroomRefresh();message="已向\(ids.count)名玩家发放行动点\(ap)、金币\(coins)。";revision += 1;return true}
        catch{message=error.localizedDescription;return false}
    }
    func setConnection(_ id:String,connected:Bool){if connected{externalIDs.insert(id)}else{externalIDs.remove(id)};updateMirrorDemand();if !externalConnected{frameMirror.frame=nil};revision += 1}
}

/// Only the clean game renderer moves between native hosts. Every host uses
/// the same 1280×720 bounds; window size/Retina scale never enter map layout.
struct MeadowRendererHost:UIViewControllerRepresentable {
    @ObservedObject var game:MeadowTeacherCoordinator
    func makeUIViewController(context:Context)->MeadowRendererContainer {MeadowRendererContainer()}
    func updateUIViewController(_ c:MeadowRendererContainer,context:Context){c.install(game.renderer)}
}
final class MeadowRendererContainer:UIViewController {
    private weak var installed:UIViewController?
    override func loadView(){view=UIView();view.backgroundColor = .black;view.clipsToBounds=true}
    func install(_ controller:UIViewController?){
        guard installed !== controller || controller?.parent !== self else{return}
        if let old=installed,old.parent === self {old.willMove(toParent:nil);old.view.removeFromSuperview();old.removeFromParent()}
        installed=controller
        guard let controller else{return}
        if controller.parent != nil{controller.willMove(toParent:nil);controller.view.removeFromSuperview();controller.removeFromParent()}
        // Reset BEFORE any geometry assignment; frame is undefined with an
        // active transform. Do not stretch the previous TV-sized bounds.
        controller.view.transform = .identity
        controller.view.bounds=CGRect(origin:.zero,size:ClassroomCanvas.size)
        controller.view.autoresizingMask=[]
        controller.view.setNeedsLayout();controller.view.layoutIfNeeded()
        addChild(controller);view.addSubview(controller.view);layoutCanvas(controller);controller.didMove(toParent:self)
    }
    private func layoutCanvas(_ child:UIViewController){
        let rect=ClassroomCanvas.fitted(in:view.bounds.size)
        guard rect.width>0 else{return}
        child.view.transform = .identity
        child.view.bounds=CGRect(origin:.zero,size:ClassroomCanvas.size)
        child.view.center=CGPoint(x:rect.midX,y:rect.midY)
        child.view.setNeedsLayout();child.view.layoutIfNeeded()
        let scale=rect.width/ClassroomCanvas.size.width
        child.view.transform=CGAffineTransform(scaleX:scale,y:scale)
    }
    override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();if let child=installed,child.parent === self{layoutCanvas(child)}}
}
