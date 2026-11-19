import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ClassroomGameCore
import MeadowWorldSupport

/// A quiz on screen. Shown in the TV overlays (over the game, the picture book and any panel) and in the teacher's
/// preview; `attempt` is set once the teacher submits.
struct LiveQuiz: Equatable {
    enum Mode: Equatable { case personal, classwide, practice, challenge }
    var token: Int
    var index: Int
    var question: QuizQuestion
    var mode: Mode
    var player: String
    var playerName: String
    var place: String
    /// The quiz spot on the map; nil when called up anywhere.
    var node: Int?
    var start: Date
    var attempt: QuizAttempt?
    var dropName: String?
    /// Reveal line instead of the reward line (class questions: who got it right).
    var headline: String?
    /// How long the reveal stays (practice moves on quickly).
    var hold: Double?
    /// Challenge: the card's clock counts down to the end of the challenge instead of the question's own limit.
    var deadline: Date?
}

/// Hosts the UIKit quiz card inside the SwiftUI overlays on a 720-point-high canvas, so the card looks the same on
/// the TV and in the teacher's preview.
struct QuizOverlayHost: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var body: some View {
        GeometryReader { g in
            if let quiz = game.quiz {
                let scale = g.size.height / 720
                QuizCardRepresentable(quiz: quiz, done: { [weak game] token in game?.quizCardFinished(token) })
                    .frame(width: g.size.width / scale, height: 720)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                    .transition(.opacity)
            }
        }
    }
}

private struct QuizCardRepresentable: UIViewRepresentable {
    let quiz: LiveQuiz
    var done: (Int) -> Void
    final class Box: UIView {
        var token = -1, revealed = false
        weak var card: MeadowQuizCard?
        override func layoutSubviews() { super.layoutSubviews(); card?.frame = bounds }
    }
    func makeUIView(context: Context) -> Box { let b = Box(); b.isUserInteractionEnabled = false; b.backgroundColor = .clear; return b }
    func updateUIView(_ box: Box, context: Context) {
        if box.token != quiz.token {
            box.card?.removeFromSuperview()
            box.layoutIfNeeded()
            let who = quiz.mode == .classwide ? "全班" : quiz.playerName
            let card = MeadowQuizCard.present(in: box, question: quiz.question, player: who, place: quiz.mode == .practice ? "闪卡练习" : quiz.mode == .challenge ? "专属挑战" : quiz.place, start: quiz.start, mode: quiz.mode, deadline: quiz.deadline)
            card.layer.zPosition = 0
            box.card = card; box.token = quiz.token; box.revealed = false
            box.setNeedsLayout()
        }
        if let attempt = quiz.attempt, !box.revealed, let card = box.card {
            box.revealed = true
            let token = quiz.token
            card.reveal(attempt, dropName: quiz.dropName, headline: quiz.headline, hold: quiz.hold) { done(token) }
        }
    }
}

// MARK: - Docked answer panel

/// What the docked answer panel shows: the panel's view and its key handler.
struct DockContent {
    let id = UUID()
    let view: AnyView
    let onKey: ((String) -> Bool)?
}
protocol DockablePanel { func dockContent() -> DockContent }
extension KeyHostingController: DockablePanel {
    func dockContent() -> DockContent { DockContent(view: AnyView(rootView), onKey: onKey) }
}

/// Beside the teacher's preview (game or picture book tab): the panel of the question on screen. Only the tab in
/// front shows it; each place builds its own controller from the same content (the models inside are shared).
struct QuizDock: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var book: Bool
    var body: some View {
        if let content = game.dockContent, game.bookTabActive == book {
            DockedPanel(content: content).id(content.id).frame(width: 480).layoutPriority(1)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.5), lineWidth: 1))
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

private struct DockedPanel: UIViewControllerRepresentable {
    let content: DockContent
    func makeUIViewController(context: Context) -> KeyHostingController<AnyView> {
        let c = KeyHostingController(rootView: content.view); c.onKey = content.onKey
        c.view.backgroundColor = .clear
        return c
    }
    func updateUIViewController(_ c: KeyHostingController<AnyView>, context: Context) { c.onKey = content.onKey }
}

// MARK: - Launcher (personal)

/// The challenge setup: who, and for how long. Keys: 1–7 student, ⏎ start, +/- half a minute, Esc close.
@MainActor final class QuizLauncherModel: ObservableObject {
    @Published var player: String?
    @Published var seconds: Int = max(30, UserDefaults.standard.integer(forKey: "classroom.challengeSeconds") == 0 ? 120 : UserDefaults.standard.integer(forKey: "classroom.challengeSeconds")) {
        didSet { UserDefaults.standard.set(seconds, forKey: "classroom.challengeSeconds") }
    }
    @Published var note: String?
}

