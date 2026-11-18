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
    /// While the GPU live mirror is on screen, the image mirror (map readback + overlay capture) is not needed at all.
    let classTimer=ClassTimerModel()
    let overlays=ClassOverlayModel()
    let grantDraft=BookGrantDraft()
    @Published var grantCapture:ClassroomGrantCapture?
    var lastGrantKey:(kind:ClassroomGrantKind,at:Date)?
    /// The teacher has the picture-book tab open (G then grants the book bar's amounts).
    var bookTabActive=false
    /// Timer panel (teacher window); the countdown itself shows on the TV. Opens over anything (pack, shop, sheets).
    func openTimer(){
        guard let presenter=presentationHost else{return}
        if presenter is ClassTimerHost {return}
        let screen=ClassTimerHost(rootView:ClassTimerPanel(timer:classTimer,onClose:{[weak self] in
            guard let top=self?.presentationHost,top is ClassTimerHost else{return};top.dismiss(animated:true)}))
        screen.modalPresentationStyle = .formSheet;screen.preferredContentSize=CGSize(width:720,height:420)
        presenter.present(screen,animated:true)
    }
    func toggleScoreboard(){withAnimation(.spring(response:0.35,dampingFraction:0.8)){overlays.scoreboard.toggle()}}
    /// Players ↔ teams; also shows the board if it was hidden.
    func toggleTeamScores(){withAnimation(.spring(response:0.35,dampingFraction:0.8)){overlays.teamScores.toggle();overlays.scoreboard=true}}
    // MARK: Quiz (anywhere)

    /// The quiz on screen (TV overlays and teacher preview), nil when none.
    @Published var quiz:LiveQuiz?
    private var quizToken=0
    private weak var quizPanel:UIViewController?
    private var quizGainBase:GameState?
    private var quizDraft:QuizAnswerDraft?
    private var quizReward:QuizManualReward?
    private var classModel:ClassQuizModel?
    private var practiceModel:PracticeModel?
    private func presentPanel(_ panel:UIViewController,size:CGSize){
        panel.modalPresentationStyle = .formSheet;panel.preferredContentSize=size
        panel.isModalInPresentation=true
        quizPanel=panel
        let show={[weak self] in self?.presentationHost?.present(panel,animated:true);return}
        if let alert=presentationHost as? UIAlertController {alert.dismiss(animated:true){show()}} else {show()}
    }
    private func closePanel(_ then:(()->Void)?=nil){
        if let panel=quizPanel,panel.presentingViewController != nil {panel.dismiss(animated:true){then?()}} else {then?()}
    }

    /// The question the launcher would start.
    func launcherCandidate(_ m:QuizLauncherModel)->Int? {
        guard let c=campaign,let player=m.player else{return nil}
        if let again=m.again,c.quizBank.indices.contains(again) {return again}
        return c.personalQuizQuestion(for:player,kind:m.kind,skip:m.skip)
    }
    /// Q: a student's next question, two keys away (Q, ⏎). 1–7 switch student, X/K/T/Y start a kind at once.
    func openQuiz(){
        guard quiz == nil,quizPanel == nil,presentationHost != nil else{return}
        let model=QuizLauncherModel();model.player=campaign?.selectedPlayerID
        let start={[weak self,weak model] in
            guard let self,let model,let player=model.player,let index=self.launcherCandidate(model) else{return}
            self.closePanel{self.startQuiz(player:player,index:index,node:nil)}
        }
        let screen=KeyHostingController(rootView:QuizLauncherPanel(game:self,model:model,onStart:start,onClose:{[weak self] in self?.closePanel()}))
        screen.onKey={[weak self,weak model] key in
            guard let self,let model else{return false}
            switch key {
            case "⏎":start()
            case "⎋":self.closePanel()
            case " ":model.skip += 1;model.again=nil
            case "z":model.again=self.campaign?.lastAskedQuestion()
            default:
                if let n=Int(key),let id=self.player(forSeat:n) {model.player=id;model.skip=0;model.again=nil;return true}
                if let kind=QuizLauncherModel.kindKeys[key] {model.kind=kind;model.skip=0;model.again=nil;if self.launcherCandidate(model) != nil {start()} else {model.note="这位同学没有可出的\(kind.title)了。"};return true}
                return false
            }
            return true
        }
        presentPanel(screen,size:CGSize(width:720,height:470))
    }
    /// One student's question: on the TV with a countdown, the answer panel for the teacher. `node`: the quiz spot,
    /// nil when called up anywhere.
    func startQuiz(player:String,index:Int,node:Int?){
        guard let c=campaign,c.quizBank.indices.contains(index),let unit=c.engine.state.units[player] else{return}
        quizToken += 1
        let q=c.quizBank[index],start=Date()
        let place=node.flatMap{n in c.engine.state.map.nodes.first{$0.id==n}?.name} ?? "课堂答题"
        withAnimation(.easeOut(duration:0.2)){quiz=LiveQuiz(token:quizToken,index:index,question:q,mode:.personal,player:player,playerName:unit.shortName,place:place,node:node,start:start)}
        let draft=QuizAnswerDraft(q),reward=QuizManualReward(q)
        quizDraft=draft;quizReward=reward
        let panel=KeyHostingController(rootView:MeadowQuizAnswerPanel(draft:draft,reward:reward,player:unit.shortName,start:start,onSubmit:{[weak self] in self?.submitQuiz()},onLater:{[weak self] in self?.cancelQuiz()}))
        panel.onKey={[weak self,weak draft] key in
            switch key {
            case "⏎":self?.submitQuiz();return true
            case "⎋":self?.cancelQuiz();return true
            default:return draft?.key(key) ?? false
            }
        }
        presentPanel(panel,size:CGSize(width:760,height:q.type == .reading ? 780:q.isShared ? 640:600))
    }
    private func cancelQuiz(){closePanel();withAnimation{quiz=nil}}
    private func submitQuiz(){
        guard let c=campaign,var live=quiz,live.mode == .personal,live.attempt==nil,let draft=quizDraft else{return}
        closePanel()
        let before=c.engine.state,r=draft.result
        let manual=live.question.isShared ? quizReward?.amount(right:draft.allRight):nil
        do{
            let attempt=try c.recordQuiz(actor:live.player,question:live.index,picks:r.picks,texts:r.texts,seconds:Date().timeIntervalSince(live.start),free:live.node==nil,manualCoins:manual)
            live.attempt=attempt;live.dropName=attempt.drop.flatMap{try? c.engine.catalog.item($0).name}
            quiz=live;quizGainBase=before
            renderer?.classroomRefresh();revision += 1
        }catch{withAnimation{quiz=nil};message=error.localizedDescription;revision += 1}
    }

    /// ⇧Q: a shared question to the whole class; the teacher picks who answered and sends rewards by hand.
    func openClassQuiz(index:Int?=nil){
        guard let c=campaign,quiz == nil,quizPanel == nil,presentationHost != nil else{return}
        guard let i=index ?? c.sharedQuizQuestion() else{message=c.quizBank.isEmpty ? "这个行程还没有题库。":"公用题都出过了（可在答题面板里“再出一次”）。";revision += 1;return}
        quizToken += 1
        let q=c.quizBank[i],start=Date()
        withAnimation(.easeOut(duration:0.2)){quiz=LiveQuiz(token:quizToken,index:i,question:q,mode:.classwide,player:"",playerName:"全班",place:"全班题",node:nil,start:start)}
        let draft=QuizAnswerDraft(q),reward=QuizManualReward(q),model=ClassQuizModel()
        quizDraft=draft;quizReward=reward;classModel=model
        let other={[weak self,weak model] in
            guard let self,let model,model.sent.isEmpty,let c=self.campaign else{return}
            let next=c.sharedQuizQuestion(skip:1) ?? i
            self.closePanel{self.quiz=nil;self.openClassQuiz(index:next)}
        }
        let panel=KeyHostingController(rootView:ClassQuizPanel(game:self,model:model,draft:draft,reward:reward,start:start,onSend:{[weak self] in self?.sendClassQuiz()},onEnd:{[weak self] in self?.endClassQuiz()},onOther:other))
        panel.onKey={[weak self,weak model,weak draft] key in
            guard let self,let model,let draft else{return false}
            switch key {
            case "⏎":self.sendClassQuiz()
            case "⎋":self.endClassQuiz()
            case " ":other()
            default:
                if let n=Int(key),n>0,let id=self.player(forSeat:n) {if model.players.contains(id){model.players.remove(id)}else{model.players.insert(id)};return true}
                return draft.key(key)
            }
            return true
        }
        presentPanel(panel,size:CGSize(width:780,height:q.type == .reading ? 820:680))
    }
    private func sendClassQuiz(){
        guard let c=campaign,let live=quiz,live.mode == .classwide,let draft=quizDraft,let model=classModel,let reward=quizReward else{return}
        guard !model.players.isEmpty,draft.answered>0 else{model.note="先选回答的同学和他们说的答案。";return}
        let r=draft.result,right=draft.allRight,coins=reward.amount(right:right)
        let order=c.engine.state.players.map(\.id)
        do{
            for id in order where model.players.contains(id) {
                let a=try c.recordQuiz(actor:id,question:live.index,picks:r.picks,texts:r.texts,seconds:Date().timeIntervalSince(live.start),free:true,manualCoins:coins,shared:true)
                model.sent.append((a.playerName,right,coins))
            }
            model.players=[];model.note=nil;draft.reset()
            renderer?.classroomRefresh();revision += 1
        }catch{model.note=error.localizedDescription}
    }
    /// Ends the class question: the TV reveals the right answer and who got it.
    private func endClassQuiz(){
        guard var live=quiz,live.mode == .classwide,let model=classModel else{closePanel();return}
        closePanel()
        let q=live.question,parts=q.parts
        let winners=model.sent.filter(\.right).map(\.name)
        live.attempt=QuizAttempt(player:"",playerName:"全班",node:-1,question:live.index,picks:parts.map{$0.answer},texts:parts.map{_ in nil},correct:parts.map{_ in true},seconds:0,limit:q.timeLimit,at:Date().timeIntervalSince1970)
        live.headline=winners.isEmpty ? (model.sent.isEmpty ? "正确答案" : "这题没人答对") : "答对：" + winners.joined(separator:"、")
        quiz=live;classModel=nil
    }

    /// K: endless flash-card practice for the selected student.
    func openPractice(){
        guard let c=campaign,quiz == nil,quizPanel == nil,presentationHost != nil else{return}
        let model=PracticeModel(player:c.selectedPlayerID)
        practiceModel=model
        let panel=KeyHostingController(rootView:PracticePanel(game:self,model:model,onClose:{[weak self] in self?.endPractice()}))
        panel.onKey={[weak self] key in
            guard let self else{return false}
            switch key {
            case "⎋":self.endPractice()
            case "0":self.practiceAnswer(nil)
            default:
                if let n=Int(key),let id=self.player(forSeat:n) {self.switchPractice(to:id);return true}
                guard key.count==1,let j=MeadowQuizCard.letters.firstIndex(of:key.uppercased()) else{return false}
                self.practiceAnswer(j)
            }
            return true
        }
        nextPracticeCard(after:nil)
        presentPanel(panel,size:CGSize(width:720,height:460))
    }
    private func nextPracticeCard(after last:Int?){
        guard let c=campaign,let model=practiceModel else{return}
        guard let i=c.practiceCard(for:model.player,after:last),let unit=c.engine.state.units[model.player] else{withAnimation{quiz=nil};return}
        quizToken += 1;model.waiting=false
        quiz=LiveQuiz(token:quizToken,index:i,question:c.quizBank[i],mode:.practice,player:model.player,playerName:unit.shortName,place:"闪卡练习",node:nil,start:Date())
    }
    func switchPractice(to id:String){
        guard let model=practiceModel,!model.waiting else{return}
        model.player=id;model.right=0;model.total=0
        nextPracticeCard(after:nil)
    }
    func practiceAnswer(_ option:Int?){
        guard let c=campaign,var live=quiz,live.mode == .practice,live.attempt==nil,let model=practiceModel,!model.waiting else{return}
        do{
            let a=try c.recordQuiz(actor:live.player,question:live.index,picks:[option],seconds:Date().timeIntervalSince(live.start),free:true,practice:true)
            model.total += 1;if a.correct.allSatisfy({$0}){model.right += 1}
            model.waiting=true
            live.attempt=a;live.hold=1.3;quiz=live
            revision += 1
        }catch{message=error.localizedDescription;revision += 1}
    }
    private func endPractice(){
        practiceModel=nil;closePanel();withAnimation{quiz=nil}
    }

    /// The card finished its reveal (called by every copy: TV and preview; the first one acts).
    func quizCardFinished(_ token:Int){
        guard let live=quiz,live.token==token,let attempt=live.attempt else{return}
        if live.mode == .practice,practiceModel != nil {nextPracticeCard(after:live.index);return}
        withAnimation(.easeIn(duration:0.2)){quiz=nil}
        if live.mode == .personal,let base=quizGainBase,attempt.coins>0 || attempt.drop != nil {
            renderer?.classroomShowGains(title:attempt.drop != nil ? "答题掉落":"答题奖励",subtitle:"\(attempt.playerName) · 答对 \(attempt.rightCount)/\(attempt.correct.count) · 用时 \(Int(attempt.seconds.rounded())) 秒",since:base)
        }
        quizGainBase=nil;quizDraft=nil;quizReward=nil
    }

    /// The answer report of the current trip (pages to look at, PDF / picture export).
    func openQuizReport(){
        guard !modalOpen,let presenter=presentationHost,let campaign else{return}
        let screen=UIHostingController(rootView:QuizReportScreen(report:campaign.quizReport,title:"课堂答题报告",itemName:{id in (try? campaign.engine.catalog.item(id).name) ?? id},onClose:{[weak self] in self?.presentationHost?.dismiss(animated:true)}))
        screen.modalPresentationStyle = .pageSheet;screen.preferredContentSize=CGSize(width:900,height:900)
        presenter.present(screen,animated:true)
    }
    func openShortcutEditor(){
        guard !modalOpen,let presenter=presentationHost else{return}
        let screen=UIHostingController(rootView:ClassroomShortcutEditor(onClose:{[weak self] in self?.presentationHost?.dismiss(animated:true)}))
        screen.modalPresentationStyle = .formSheet;screen.preferredContentSize=CGSize(width:640,height:760)
        presenter.present(screen,animated:true)
    }
    private var liveMirrors=0
    @Published var liveMirrorPreferred=MeadowLiveMirror.preferred {didSet{MeadowLiveMirror.preferred=liveMirrorPreferred}}
    func setLiveMirror(_ on:Bool){liveMirrors=max(0,liveMirrors+(on ? 1:-1));updateMirrorDemand()}
    private func updateMirrorDemand(){
        let enabled=liveMirrors==0 && ClassroomPreviewPolicy.enabled(external:externalConnected,visible:!previewObservers.isEmpty,foreground:UIApplication.shared.applicationState == .active,privateModal:modalOpen,surface:surface)
        if renderer?.classroomMirrorEnabled != enabled {renderer?.classroomMirrorEnabled=enabled}
    }
    func previewVisibility(_ id:UUID,visible:Bool){
        if visible{previewObservers.insert(id)}else{previewObservers.remove(id)}
        updateMirrorDemand()
    }
    @Published var revision=0
    @Published private(set) var externalIDs=Set<String>()
    @Published var message="先在教师后台生成地图，或继续已保存的行程。"
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
    private var wipeSince:Double?
    private func tick(){
        let now=ProcessInfo.processInfo.systemUptime,delta=min(0.5,max(0,now-lastTick));lastTick=now
        defer{publishChanges();updateMirrorDemand()}
        renderer?.classroomFinishBattleIfReady()
        // Whole party down: let the fall play for a moment, then stand everyone up on the map with 1 health.
        if let c=campaign,c.mustRetreat,!busy,surface != .book {
            if wipeSince==nil {wipeSince=now}
            if let since=wipeSince,now-since>=2.5 {
                wipeSince=nil
                do{try c.retreatAfterWipe();renderer?.classroomRefresh();renderer?.classroomShowRetreat();message="全队倒地，已撤回地图：每人以 1 点生命继续，可用行囊里的药水恢复。";revision += 1}
                catch{message=error.localizedDescription}
            }
            return
        } else {wipeSince=nil}
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
    /// The teacher-window inventory, shop or character studio that the public display copies live (nil when none is open).
    var publicPanelSource:UIView? {
        var next=privatePresenter?.presentedViewController
        while let controller=next {
            if controller is MeadowCampaignInventoryViewController || controller is MeadowShopViewController
                || controller is UIHostingController<TeacherCharacterStudio> {return controller.view}
            next=controller.presentedViewController
        }
        return nil
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
        ClassroomGlobalTools.openTimer={[weak self] in MainActor.assumeIsolated{self?.openTimer()}}
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
            controller.classroomQuizRequest={[weak self] actor,node,index in self?.startQuiz(player:actor,index:index,node:node)}
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
    /// The character studio (teacher window): looks, live preview, apply to a member, 50 character slots.
    func openCharacterStudio(){
        guard !busy,!modalOpen,let presenter=presentationHost else{return}
        let screen=UIHostingController(rootView:TeacherCharacterStudio(game:self,onClose:{[weak self] in self?.presentationHost?.dismiss(animated:true)}))
        screen.modalPresentationStyle = .formSheet;screen.preferredContentSize=CGSize(width:1000,height:760)
        presenter.present(screen,animated:true)
    }
    /// 像素人物测试（教师窗口）：用游戏内 Swift 烘焙器现场合成人物，换装后实时预览八个方向。
    func openPixelCharacterLab(){
        guard !busy,!modalOpen,let presenter=presentationHost else{return}
        let screen=UIHostingController(rootView:PixelCharacterLab(onClose:{[weak self] in self?.presentationHost?.dismiss(animated:true)}))
        screen.modalPresentationStyle = .formSheet;screen.preferredContentSize=CGSize(width:1100,height:820)
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
            else if backend.surface == .book {
                // Leave the book first so the TV always switches, even if clearing the saved book pause fails.
                try backend.project(value,role:.teacher);renderer?.classroomResumeRenderer()
                do{try campaign?.engine.setPause(.book,enabled:false)}catch{message=error.localizedDescription}
                renderer?.classroomRefresh()
            }
            try backend.project(value,role:.teacher)
            updateMirrorDemand()
            if case .encounter(let id)=value {renderer?.classroomPreviewEncounter(id)}else{renderer?.classroomPreviewEncounter(nil)}
            revision += 1
        }catch{message=error.localizedDescription}
    }
    func select(_ id:String){do{try backend.selectPlayer(id,role:.teacher);selectedTarget=id;renderer?.classroomRefresh();revision += 1}catch{message=error.localizedDescription}}
    func canTapCanvas(_ point:CGPoint)->Bool {
        guard ready,!modalOpen,surface != .book else{return false}
        if renderer?.classroomHasGainPopup==true {return true}
        guard !busy else{return false}
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
        if !modalOpen,(try? renderer?.classroomGainPopupTap(at:point,role:.teacher))==true {revision += 1;return}
        guard !busy,!modalOpen else{message="请等待当前动作结束或关闭后台对话框。";return}
        if campaign?.engine.state.battle != nil {
            if let hit=try? renderer?.classroomBattleHit(at:point,role:.teacher) {
                switch hit {case .action(let action):battle(action);case .target(let id):chooseBattleTarget(id);case .toggleMap:try? renderer?.classroomToggleBattleMap(role:.teacher);case .leave:if renderer?.classroomLeaveTap()==true {leaveBattle()} else {message="再点一次「撤离」确认离开战斗。";revision += 1}}
            }
            return
        }
        guard surface.acceptsMapInput,let c=campaign,c.engine.state.battle==nil,!c.isCompleted else{message="请先收起当前面板或返回探索地图。";return}
        if !selectingNode,(try? renderer?.classroomEdgeMarkerTap(at:point,role:.teacher))==true {revision += 1;return}
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
    /// Monster challenge switch (outside battle). Rescales every monster at once; the TV map/encounter previews refresh.
    func setDifficulty(_ level:GameDifficulty){
        guard !busy,let c=campaign else{return}
        do{
            GameDifficulty.lastChosen=level
            if try c.setDifficulty(level) != nil {renderer?.classroomRefresh();message="难度：\(level.title)（\(level.summary)）"}
            revision += 1
        }catch{message=error.localizedDescription}
    }
    func award(){
        guard !busy,let c=campaign else{return}
        do{try backend.apply(.reward(actors:[c.selectedPlayerID],value:ResourceReward(coins:10)),role:.teacher);renderer?.classroomRefresh();message="已向选中成员发放10金币。";revision += 1}catch{message=error.localizedDescription}
    }
    /// The other team on the selected player's node that this team may still duel.
    var duelOpponent:String? {campaign.flatMap{c in c.duelOpponent(actor:c.selectedPlayerID)}}
    func startDuel(){
        guard ready,!busy,!modalOpen,let c=campaign,duelOpponent != nil else{message="这里没有可以对战的队伍（每两队只能对战一次）。";return}
        renderer?.startCampaignDuel(actor:c.selectedPlayerID);message="队伍PVP开始。";revision += 1
    }
    /// GM: every pair of teams may duel again.
    func resetDuels(){
        guard !busy,let c=campaign else{return}
        do{try c.resetDuelLimits();message="已重置PVP次数：各队之间可以再对战一次。";revision += 1}catch{message=error.localizedDescription}
    }
    /// Leave the current monster fight: no winner, no drops; heroes keep their health and the monsters stay for later.
    func leaveBattle(){
        guard ready,!busy,let c=campaign,c.canLeaveBattle else{return}
        do{
            enemyWork?.cancel();enemyWork=nil;aiKey=nil
            let paused=c.engine.state.pauseReasons.contains(.manual),duel=c.engine.state.battle?.duel==true
            if paused {try c.engine.setPause(.manual,enabled:false)}
            try c.leaveBattle()
            if paused {renderer?.classroomResumeRenderer()}
            renderer?.classroomRefresh();renderer?.classroomShowLeftBattle(duel:duel)
            message="小队已撤离战斗，怪物仍留在原地，可稍后再来挑战。";revision += 1
        }catch{message=error.localizedDescription}
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
    @discardableResult func grantBookPlayers(_ ids:[String],movement:Int,coins:Int)->Bool {
        guard !busy else{message="请等待当前动作结束。";return false}
        guard !ids.isEmpty else{message="请先选择发放对象。";return false}
        guard movement>0 || coins>0 else{message="请填写移动步数或金币数量。";return false}
        do{try backend.grantSupplies(ids,movement:movement,coins:coins,role:.teacher);renderer?.classroomRefresh();message="已向\(ids.count)名玩家发放"+[movement>0 ? "移动\(movement)步":nil,coins>0 ? "金币\(coins)":nil].compactMap{$0}.joined(separator:"、")+"。";revision += 1;return true}
        catch{message=error.localizedDescription;return false}
    }
    func setConnection(_ id:String,connected:Bool){if connected{externalIDs.insert(id)}else{externalIDs.remove(id)};updateMirrorDemand();if !externalConnected{frameMirror.frame=nil};revision += 1}
}

/// Only the clean game renderer moves between native hosts. Every host uses
/// the same 1280×720 bounds; window size/Retina scale never enter map layout.
struct MeadowRendererHost:UIViewControllerRepresentable {
    @ObservedObject var game:MeadowTeacherCoordinator
    /// The teacher's own preview owns the game view only while no public screen is connected; the public
    /// screen owns it only while it is connected. Without this, a host that is about to be removed (the
    /// teacher preview when the TV / Mac public window connects, or the closing public window) could take
    /// the view back in a last update and leave it in no window at all (both screens black).
    var teacherPreview=false
    func makeUIViewController(context:Context)->MeadowRendererContainer {MeadowRendererContainer()}
    func updateUIViewController(_ c:MeadowRendererContainer,context:Context){
        if teacherPreview != game.externalConnected {c.install(game.renderer)}
    }
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

/// The timer sheet's own controller type, so a second request does not stack another one.
final class ClassTimerHost:UIHostingController<ClassTimerPanel> {}
