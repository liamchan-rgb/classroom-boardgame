import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ClassroomGameCore
import MeadowWorldSupport

/// A quiz on screen. Shown in the TV overlays (over the game, the picture book and any panel) and in the teacher's
/// preview; `attempt` is set once the teacher submits.
/// A clock the quiz card reads (the same object on the TV and in the preview).
struct QuizCountdown: Equatable {
    let read: () -> Double
    let id = UUID()
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}
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
    /// Challenge: the card's clock shows the challenge's time left (which stops while no question is being
    /// answered) instead of the question's own limit.
    var countdown: QuizCountdown?
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

/// Over the teacher's preview while an answer is showing: a tap anywhere ends the reveal (like Esc).
struct QuizRevealTapCatcher: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var body: some View {
        if game.quiz?.attempt != nil {
            Color.clear.contentShape(Rectangle()).onTapGesture { game.skipQuizReveal() }
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
            let card = MeadowQuizCard.present(in: box, question: quiz.question, player: who, place: quiz.mode == .practice ? "闪卡练习" : quiz.mode == .challenge ? "个人挑战" : quiz.place, start: quiz.start, mode: quiz.mode, countdown: quiz.countdown?.read)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(QuizDrawSettings.Mode.allCases, id: \.self) { m in
                    chip(m.title, icon: m.icon, on: settings.mode == m) { settings.mode = m }
                }
            }
            if settings.mode == .difficulty {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { d in
                        chip(String(repeating: "★", count: d) + " \(game.campaign?.quizPool(.difficulty(d)).count ?? 0) 题", icon: nil, on: settings.difficulty == d) { settings.difficulty = d }
                    }
                }
            }
        }
    }
    /// "从全部题里随机" / "从 ★★ 里随机".
    static func source(_ settings: QuizDrawSettings) -> String {
        settings.mode == .difficulty ? "从 " + String(repeating: "★", count: settings.difficulty) + " 里随机" : "从全部题里随机"
    }
    private func chip(_ title: String, icon: String?, on: Bool, tap: @escaping () -> Void) -> some View {
        Button { KeyHostingController<EmptyView>.endEditing(); tap() } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption.bold()) }
                Text(title).font(.callout.weight(.semibold)).lineLimit(1).fixedSize()
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
                // Tabs 0 全部, 1–3 by difficulty, 4 未考察, 5 有错 (each list worked out once per update).
                let pools = Self.pools(c, player: player)
                HStack(spacing: 6) {
                    ForEach([0, 1, 2, 3], id: \.self) { t in tabButton(t, pools[t].count) }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    ForEach([4, 5], id: \.self) { t in tabButton(t, pools[t].count) }
                    Spacer(minLength: 0)
                }
                Text("点题目即出这一题，点 👁 先预览整题；随机出题时先出未考察和有错的题").font(.caption).foregroundStyle(GameTheme.muted)
                let pool = pools[tab]
                if pool.isEmpty { Label("这一类没有题。", systemImage: "tray").foregroundStyle(GameTheme.muted) }
                let bank = c.quizBank, log = c.quizLog
                // A new tab starts at the top (a short list kept at a long list's scroll position looked empty).
                ScrollView {
                    VStack(spacing: 6) { ForEach(pool, id: \.self) { i in row(bank[i], i, log: log) } }
                }.id(tab)
            }
        }
    }
    private func tabButton(_ t: Int, _ n: Int) -> some View {
        let on = tab == t
        let title = t == 0 ? "全部" : t == 4 ? "未考察" : t == 5 ? "有错" : String(repeating: "★", count: t)
        let tint = t == 5 ? Color.red : GameTheme.primary
        return Button { tab = t; open = nil } label: {
            Text("\(title) \(n)").font(.callout.bold()).lineLimit(1).fixedSize().padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(on ? Color.white : (t == 5 && n > 0 ? Color.red : GameTheme.ink))
                .background(Capsule().fill(on ? tint : Color.white.opacity(0.55)))
        }.buttonStyle(.plain)
    }
    static func pools(_ c: MeadowCampaignSession, player: String?) -> [[Int]] {
        let all = c.quizPool(.random), bank = c.quizBank
        let unasked = c.unaskedQuestions(for: player), mistaken = c.mistakenQuestions(for: player)
        return [all] + (1...3).map { d in all.filter { (bank[$0].difficulty ?? 1) == d } }
            + [all.filter { unasked.contains($0) }, all.filter { mistaken.contains($0) }]
    }
    @ViewBuilder private func row(_ q: QuizQuestion, _ i: Int, log: [QuizAttempt]) -> some View {
        let asked = log.filter { $0.question == i && $0.practice != true && (player == nil || $0.player == player) }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { KeyHostingController<EmptyView>.endEditing(); onPick(i) } label: {
                    HStack(spacing: 8) {
                        Text(String(repeating: "★", count: max(1, min(3, q.difficulty ?? 1)))).font(.caption.bold()).lineLimit(1).fixedSize().foregroundStyle(Color(red: 0.85, green: 0.6, blue: 0.12)).frame(width: 36, alignment: .leading)
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
    @Published var seconds: Int = max(10, UserDefaults.standard.integer(forKey: "classroom.challengeSeconds") == 0 ? 120 : UserDefaults.standard.integer(forKey: "classroom.challengeSeconds")) {
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
    @State private var timeInput = ""
    private func applyTime() {
        let text = timeInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let s = Self.seconds(text) { model.seconds = s; model.note = nil } else { model.note = "时间格式：90（秒）、1:30 或 3分" }
        timeInput = ""
    }
    /// "90" → 90 s, "1:30" → 90 s, "3分" / "3m" / "3min" → 180 s, "1分30秒" → 90 s; 10 s to 60 min. Full-width digits work.
    static func seconds(_ raw: String) -> Int? {
        let t = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false)?.lowercased().replacingOccurrences(of: " ", with: "") ?? raw
        var total: Double?
        let parts = t.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) { total = m * 60 + sec }
        else if let range = t.range(of: "分") ?? t.range(of: "min") ?? t.range(of: "m") {
            let m = Double(t[..<range.lowerBound]) ?? (t[..<range.lowerBound].isEmpty ? nil : nil)
            let rest = t[range.upperBound...].replacingOccurrences(of: "钟", with: "").replacingOccurrences(of: "in", with: "")
                .replacingOccurrences(of: "秒", with: "").replacingOccurrences(of: "s", with: "")
            if let m { total = m * 60 + (rest.isEmpty ? 0 : (Double(rest) ?? .nan)) }
        } else { total = Double(t.replacingOccurrences(of: "秒", with: "").replacingOccurrences(of: "s", with: "")) }
        guard let total, total.isFinite else { return nil }
        let whole = Int(total.rounded())
        return (10...3600).contains(whole) ? whole : nil
    }

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
                    Button { model.seconds = max(10, model.seconds - 30) } label: { Image(systemName: "minus") }.buttonStyle(GlassIconButtonStyle())
                    // Any time typed in: 90 (seconds), 1:30, 3分 / 3m (minutes); applied on ⏎ or when the field is left.
                    ClassroomTextField(placeholder: ClassTimerModel.label(Double(model.seconds)), text: $timeInput, limit: 8, keyboard: .numbersAndPunctuation,
                                       alignment: .center, onSubmit: { applyTime() }, onEndEditing: { applyTime() })
                        .frame(width: 84, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.7)))
                        .help("输入挑战时间：90 = 90 秒，1:30 = 1 分 30 秒，3分 = 3 分钟；回车确认")
                    Button { model.seconds = min(3600, model.seconds + 30) } label: { Image(systemName: "plus") }.buttonStyle(GlassIconButtonStyle())
                    Spacer()
                    Button { onStart() } label: { Label("开始挑战 (⏎)", systemImage: "play.fill") }
                        .buttonStyle(GlassIconButtonStyle(prominent: true))
                        .disabled(model.player == nil || campaign?.courseIndices.isEmpty != false)
                }
                Text("开始后电视倒计时。全随机、按难度随机：答完自动抽下一题（这位同学没答过的优先，都答过才会重复；重复的选择题、填空题会打乱选项）；老师点选：每题从题单里点。学生口头作答你录入，选好即揭晓并按难度发奖，时间到即停。时间可点预设、±30 秒或直接输入（90、1:30、3分）。计时只在题目出好、等学生作答时走，选题、动画和揭晓答案时暂停。键盘：1–7 换人，+/− 调时间，回车开始。").font(.caption).foregroundStyle(GameTheme.muted)
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
    /// Time left when the clock last stopped, and since when it runs (nil = stopped). It runs only while a
    /// question is up and not yet answered: not while choosing, during the card's entrance or the answer's reveal.
    private var banked: Double
    private(set) var runningSince: Date?
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
        self.player = player; self.name = name; self.seconds = seconds; banked = Double(seconds)
    }
    var remaining: Double { max(0, banked - (runningSince.map { Date().timeIntervalSince($0) } ?? 0)) }
    var running: Bool { runningSince != nil }
    func resume() { guard runningSince == nil, remaining > 0 else { return }; runningSince = Date(); objectWillChange.send() }
    func pause() { guard runningSince != nil else { return }; banked = remaining; runningSince = nil; objectWillChange.send() }
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
                    HStack(spacing: 4) {
                        if model.phase != .finished && !model.running { Image(systemName: "pause.circle.fill").font(.title3).foregroundStyle(GameTheme.muted) }
                        Text(model.phase == .finished ? "结束" : ClassTimerModel.label(left)).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(left <= 10 ? Color.orange : model.running ? GameTheme.ink : GameTheme.muted)
                    }.help("计时只在题目出好、等学生作答时走；选题、动画和揭晓答案时暂停")
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
                        Text(QuizDrawBar.source(settings) + "出下一题").font(.headline)
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
        // In seat-number order (the numbers the teacher set by long-pressing), so 1, 2, 3… read left to right.
        FlowRow(spacing: 8) {
            ForEach(game.seatOrderedPlayers, id: \.id) { u in
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
    /// Questions with one set of options (choice, one-blank fill): each student's own answer (option index as
    /// shown; -1 = 不会), so everyone is marked on what they said.
    @Published var choices: [String: Int] = [:]
    /// The students picked (1–7) take this answer; the pick clears so the next ones can be chosen.
    func assign(_ option: Int) {
        guard !players.isEmpty else { note = "先按 1–7 选同学，再按他们选的答案。"; return }
        for id in players { choices[id] = option }
        players = []; note = nil
    }
    func clearPicked() { for id in players { choices[id] = nil }; players = [] }
    /// Whether this question takes one answer per student.
    static func perStudent(_ q: QuizQuestion) -> Bool { q.type != .flashcard && q.parts.count == 1 && q.parts[0].options.count >= 2 }
}

/// Each student's own answer to a class question with one set of options: a row per student with the options to
/// tap (A, B, C…, 不会); the right one is marked for the teacher only.
struct ClassChoiceGrid: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var model: ClassQuizModel
    let question: QuizQuestion
    private static let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
    var body: some View {
        let part = question.parts[0]
        VStack(alignment: .leading, spacing: 8) {
            Text(question.type == .fill ? question.prompt.replacingOccurrences(of: #"\{\{(\d+)\}\}"#, with: "（$1）", options: .regularExpression) : question.prompt)
                .font(.headline).foregroundStyle(GameTheme.ink)
            FlowRow(spacing: 6) {
                ForEach(part.options.indices, id: \.self) { k in
                    HStack(spacing: 4) {
                        Text(Self.letters[min(k, 7)]).font(.caption.bold()).foregroundStyle(.white).frame(width: 20, height: 20).background(Circle().fill(GameTheme.primary))
                        Text(part.options[k]).font(.callout)
                        if k == part.answer { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Color.green) }
                    }.padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.white.opacity(0.55)))
                }
            }
            Text("每人的答案（点选，或按 1–7 选人再按 A–\(Self.letters[min(part.options.count, 8) - 1])，0 不会）").font(.caption.bold()).foregroundStyle(GameTheme.muted)
            ForEach(game.seatOrderedPlayers.filter { !$0.host }, id: \.id) { u in
                let picked = model.players.contains(u.id), choice = model.choices[u.id]
                HStack(spacing: 6) {
                    Button { if picked { model.players.remove(u.id) } else { model.players.insert(u.id) } } label: {
                        HStack(spacing: 5) {
                            Text("\(game.seatNumber(u.id))").font(.caption.bold()).foregroundStyle(.white).frame(width: 20, height: 20)
                                .background(Circle().fill(picked ? Color.white.opacity(0.3) : GameTheme.primary))
                            Text(u.shortName).font(.callout.weight(.semibold)).lineLimit(1)
                        }.frame(width: 104, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 5)
                        .foregroundStyle(picked ? Color.white : GameTheme.ink)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(picked ? GameTheme.primary : Color.white.opacity(0.5)))
                    }.buttonStyle(.plain)
                    ForEach(part.options.indices, id: \.self) { k in option(Self.letters[min(k, 7)], on: choice == k, right: k == part.answer) { model.choices[u.id] = choice == k ? nil : k } }
                    option("不会", on: choice == -1, right: false) { model.choices[u.id] = choice == -1 ? nil : -1 }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    private func option(_ title: String, on: Bool, right: Bool, tap: @escaping () -> Void) -> some View {
        Button { KeyHostingController<EmptyView>.endEditing(); tap() } label: {
            Text(title).font(.callout.bold()).frame(minWidth: 30).padding(.horizontal, 6).padding(.vertical, 5)
                .foregroundStyle(on ? Color.white : GameTheme.ink)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? (right ? Color.green : Color.orange) : Color.white.opacity(0.55)))
        }.buttonStyle(.plain)
    }
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
            if ClassQuizModel.perStudent(draft.question) {
                ScrollView { ClassChoiceGrid(game: game, model: model, question: draft.question) }
            } else {
                Text("谁回答了（1–7，可多选）").font(.headline)
                QuizPlayerChips(game: game, selected: model.players, marks: marks) { id in
                    if model.players.contains(id) { model.players.remove(id) } else { model.players.insert(id) }
                }
                ScrollView { QuizAnswerRows(draft: draft) }
            }
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
                if ClassQuizModel.perStudent(draft.question) {
                    let answer = draft.question.parts[0].answer
                    let right = model.choices.values.filter { $0 == answer }.count
                    Text(model.choices.isEmpty ? "先记每人的答案" : "\(model.choices.count) 人作答 · \(right) 人答对（各得 \(reward.question.rewardLine)）")
                        .font(.callout.bold()).foregroundStyle(right > 0 ? Color.green : GameTheme.muted)
                    Button { onSend() } label: { Label("揭晓并发奖 (⏎)", systemImage: "paperplane.fill") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                        .disabled(model.choices.isEmpty)
                } else {
                    let right = draft.allRight
                    Text(model.players.isEmpty ? "先选人" : "\(model.players.count) 人 · \(right ? "答对 " + reward.question.rewardLine : "答错 · 参与奖 +\(reward.participationCoins)")")
                        .font(.callout.bold()).foregroundStyle(right ? Color.green : GameTheme.muted)
                    Button { onSend() } label: { Label("揭晓并发奖 (⏎)", systemImage: "paperplane.fill") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                        .disabled(model.players.isEmpty || draft.answered == 0)
                }
            }
            Text(ClassQuizModel.perStudent(draft.question)
                 ? "键盘：1–7 选人（可多选）再按 A–H 记下他们的答案，0 不会，⌫ 清掉选中的人的答案；回车揭晓答案、按每人的答案发奖并记录；Esc 只揭晓不发奖。"
                 : "键盘：1–7 选人，A–H 选答案，0 不会，⌫ 撤回，回车揭晓答案、同时发奖并记录；Esc 只揭晓不发奖。").font(.caption).foregroundStyle(GameTheme.muted)
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
    }
    private var marks: [String: String] {
        var m: [String: String] = [:]
        for s in model.sent { if let id = game.campaign?.engine.state.players.first(where: { $0.shortName == s.name })?.id { m[id] = s.right ? "✓" : "✗" } }
        return m
    }
}

