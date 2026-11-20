import SwiftUI
import UIKit
import ClassroomGameCore

// MARK: - Keyboard

/// A hosted panel that takes the keyboard: `onKey` gets ⏎ ⎋ ⌫ and shortcut tokens; keys it does not use go on to
/// the console's global shortcuts (timer, scoreboard…). Text fields inside still get their own typing.
final class KeyHostingController<Content: View>: UIHostingController<Content> {
    var onKey: ((String) -> Bool)?
    private var editingEnded: NSObjectProtocol?
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); becomeFirstResponder()
        // After a coin / other-answer field is done, the keys come back to the panel.
        editingEnded = NotificationCenter.default.addObserver(forName: UITextField.textDidEndEditingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.view.window != nil { self?.becomeFirstResponder() } }
        }
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if let editingEnded { NotificationCenter.default.removeObserver(editingEnded) } }
    /// Ends typing in any field (taps on option buttons do this, so letter keys pick again).
    static func endEditing() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses { if let key = press.key, let token = ClassroomShortcuts.panelToken(key), onKey?(token) == true { handled = true } }
        if handled { return }
        if ClassroomGlobalTools.handlePresses?(presses) == true { return }
        super.pressesBegan(presses, with: event)
    }
}

/// The answer being recorded for one question: an option per graded item, "不会", or another answer typed in.
/// Letter keys A–H pick for the first item still open, 0 = 不会, ⌫ undoes the last pick.
@MainActor final class QuizAnswerDraft: ObservableObject {
    let question: QuizQuestion
    @Published var picks: [Int?]
    @Published var unknown: [Bool]
    @Published var texts: [String]
    /// Called (on the next turn) once every item has an answer picked: the challenge submits straight away.
    var onComplete: (() -> Void)?
    init(_ question: QuizQuestion) {
        self.question = question
        let n = question.parts.count
        picks = Array(repeating: nil, count: n); unknown = Array(repeating: false, count: n); texts = Array(repeating: "", count: n)
    }
    func done(_ i: Int) -> Bool { picks[i] != nil || unknown[i] || !texts[i].trimmingCharacters(in: .whitespaces).isEmpty }
    var answered: Int { question.parts.indices.filter(done).count }
    var current: Int? { question.parts.indices.first { !done($0) } }
    func pick(_ i: Int, _ option: Int?) {
        KeyHostingController<EmptyView>.endEditing()
        if let option { picks[i] = picks[i] == option && !unknown[i] ? nil : option; unknown[i] = false; texts[i] = "" }
        else { unknown[i].toggle(); if unknown[i] { picks[i] = nil; texts[i] = "" } }
        checkComplete()
    }
    private func checkComplete() {
        guard let onComplete, answered == question.parts.count else { return }
        DispatchQueue.main.async { onComplete() }
    }
    func undo() { if let i = question.parts.indices.last(where: done) { picks[i] = nil; unknown[i] = false; texts[i] = "" } }
    /// A letter (option) or "0" (不会) for the first open item. Returns whether it was used.
    func key(_ token: String) -> Bool {
        if token == "⌫" { undo(); return true }
        let used = apply(token)
        if used { checkComplete() }
        return used
    }
    private func apply(_ token: String) -> Bool {
        // Flash cards: the teacher only says right (D, 对) or wrong (C, 错).
        if question.type == .flashcard {
            guard let i = current ?? 0 as Int?, question.parts.indices.contains(i) else { return false }
            if token == "d" { picks[i] = question.parts[i].answer; unknown[i] = false; return true }
            if token == "c" || token == "0" { picks[i] = nil; unknown[i] = true; return true }
            return false
        }
        guard let i = current ?? (question.parts.count == 1 ? 0 : nil) else { return false }
        if token == "0" { pick(i, nil); return true }
        guard token.count == 1, let index = MeadowQuizCard.letters.firstIndex(of: token.uppercased()), question.parts[i].options.indices.contains(index) else { return false }
        picks[i] = index; unknown[i] = false; texts[i] = ""
        return true
    }
    var result: (picks: [Int?], texts: [String?]) {
        (picks.indices.map { unknown[$0] ? nil : picks[$0] },
         texts.indices.map { let t = texts[$0].trimmingCharacters(in: .whitespaces); return unknown[$0] || picks[$0] != nil || t.isEmpty ? nil : String(t.prefix(120)) })
    }
    var allRight: Bool { let r = result; return question.parts.indices.allSatisfy { r.picks[$0] == question.parts[$0].answer } }
    func reset() { for i in picks.indices { picks[i] = nil; unknown[i] = false; texts[i] = "" } }
}

