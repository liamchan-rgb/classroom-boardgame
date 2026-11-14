import UIKit
import ClassroomGameCore

/// A quiz event on the TV: the question large, the options as lettered cards. The teacher picks the class's answer
/// on the iPad; the card then marks the right option green (and a wrong pick red), shows the explanation, and leaves.
final class MeadowQuizCard: UIView {
    private let card = UIView(), prompt = UILabel(), header = UILabel(), result = UILabel()
    private var optionViews: [UIView] = []
    private static let letters = ["A", "B", "C", "D", "E", "F"]

    static func present(in host: UIView, question: QuizQuestion, place: String) -> MeadowQuizCard {
        host.subviews.compactMap { $0 as? MeadowQuizCard }.forEach { $0.removeFromSuperview() }
        let view = MeadowQuizCard(frame: host.bounds); view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.build(question, place: place); host.addSubview(view)
        view.alpha = 0; view.card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.6) { view.alpha = 1; view.card.transform = .identity }
        return view
    }
    private func build(_ q: QuizQuestion, place: String) {
        backgroundColor = UIColor.black.withAlphaComponent(0.45); layer.zPosition = 5200; isUserInteractionEnabled = false
        MeadowPreviewPalette.stylePanel(card); card.layer.borderColor = MeadowPreviewPalette.gold.withAlphaComponent(0.7).cgColor; card.layer.borderWidth = 1.5
        addSubview(card)
        header.attributedText = MeadowGlassText.iconLine("questionmark.bubble.fill", place + " · 答对 +\(q.reward)", size: 18, tint: MeadowPreviewPalette.gold)
        prompt.text = q.prompt; prompt.font = MeadowPreviewPalette.font(30, .bold); prompt.textColor = .white; prompt.numberOfLines = 0
        result.font = MeadowPreviewPalette.font(20, .semibold); result.textColor = MeadowPreviewPalette.ink; result.numberOfLines = 3; result.alpha = 0
        [header, prompt, result].forEach(card.addSubview)
        for (i, text) in q.options.enumerated() {
            let v = UIView(); v.backgroundColor = UIColor.white.withAlphaComponent(0.10); v.layer.cornerRadius = 14; v.layer.cornerCurve = .continuous
            v.layer.borderWidth = 1; v.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
            let letter = UILabel(); letter.text = Self.letters[i]; letter.textAlignment = .center; letter.font = MeadowPreviewPalette.font(22, .heavy)
            letter.textColor = UIColor(red: 0.08, green: 0.12, blue: 0.10, alpha: 1); letter.backgroundColor = MeadowPreviewPalette.gold; letter.layer.cornerRadius = 18; letter.clipsToBounds = true; letter.tag = 1
            let body = UILabel(); body.text = text; body.font = MeadowPreviewPalette.font(24, .semibold); body.textColor = .white; body.numberOfLines = 2; body.adjustsFontSizeToFitWidth = true; body.minimumScaleFactor = 0.6; body.tag = 2
            v.addSubview(letter); v.addSubview(body); card.addSubview(v); optionViews.append(v)
        }
    }
    /// Marks the answer. `choice` nil = skipped.
    func reveal(choice: Int?, question q: QuizQuestion, then done: @escaping () -> Void) {
        for (i, v) in optionViews.enumerated() {
            let right = i == q.answer, picked = i == choice
            UIView.animate(withDuration: 0.3) {
                v.backgroundColor = right ? UIColor.systemGreen.withAlphaComponent(0.55) : picked ? UIColor.systemRed.withAlphaComponent(0.5) : UIColor.white.withAlphaComponent(0.05)
                v.alpha = right || picked ? 1 : 0.5
            }
            if right { v.transform = CGAffineTransform(scaleX: 0.94, y: 0.94); UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.8) { v.transform = .identity } }
        }
        let correct = choice == q.answer
        let head = choice == nil ? "跳过" : correct ? "答对了！+\(q.reward) 金币" : "答错了"
        result.attributedText = MeadowGlassText.iconLine(choice == nil ? "forward.fill" : correct ? "checkmark.seal.fill" : "xmark.octagon.fill", head + (q.explanation.map { "  ·  " + $0 } ?? ""), size: 20,
                                                        tint: choice == nil ? MeadowPreviewPalette.muted : correct ? .systemGreen : .systemRed)
        UIView.animate(withDuration: 0.3) { self.result.alpha = 1 }
        setNeedsLayout()
        DispatchQueue.main.asyncAfter(deadline: .now() + (q.explanation == nil ? 2.6 : 4.5)) { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }) { _ in self.removeFromSuperview(); done() }
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(980, bounds.width - 80), inner = width - 56
        let promptH = ceil(prompt.sizeThatFits(CGSize(width: inner, height: 300)).height)
        let columns = optionViews.count <= 2 ? optionViews.count : 2, rows = (optionViews.count + columns - 1) / max(1, columns)
        let optionH: CGFloat = 70, gap: CGFloat = 14
        let height = 28 + 30 + 14 + promptH + 22 + CGFloat(rows) * optionH + CGFloat(max(0, rows - 1)) * gap + 18 + 56 + 24
        card.frame = CGRect(x: (bounds.width - width) / 2, y: max(20, (bounds.height - height) / 2), width: width, height: min(bounds.height - 40, height))
        header.frame = CGRect(x: 28, y: 24, width: inner, height: 30)
        prompt.frame = CGRect(x: 28, y: header.frame.maxY + 14, width: inner, height: promptH)
        let ow = (inner - CGFloat(columns - 1) * gap) / CGFloat(max(1, columns))
        for (i, v) in optionViews.enumerated() {
            let saved = v.transform; v.transform = .identity
            v.frame = CGRect(x: 28 + CGFloat(i % columns) * (ow + gap), y: prompt.frame.maxY + 22 + CGFloat(i / columns) * (optionH + gap), width: ow, height: optionH)
            v.transform = saved
            v.viewWithTag(1)?.frame = CGRect(x: 14, y: (optionH - 36) / 2, width: 36, height: 36)
            v.viewWithTag(2)?.frame = CGRect(x: 62, y: 6, width: ow - 76, height: optionH - 12)
        }
        result.frame = CGRect(x: 28, y: card.bounds.height - 76, width: inner, height: 56)
    }
}
