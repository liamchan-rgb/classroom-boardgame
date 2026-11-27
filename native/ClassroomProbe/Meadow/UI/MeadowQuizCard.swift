import UIKit
import ClassroomGameCore
import MeadowClassroomSupport

/// A quiz on the TV for one student or the whole class: supports both full centered presentation and
/// a compact, edge-docked / draggable picture-friendly mode ("边看图边看题") synced live with the preview.
final class MeadowQuizCard: UIView {
    private let card = UIView(), dragHandle = UIView(), header = UILabel(), clock = UILabel(), prompt = UILabel(), result = UILabel()
    private let passage = UILabel(), questions = UILabel(), face = UILabel(), faceBox = UIView()
    /// Reading: soft panels behind the passage and the questions.
    private let passagePanel = UIView(), questionsPanel = UIView()
    private var optionViews: [UIView] = []
    private var question: QuizQuestion!
    private var playerName = "", placeName = ""
    private var start = Date(), limit = 60
    private var ticker: Timer?
    private var revealed = false
    private var lastAttempt: QuizAttempt?
    private var lastDropName: String?
    private var lastHeadline: String?
    private(set) var compact = false
    private(set) var anchor = ClassroomQuizCardLayout.defaultAnchor
    private(set) var topInset = ClassroomQuizCardLayout.edgeMargin
    /// Reports the card's current size and top safe inset (in 720-pt canvas units) so the teacher preview's
    /// drag overlay matches the rendered compact card pixel-for-pixel.
    var onLayoutReport: ((CGSize, CGFloat) -> Void)?

    static let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
    static let circled = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑪", "⑫"]

    private var mode: LiveQuiz.Mode = .personal
    /// Challenge: time left read from the challenge's clock (it stops between questions).
    private var countdown: (() -> Double)?
    /// How long the card takes to come in (the challenge clock starts after it).
    static let entrance = 0.45

