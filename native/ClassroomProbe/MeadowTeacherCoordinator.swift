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
    @Published private(set) var revision=0
    @Published private(set) var externalIDs=Set<String>()
    @Published private(set) var message="先在教师后台生成地图，或继续已保存的行程。"
    @Published var selectedNode:Int?
    @Published var selectedTarget="p1"
    private(set) var renderer:GameViewController?
    weak var privatePresenter:UIViewController? {didSet{renderer?.classroomPrivatePresenter=privatePresenter}}
    private var timer:Timer?
    private var installed=false
    private var enemyWork:DispatchWorkItem?
    private var lastTick=ProcessInfo.processInfo.systemUptime
    private var aiKey:String?
    private func tick(){
        let now=ProcessInfo.processInfo.systemUptime,delta=min(0.5,max(0,now-lastTick));lastTick=now;revision += 1
        renderer?.classroomFinishBattleIfReady()
        guard UIApplication.shared.applicationState == .active,ready,let c=campaign,c.engine.state.battle != nil,surface != .book,c.engine.state.pauseReasons.isEmpty else{enemyWork?.cancel();enemyWork=nil;aiKey=nil;return}
        guard !busy else{return}
        do{
            if try c.engine.advanceClock(by:delta) != nil {renderer?.classroomRefresh()}
            guard let actor=c.engine.state.battle?.current,c.engine.state.units[actor]?.kind == .monster else{enemyWork?.cancel();enemyWork=nil;aiKey=nil;return}
            let key=c.engine.state.gameID+":"+actor+":"+String(c.engine.history.count)
            guard aiKey != key else{return};enemyWork?.cancel();aiKey=key
            let task=DispatchWorkItem{[weak self,weak c] in
                guard let self,let c,self.campaign === c,!self.busy,c.engine.state.pauseReasons.isEmpty,self.surface != .book else{return}
                self.renderer?.classroomEnemyStep()
            }
            enemyWork=task;DispatchQueue.main.asyncAfter(deadline:.now()+0.65,execute:task)
        }catch{message=error.localizedDescription;enemyWork?.cancel();enemyWork=nil}
    }
    var campaign:MeadowCampaignSession? {backend.campaign}
    var surface:ClassroomPublicSurface {backend.surface}
    var busy:Bool {renderer?.classroomBusy ?? false}
    var ready:Bool {renderer?.classroomReady ?? false}
    var actions:[PartyAction] {renderer?.classroomActions ?? []}
    var externalConnected:Bool {!externalIDs.isEmpty}
    var modalOpen:Bool {privatePresenter?.presentedViewController != nil}
    init(){
        timer=Timer.scheduledTimer(withTimeInterval:0.15,repeats:true){[weak self] _ in Task{@MainActor in self?.tick()}}
    }
    func install(_ session:MeadowCampaignSession){
        do{
            enemyWork?.cancel();enemyWork=nil;aiKey=nil
            try backend.install(session,role:.teacher)
            if let old=renderer {old.willMove(toParent:nil);old.view.removeFromSuperview();old.removeFromParent()}
            let controller=GameViewController(campaign:session,classroomMode:true)
            controller.classroomPrivatePresenter=privatePresenter
            controller.classroomAdvanceTravel={ [backend] distance in try backend.advanceTravel(distance:distance,role:.teacher) }
            controller.classroomBattleModel={ [backend] in try backend.battleModel(role:.teacher) }
            controller.classroomStatus={ [weak self] text in self?.message=text;self?.revision += 1 }
            controller.classroomInventoryChanged={ [weak self] id in self?.project(id.map{.inventory($0)} ?? .exploration) }
            controller.classroomReload={ [weak self,weak session] in if let session{self?.install(session)} }
            renderer=controller;installed=true;selectedNode=nil;selectedTarget=session.selectedPlayerID
            message="地图已由后台准备，投放端只显示游戏。";revision += 1
        }catch{message=error.localizedDescription}
    }
    func restore(){
        guard !busy,campaign?.engine.state.battle==nil else{message="请先结束当前战斗。";return}
        do{let store=MeadowMapSettingsViewController.campaignStore();guard let save=try store.read() else{message="还没有已保存的行程。";return};install(try MeadowCampaignSession(save:save,persist:store.write))}
        catch{message="存档读取失败，原文件保留："+error.localizedDescription}
    }
    func settings(){
        guard !busy,campaign?.engine.state.battle==nil,let presenter=privatePresenter else{message="请先结束战斗，再调整随机地图。";return}
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
    func move(x:Double,y:Double){
        guard ready,!busy,let c=campaign else{return}
        do{try backend.travel(to:.init(x*1280,y*c.snapshot.layout.coordinateHeight),role:.teacher);renderer?.classroomPreviewEncounter(nil);renderer?.classroomRefresh();message="已指定道路目标，移动条按实际距离扣除。"
            if let node=c.engine.state.map.nodes.min(by:{hypot($0.x-x,$0.y-y)<hypot($1.x-x,$1.y-y)}),hypot(node.x-x,node.y-y)<0.06,(node.kind == .combat || node.kind == .boss){selectedNode=node.id;project(.encounter(node.id))}
            revision += 1}
        catch{message=error.localizedDescription}
    }
    func battle(_ action:PartyAction){
        do{try renderer?.classroomAction(action,target:selectedTarget,role:.teacher);revision += 1}catch{message=error.localizedDescription}
    }
    func focus(_ action:PartyAction?){try? renderer?.classroomFocus(action,target:selectedTarget,role:.teacher)}
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
    func editResources(){
        guard !busy,let c=campaign,let unit=c.engine.state.units[c.selectedPlayerID],let presenter=privatePresenter else{return}
        let sheet=UIAlertController(title:"教师调整 · "+unit.name,message:"仅后台可修改，投放端只显示保存后的状态。\n生命 / 护盾 / 当前行动点 / 金币 / 积分",preferredStyle:.alert)
        for (label,value) in [("生命",unit.health),("护盾",unit.shield),("当前行动点",unit.ap),("金币",unit.coins),("积分",unit.score)] {sheet.addTextField{$0.placeholder=label;$0.accessibilityLabel=label;$0.text=String(value);$0.keyboardType = .numberPad}}
        sheet.addAction(UIAlertAction(title:"取消",style:.cancel))
        sheet.addAction(UIAlertAction(title:"保存",style:.default){[weak self,weak sheet] _ in
            guard let self,let values=sheet?.textFields?.compactMap({Int($0.text ?? "")}),values.count==5 else{return}
            do{try self.backend.apply(.editResources(unit:unit.id,value:ResourcePatch(health:values[0],shield:values[1],ap:values[2],coins:values[3],score:values[4])),role:.teacher);self.renderer?.classroomRefresh();self.revision += 1}catch{self.message=error.localizedDescription}
        });presenter.present(sheet,animated:true)
    }
    func setConnection(_ id:String,connected:Bool){if connected{externalIDs.insert(id)}else{externalIDs.remove(id)};revision += 1}
}

