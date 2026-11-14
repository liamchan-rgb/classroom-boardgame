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
    func start(_ seconds:Int) {
        duration=max(1,min(5999,seconds));endDate=Date().addingTimeInterval(Double(duration));pausedRemaining=nil;visible=true
    }
    func toggle() {
        if let endDate {pausedRemaining=max(0,endDate.timeIntervalSinceNow);self.endDate=nil;return}
        let left=pausedRemaining ?? Double(duration)
        if left<=0.05 {start(duration)} else {endDate=Date().addingTimeInterval(left);pausedRemaining=nil;visible=true}
    }
    func reset() {endDate=nil;pausedRemaining=nil}
    func add(_ seconds:Int) {
        if let endDate {self.endDate=max(Date(),endDate).addingTimeInterval(Double(seconds))}
        else {pausedRemaining=max(0,(pausedRemaining ?? Double(duration))+Double(seconds))}
        visible=true
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
                if overlays.scoreboard {ClassroomScoreboard(players:game.campaign?.engine.state.players ?? [],unit:unit).frame(maxWidth:.infinity,maxHeight:.infinity)}
                if timer.visible {ClassTimerBadge(timer:timer,unit:unit).padding(.top,16*unit)}
            }.frame(width:g.size.width,height:g.size.height)
        }.allowsHitTesting(false)
    }
}

private struct ClassTimerBadge:View {
    @ObservedObject var timer:ClassTimerModel
    let unit:CGFloat
    var body:some View {
        TimelineView(.periodic(from:.now,by:timer.running ? 0.1:3600)){context in
            let left=timer.remaining(at:context.date),done=left<=0.05
            let urgent=!done && left<=3.05
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
            }.font(.system(size:20*unit,weight:.bold,design:.rounded)).foregroundStyle(.white.opacity(0.9))
            ForEach(Array(ranked.enumerated()),id:\.element.id){rank,u in
                let seat=(players.firstIndex{$0.id==u.id} ?? rank)
                HStack(spacing:14*unit){
                    Text("\(rank+1)").font(.system(size:24*unit,weight:.heavy,design:.rounded)).frame(width:34*unit)
                        .foregroundStyle(rank==0 ? Color(red:1,green:0.84,blue:0.35):.white.opacity(0.8))
                    Text(String(u.shortName.prefix(1)).uppercased()).font(.system(size:20*unit,weight:.heavy,design:.rounded))
                        .frame(width:40*unit,height:40*unit).background(Self.tints[seat%Self.tints.count],in:Circle())
                    Text(u.name).font(.system(size:26*unit,weight:.bold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength:0)
                    Text("\(u.score)").frame(width:150*unit,alignment:.trailing).foregroundStyle(Color(red:1,green:0.86,blue:0.45))
                    Text("\(u.coins)").frame(width:150*unit,alignment:.trailing).foregroundStyle(Color(red:0.98,green:0.80,blue:0.40))
                }
                .font(.system(size:28*unit,weight:.heavy,design:.rounded)).monospacedDigit().foregroundStyle(.white)
                .padding(.horizontal,16*unit).padding(.vertical,8*unit)
                .background(RoundedRectangle(cornerRadius:16*unit,style:.continuous).fill(.white.opacity(rank==0 ? 0.16:0.08)))
            }
            if players.isEmpty {Text("还没有进行中的行程").font(.system(size:22*unit)).foregroundStyle(.white.opacity(0.7))}
        }
        .padding(26*unit).frame(width:820*unit)
        // A static dark glass (no live blur over the moving game, which would cost every frame).
        .background(RoundedRectangle(cornerRadius:28*unit,style:.continuous).fill(Color(red:0.04,green:0.08,blue:0.07).opacity(0.86)))
        .overlay(RoundedRectangle(cornerRadius:28*unit,style:.continuous).stroke(LinearGradient(colors:[.white.opacity(0.45),.white.opacity(0.08)],startPoint:.top,endPoint:.bottom),lineWidth:1.5*unit))
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
            TimelineView(.periodic(from:.now,by:timer.running ? 0.1:3600)){context in
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
                    Button{timer.start(s)}label:{Label(ClassTimerModel.label(Double(s)),systemImage:"play.fill")}
                }
                Button{timer.add(10)}label:{Label("+10",systemImage:"plus")}
                Button{timer.toggle()}label:{Label(timer.running ? "暂停":"继续",systemImage:timer.running ? "pause.fill":"play.fill")}.buttonStyle(GlassIconButtonStyle(prominent:true))
                Button{timer.reset()}label:{Label("重置",systemImage:"arrow.counterclockwise")}
            }.buttonStyle(GlassIconButtonStyle())
            Label("默认 10 秒 · 输入数字按回车即开始，可连续输入", systemImage:"info.circle").font(.caption).foregroundStyle(GameTheme.muted)
        }.padding(22).background(GlassBackdrop())
    }
    private func submit(){
        invalid = !timer.apply(input)
        if !invalid {input=""}
    }
}

// MARK: - Keyboard shortcuts

enum ClassroomShortcutAction:String,CaseIterable,Identifiable {
    case select1,select2,select3,select4,select5,select6,select7,award,attack,endTurn,pauseResume,pageBack,pageForward,openTimer,timerStartPause,timerPlus10,toggleScoreboard
    var id:String {rawValue}
    var title:String {
        switch self {
        case .select1,.select2,.select3,.select4,.select5,.select6,.select7:return "选择第\(seat!)位成员"
        case .award:return "奖励 10 金币";case .attack:return "战斗：普通攻击";case .endTurn:return "战斗：结束行动"
        case .pauseResume:return "暂停 / 继续";case .pageBack:return "绘本上一页";case .pageForward:return "绘本下一页"
        case .openTimer:return "打开计时器";case .timerStartPause:return "计时开始 / 暂停";case .timerPlus10:return "计时 +10 秒"
        case .toggleScoreboard:return "显示 / 隐藏记分板"
        }
    }
    var icon:String {
        switch self {
        case .select1,.select2,.select3,.select4,.select5,.select6,.select7:return "person.fill"
        case .award:return "bitcoinsign.circle";case .attack:return "burst";case .endTurn:return "forward.end";case .pauseResume:return "playpause"
        case .pageBack:return "chevron.left";case .pageForward:return "chevron.right";case .openTimer:return "timer";case .timerStartPause:return "playpause.circle"
        case .timerPlus10:return "plus.circle";case .toggleScoreboard:return "list.number"
        }
    }
    var seat:Int? {["select1":1,"select2":2,"select3":3,"select4":4,"select5":5,"select6":6,"select7":7][rawValue]}
    var defaultKey:String {
        switch self {
        case .select1:return "1";case .select2:return "2";case .award:return "g";case .attack:return "a";case .endTurn:return "e"
        case .pauseResume:return " ";case .pageBack:return "←";case .pageForward:return "→";case .openTimer:return "t";case .toggleScoreboard:return "s"
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
            return c.isEmpty ? nil:c
        }
    }
    static func label(_ key:String)->String {key.isEmpty ? "未设置":key==" " ? "空格":key.uppercased()}
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
        Button{action()}label:{Label("记分",systemImage:overlays.scoreboard ? "list.number.rtl":"list.number")}
            .buttonStyle(GlassIconButtonStyle(tint:overlays.scoreboard ? .orange:GameTheme.primary,prominent:overlays.scoreboard))
    }
}
