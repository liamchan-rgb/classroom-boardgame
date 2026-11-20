import SwiftUI
import UIKit
import ClassroomGameCore
import MeadowWorldSupport

// MARK: - Class timer

/// The classroom countdown shown on the TV over everything (game and picture book). Only state changes are
/// published; the badge itself redraws from `endDate`, so a running timer does not refresh the teacher console.
@MainActor final class ClassTimerModel:ObservableObject {
    @Published var visible=false
    @Published private(set) var endDate:Date?
    @Published private(set) var pausedRemaining:Double?
    @Published private(set) var duration=10
    var running:Bool {endDate != nil}
    func remaining(at now:Date=Date())->Double {
        if let endDate {return max(0,endDate.timeIntervalSince(now))}
        return pausedRemaining ?? Double(duration)
    }
    /// "时间到" stays this long on the TV, then the badge goes away by itself.
    static let doneHold=4.0
    private var finishTimer:Timer?
    func start(_ seconds:Int) {
        duration=max(1,min(5999,seconds));endDate=Date().addingTimeInterval(Double(duration));pausedRemaining=nil;visible=true;scheduleFinish()
    }
    func toggle() {
        if let endDate {pausedRemaining=max(0,endDate.timeIntervalSinceNow);self.endDate=nil;finishTimer?.invalidate();finishTimer=nil;return}
        let left=pausedRemaining ?? Double(duration)
        if left<=0.05 {start(duration)} else {endDate=Date().addingTimeInterval(left);pausedRemaining=nil;visible=true;scheduleFinish()}
    }
    func reset() {finishTimer?.invalidate();finishTimer=nil;endDate=nil;pausedRemaining=nil}
    /// Put the badge away (also when "时间到" is showing).
    func hide() {finishTimer?.invalidate();finishTimer=nil;if let endDate,endDate<=Date() {self.endDate=nil;pausedRemaining=nil};visible=false}
    func add(_ seconds:Int) {
        if let endDate {self.endDate=max(Date(),endDate).addingTimeInterval(Double(seconds));scheduleFinish()}
        else {pausedRemaining=max(0,(pausedRemaining ?? Double(duration))+Double(seconds))}
        visible=true
    }
    /// When the countdown runs out, show "时间到" for a few seconds, then stop and hide.
    private func scheduleFinish() {
        finishTimer?.invalidate();finishTimer=nil
        guard let endDate else{return}
        // A plain run-loop timer on the main thread (no async task): fires once, a few seconds after time is up.
        let fire=endDate.addingTimeInterval(Self.doneHold)
        let t=Timer(fire:fire,interval:0,repeats:false){[weak self] _ in
            DispatchQueue.main.async{self?.finishIfDone()}
        }
        RunLoop.main.add(t,forMode:.common);finishTimer=t
    }
    private func finishIfDone() {
        finishTimer=nil
        guard let end=endDate,end<=Date() else{return}
        endDate=nil;pausedRemaining=nil;visible=false
    }
    /// "45" → 45 s, "1:30" → 90 s, "+10" / "-10" → adjust the running timer. Returns false for anything else.
    @discardableResult func apply(_ raw:String)->Bool {
        let text=raw.trimmingCharacters(in:.whitespaces).replacingOccurrences(of:"：",with:":")
        if let sign=text.first,"+-".contains(sign),let value=Int(text.dropFirst()) {add(sign=="+" ? value:-value);return true}
        let parts=text.split(separator:":").map{Int($0)}
        if parts.count==2,let m=parts[0],let s=parts[1],m>=0,(0..<60).contains(s),m*60+s>0 {start(m*60+s);return true}
        if parts.count==1,let s=parts[0],s>0 {start(s);return true}
        return false
    }
    static func label(_ seconds:Double)->String {
        let whole=Int(ceil(seconds))
        return whole>=60 ? String(format:"%d:%02d",whole/60,whole%60):"\(whole)"
    }
}

/// Teacher-switched TV overlays besides the timer.
@MainActor final class ClassOverlayModel:ObservableObject {
    @Published var scoreboard=false
    /// Scoreboard by team (average score per student) instead of by player; remembered on this device.
    @Published var teamScores=UserDefaults.standard.bool(forKey:"classroom.scoreboardTeams") {didSet{UserDefaults.standard.set(teamScores,forKey:"classroom.scoreboardTeams")}}
}

