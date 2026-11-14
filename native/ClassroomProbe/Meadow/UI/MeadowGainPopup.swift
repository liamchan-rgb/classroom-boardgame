import UIKit
import ClassroomGameCore

/// What one hero gained between two game states: coins, score and items put into their pack.
struct MeadowGain {
    let unitName: String
    var coins = 0, score = 0
    var items: [(id: String, count: Int)] = []
    var isEmpty: Bool { coins <= 0 && score <= 0 && items.isEmpty }

    /// Everything the heroes gained from `before` to `after` (losses are not listed).
    static func between(_ before: GameState, _ after: GameState) -> [MeadowGain] {
        after.players.compactMap { unit in
            guard let old = before.units[unit.id] else { return nil }
            var gain = MeadowGain(unitName: unit.name)
            gain.coins = max(0, unit.coins - old.coins); gain.score = max(0, unit.score - old.score)
            for (item, count) in unit.inventory.sorted(by: { $0.key < $1.key }) where count > (old.inventory[item] ?? 0) {
                gain.items.append((item, count - (old.inventory[item] ?? 0)))
            }
            return gain.isEmpty ? nil : gain
        }
    }
}

/// The "you received" card: shown when things go into a pack (supplies claimed, a find on the road, a purchase) and when a battle ends.
/// A dim backdrop, a parchment-green card that springs in, one row per hero with a chip for every gain (the chips pop in one after
/// another), and a button to put it away. Tapping outside also closes it.
final class MeadowGainPopup: UIView {
    private let card = UIView(), stack = UIStackView(), button = MeadowPreviewPalette.iconButton("checkmark", "收下", prominent: true)
    private var chips: [UIView] = []
    private var onClose: (() -> Void)?

