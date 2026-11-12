import UIKit
import ClassroomGameCore

/// The turn order of a party battle as one bar: a rail with every unit's face on it, in the order they act.
///
/// * The rail is filled in gold up to whoever is acting; a spark runs along the filled part, towards that unit.
/// * The acting unit's face is larger, ringed in gold and breathing, with a small arrow above it. Faces that already acted are dim with a
///   tick; fallen ones are grey. Ring colour says the side (green ours, red theirs); a white ring marks the picked targets.
/// * No health, no numbers, no tags: those live on the field. The only words are the short names under the faces and the round at the left end.
/// * The faces are spread over the whole bar, so 1v1 (two faces) and 7v3 (ten) both fill it; they shrink a little when there are many.
/// * When the turn passes on, the gold fill glides to the next face, which pops; tapping a face picks it as the target.
final class MeadowTurnOrderView: UIView {
    struct Entry {
        let id: String, name: String
        let hp: Int, maxHP: Int, shield: Int
        let enemy: Bool, acted: Bool, down: Bool
    }
    var onSelect: ((String) -> Void)?
    private let round = UILabel()
    private let rail = UIView(), fill = UIView(), spark = UIView()
    private var tokens: [String: MeadowTurnOrderToken] = [:]
    private var order: [String] = []
    private var currentID: String?
    private var finished = false

    override init(frame: CGRect) {
        super.init(frame: frame); MeadowPreviewPalette.stylePanel(self)
        round.font = .systemFont(ofSize: 15, weight: .heavy); round.textColor = MeadowPreviewPalette.gold; round.textAlignment = .center
        round.layer.cornerRadius = 9; round.layer.borderWidth = 1.5; round.layer.borderColor = MeadowPreviewPalette.gold.withAlphaComponent(0.7).cgColor
        round.backgroundColor = UIColor(red: 0.23, green: 0.19, blue: 0.07, alpha: 1); round.clipsToBounds = true
        rail.backgroundColor = UIColor.black.withAlphaComponent(0.55); rail.layer.cornerRadius = 4
        rail.layer.borderWidth = 1; rail.layer.borderColor = MeadowPreviewPalette.border.cgColor
        fill.backgroundColor = MeadowPreviewPalette.gold; fill.layer.cornerRadius = 4
        fill.layer.shadowColor = MeadowPreviewPalette.gold.cgColor; fill.layer.shadowRadius = 6; fill.layer.shadowOpacity = 0.8; fill.layer.shadowOffset = .zero
        spark.backgroundColor = .white; spark.layer.cornerRadius = 3
        spark.layer.shadowColor = UIColor.white.cgColor; spark.layer.shadowRadius = 5; spark.layer.shadowOpacity = 1; spark.layer.shadowOffset = .zero
        [rail, fill, spark, round].forEach(addSubview)
        accessibilityIdentifier = "meadowTurnOrder"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `entries` in the battle's queue order. `current` is the unit acting (or about to act); `selected` the units picked as targets.
    func show(entries: [Entry], current: String?, round number: Int, selected: Set<String>, finished text: String? = nil) {
        let ids = entries.map(\.id)
        for id in tokens.keys where !ids.contains(id) { tokens.removeValue(forKey: id)?.removeFromSuperview() }
        for entry in entries where tokens[entry.id] == nil {
            let token = MeadowTurnOrderToken(id: entry.id)
            token.onTap = { [weak self] id in self?.onSelect?(id) }
            tokens[entry.id] = token; addSubview(token)
        }
        for entry in entries {
            let status: MeadowTurnOrderToken.Status = entry.down ? .down : entry.id == current ? .current : entry.acted ? .done : .waiting
            tokens[entry.id]?.update(entry, status: status, targeted: selected.contains(entry.id))
        }
        round.text = text ?? "第\(number)轮"
        let turnChanged = current != currentID, changed = ids != order || turnChanged || finished != (text != nil)
        order = ids; currentID = current; finished = text != nil
        if changed, window != nil {
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: [.allowUserInteraction, .beginFromCurrentState]) { self.setNeedsLayout(); self.layoutIfNeeded() }
            if turnChanged, let current { tokens[current]?.pop() }
        } else { setNeedsLayout() }
    }

    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { setNeedsLayout() } }

    /// The unit whose face is under `point` (this view's coordinates), for clicks routed from the teacher's window.
    func unit(at point: CGPoint) -> String? {
        guard bounds.contains(point) else { return nil }
        return order.first { tokens[$0].map { !$0.isHidden && $0.frame.contains(point) } ?? false }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let h = bounds.height
        round.frame = CGRect(x: 10, y: (h - 30) / 2, width: 74, height: 30)
        let left = round.frame.maxX + 14, right = bounds.width - 14, n = order.count
        guard n > 0, right > left else { return }
        // Faces: evenly spread; the name sits under each face, the rail runs through their centres.
        let slot = (right - left) / CGFloat(n), nameH: CGFloat = 13
        let face = max(20, min(h - nameH - 16, slot - 10, 46))
        let cy = 6 + (h - nameH - 12) / 2
        var centres: [String: CGFloat] = [:]
        for (i, id) in order.enumerated() {
            guard let token = tokens[id] else { continue }
            let cx = left + slot * (CGFloat(i) + 0.5); centres[id] = cx
            token.face = id == currentID ? min(face * 1.22, h - nameH - 8) : face
            token.transform = .identity
            token.frame = CGRect(x: cx - slot / 2, y: 0, width: slot, height: h); token.railY = cy
            token.setNeedsLayout(); token.layoutIfNeeded()
        }
        let first = left + slot / 2, last = right - slot / 2
        rail.frame = CGRect(x: first, y: cy - 4, width: max(0, last - first), height: 8)
        let reach = finished ? last : (currentID.flatMap { centres[$0] } ?? first)
        fill.frame = CGRect(x: first, y: cy - 4, width: max(0, reach - first), height: 8)
        // The spark: runs from the start of the rail to the acting unit, over and over.
        spark.layer.removeAnimation(forKey: "run")
        spark.isHidden = finished || reach - first < 12
        if !spark.isHidden {
            spark.frame = CGRect(x: first, y: cy - 3, width: 14, height: 6)
            let run = CABasicAnimation(keyPath: "position.x"); run.fromValue = first; run.toValue = reach
            let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.15, 0.8, 1]
            let group = CAAnimationGroup(); group.animations = [run, fade]; group.duration = max(0.7, Double(reach - first) / 260); group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            spark.layer.add(group, forKey: "run")
        }
    }
}