/// Everything the TV shows on top of game or book: the countdown and the scoreboard. Sized from the screen height
/// so the TV and the teacher's preview look the same.
struct ClassroomTVOverlays:View {
    @ObservedObject var timer:ClassTimerModel
    @ObservedObject var overlays:ClassOverlayModel
    @ObservedObject var game:MeadowTeacherCoordinator
    var body:some View {
        GeometryReader{g in
            let unit=g.size.height/720
            ZStack(alignment:.top){
                if overlays.scoreboard {
                    Group{
                        if overlays.teamScores {ClassroomTeamScoreboard(state:game.campaign?.engine.state,unit:unit)}
                        else {ClassroomScoreboard(players:game.campaign?.engine.state.players ?? [],unit:unit)}
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                }
                if game.quiz != nil {QuizOverlayHost(game:game)}
                if let challenge=game.challenge {ChallengeOverlay(model:challenge,unit:unit)}
                if timer.visible {ClassTimerBadge(timer:timer,unit:unit).padding(.top,16*unit)}
                LaserLayer(laser:game.laser)
            }.frame(width:g.size.width,height:g.size.height,alignment:.top)
        }.allowsHitTesting(false)
    }
}

private struct ClassTimerBadge:View {
    @ObservedObject var timer:ClassTimerModel
    let unit:CGFloat
    var body:some View {
        TimelineView(.periodic(from:.now,by:0.1)){context in
            let left=timer.remaining(at:context.date),done=left<=0.05
            let urgent = !done && left<=3.05
            let pulse=done ? (Int(context.date.timeIntervalSinceReferenceDate*2)%2==0 ? 1.0:0.55):1.0
            HStack(spacing:12*unit){
                Image(systemName:done ? "bell.fill":(timer.running ? "timer":"pause.fill")).font(.system(size:34*unit,weight:.bold))
                Text(done ? "时间到":ClassTimerModel.label(left)).font(.system(size:56*unit,weight:.heavy,design:.rounded)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal,28*unit).padding(.vertical,10*unit)
            .background(Capsule().fill(done ? Color.red.opacity(0.85):(urgent ? Color.orange.opacity(0.85):Color.black.opacity(0.62))))
            .overlay(Capsule().stroke(.white.opacity(0.35),lineWidth:1.5*unit))
            .opacity(pulse)
            .scaleEffect(urgent ? 1.06:1)
            .animation(.spring(response:0.3,dampingFraction:0.6),value:Int(ceil(left)))
        }
    }
}

// MARK: - Scoreboard

private struct ClassroomScoreboard:View {
    let players:[GameUnit]
    let unit:CGFloat
    private static let tints:[Color]=[Color(red:0.36,green:0.72,blue:0.52),Color(red:0.42,green:0.62,blue:0.95),Color(red:0.95,green:0.62,blue:0.36),Color(red:0.78,green:0.52,blue:0.92),Color(red:0.95,green:0.80,blue:0.38),Color(red:0.40,green:0.80,blue:0.85),Color(red:0.92,green:0.50,blue:0.55)]
    var body:some View {
        let ranked=players.sorted{($0.score,$0.coins,$1.id)>($1.score,$1.coins,$0.id)}
        VStack(spacing:10*unit){
            HStack{
                Label("记分板",systemImage:"list.number").font(.system(size:30*unit,weight:.heavy,design:.rounded))
                Spacer()
                Label("积分",systemImage:"star.fill").frame(width:150*unit,alignment:.trailing)
                Label("金币",systemImage:"bitcoinsign.circle.fill").frame(width:150*unit,alignment:.trailing)
            }.font(.system(size:20*unit,weight:.bold,design:.rounded)).foregroundStyle(GameTheme.muted)
            ForEach(Array(ranked.enumerated()),id:\.element.id){rank,u in
                let seat=(players.firstIndex{$0.id==u.id} ?? rank)
                HStack(spacing:14*unit){
                    Text("\(rank+1)").font(.system(size:24*unit,weight:.heavy,design:.rounded)).frame(width:34*unit)
                        .foregroundStyle(rank==0 ? Color(red:0.74,green:0.52,blue:0.12):GameTheme.muted)
                    Text(String(u.shortName.prefix(1)).uppercased()).font(.system(size:20*unit,weight:.heavy,design:.rounded))
                        .frame(width:40*unit,height:40*unit).background(Self.tints[seat%Self.tints.count],in:Circle())
                    Text(u.name).font(.system(size:26*unit,weight:.bold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength:0)
                    Text("\(u.score)").frame(width:150*unit,alignment:.trailing).foregroundStyle(GameTheme.primary)
                    Text("\(u.coins)").frame(width:150*unit,alignment:.trailing).foregroundStyle(Color(red:0.74,green:0.52,blue:0.12))
                }
                .font(.system(size:28*unit,weight:.heavy,design:.rounded)).monospacedDigit().foregroundStyle(GameTheme.ink)
                .padding(.horizontal,16*unit).padding(.vertical,8*unit)
                .background(RoundedRectangle(cornerRadius:16*unit,style:.continuous).fill(.white.opacity(rank==0 ? 0.7:0.42)))
            }
            if players.isEmpty {Text("还没有进行中的行程").font(.system(size:22*unit)).foregroundStyle(GameTheme.muted)}
        }
        .padding(26*unit).frame(width:820*unit)
        // Static light glass like the console (no live blur over the moving game, which would cost every frame);
        // thick sheet, thinner rows inside it.
        .background(RoundedRectangle(cornerRadius:28*unit,style:.continuous).fill(LinearGradient(colors:[Color(red:0.95,green:0.98,blue:0.98).opacity(0.94),Color(red:0.90,green:0.95,blue:0.96).opacity(0.90)],startPoint:.top,endPoint:.bottom)))
        .overlay(RoundedRectangle(cornerRadius:28*unit,style:.continuous).stroke(.white,lineWidth:1.5*unit))
        .transition(.scale(scale:0.92).combined(with:.opacity))
    }
}

/// Team view of the scoreboard: teams ranked by the average score of their students, with each team's total,
/// head count and coins; the members' initials sit under the team name.
private struct ClassroomTeamScoreboard:View {
    let state:GameState?
    let unit:CGFloat
    static let tints:[Color]=[Color(red:0.90,green:0.36,blue:0.36),Color(red:0.36,green:0.56,blue:0.92),Color(red:0.32,green:0.70,blue:0.44),Color(red:0.88,green:0.68,blue:0.22),Color(red:0.66,green:0.44,blue:0.88),Color(red:0.94,green:0.56,blue:0.26)]
    var body:some View {
        let rows=state.map(GameRules.teamStandings) ?? []
        let order=state?.teams.map(\.id) ?? []
        VStack(spacing:12*unit){
            HStack{
                Label("队伍记分",systemImage:"person.3.fill").font(.system(size:30*unit,weight:.heavy,design:.rounded))
                Spacer()
                Label("平均积分",systemImage:"star.fill").frame(width:190*unit,alignment:.trailing)
                Label("总积分",systemImage:"sum").frame(width:130*unit,alignment:.trailing)
                Label("金币",systemImage:"bitcoinsign.circle.fill").frame(width:130*unit,alignment:.trailing)
            }.font(.system(size:20*unit,weight:.bold,design:.rounded)).foregroundStyle(GameTheme.muted)
            ForEach(rows){row in
                let tint=Self.tints[(order.firstIndex(of:row.id) ?? 0)%Self.tints.count]
                HStack(spacing:14*unit){
                    Text("\(row.rank)").font(.system(size:26*unit,weight:.heavy,design:.rounded)).frame(width:34*unit)
                        .foregroundStyle(row.rank==1 ? Color(red:0.74,green:0.52,blue:0.12):GameTheme.muted)
                    RoundedRectangle(cornerRadius:5*unit).fill(tint).frame(width:10*unit,height:56*unit)
                    VStack(alignment:.leading,spacing:4*unit){
                        Text(row.name).font(.system(size:28*unit,weight:.heavy,design:.rounded)).lineLimit(1).minimumScaleFactor(0.6)
                        HStack(spacing:4*unit){
                            ForEach(row.memberIDs,id:\.self){id in
                                Text(String((state?.units[id]?.shortName ?? id).prefix(1)).uppercased())
                                    .font(.system(size:13*unit,weight:.heavy,design:.rounded)).foregroundStyle(.white)
                                    .frame(width:24*unit,height:24*unit).background(tint.opacity(0.85),in:Circle())
                            }
                            Text("\(row.memberIDs.count) 人").font(.system(size:15*unit,weight:.bold,design:.rounded)).foregroundStyle(GameTheme.muted)
                        }
                    }
                    Spacer(minLength:0)
                    Text(row.averageScore.formatted(.number.precision(.fractionLength(0...1)))).font(.system(size:38*unit,weight:.heavy,design:.rounded))
                        .frame(width:190*unit,alignment:.trailing).foregroundStyle(GameTheme.primary)
                    Text("\(row.totalScore)").frame(width:130*unit,alignment:.trailing).foregroundStyle(GameTheme.ink)
                    Text("\(row.totalCoins)").frame(width:130*unit,alignment:.trailing).foregroundStyle(Color(red:0.74,green:0.52,blue:0.12))
                }
                .font(.system(size:26*unit,weight:.heavy,design:.rounded)).monospacedDigit().foregroundStyle(GameTheme.ink)
                .padding(.horizontal,16*unit).padding(.vertical,10*unit)
                .background(RoundedRectangle(cornerRadius:16*unit,style:.continuous).fill(.white.opacity(row.rank==1 ? 0.7:0.42)))
            }
            if rows.isEmpty {Text(state==nil ? "还没有进行中的行程":"还没有队伍成员").font(.system(size:22*unit)).foregroundStyle(GameTheme.muted)}
            Text("按队员平均积分排名（不含老师）").font(.system(size:16*unit,weight:.semibold,design:.rounded)).foregroundStyle(GameTheme.muted)
        }
        .padding(26*unit).frame(width:900*unit)
        .background(RoundedRectangle(cornerRadius:28*unit,style:.continuous).fill(LinearGradient(colors:[Color(red:0.95,green:0.98,blue:0.98).opacity(0.94),Color(red:0.90,green:0.95,blue:0.96).opacity(0.90)],startPoint:.top,endPoint:.bottom)))
        .overlay(RoundedRectangle(cornerRadius:28*unit,style:.continuous).stroke(.white,lineWidth:1.5*unit))
        .transition(.scale(scale:0.92).combined(with:.opacity))
    }
}

// MARK: - Timer panel (teacher)

struct ClassTimerPanel:View {
    @ObservedObject var timer:ClassTimerModel
    var onClose:()->Void
    @State private var input=""
    @State private var invalid=false
    var body:some View {
        VStack(spacing:16){
            HStack{
                Label("计时器",systemImage:"timer").font(.title2.bold())
                Spacer()
                Toggle(isOn:$timer.visible){Label("投屏显示",systemImage:"tv")}.fixedSize()
                Button{onClose()}label:{Image(systemName:"xmark.circle.fill").font(.title2)}.buttonStyle(.plain).foregroundStyle(GameTheme.muted)
            }
            TimelineView(.periodic(from:.now,by:0.1)){context in
                let left=timer.remaining(at:context.date)
                Text(left<=0.05 && timer.running ? "时间到":ClassTimerModel.label(left))
                    .font(.system(size:84,weight:.heavy,design:.rounded)).monospacedDigit()
                    .foregroundStyle(left<=3.05 && timer.running ? Color.orange:GameTheme.ink)
            }
            HStack(spacing:10){
                Image(systemName:"keyboard").font(.system(size:17,weight:.semibold)).foregroundStyle(GameTheme.primary).frame(width:22)
                ClassroomTextField(placeholder:"输入秒数后回车（如 30、1:30、+10）",text:$input,limit:8,keyboard:.numbersAndPunctuation,onSubmit:{submit()},autoFocus:true).frame(height:44)
                if invalid{Text("格式不对").font(.caption).foregroundStyle(.red)}
            }
            .padding(.horizontal,12).background(GlassFill.field,in:RoundedRectangle(cornerRadius:12,style:.continuous))
            HStack(spacing:10){
                ForEach([10,30,60,120],id:\.self){s in
                    Button{timer.start(s);onClose()}label:{Label(ClassTimerModel.label(Double(s)),systemImage:"play.fill")}
                }
                Button{timer.add(10)}label:{Label("+10",systemImage:"plus")}
                Button{timer.toggle();if timer.running{onClose()}}label:{Label(timer.running ? "暂停":"继续",systemImage:timer.running ? "pause.fill":"play.fill")}.buttonStyle(GlassIconButtonStyle(prominent:true))
                Button{timer.reset()}label:{Label("重置",systemImage:"arrow.counterclockwise")}
                Button{timer.reset();timer.hide();onClose()}label:{Label("关闭计时",systemImage:"xmark.circle")}
            }.buttonStyle(GlassIconButtonStyle())
            Label("默认 10 秒 · 输入数字按回车即开始，开始后窗口自动关闭", systemImage:"info.circle").font(.caption).foregroundStyle(GameTheme.muted)
        }.padding(22).background(GlassBackdrop())
    }
    private func submit(){
        invalid = !timer.apply(input)
        // A countdown that is running is all the teacher wanted: the settings get out of the way.
        if !invalid {input="";if timer.running{onClose()}}
    }
}

// MARK: - Keyboard shortcuts

enum ClassroomShortcutAction:String,CaseIterable,Identifiable {
    case select1,select2,select3,select4,select5,select6,select7,award,grantMovement,attack,endTurn,pauseResume,pageBack,pageForward,goToPage,openTimer,timerStartPause,timerPlus10,toggleScoreboard,toggleTeamScores,openQuizReport,openQuiz,openClassQuiz,openPractice,openClassPractice,toggleLaser,timerClose
    /// Works everywhere, also over the pack / shop / sheets.
    var global:Bool {[.openTimer,.timerStartPause,.timerPlus10,.timerClose,.toggleScoreboard,.toggleTeamScores,.openQuiz,.openClassQuiz,.openPractice,.openClassPractice,.toggleLaser].contains(self)}
    var id:String {rawValue}
    var title:String {
        switch self {
        case .select1,.select2,.select3,.select4,.select5,.select6,.select7:return "选择第\(seat!)位成员"
        case .award:return "发金币（按下后输数字回车；连按两下按输入框）";case .grantMovement:return "发体力/移动（按下后输数字回车；连按两下按输入框）";case .attack:return "战斗：普通攻击";case .endTurn:return "战斗：结束行动"
        case .pauseResume:return "暂停 / 继续";case .pageBack:return "绘本上一页";case .pageForward:return "绘本下一页";case .goToPage:return "绘本跳到指定页（输页码回车）"
        case .openTimer:return "打开计时器";case .timerStartPause:return "计时开始 / 暂停";case .timerPlus10:return "计时 +10 秒"
        case .toggleScoreboard:return "显示 / 隐藏记分板"
        case .toggleTeamScores:return "记分板：个人 / 队伍切换"
        case .openQuizReport:return "打开答题报告"
        case .openQuiz:return "指定答题（个人挑战）"
        case .openClassQuiz:return "全班题（老师发奖）"
        case .openPractice:return "闪卡练习"
        case .openClassPractice:return "全班闪卡"
        case .toggleLaser:return "激光笔"
        case .timerClose:return "关闭计时（停止并收起）"
        }
    }
    var icon:String {
        switch self {
        case .select1,.select2,.select3,.select4,.select5,.select6,.select7:return "person.fill"
        case .award:return "bitcoinsign.circle";case .grantMovement:return "figure.walk";case .attack:return "burst";case .endTurn:return "forward.end";case .pauseResume:return "playpause"
        case .pageBack:return "chevron.left";case .pageForward:return "chevron.right";case .goToPage:return "arrow.right.doc.on.clipboard";case .openTimer:return "timer";case .timerStartPause:return "playpause.circle"
        case .timerPlus10:return "plus.circle";case .toggleScoreboard:return "list.number";case .toggleTeamScores:return "person.3";case .openQuizReport:return "chart.bar.doc.horizontal";case .openQuiz:return "questionmark.bubble";case .openClassQuiz:return "person.3.sequence";case .openPractice:return "rectangle.on.rectangle.angled";case .openClassPractice:return "rectangle.stack.badge.person.crop";case .toggleLaser:return "smallcircle.filled.circle";case .timerClose:return "timer.circle"
        }
    }
    var seat:Int? {["select1":1,"select2":2,"select3":3,"select4":4,"select5":5,"select6":6,"select7":7][rawValue]}
    var defaultKey:String {
        switch self {
        case .select1:return "1";case .select2:return "2";case .award:return "g";case .grantMovement:return "m";case .attack:return "a";case .endTurn:return "e"
        case .pauseResume:return " ";case .pageBack:return "←";case .pageForward:return "→";case .goToPage:return "p";case .openTimer:return "t";case .toggleScoreboard:return "s";case .toggleTeamScores:return "d";case .openQuizReport:return "r";case .openQuiz:return "q";case .openClassQuiz:return "⇧q";case .openPractice:return "k";case .openClassPractice:return "⇧k";case .toggleLaser:return "l";case .timerClose:return "⇧t"
        default:return ""
        }
    }
}
/// Teacher's key bindings (stored on this iPad). A key belongs to at most one action; "" = no key.
enum ClassroomShortcuts {
    private static let storeKey="classroom.shortcuts"
    static func bindings()->[ClassroomShortcutAction:String] {
        let saved=(UserDefaults.standard.dictionary(forKey:storeKey) as? [String:String]) ?? [:]
        var result:[ClassroomShortcutAction:String]=[:]
        for action in ClassroomShortcutAction.allCases {result[action]=saved[action.rawValue] ?? action.defaultKey}
        return result
    }
    static func set(_ key:String,for action:ClassroomShortcutAction) {
        var all=bindings()
        if !key.isEmpty {for (other,k) in all where k==key && other != action {all[other]=""}}
        all[action]=key
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues:all.map{($0.key.rawValue,$0.value)}),forKey:storeKey)
    }
    static func reset(){UserDefaults.standard.removeObject(forKey:storeKey)}
    static func action(for key:String)->ClassroomShortcutAction? {
        guard !key.isEmpty else{return nil}
        return bindings().first{$0.value==key}?.key
    }
    /// One token per physical key: arrows as ←→↑↓, space as " ", others as their lowercase character.
    static func token(_ key:UIKey)->String? {
        switch key.keyCode {
        case .keyboardLeftArrow:return "←";case .keyboardRightArrow:return "→";case .keyboardUpArrow:return "↑";case .keyboardDownArrow:return "↓"
        case .keyboardEscape,.keyboardReturnOrEnter,.keyboardTab,.keyboardDeleteOrBackspace:return nil
        default:
            let c=key.charactersIgnoringModifiers.lowercased()
            guard !c.isEmpty else{return nil}
            // Shift + a letter is its own key (⇧Q next to Q).
            if key.modifierFlags.contains(.shift),c.count==1,c.first!.isLetter {return "⇧"+c}
            return c
        }
    }
    static func label(_ key:String)->String {key.isEmpty ? "未设置":key==" " ? "空格":key.hasPrefix("⇧") ? "⇧"+key.dropFirst().uppercased():key.uppercased()}
    /// Keys inside quiz panels: the shortcut token, plus ⏎ ⎋ ⌫ (which shortcuts leave alone).
    static func panelToken(_ key:UIKey)->String? {
        switch key.keyCode {
        case .keyboardReturnOrEnter,.keypadEnter:return "⏎"
        case .keyboardEscape:return "⎋"
        case .keyboardDeleteOrBackspace:return "⌫"
        default:return token(key)
        }
    }
}

struct ClassroomShortcutEditor:View {
    var onClose:()->Void
    @State private var bindings=ClassroomShortcuts.bindings()
    @State private var recording:ClassroomShortcutAction?
    var body:some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ClassroomShortcutAction.allCases){action in
                        HStack{
                            Label(action.title,systemImage:action.icon)
                            Spacer()
                            if recording==action {
                                Text("请按一个键…").foregroundStyle(.orange)
                                ClassroomKeyCapture{key in
                                    if let key {ClassroomShortcuts.set(key,for:action)}
                                    bindings=ClassroomShortcuts.bindings();recording=nil
                                }.frame(width:1,height:1)
                            } else {
                                Text(ClassroomShortcuts.label(bindings[action] ?? "")).font(.system(.body,design:.monospaced).bold())
                                    .padding(.horizontal,10).padding(.vertical,4).background(GlassFill.field,in:RoundedRectangle(cornerRadius:8))
                                    .foregroundStyle((bindings[action] ?? "").isEmpty ? GameTheme.muted:GameTheme.ink)
                            }
                            Button{recording=recording==action ? nil:action}label:{Image(systemName:recording==action ? "xmark.circle":"keyboard")}.buttonStyle(.borderless)
                            Button{ClassroomShortcuts.set("",for:action);bindings=ClassroomShortcuts.bindings()}label:{Image(systemName:"minus.circle")}.buttonStyle(.borderless).disabled((bindings[action] ?? "").isEmpty)
                        }.glassRow()
                    }
                } footer:{Text("点键盘图标后按下想用的键；同一个键只能对应一个动作，新设置会顶替旧的。输入文字时快捷键自动失效。")}
            }
            .glassSheet()
            .navigationTitle("快捷键")
            .toolbar{
                ToolbarItem(placement:.cancellationAction){Button("恢复默认"){ClassroomShortcuts.reset();bindings=ClassroomShortcuts.bindings();recording=nil}}
                ToolbarItem(placement:.confirmationAction){Button{onClose()}label:{Image(systemName:"checkmark.circle.fill").font(.title2)}}
            }
        }
    }
}
/// Captures the next hardware key press for the shortcut editor (Esc cancels).
private struct ClassroomKeyCapture:UIViewRepresentable {
    var onKey:(String?)->Void
    func makeUIView(context:Context)->KeyCaptureView {let v=KeyCaptureView();v.onKey=onKey;return v}
    func updateUIView(_ v:KeyCaptureView,context:Context){v.onKey=onKey}
    final class KeyCaptureView:UIView {
        var onKey:((String?)->Void)?
        override var canBecomeFirstResponder:Bool {true}
        override func didMoveToWindow(){super.didMoveToWindow();if window != nil {DispatchQueue.main.async{self.becomeFirstResponder()}}}
        override func pressesBegan(_ presses:Set<UIPress>,with event:UIPressesEvent?) {
            guard let key=presses.first?.key else{super.pressesBegan(presses,with:event);return}
            if key.keyCode == .keyboardEscape {onKey?(nil);return}
            guard let token=ClassroomShortcuts.token(key) else{return}
            onKey?(token)
        }
    }
}

