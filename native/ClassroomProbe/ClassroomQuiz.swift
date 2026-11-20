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
    /// The question came up again with its options in another order: picks are mapped back for the record.
    var shuffle: QuizShuffle? = nil
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
            let card = MeadowQuizCard.present(in: box, question: quiz.question, player: who, place: quiz.mode == .practice ? "闪卡练习" : quiz.mode == .challenge ? "个人挑战" : quiz.place, start: quiz.start, mode: quiz.mode, deadline: quiz.deadline)
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

// MARK: - How questions are drawn

/// The teacher's way of choosing the next question (individual challenge and class questions alike), kept on this
/// device: at random from the whole course, at random from one difficulty, or picked by hand from the list.
@MainActor final class QuizDrawSettings: ObservableObject {
    enum Mode: String, CaseIterable {
        case random, difficulty, manual
        var title: String { switch self { case .random: return "全随机"; case .difficulty: return "按难度随机"; case .manual: return "老师点选" } }
        var icon: String { switch self { case .random: return "shuffle"; case .difficulty: return "star.leadinghalf.filled"; case .manual: return "hand.point.up.left.fill" } }
    }
    static let shared = QuizDrawSettings()
    @Published var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "classroom.quizDraw") ?? "") ?? .random {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "classroom.quizDraw") }
    }
    @Published var difficulty: Int = min(3, max(1, UserDefaults.standard.integer(forKey: "classroom.quizDrawLevel"))) {
        didSet { UserDefaults.standard.set(difficulty, forKey: "classroom.quizDrawLevel") }
    }
    /// nil = the teacher picks by hand.
    var draw: QuizDraw? { switch mode { case .random: return .random; case .difficulty: return .difficulty(difficulty); case .manual: return nil } }
}

/// 出题方式: 全随机 / 按难度随机 (★ ★★ ★★★, with how many questions each has) / 老师点选.
struct QuizDrawBar: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var settings = QuizDrawSettings.shared
    var body: some View {
        HStack(spacing: 6) {
            ForEach(QuizDrawSettings.Mode.allCases, id: \.self) { m in
                chip(m.title, icon: m.icon, on: settings.mode == m) { settings.mode = m }
            }
            if settings.mode == .difficulty {
                Rectangle().fill(GameTheme.muted.opacity(0.3)).frame(width: 1, height: 22).padding(.horizontal, 2)
                ForEach(1...3, id: \.self) { d in
                    chip(String(repeating: "★", count: d) + " \(game.campaign?.quizPool(.difficulty(d)).count ?? 0)", icon: nil, on: settings.difficulty == d) { settings.difficulty = d }
                }
            }
        }
    }
    private func chip(_ title: String, icon: String?, on: Bool, tap: @escaping () -> Void) -> some View {
        Button { KeyHostingController<EmptyView>.endEditing(); tap() } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption.bold()) }
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(on ? Color.white : GameTheme.ink)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
        }.buttonStyle(.plain)
    }
}

/// 老师点选: the course's questions under difficulty tabs (or all of them). Tap a row to ask it; the eye shows the
/// whole question (options, the right answer) first.
struct QuizPicker: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    /// Whose answers mark the rows (nil = anyone in the class).
    var player: String? = nil
    var onPick: (Int) -> Void
    @State private var tab = 0
    @State private var open: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let c = game.campaign {
                HStack(spacing: 6) {
                    ForEach(0...3, id: \.self) { t in
                        let on = tab == t
                        Button { tab = t; open = nil } label: {
                            Text((t == 0 ? "全部" : String(repeating: "★", count: t)) + " \(c.quizPool(t == 0 ? .random : .difficulty(t)).count)")
                                .font(.callout.bold()).padding(.horizontal, 12).padding(.vertical, 6)
                                .foregroundStyle(on ? Color.white : GameTheme.ink)
                                .background(Capsule().fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Text("点题目出题 · 👁 预览").font(.caption).foregroundStyle(GameTheme.muted)
                }
                let pool = c.quizPool(tab == 0 ? .random : .difficulty(tab))
                if pool.isEmpty { Label("这一档没有题。", systemImage: "tray").foregroundStyle(GameTheme.muted) }
                ScrollView {
                    LazyVStack(spacing: 6) { ForEach(pool, id: \.self) { i in row(c, i) } }
                }
            }
        }
    }
    @ViewBuilder private func row(_ c: MeadowCampaignSession, _ i: Int) -> some View {
        let q = c.quizBank[i]
        let asked = c.quizLog.filter { $0.question == i && $0.practice != true && (player == nil || $0.player == player) }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { KeyHostingController<EmptyView>.endEditing(); onPick(i) } label: {
                    HStack(spacing: 8) {
                        Text(String(repeating: "★", count: max(1, min(3, q.difficulty ?? 1)))).font(.caption.bold()).foregroundStyle(Color(red: 0.85, green: 0.6, blue: 0.12)).frame(width: 34, alignment: .leading)
                        Text(q.type.title).font(.caption.bold()).foregroundStyle(GameTheme.primary)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(GameTheme.primary.opacity(0.12)))
                        Text(q.type == .flashcard ? q.prompt : QuizReport.summary(q)).font(.callout).foregroundStyle(GameTheme.ink).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        if asked > 0 { Text(player == nil ? "已出 \(asked)" : "已答 \(asked)").font(.caption2.bold()).foregroundStyle(GameTheme.muted) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { open = open == i ? nil : i } label: { Image(systemName: open == i ? "eye.fill" : "eye") }.buttonStyle(GlassIconButtonStyle())
            }
            if open == i { QuizPreview(question: q).padding(.leading, 42) }
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(open == i ? 0.75 : 0.45)))
    }
}

