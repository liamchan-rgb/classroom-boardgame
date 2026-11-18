import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ClassroomGameCore
import MeadowWorldSupport

/// A quiz on screen. Shown in the TV overlays (over the game, the picture book and any panel) and in the teacher's
/// preview; `attempt` is set once the teacher submits.
struct LiveQuiz: Equatable {
    enum Mode: Equatable { case personal, classwide, practice }
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
            let card = MeadowQuizCard.present(in: box, question: quiz.question, player: who, place: quiz.mode == .practice ? "闪卡练习" : quiz.place, start: quiz.start, mode: quiz.mode)
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

// MARK: - Launcher (personal)

/// What the launcher shows: the student and their next question. Keys: 1–7 student, X/K/T/Y start a choice /
/// flash-card / fill-in / reading question at once, ⏎ start, space 换一题, Z 再出一次, Esc close.
@MainActor final class QuizLauncherModel: ObservableObject {
    @Published var player: String?
    @Published var kind: QuizKind?
    @Published var skip = 0
    /// "再出一次": ask this (already used) question again.
    @Published var again: Int?
    @Published var note: String?
    static let kindKeys: [String: QuizKind] = ["x": .choice, "k": .flashcard, "t": .fill, "y": .reading]
    static func key(for kind: QuizKind) -> String { kindKeys.first { $0.value == kind }!.key.uppercased() }
}

struct QuizLauncherPanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var model: QuizLauncherModel
    var onStart: () -> Void
    var onClose: () -> Void
    @State private var importing = false