/// UIKit containment moves the one real renderer between local preview and the
/// external output. No screenshot mirroring and no second engine/AI/Metal map.
struct MeadowRendererHost:UIViewControllerRepresentable {
    @ObservedObject var game:MeadowTeacherCoordinator
    func makeUIViewController(context:Context)->MeadowRendererContainer {MeadowRendererContainer()}
    func updateUIViewController(_ c:MeadowRendererContainer,context:Context){c.install(game.renderer)}
}
final class MeadowRendererContainer:UIViewController {
    private weak var installed:UIViewController?
    override func loadView(){view=UIView();view.backgroundColor = .black}
    func install(_ controller:UIViewController?){
        guard installed !== controller || controller?.parent !== self else{return}
        if let old=installed,old.parent === self {old.willMove(toParent:nil);old.view.removeFromSuperview();old.removeFromParent()}
        installed=controller
        guard let controller else{return}
        if controller.parent != nil{controller.willMove(toParent:nil);controller.view.removeFromSuperview();controller.removeFromParent()}
        addChild(controller);view.addSubview(controller.view);controller.view.frame=view.bounds;controller.view.autoresizingMask=[];controller.didMove(toParent:self)
    }
    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews();guard let child=installed,child.parent === self,view.bounds.width>0,view.bounds.height>0 else{return}
        let factor=max(1,1280/view.bounds.width,720/view.bounds.height)
        child.view.transform = .identity;child.view.bounds=CGRect(origin:.zero,size:CGSize(width:view.bounds.width*factor,height:view.bounds.height*factor));child.view.center=CGPoint(x:view.bounds.midX,y:view.bounds.midY)
        child.view.transform=CGAffineTransform(scaleX:1/factor,y:1/factor)
    }
}