/// One face on the rail.
private final class MeadowTurnOrderToken: UIView {
    enum Status { case current, waiting, done, down }
    var onTap: ((String) -> Void)?
    var face: CGFloat = 40, railY: CGFloat = 30
    private let id: String
    private let name = UILabel(), circle = UIView(), portrait = UIImageView(), badge = UILabel(), arrow = UILabel()
    private var status = Status.waiting
    private static let portraits: [UIImage?] = (1...3).map { index in
        guard let atlas = UIImage(named: "Hero\(index)Directions")?.cgImage else { return nil }
        let cell = atlas.height / HeroFrames.atlasRows
        return atlas.cropping(to: CGRect(x: 0, y: 0, width: cell, height: cell)).map { UIImage(cgImage: $0) }
    }
    init(id: String) {
        self.id = id
        super.init(frame: .zero); isAccessibilityElement = true; accessibilityIdentifier = "previewQueue\(id)"
        name.font = .systemFont(ofSize: 11, weight: .heavy); name.textAlignment = .center; name.adjustsFontSizeToFitWidth = true; name.minimumScaleFactor = 0.7
        circle.backgroundColor = MeadowPreviewPalette.card
        portrait.contentMode = .scaleAspectFit; portrait.layer.magnificationFilter = .nearest
        badge.font = .systemFont(ofSize: 11, weight: .heavy); badge.textAlignment = .center; badge.textColor = .white; badge.layer.cornerRadius = 8; badge.clipsToBounds = true
        arrow.text = "▼"; arrow.font = .systemFont(ofSize: 10, weight: .heavy); arrow.textColor = MeadowPreviewPalette.gold; arrow.textAlignment = .center
        [circle, portrait, badge, arrow, name].forEach(addSubview)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped() {
        onTap?(id)
        UIView.animate(withDuration: 0.08, animations: { self.circle.transform = CGAffineTransform(scaleX: 0.88, y: 0.88) }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8, options: .allowUserInteraction) { self.circle.transform = .identity }
        }
    }
    /// The turn just came to this unit.
    func pop() {
        transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        UIView.animate(withDuration: 0.55, delay: 0.1, usingSpringWithDamping: 0.42, initialSpringVelocity: 0.9, options: .allowUserInteraction) { self.transform = .identity }
    }