    private var campaign: MeadowCampaignSession? { game.campaign }
    var candidate: Int? { game.launcherCandidate(model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("答题", systemImage: "questionmark.bubble.fill").font(.title2.bold())
                Text("题库 \(campaign?.quizBank.count ?? 0) 题 · 已作答 \(campaign?.quizLog.count ?? 0) 次").font(.callout).foregroundStyle(GameTheme.muted)
                Spacer()
                if let c = campaign, !c.quizPortions.isEmpty {
                    Button { game.openQuizPortions() } label: { Label("专属题分配 (\(c.quizPortions.count)份)", systemImage: "person.2.badge.gearshape") }.buttonStyle(GlassIconButtonStyle())
                }
                if campaign?.quizBank.isEmpty == true {
                    Button { loadSample() } label: { Label("载入示例题库", systemImage: "text.book.closed") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                }
                Button { importing = true } label: { Label("导入题库", systemImage: "square.and.arrow.down") }.buttonStyle(GlassIconButtonStyle()).disabled(campaign == nil)
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }.buttonStyle(.plain).foregroundStyle(GameTheme.muted)
            }
            if let note = model.note { Text(note).font(.caption).foregroundStyle(note.hasPrefix("✓") ? GameTheme.primary : .red) }
            if campaign == nil {
                Label("先开始或继续一个行程：题库和作答记录都存在行程里。", systemImage: "info.circle").foregroundStyle(GameTheme.muted)
            } else {
                QuizPlayerChips(game: game, selected: Set([model.player].compactMap { $0 })) { model.player = $0; model.skip = 0; model.again = nil }
                HStack(spacing: 8) {
                    kindChip(nil, "全部")
                    ForEach(QuizKind.allCases, id: \.self) { kindChip($0, $0.title) }
                    Spacer()
                }
                if let i = candidate, let q = campaign?.quizBank[i] {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text((model.again != nil ? "再出一次 · " : "") + (q.isShared ? "公用题 · 老师发奖" : (q.portion.map { "第\($0)份 · " } ?? "") + "专属题 · 满分 \(q.reward) 金币") + " · \(q.type.title) \(MeadowQuizCard.stars(q)) · 限时 \(q.timeLimit) 秒")
                                .font(.caption.bold()).foregroundStyle(q.isShared ? GameTheme.muted : GameTheme.primary)
                            Spacer()
                            Button { model.skip += 1; model.again = nil } label: { Label("换一题 (空格)", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(GlassIconButtonStyle())
                        }
                        Text(QuizReport.summary(q)).font(.title3.bold()).lineLimit(3)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GlassFill.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Label((campaign?.quizBank.isEmpty ?? true) ? "这个行程还没有题库，点右上角“导入题库”。" : "这位同学没有可出的题了（专属题和公用题都已出过）。", systemImage: "tray").foregroundStyle(GameTheme.muted)
                }
                HStack {
                    Button { model.again = campaign?.lastAskedQuestion() } label: { Label("再出一次 (Z)", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(GlassIconButtonStyle()).disabled(campaign?.lastAskedQuestion() == nil)
                    Spacer()
                    Button { onStart() } label: { Label("开始答题 (⏎)", systemImage: "play.fill") }
                        .buttonStyle(GlassIconButtonStyle(prominent: true)).disabled(model.player == nil || candidate == nil)
                }
                Text("Q 回车即开题 · 1–7 换人 · X 选择 K 闪卡 T 填空 Y 阅读（按下即开题）").font(.caption).foregroundStyle(GameTheme.muted)
            }
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .json, .text]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let list = try QuizBankParser.parse(Data(contentsOf: url))
                try campaign?.appendQuizBank(list)
                model.note = "✓ 已加入 \(list.count) 题（共 \(campaign?.quizBank.count ?? 0) 题）"; model.skip = 0
                game.revision += 1
            } catch { model.note = "导入失败：\(error.localizedDescription)" }
        }
    }
    /// The sample bank that ships with the app (six portions of word cards plus shared questions of every kind).
    private func loadSample() {
        do {
            guard let url = Bundle.main.url(forResource: "quiz-sample", withExtension: "txt") else { model.note = "示例题库缺失。"; return }
            let list = try QuizBankParser.parse(Data(contentsOf: url))
            try campaign?.appendQuizBank(list)
            model.note = "✓ 已载入示例题库 \(list.count) 题（含 \(campaign?.quizPortions.count ?? 0) 份专属题）"; model.skip = 0
            game.revision += 1
        } catch { model.note = "载入失败：\(error.localizedDescription)" }
    }
    private func kindChip(_ kind: QuizKind?, _ title: String) -> some View {
        let on = model.kind == kind
        return Button { model.kind = kind; model.skip = 0; model.again = nil } label: {
            Text(kind.map { "\(title) \(QuizLauncherModel.key(for: $0))" } ?? title).font(.callout.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(on ? Color.white : GameTheme.ink)
                .background(Capsule().fill(on ? GameTheme.primary : Color.white.opacity(0.5)))
        }.buttonStyle(.plain)
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
/// ⏎ sends: right → the reward and a "答对" record, wrong → the participation prize and "答错". The panel stays for
/// the next group; Esc ends it and reveals the answer on the TV.
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
                Button { onEnd() } label: { Label("结束并揭晓 (Esc)", systemImage: "eye") }.buttonStyle(GlassIconButtonStyle())
                Spacer()
                let right = draft.allRight
                Text(model.players.isEmpty ? "先选人" : "\(model.players.count) 人 · \(right ? "答对 +\(reward.amount(right: true))" : "答错 · 参与奖 +\(reward.amount(right: false))")")
                    .font(.callout.bold()).foregroundStyle(right ? Color.green : GameTheme.muted)
                Button { onSend() } label: { Label("发送 (⏎)", systemImage: "paperplane.fill") }.buttonStyle(GlassIconButtonStyle(prominent: true))
                    .disabled(model.players.isEmpty || draft.answered == 0)
            }
            Text("键盘：1–7 选人，A–H 选答案，0 不会，⌫ 撤回，回车发送并记录；发完可接着选下一组。").font(.caption).foregroundStyle(GameTheme.muted)
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
    init(player: String) { self.player = player }
}

/// K from anywhere: flash cards for one student, one after another. A–H records what they said and moves on; 0 不会;
/// 1–7 switches student; Esc ends. Recorded for the report (错词), no reward.
struct PracticePanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    @ObservedObject var model: PracticeModel
    var onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("闪卡练习", systemImage: "rectangle.on.rectangle.angled").font(.title2.bold())
                Text("本轮 \(model.right)/\(model.total)").font(.callout.bold()).foregroundStyle(GameTheme.muted)
                Spacer()
                Button { onClose() } label: { Label("结束 (Esc)", systemImage: "xmark.circle") }.buttonStyle(GlassIconButtonStyle())
            }
            QuizPlayerChips(game: game, selected: [model.player]) { id in game.switchPractice(to: id) }
            if let live = game.quiz, live.mode == .practice {
                VStack(alignment: .leading, spacing: 8) {
                    Text("正面：\(live.question.prompt)").font(.title2.bold())
                    let part = live.question.parts[0]
                    FlowRow(spacing: 8) {
                        ForEach(part.options.indices, id: \.self) { j in
                            Button { game.practiceAnswer(j) } label: {
                                HStack(spacing: 6) {
                                    Text(MeadowQuizCard.letters[j]).font(.caption.bold()).frame(width: 20, height: 20).background(Circle().fill(GameTheme.primary.opacity(0.15)))
                                    Text(part.options[j]).font(.body.weight(.semibold))
                                    if j == part.answer { Image(systemName: "checkmark").font(.caption2.bold()).opacity(0.55) }
                                }.padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(GameTheme.ink)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.55)))
                            }.buttonStyle(.plain).disabled(model.waiting)
                        }
                        Button { game.practiceAnswer(nil) } label: {
                            Label("不会 (0)", systemImage: "questionmark").padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(GameTheme.muted)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.4)))
                        }.buttonStyle(.plain).disabled(model.waiting)
                    }
                }
            } else {
                Label("题库里没有这位同学能练的闪卡。", systemImage: "tray").foregroundStyle(GameTheme.muted)
            }
            Text("键盘：A–H 记录学生说的背面并自动下一张，0 不会，1–7 换人，Esc 结束。只记录、不发奖励，错词进报告。").font(.caption).foregroundStyle(GameTheme.muted)
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