/// Scoreboard on/off button: lit while the TV shows it.
struct ClassroomScoreboardButton:View {
    @ObservedObject var overlays:ClassOverlayModel
    var action:()->Void
    var body:some View {
        // Tap shows / hides; the menu (long press, or the arrow on Mac) picks players or teams.
        Menu{
            Button{if !overlays.scoreboard{action()};withAnimation{overlays.teamScores=false}}label:{Label("个人记分",systemImage:overlays.teamScores ? "person":"checkmark")}
            Button{if !overlays.scoreboard{action()};withAnimation{overlays.teamScores=true}}label:{Label("队伍记分（平均积分）",systemImage:overlays.teamScores ? "checkmark":"person.3")}
            if overlays.scoreboard {Button(role:.destructive){action()}label:{Label("隐藏记分板",systemImage:"eye.slash")}}
        }label:{Label(overlays.teamScores ? "队分":"记分",systemImage:overlays.teamScores ? "person.3.fill":(overlays.scoreboard ? "list.number.rtl":"list.number"))}
        primaryAction:{action()}
            .buttonStyle(GlassIconButtonStyle(tint:overlays.scoreboard ? .orange:GameTheme.primary,prominent:overlays.scoreboard))
    }
}


// MARK: - Quick grant by keyboard

/// G (coins) / M (movement): press once, type a number, Enter grants it; press twice quickly to grant the book bar's
/// amounts. Recipients: the ticked players on the book tab, otherwise the selected player.
enum ClassroomGrantKind:Equatable {case coins,movement
    var title:String {self == .coins ? "金币":"体力（移动步数）"}
    var icon:String {self == .coins ? "bitcoinsign.circle.fill":"figure.walk"}
}
struct ClassroomGrantCapture:Equatable {var kind:ClassroomGrantKind;var digits:String}

