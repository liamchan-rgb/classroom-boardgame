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
        backgroundColor = UIColor(red: 0.05, green: 0.15, blue: 0.18, alpha: 0.28); layer.zPosition = 5000
        accessibilityIdentifier = "meadowGainPopup"; accessibilityViewIsModal = true
        // Over a moving battle the card needs the thickest glass to stay readable.
        MeadowPreviewPalette.stylePanel(card); card.backgroundColor = MeadowPreviewPalette.panel; card.layer.borderWidth = 1.5; card.layer.borderColor = UIColor.white.cgColor
        card.layer.shadowColor = UIColor(red: 0.05, green: 0.18, blue: 0.22, alpha: 1).cgColor; card.layer.shadowRadius = 24; card.layer.shadowOpacity = 0.3; card.layer.shadowOffset = .zero
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
        // 这次拿到的最好的东西：史诗 / 传说时卡片换成品级颜色的边框，标题下面多一条醒目的横幅
        let best = gains.flatMap { $0.items.map { MeadowItemRarity.of($0.id, item: try? catalog?.item($0.id)) } }.max() ?? .common
        if best >= .epic {
            let banner = MeadowPreviewPalette.label("✦ \(best.title)掉落 ✦", size: 22, weight: .black)
            banner.textColor = best.color; banner.textAlignment = .center
            banner.layer.shadowColor = best.color.cgColor; banner.layer.shadowRadius = 10; banner.layer.shadowOpacity = 0.9; banner.layer.shadowOffset = .zero
            stack.insertArrangedSubview(banner, at: 1)
            pulse(banner.layer, from: 1, to: 1.08, key: "transform.scale", duration: 0.7)
            card.layer.borderColor = best.color.cgColor; card.layer.borderWidth = 3
            card.layer.shadowColor = best.color.cgColor; card.layer.shadowOpacity = 0.8; card.layer.shadowRadius = 30
            pulse(card.layer, from: 0.45, to: 0.95, key: "shadowOpacity", duration: 0.9)
        }
        for gain in gains {
            let name = MeadowPreviewPalette.label(gain.unitName, size: 16, weight: .bold)
            stack.addArrangedSubview(name)
            let flow = MeadowChipFlow()
            if gain.coins > 0 { flow.add(chip(icon: UIImage(systemName: "circle.hexagongrid.circle.fill"), tint: MeadowPreviewPalette.gold, text: "+\(gain.coins)")) }
            if gain.score > 0 { flow.add(chip(icon: UIImage(systemName: "star.circle.fill"), tint: UIColor(red: 0.12, green: 0.45, blue: 0.72, alpha: 1), text: "+\(gain.score)")) }
            // 物品按品级从高到低，名字用品级颜色，前面带品级标签
            let sorted = gain.items.sorted { MeadowItemRarity.of($0.id) > MeadowItemRarity.of($1.id) }
            for item in sorted {
                let definition = try? catalog?.item(item.id)
                let itemName = definition?.name ?? item.id, rarity = MeadowItemRarity.of(item.id, item: definition)
                flow.add(chip(icon: MeadowItemIcon.image(item.id, item: definition), tint: nil, text: "\(itemName) ×\(item.count)", rarity: rarity))
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

    private func chip(icon: UIImage?, tint: UIColor?, text: String, rarity: MeadowItemRarity? = nil) -> UIView {
        let view = UIView(); view.backgroundColor = MeadowPreviewPalette.glass(.medium); view.layer.cornerRadius = 22; view.layer.cornerCurve = .continuous; view.layer.borderWidth = 1; view.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        let image = UIImageView(image: tint == nil ? icon?.withRenderingMode(.alwaysOriginal) : icon); image.tintColor = tint ?? MeadowPreviewPalette.gold
        image.contentMode = .scaleAspectFit; image.layer.magnificationFilter = .nearest
        let label = MeadowPreviewPalette.label(text, size: 16, weight: .bold); label.adjustsFontSizeToFitWidth = false
        if let rarity {
            // 「传说」小标签 + 品级颜色的名字（普通物品只加灰色的「普通」）
            let line = NSMutableAttributedString(string: rarity.title + " ", attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .heavy), .foregroundColor: rarity.color, .baselineOffset: 1])
            line.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 16, weight: rarity >= .rare ? .heavy : .bold),
                                                                      .foregroundColor: rarity >= .rare ? rarity.color : label.textColor ?? .white]))
            if rarity >= .rare { label.shadowColor = UIColor.black.withAlphaComponent(0.6); label.shadowOffset = CGSize(width: 0, height: 1) }
            label.attributedText = line
        }
        let width = ceil(label.intrinsicContentSize.width)
        image.frame = CGRect(x: 8, y: 6, width: 32, height: 32); label.frame = CGRect(x: 46, y: 0, width: width, height: 44)
        view.addSubview(image); view.addSubview(label)
        view.frame = CGRect(x: 0, y: 0, width: 46 + width + 12, height: 44)
        if let rarity, rarity >= .rare { decorate(view, icon: image, rarity: rarity) }
        return view
    }

    /// 稀有以上的物品格：品级颜色的边框和底色、一圈呼吸的光、定时扫过的一道亮光、弹出时图标上炸开一团拾取光
    private func decorate(_ view: UIView, icon: UIImageView, rarity: MeadowItemRarity) {
        let c = rarity.color
        view.layer.borderColor = c.cgColor; view.layer.borderWidth = rarity == .legendary ? 2.5 : 2
        view.backgroundColor = c.withAlphaComponent(rarity == .legendary ? 0.26 : 0.18)
        view.layer.shadowColor = c.cgColor; view.layer.shadowOffset = .zero; view.layer.shadowRadius = rarity == .legendary ? 14 : 9
        view.layer.shadowPath = UIBezierPath(roundedRect: view.bounds, cornerRadius: 22).cgPath
        pulse(view.layer, from: 0.25, to: rarity == .legendary ? 1 : 0.75, key: "shadowOpacity", duration: 0.8)
        // 扫光：一条斜的白色渐变从左扫到右
        let clip = UIView(frame: view.bounds); clip.layer.cornerRadius = 22; clip.clipsToBounds = true; clip.isUserInteractionEnabled = false
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
        // 弹出时的拾取光（像素特效片段，播一次）
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