/// Q: the timed challenge on a student's own questions. Pick the student and the time; during it the student
/// chooses each question's difficulty, the teacher calls it up and marks the answer — as many as fit in the time.
struct QuizLauncherPanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var model: QuizLauncherModel
    var onStart: () -> Void
    var onClose: () -> Void

    private var campaign: MeadowCampaignSession? { game.campaign }
    private static let presets = [60, 120, 180, 300]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("专属题挑战", systemImage: "timer").font(.title2.bold())
                Text("课程：\(QuizLibrary.shared.active ?? "未选") · \(campaign?.courseIndices.count ?? 0) 题").font(.callout).foregroundStyle(GameTheme.muted)
                Spacer()
                if let c = campaign, !c.quizPortions.isEmpty {
                    Button { game.openQuizPortions() } label: { Label("专属题分配 (\(c.quizPortions.count)份)", systemImage: "person.2.badge.gearshape") }.buttonStyle(GlassIconButtonStyle())
                }
                Button { game.openQuizBank(back: true) } label: { Label("题库", systemImage: "text.book.closed") }.buttonStyle(GlassIconButtonStyle(prominent: campaign?.quizBank.isEmpty == true))
                Button { onClose() } label: { Label("关闭", systemImage: "xmark") }.buttonStyle(GlassIconButtonStyle())
            }
            if let note = model.note { Text(note).font(.caption).foregroundStyle(note.hasPrefix("✓") ? GameTheme.primary : .red) }
            if campaign == nil {
                Label("题库和作答记录存在行程里：先打开行程（电视上的绘本不会被切走）。", systemImage: "info.circle").foregroundStyle(GameTheme.muted)
                HStack {
                    Button { game.restore() } label: { Label("继续上次行程", systemImage: "arrow.clockwise.circle") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                    Text(game.message).font(.caption).foregroundStyle(GameTheme.muted).lineLimit(2)
                }
            } else {
                Text("谁来挑战").font(.headline)
                QuizPlayerChips(game: game, selected: Set([model.player].compactMap { $0 })) { model.player = $0 }
                if let c = campaign, let p = model.player {
                    let left = c.challengeLeft(for: p)
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { d in
                            Text("\(String(repeating: "★", count: d + 1)) 剩 \(left[d]) 题").font(.callout.bold()).foregroundStyle(left[d] > 0 ? GameTheme.ink : GameTheme.muted)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(0.5)))
                        }
                        if left.reduce(0, +) == 0 { Text("这位同学没有专属题（检查题库的“份”和专属题分配）").font(.caption).foregroundStyle(.orange) }
                    }
                }
                Text("挑战时间").font(.headline)
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { sec in
                        let on = model.seconds == sec
                        Button { model.seconds = sec } label: {
                            Text(ClassTimerModel.label(Double(sec))).font(.body.bold()).padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(on ? Color.white : GameTheme.ink)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                        }.buttonStyle(.plain)
                    }
                    Button { model.seconds = max(30, model.seconds - 30) } label: { Image(systemName: "minus") }.buttonStyle(GlassIconButtonStyle())
                    Text(ClassTimerModel.label(Double(model.seconds))).font(.title3.bold()).monospacedDigit().frame(minWidth: 60)
                    Button { model.seconds = min(1800, model.seconds + 30) } label: { Image(systemName: "plus") }.buttonStyle(GlassIconButtonStyle())
                    Spacer()
                    Button { onStart() } label: { Label("开始挑战 (⏎)", systemImage: "play.fill") }
                        .buttonStyle(GlassIconButtonStyle(prominent: true))
                        .disabled(model.player == nil || (model.player.map { campaign?.challengeLeft(for: $0).reduce(0, +) ?? 0 } ?? 0) == 0)
                }
                Text("开始后电视倒计时；学生每题自己选难度（1 ★ / 2 ★★ / 3 ★★★），你调出他那份里对应难度的题，他作答你录入，时间到即停，能做多少算多少。按难度自动发奖励。键盘：1–7 换人，+/− 调时间，回车开始。").font(.caption).foregroundStyle(GameTheme.muted)
            }
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
        .onChange(of: game.campaign == nil) { _, none in if !none, model.player == nil { model.player = game.campaign?.selectedPlayerID } }
    }
}

// MARK: - Timed challenge

@MainActor final class ChallengeModel: ObservableObject {
    enum Phase: Equatable { case picking, question, finished }
    let player: String
    let name: String
    let seconds: Int
    let end: Date
    @Published var phase: Phase = .picking
    @Published var right = 0
    @Published var answered = 0
    @Published var coins = 0
    @Published var score = 0
    @Published var left = [0, 0, 0]
    @Published var note: String?
    /// The answer being marked (question phase).
    @Published var draft: QuizAnswerDraft?
    var questionStart = Date()
    init(player: String, name: String, seconds: Int) {
        self.player = player; self.name = name; self.seconds = seconds; end = Date().addingTimeInterval(Double(seconds))
    }
    var remaining: Double { max(0, end.timeIntervalSinceNow) }
}

