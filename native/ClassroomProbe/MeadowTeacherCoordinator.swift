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
    @Published var bookTabActive=false
    /// Timer panel (teacher window); the countdown itself shows on the TV. Opens over anything (pack, shop, sheets).
    func openTimer(){
        guard let presenter=presentationHost else{return}
        if presenter is ClassTimerHost {return}
        let screen=ClassTimerHost(rootView:ClassTimerPanel(timer:classTimer,onClose:{[weak self] in
            guard let top=self?.presentationHost,top is ClassTimerHost else{return};top.dismiss(animated:true)}))
        screen.modalPresentationStyle = .formSheet;screen.preferredContentSize=CGSize(width:720,height:420)
        presenter.present(screen,animated:true)
    }
    /// Laser pointer over the teacher's preview, shown on the TV (L).
    let laser=LaserPointer()
    func toggleLaser(){laser.on.toggle();syncPanelLaser();message=laser.on ? "激光笔：在预览画面、行囊或商店上移动指针（再按 L 关闭）":"激光笔已关闭";revision += 1}
    /// Keeps the laser catcher on the open pack / shop while the laser is on (and only then).
    func syncPanelLaser(){
        let source=publicPanelSource
        if laser.on,let source,!source.subviews.contains(where:{$0 is LaserPanelCatcher}) {
            let catcher=LaserPanelCatcher(laser:laser);catcher.frame=source.bounds;source.addSubview(catcher)
        }
        var next=privatePresenter?.presentedViewController
        while let controller=next {
            if controller.view !== source || !laser.on {controller.view.subviews.filter{$0 is LaserPanelCatcher}.forEach{$0.removeFromSuperview()}}
            next=controller.presentedViewController
        }
    }
    func toggleScoreboard(){withAnimation(.spring(response:0.35,dampingFraction:0.8)){overlays.scoreboard.toggle()}}
    /// Players ↔ teams; also shows the board if it was hidden.
    func toggleTeamScores(){withAnimation(.spring(response:0.35,dampingFraction:0.8)){overlays.teamScores.toggle();overlays.scoreboard=true}}
    // MARK: Quiz (anywhere)

    /// The quiz on screen (TV overlays and teacher preview), nil when none.
    @Published var quiz:LiveQuiz? {didSet{if quiz?.token != oldValue?.token || quiz == nil {miniGame?.flush(quiz:quiz?.token)}}}
    /// A classroom mini-game on the TV (boss, camp, race, memory, arena), driven by the answers sent.
    @Published var miniGame:MiniGameModel?
    private var quizToken=0
    private weak var quizPanel:UIViewController?
    private var quizGainBase:GameState?
    private var quizDraft:QuizAnswerDraft?
    private var quizReward:QuizManualReward?
    private var classModel:ClassQuizModel?
    /// The class question list while it is docked (it gives way to the next question).
    private weak var classPicker:UIViewController?
    /// After a shared question: the students nobody picked, offered to put in their mistakes. Shown in the
    /// question list / flash-card panel (not a dialog), so the next question can be picked meanwhile.
    @Published var skippedPrompt:SkippedPrompt?
    struct SkippedPrompt:Equatable {
        let question:Int
        let ids:[String]
        let names:String
        let practice:Bool
    }
    /// The flash card just made from the notes and put to the class (front, course): Esc on it raises its difficulty.
    /// The trip-bank question last called up from the notes (double-click): if nobody gets it right it goes up a star.
    var noteCardIndex:Int?
    private var practiceModel:PracticeModel?
    /// The answer panel of the question on screen, docked beside the teacher's preview (not a sheet over it), so
    /// the preview, the map and the laser pointer stay usable while a question is up.
    /// What the dock shows; each place that shows it builds its own hosting controller from it (one controller
    /// moved between places went blank).
    @Published var dockContent:DockContent?
    /// Kept strongly: the dock only holds a copy of its view, so nothing else keeps the panel (and closing it
    /// must still find it).
    private var dockPanel:UIViewController?
    func presentPanel(_ panel:UIViewController,size:CGSize,dock:Bool=false){
        if dock,let content=(panel as? DockablePanel)?.dockContent() {
            quizPanel=panel;dockPanel=panel
            withAnimation(.easeOut(duration:0.2)){dockContent=content}
            return
        }
        panel.modalPresentationStyle = .formSheet;panel.preferredContentSize=size
        panel.isModalInPresentation=true
        quizPanel=panel
        let show={[weak self] in self?.presentationHost?.present(panel,animated:true);return}
        if let alert=presentationHost as? UIAlertController {alert.dismiss(animated:true){show()}} else {show()}
    }
    func closePanel(_ then:(()->Void)?=nil){
        // Forget the panel first: whatever opens next (the launcher again) must not think one is still up.
        let panel=quizPanel;quizPanel=nil
        if let panel,panel===dockPanel {
            dockPanel=nil
            withAnimation(.easeIn(duration:0.15)){dockContent=nil}
            DispatchQueue.main.async{then?()}
            return
        }
        if let panel,panel.presentingViewController != nil {panel.dismiss(animated:true){then?()}} else {then?()}
    }

    /// The open trip deals from the current course (its questions are added to the trip if needed).
    func applyQuizCourse(){
        guard let c=campaign else{return}
        let library=QuizLibrary.shared
        do{try c.useQuizCourse(library.active,questions:library.activeQuestions)}
        catch{message="题库没能用到当前行程："+error.localizedDescription}
        revision += 1
    }
    func selectQuizCourse(_ name:String){
        QuizLibrary.shared.select(name);applyQuizCourse()
        message="当前课程：\(name)";revision += 1
    }
    /// Top bar "题库". From the quiz launcher (`back`) it replaces it and returns to it when done.
    func openQuizBank(back:Bool=false){
        let show={[weak self] in
            guard let self else{return}
            let done={[weak self] in self?.closePanel{if back {self?.openQuiz()}};return}
            let screen=KeyHostingController(rootView:QuizBankPanel(game:self,onClose:done))
            screen.onKey={key in if key=="⎋" {done();return true};return false}
            self.presentPanel(screen,size:CGSize(width:760,height:540))
        }
        if quizPanel != nil {closePanel(show)} else if presentationHost != nil {show()}
    }
    /// Anything quiz-related on screen (a question, a challenge, practice or its panel).
    var quizActive:Bool {quiz != nil || challenge != nil || dockContent != nil}
    /// Top bar "结束答题": ends whatever is going on at once (nothing more is recorded; what was already sent stays).
    func abortQuiz(){
        challengeTimer?.invalidate();challengeTimer=nil
        practiceModel=nil;classModel=nil;quizDraft=nil;quizReward=nil;quizGainBase=nil;skippedPrompt=nil
        closePanel()
        dockPanel=nil;dockContent=nil
        withAnimation(.easeIn(duration:0.15)){quiz=nil;challenge=nil}
        renderer?.classroomRefresh();revision += 1
    }
    /// Q: a timed challenge for one student (setup: who, how questions are drawn, how long).
    func openQuiz(){
        guard quiz == nil,challenge == nil,quizPanel == nil,presentationHost != nil else{return}
        let model=QuizLauncherModel();model.player=campaign?.selectedPlayerID
        let start={[weak self,weak model] in
            guard let self,let model,let player=model.player,let c=self.campaign else{return}
            guard !c.courseIndices.isEmpty else{model.note="当前课程没有题，先在题库里选课或导入。";return}
            let seconds=model.seconds
            self.closePanel{self.startChallenge(player:player,seconds:seconds)}
        }
        let screen=KeyHostingController(rootView:QuizLauncherPanel(game:self,model:model,onStart:start,onClose:{[weak self] in self?.closePanel()}))
        screen.onKey={[weak self,weak model] key in
            guard let self,let model else{return false}
            switch key {
            case "⏎":start()
            case "⎋":self.closePanel()
            case "+","=":model.seconds=min(3600,model.seconds+30)
            case "-":model.seconds=max(10,model.seconds-30)
            default:
                if let n=Int(key),let id=self.player(forSeat:n) {model.player=id;return true}
                return false
            }
            return true
        }
        presentPanel(screen,size:CGSize(width:760,height:470))
    }

    // MARK: Timed challenge
    @Published var challenge:ChallengeModel?
    private var challengeTimer:Timer?
    /// The latest challenge's answers, so a challenge given to the wrong student can be taken back or moved to the
    /// right one in one go (while it runs, and after it ended, until anything else is done in the trip).
    struct ChallengeRun {
        let mark:QuizRunMark
        var ids:[String]
        var player:String
        var name:String
    }
    @Published private(set) var lastChallenge:ChallengeRun?
    /// The last challenge can still be undone or moved as a whole.
    var challengeRunUndoable:Bool {
        guard let run=lastChallenge,let c=campaign else{return false}
        return c.canUndoQuizRun(run.mark,ids:run.ids)
    }
    func startChallenge(player:String,seconds:Int){
        guard let c=campaign,let unit=c.engine.state.units[player] else{return}
        lastChallenge=ChallengeRun(mark:c.quizRunMark(),ids:[],player:player,name:unit.shortName)
        let model=ChallengeModel(player:player,name:unit.shortName,seconds:seconds)
        withAnimation{challenge=model}
        showChallengePanel()
        challengeTimer?.invalidate()
        let t=Timer(timeInterval:0.25,repeats:true){[weak self] _ in MainActor.assumeIsolated{self?.challengeTick()}}
        RunLoop.main.add(t,forMode:.common);challengeTimer=t
        challengeNext()
    }
    /// One panel for the whole challenge; its content follows the phase (choosing / marking / result).
    private func showChallengePanel(){
        guard let model=challenge else{return}
        let screen=KeyHostingController(rootView:ChallengePanel(game:self,model:model,onAsk:{[weak self] i in self?.challengeAsk(i)},onNext:{[weak self] in self?.challengeNext()},
                                                                onSkip:{[weak self] in self?.challengeSkip()},onSubmit:{[weak self] in self?.challengeSubmit()},onEnd:{[weak self] in self?.endChallenge()}))
        screen.onKey={[weak self] key in
            guard let self,let model=self.challenge else{return false}
            let settings=QuizDrawSettings.shared
            switch (key,model.phase) {
            case ("⎋",_):self.endChallenge();return true
            case ("⏎",.question):self.challengeSubmit();return true
            case (" ",.question):self.challengeSkip();return true
            case ("⏎",.picking):self.challengeNext();return true
            case ("r",.picking):settings.mode = .random;self.challengeNext();return true
            case (_,.picking):
                if let d=Int(key),(1...3).contains(d){settings.difficulty=d;settings.mode = .difficulty;self.challengeNext();return true}
                return false
            case (_,.question):return model.draft?.key(key) ?? false
            default:return false
            }
        }
        presentPanel(screen,size:CGSize(width:780,height:640),dock:true)
    }
    /// The question as it is shown: options shuffled when it was asked before (choice and fill-in).
    private func presented(_ index:Int)->(question:QuizQuestion,shuffle:QuizShuffle?) {
        guard let c=campaign else{return(QuizQuestion(prompt:"",options:[],answer:0),nil)}
        let q=c.quizBank[index]
        guard c.quizAskedBefore(index),q.type == .choice || q.type == .fill else{return(q,nil)}
        let s=q.shuffledOptions()
        return(s.question,s)
    }
    /// Picks on the shown card → the bank's order (recorded); and the stored attempt → the shown card (its reveal).
    private func recorded(_ picks:[Int?],_ live:LiveQuiz)->[Int?] {live.shuffle?.original(picks) ?? picks}
    private func shown(_ attempt:QuizAttempt,_ live:LiveQuiz)->QuizAttempt {
        guard let s=live.shuffle else{return attempt}
        var a=attempt;a.picks=s.shown(a.picks);return a
    }
    /// The next question the chosen way: drawn (this student's unanswered ones first), or the list for 老师点选.
    private func challengeNext(excluding:Set<Int>=[]){
        guard let c=campaign,let model=challenge,model.phase != .finished,model.remaining>0 else{return}
        model.draft=nil
        model.pause()
        guard let draw=QuizDrawSettings.shared.draw else{model.phase = .picking;model.note=nil;return}
        guard let i=c.drawQuestion(draw,for:model.player,excluding:excluding) else{
            model.phase = .picking;model.note="这一档没有题，换个出题方式或难度。";return
        }
        challengeAsk(i)
    }
    private func challengeAsk(_ i:Int){
        guard let c=campaign,let model=challenge,model.phase != .finished,model.remaining>0,c.quizBank.indices.contains(i) else{return}
        model.note=nil;model.phase = .question;model.questionStart=Date()
        quizToken += 1
        let shown=presented(i)
        model.pause()
        quiz=LiveQuiz(token:quizToken,index:i,question:shown.question,mode:.challenge,player:model.player,playerName:model.name,place:"个人挑战",node:nil,start:Date(),
                      countdown:QuizCountdown{[weak model] in model?.remaining ?? 0},shuffle:shown.shuffle)
        // The clock runs from when the card is in until the answer is picked.
        let token=quizToken
        DispatchQueue.main.asyncAfter(deadline:.now()+MeadowQuizCard.entrance){[weak self,weak model] in
            guard let self,let model,self.challenge === model,model.phase == .question,self.quiz?.token==token,self.quiz?.attempt==nil else{return}
            model.resume()
        }
        let draft=QuizAnswerDraft(shown.question)
        // The answer is picked: reveal and pay straight away (no separate submit).
        draft.onComplete={[weak self] in self?.challengeSubmit()}
        model.draft=draft
    }
    /// 换一题 / 重新选题: the question on screen is dropped without a record.
    private func challengeSkip(){
        // While an answer shows: on to the next question now.
        if challenge != nil,quiz?.mode == .challenge,quiz?.attempt != nil {skipQuizReveal();return}
        guard let model=challenge,model.phase == .question,let live=quiz,live.attempt==nil else{return}
        model.pause();quiz=nil
        if QuizDrawSettings.shared.mode == .manual {model.phase = .picking;model.draft=nil} else {challengeNext(excluding:[live.index])}
    }
    /// 老师点选 chosen in the middle of a challenge: the question list right away. A question not answered yet is taken
    /// back (nothing recorded); an answer being revealed keeps playing while the list is up.
    func challengeShowList(){
        guard let model=challenge,model.phase == .question else{return}
        if let live=quiz,live.mode == .challenge,live.attempt==nil {model.pause();quiz=nil}
        model.phase = .picking;model.draft=nil;model.note=nil
    }
    private func challengeSubmit(){
        guard let c=campaign,let model=challenge,model.phase == .question,var live=quiz,live.attempt==nil,let draft=model.draft else{return}
        // Answer picked: the clock stops through the reveal and until the next question is up.
        model.pause()
        let r=draft.result
        do{
            let opID=UUID().uuidString
            let a=try c.recordQuiz(actor:model.player,question:live.index,picks:recorded(r.picks,live),texts:r.texts,seconds:Date().timeIntervalSince(model.questionStart),free:true,challenge:true,askedAt:live.start,id:opID)
            lastChallenge?.ids.append(opID)
            model.answered += 1;if a.rightCount==a.correct.count {model.right += 1}
            model.coins += a.coins;model.score += a.score
            live.attempt=shown(a,live);live.hold=1.6;live.dropName=a.drop.flatMap{try? c.engine.catalog.item($0).name}
            quiz=live
            // 老师点选: the list is back at once, so the next question can be picked while this answer shows.
            if QuizDrawSettings.shared.mode == .manual {model.phase = .picking;model.draft=nil}
            renderer?.classroomRefresh();revision += 1
        }catch{model.note=error.localizedDescription}
    }
    /// 撤销本次挑战: every answer of the last challenge comes back off (records, coins, points, steps); a running
    /// challenge ends.
    func undoChallengeRun(){
        guard let run=lastChallenge,let c=campaign else{return}
        guard !run.ids.isEmpty else{message="这次挑战还没有记录。";revision += 1;return}
        do{
            try c.undoQuizRun(run.mark,ids:run.ids)
            lastChallenge=nil
            if challenge != nil {abortQuiz()}
            renderer?.classroomRefresh()
            message="已撤销 \(run.name) 的挑战（\(run.ids.count) 条作答和奖励）";revision += 1
        }catch{message=error.localizedDescription;revision += 1}
    }
    /// 改给…: the last challenge's answers go to `player` instead (their rewards follow); a running challenge
    /// goes on for them.
    func moveChallengeRun(to player:String){
        guard var run=lastChallenge,let c=campaign,player != run.player,let unit=c.engine.state.units[player] else{return}
        do{
            if !run.ids.isEmpty {run.ids=try c.moveQuizRun(run.mark,ids:run.ids,to:player)}
            run.player=player;run.name=unit.shortName;lastChallenge=run
            if let model=challenge {
                model.player=player;model.name=unit.shortName
                // The card on screen shows the new name (a fresh card; the clock goes on if a question is waiting).
                if var live=quiz,live.mode == .challenge {
                    quizToken += 1;live.token=quizToken;live.player=player;live.playerName=unit.shortName;quiz=live
                    if live.attempt == nil,model.phase == .question {model.resume()}
                }
            }
            renderer?.classroomRefresh()
            message="已改给 \(unit.shortName)（\(run.ids.count) 条作答和奖励一起转过去）";revision += 1
        }catch{message=error.localizedDescription;revision += 1}
    }
    private func challengeTick(){
        guard let model=challenge,model.phase != .finished,model.running,model.remaining<=0 else{return}
        finishChallenge()
    }
    /// Time is up (or the teacher ended it): a question in progress does not count; the result shows on the TV.
    private func finishChallenge(){
        guard let model=challenge,model.phase != .finished else{return}
        model.pause()
        challengeTimer?.invalidate();challengeTimer=nil
        if quiz?.attempt == nil {withAnimation{quiz=nil}}
        model.phase = .finished;model.draft=nil
        // The result stays 2 seconds on the TV, then everything closes by itself.
        DispatchQueue.main.asyncAfter(deadline:.now()+2){[weak self,weak model] in
            guard let self,let model,self.challenge === model,model.phase == .finished else{return}
            self.endChallenge()
        }
    }
    private func endChallenge(){
        guard let model=challenge else{closePanel();return}
        if model.phase != .finished {finishChallenge();return}
        closePanel()
        withAnimation{challenge=nil;quiz=nil}
    }

    /// One student's question: on the TV with a countdown, the answer panel for the teacher. `node`: the quiz spot,
    /// nil when called up anywhere.
    func startQuiz(player:String,index:Int,node:Int?){
        guard let c=campaign,c.quizBank.indices.contains(index),let unit=c.engine.state.units[player] else{return}
        quizToken += 1
        let shown=presented(index),q=shown.question,start=Date()
        let place=node.flatMap{n in c.engine.state.map.nodes.first{$0.id==n}?.name} ?? "课堂答题"
        withAnimation(.easeOut(duration:0.2)){quiz=LiveQuiz(token:quizToken,index:index,question:q,mode:.personal,player:player,playerName:unit.shortName,place:place,node:node,start:start,shuffle:shown.shuffle)}
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
        presentPanel(panel,size:CGSize(width:760,height:q.type == .reading ? 780:600),dock:true)
    }
    private func cancelQuiz(){closePanel();withAnimation{quiz=nil}}
    private func submitQuiz(){
        guard let c=campaign,var live=quiz,live.mode == .personal,live.attempt==nil,let draft=quizDraft else{return}
        closePanel()
        let before=c.engine.state,r=draft.result
        do{
            let attempt=try c.recordQuiz(actor:live.player,question:live.index,picks:recorded(r.picks,live),texts:r.texts,seconds:Date().timeIntervalSince(live.start),free:live.node==nil,askedAt:live.start)
            live.attempt=shown(attempt,live);live.dropName=attempt.drop.flatMap{try? c.engine.catalog.item($0).name}
            quiz=live;quizGainBase=before
            feedMiniGame(question:live.index,answers:[MiniGameAnswer(player:live.player,right:attempt.rightCount==attempt.correct.count)])
            renderer?.classroomRefresh();revision += 1
        }catch{withAnimation{quiz=nil};message=error.localizedDescription;revision += 1}
    }

    /// ⇧Q: a question to the whole class (drawn the teacher's way, or picked from the list); the teacher picks who
    /// answered and sends rewards by hand.
    func openClassQuiz(index:Int?=nil,excluding:Set<Int>=[],englishFront:Bool=false){
        // No trip open yet: the launcher offers to continue the last one.
        if campaign == nil {openQuiz();return}
        // The class question list is up (between questions): it gives way to this question (a double-click in the
        // notes, a pick, a draw).
        if let picker=classPicker,quizPanel===picker {
            classPicker=nil
            closePanel{[weak self] in self?.openClassQuiz(index:index,excluding:excluding,englishFront:englishFront)};return
        }
        // The last class question's answer may still be showing: the next one takes over.
        if quiz?.mode == .classwide,quiz?.attempt != nil {quiz=nil}
        guard let c=campaign,quiz == nil,quizPanel == nil,presentationHost != nil else{return}
        guard !c.courseIndices.isEmpty else{message="当前课程没有题，先在题库里选课或导入。";revision += 1;return}
        if index == nil,QuizDrawSettings.shared.draw == nil {openClassPicker();return}
        guard let i=index ?? QuizDrawSettings.shared.draw.flatMap({c.drawQuestion($0,for:nil,excluding:excluding)}) else{
            message="这一档没有题，换个出题方式或难度。";revision += 1;openClassPicker();return
        }
        quizToken += 1
        let shown=presented(i),start=Date()
        var q=shown.question
        // From the notes a flash card always shows its English side (a 鼻子 → nose card asks nose → 鼻子); the answer
        // is still recorded on the same card.
        if englishFront,q.type == .flashcard,q.prompt.range(of:"[A-Za-z]",options:.regularExpression)==nil,let w=QuizReport.word(q,part:0),let meaning=w.meaning {
            q.prompt=w.word;q.items=[QuizItem(options:[meaning],answer:0)]
        }
        withAnimation(.easeOut(duration:0.2)){quiz=LiveQuiz(token:quizToken,index:i,question:q,mode:.classwide,player:"",playerName:"全班",place:"全班题",node:nil,start:start,shuffle:shown.shuffle)}
        let draft=QuizAnswerDraft(q),reward=QuizManualReward(q),model=ClassQuizModel()
        quizDraft=draft;quizReward=reward;classModel=model
        let other={[weak self,weak model] in
            guard let self,let model,model.sent.isEmpty else{return}
            self.classModel=nil;self.quizDraft=nil;self.quizReward=nil
            self.closePanel{self.quiz=nil;self.openClassQuiz(excluding:[i])}
        }
        // Only the question this note card was asked with counts; any other question clears it.
        if let n=noteCardIndex,n != i {noteCardIndex=nil}
        let panel=KeyHostingController(rootView:ClassQuizPanel(game:self,model:model,draft:draft,reward:reward,start:start,onSend:{[weak self] in self?.sendClassQuiz()},onEnd:{[weak self] in self?.endClassQuiz(nobodyAnswered:true)},onOther:other))
        panel.onKey={[weak self,weak model,weak draft] key in
            guard let self,let model,let draft else{return false}
            switch key {
            case "⏎":self.sendClassQuiz()
            case "⎋":self.endClassQuiz(nobodyAnswered:true)
            case " ":other()
            default:
                if let n=Int(key),n>0,let id=self.player(forSeat:n) {if model.players.contains(id){model.players.remove(id)}else{model.players.insert(id)};return true}
                // One answer per student: the picked students take the letter (0 = 不会), ⌫ clears theirs.
                if ClassQuizModel.perStudent(draft.question) {
                    let letters=Array("abcdefgh").map(String.init)
                    if let k=letters.firstIndex(of:key),k<draft.question.parts[0].options.count {model.assign(k);return true}
                    if key=="0" {model.assign(-1);return true}
                    if key=="⌫" {model.clearPicked();return true}
                    return false
                }
                return draft.key(key)
            }
            return true
        }
        presentPanel(panel,size:CGSize(width:780,height:q.type == .reading ? 820:680),dock:true)
    }
    /// 老师点选 (or a draw that found nothing): the class question list in the dock.
    private func openClassPicker(){
        guard presentationHost != nil else{return}
        let draw={[weak self] in
            guard let self,QuizDrawSettings.shared.draw != nil else{return}
            self.openClassQuiz()
        }
        let panel=KeyHostingController(rootView:ClassQuizPickPanel(game:self,onPick:{[weak self] i in self?.openClassQuiz(index:i)},onDraw:draw,onClose:{[weak self] in self?.skippedPrompt=nil;self?.closePanel()}))
        classPicker=panel
        panel.onKey={[weak self] key in
            switch key {
            case "⎋":self?.closePanel();return true
            case "⏎":draw();return true
            default:return false
            }
        }
        presentPanel(panel,size:CGSize(width:780,height:680),dock:true)
    }
    private func sendClassQuiz(){
        guard let c=campaign,let live=quiz,live.mode == .classwide,let draft=quizDraft,let model=classModel,let reward=quizReward else{return}
        if ClassQuizModel.perStudent(draft.question) {sendClassChoices(c,live:live,model:model,reward:reward);return}
        guard !model.players.isEmpty,draft.answered>0 else{model.note="先选回答的同学和他们说的答案。";return}
        let r=draft.result,right=draft.allRight,participation=reward.participationCoins
        let order=c.engine.state.players.map(\.id)
        do{
            for id in order where model.players.contains(id) {
                let a=try c.recordQuiz(actor:id,question:live.index,picks:recorded(r.picks,live),texts:r.texts,seconds:Date().timeIntervalSince(live.start),free:true,participation:participation,shared:true,askedAt:live.start)
                model.sent.append((a.playerName,right,a.coins))
            }
            let answered=model.players
            feedMiniGame(question:live.index,answers:order.filter{answered.contains($0)}.map{MiniGameAnswer(player:$0,right:right)})
            model.players=[];model.note=nil
            renderer?.classroomRefresh();revision += 1
            // Sent: the TV reveals the answer as the coins go out.
            endClassQuiz()
            askRecordSkipped(question:live.index,answered:answered,practice:false)
        }catch{model.note=error.localizedDescription}
    }
    /// One answer per student: each is marked and paid on what they said (a wrong answer gets the participation
    /// prize, if any).
    private func sendClassChoices(_ c:MeadowCampaignSession,live:LiveQuiz,model:ClassQuizModel,reward:QuizManualReward){
        guard !model.choices.isEmpty else{model.note="先记下每人的答案（点选项，或 1–7 选人再按字母）。";return}
        do{
            var answers:[MiniGameAnswer]=[]
            for id in c.engine.state.players.map(\.id) {
                guard let choice=model.choices[id] else{continue}
                let a=try c.recordQuiz(actor:id,question:live.index,picks:recorded([choice<0 ? nil:choice],live),seconds:Date().timeIntervalSince(live.start),
                                       free:true,participation:reward.participationCoins,shared:true,askedAt:live.start)
                model.sent.append((a.playerName,a.correct.allSatisfy{$0},a.coins))
                answers.append(MiniGameAnswer(player:id,right:a.correct.allSatisfy{$0}))
            }
            feedMiniGame(question:live.index,answers:answers)
            let answered=Set(model.choices.keys)
            model.players=[];model.note=nil
            renderer?.classroomRefresh();revision += 1
            endClassQuiz()
            askRecordSkipped(question:live.index,answered:answered,practice:false)
        }catch{model.note=error.localizedDescription}
    }
    /// After a shared question: the students who were not picked can have it put in their mistakes (recorded as
    /// 不会 / 答错, no reward), so the report shows it for them too.
    private func askRecordSkipped(question index:Int,answered:Set<String>,practice:Bool){
        guard let c=campaign else{return}
        let others=c.engine.state.players.filter{!answered.contains($0.id) && !$0.host}
        guard !others.isEmpty else{skippedPrompt=nil;return}
        skippedPrompt=SkippedPrompt(question:index,ids:others.map(\.id),names:others.map(\.shortName).joined(separator:"、"),practice:practice)
    }
    /// 记入错题 / 不记 for the students nobody picked on the last shared question.
    func answerSkippedPrompt(record:Bool){
        guard let prompt=skippedPrompt else{return}
        skippedPrompt=nil
        guard record,let c=campaign,c.quizBank.indices.contains(prompt.question) else{return}
        let blanks=Array(repeating:Optional<Int>.none,count:c.quizBank[prompt.question].parts.count)
        do{
            for id in prompt.ids {try c.recordQuiz(actor:id,question:prompt.question,picks:blanks,seconds:0,free:true,shared:true,practice:prompt.practice,skipped:true)}
            message="已记入 \(prompt.names) 的错题";revision += 1
        }catch{message=error.localizedDescription;revision += 1}
    }
    /// Ends the class question: the TV reveals the right answer and who got it.
    /// `nobodyAnswered`: Esc / 只揭晓 with nothing sent. On a card just made from the notes that means it was too
    /// hard for now: it goes up one star (at most ★★★) in its course.
    private func endClassQuiz(nobodyAnswered:Bool=false){
        let fromNotes=noteCardIndex;noteCardIndex=nil
        guard var live=quiz,live.mode == .classwide,let model=classModel else{closePanel();return}
        if nobodyAnswered,model.sent.isEmpty {feedMiniGame(question:live.index,answers:[])}
        // The class stays in question mode: the list (or the draw) comes back for the next question while the
        // answer shows; Esc there ends.
        closePanel{[weak self] in self?.openClassPicker()}
        // A card from the notes that nobody got right (nobody answered, or every answer sent was wrong) is harder
        // than thought: one star up, at most ★★ (★★★ is for sentence questions). Answers already given stay with it.
        if fromNotes==live.index,!model.sent.contains(where:\.right),let c=campaign,c.quizBank.indices.contains(live.index),c.quizBank[live.index].type == .flashcard {
            let card=c.quizBank[live.index],level=card.level
            if level<2 {
                var harder=card;harder.difficulty=level+1
                replaceQuestion(card,with:harder)
                message="没人答对：\(live.question.prompt) 难度升为"+String(repeating:"★",count:level+1)
            }else{message="没人答对：\(live.question.prompt) 已是单词卡最高难度★★"}
        }
        let q=live.question,parts=q.parts
        let winners=model.sent.filter(\.right).map(\.name)
        live.attempt=QuizAttempt(player:"",playerName:"全班",node:-1,question:live.index,picks:parts.map{$0.answer},texts:parts.map{_ in nil},correct:parts.map{_ in true},seconds:0,limit:q.timeLimit,at:Date().timeIntervalSince1970)
        live.headline=winners.isEmpty ? (model.sent.isEmpty ? "正确答案" : "这题没人答对") : "答对：" + winners.joined(separator:"、")
        quiz=live;classModel=nil
    }

    /// K: endless flash-card practice, for the whole class by default (the panel switches to one student; A picks
    /// everybody).
    func openPractice(classwide:Bool=true){
        if campaign == nil {openQuiz();return}
        guard let c=campaign,quiz == nil,quizPanel == nil,presentationHost != nil else{return}
        let model=PracticeModel(player:c.selectedPlayerID,classwide:classwide)
        practiceModel=model
        let panel=KeyHostingController(rootView:PracticePanel(game:self,model:model,onClose:{[weak self] in self?.endPractice()}))
        panel.onKey={[weak self] key in
            guard let self else{return false}
            // Correcting a card: ⏎ saves, Esc cancels, nothing else marks or moves the deck.
            if let model=self.practiceModel,model.editing != nil {
                if key=="⏎" {self.saveFlashCardEdit();return true}
                if key=="⎋" {model.editing=nil;return true}
                return false
            }
            switch key {
            case "⎋":self.endPractice()
            case "c","0":self.practiceAnswer(nil)
            case "d":if let q=self.quiz?.question,q.type == .flashcard {self.practiceAnswer(q.parts[0].answer)}
            case "e":self.editPracticeCard()
            case "a":self.selectAllPracticePlayers()
            case "o":self.setPracticeOrder(self.practiceModel?.order == .shuffled ? .sequential:.shuffled)
            case "→":self.stepPractice(1)
            case "←":self.stepPractice(-1)
            case " ":if self.practiceModel?.classwide == true {self.skipClassCard()} else {self.stepPractice(1)}
            default:
                if let n=Int(key),let id=self.player(forSeat:n) {
                    if self.practiceModel?.classwide == true {self.togglePracticePlayer(id)} else {self.switchPractice(to:id)}
                    return true
                }
                return false
            }
            return true
        }
        rebuildDeck()
        presentPanel(panel,size:CGSize(width:720,height:460),dock:true)
    }
    /// The deck for the current student / the class, in bank order or shuffled; shows its first card.
    private func rebuildDeck(keeping current:Int?=nil){
        guard let c=campaign,let model=practiceModel else{return}
        var deck=model.classwide ? c.classFlashDeck:c.practiceDeck(for:model.player)
        if model.order == .shuffled {deck.shuffle()}
        model.deck=deck
        model.cursor=current.flatMap{deck.firstIndex(of:$0)} ?? 0
        if current == nil {showPracticeCard()}
    }
    /// Shows the card at the deck position (the teacher's pick, or the next one).
    private func showPracticeCard(){
        guard let c=campaign,let model=practiceModel else{return}
        guard !model.deck.isEmpty else{withAnimation{quiz=nil};return}
        model.cursor=(model.cursor%model.deck.count+model.deck.count)%model.deck.count
        let i=model.deck[model.cursor]
        quizToken += 1;model.waiting=false
        if model.classwide {
            model.players=[];model.note=nil
            quiz=LiveQuiz(token:quizToken,index:i,question:c.quizBank[i],mode:.practice,player:"",playerName:"全班",place:"全班闪卡",node:nil,start:Date())
        } else if let unit=c.engine.state.units[model.player] {
            quiz=LiveQuiz(token:quizToken,index:i,question:c.quizBank[i],mode:.practice,player:model.player,playerName:unit.shortName,place:"闪卡练习",node:nil,start:Date())
        }
    }
    /// After a card is marked: the next one (a shuffled deck is shuffled again at the end of each round).
    private func advancePractice(){
        guard let model=practiceModel,!model.deck.isEmpty else{return}
        if model.cursor+1>=model.deck.count {
            model.cursor=0
            if model.order == .shuffled {let last=model.deck.last;model.deck.shuffle();if model.deck.count>1,model.deck.first==last {model.deck.swapAt(0,model.deck.count-1)}}
        } else {model.cursor += 1}
        showPracticeCard()
    }
    /// ← / → (and the arrow buttons): move through the deck without marking.
    /// While a card's back shows (after marking), moving on takes over at once.
    func stepPractice(_ by:Int){
        guard let model=practiceModel,!model.deck.isEmpty else{return}
        model.waiting=false
        model.cursor += by;showPracticeCard()
    }
    /// The teacher picked a card from the list (also while the last one's back shows).
    func pickPracticeCard(_ position:Int){
        guard let model=practiceModel,model.deck.indices.contains(position) else{return}
        model.waiting=false
        model.cursor=position;showPracticeCard()
    }
    func setPracticeOrder(_ order:PracticeModel.Order){
        guard let model=practiceModel,model.order != order else{return}
        model.order=order
        // The card on screen stays; the rest of the deck follows the new order from here.
        rebuildDeck(keeping:quiz?.mode == .practice ? quiz?.index:nil)
    }
    func setPracticeClasswide(_ on:Bool){
        guard let model=practiceModel,!model.waiting,model.classwide != on else{return}
        model.classwide=on;model.right=0;model.total=0;model.players=[];model.note=nil;model.results=[:]
        // The card on screen stays (one student ↔ the whole class answer the same card); only who answers changes.
        let current=quiz?.mode == .practice && quiz?.attempt == nil ? quiz?.index:nil
        rebuildDeck(keeping:current)
        if current != nil {showPracticeCard()}
    }
    /// A: everybody answered (again: nobody). From one student's practice it switches to the whole class first.
    func selectAllPracticePlayers(){
        guard let c=campaign,let model=practiceModel,!model.waiting else{return}
        if !model.classwide {setPracticeClasswide(true)}
        let everyone=Set(c.engine.state.players.filter{!$0.host && $0.isAlive}.map(\.id))
        model.players=model.players==everyone ? []:everyone;model.note=nil
    }
    func togglePracticePlayer(_ id:String){
        guard let model=practiceModel,model.classwide,!model.waiting else{return}
        if model.players.contains(id){model.players.remove(id)}else{model.players.insert(id)}
        model.note=nil
    }
    /// Whole class: nobody to record, show the back and go on.
    private func skipClassCard(){
        guard var live=quiz,live.mode == .practice,live.attempt==nil,let model=practiceModel,model.classwide,!model.waiting else{return}
        model.waiting=true
        live.attempt=classReveal(live.question,index:live.index);live.headline="背面";live.hold=1.3;quiz=live
    }
    /// A stand-in attempt that shows the right answers (class reveals).
    private func classReveal(_ q:QuizQuestion,index:Int)->QuizAttempt {
        let parts=q.parts
        return QuizAttempt(player:"",playerName:"全班",node:-1,question:index,picks:parts.map{$0.answer},texts:parts.map{_ in nil},correct:parts.map{_ in true},seconds:0,limit:q.timeLimit,at:Date().timeIntervalSince1970)
    }
    func switchPractice(to id:String){
        guard let model=practiceModel,!model.waiting else{return}
        model.player=id;model.right=0;model.total=0;model.results=[:]
        rebuildDeck()
    }
    func practiceAnswer(_ option:Int?){
        guard let c=campaign,var live=quiz,live.mode == .practice,live.attempt==nil,let model=practiceModel,!model.waiting else{return}
        if model.classwide {
            guard !model.players.isEmpty else{model.note="先按 1–7 选回答的同学。";return}
            let right=option != nil
            do{
                var names:[String]=[]
                for id in c.engine.state.players.map(\.id) where model.players.contains(id) {
                    let a=try c.recordQuiz(actor:id,question:live.index,picks:[option],seconds:Date().timeIntervalSince(live.start),free:true,shared:true,practice:true,askedAt:live.start)
                    names.append(a.playerName)
                }
                model.total += names.count;if right {model.right += names.count}
                model.results[live.index]=right
                askRecordSkipped(question:live.index,answered:model.players,practice:true)
                model.waiting=true
                live.attempt=classReveal(live.question,index:live.index)
                live.headline=(right ? "答对：" : "答错：")+names.joined(separator:"、")
                live.hold=1.6;quiz=live
                renderer?.classroomRefresh();revision += 1
            }catch{model.note=error.localizedDescription}
            return
        }
        do{
            let a=try c.recordQuiz(actor:live.player,question:live.index,picks:[option],seconds:Date().timeIntervalSince(live.start),free:true,practice:true,askedAt:live.start)
            model.total += 1;if a.correct.allSatisfy({$0}){model.right += 1}
            model.results[live.index]=a.correct.allSatisfy{$0}
            model.waiting=true
            live.attempt=a;live.hold=1.3;quiz=live
            renderer?.classroomRefresh();revision += 1
        }catch{message=error.localizedDescription;revision += 1}
    }
    /// 编辑: correct the card on screen (pick another with 选卡 first).
    func editPracticeCard(){
        guard let c=campaign,let model=practiceModel,!model.waiting,let live=quiz,live.mode == .practice,c.quizBank.indices.contains(live.index) else{return}
        model.editing=FlashCardDraft(index:live.index,question:c.quizBank[live.index])
    }
    /// Saves the corrected card in place in the trip (its answers stay with it) and in its course; the meaning is
    /// remembered for the next double-click on that word.
    func saveFlashCardEdit(){
        guard let c=campaign,let model=practiceModel,let draft=model.editing,c.quizBank.indices.contains(draft.index) else{return}
        let old=c.quizBank[draft.index]
        let front=String(draft.front.trimmingCharacters(in:.whitespacesAndNewlines).prefix(120)),back=String(draft.back.trimmingCharacters(in:.whitespacesAndNewlines).prefix(200))
        guard !front.isEmpty,!back.isEmpty,var item=old.items?.first,item.options.indices.contains(item.answer) else{draft.note="正面和背面都要填。";return}
        var new=old
        new.prompt=front;item.options[item.answer]=back;new.items=[item];new.difficulty=draft.difficulty
        if new != old {
            if let problem=replaceQuestion(old,with:new) {draft.note=problem;return}
            if draft.englishFront {NotesDictionary.shared.remember(front,back)} else {NotesDictionary.shared.remember(back,front)}
            message="已修改闪卡：\(front) → \(back)（作答记录保留）"
        }
        model.editing=nil
        // The card on screen shows the corrected sides.
        if var live=quiz,live.mode == .practice,live.index==draft.index,live.attempt==nil {quizToken += 1;live.token=quizToken;live.question=new;quiz=live}
        revision += 1
    }
    /// The teacher corrected a question: it changes in its course and, when the open trip has it, in place in the
    /// trip so the answers already given stay with it. Returns a problem to show, if any (the course still changes;
    /// a question whose options changed in number starts afresh in the trip, its old answers stay on the old one).
    @discardableResult func replaceQuestion(_ old:QuizQuestion,with new:QuizQuestion)->String? {
        do{try new.validate()}catch{return error.localizedDescription}
        var note:String?
        if let c=campaign,let i=c.quizBank.firstIndex(of:old) {
            do{try c.replaceQuizQuestion(at:i,with:new)}catch{note="选项数变了：这节课已作答的记录留在旧题上。"}
        }
        QuizLibrary.shared.replace(old,with:new)
        applyQuizCourse()
        revision += 1
        return note
    }
    private func endPractice(){
        practiceModel=nil;closePanel();withAnimation{quiz=nil}
    }

    /// Esc or a tap on the preview while an answer is showing: the reveal ends now (what follows it, the next
    /// challenge question or flash card, comes straight away).
    @discardableResult func skipQuizReveal()->Bool {
        guard let live=quiz,live.attempt != nil else{return false}
        quizCardFinished(live.token);return true
    }
    /// The card finished its reveal (called by every copy: TV and preview; the first one acts).
    func quizCardFinished(_ token:Int){
        guard let live=quiz,live.token==token,let attempt=live.attempt else{return}
        if live.mode == .practice,practiceModel != nil {advancePractice();return}
        if live.mode == .challenge {
            withAnimation{quiz=nil}
            if let model=challenge,model.phase == .question {
                // The next question the chosen way, until the time is up.
                if model.remaining>0 {challengeNext()} else {finishChallenge()}
            }
            return
        }
        withAnimation(.easeIn(duration:0.2)){quiz=nil}
        if live.mode == .personal,let base=quizGainBase,attempt.coins>0 || attempt.drop != nil {
            renderer?.classroomShowGains(title:attempt.drop != nil ? "答题掉落":"答题奖励",subtitle:"\(attempt.playerName) · 答对 \(attempt.rightCount)/\(attempt.correct.count) · 用时 \(Int(attempt.seconds.rounded())) 秒",since:base)
        }
        quizGainBase=nil;quizDraft=nil;quizReward=nil
    }

    /// The answer report of the current trip (pages to look at, PDF / picture export).
    func openQuizReport(){
        guard !modalOpen,let presenter=presentationHost,let campaign else{return}
        let screen=UIHostingController(rootView:QuizReportScreen(report:campaign.quizReport,title:"课堂答题报告",course:QuizLibrary.shared.active,itemName:{id in (try? campaign.engine.catalog.item(id).name) ?? id},onClose:{[weak self] in self?.presentationHost?.dismiss(animated:true)},
                                                                 records:recordEditing,refresh:{[weak self] in self?.campaign?.quizReport ?? campaign.quizReport}))
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
    @Published var highFrameRate=MeadowFrameRate.high {didSet{MeadowFrameRate.high=highFrameRate;renderer?.classroomApplyFrameRate()}}
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
            if controller is MeadowCampaignInventoryViewController || controller is MeadowShopViewController || controller is CustomWheelViewController
                || controller is UIHostingController<TeacherCharacterStudio> {return controller.view}
            next=controller.presentedViewController
        }
        return nil
    }
    var presentationHost:UIViewController? {
        var top=privatePresenter
        while let next=top?.presentedViewController {top=next}
        return top
    }
    init(){
        mirrorTimer=Timer.scheduledTimer(withTimeInterval:1/ClassroomPreviewPolicy.framesPerSecond,repeats:true){[weak self] _ in
            Task{@MainActor in
                self?.publishMirrorFrame()
                // A pack / shop opened while the laser is on gets the catcher too.
                if self?.laser.on == true {self?.syncPanelLaser()}
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
            // Every trip (a new map each lesson) deals from the teacher's current course.
            try? session.useQuizCourse(QuizLibrary.shared.active,questions:QuizLibrary.shared.activeQuestions)
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
        // A background save of the trip being replaced must not land after this one.
        MeadowCampaignSession.flushPendingSaves()
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
    /// Mid-trip: move one player to another team (they walk over to where that team stands).
    func movePlayer(_ id:String,toTeam team:String){
        guard !busy,let c=campaign else{return}
        let name=c.engine.state.units[id]?.shortName ?? id
        do{try c.movePlayer(id,toTeam:team);renderer?.classroomRefresh();message="\(name) 已换到\(c.teamName(team))，站到该队所在地点。";revision += 1}catch{message=error.localizedDescription}
    }
    /// Mid-trip: take one player out of the game. The map is rebuilt for the smaller party; undo in 历史.
    func removePlayer(_ id:String){
        guard !busy,let c=campaign else{return}
        let name=c.engine.state.units[id]?.shortName ?? id
        do{
            try c.removePlayer(id)
            MeadowCampaignSession.flushPendingSaves()
            try loadJourney(c.snapshot)
            message="已删除玩家 \(name)（可在存档 → 历史里撤销）。";revision += 1
        }catch{message=error.localizedDescription}
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
        if renderer?.startCampaignDuel(actor:c.selectedPlayerID)==true {message="队伍PVP开始。"};revision += 1
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
    @discardableResult func grantBookPlayers(_ ids:[String],movement:Int,coins:Int,score:Int=0)->Bool {
        guard !busy else{message="请等待当前动作结束。";return false}
        guard !ids.isEmpty else{message="请先选择发放对象。";return false}
        guard movement>0 || coins>0 || score>0 else{message="请填写移动步数、金币或积分。";return false}
        do{try backend.grantSupplies(ids,movement:movement,coins:coins,score:score,role:.teacher);renderer?.classroomRefresh();message="已向\(ids.count)名玩家发放"+[movement>0 ? "移动\(movement)步":nil,coins>0 ? "金币\(coins)":nil,score>0 ? "积分\(score)":nil].compactMap{$0}.joined(separator:"、")+"。";revision += 1;return true}
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
