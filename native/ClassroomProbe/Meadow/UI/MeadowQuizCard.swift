import UIKit
import ClassroomGameCore

/// A quiz on the TV for one student: who answers, the difficulty and kind, a countdown, and the question laid out by
/// kind (choice cards, a big flash card, a sentence with numbered blanks, or a passage with its questions). The teacher
/// taps what the student said on the iPad; the card then reveals the answers and the reward.
final class MeadowQuizCard: UIView {
    private let card = UIView(), header = UILabel(), clock = UILabel(), prompt = UILabel(), result = UILabel()
    private let passage = UILabel(), questions = UILabel(), face = UILabel(), faceBox = UIView()
    private var optionViews: [UIView] = []
    private var question: QuizQuestion!
    private var start = Date(), limit = 60
    private var ticker: Timer?
    private var revealed = false
    static let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
    static let circled = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑪", "⑫"]

    private var mode: LiveQuiz.Mode = .personal
    private var deadline: Date?
    static func present(in host: UIView, question: QuizQuestion, player: String, place: String, start: Date, mode: LiveQuiz.Mode = .personal, deadline: Date? = nil) -> MeadowQuizCard {
        host.subviews.compactMap { $0 as? MeadowQuizCard }.forEach { $0.removeFromSuperview() }
        let view = MeadowQuizCard(frame: host.bounds); view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.question = question; view.start = start; view.limit = question.timeLimit; view.mode = mode; view.deadline = deadline
        view.build(player: player, place: place); host.addSubview(view)
        view.alpha = 0; view.card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.6) { view.alpha = 1; view.card.transform = .identity }
        return view
    }
    deinit { ticker?.invalidate() }
    override func removeFromSuperview() { ticker?.invalidate(); super.removeFromSuperview() }

    static func stars(_ q: QuizQuestion) -> String { q.difficulty.map { String(repeating: "★", count: $0) + String(repeating: "☆", count: 3 - $0) } ?? "" }

    private func build(player: String, place: String) {
        let q = question!
        backgroundColor = UIColor(red: 0.05, green: 0.15, blue: 0.18, alpha: 0.32); layer.zPosition = 5200; isUserInteractionEnabled = false
        MeadowPreviewPalette.stylePanel(card); card.backgroundColor = MeadowPreviewPalette.panel; card.layer.borderColor = UIColor.white.cgColor; card.layer.borderWidth = 1.5
        addSubview(card)
        let stars = Self.stars(q)
        let prize = mode == .practice ? "练习" : mode == .classwide ? "老师发奖" : "满分 +\(q.reward)"
        header.attributedText = MeadowGlassText.iconLine(mode == .classwide ? "person.3.fill" : mode == .practice ? "rectangle.on.rectangle.angled" : "person.crop.circle.fill",
                                                         "\(player) 作答 · \(q.type.title)\(stars.isEmpty ? "" : " " + stars) · \(prize) · \(place)", size: 18, tint: MeadowPreviewPalette.gold)
        header.adjustsFontSizeToFitWidth = true; header.minimumScaleFactor = 0.6
        clock.font = .monospacedDigitSystemFont(ofSize: 26, weight: .heavy); clock.textAlignment = .center; clock.textColor = .white
        clock.layer.cornerRadius = 20; clock.clipsToBounds = true; clock.backgroundColor = MeadowPreviewPalette.primary
        prompt.font = MeadowPreviewPalette.font(30, .bold); prompt.textColor = MeadowPreviewPalette.ink; prompt.numberOfLines = 0
        result.font = MeadowPreviewPalette.font(20, .semibold); result.textColor = MeadowPreviewPalette.ink; result.numberOfLines = 2; result.alpha = 0
        [header, clock, result].forEach(card.addSubview)
        switch q.type {
        case .choice:
            prompt.text = q.prompt; card.addSubview(prompt)
            for (i, text) in q.options.enumerated() { optionViews.append(optionView(Self.letters[i], text)) }
        case .flashcard:
            faceBox.backgroundColor = MeadowPreviewPalette.glass(.medium); faceBox.layer.cornerRadius = 26; faceBox.layer.cornerCurve = .continuous
            faceBox.layer.borderWidth = 2; faceBox.layer.borderColor = UIColor.white.cgColor
            face.text = q.prompt; face.font = MeadowPreviewPalette.font(72, .heavy); face.textColor = MeadowPreviewPalette.ink
            face.textAlignment = .center; face.numberOfLines = 3; face.adjustsFontSizeToFitWidth = true; face.minimumScaleFactor = 0.3
            faceBox.addSubview(face); card.addSubview(faceBox)
        case .fill:
            prompt.attributedText = fillText(answers: nil); card.addSubview(prompt)
        case .reading:
            passage.text = q.passage; passage.font = MeadowPreviewPalette.font(26, .medium); passage.textColor = MeadowPreviewPalette.ink
            passage.numberOfLines = 0; passage.adjustsFontSizeToFitWidth = true; passage.minimumScaleFactor = 0.5
            questions.numberOfLines = 0; questions.adjustsFontSizeToFitWidth = true; questions.minimumScaleFactor = 0.5
            questions.attributedText = readingText(attempt: nil)
            [passage, questions].forEach(card.addSubview)
        }
        tick()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common); ticker = t
    }
    private func optionView(_ letterText: String, _ text: String) -> UIView {
        let v = UIView(); v.backgroundColor = MeadowPreviewPalette.glass(.medium); v.layer.cornerRadius = 14; v.layer.cornerCurve = .continuous
        v.layer.borderWidth = 1; v.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        let letter = UILabel(); letter.text = letterText; letter.textAlignment = .center; letter.font = MeadowPreviewPalette.font(22, .heavy)
        letter.textColor = .white; letter.backgroundColor = MeadowPreviewPalette.primary; letter.layer.cornerRadius = 18; letter.clipsToBounds = true; letter.tag = 1
        let body = UILabel(); body.text = text; body.font = MeadowPreviewPalette.font(24, .semibold); body.textColor = MeadowPreviewPalette.ink; body.numberOfLines = 2; body.adjustsFontSizeToFitWidth = true; body.minimumScaleFactor = 0.6; body.tag = 2
        v.addSubview(letter); v.addSubview(body); card.addSubview(v)
        return v
    }
    private func tick() {
        guard !revealed else { return }
        let left = deadline.map { $0.timeIntervalSinceNow } ?? Double(limit) - Date().timeIntervalSince(start)
        if left <= 0 {
            clock.text = "时间到"; clock.backgroundColor = UIColor.systemRed.withAlphaComponent(Int(Date().timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 0.9 : 0.6)
        } else {
            let whole = Int(ceil(left)); clock.text = String(format: "%d:%02d", whole / 60, whole % 60)
            clock.backgroundColor = left <= 10 ? UIColor.systemOrange : MeadowPreviewPalette.primary
        }
    }

    /// The sentence with blanks as ①②…; after the reveal each blank holds the right answer (green), with what the
    /// student said struck through in red when it was wrong.
    private func fillText(answers attempt: QuizAttempt?) -> NSAttributedString {
        let out = NSMutableAttributedString(), base: [NSAttributedString.Key: Any] = [.font: MeadowPreviewPalette.font(32, .bold), .foregroundColor: MeadowPreviewPalette.ink]
        var rest = Substring(question.prompt), n = 0
        while let open = rest.range(of: "{{"), let close = rest[open.upperBound...].range(of: "}}") {
            out.append(NSAttributedString(string: String(rest[..<open.lowerBound]), attributes: base))
            let part = question.parts[min(n, question.parts.count - 1)]
            if let attempt {
                let right = attempt.correct[n]
                if !right {
                    let said = attempt.picks[n].map { part.options[$0] } ?? attempt.texts[n] ?? "—"
                    out.append(NSAttributedString(string: " \(said) ", attributes: [.font: MeadowPreviewPalette.font(26, .semibold), .foregroundColor: UIColor.systemRed, .strikethroughStyle: NSUnderlineStyle.single.rawValue]))
                }
                out.append(NSAttributedString(string: " \(part.options[part.answer]) ", attributes: [.font: MeadowPreviewPalette.font(32, .heavy), .foregroundColor: right ? UIColor.systemGreen : MeadowPreviewPalette.primary, .underlineStyle: NSUnderlineStyle.thick.rawValue]))
            } else {
                out.append(NSAttributedString(string: " ＿\(Self.circled[min(n, 11)])＿ ", attributes: [.font: MeadowPreviewPalette.font(32, .heavy), .foregroundColor: MeadowPreviewPalette.primary]))
            }
            n += 1; rest = rest[close.upperBound...]
        }
        out.append(NSAttributedString(string: String(rest), attributes: base))
        // Each blank's choices (the same letters the teacher picks by), one line per blank; after the reveal the
        // right one is green with a tick (the lines stay, so the card keeps its height).
        for (i, part) in question.parts.enumerated() where part.options.count > 1 {
            let line = NSMutableAttributedString(string: "\n" + (i == 0 ? "\n" : "") + "\(Self.circled[min(i, 11)])  ", attributes: [.font: MeadowPreviewPalette.font(26, .heavy), .foregroundColor: MeadowPreviewPalette.primary])
            for (j, o) in part.options.enumerated() {
                let right = attempt != nil && j == part.answer
                let dim = attempt != nil && !right
                line.append(NSAttributedString(string: right ? "✓ " : "\(Self.letters[j]) ", attributes: [.font: MeadowPreviewPalette.font(22, .heavy), .foregroundColor: right ? UIColor.systemGreen : MeadowPreviewPalette.primary.withAlphaComponent(dim ? 0.45 : 1)]))
                line.append(NSAttributedString(string: o + (j < part.options.count - 1 ? "      " : ""), attributes: [.font: MeadowPreviewPalette.font(26, right ? .heavy : .semibold), .foregroundColor: right ? UIColor.systemGreen : MeadowPreviewPalette.ink.withAlphaComponent(dim ? 0.45 : 1)]))
            }
            out.append(line)
        }
        return out
    }
    private func readingText(attempt: QuizAttempt?) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, part) in question.parts.enumerated() {
            var mark = ""
            if let attempt { mark = attempt.correct[i] ? "✓ " : "✗ " }
            let color: UIColor = attempt == nil ? MeadowPreviewPalette.ink : (attempt!.correct[i] ? .systemGreen : .systemRed)
            out.append(NSAttributedString(string: "\(mark)\(i + 1). \(part.prompt ?? "")\n", attributes: [.font: MeadowPreviewPalette.font(24, .bold), .foregroundColor: color]))
            let options = part.options.enumerated().map { j, o in
                let tag = attempt != nil && j == part.answer ? "✔︎" : Self.letters[j]
                return "\(tag). \(o)"
            }.joined(separator: "    ")
            out.append(NSAttributedString(string: options + (i < question.parts.count - 1 ? "\n\n" : ""), attributes: [.font: MeadowPreviewPalette.font(21, .medium), .foregroundColor: MeadowPreviewPalette.muted]))
        }
        return out
    }

    /// Shows the answers and the reward line, then leaves.
    func reveal(_ attempt: QuizAttempt, dropName: String? = nil, headline: String? = nil, hold customHold: Double? = nil, then done: @escaping () -> Void) {
        revealed = true; ticker?.invalidate()
        clock.text = mode == .classwide ? "答案" : "\(attempt.rightCount)/\(attempt.correct.count)"
        clock.backgroundColor = attempt.rightCount == attempt.correct.count ? .systemGreen : attempt.rightCount == 0 ? .systemRed : .systemOrange
        let q = question!
        switch q.type {
        case .choice:
            let picked = attempt.picks.first ?? nil
            for (i, v) in optionViews.enumerated() {
                let right = i == q.answer, chose = i == picked
                UIView.animate(withDuration: 0.3) {
                    v.backgroundColor = right ? UIColor.systemGreen.withAlphaComponent(0.55) : chose ? UIColor.systemRed.withAlphaComponent(0.5) : MeadowPreviewPalette.glass(.thin)
                    v.alpha = right || chose ? 1 : 0.5
                }
                if right { v.transform = CGAffineTransform(scaleX: 0.94, y: 0.94); UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.8) { v.transform = .identity } }
            }
        case .flashcard:
            let part = q.parts[0], right = attempt.correct[0]
            let said = attempt.picks[0].map { part.options[$0] } ?? attempt.texts[0]
            UIView.transition(with: faceBox, duration: 0.5, options: .transitionFlipFromRight) {
                // Front small on top, the right back large below (and what was said instead).
                let text = NSMutableAttributedString(string: q.prompt + "\n", attributes: [.font: MeadowPreviewPalette.font(30, .bold), .foregroundColor: MeadowPreviewPalette.muted])
                text.append(NSAttributedString(string: part.options[part.answer], attributes: [.font: MeadowPreviewPalette.font(72, .heavy), .foregroundColor: right ? UIColor.systemGreen : MeadowPreviewPalette.ink]))
                if !right { text.append(NSAttributedString(string: said.map { "\n说成了：\($0)" } ?? "\n✗ 答错", attributes: [.font: MeadowPreviewPalette.font(28, .semibold), .foregroundColor: UIColor.systemRed])) }
                self.face.attributedText = text
                self.faceBox.backgroundColor = right ? UIColor.systemGreen.withAlphaComponent(0.18) : MeadowPreviewPalette.glass(.medium)
            }
        case .fill:
            UIView.transition(with: prompt, duration: 0.35, options: .transitionCrossDissolve) { self.prompt.attributedText = self.fillText(answers: attempt) }
        case .reading:
            UIView.transition(with: questions, duration: 0.35, options: .transitionCrossDissolve) { self.questions.attributedText = self.readingText(attempt: attempt) }
        }
        let all = attempt.rightCount == attempt.correct.count
        if mode == .classwide { clock.backgroundColor = MeadowPreviewPalette.primary }
        var head = attempt.overtime ? "超时 · 不发奖励" : all ? "全对！" : attempt.rightCount == 0 ? "这次没答对" : "答对 \(attempt.rightCount)/\(attempt.correct.count)"
        if attempt.coins > 0 { head += "  +\(attempt.coins) 金币" }
        if attempt.score > 0 { head += "  +\(attempt.score) 积分" }
        if let dropName { head += "  掉落：\(dropName)" + ((attempt.dropCount ?? 1) > 1 ? "×\(attempt.dropCount!)" : "") }
        if let headline { head = headline }
        let icon = mode == .classwide ? "checkmark.seal.fill" : attempt.overtime ? "clock.badge.xmark" : all ? "checkmark.seal.fill" : attempt.rightCount == 0 ? "xmark.octagon.fill" : "circle.lefthalf.filled"
        let tint: UIColor = attempt.overtime ? MeadowPreviewPalette.muted : all ? .systemGreen : attempt.rightCount == 0 ? .systemRed : .systemOrange
        result.attributedText = MeadowGlassText.iconLine(icon, head + (q.explanation.map { "  ·  " + $0 } ?? ""), size: 20, tint: tint)
        UIView.animate(withDuration: 0.3) { self.result.alpha = 1 }
        setNeedsLayout()
        let hold: Double = customHold ?? (mode == .classwide || q.type == .reading || q.type == .fill ? 5 : (q.explanation == nil ? 3 : 4.5))
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }) { _ in self.removeFromSuperview(); done() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let q = question else { return }
        let width = min(q.type == .reading ? 1160 : 1000, bounds.width - 60), inner = width - 56
        var body: CGFloat
        switch q.type {
        case .choice:
            let promptH = ceil(prompt.sizeThatFits(CGSize(width: inner, height: 300)).height)
            let columns = optionViews.count <= 2 ? optionViews.count : 2, rows = (optionViews.count + columns - 1) / max(1, columns)
            body = promptH + 22 + CGFloat(rows) * 70 + CGFloat(max(0, rows - 1)) * 14
        case .flashcard: body = 260
        case .fill: body = min(bounds.height - 220, ceil(prompt.sizeThatFits(CGSize(width: inner, height: 700)).height) + 20)
        case .reading:
            let half = (min(1160, bounds.width - 60) - 56) * 0.5 - 16
            let need = max(passage.sizeThatFits(CGSize(width: half, height: .greatestFiniteMagnitude)).height, questions.sizeThatFits(CGSize(width: half, height: .greatestFiniteMagnitude)).height)
            body = min(bounds.height - 220, max(160, ceil(need)))
        }
        let height = min(bounds.height - 30, 24 + 40 + 18 + body + 18 + 56 + 20)
        card.frame = CGRect(x: (bounds.width - width) / 2, y: max(15, (bounds.height - height) / 2), width: width, height: height)
        clock.frame = CGRect(x: width - 28 - 120, y: 22, width: 120, height: 40)
        header.frame = CGRect(x: 28, y: 27, width: inner - 136, height: 30)
        let top: CGFloat = 22 + 40 + 18, avail = height - top - 18 - 56 - 20
        switch q.type {
        case .choice:
            let promptH = ceil(prompt.sizeThatFits(CGSize(width: inner, height: 300)).height)
            prompt.frame = CGRect(x: 28, y: top, width: inner, height: promptH)
            let columns = optionViews.count <= 2 ? optionViews.count : 2, gap: CGFloat = 14, optionH: CGFloat = 70
            let ow = (inner - CGFloat(columns - 1) * gap) / CGFloat(max(1, columns))
            for (i, v) in optionViews.enumerated() {
                let saved = v.transform; v.transform = .identity
                v.frame = CGRect(x: 28 + CGFloat(i % columns) * (ow + gap), y: prompt.frame.maxY + 22 + CGFloat(i / columns) * (optionH + gap), width: ow, height: optionH)
                v.transform = saved
                v.viewWithTag(1)?.frame = CGRect(x: 14, y: (optionH - 36) / 2, width: 36, height: 36)
                v.viewWithTag(2)?.frame = CGRect(x: 62, y: 6, width: ow - 76, height: optionH - 12)
            }
        case .flashcard:
            faceBox.frame = CGRect(x: 28 + inner * 0.15, y: top, width: inner * 0.7, height: avail)
            face.frame = faceBox.bounds.insetBy(dx: 24, dy: 16)
        case .fill:
            prompt.frame = CGRect(x: 28, y: top, width: inner, height: min(avail, ceil(prompt.sizeThatFits(CGSize(width: inner, height: avail)).height)))
        case .reading:
            // Text starts at the top of each column (a label would otherwise centre it in the space left).
            let left = inner * 0.5
            func fit(_ l: UILabel, _ w: CGFloat) -> CGFloat { min(avail, ceil(l.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)) }
            passage.frame = CGRect(x: 28, y: top, width: left - 16, height: fit(passage, left - 16))
            questions.frame = CGRect(x: 28 + left + 16, y: top, width: inner - left - 16, height: fit(questions, inner - left - 16))
        }
        result.frame = CGRect(x: 28, y: height - 76, width: inner, height: 56)
    }
}