/// Teacher side of a challenge: pick the level the student asks for (1/2/3), then mark the answer (⏎ submits);
/// Esc ends early.
struct ChallengePanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var model: ChallengeModel
    var onPick: (Int) -> Void
    var onSubmit: () -> Void
    var onEnd: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "timer").font(.title2).foregroundStyle(GameTheme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.name) · 专属题挑战").font(.title3.bold())
                    Text("答对 \(model.right)/\(model.answered) · +\(model.coins) 金币 · +\(model.score) 积分").font(.caption).foregroundStyle(GameTheme.muted)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let left = model.remaining
                    Text(model.phase == .finished ? "结束" : ClassTimerModel.label(left)).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(left <= 10 ? Color.orange : GameTheme.ink)
                }
                Button { onEnd() } label: { Label(model.phase == .finished ? "关闭 (Esc)" : "结束 (Esc)", systemImage: "stop.circle") }.buttonStyle(GlassIconButtonStyle())
            }
            if let note = model.note { Text(note).font(.callout.bold()).foregroundStyle(.orange) }
            switch model.phase {
            case .picking:
                Text("学生选难度").font(.headline)
                HStack(spacing: 12) {
                    ForEach(1...3, id: \.self) { d in
                        Button { onPick(d) } label: {
                            VStack(spacing: 4) {
                                Text(String(repeating: "★", count: d)).font(.title.bold())
                                Text(["简单", "中等", "困难"][d - 1] + " (\(d))").font(.headline)
                                Text("+\(QuizRewards.baseCoins[d - 1]) 金币 · 剩 \(model.left[d - 1]) 题").font(.caption)
                            }.frame(maxWidth: .infinity).padding(.vertical, 14)
                            .foregroundStyle(model.left[d - 1] > 0 ? GameTheme.ink : GameTheme.muted)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(model.left[d - 1] > 0 ? 0.6 : 0.25)))
                        }.buttonStyle(.plain).disabled(model.left[d - 1] == 0)
                    }
                }
            case .question:
                if let draft = model.draft {
                    ScrollView { QuizAnswerRows(draft: draft) }
                    HStack {
                        Spacer()
                        Text("选好答案即揭晓并发奖").font(.caption).foregroundStyle(GameTheme.muted)
                        Button { onSubmit() } label: { Label("提交 (⏎)", systemImage: "checkmark.seal.fill") }.buttonStyle(GlassIconButtonStyle())
                    }
                }
            case .finished:
                VStack(alignment: .leading, spacing: 6) {
                    Text("挑战结束").font(.title2.bold())
                    Text("答对 \(model.right)/\(model.answered) 题 · 获得 \(model.coins) 金币、\(model.score) 积分").font(.title3)
                }
            }
            Text("键盘：1/2/3 选难度；作答时 D 对 C 错（闪卡）或 A–H 选项、0 不会，选好即揭晓答案并发奖（填了“其他答案”时按回车）；Esc 结束。时间到时正在答的这题不计。").font(.caption).foregroundStyle(GameTheme.muted)
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
    }
}

