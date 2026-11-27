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

/// The "you received" card: high-contrast rarity pills, tight padding, and zero washed-out text on light frosted glass.
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
        if let autoDismiss { DispatchQueue.main.asyncAfter(deadline: .now() + autoDismiss) { [weak popup] in popup?.close() } }
    }

    private func build(title: String, subtitle: String?, gains: [MeadowGain], catalog: GameCatalog?, emptyText: String?) {
        backgroundColor = UIColor(red: 0.04, green: 0.12, blue: 0.15, alpha: 0.36); layer.zPosition = 5000
        accessibilityIdentifier = "meadowGainPopup"; accessibilityViewIsModal = true
        MeadowPreviewPalette.stylePanel(card)
        card.backgroundColor = UIColor(red: 0.96, green: 0.98, blue: 0.98, alpha: 0.97)
        card.layer.borderWidth = 2; card.layer.borderColor = UIColor.white.cgColor
        card.layer.shadowColor = UIColor(red: 0.04, green: 0.16, blue: 0.20, alpha: 1).cgColor
        card.layer.shadowRadius = 24; card.layer.shadowOpacity = 0.36; card.layer.shadowOffset = CGSize(width: 0, height: 8)
        addSubview(card)

        stack.axis = .vertical; stack.spacing = 10; stack.alignment = .fill
        card.addSubview(stack)

        let heading = MeadowPreviewPalette.label(title, size: 25, weight: .heavy)
        heading.textColor = MeadowPreviewPalette.ink; heading.textAlignment = .center
        stack.addArrangedSubview(heading)

        if let subtitle {
            let line = MeadowPreviewPalette.label(subtitle, size: 14.5, weight: .semibold)
            line.textAlignment = .center; line.numberOfLines = 0; line.textColor = MeadowPreviewPalette.muted
            stack.addArrangedSubview(line)
        }

        let best = gains.flatMap { $0.items.map { MeadowItemRarity.of($0.id, item: try? catalog?.item($0.id)) } }.max() ?? .common
        if best >= .epic {
            let bannerWrap = UIView()
            bannerWrap.heightAnchor.constraint(equalToConstant: 32).isActive = true
            let banner = UILabel()
            banner.text = "  ✦ \(best.title)掉落 \(best.stars) ✦  "
            banner.font = MeadowPreviewPalette.font(16, .black)
            banner.textColor = .white
            banner.textAlignment = .center
            banner.backgroundColor = best.badgeColor
            banner.layer.cornerRadius = 15; banner.clipsToBounds = true
            banner.translatesAutoresizingMaskIntoConstraints = false
            bannerWrap.addSubview(banner)
            NSLayoutConstraint.activate([
                banner.centerXAnchor.constraint(equalTo: bannerWrap.centerXAnchor),
                banner.centerYAnchor.constraint(equalTo: bannerWrap.centerYAnchor),
                banner.heightAnchor.constraint(equalToConstant: 30),
            ])
            stack.insertArrangedSubview(bannerWrap, at: 1)
            pulse(banner.layer, from: 1.0, to: 1.05, key: "transform.scale", duration: 0.7)
            card.layer.borderColor = best.borderColor.cgColor; card.layer.borderWidth = 3
            card.layer.shadowColor = best.badgeColor.cgColor; card.layer.shadowOpacity = 0.75; card.layer.shadowRadius = 28
            pulse(card.layer, from: 0.42, to: 0.88, key: "shadowOpacity", duration: 0.9)
        }

        let rule = UIView(); rule.backgroundColor = MeadowPreviewPalette.ink.withAlphaComponent(0.12)
        rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stack.addArrangedSubview(rule)

        if gains.isEmpty, let emptyText {
            let line = MeadowPreviewPalette.label(emptyText, size: 16.5, weight: .semibold)
            line.textAlignment = .center; line.numberOfLines = 0
            stack.addArrangedSubview(line)
        }

        for gain in gains {
            let name = MeadowPreviewPalette.label(gain.unitName, size: 15.5, weight: .heavy)
            name.textColor = MeadowPreviewPalette.primary
            stack.addArrangedSubview(name)
            let flow = MeadowChipFlow()
            if gain.coins > 0 {
                flow.add(chip(icon: UIImage(systemName: "bitcoinsign.circle.fill"), tint: MeadowPreviewPalette.gold, text: "+\(gain.coins) 金币"))
            }
            if gain.score > 0 {
                flow.add(chip(icon: UIImage(systemName: "star.circle.fill"), tint: UIColor(red: 0.10, green: 0.44, blue: 0.78, alpha: 1), text: "+\(gain.score) 积分"))
            }
            let sorted = gain.items.sorted { MeadowItemRarity.of($0.id) > MeadowItemRarity.of($1.id) }
            for item in sorted {
                let definition = try? catalog?.item(item.id)
                let itemName = definition?.name ?? item.id
                let rarity = MeadowItemRarity.of(item.id, item: definition)
                flow.add(chip(icon: MeadowItemIcon.image(item.id, item: definition), tint: nil, text: "\(itemName) ×\(item.count)", rarity: rarity))
            }
            chips += flow.chips
            stack.addArrangedSubview(flow)
        }

        button.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        button.accessibilityIdentifier = "meadowGainPopupClose"
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last ?? heading)
        stack.addArrangedSubview(button)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backdropTapped(_:))))
    }

    private func chip(icon: UIImage?, tint: UIColor?, text: String, rarity: MeadowItemRarity? = nil) -> UIView {
        let view = UIView()
        view.backgroundColor = rarity?.surfaceTint ?? UIColor.white.withAlphaComponent(0.85)
        view.layer.cornerRadius = 14; view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1.4
        view.layer.borderColor = (rarity?.borderColor ?? MeadowPreviewPalette.ink.withAlphaComponent(0.16)).cgColor

        let image = UIImageView(image: tint == nil ? icon?.withRenderingMode(.alwaysOriginal) : icon)
        image.tintColor = tint ?? MeadowPreviewPalette.gold
        image.contentMode = .scaleAspectFit; image.layer.magnificationFilter = .nearest
        image.frame = CGRect(x: 8, y: 6, width: 32, height: 32)
        view.addSubview(image)

        var x: CGFloat = 45
        if let rarity {
            let pill = UILabel()
            pill.text = rarity.title
            pill.font = MeadowPreviewPalette.font(11, .heavy)
            pill.textColor = .white
            pill.textAlignment = .center
            pill.backgroundColor = rarity.badgeColor
            pill.layer.cornerRadius = 6; pill.clipsToBounds = true
            pill.frame = CGRect(x: x, y: 12.5, width: 34, height: 19)
            view.addSubview(pill)
            x += 40
        }

        let label = UILabel()
        label.text = text
        label.font = MeadowPreviewPalette.font(15.5, rarity != nil && rarity! >= .rare ? .heavy : .bold)
        label.textColor = rarity.map { $0 >= .rare ? $0.inkColor : MeadowPreviewPalette.ink } ?? MeadowPreviewPalette.ink
        let width = ceil(label.intrinsicContentSize.width)
        label.frame = CGRect(x: x, y: 0, width: width, height: 44)
        view.addSubview(label)

        view.frame = CGRect(x: 0, y: 0, width: x + width + 12, height: 44)
        if let rarity, rarity >= .rare { decorate(view, icon: image, rarity: rarity) }
        return view
    }

    private func decorate(_ view: UIView, icon: UIImageView, rarity: MeadowItemRarity) {
        view.layer.borderColor = rarity.borderColor.cgColor
        view.layer.borderWidth = rarity == .legendary ? 2.4 : 1.8
        view.layer.shadowColor = rarity.badgeColor.cgColor; view.layer.shadowOffset = .zero; view.layer.shadowRadius = rarity == .legendary ? 12 : 8
        view.layer.shadowPath = UIBezierPath(roundedRect: view.bounds, cornerRadius: 14).cgPath
        pulse(view.layer, from: 0.20, to: rarity == .legendary ? 0.85 : 0.55, key: "shadowOpacity", duration: 0.85)

        let clip = UIView(frame: view.bounds); clip.layer.cornerRadius = 14; clip.clipsToBounds = true; clip.isUserInteractionEnabled = false
        let sweep = CAGradientLayer()
        sweep.colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        sweep.startPoint = CGPoint(x: 0, y: 0.3); sweep.endPoint = CGPoint(x: 1, y: 0.7)
        sweep.frame = CGRect(x: -60, y: 0, width: 60, height: view.bounds.height)
        clip.layer.addSublayer(sweep); view.insertSubview(clip, at: 0)
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -60; move.toValue = view.bounds.width + 60; move.duration = 0.9
        let group = CAAnimationGroup(); group.animations = [move]; group.duration = rarity == .legendary ? 1.8 : 2.6; group.repeatCount = .infinity
        group.beginTime = CACurrentMediaTime() + 0.6
        sweep.add(group, forKey: "sweep")

        if let suffix = rarity.clipSuffix, let burst = MeadowPixelFX.clips["collect" + suffix] {
            let images = MeadowPixelFX.images(burst)
            let start = burst.back && burst.front ? burst.n : 0
            let frames = (start..<min(images.count, start + burst.n)).map { UIImage(cgImage: images[$0]) }
            if !frames.isEmpty {
                let fx = UIImageView(frame: CGRect(x: icon.frame.midX - 40, y: icon.frame.midY - 52, width: 80, height: 88))
                fx.animationImages = frames; fx.animationDuration = Double(frames.count) / 20; fx.animationRepeatCount = rarity == .legendary ? 3 : 1
                fx.layer.magnificationFilter = .nearest; fx.isUserInteractionEnabled = false
                view.addSubview(fx)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fx.startAnimating() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + fx.animationDuration * Double(fx.animationRepeatCount)) { fx.removeFromSuperview() }
            }
        }
        view.clipsToBounds = false
    }

    private func pulse(_ layer: CALayer, from: Double, to: Double, key: String, duration: Double) {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from; a.toValue = to; a.duration = duration; a.autoreverses = true; a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(a, forKey: key)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(560, bounds.width - 44), inner = width - 40
        for case let flow as MeadowChipFlow in stack.arrangedSubviews { flow.arrange(width: inner) }
        let height = stack.systemLayoutSizeFitting(CGSize(width: inner, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let saved = card.transform; card.transform = .identity
        card.frame = CGRect(x: (bounds.width - width) / 2, y: max(16, (bounds.height - height - 40) / 2), width: width, height: min(bounds.height - 32, height + 40))
        card.transform = saved
        stack.frame = CGRect(x: 20, y: 20, width: inner, height: height)
    }

    private func appear() {
        layoutIfNeeded()
        alpha = 0; card.transform = CGAffineTransform(scaleX: 0.72, y: 0.72).translatedBy(x: 0, y: 34)
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        UIView.animate(withDuration: 0.52, delay: 0, usingSpringWithDamping: 0.62, initialSpringVelocity: 0.8, options: .allowUserInteraction) { self.card.transform = .identity }
        for (i, chip) in chips.enumerated() {
            chip.alpha = 0; chip.transform = CGAffineTransform(scaleX: 0.45, y: 0.45)
            UIView.animate(withDuration: 0.42, delay: 0.22 + 0.08 * Double(i), usingSpringWithDamping: 0.54, initialSpringVelocity: 0.85, options: .allowUserInteraction) { chip.alpha = 1; chip.transform = .identity }
        }
        UIAccessibility.post(notification: .screenChanged, argument: card)
    }
    @objc private func backdropTapped(_ r: UITapGestureRecognizer) { if !card.frame.contains(r.location(in: self)) { close() } }
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
            if x > 0, x + w > width { x = 0; y += 50 }
            chip.frame = CGRect(x: x, y: y, width: w, height: 44); chip.transform = saved
            x += w + 8
        }
        let total = chips.isEmpty ? 0 : y + 44
        if let height { height.constant = total } else { height = heightAnchor.constraint(equalToConstant: total); height?.isActive = true }
    }
}