extension MeadowTeacherCoordinator {
    var grantTargets:[String] {
        guard let c=campaign else{return []}
        if bookTabActive {return c.engine.state.players.map(\.id).filter{grantDraft.recipients.contains($0)}}
        return [c.selectedPlayerID]
    }
    /// The grant key was pressed.
    func grantKey(_ kind:ClassroomGrantKind) {
        let now=Date()
        if let last=lastGrantKey,last.kind==kind,now.timeIntervalSince(last.at)<0.45 {
            // Double press: the amounts from the book bar's fields.
            lastGrantKey=nil;grantCapture=nil
            let amount=BookGrantDraft.amount(kind == .coins ? grantDraft.coins:grantDraft.steps)
            grantNow(kind,amount:amount);return
        }
        lastGrantKey=(kind,now);grantCapture=ClassroomGrantCapture(kind:kind,digits:"")
        message="输入\(kind.title)数量后按回车发放（Esc取消）"
    }
    func grantCaptureDigit(_ d:Character) {guard var c=grantCapture,c.digits.count<5 else{return};c.digits.append(d);grantCapture=c}
    func grantCaptureBackspace() {guard var c=grantCapture else{return};if !c.digits.isEmpty{c.digits.removeLast()};grantCapture=c}
    func grantCaptureCancel() {grantCapture=nil;lastGrantKey=nil}
    func grantCaptureCommit() {
        guard let c=grantCapture else{return}
        grantCapture=nil;lastGrantKey=nil
        grantNow(c.kind,amount:Int(c.digits) ?? 0)
    }
    private func grantNow(_ kind:ClassroomGrantKind,amount:Int) {
        let ids=grantTargets
        guard amount>0 else{message="数量为0，未发放。";return}
        guard !ids.isEmpty else{message="请先选择发放对象。";return}
        grantBookPlayers(ids,movement:kind == .movement ? amount:0,coins:kind == .coins ? amount:0)
    }