/// On the TV during a challenge: a banner with the time left and the score, and while the student chooses, the
/// three levels; at the end, the result.
struct ChallengeOverlay: View {
    @ObservedObject var model: ChallengeModel
    let unit: CGFloat
    var showLevels: Bool
    var body: some View {
        VStack(spacing: 18 * unit) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let left = model.remaining
                HStack(spacing: 14 * unit) {
                    Image(systemName: "timer").font(.system(size: 26 * unit, weight: .bold))
                    Text(model.name).font(.system(size: 26 * unit, weight: .heavy, design: .rounded))
                    Text(model.phase == .finished ? "结束" : ClassTimerModel.label(left)).font(.system(size: 34 * unit, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(model.phase != .finished && left <= 10 ? Color.orange : Color.white)
                    Text("✓ \(model.right)/\(model.answered)  +\(model.coins)").font(.system(size: 22 * unit, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(.white).padding(.horizontal, 24 * unit).padding(.vertical, 10 * unit)
                .background(Capsule().fill(Color(red: 0.09, green: 0.35, blue: 0.45).opacity(0.9)))
                .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1.5 * unit))
            }
            .padding(.top, 14 * unit)
            if model.phase == .picking && showLevels {
                VStack(spacing: 16 * unit) {
                    Text("\(model.name)，选一道题的难度").font(.system(size: 34 * unit, weight: .heavy, design: .rounded)).foregroundStyle(GameTheme.ink)
                    HStack(spacing: 18 * unit) {
                        ForEach(1...3, id: \.self) { d in
                            VStack(spacing: 6 * unit) {
                                Text(String(repeating: "★", count: d)).font(.system(size: 40 * unit, weight: .heavy)).foregroundStyle(Color(red: 0.85, green: 0.62, blue: 0.12))
                                Text(["简单", "中等", "困难"][d - 1]).font(.system(size: 26 * unit, weight: .bold, design: .rounded))
                                Text("+\(QuizRewards.baseCoins[d - 1]) 金币").font(.system(size: 18 * unit, weight: .semibold, design: .rounded)).foregroundStyle(GameTheme.muted)
                            }
                            .frame(width: 200 * unit, height: 170 * unit)
                            .foregroundStyle(GameTheme.ink).opacity(model.left[d - 1] > 0 ? 1 : 0.35)
                            .background(RoundedRectangle(cornerRadius: 22 * unit, style: .continuous).fill(Color.white.opacity(0.85)))
                        }
                    }
                }
                .padding(30 * unit)
                .background(RoundedRectangle(cornerRadius: 28 * unit, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.95, green: 0.98, blue: 0.98).opacity(0.94), Color(red: 0.90, green: 0.95, blue: 0.96).opacity(0.9)], startPoint: .top, endPoint: .bottom)))
                .padding(.top, 60 * unit)
            }
            if model.phase == .finished {
                VStack(spacing: 10 * unit) {
                    Text("挑战结束").font(.system(size: 40 * unit, weight: .heavy, design: .rounded))
                    Text("\(model.name) 答对 \(model.right)/\(model.answered) 题").font(.system(size: 30 * unit, weight: .bold, design: .rounded))
                    Text("+\(model.coins) 金币 · +\(model.score) 积分").font(.system(size: 26 * unit, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.74, green: 0.52, blue: 0.12))
                }
                .foregroundStyle(GameTheme.ink).padding(36 * unit)
                .background(RoundedRectangle(cornerRadius: 28 * unit, style: .continuous).fill(Color.white.opacity(0.92)))
                .padding(.top, 80 * unit)
            }
            Spacer()
        }.frame(maxWidth: .infinity)
    }
}

/// Students as chips with their number key; `selected` lights up.
struct QuizPlayerChips: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    let selected: Set<String>
    var marks: [String: String] = [:]
    var tap: (String) -> Void
    var body: some View {
        FlowRow(spacing: 8) {
            ForEach(game.campaign?.engine.state.players ?? [], id: \.id) { u in
                let on = selected.contains(u.id)
                Button { KeyHostingController<EmptyView>.endEditing(); tap(u.id) } label: {
                    HStack(spacing: 6) {
                        Text("\(game.seatNumber(u.id))").font(.caption.bold()).foregroundStyle(.white).frame(width: 22, height: 22).background(Circle().fill(on ? Color.white.opacity(0.3) : GameTheme.primary))
                        Text(u.shortName).font(.body.weight(.semibold))
                        if let m = marks[u.id] { Text(m).font(.caption.bold()) }
                    }.padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(on ? Color.white : GameTheme.ink)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                }.buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Class question (shared bank, the teacher hands out rewards)

/// One shared question to the whole class. Pick who answered (1–7, several at once), what they said (A–H; 0 不会),
/// ⏎ sends: right → the reward and a "答对" record, wrong → the participation prize and "答错"; the TV reveals the
/// answer at the same moment. Esc reveals without sending.
@MainActor final class ClassQuizModel: ObservableObject {
    @Published var players = Set<String>()
    @Published var sent: [(name: String, right: Bool, coins: Int)] = []
    @Published var note: String?
}

struct ClassQuizPanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var model: ClassQuizModel
    @ObservedObject var draft: QuizAnswerDraft
    @ObservedObject var reward: QuizManualReward
    let start: Date
    var onSend: () -> Void
    var onEnd: () -> Void
    var onOther: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.3.fill").font(.title2).foregroundStyle(GameTheme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("全班题").font(.title3.bold())
                    Text("\(draft.question.type.title) \(MeadowQuizCard.stars(draft.question)) · 老师发奖").font(.caption).foregroundStyle(GameTheme.muted)
                }
                Spacer()
                if model.sent.isEmpty { Button { onOther() } label: { Label("换一题 (空格)", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(GlassIconButtonStyle()) }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(Int(context.date.timeIntervalSince(start)))s").font(.system(size: 18, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(GameTheme.muted)
                }
            }
            Text("谁回答了（1–7，可多选）").font(.headline)
            QuizPlayerChips(game: game, selected: model.players, marks: marks) { id in
                if model.players.contains(id) { model.players.remove(id) } else { model.players.insert(id) }
            }
            ScrollView { QuizAnswerRows(draft: draft) }
            QuizRewardFields(reward: reward)
            if !model.sent.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(Array(model.sent.enumerated()), id: \.offset) { _, s in
                        Text("\(s.right ? "✓" : "✗") \(s.name) +\(s.coins)").font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(s.right ? Color.green : Color.red)
                            .background(Capsule().fill((s.right ? Color.green : Color.red).opacity(0.12)))
                    }
                }
            }
            if let note = model.note { Text(note).font(.caption).foregroundStyle(.red) }
            HStack {
                Button { onEnd() } label: { Label("只揭晓 (Esc)", systemImage: "eye") }.buttonStyle(GlassIconButtonStyle())
                Spacer()
                let right = draft.allRight
                Text(model.players.isEmpty ? "先选人" : "\(model.players.count) 人 · \(right ? "答对 +\(reward.amount(right: true))" : "答错 · 参与奖 +\(reward.amount(right: false))")")
                    .font(.callout.bold()).foregroundStyle(right ? Color.green : GameTheme.muted)
                Button { onSend() } label: { Label("揭晓并发奖 (⏎)", systemImage: "paperplane.fill") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                    .disabled(model.players.isEmpty || draft.answered == 0)
            }
            Text("键盘：1–7 选人，A–H 选答案，0 不会，⌫ 撤回，回车揭晓答案、同时发奖并记录；Esc 只揭晓不发奖。").font(.caption).foregroundStyle(GameTheme.muted)
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
    }
    private var marks: [String: String] {
        var m: [String: String] = [:]
        for s in model.sent { if let id = game.campaign?.engine.state.players.first(where: { $0.shortName == s.name })?.id { m[id] = s.right ? "✓" : "✗" } }
        return m
    }
}