/// The students nobody picked on the last shared question: put it in their mistakes, or not (no dialog, so the
/// next question can be picked meanwhile).
struct SkippedPromptBar: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var body: some View {
        if let p = game.skippedPrompt {
            VStack(alignment: .leading, spacing: 6) {
                Text("没选到：\(p.names)").font(.callout.bold()).foregroundStyle(GameTheme.ink).lineLimit(2)
                HStack(spacing: 8) {
                    Text("上一题记到他们的错题里吗？").font(.caption).foregroundStyle(GameTheme.muted)
                    Spacer()
                    Button("不记") { game.answerSkippedPrompt(record: false) }.buttonStyle(GlassIconButtonStyle())
                    Button("记入错题") { game.answerSkippedPrompt(record: true) }.buttonStyle(GlassIconButtonStyle(prominent: true))
                }
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.orange.opacity(0.4), lineWidth: 1))
        }
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
            SkippedPromptBar(game: game)
            QuizDrawBar(game: game)
            if settings.mode == .manual {
                QuizPicker(game: game, onPick: onPick)
            } else {
                HStack {
                    Text(QuizDrawBar.source(settings) + "抽一题（全班没出过的优先）").font(.headline)
                    Spacer()
                    Button { onDraw() } label: { Label("抽一题 (⏎)", systemImage: "shuffle") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                }
                Spacer()
            }
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
    }
}