/// A right answer pays by difficulty (fixed); a wrong one to the class may get the teacher's participation prize.
@MainActor final class QuizManualReward: ObservableObject {
    let question: QuizQuestion
    @Published var participation: String {didSet{UserDefaults.standard.set(participation,forKey:"classroom.quizParticipation")}}
    init(_ q: QuizQuestion) {
        question = q
        participation = UserDefaults.standard.string(forKey: "classroom.quizParticipation") ?? "2"
    }
    private static func value(_ s: String) -> Int { min(1000, max(0, Int(s.filter(\.isNumber)) ?? 0)) }
    var participationCoins: Int { Self.value(participation) }
}

extension QuizQuestion {
    /// "+20 金币 +1 行动 +2 积分": what a right answer pays (by difficulty).
    var rewardLine: String { "+\(reward) 金币 +\(QuizRewards.steps) 行动 +\(points) 积分" }
}

// MARK: - Answer rows (shared by the personal and the class panels)

struct QuizAnswerRows: View {
    @ObservedObject var draft: QuizAnswerDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            context
            ForEach(draft.question.parts.indices, id: \.self) { i in row(i) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var context: some View {
        let q = draft.question
        switch q.type {
        case .reading:
            Text(q.passage ?? "").font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(GlassFill.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .flashcard: Text("正面：\(q.prompt)").font(.title3.bold())
        case .fill: Text(q.prompt.replacingOccurrences(of: #"\{\{(\d+)\}\}"#, with: "（$1）", options: .regularExpression)).font(.title3.bold())
        case .choice: Text(q.prompt).font(.title3.bold())
        }
    }
    /// Flash card: the back, and right / wrong.
    private func flashRow(_ i: Int) -> some View {
        let part = draft.question.parts[i]
        let right = draft.picks[i] == part.answer && !draft.unknown[i], wrong = draft.unknown[i]
        return VStack(alignment: .leading, spacing: 10) {
            Text("背面：\(part.options[part.answer])").font(.title2.bold()).foregroundStyle(GameTheme.primary)
            HStack(spacing: 12) {
                Button { draft.pick(i, part.answer) } label: {
                    Label("对 (D)", systemImage: "checkmark.circle.fill").font(.title3.bold()).frame(minWidth: 120).padding(.vertical, 10)
                        .foregroundStyle(right ? Color.white : Color.green)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(right ? Color.green : Color.green.opacity(0.12)))
                }.buttonStyle(.plain)
                Button { if !wrong { draft.pick(i, nil) } } label: {
                    Label("错 (C)", systemImage: "xmark.circle.fill").font(.title3.bold()).frame(minWidth: 120).padding(.vertical, 10)
                        .foregroundStyle(wrong ? Color.white : Color.red)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(wrong ? Color.red : Color.red.opacity(0.12)))
                }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private func row(_ i: Int) -> some View {
        if draft.question.type == .flashcard { flashRow(i) } else { optionRow(i) }
    }
    private func optionRow(_ i: Int) -> some View {
        let q = draft.question, part = q.parts[i]
        let title: String = {
            switch q.type {
            case .choice: return "学生选了"
            case .flashcard: return "学生说的背面"
            case .fill: return "第\(i + 1)空"
            case .reading: return "\(i + 1). \(part.prompt ?? "")"
            }
        }()
        let focus = draft.current == i
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if focus { Image(systemName: "keyboard").font(.caption.bold()).foregroundStyle(GameTheme.primary) }
                Text(title).font(.headline)
            }
            FlowRow(spacing: 8) {
                ForEach(part.options.indices, id: \.self) { j in
                    let on = draft.picks[i] == j && !draft.unknown[i]
                    Button { draft.pick(i, j) } label: {
                        HStack(spacing: 6) {
                            Text(MeadowQuizCard.letters[j]).font(.caption.bold()).frame(width: 20, height: 20).background(Circle().fill(on ? Color.white.opacity(0.3) : GameTheme.primary.opacity(0.15)))
                            Text(part.options[j]).font(.body.weight(.semibold))
                            if j == part.answer { Image(systemName: "checkmark").font(.caption2.bold()).opacity(0.55) }
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(on ? Color.white : GameTheme.ink)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? GameTheme.primary : Color.white.opacity(0.55)))
                    }.buttonStyle(.plain)
                }
                Button { draft.pick(i, nil) } label: {
                    Label("不会 (0)", systemImage: "questionmark").padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(draft.unknown[i] ? Color.white : GameTheme.muted)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(draft.unknown[i] ? Color.gray : Color.white.opacity(0.4)))
                }.buttonStyle(.plain)
            }
            if q.type == .fill {
                ClassroomTextField(placeholder: "其他答案（学生说的不在选项里时输入）", text: Binding(get: { draft.texts[i] }, set: { v in draft.texts[i] = v; if !v.isEmpty { draft.picks[i] = nil; draft.unknown[i] = false } }), limit: 120)
                    .frame(height: 36).padding(.horizontal, 10).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(focus ? 8 : 0)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(GameTheme.primary.opacity(focus ? 0.5 : 0), lineWidth: 1.5))
    }
}

/// Coin fields for shared-bank questions.
struct QuizRewardFields: View {
    @ObservedObject var reward: QuizManualReward
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bitcoinsign.circle.fill").foregroundStyle(Color(red: 0.74, green: 0.52, blue: 0.12))
            Text("答对 " + reward.question.rewardLine).font(.callout.bold())
            Spacer(minLength: 4)
            Text("答错参与奖").font(.callout.bold())
            ClassroomTextField(placeholder: "0", text: $reward.participation, limit: 4, keyboard: .numberPad).frame(width: 56, height: 32)
                .padding(.horizontal, 8).background(GlassFill.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - Personal answer panel

/// Teacher side of one student's question: tap (or type A–H) what the student said, ⏎ submits and reveals.
/// A right answer pays by difficulty.
struct MeadowQuizAnswerPanel: View {
    @ObservedObject var draft: QuizAnswerDraft
    @ObservedObject var reward: QuizManualReward
    let player: String
    let start: Date
    var onSubmit: () -> Void
    var onLater: () -> Void
    private var question: QuizQuestion { draft.question }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(GameTheme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(player) 作答").font(.title3.bold())
                    Text("\(question.type.title) \(MeadowQuizCard.stars(question)) · 限时 \(question.timeLimit) 秒 · 答对 \(question.rewardLine)")
                        .font(.caption).foregroundStyle(GameTheme.muted)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let left = Double(question.timeLimit) - context.date.timeIntervalSince(start)
                    Text(left <= 0 ? "超时 \(Int(-left))s" : String(format: "%d:%02d", Int(ceil(left)) / 60, Int(ceil(left)) % 60))
                        .font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(left <= 0 ? Color.red : left <= 10 ? Color.orange : GameTheme.ink)
                }
            }
            ScrollView { QuizAnswerRows(draft: draft) }
            HStack {
                Button { onLater() } label: { Label("稍后 (Esc)", systemImage: "clock.arrow.circlepath") }.buttonStyle(GlassIconButtonStyle())
                Spacer()
                Text("已录 \(draft.answered)/\(question.parts.count)").font(.callout.bold()).foregroundStyle(GameTheme.muted)
                Button { onSubmit() } label: { Label("提交并揭晓 (⏎)", systemImage: "checkmark.seal.fill") }.buttonStyle(GlassIconButtonStyle(prominent: true))
            }
            Text(question.type == .flashcard ? "键盘：D 对，C 错，⌫ 撤回，回车提交。" : "键盘：A–H 选学生说的答案，0 不会，⌫ 撤回，回车提交。未录入的按答错记。").font(.caption).foregroundStyle(GameTheme.muted)
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(GlassBackdrop())
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