// MARK: - Flash-card practice (fixed entry, endless)

@MainActor final class PracticeModel: ObservableObject {
    @Published var player: String
    @Published var right = 0
    @Published var total = 0
    @Published var waiting = false
    /// The whole class answers the same card; the teacher picks who answered, then D / C.
    @Published var classwide = false
    @Published var players = Set<String>()
    @Published var note: String?
    enum Order: String { case sequential, shuffled }
    /// In bank order or shuffled; remembered on this device.
    @Published var order: Order = Order(rawValue: UserDefaults.standard.string(forKey: "classroom.flashOrder") ?? "") ?? .sequential {
        didSet { UserDefaults.standard.set(order.rawValue, forKey: "classroom.flashOrder") }
    }
    /// The cards (bank indices) in the order they come, and where we are.
    @Published var deck: [Int] = []
    @Published var cursor = 0
    /// This round's marks per card (bank index → right), for the card list.
    @Published var results: [Int: Bool] = [:]
    @Published var showList = false
    init(player: String, classwide: Bool = false) { self.player = player; self.classwide = classwide }
}

/// K from anywhere: flash cards for one student, one after another. D right / C wrong records it and moves on;
/// 1–7 switches student; Esc ends. Recorded for the report (错词), no reward. A switches to the whole class: one card
/// for everybody, 1–7 picks who answered (several at once), D / C records it for them, reveals and moves on.
struct PracticePanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var model: PracticeModel
    var onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("闪卡", systemImage: "rectangle.on.rectangle.angled").font(.title2.bold()).fixedSize()
                Picker("", selection: Binding(get: { model.classwide }, set: { game.setPracticeClasswide($0) })) {
                    Text("个人").tag(false); Text("全班 (A)").tag(true)
                }.pickerStyle(.segmented).frame(width: 170)
                Text("本轮 \(model.right)/\(model.total)").font(.callout.bold()).foregroundStyle(GameTheme.muted)
                Spacer()
                Button { onClose() } label: { Label("结束 (Esc)", systemImage: "xmark.circle") }.buttonStyle(GlassIconButtonStyle())
            }
            if model.classwide {
                Text("谁回答了（1–7，可多选）").font(.headline)
                QuizPlayerChips(game: game, selected: model.players) { id in game.togglePracticePlayer(id) }
            } else {
                QuizPlayerChips(game: game, selected: [model.player]) { id in game.switchPractice(to: id) }
            }
            if let note = model.note { Text(note).font(.caption.bold()).foregroundStyle(.orange) }
            HStack(spacing: 10) {
                Picker("", selection: Binding(get: { model.order }, set: { game.setPracticeOrder($0) })) {
                    Text("顺序").tag(PracticeModel.Order.sequential); Text("乱序").tag(PracticeModel.Order.shuffled)
                }.pickerStyle(.segmented).frame(width: 130)
                Button { game.stepPractice(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(GlassIconButtonStyle()).disabled(model.waiting || model.deck.isEmpty)
                Text(model.deck.isEmpty ? "0/0" : "第 \(model.cursor + 1)/\(model.deck.count) 张").font(.callout.bold()).monospacedDigit()
                Button { game.stepPractice(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(GlassIconButtonStyle()).disabled(model.waiting || model.deck.isEmpty)
                Spacer()
                Button { model.showList.toggle() } label: { Label(model.showList ? "收起列表" : "选卡", systemImage: "list.bullet.rectangle") }.buttonStyle(GlassIconButtonStyle(prominent: model.showList))
            }
            if model.showList, let c = game.campaign {
                // Every card of the deck: tap one to show it now (✓ / ✗ = marked this round).
                ScrollView {
                    FlowRow(spacing: 6) {
                        ForEach(Array(model.deck.enumerated()), id: \.offset) { pos, index in
                            let current = pos == model.cursor, mark = model.results[index]
                            Button { game.pickPracticeCard(pos) } label: {
                                HStack(spacing: 4) {
                                    Text("\(pos + 1)").font(.caption2.bold()).foregroundStyle(current ? Color.white.opacity(0.8) : GameTheme.muted)
                                    Text(c.quizBank.indices.contains(index) ? c.quizBank[index].prompt : "?").font(.callout.weight(.semibold)).lineLimit(1)
                                    if let mark { Image(systemName: mark ? "checkmark" : "xmark").font(.caption.bold()).foregroundStyle(current ? .white : (mark ? Color.green : Color.red)) }
                                }.padding(.horizontal, 9).padding(.vertical, 5)
                                .foregroundStyle(current ? Color.white : GameTheme.ink)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(current ? GameTheme.primary : Color.white.opacity(0.55)))
                            }.buttonStyle(.plain).disabled(model.waiting)
                        }
                    }
                }.frame(maxHeight: 200)
            }
            if let live = game.quiz, live.mode == .practice {
                VStack(alignment: .leading, spacing: 8) {
                    Text("正面：\(live.question.prompt)").font(.title2.bold())
                    let part = live.question.parts[0]
                    Text("背面：\(part.options[part.answer])").font(.title3.bold()).foregroundStyle(GameTheme.primary)
                    HStack(spacing: 12) {
                        Button { game.practiceAnswer(part.answer) } label: {
                            Label("对 (D)", systemImage: "checkmark.circle.fill").font(.title3.bold()).frame(minWidth: 120).padding(.vertical, 10)
                                .foregroundStyle(.green).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.green.opacity(0.12)))
                        }.buttonStyle(.plain).disabled(model.waiting)
                        Button { game.practiceAnswer(nil) } label: {
                            Label("错 (C)", systemImage: "xmark.circle.fill").font(.title3.bold()).frame(minWidth: 120).padding(.vertical, 10)
                                .foregroundStyle(.red).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red.opacity(0.12)))
                        }.buttonStyle(.plain).disabled(model.waiting)
                    }
                }
            } else {
                Label(model.classwide ? "当前课程没有闪卡。" : "题库里没有这位同学能练的闪卡。", systemImage: "tray").foregroundStyle(GameTheme.muted)
            }
            Text(model.classwide
                 ? "键盘：1–7 选回答的同学，D 对、C 错：记录、揭晓背面并自动下一张；空格跳过这张；←/→ 上一张/下一张，O 顺序/乱序，A 切回个人，Esc 结束。只记录、不发奖励，错词进报告。"
                 : "键盘：D 对、C 错，记录后自动下一张；←/→ 上一张/下一张，O 顺序/乱序；1–7 换人，A 切到全班，Esc 结束。只记录、不发奖励，错词进报告。").font(.caption).foregroundStyle(GameTheme.muted)
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
    }
}

