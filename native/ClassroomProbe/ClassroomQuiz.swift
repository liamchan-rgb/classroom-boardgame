import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ClassroomGameCore
import MeadowWorldSupport

/// A quiz on screen: one student, one question from the trip's bank. Shown in the TV overlays (over the game, the
/// picture book and any panel) and in the teacher's preview; `attempt` is set once the teacher submits.
struct LiveQuiz: Equatable {
    var token: Int
    var index: Int
    var question: QuizQuestion
    var player: String
    var playerName: String
    var place: String
    /// nil when called up anywhere (not at a quiz spot).
    var node: Int?
    var start: Date
    var attempt: QuizAttempt?
    var dropName: String?
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
            let card = MeadowQuizCard.present(in: box, question: quiz.question, player: quiz.playerName, place: quiz.place, start: quiz.start)
            card.layer.zPosition = 0
            box.card = card; box.token = quiz.token; box.revealed = false
            box.setNeedsLayout()
        }
        if let attempt = quiz.attempt, !box.revealed, let card = box.card {
            box.revealed = true
            let token = quiz.token
            card.reveal(attempt, dropName: quiz.dropName) { done(token) }
        }
    }
}

// MARK: - Launcher (teacher)

/// "答题" from anywhere: pick the student, optionally a kind and difficulty, check the question, and start. Also
/// imports more questions into the current trip.
struct QuizLauncherPanel: View {
    @ObservedObject var game: MeadowTeacherCoordinator
    var onStart: (String, Int) -> Void
    var onClose: () -> Void
    @State private var player: String?
    @State private var kind: QuizKind?
    @State private var difficulty: Int?
    @State private var skip = 0
    @State private var importing = false
    @State private var note: String?

    private var campaign: MeadowCampaignSession? { game.campaign }
    private var candidate: Int? { campaign?.quizCandidate(kind: kind, difficulty: difficulty, skip: skip) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("答题", systemImage: "questionmark.bubble.fill").font(.title2.bold())
                Text("题库 \(campaign?.quizBank.count ?? 0) 题 · 已作答 \(campaign?.quizLog.count ?? 0) 次").font(.callout).foregroundStyle(GameTheme.muted)
                Spacer()
                Button { importing = true } label: { Label("导入题库", systemImage: "square.and.arrow.down") }.buttonStyle(GlassIconButtonStyle()).disabled(campaign == nil)
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }.buttonStyle(.plain).foregroundStyle(GameTheme.muted)
            }
            if let note { Text(note).font(.caption).foregroundStyle(note.hasPrefix("✓") ? GameTheme.primary : .red) }
            if campaign == nil {
                Label("先开始或继续一个行程：题库和作答记录都存在行程里。", systemImage: "info.circle").foregroundStyle(GameTheme.muted)
            } else {
                Text("谁来答").font(.headline)
                FlowRow(spacing: 8) {
                    ForEach(campaign?.engine.state.players ?? [], id: \.id) { u in
                        let on = player == u.id
                        let count = campaign?.quizLog.filter { $0.player == u.id }.count ?? 0
                        Button { player = u.id } label: {
                            HStack(spacing: 6) {
                                Text(quizInitial(u.shortName)).font(.caption.bold()).foregroundStyle(.white).frame(width: 24, height: 24).background(Circle().fill(on ? Color.white.opacity(0.3) : GameTheme.primary))
                                Text(u.shortName).font(.body.weight(.semibold))
                                if count > 0 { Text("\(count)").font(.caption2.bold()).opacity(0.7) }
                            }.padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(on ? Color.white : GameTheme.ink)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                        }.buttonStyle(.plain)
                    }
                }
                HStack(spacing: 14) {
                    Picker("题型", selection: $kind) {
                        Text("全部题型").tag(QuizKind?.none)
                        ForEach(QuizKind.allCases, id: \.self) { Text($0.title).tag(QuizKind?.some($0)) }
                    }.fixedSize()
                    Picker("难度", selection: $difficulty) {
                        Text("全部难度").tag(Int?.none)
                        ForEach(1...3, id: \.self) { Text(String(repeating: "★", count: $0)).tag(Int?.some($0)) }
                    }.fixedSize()
                    Spacer()
                }.onChange(of: kind) { skip = 0 }.onChange(of: difficulty) { skip = 0 }
                if let i = candidate, let q = campaign?.quizBank[i] {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(q.type.title) \(MeadowQuizCard.stars(q)) · 满分 \(q.reward) 金币 · 限时 \(q.timeLimit) 秒").font(.caption.bold()).foregroundStyle(GameTheme.muted)
                            Spacer()
                            Button { skip += 1 } label: { Label("换一题", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(GlassIconButtonStyle())
                        }
                        Text(QuizReport.summary(q)).font(.title3.bold()).lineLimit(3)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GlassFill.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Label((campaign?.quizBank.isEmpty ?? true) ? "这个行程还没有题库，点右上角“导入题库”。" : "没有符合筛选的题目。", systemImage: "tray").foregroundStyle(GameTheme.muted)
                }
                HStack {
                    Spacer()
                    Button { if let player, let i = candidate { onStart(player, i) } } label: { Label("开始答题", systemImage: "play.fill") }
                        .buttonStyle(GlassIconButtonStyle(prominent: true)).disabled(player == nil || candidate == nil)
                }
            }
        }
        .padding(22).background(GlassBackdrop())
        .onAppear { player = player ?? game.campaign?.selectedPlayerID }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .json, .text]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let list = try QuizBankParser.parse(Data(contentsOf: url))
                try campaign?.appendQuizBank(list)
                note = "✓ 已加入 \(list.count) 题（共 \(campaign?.quizBank.count ?? 0) 题）"; skip = 0
                game.revision += 1
            } catch { note = "导入失败：\(error.localizedDescription)" }
        }
    }
}