    // Seat numbers: which number key (1–7) means which player; changed by long-pressing a player in the grant picker.
    private var seatKey:String {"classroom.seats."+(campaign?.engine.state.gameID ?? "none")}
    func seatNumber(_ id:String)->Int {
        let ids=campaign?.engine.state.players.map(\.id) ?? []
        let saved=(UserDefaults.standard.dictionary(forKey:seatKey) as? [String:Int]) ?? [:]
        return saved[id] ?? ((ids.firstIndex(of:id) ?? 0)+1)
    }
    func player(forSeat n:Int)->String? {campaign?.engine.state.players.map(\.id).first{seatNumber($0)==n}}
    /// Give `id` number `n`; whoever had `n` takes `id`'s old number.
    func setSeatNumber(_ id:String,_ n:Int) {
        let ids=campaign?.engine.state.players.map(\.id) ?? []
        var all=Dictionary(uniqueKeysWithValues:ids.map{($0,seatNumber($0))})
        let old=all[id] ?? n
        if let other=all.first(where:{$0.value==n && $0.key != id})?.key {all[other]=old}
        all[id]=n
        UserDefaults.standard.set(all,forKey:seatKey);revision += 1
        message="已把编号 \(n) 给 \(campaign?.engine.state.units[id]?.shortName ?? id)。"
    }
}

/// The small "type a number" banner while a grant key is waiting for its amount.
struct ClassroomGrantCaptureBanner:View {
    @ObservedObject var game:MeadowTeacherCoordinator
    var body:some View {
        if let c=game.grantCapture {
            HStack(spacing:10){
                Image(systemName:c.kind.icon).font(.title2.bold()).foregroundStyle(GameTheme.accent)
                Text("发\(c.kind.title)").font(.headline)
                Text(c.digits.isEmpty ? "输入数字":c.digits).font(.system(size:28,weight:.heavy,design:.rounded)).monospacedDigit()
                    .foregroundStyle(c.digits.isEmpty ? GameTheme.muted:GameTheme.ink).frame(minWidth:80)
                Text("→ \(game.grantTargets.count)人 · 回车发放 · Esc取消").font(.subheadline).foregroundStyle(GameTheme.muted)
            }
            .padding(.horizontal,18).padding(.vertical,10)
            .background(GlassFill.panel,in:Capsule()).overlay(Capsule().stroke(.white.opacity(0.8),lineWidth:1))
            .shadow(color:.black.opacity(0.12),radius:12,y:4)
            .transition(.move(edge:.top).combined(with:.opacity))
        }
    }
}