// MARK: - Exclusive portions (whose questions are whose)

/// The bank's pre-cut portions of exclusive questions: one row per portion, tap a student to give it to them (tap
/// again: nobody). Until set, portion n belongs to student n.
struct QuizPortionPanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("专属题分配", systemImage: "person.2.badge.gearshape").font(.title2.bold())
                Spacer()
                Button { onClose() } label: { Label("完成 (Esc)", systemImage: "checkmark") }.buttonStyle(GlassIconButtonStyle(prominent: true))
            }
            Text("题库里每一“份”是一组专属题。点同学把这一份给他，再点一次取消（这一份就不出给任何人）。没改过时，第 n 份默认给第 n 位同学。").font(.caption).foregroundStyle(GameTheme.muted)
            if let c = game.campaign {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(c.quizPortions, id: \.name) { portion in
                            let owner = c.portionOwner(portion.name)
                            // Questions of this portion its owner has not answered yet.
                            let answered = Set(c.quizLog.filter { $0.player == owner }.map(\.question))
                            let left = c.quizBank.indices.filter { c.quizBank[$0].portion == portion.name && !answered.contains($0) }.count
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("第\(portion.name)份").font(.headline)
                                    Text(owner == nil ? "\(portion.count) 题" : "剩 \(left)/\(portion.count) 题").font(.caption).foregroundStyle(GameTheme.muted)
                                }.frame(width: 72, alignment: .leading)
                                QuizPlayerChips(game: game, selected: Set([owner].compactMap { $0 })) { id in
                                    try? c.assignQuizPortion(portion.name, to: owner == id ? nil : id)
                                    game.revision += 1
                                }
                                if owner == nil { Text("未分配").font(.caption.bold()).foregroundStyle(.orange) }
                            }
                            .padding(10).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
    }
}