/// A whole question as the teacher sees it before asking: options with the right one marked.
struct QuizPreview: View {
    let question: QuizQuestion
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch question.type {
            case .flashcard:
                Text("正面：\(question.prompt)").font(.callout.bold())
                Text("背面：\(question.parts.first.map { $0.options[$0.answer] } ?? "")").font(.callout).foregroundStyle(Color.green)
            case .reading:
                Text(question.passage ?? question.prompt).font(.caption).foregroundStyle(GameTheme.ink).lineLimit(8)
                ForEach(Array(question.parts.enumerated()), id: \.offset) { k, p in options(p, label: "\(k + 1). \(p.prompt ?? "")") }
            case .fill:
                Text(QuizReport.summary(question)).font(.callout.bold())
                ForEach(Array(question.parts.enumerated()), id: \.offset) { k, p in options(p, label: "（\(k + 1)）") }
            case .choice:
                Text(question.prompt).font(.callout.bold())
                options(question.parts[0], label: nil)
            }
            if let e = question.explanation { Text("解析：\(e)").font(.caption).foregroundStyle(GameTheme.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func options(_ p: QuizItem, label: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label { Text(label).font(.caption.bold()) }
            FlowRow(spacing: 6) {
                ForEach(Array(p.options.enumerated()), id: \.offset) { o, text in
                    Text("\(MeadowQuizCard.letters.indices.contains(o) ? MeadowQuizCard.letters[o] : "") \(text)\(o == p.answer ? " ✓" : "")")
                        .font(.caption.weight(o == p.answer ? .bold : .regular))
                        .foregroundStyle(o == p.answer ? Color.green : GameTheme.ink)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill((o == p.answer ? Color.green : Color.white).opacity(o == p.answer ? 0.14 : 0.5)))
                }
            }
        }
    }
}

// MARK: - Launcher (individual challenge)

/// The challenge setup: who, how questions are drawn, and for how long. Keys: 1–7 student, ⏎ start, +/- half a
/// minute, Esc close.
@MainActor final class QuizLauncherModel: ObservableObject {
    @Published var player: String?
    @Published var seconds: Int = max(30, UserDefaults.standard.integer(forKey: "classroom.challengeSeconds") == 0 ? 120 : UserDefaults.standard.integer(forKey: "classroom.challengeSeconds")) {
        didSet { UserDefaults.standard.set(seconds, forKey: "classroom.challengeSeconds") }
    }
    @Published var note: String?
}

/// Q: a timed challenge for one student on the course's questions, drawn the teacher's way.
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
                Label("个人挑战", systemImage: "timer").font(.title2.bold())
                Text("课程：\(QuizLibrary.shared.active ?? "未选") · \(campaign?.courseIndices.count ?? 0) 题").font(.callout).foregroundStyle(GameTheme.muted)
                Spacer()
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
                Text("出题方式").font(.headline)
                QuizDrawBar(game: game)
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
                        .disabled(model.player == nil || campaign?.courseIndices.isEmpty != false)
                }
                Text("开始后电视倒计时。全随机、按难度随机：答完自动抽下一题（这位同学没答过的优先，都答过才会重复；重复的选择题、填空题会打乱选项）；老师点选：每题从题单里点。学生口头作答你录入，选好即揭晓并按难度发奖，时间到即停。键盘：1–7 换人，+/− 调时间，回车开始。").font(.caption).foregroundStyle(GameTheme.muted)
            }
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
        .onChange(of: game.campaign == nil) { _, none in if !none, model.player == nil { model.player = game.campaign?.selectedPlayerID } }
    }
}

// MARK: - Timed challenge

@MainActor final class ChallengeModel: ObservableObject {
    /// picking: between questions, the teacher chooses (老师点选, or a draw that found nothing).
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
    @Published var note: String?
    /// The answer being marked (question phase).
    @Published var draft: QuizAnswerDraft?
    var questionStart = Date()
    init(player: String, name: String, seconds: Int) {
        self.player = player; self.name = name; self.seconds = seconds; end = Date().addingTimeInterval(Double(seconds))
    }
    var remaining: Double { max(0, end.timeIntervalSinceNow) }
}