// MARK: - Flash-card practice (fixed entry, endless)

/// A flash card being corrected: both sides, its difficulty, and the dictionary's meanings of its English side
/// (tap one to use it).
@MainActor final class FlashCardDraft: ObservableObject {
    let index: Int
    @Published var front: String
    @Published var back: String
    @Published var difficulty: Int
    @Published var note: String?
    /// Which side is English (the word); the meanings fill the other side.
    let englishFront: Bool
    let senses: [ClassroomDictionary.Sense]
    init(index: Int, question q: QuizQuestion) {
        self.index = index
        let part = q.parts.first, backText = part.map { $0.options[$0.answer] } ?? ""
        let english = q.prompt.range(of: "[A-Za-z]", options: .regularExpression) != nil
        front = q.prompt; back = backText
        difficulty = min(3, max(1, q.difficulty ?? 1))
        englishFront = english
        senses = NotesDictionary.shared.ready()?.entry(english ? q.prompt : backText)?.senses ?? []
    }
    func use(_ meaning: String) { if englishFront { back = meaning } else { front = meaning } }
}

/// Correcting the card on screen (闪卡 → 编辑): its answers so far stay with it.
struct FlashCardEditor: View {
    @ObservedObject var draft: FlashCardDraft
    var onSave: () -> Void
    var onCancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("编辑闪卡", systemImage: "pencil").font(.headline)
                Spacer()
                Text("已有的作答记录会保留").font(.caption).foregroundStyle(GameTheme.muted)
            }
            HStack {
                Text("正面").font(.caption.bold()).foregroundStyle(GameTheme.muted).frame(width: 34, alignment: .leading)
                ClassroomTextField(placeholder: "正面", text: $draft.front, limit: 120).frame(height: 32)
                    .padding(.horizontal, 8).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack {
                Text("背面").font(.caption.bold()).foregroundStyle(GameTheme.muted).frame(width: 34, alignment: .leading)
                ClassroomTextField(placeholder: "背面", text: $draft.back, limit: 200).frame(height: 32)
                    .padding(.horizontal, 8).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack(spacing: 6) {
                Text("难度").font(.caption.bold()).foregroundStyle(GameTheme.muted).frame(width: 34, alignment: .leading)
                ForEach(1...3, id: \.self) { d in
                    let on = draft.difficulty == d
                    Button { draft.difficulty = d } label: {
                        Text(String(repeating: "★", count: d)).font(.callout.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(on ? Color.white : GameTheme.ink)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                    }.buttonStyle(.plain)
                }
            }
            if !draft.senses.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(draft.senses.enumerated()), id: \.offset) { _, sense in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(sense.pos ?? "").font(.caption.bold()).foregroundStyle(GameTheme.muted).frame(width: 34, alignment: .leading)
                                FlowRow(spacing: 5) {
                                    ForEach(sense.meanings, id: \.self) { m in
                                        let on = (draft.englishFront ? draft.back : draft.front) == m
                                        Button { KeyHostingController<EmptyView>.endEditing(); draft.use(m) } label: {
                                            Text(m).font(.callout).padding(.horizontal, 8).padding(.vertical, 3)
                                                .foregroundStyle(on ? Color.white : GameTheme.ink)
                                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }.frame(maxHeight: 130)
            }
            if let note = draft.note { Text(note).font(.caption.bold()).foregroundStyle(.red) }
            HStack {
                Button { onCancel() } label: { Label("取消", systemImage: "xmark") }.buttonStyle(GlassIconButtonStyle())
                Spacer()
                Button { onSave() } label: { Label("保存", systemImage: "checkmark") }.buttonStyle(GlassIconButtonStyle(prominent: true))
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.5)))
    }
}

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
    /// The card being corrected (编辑).
    @Published var editing: FlashCardDraft?
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
                    Text("个人").tag(false); Text("全班").tag(true)
                }.pickerStyle(.segmented).frame(width: 170)
                Text("本轮 \(model.right)/\(model.total)").font(.callout.bold()).foregroundStyle(GameTheme.muted)
                Spacer()
                Button { onClose() } label: { Label("结束 (Esc)", systemImage: "xmark.circle") }.buttonStyle(GlassIconButtonStyle())
            }
            SkippedPromptBar(game: game)
            if model.classwide {
                HStack {
                    Text("谁回答了（1–7，可多选）").font(.headline)
                    Spacer()
                    Button { game.selectAllPracticePlayers() } label: { Label("全选 (A)", systemImage: "person.3.sequence.fill") }.buttonStyle(GlassIconButtonStyle())
                }
                QuizPlayerChips(game: game, selected: model.players) { id in game.togglePracticePlayer(id) }
            } else {
                QuizPlayerChips(game: game, selected: [model.player]) { id in game.switchPractice(to: id) }
            }
            if let note = model.note { Text(note).font(.caption.bold()).foregroundStyle(.orange) }
            HStack(spacing: 10) {
                Picker("", selection: Binding(get: { model.order }, set: { game.setPracticeOrder($0) })) {
                    Text("顺序").tag(PracticeModel.Order.sequential); Text("乱序").tag(PracticeModel.Order.shuffled)
                }.pickerStyle(.segmented).frame(width: 130)
                Button { game.stepPractice(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(GlassIconButtonStyle()).disabled(model.deck.isEmpty)
                Text(model.deck.isEmpty ? "0/0" : "第 \(model.cursor + 1)/\(model.deck.count) 张").font(.callout.bold()).monospacedDigit()
                Button { game.stepPractice(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(GlassIconButtonStyle()).disabled(model.deck.isEmpty)
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
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 200)
            }
            if let draft = model.editing {
                FlashCardEditor(draft: draft, onSave: { game.saveFlashCardEdit() }, onCancel: { model.editing = nil })
            } else if let live = game.quiz, live.mode == .practice {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("正面：\(live.question.prompt)").font(.title2.bold())
                        Spacer()
                        Button { game.editPracticeCard() } label: { Label("编辑 (E)", systemImage: "pencil") }.buttonStyle(GlassIconButtonStyle()).disabled(model.waiting)
                    }
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
                 ? "键盘：1–7 选回答的同学，D 对、C 错：记录、揭晓背面并自动下一张；空格跳过这张；←/→ 上一张/下一张，O 顺序/乱序，A 全选（再按取消），Esc 结束。答对按难度发奖（★ 10 金币 / ★★ 20 / ★★★ 30，+1 行动，+1/2/3 积分），错词进报告。"
                 : "键盘：D 对、C 错，记录后自动下一张；←/→ 上一张/下一张，O 顺序/乱序；1–7 换人，A 切到全班并全选，Esc 结束。答对按难度发奖，错词进报告。").font(.caption).foregroundStyle(GameTheme.muted)
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
    /// A corrected question takes the old one's place in its course (added when it is not there any more).
    func replace(_ old: QuizQuestion, with new: QuizQuestion) {
        if let i = questions.firstIndex(of: old) { questions[i] = new; save() }
        else { addCard(new, to: new.course ?? active ?? Self.lessonWords) }
    }
    func addCard(_ card: QuizQuestion, to course: String) {
        var card = card; card.course = course
        if let i = questions.firstIndex(where: { $0.course == course && $0.type == .flashcard && $0.prompt.lowercased() == card.prompt.lowercased() }) { questions[i] = card }
        else if let last = questions.lastIndex(where: { $0.course == course }) { questions.insert(card, at: last + 1) }
        else { questions.append(card) }
        save()
        if active == nil { active = course }
    }
    /// One question out of its course (answers already given stay in the trips).
    func remove(_ question: QuizQuestion) {
        if let i = questions.firstIndex(of: question) { questions.remove(at: i); save() }
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
            Button { game.openBankEditor() } label: { Label("编辑题目…", systemImage: "square.and.pencil") }
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
                Button { game.openQuizPrompts() } label: { Label("出题提示词", systemImage: "wand.and.stars") }.buttonStyle(GlassIconButtonStyle())
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
                Button { game.openBankEditor(course: c, back: true) } label: { Label("编辑题目", systemImage: "square.and.pencil") }.buttonStyle(GlassIconButtonStyle())
                Button { newName = c; renaming = c } label: { Label("改名", systemImage: "character.cursor.ibeam") }.buttonStyle(GlassIconButtonStyle())
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