// MARK: - Question bank (app level, top bar)

/// The teacher's question bank, kept by the app and split into courses (one per imported file, named after it).
/// The teacher picks the current course by hand; the open trip deals only from it. Trips (a fresh map every
/// lesson) only keep the questions they used and the answers, for rewards and the report.
@MainActor final class QuizLibrary: ObservableObject {
    static let shared = QuizLibrary()
    @Published private(set) var questions: [QuizQuestion] = []
    @Published private(set) var active: String? = UserDefaults.standard.string(forKey: "classroom.quizCourse") {
        didSet { UserDefaults.standard.set(active, forKey: "classroom.quizCourse") }
    }
    static let unsorted = "未分类"
    private var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClassroomMeadow/quiz-bank.json")
    }
    private init() {
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([QuizQuestion].self, from: data) {
            // Questions imported before courses existed go to "未分类".
            questions = list.map { q in var q = q; if q.course == nil { q.course = Self.unsorted }; return q }
        }
        if let active, !courses.contains(active) { self.active = courses.first }
        if active == nil { active = courses.first }
    }
    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(questions).write(to: url, options: .atomic)
    }
    /// Course names in the order they were first imported.
    var courses: [String] {
        var seen = Set<String>(); return questions.compactMap { q in q.course.flatMap { seen.insert($0).inserted ? $0 : nil } }
    }
    func questions(of course: String) -> [QuizQuestion] { questions.filter { $0.course == course } }
    var activeQuestions: [QuizQuestion] { active.map(questions(of:)) ?? [] }
    /// Adds a course (a file with the same name replaces that course) and makes it the current one.
    func add(course: String, _ list: [QuizQuestion]) {
        let tagged = list.map { q in var q = q; q.course = course; return q }
        questions.removeAll { $0.course == course }
        questions += tagged; save(); active = course
    }
    func select(_ course: String?) { active = course }
    /// Adds one card to a course in place (a flash card with the same front there is replaced); the course becomes
    /// current only when none is.
    func addCard(_ card: QuizQuestion, to course: String) {
        var card = card; card.course = course
        if let i = questions.firstIndex(where: { $0.course == course && $0.type == .flashcard && $0.prompt.lowercased() == card.prompt.lowercased() }) { questions[i] = card }
        else if let last = questions.lastIndex(where: { $0.course == course }) { questions.insert(card, at: last + 1) }
        else { questions.append(card) }
        save()
        if active == nil { active = course }
    }
    func remove(course: String) {
        questions.removeAll { $0.course == course }; save()
        if active == course { active = courses.first }
    }
    func rename(_ course: String, to name: String) {
        let name = String(name.trimmingCharacters(in: .whitespaces).prefix(120))
        guard !name.isEmpty, name != course, !courses.contains(name) else { return }
        questions = questions.map { q in var q = q; if q.course == course { q.course = name }; return q }; save()
        if active == course { active = name }
    }
    static func sample() throws -> [QuizQuestion] {
        guard let url = Bundle.main.url(forResource: "quiz-sample", withExtension: "txt") else { throw GameError("示例题库缺失。") }
        return try QuizBankParser.parse(Data(contentsOf: url))
    }
    /// The course name for an imported file: its name without the extension.
    static func courseName(_ url: URL) -> String { String(url.deletingPathExtension().lastPathComponent.prefix(120)) }
}

/// Top bar course switch: the current course's name; the menu lists every course.
struct QuizCourseMenu: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var library = QuizLibrary.shared
    var body: some View {
        Menu {
            ForEach(library.courses, id: \.self) { c in
                Button { game.selectQuizCourse(c) } label: {
                    Label("\(c)（\(library.questions(of: c).count) 题）", systemImage: library.active == c ? "checkmark" : "book.closed")
                }
            }
            Divider()
            Button { game.openQuizBank() } label: { Label("题库管理…", systemImage: "text.book.closed") }
        } label: {
            Label(library.active ?? "题库", systemImage: "text.book.closed").lineLimit(1)
        } primaryAction: { game.openQuizBank() }
    }
}