    /// Shows the card over `host`. With no gains, `emptyText` is shown instead (nil: nothing is shown at all).
    static func present(in host: UIView, title: String, subtitle: String? = nil, gains: [MeadowGain], catalog: GameCatalog?, emptyText: String? = nil, autoDismiss: Double? = nil, onClose: (() -> Void)? = nil) {
        guard !gains.isEmpty || emptyText != nil else { onClose?(); return }
        host.subviews.compactMap { $0 as? MeadowGainPopup }.forEach { $0.removeFromSuperview() }
        let popup = MeadowGainPopup(frame: host.bounds)
        popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]; popup.onClose = onClose
        popup.build(title: title, subtitle: subtitle, gains: gains, catalog: catalog, emptyText: emptyText)
        host.addSubview(popup); popup.appear()
        // Stays until put away (button / outside tap, or a tap relayed from the teacher window).
        if let autoDismiss { DispatchQueue.main.asyncAfter(deadline: .now() + autoDismiss) { [weak popup] in popup?.close() } }
    }

    private func build(title: String, subtitle: String?, gains: [MeadowGain], catalog: GameCatalog?, emptyText: String?) {
        backgroundColor = UIColor.black.withAlphaComponent(0.35); layer.zPosition = 5000
        accessibilityIdentifier = "meadowGainPopup"; accessibilityViewIsModal = true
        MeadowPreviewPalette.stylePanel(card); card.layer.borderWidth = 1.5; card.layer.borderColor = MeadowPreviewPalette.gold.withAlphaComponent(0.7).cgColor
        card.layer.shadowColor = MeadowPreviewPalette.gold.cgColor; card.layer.shadowRadius = 24; card.layer.shadowOpacity = 0.45; card.layer.shadowOffset = .zero
        addSubview(card)
        stack.axis = .vertical; stack.spacing = 12; stack.alignment = .fill
        card.addSubview(stack)
        let heading = MeadowPreviewPalette.label(title, size: 26, weight: .heavy); heading.textColor = MeadowPreviewPalette.gold; heading.textAlignment = .center
        stack.addArrangedSubview(heading)
        if let subtitle { let line = MeadowPreviewPalette.label(subtitle, size: 15, weight: .semibold); line.textAlignment = .center; line.numberOfLines = 0; line.textColor = MeadowPreviewPalette.muted; stack.addArrangedSubview(line) }
        let rule = UIView(); rule.backgroundColor = MeadowPreviewPalette.border; rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stack.addArrangedSubview(rule)
        if gains.isEmpty, let emptyText {
            let line = MeadowPreviewPalette.label(emptyText, size: 17, weight: .semibold); line.textAlignment = .center; line.numberOfLines = 0
            stack.addArrangedSubview(line)
        }
        for gain in gains {
            let name = MeadowPreviewPalette.label(gain.unitName, size: 16, weight: .bold)
            stack.addArrangedSubview(name)
            let flow = MeadowChipFlow()
            if gain.coins > 0 { flow.add(chip(icon: UIImage(systemName: "circle.hexagongrid.circle.fill"), tint: MeadowPreviewPalette.gold, text: "+\(gain.coins)")) }
            if gain.score > 0 { flow.add(chip(icon: UIImage(systemName: "star.circle.fill"), tint: UIColor(red: 0.55, green: 0.85, blue: 1, alpha: 1), text: "+\(gain.score)")) }
            for item in gain.items {
                let itemName = (try? catalog?.item(item.id).name) ?? item.id
                flow.add(chip(icon: MeadowItemIcon.image(item.id, item: try? catalog?.item(item.id)), tint: nil, text: "\(itemName) ×\(item.count)"))
            }
            chips += flow.chips
            stack.addArrangedSubview(flow)
        }
        button.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        button.accessibilityIdentifier = "meadowGainPopupClose"
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        stack.setCustomSpacing(18, after: stack.arrangedSubviews.last ?? heading)
        stack.addArrangedSubview(button)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backdropTapped(_:))))
    }

    /// The pack icon of an item, if the app has one.
    private static func icon(_ id: String) -> UIImage? {
        let cap = id.prefix(1).uppercased() + id.dropFirst()
        return UIImage(named: "PixelIcon" + cap) ?? UIImage(named: "MeadowParty" + cap) ?? UIImage(named: "Meadow" + cap + "Icon") ?? UIImage(named: HeroFrames.accessoryVisual(id)?.iconAsset ?? "") ?? UIImage(systemName: "shippingbox.fill")
    }

    private func chip(icon: UIImage?, tint: UIColor?, text: String) -> UIView {
        let view = UIView(); view.backgroundColor = UIColor.white.withAlphaComponent(0.12); view.layer.cornerRadius = 22; view.layer.cornerCurve = .continuous; view.layer.borderWidth = 1; view.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        let image = UIImageView(image: tint == nil ? icon?.withRenderingMode(.alwaysOriginal) : icon); image.tintColor = tint ?? MeadowPreviewPalette.gold
        image.contentMode = .scaleAspectFit; image.layer.magnificationFilter = .nearest
        let label = MeadowPreviewPalette.label(text, size: 16, weight: .bold); label.adjustsFontSizeToFitWidth = false
        let width = ceil(label.intrinsicContentSize.width)
        image.frame = CGRect(x: 8, y: 6, width: 32, height: 32); label.frame = CGRect(x: 46, y: 0, width: width, height: 44)
        view.addSubview(image); view.addSubview(label)
        view.frame = CGRect(x: 0, y: 0, width: 46 + width + 12, height: 44)
        return view
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(520, bounds.width - 48), inner = width - 48
        for case let flow as MeadowChipFlow in stack.arrangedSubviews { flow.arrange(width: inner) }
        let height = stack.systemLayoutSizeFitting(CGSize(width: inner, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let saved = card.transform; card.transform = .identity
        card.frame = CGRect(x: (bounds.width - width) / 2, y: max(16, (bounds.height - height - 48) / 2), width: width, height: min(bounds.height - 32, height + 48))
        card.transform = saved
        stack.frame = CGRect(x: 24, y: 24, width: inner, height: height)
    }

    private func appear() {
        layoutIfNeeded()
        alpha = 0; card.transform = CGAffineTransform(scaleX: 0.7, y: 0.7).translatedBy(x: 0, y: 40)
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.62, initialSpringVelocity: 0.8, options: .allowUserInteraction) { self.card.transform = .identity }
        for (i, chip) in chips.enumerated() {
            chip.alpha = 0; chip.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
            UIView.animate(withDuration: 0.45, delay: 0.25 + 0.09 * Double(i), usingSpringWithDamping: 0.5, initialSpringVelocity: 0.9, options: .allowUserInteraction) { chip.alpha = 1; chip.transform = .identity }
        }
        UIAccessibility.post(notification: .screenChanged, argument: card)
    }
    @objc private func backdropTapped(_ r: UITapGestureRecognizer) { if !card.frame.contains(r.location(in: self)) { close() } }
    /// A tap relayed from the teacher window (the public display itself takes no touches): the button or
    /// anywhere outside the card puts the card away. Returns true when the tap closed it.
    @discardableResult func relayTap(_ point: CGPoint) -> Bool {
        let onButton = button.convert(button.bounds, to: self).insetBy(dx: -12, dy: -12).contains(point)
        guard onButton || !card.frame.contains(point) else { return false }
        if onButton { button.transform = CGAffineTransform(scaleX: 0.92, y: 0.92) }
        close(); return true
    }
    func close() {
        guard isUserInteractionEnabled else { return }
        isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 0; self.card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9) }) { _ in
            self.removeFromSuperview(); self.onClose?()
        }
    }
}

/// Chips laid out left to right, wrapping to new lines.
private final class MeadowChipFlow: UIView {
    private(set) var chips: [UIView] = []
    private var height: NSLayoutConstraint?
    func add(_ chip: UIView) { chips.append(chip); addSubview(chip) }
    func arrange(width: CGFloat) {
        var x: CGFloat = 0, y: CGFloat = 0
        for chip in chips {
            let saved = chip.transform; chip.transform = .identity
            let w = min(width, chip.bounds.width)
            if x > 0, x + w > width { x = 0; y += 52 }
            chip.frame = CGRect(x: x, y: y, width: w, height: 44); chip.transform = saved
            x += w + 8
        }
        let total = chips.isEmpty ? 0 : y + 44
        if let height { height.constant = total } else { height = heightAnchor.constraint(equalToConstant: total); height?.isActive = true }
    }
}
