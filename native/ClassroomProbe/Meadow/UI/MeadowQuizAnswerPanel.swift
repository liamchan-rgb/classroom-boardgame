import SwiftUI
import UIKit
import ClassroomGameCore

/// Teacher side of a quiz: the student says the answer, the teacher taps it. One row per graded item (the choice, the
/// flash card, each blank, each reading question) with every option, "不会", and for cards and blanks a field for
/// any other answer. The right option carries a small check so the teacher can confirm at a glance.
struct MeadowQuizAnswerPanel: View {
    let question: QuizQuestion
    let player: String
    let start: Date
    var onSubmit: ([Int?], [String?]) -> Void
    var onLater: () -> Void
    @State private var picks: [Int?]
    @State private var unknown: [Bool]
    @State private var texts: [String]

    init(question: QuizQuestion, player: String, start: Date, onSubmit: @escaping ([Int?], [String?]) -> Void, onLater: @escaping () -> Void) {
        self.question = question; self.player = player; self.start = start; self.onSubmit = onSubmit; self.onLater = onLater
        let n = question.parts.count
        _picks = State(initialValue: Array(repeating: nil, count: n))
        _unknown = State(initialValue: Array(repeating: false, count: n))
        _texts = State(initialValue: Array(repeating: "", count: n))
    }
    private var answered: Int { question.parts.indices.filter { picks[$0] != nil || unknown[$0] || !texts[$0].trimmingCharacters(in: .whitespaces).isEmpty }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(GameTheme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(player) 作答").font(.title3.bold())
                    Text("\(question.type.title) \(MeadowQuizCard.stars(question)) · 满分 \(question.reward) 金币 · 限时 \(question.timeLimit) 秒").font(.caption).foregroundStyle(GameTheme.muted)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let left = Double(question.timeLimit) - context.date.timeIntervalSince(start)
                    Text(left <= 0 ? "超时 \(Int(-left))s" : String(format: "%d:%02d", Int(ceil(left)) / 60, Int(ceil(left)) % 60))
                        .font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(left <= 0 ? Color.red : left <= 10 ? Color.orange : GameTheme.ink)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    context
                    ForEach(question.parts.indices, id: \.self) { i in row(i) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button { onLater() } label: { Label("稍后再答", systemImage: "clock.arrow.circlepath") }.buttonStyle(GlassIconButtonStyle())
                Spacer()
                Text("已录 \(answered)/\(question.parts.count)").font(.callout.bold()).foregroundStyle(GameTheme.muted)
                Button {
                    onSubmit(picks.indices.map { unknown[$0] ? nil : picks[$0] },
                             texts.indices.map { let t = texts[$0].trimmingCharacters(in: .whitespaces); return unknown[$0] || picks[$0] != nil || t.isEmpty ? nil : String(t.prefix(120)) })
                } label: { Label("提交并揭晓", systemImage: "checkmark.seal.fill") }.buttonStyle(GlassIconButtonStyle(prominent: true))
            }
            Text("学生说出答案后点对应选项；没在选项里的点“不会”或在“其他”里输入。未录入的小题按答错记。").font(.caption).foregroundStyle(GameTheme.muted)
        }.padding(22).background(GlassBackdrop())
    }

    @ViewBuilder private var context: some View {
        switch question.type {
        case .reading:
            Text(question.passage ?? "").font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(GlassFill.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .flashcard:
            Text("正面：\(question.prompt)").font(.title3.bold())
        case .fill:
            Text(question.prompt.replacingOccurrences(of: #"\{\{(\d+)\}\}"#, with: "（$1）", options: .regularExpression)).font(.title3.bold())
        case .choice:
            Text(question.prompt).font(.title3.bold())
        }
    }

    private func row(_ i: Int) -> some View {
        let part = question.parts[i]
        let title: String = {
            switch question.type {
            case .choice: return "学生选了"
            case .flashcard: return "学生说的背面"
            case .fill: return "第\(i + 1)空"
            case .reading: return "\(i + 1). \(part.prompt ?? "")"
            }
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            FlowRow(spacing: 8) {
                ForEach(part.options.indices, id: \.self) { j in
                    let on = picks[i] == j && !unknown[i]
                    Button {
                        picks[i] = on ? nil : j; unknown[i] = false
                        if !on { texts[i] = "" }
                    } label: {
                        HStack(spacing: 6) {
                            Text(MeadowQuizCard.letters[j]).font(.caption.bold()).frame(width: 20, height: 20).background(Circle().fill(on ? Color.white.opacity(0.3) : GameTheme.primary.opacity(0.15)))
                            Text(part.options[j]).font(.body.weight(.semibold))
                            if j == part.answer { Image(systemName: "checkmark").font(.caption2.bold()).opacity(0.55) }
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(on ? Color.white : GameTheme.ink)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                    }.buttonStyle(.plain)
                }
                Button { unknown[i].toggle(); if unknown[i] { picks[i] = nil; texts[i] = "" } } label: {
                    Label("不会", systemImage: "questionmark").padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(unknown[i] ? Color.white : GameTheme.muted)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(unknown[i] ? Color.gray : Color.white.opacity(0.4)))
                }.buttonStyle(.plain)
            }
            if question.type == .fill || question.type == .flashcard {
                ClassroomTextField(placeholder: "其他答案（学生说的不在选项里时输入）", text: Binding(get: { texts[i] }, set: { v in texts[i] = v; if !v.isEmpty { picks[i] = nil; unknown[i] = false } }), limit: 120)
                    .frame(height: 36).padding(.horizontal, 10).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

/// Wraps its children onto new lines like text.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(width, widest), height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}