/// "题库": the courses (import a file = a course named after it), which one is current, rename / delete.
struct QuizBankPanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var library = QuizLibrary.shared
    var onPortions: () -> Void
    var onClose: () -> Void
    @State private var importing = false
    @State private var note: String?
    @State private var renaming: String?
    @State private var newName = ""

    private func summary(_ list: [QuizQuestion]) -> String {
        let kinds = QuizKind.allCases.compactMap { k -> String? in let n = list.filter { $0.type == k }.count; return n > 0 ? "\(k.title) \(n)" : nil }
        let portions = Set(list.compactMap(\.portion)).count
        return kinds.joined(separator: " · ") + (portions > 0 ? " · 专属 \(portions) 份" : "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("题库", systemImage: "text.book.closed.fill").font(.title2.bold())
                Spacer()
                Button { importing = true } label: { Label("导入课程", systemImage: "square.and.arrow.down") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                Button { loadSample() } label: { Label("示例题库", systemImage: "text.book.closed") }.buttonStyle(GlassIconButtonStyle())
                Button { onClose() } label: { Label("完成 (Esc)", systemImage: "checkmark") }.buttonStyle(GlassIconButtonStyle())
            }
            Text("每导入一个文件就是一门课（用文件名命名，同名再导入会更新这门课）。点一门课把它设为当前课程：答题、全班题、闪卡和地图答题点只出这门课的题。").font(.caption).foregroundStyle(GameTheme.muted)
            if let note { Text(note).font(.callout.bold()).foregroundStyle(note.hasPrefix("✓") ? GameTheme.primary : .red) }
            ScrollView {
                VStack(spacing: 8) {
                    if library.courses.isEmpty { Label("还没有课程，点“导入课程”或“示例题库”。", systemImage: "tray").foregroundStyle(GameTheme.muted).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(library.courses, id: \.self) { c in courseRow(c) }
                }
            }
            if let c = game.campaign, !c.quizPortions.isEmpty {
                Button { onPortions() } label: { Label("当前课程的专属题分配 (\(c.quizPortions.count)份)", systemImage: "person.2.badge.gearshape") }.buttonStyle(GlassIconButtonStyle())
            }
            Text("格式：每题空一行；`份：1` 为第 1 份专属题，不写“份”的是公用题。详见 docs/question-bank-format.md。").font(.caption).foregroundStyle(GameTheme.muted)
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .json, .text], allowsMultipleSelection: true) { result in
            do {
                var names: [String] = []
                for url in try result.get() {
                    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let list = try QuizBankParser.parse(Data(contentsOf: url))
                    let name = QuizLibrary.courseName(url)
                    library.add(course: name, list); names.append("\(name)（\(list.count) 题）")
                }
                game.applyQuizCourse()
                note = "✓ 已导入：" + names.joined(separator: "、") + "，当前课程：\(library.active ?? "")"
            } catch { note = "导入失败：\(error.localizedDescription)" }
        }
    }
    @ViewBuilder private func courseRow(_ c: String) -> some View {
        let on = library.active == c, list = library.questions(of: c)
        HStack(spacing: 10) {
            Button { game.selectQuizCourse(c) } label: {
                HStack(spacing: 10) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(on ? GameTheme.primary : GameTheme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c).font(.headline).foregroundStyle(GameTheme.ink).lineLimit(1)
                        Text("\(list.count) 题 · " + summary(list)).font(.caption).foregroundStyle(GameTheme.muted).lineLimit(1)
                    }
                    Spacer()
                    if on { Text("当前课程").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(GameTheme.primary)) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if renaming == c {
                ClassroomTextField(placeholder: c, text: $newName, limit: 60, onSubmit: { library.rename(c, to: newName); renaming = nil; game.applyQuizCourse() }).frame(width: 160, height: 30)
                    .padding(.horizontal, 8).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button { library.rename(c, to: newName); renaming = nil; game.applyQuizCourse() } label: { Image(systemName: "checkmark") }.buttonStyle(GlassIconButtonStyle())
            } else {
                Button { newName = c; renaming = c } label: { Label("改名", systemImage: "pencil") }.buttonStyle(GlassIconButtonStyle())
            }
            Button(role: .destructive) { library.remove(course: c); game.applyQuizCourse(); note = "✓ 已删除“\(c)”（已作答的记录保留在行程里）" } label: { Label("删除", systemImage: "trash") }.buttonStyle(GlassIconButtonStyle())
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(on ? 0.7 : 0.4)))
    }
    private func loadSample() {
        do { let list = try QuizLibrary.sample(); library.add(course: "示例题库", list); game.applyQuizCourse(); note = "✓ 已载入示例题库（\(list.count) 题），并设为当前课程" }
        catch { note = "载入失败：\(error.localizedDescription)" }
    }
}