    static func present(in host: UIView, question: QuizQuestion, player: String, place: String, start: Date, mode: LiveQuiz.Mode = .personal, countdown: (() -> Double)? = nil, compact: Bool = false, anchor: CGPoint = ClassroomQuizCardLayout.defaultAnchor, topInset: CGFloat = ClassroomQuizCardLayout.edgeMargin, animated: Bool = true, onLayoutReport: ((CGSize, CGFloat) -> Void)? = nil) -> MeadowQuizCard {
        host.subviews.compactMap { $0 as? MeadowQuizCard }.forEach { $0.removeFromSuperview() }
        let view = MeadowQuizCard(frame: host.bounds); view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.question = question; view.playerName = player; view.placeName = place
        view.start = start; view.limit = question.timeLimit; view.mode = mode; view.countdown = countdown
        view.compact = compact; view.anchor = ClassroomQuizCardLayout.clampedAnchor(anchor); view.topInset = topInset
        view.onLayoutReport = onLayoutReport
        view.build(); host.addSubview(view)
        view.layoutNow()
        if animated {
            view.alpha = 0; view.card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.6) { view.alpha = 1; view.card.transform = .identity }
        }
        return view
    }
    deinit { ticker?.invalidate() }
    override func removeFromSuperview() { ticker?.invalidate(); super.removeFromSuperview() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { setNeedsLayout() }
    }

    static func stars(_ q: QuizQuestion) -> String { q.difficulty.map { String(repeating: "★", count: $0) + String(repeating: "☆", count: 3 - $0) } ?? "" }

    /// Switches between centered and compact modes or moves the compact card in place without restarting timers.
    func setPresentation(compact newCompact: Bool, anchor newAnchor: CGPoint, topInset newTopInset: CGFloat, animated: Bool) {
        let clamped = ClassroomQuizCardLayout.clampedAnchor(newAnchor)
        let compactChanged = newCompact != compact
        let anchorChanged = abs(clamped.x - anchor.x) > 0.0005 || abs(clamped.y - anchor.y) > 0.0005
        let insetChanged = abs(newTopInset - topInset) > 0.5
        guard compactChanged || anchorChanged || insetChanged else { return }
        compact = newCompact
        anchor = clamped
        topInset = newTopInset
        if compactChanged { applyTypographyAndContent() }
        setNeedsLayout()
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.35, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.applyVisualChrome()
                self.layoutNow()
            }
        } else {
            applyVisualChrome()
            layoutNow()
        }
    }

    private func build() {
        let q = question!
        layer.zPosition = 5200; isUserInteractionEnabled = false
        MeadowPreviewPalette.stylePanel(card)
        card.backgroundColor = MeadowPreviewPalette.panel
        card.layer.borderColor = UIColor.white.cgColor
        card.layer.shadowColor = UIColor(red: 0.05, green: 0.14, blue: 0.18, alpha: 1).cgColor
        addSubview(card)

        dragHandle.backgroundColor = MeadowPreviewPalette.ink.withAlphaComponent(0.18)
        dragHandle.layer.cornerRadius = 2
        header.adjustsFontSizeToFitWidth = true; header.minimumScaleFactor = 0.6
        clock.textAlignment = .center; clock.textColor = .white; clock.clipsToBounds = true; clock.backgroundColor = MeadowPreviewPalette.primary
        prompt.textColor = MeadowPreviewPalette.ink; prompt.numberOfLines = 0
        result.textColor = MeadowPreviewPalette.ink; result.numberOfLines = 2; result.adjustsFontSizeToFitWidth = true; result.minimumScaleFactor = 0.7; result.alpha = 0
        [dragHandle, header, clock, result].forEach(card.addSubview)

        switch q.type {
        case .choice:
            prompt.text = q.prompt; card.addSubview(prompt)
            for (i, text) in q.options.enumerated() { optionViews.append(optionView(Self.letters[i], text)) }
        case .flashcard:
            faceBox.backgroundColor = MeadowPreviewPalette.glass(.medium); faceBox.layer.cornerCurve = .continuous
            faceBox.layer.borderWidth = 2; faceBox.layer.borderColor = UIColor.white.cgColor
            face.textColor = MeadowPreviewPalette.ink; face.textAlignment = .center; face.adjustsFontSizeToFitWidth = true
            faceBox.addSubview(face); card.addSubview(faceBox)
        case .fill:
            card.addSubview(prompt)
        case .reading:
            for panel in [passagePanel, questionsPanel] {
                panel.backgroundColor = UIColor.white.withAlphaComponent(0.5); panel.layer.cornerCurve = .continuous
                panel.layer.borderWidth = 1; panel.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor; card.addSubview(panel)
            }
            passage.numberOfLines = 0; passage.adjustsFontSizeToFitWidth = true; passage.minimumScaleFactor = 0.5
            questions.numberOfLines = 0; questions.adjustsFontSizeToFitWidth = true; questions.minimumScaleFactor = 0.5
            [passage, questions].forEach(card.addSubview)
        }
        applyTypographyAndContent()
        applyVisualChrome()
        tick()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common); ticker = t
    }

    private func applyVisualChrome() {
        backgroundColor = compact ? .clear : UIColor(red: 0.05, green: 0.15, blue: 0.18, alpha: 0.30)
        card.backgroundColor = compact ? MeadowPreviewPalette.panel.withAlphaComponent(0.95) : MeadowPreviewPalette.panel
        card.layer.cornerRadius = compact ? 18 : 20
        card.layer.borderWidth = compact ? 1.8 : 1.5
        card.layer.shadowOpacity = compact ? 0.28 : 0.14
        card.layer.shadowRadius = compact ? 18 : 14
        card.layer.shadowOffset = CGSize(width: 0, height: compact ? 8 : 6)
        dragHandle.alpha = compact ? 1 : 0
    }

    private func applyTypographyAndContent() {
        guard let q = question else { return }
        let stars = Self.stars(q)
        let iconName = mode == .classwide ? "person.3.fill" : mode == .practice ? "rectangle.on.rectangle.angled" : "person.crop.circle.fill"
        if compact {
            let shortText = "\(playerName) · \(q.type.title)\(stars.isEmpty ? "" : " " + stars) · +\(q.reward)币"
            header.attributedText = MeadowGlassText.iconLine(iconName, shortText, size: 14, tint: MeadowPreviewPalette.gold)
            clock.font = .monospacedDigitSystemFont(ofSize: 16, weight: .heavy)
            clock.layer.cornerRadius = 13
            result.font = MeadowPreviewPalette.font(16, .semibold)
        } else {
            let prize = "答对 +\(q.reward) 金币 +\(QuizRewards.steps) 行动"
            header.attributedText = MeadowGlassText.iconLine(iconName, "\(playerName) 作答 · \(q.type.title)\(stars.isEmpty ? "" : " " + stars) · \(prize) · \(placeName)", size: 18, tint: MeadowPreviewPalette.gold)
            clock.font = .monospacedDigitSystemFont(ofSize: 26, weight: .heavy)
            clock.layer.cornerRadius = 20
            result.font = MeadowPreviewPalette.font(20, .semibold)
        }

        switch q.type {
        case .choice:
            prompt.font = MeadowPreviewPalette.font(compact ? 21 : 30, .bold)
            prompt.numberOfLines = compact ? 3 : 0
            prompt.adjustsFontSizeToFitWidth = compact
            prompt.minimumScaleFactor = compact ? 0.72 : 1
            for v in optionViews {
                v.layer.cornerRadius = compact ? 11 : 14
                if let letter = v.viewWithTag(1) as? UILabel {
                    letter.font = MeadowPreviewPalette.font(compact ? 16 : 22, .heavy)
                    letter.layer.cornerRadius = compact ? 14 : 18
                }
                if let body = v.viewWithTag(2) as? UILabel {
                    body.font = MeadowPreviewPalette.font(compact ? 18 : 24, .semibold)
                }
            }
        case .flashcard:
            faceBox.layer.cornerRadius = compact ? 18 : 26
            if let attempt = lastAttempt, revealed {
                face.attributedText = flashRevealText(attempt, compact: compact)
                face.numberOfLines = 4
                face.minimumScaleFactor = 0.38
            } else {
                face.attributedText = nil
                face.text = q.prompt
                if compact {
                    let isSentence = q.prompt.count > 22
                    face.font = MeadowPreviewPalette.font(isSentence ? 30 : 44, .heavy)
                    face.numberOfLines = isSentence ? 3 : 2
                    face.minimumScaleFactor = 0.42
                } else {
                    face.font = MeadowPreviewPalette.font(72, .heavy)
                    face.numberOfLines = 3
                    face.minimumScaleFactor = 0.3
                }
            }
        case .fill:
            prompt.attributedText = fillText(answers: lastAttempt, compact: compact)
            prompt.numberOfLines = 0
            prompt.adjustsFontSizeToFitWidth = compact
            prompt.minimumScaleFactor = compact ? 0.65 : 1
        case .reading:
            let lines = NSMutableParagraphStyle()
            lines.lineSpacing = compact ? 4 : 7
            lines.paragraphSpacing = compact ? 6 : 10
            passage.attributedText = NSAttributedString(string: q.passage ?? "", attributes: [
                .font: MeadowPreviewPalette.font(compact ? 17.5 : 25, .medium),
                .foregroundColor: MeadowPreviewPalette.ink,
                .paragraphStyle: lines
            ])
            questions.attributedText = readingText(attempt: lastAttempt, compact: compact)
            for panel in [passagePanel, questionsPanel] { panel.layer.cornerRadius = compact ? 14 : 18 }
        }
        if let attempt = lastAttempt, revealed {
            updateResultText(attempt: attempt)
        }
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
        let left = countdown?() ?? Double(limit) - Date().timeIntervalSince(start)
        if left <= 0 {
            clock.text = "时间到"; clock.backgroundColor = UIColor.systemRed.withAlphaComponent(Int(Date().timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 0.9 : 0.6)
        } else {
            let whole = Int(ceil(left)); clock.text = String(format: "%d:%02d", whole / 60, whole % 60)
            clock.backgroundColor = left <= 10 ? UIColor.systemOrange : MeadowPreviewPalette.primary
        }
    }

    private func flashRevealText(_ attempt: QuizAttempt, compact: Bool) -> NSAttributedString {
        let q = question!, part = q.parts[0], right = attempt.correct[0]
        let said = attempt.picks[0].map { part.options[$0] } ?? attempt.texts[0]
        let frontSize: CGFloat = compact ? 17 : 30
        let backSize: CGFloat = compact ? 38 : 72
        let wrongSize: CGFloat = compact ? 17 : 28
        let text = NSMutableAttributedString(string: q.prompt + "\n", attributes: [.font: MeadowPreviewPalette.font(frontSize, .bold), .foregroundColor: MeadowPreviewPalette.muted])
        text.append(NSAttributedString(string: part.options[part.answer], attributes: [.font: MeadowPreviewPalette.font(backSize, .heavy), .foregroundColor: right ? UIColor.systemGreen : MeadowPreviewPalette.ink]))
        if !right {
            text.append(NSAttributedString(string: said.map { "\n说成了：\($0)" } ?? "\n✗ 答错", attributes: [.font: MeadowPreviewPalette.font(wrongSize, .semibold), .foregroundColor: UIColor.systemRed]))
        }
        return text
    }

    /// The sentence with blanks as ①②…; after the reveal each blank holds the right answer (green), with what the
    /// student said struck through in red when it was wrong.
    private func fillText(answers attempt: QuizAttempt?, compact: Bool) -> NSAttributedString {
        let mainSize: CGFloat = compact ? 22 : 32
        let numSize: CGFloat = compact ? 17 : 24
        let wrongSize: CGFloat = compact ? 18 : 26
        let optNumSize: CGFloat = compact ? 18 : 26
        let optLetterSize: CGFloat = compact ? 16 : 22
        let optWordSize: CGFloat = compact ? 19 : 26
        let blankSpaces = compact ? 8 : 14
        let out = NSMutableAttributedString(), base: [NSAttributedString.Key: Any] = [.font: MeadowPreviewPalette.font(mainSize, .bold), .foregroundColor: MeadowPreviewPalette.ink]
        var rest = Substring(question.prompt), n = 0
        while let open = rest.range(of: "{{"), let close = rest[open.upperBound...].range(of: "}}") {
            out.append(NSAttributedString(string: String(rest[..<open.lowerBound]), attributes: base))
            let part = question.parts[min(n, question.parts.count - 1)]
            if let attempt {
                let right = attempt.correct[n]
                if !right {
                    let said = attempt.picks[n].map { part.options[$0] } ?? attempt.texts[n] ?? "—"
                    out.append(NSAttributedString(string: " \(said) ", attributes: [.font: MeadowPreviewPalette.font(wrongSize, .semibold), .foregroundColor: UIColor.systemRed, .strikethroughStyle: NSUnderlineStyle.single.rawValue]))
                }
                out.append(NSAttributedString(string: " \(part.options[part.answer]) ", attributes: [.font: MeadowPreviewPalette.font(mainSize, .heavy), .foregroundColor: right ? UIColor.systemGreen : MeadowPreviewPalette.primary, .underlineStyle: NSUnderlineStyle.thick.rawValue]))
            } else {
                out.append(NSAttributedString(string: " \(Self.circled[min(n, 11)])", attributes: [.font: MeadowPreviewPalette.font(numSize, .heavy), .foregroundColor: MeadowPreviewPalette.primary]))
                out.append(NSAttributedString(string: String(repeating: "\u{00A0}", count: blankSpaces), attributes: [.font: MeadowPreviewPalette.font(mainSize, .heavy), .foregroundColor: MeadowPreviewPalette.primary,
                                                                                                         .underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: MeadowPreviewPalette.primary]))
                out.append(NSAttributedString(string: " ", attributes: base))
            }
            n += 1; rest = rest[close.upperBound...]
        }
        out.append(NSAttributedString(string: String(rest), attributes: base))
        for (i, part) in question.parts.enumerated() where part.options.count > 1 {
            let lead = (i == 0 && !compact) ? "\n\n" : "\n"
            let line = NSMutableAttributedString(string: lead + "\(Self.circled[min(i, 11)])  ", attributes: [.font: MeadowPreviewPalette.font(optNumSize, .heavy), .foregroundColor: MeadowPreviewPalette.primary])
            for (j, o) in part.options.enumerated() {
                let right = attempt != nil && j == part.answer
                let dim = attempt != nil && !right
                line.append(NSAttributedString(string: right ? "✓ " : "\(Self.letters[j]) ", attributes: [.font: MeadowPreviewPalette.font(optLetterSize, .heavy), .foregroundColor: right ? UIColor.systemGreen : MeadowPreviewPalette.primary.withAlphaComponent(dim ? 0.45 : 1)]))
                line.append(NSAttributedString(string: o + (j < part.options.count - 1 ? (compact ? "    " : "      ") : ""), attributes: [.font: MeadowPreviewPalette.font(optWordSize, right ? .heavy : .semibold), .foregroundColor: right ? UIColor.systemGreen : MeadowPreviewPalette.ink.withAlphaComponent(dim ? 0.45 : 1)]))
            }
            out.append(line)
        }
        return out
    }

    /// Reading: each question on its own line, then its options one per line (letter, then the words, wrapped
    /// lines kept under the words), with room between questions. After the reveal the right option is green with
    /// a tick and a wrong pick is red and struck through.
    private func readingText(attempt: QuizAttempt?, compact: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let qFontSize: CGFloat = compact ? 17 : 24
        let letterFontSize: CGFloat = compact ? 15 : 21
        let optFontSize: CGFloat = compact ? 16 : 22
        let indent1: CGFloat = compact ? 24 : 34
        let indent2: CGFloat = compact ? 52 : 72
        for (i, part) in question.parts.enumerated() {
            let qStyle = NSMutableParagraphStyle()
            qStyle.paragraphSpacingBefore = i == 0 ? 0 : (compact ? 10 : 20)
            qStyle.paragraphSpacing = compact ? 4 : 8
            qStyle.lineSpacing = compact ? 2 : 3
            qStyle.headIndent = indent1; qStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent1)]; qStyle.defaultTabInterval = indent1
            var mark = "\(i + 1)."
            if let attempt { mark = attempt.correct[i] ? "✓" : "✗" }
            let color: UIColor = attempt == nil ? MeadowPreviewPalette.ink : (attempt!.correct[i] ? .systemGreen : .systemRed)
            out.append(NSAttributedString(string: "\(mark)\t\(part.prompt ?? "")\n", attributes: [.font: MeadowPreviewPalette.font(qFontSize, .bold), .foregroundColor: color, .paragraphStyle: qStyle]))
            let oStyle = NSMutableParagraphStyle()
            oStyle.paragraphSpacing = compact ? 2.5 : 5
            oStyle.lineSpacing = compact ? 1 : 2
            oStyle.firstLineHeadIndent = indent1; oStyle.headIndent = indent2; oStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent2)]
            for (j, o) in part.options.enumerated() {
                let right = attempt != nil && j == part.answer
                let pickedWrong = attempt != nil && !right && attempt!.picks.indices.contains(i) && attempt!.picks[i] == j
                let dim = attempt != nil && !right && !pickedWrong
                let letterColor: UIColor = right ? .systemGreen : pickedWrong ? .systemRed : MeadowPreviewPalette.primary.withAlphaComponent(dim ? 0.45 : 1)
                let textColor: UIColor = right ? .systemGreen : pickedWrong ? .systemRed : MeadowPreviewPalette.ink.withAlphaComponent(dim ? 0.45 : 0.9)
                let last = i == question.parts.count - 1 && j == part.options.count - 1
                out.append(NSAttributedString(string: (right ? "✓" : Self.letters[j]) + "\t", attributes: [.font: MeadowPreviewPalette.font(letterFontSize, .heavy), .foregroundColor: letterColor, .paragraphStyle: oStyle]))
                var attrs: [NSAttributedString.Key: Any] = [.font: MeadowPreviewPalette.font(optFontSize, right ? .heavy : .medium), .foregroundColor: textColor, .paragraphStyle: oStyle]
                if pickedWrong { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                out.append(NSAttributedString(string: o + (last ? "" : "\n"), attributes: attrs))
            }
        }
        return out
    }

    private func updateResultText(attempt: QuizAttempt) {
        let q = question!
        let all = attempt.rightCount == attempt.correct.count
        var head = attempt.overtime ? "超时 · 不发奖励" : all ? "全对！" : attempt.rightCount == 0 ? "这次没答对" : "答对 \(attempt.rightCount)/\(attempt.correct.count)"
        if attempt.coins > 0 { head += "  +\(attempt.coins) 金币" }
        if attempt.coins > 0 && !attempt.correct.isEmpty && attempt.rightCount == attempt.correct.count { head += "  +\(QuizRewards.steps) 行动" }
        if attempt.score > 0 { head += "  +\(attempt.score) 积分" }
        if let dropName = lastDropName { head += "  掉落：\(dropName)" + ((attempt.dropCount ?? 1) > 1 ? "×\(attempt.dropCount!)" : "") }
        if let headline = lastHeadline { head = headline }
        let icon = mode == .classwide ? "checkmark.seal.fill" : attempt.overtime ? "clock.badge.xmark" : all ? "checkmark.seal.fill" : attempt.rightCount == 0 ? "xmark.octagon.fill" : "circle.lefthalf.filled"
        let tint: UIColor = attempt.overtime ? MeadowPreviewPalette.muted : all ? .systemGreen : attempt.rightCount == 0 ? .systemRed : .systemOrange
        result.attributedText = MeadowGlassText.iconLine(icon, head + (q.explanation.map { "  ·  " + $0 } ?? ""), size: compact ? 16 : 20, tint: tint)
    }

    /// Shows the answers and the reward line, then leaves.
    func reveal(_ attempt: QuizAttempt, dropName: String? = nil, headline: String? = nil, hold customHold: Double? = nil, then done: @escaping () -> Void) {
        revealed = true; ticker?.invalidate()
        lastAttempt = attempt; lastDropName = dropName; lastHeadline = headline
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
            let right = attempt.correct[0]
            UIView.transition(with: faceBox, duration: 0.5, options: .transitionFlipFromRight) {
                self.face.attributedText = self.flashRevealText(attempt, compact: self.compact)
                self.face.numberOfLines = 4
                self.face.minimumScaleFactor = 0.38
                self.faceBox.backgroundColor = right ? UIColor.systemGreen.withAlphaComponent(0.18) : MeadowPreviewPalette.glass(.medium)
            }
        case .fill:
            UIView.transition(with: prompt, duration: 0.35, options: .transitionCrossDissolve) { self.prompt.attributedText = self.fillText(answers: attempt, compact: self.compact) }
        case .reading:
            UIView.transition(with: questions, duration: 0.35, options: .transitionCrossDissolve) { self.questions.attributedText = self.readingText(attempt: attempt, compact: self.compact) }
        }
        if mode == .classwide { clock.backgroundColor = MeadowPreviewPalette.primary }
        updateResultText(attempt: attempt)
        setNeedsLayout()
        UIView.animate(withDuration: 0.28) {
            self.result.alpha = 1
            if self.compact { self.layoutNow() }
        }
        let hold: Double = customHold ?? (mode == .classwide || q.type == .reading || q.type == .fill ? 5 : (q.explanation == nil ? 3 : 4.5))
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }) { _ in self.removeFromSuperview(); done() }
        }
    }

    /// Chooses 1 horizontal row for short choice options in compact mode, or 2 columns for longer choices.
    private func compactChoiceColumns(innerWidth: CGFloat, gap: CGFloat) -> Int {
        let count = optionViews.count
        guard count > 1 else { return max(1, count) }
        if count <= 4 {
            let singleW = (innerWidth - CGFloat(count - 1) * gap) / CGFloat(count)
            let availTextW = singleW - 56
            if availTextW >= 54 {
                let font = MeadowPreviewPalette.font(18, .semibold)
                let allFitOneLine = optionViews.allSatisfy { v in
                    guard let body = v.viewWithTag(2) as? UILabel, let text = body.text else { return true }
                    let measured = (text as NSString).size(withAttributes: [.font: font]).width
                    return measured <= availTextW * 1.15
                }
                if allFitOneLine { return count }
            }
        }
        return min(2, count)
    }

    /// Places this card's subviews right away. Not `layoutIfNeeded()`: UIKit then also lays out every ancestor that
    /// needs it, and this card is created / switched / revealed from inside SwiftUI view updates (it lives in a
    /// UIViewRepresentable), so that re-entered SwiftUI's layout of its hosting view mid-update — memory corruption
    /// that crashed the app a little later in SwiftUI layout (worst with the public window open: two cards).
    func layoutNow() {
        guard bounds.width > 0, bounds.height > 0 else { setNeedsLayout(); return }
        layoutSubviews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let q = question, bounds.width > 0, bounds.height > 0 else { return }
        if compact {
            layoutCompact(q)
        } else {
            layoutCentered(q)
        }
        card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds, cornerRadius: card.layer.cornerRadius).cgPath
    }

    private func layoutCentered(_ q: QuizQuestion) {
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
            let half = (min(1160, bounds.width - 60) - 56) * 0.5 - 12 - 36
            let need = max(passage.sizeThatFits(CGSize(width: half, height: .greatestFiniteMagnitude)).height, questions.sizeThatFits(CGSize(width: half, height: .greatestFiniteMagnitude)).height) + 36
            body = min(bounds.height - 220, max(180, ceil(need)))
        }
        let height = min(bounds.height - 30, 24 + 40 + 18 + body + 18 + 56 + 20)
        let savedTransform = card.transform
        card.transform = .identity
        card.frame = CGRect(x: (bounds.width - width) / 2, y: max(15, (bounds.height - height) / 2), width: width, height: height)
        card.transform = savedTransform
        dragHandle.frame = CGRect(x: (width - 36) / 2, y: 6, width: 36, height: 4)
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
            let left = inner * 0.5
            func fit(_ l: UILabel, _ w: CGFloat) -> CGFloat { min(avail, ceil(l.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)) }
            let pad: CGFloat = 18
            let pw = left - 12 - 2 * pad, qw = inner - left - 12 - 2 * pad
            passage.frame = CGRect(x: 28 + pad, y: top + pad, width: pw, height: min(avail - 2 * pad, fit(passage, pw)))
            questions.frame = CGRect(x: 28 + left + 12 + pad, y: top + pad, width: qw, height: min(avail - 2 * pad, fit(questions, qw)))
            passagePanel.frame = CGRect(x: 28, y: top, width: left - 12, height: avail)
            questionsPanel.frame = CGRect(x: 28 + left + 12, y: top, width: inner - left - 12, height: avail)
        }
        result.frame = CGRect(x: 28, y: height - 76, width: inner, height: 56)
        reportLayout(size: .zero, topInset: topInset)
    }

    private func layoutCompact(_ q: QuizQuestion) {
        let padX: CGFloat = 18
        let topPad: CGFloat = 14
        let headerH: CGFloat = 26
        let top: CGFloat = topPad + headerH + 8
        let footerH: CGFloat = revealed ? 42 : 0
        let bottomPad: CGFloat = 14
        let maxW = max(300, bounds.width - ClassroomQuizCardLayout.edgeMargin * 2)

        let width: CGFloat
        switch q.type {
        case .flashcard:
            let isSentence = q.prompt.count > 22
            let frontW = (q.prompt as NSString).size(withAttributes: [.font: MeadowPreviewPalette.font(isSentence ? 30 : 44, .heavy)]).width
            let backStr = q.parts.first.map { $0.options[$0.answer] } ?? ""
            let backW = revealed ? (backStr as NSString).size(withAttributes: [.font: MeadowPreviewPalette.font(38, .heavy)]).width : 0
            let headerMinW: CGFloat = 360
            let desired = max(headerMinW, max(frontW, backW) + 92)
            width = min(maxW, min(isSentence ? 760 : 680, desired))
        case .choice:
            width = min(maxW, 920)
        case .fill:
            width = min(maxW, 920)
        case .reading:
            width = min(maxW, 980)
        }

        let inner = max(120, width - padX * 2)
        let maxBodyH = max(90, bounds.height - topInset - ClassroomQuizCardLayout.edgeMargin - top - footerH - bottomPad)
        let body: CGFloat
        switch q.type {
        case .choice:
            let promptH = min(96, ceil(prompt.sizeThatFits(CGSize(width: inner, height: 120)).height))
            let gap: CGFloat = 8
            let columns = compactChoiceColumns(innerWidth: inner, gap: gap)
            let optionH: CGFloat = columns == optionViews.count ? 44 : 48
            let rows = (optionViews.count + columns - 1) / max(1, columns)
            body = promptH + 10 + CGFloat(rows) * optionH + CGFloat(max(0, rows - 1)) * gap
        case .flashcard:
            if revealed {
                let wrongExtra: CGFloat = (lastAttempt?.correct.first == false) ? 24 : 0
                let measured = ceil(face.sizeThatFits(CGSize(width: inner - 28, height: 200)).height) + 22
                body = min(maxBodyH, max(112 + wrongExtra, min(168, measured)))
            } else {
                let measured = ceil(face.sizeThatFits(CGSize(width: inner - 28, height: 150)).height) + 26
                body = min(maxBodyH, max(82, min(132, measured)))
            }
        case .fill:
            let cap = min(maxBodyH, bounds.height * 0.40)
            body = min(cap, max(78, ceil(prompt.sizeThatFits(CGSize(width: inner, height: cap)).height) + 8))
        case .reading:
            let half = inner * 0.5 - 8 - 24
            let need = max(passage.sizeThatFits(CGSize(width: half, height: .greatestFiniteMagnitude)).height,
                           questions.sizeThatFits(CGSize(width: half, height: .greatestFiniteMagnitude)).height) + 24
            body = min(min(maxBodyH, min(bounds.height * 0.42, 300)), max(150, ceil(need)))
        }

        let height = min(bounds.height - topInset - ClassroomQuizCardLayout.edgeMargin, top + body + footerH + bottomPad)
        let cardSize = CGSize(width: width, height: max(110, height))
        let targetFrame = ClassroomQuizCardLayout.compactFrame(cardSize: cardSize, in: bounds.size, anchor: anchor, topInset: topInset)
        let savedTransform = card.transform
        card.transform = .identity
        card.frame = targetFrame
        card.transform = savedTransform

        dragHandle.frame = CGRect(x: (width - 36) / 2, y: 5, width: 36, height: 4)
        clock.frame = CGRect(x: width - padX - 76, y: topPad, width: 76, height: headerH)
        header.frame = CGRect(x: padX, y: topPad + 2, width: inner - 84, height: 22)

        let avail = max(56, cardSize.height - top - footerH - bottomPad)
        switch q.type {
        case .choice:
            let promptH = min(96, ceil(prompt.sizeThatFits(CGSize(width: inner, height: 120)).height))
            prompt.frame = CGRect(x: padX, y: top, width: inner, height: promptH)
            let gap: CGFloat = 8
            let columns = compactChoiceColumns(innerWidth: inner, gap: gap)
            let optionH: CGFloat = columns == optionViews.count ? 44 : 48
            let ow = (inner - CGFloat(columns - 1) * gap) / CGFloat(max(1, columns))
            for (i, v) in optionViews.enumerated() {
                let saved = v.transform; v.transform = .identity
                v.frame = CGRect(x: padX + CGFloat(i % columns) * (ow + gap), y: prompt.frame.maxY + 10 + CGFloat(i / columns) * (optionH + gap), width: ow, height: optionH)
                v.transform = saved
                v.viewWithTag(1)?.frame = CGRect(x: 9, y: (optionH - 28) / 2, width: 28, height: 28)
                v.viewWithTag(2)?.frame = CGRect(x: 44, y: 4, width: max(20, ow - 52), height: optionH - 8)
            }
        case .flashcard:
            faceBox.frame = CGRect(x: padX, y: top, width: inner, height: avail)
            face.frame = faceBox.bounds.insetBy(dx: 14, dy: 8)
        case .fill:
            prompt.frame = CGRect(x: padX, y: top, width: inner, height: min(avail, ceil(prompt.sizeThatFits(CGSize(width: inner, height: avail)).height)))
        case .reading:
            let left = inner * 0.5
            func fit(_ l: UILabel, _ w: CGFloat) -> CGFloat { min(avail, ceil(l.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)) }
            let pad: CGFloat = 12
            let pw = left - 8 - 2 * pad, qw = inner - left - 8 - 2 * pad
            passage.frame = CGRect(x: padX + pad, y: top + pad, width: pw, height: min(avail - 2 * pad, fit(passage, pw)))
            questions.frame = CGRect(x: padX + left + 8 + pad, y: top + pad, width: qw, height: min(avail - 2 * pad, fit(questions, qw)))
            passagePanel.frame = CGRect(x: padX, y: top, width: left - 8, height: avail)
            questionsPanel.frame = CGRect(x: padX + left + 8, y: top, width: inner - left - 8, height: avail)
        }
        result.frame = CGRect(x: padX, y: cardSize.height - bottomPad - 36, width: inner, height: revealed ? 36 : 0)
        reportLayout(size: cardSize, topInset: topInset)
    }

    private func reportLayout(size: CGSize, topInset: CGFloat) {
        onLayoutReport?(size, topInset)
    }
}