    func update(_ entry: MeadowTurnOrderView.Entry, status: Status, targeted: Bool) {
        self.status = status
        // The short name: "P1" for heroes, the species for monsters.
        name.text = entry.name.components(separatedBy: " · ").first ?? entry.name
        name.textColor = status == .current ? MeadowPreviewPalette.gold : MeadowPreviewPalette.ink
        if entry.id.hasPrefix("p"), let number = Int(entry.id.dropFirst()) { portrait.image = Self.portraits[(number - 1) % Self.portraits.count]; portrait.tintColor = nil }
        else { portrait.image = UIImage(systemName: "pawprint.fill"); portrait.tintColor = UIColor(red: 0.93, green: 0.45, blue: 0.38, alpha: 1) }
        let side: UIColor = entry.enemy ? UIColor(red: 0.92, green: 0.36, blue: 0.30, alpha: 1) : UIColor(red: 0.40, green: 0.85, blue: 0.56, alpha: 1)
        circle.layer.borderColor = (status == .current ? MeadowPreviewPalette.gold : targeted ? UIColor.white : status == .down ? UIColor.gray : side).cgColor
        circle.layer.borderWidth = status == .current ? 3.5 : targeted ? 3 : 2
        circle.layer.shadowColor = MeadowPreviewPalette.gold.cgColor; circle.layer.shadowOffset = .zero; circle.layer.shadowRadius = 9
        circle.layer.shadowOpacity = status == .current ? 0.95 : 0
        circle.layer.removeAnimation(forKey: "glow"); circle.layer.removeAnimation(forKey: "breathe"); arrow.layer.removeAnimation(forKey: "bob")
        arrow.isHidden = status != .current
        if status == .current {
            let pulse = CABasicAnimation(keyPath: "shadowOpacity"); pulse.fromValue = 0.3; pulse.toValue = 1; pulse.duration = 0.75; pulse.autoreverses = true; pulse.repeatCount = .infinity
            circle.layer.add(pulse, forKey: "glow")
            let breathe = CABasicAnimation(keyPath: "transform.scale"); breathe.fromValue = 1; breathe.toValue = 1.08; breathe.duration = 0.75; breathe.autoreverses = true; breathe.repeatCount = .infinity
            circle.layer.add(breathe, forKey: "breathe")
            let bob = CABasicAnimation(keyPath: "transform.translation.y"); bob.fromValue = -2; bob.toValue = 2; bob.duration = 0.45; bob.autoreverses = true; bob.repeatCount = .infinity
            arrow.layer.add(bob, forKey: "bob")
        }
        badge.isHidden = !(status == .done || status == .down)
        badge.text = status == .down ? "✕" : "✓"
        badge.backgroundColor = status == .down ? UIColor(red: 0.62, green: 0.14, blue: 0.12, alpha: 1) : UIColor(red: 0.55, green: 0.45, blue: 0.16, alpha: 1)
        let dim: CGFloat = status == .done ? 0.55 : status == .down ? 0.35 : 1
        circle.alpha = max(0.75, dim); portrait.alpha = dim; name.alpha = max(0.6, dim)
        accessibilityLabel = entry.name
        accessibilityValue = status == .current ? "当前行动" : status == .done ? "已行动" : status == .down ? "倒地" : "等待"
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 0 else { return }
        let saved = circle.transform; circle.transform = .identity
        circle.bounds = CGRect(x: 0, y: 0, width: face, height: face); circle.center = CGPoint(x: w / 2, y: railY)
        circle.layer.cornerRadius = face / 2; circle.transform = saved
        portrait.bounds = circle.bounds.insetBy(dx: face * 0.1, dy: face * 0.07); portrait.center = circle.center
        badge.frame = CGRect(x: w / 2 + face / 2 - 12, y: railY - face / 2 - 3, width: 16, height: 16)
        arrow.frame = CGRect(x: w / 2 - 8, y: max(-2, railY - face / 2 - 12), width: 16, height: 10)
        name.frame = CGRect(x: 1, y: min(bounds.height - 14, railY + face / 2 + 2), width: w - 2, height: 13)
    }
}