/// Teacher side of a challenge: the question's answer (picked = revealed and paid), then the next question the
/// chosen way; Esc ends early.
struct ChallengePanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var model: ChallengeModel
    @ObservedObject var settings = QuizDrawSettings.shared
    var onAsk: (Int) -> Void
    var onNext: () -> Void
    var onSkip: () -> Void
    var onSubmit: () -> Void
    var onEnd: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "timer").font(.title2).foregroundStyle(GameTheme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.name) · 个人挑战").font(.title3.bold())
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
            if model.phase != .finished { QuizDrawBar(game: game) }
            if let note = model.note { Text(note).font(.callout.bold()).foregroundStyle(.orange) }
            switch model.phase {
            case .picking:
                if settings.mode == .manual {
                    QuizPicker(game: game, player: model.player, onPick: onAsk)
                } else {
                    HStack {
                        Text("按“\(settings.mode.title)\(settings.mode == .difficulty ? " " + String(repeating: "★", count: settings.difficulty) : "")”出下一题").font(.headline)
                        Spacer()
                        Button { onNext() } label: { Label("出下一题 (⏎)", systemImage: "arrow.right.circle.fill") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                    }
                }
            case .question:
                if let draft = model.draft {
                    ScrollView { QuizAnswerRows(draft: draft) }
                    HStack {
                        Button { onSkip() } label: { Label(settings.mode == .manual ? "重新选题 (空格)" : "换一题 (空格)", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(GlassIconButtonStyle())
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
            Text("键盘：作答时 D 对 C 错（闪卡）或 A–H 选项、0 不会，选好即揭晓并发奖（填了“其他答案”时按回车）；空格换一题；等下一题时回车出题、1/2/3 按该难度出、R 全随机出；Esc 结束。时间到时正在答的这题不计。").font(.caption).foregroundStyle(GameTheme.muted)
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
    }
}

/// On the TV during a challenge: a banner with the time left and the score; at the end, the result.
struct ChallengeOverlay: View {
    @ObservedObject var model: ChallengeModel
    let unit: CGFloat
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

// MARK: - Class question (the teacher hands out rewards)

/// One question to the whole class. Pick who answered (1–7, several at once), what they said (A–H; 0 不会),
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
                if model.sent.isEmpty { Button { onOther() } label: { Label(QuizDrawSettings.shared.mode == .manual ? "重新选题 (空格)" : "换一题 (空格)", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(GlassIconButtonStyle()) }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(Int(context.date.timeIntervalSince(start)))s").font(.system(size: 18, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(GameTheme.muted)
                }
            }
            if model.sent.isEmpty { QuizDrawBar(game: game) }
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

/// ⇧Q with 老师点选 (or 重新选题): choose the class question from the list; with a random way, draw one.
struct ClassQuizPickPanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var settings = QuizDrawSettings.shared
    var onPick: (Int) -> Void
    var onDraw: () -> Void
    var onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.3.fill").font(.title2).foregroundStyle(GameTheme.primary)
                Text("全班题 · 选题").font(.title3.bold())
                Text("课程：\(QuizLibrary.shared.active ?? "未选")").font(.caption).foregroundStyle(GameTheme.muted)
                Spacer()
                Button { onClose() } label: { Label("关闭 (Esc)", systemImage: "xmark") }.buttonStyle(GlassIconButtonStyle())
            }
            QuizDrawBar(game: game)
            if settings.mode == .manual {
                QuizPicker(game: game, onPick: onPick)
            } else {
                HStack {
                    Text("按“\(settings.mode.title)\(settings.mode == .difficulty ? " " + String(repeating: "★", count: settings.difficulty) : "")”抽一题（全班没出过的优先）").font(.headline)
                    Spacer()
                    Button { onDraw() } label: { Label("抽一题 (⏎)", systemImage: "shuffle") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                }
                Spacer()
            }
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
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
    /// The flash card with this front in the course, if there is one (fronts match without case).
    func card(front: String, in course: String) -> QuizQuestion? {
        questions.first { $0.course == course && $0.type == .flashcard && $0.prompt.lowercased() == front.lowercased() }
    }
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
    var onClose: () -> Void
    @State private var importing = false
    @State private var note: String?
    @State private var renaming: String?
    @State private var newName = ""

    private func summary(_ list: [QuizQuestion]) -> String {
        let kinds = QuizKind.allCases.compactMap { k -> String? in let n = list.filter { $0.type == k }.count; return n > 0 ? "\(k.title) \(n)" : nil }
        let levels = (1...3).compactMap { d -> String? in let n = list.filter { ($0.difficulty ?? 1) == d }.count; return n > 0 ? String(repeating: "★", count: d) + " \(n)" : nil }
        return (kinds + levels).joined(separator: " · ")
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
            Text("格式：每题空一行，写明类型与难度；全部题目是一套题库，个人挑战与全班题都从这里出。详见 docs/question-bank-format.md。").font(.caption).foregroundStyle(GameTheme.muted)
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
