import UIKit
import ClassroomGameCore

/// One slice of a prize wheel: what it shows and how rare it is (the rarer, the richer its material and the bigger the
/// celebration when it comes up).
struct WheelSlice {
    var title: String
    var icon: UIImage?
    /// Small text under the icon (×2, an amount); nil for none.
    var badge: String?
    var rarity: MeadowItemRarity
    /// Coins / score: drawn in warm honey-gold parchment & gilt foil.
    var coins: Bool = false
    /// How likely it is: the slice's share of the wheel.
    var weight: Double = 1
    /// Optional 1-line stat or reward description shown on the win reveal plaque.
    var subtitle: String? = nil

    /// Each slice's start and width (radians, clockwise from the top), in proportion to the weights.
    static func angles(_ slices: [WheelSlice]) -> [(start: CGFloat, width: CGFloat)] {
        let total = slices.reduce(0) { $0 + max(0, $1.weight) }
        var at: CGFloat = 0
        return slices.map { s in
            let w = total > 0 ? CGFloat(max(0, s.weight) / total) * 2 * .pi : 2 * .pi / CGFloat(max(1, slices.count))
            defer { at += w }
            return (at, w)
        }
    }

    /// A teacher-made prize: its item's rarity, or how unlikely it is (≤5 % legendary, ≤12 % epic, ≤25 % rare).
    static func rarity(chance: Double, item: MeadowItemRarity? = nil) -> MeadowItemRarity {
        let byChance: MeadowItemRarity = chance <= 0.05 ? .legendary : chance <= 0.12 ? .epic : chance <= 0.25 ? .rare : .common
        return max(byChance, item ?? .common)
    }
}

// MARK: - Tactile Material Texture Cache

private enum WheelMaterials {
    static let walnut: UIImage? = UIImage(named: "WheelTex_WalnutWood")
    static let brushedBrass: UIImage? = UIImage(named: "WheelTex_BrushedBrass")
    static let radialBrass: UIImage? = UIImage(named: "WheelTex_RadialBrass")
    static let parchment: UIImage? = UIImage(named: "WheelTex_Parchment")
    static let royalDamask: UIImage? = UIImage(named: "WheelTex_RoyalDamask")
    static let hammeredGold: UIImage? = UIImage(named: "WheelTex_HammeredGold")

    /// Draws a material image covering `rect` while maintaining aspect ratio (aspect-fill) with optional blend & alpha.
    static func drawCover(_ image: UIImage?, in rect: CGRect, blend: CGBlendMode = .normal, alpha: CGFloat = 1) {
        guard let image, rect.width > 0.5, rect.height > 0.5 else { return }
        let side = max(rect.width, rect.height)
        let target = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        image.draw(in: target, blendMode: blend, alpha: alpha)
    }
}

// MARK: - Skeuomorphic Wooden & Brass Fantasy Prize Wheel

/// Skeuomorphic antique tabletop prize wheel with real tactile material textures:
/// carved burled-walnut bezel & brass-clasped wooden cradle stand, concentric lathe-turned brass moldings,
/// 28 vintage glass marquee bulbs seated in brass sockets, physical 3D brass sector ribs & rim pegs,
/// textured rarity surfaces (antique cotton parchment / royal damask sapphire & amethyst / hammered gold leaf),
/// stationary overhead lighting & recessed bezel shadow overlay, bolted brass-ruby clapper pointer,
/// riveted lathe-turned brass hub, and strict readability-first narrow-slice simplification.
final class MeadowPrizeWheelView: UIView, UIGestureRecognizerDelegate {
    var slices: [WheelSlice] = [] { didSet { face.slices = slices; face.setNeedsDisplay(); clearWin() } }
    private(set) var spinning = false
    /// Tapping the center brass hub spins (the same as the spin button).
    var onHubTap: (() -> Void)?
    /// How long the win shows before it fades away (the prize card goes with it).
    static let winHold = 3.2
    /// Called when the win fades (the owner hides its prize card then).
    var onWinFaded: (() -> Void)?
    private var winToken = 0

    private let glow = CALayer()
    private let bezelView = WheelBezelView()
    private let face = WheelFaceView()
    private let drumOverlay = WheelDrumOverlayView()
    private var bulbs: [CALayer] = []
    private let hubView = WheelHubView()
    private let pointerView = WheelPointerView()
    private let winWedge = CAShapeLayer()
    private let effects = CALayer()
    private var link: CADisplayLink?
    private var lastTickSlice = -1
    private var angle: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        glow.shadowOpacity = 0.48
        glow.shadowRadius = 26
        glow.shadowOffset = CGSize(width: 0, height: 10)
        glow.shadowColor = UIColor(red: 0.24, green: 0.14, blue: 0.05, alpha: 1).cgColor
        layer.addSublayer(glow)

        addSubview(bezelView)
        addSubview(face)

        winWedge.fillColor = UIColor.white.withAlphaComponent(0.0).cgColor
        winWedge.strokeColor = UIColor(red: 1.0, green: 0.95, blue: 0.70, alpha: 1).cgColor
        winWedge.opacity = 0
        face.layer.addSublayer(winWedge)

        // Stationary physical lighting & recessed inner bezel shadow above the spinning drum.
        addSubview(drumOverlay)
        addSubview(hubView)
        addSubview(pointerView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(hubTapped))
        tap.delegate = self
        addGestureRecognizer(tap)

        layer.addSublayer(effects)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var rimWidth: CGFloat {
        let approx = min(bounds.width, bounds.height) * 0.5
        return max(20, min(26, approx * 0.095))
    }
    private var radius: CGFloat {
        let rim = rimWidth
        // Reserve space for thick walnut bezel, top cast-brass pointer bracket, and carved pedestal foot.
        let maxR = min(bounds.width / 2 - rim - 6, (bounds.height - rim * 2 - 22) / 2)
        return max(44, maxR)
    }
    private var centre: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY - 3) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = radius, c = centre, rim = rimWidth
        guard r > 20 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)

        bezelView.frame = bounds
        bezelView.wheelCenter = c
        bezelView.wheelRadius = r
        bezelView.rimWidth = rim
        bezelView.setNeedsDisplay()

        face.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        face.center = c
        face.transform = CGAffineTransform(rotationAngle: angle)

        drumOverlay.frame = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        drumOverlay.hubRadius = max(28, min(46, r * 0.195))
        drumOverlay.setNeedsDisplay()

        let outerR = r + rim
        glow.frame = CGRect(x: c.x - outerR + 4, y: c.y - outerR + 4, width: 2 * (outerR - 4), height: 2 * (outerR - 4))
        glow.shadowPath = UIBezierPath(ovalIn: glow.bounds).cgPath

        // 28 vintage glass marquee bulbs seated inside the recessed brass sockets on the walnut bezel.
        let count = 28
        if bulbs.count != count {
            bulbs.forEach { $0.removeFromSuperlayer() }
            let defaultSprite = Self.glassBulbImage(tint: UIColor(red: 1.0, green: 0.86, blue: 0.42, alpha: 1))
            bulbs = (0..<count).map { _ in
                let b = CALayer()
                b.contents = defaultSprite
                b.contentsGravity = .resizeAspect
                b.shadowColor = UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1).cgColor
                b.shadowOpacity = 0.90
                b.shadowRadius = 5.5
                b.shadowOffset = .zero
                layer.insertSublayer(b, above: drumOverlay.layer)
                return b
            }
        }
        let bulbRingR = r + rim * 0.54
        let bulbSize: CGFloat = max(8.5, min(12.0, rim * 0.46))
        for (i, b) in bulbs.enumerated() {
            let a = CGFloat(i) / CGFloat(count) * 2 * .pi - .pi / 2
            b.bounds = CGRect(x: 0, y: 0, width: bulbSize, height: bulbSize)
            b.position = CGPoint(x: c.x + cos(a) * bulbRingR, y: c.y + sin(a) * bulbRingR)
            b.opacity = i % 2 == 0 ? 1.0 : 0.44
        }

        let hr = max(28, min(46, r * 0.195))
        hubView.bounds = CGRect(x: 0, y: 0, width: 2 * hr, height: 2 * hr)
        hubView.center = c
        hubView.setNeedsDisplay()

        // Sculpted cast-brass & faceted ruby clapper pointer pivoted on the top bezel bracket.
        let pw: CGFloat = max(32, min(46, r * 0.18))
        let ph: CGFloat = pw * 1.54
        pointerView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.22)
        pointerView.bounds = CGRect(x: 0, y: 0, width: pw, height: ph)
        pointerView.center = CGPoint(x: c.x, y: c.y - r - rim * 0.58)
        pointerView.setNeedsDisplay()

        bringSubviewToFront(drumOverlay)
        bringSubviewToFront(hubView)
        bringSubviewToFront(pointerView)
        effects.frame = bounds
        layer.addSublayer(effects)
        CATransaction.commit()
    }

    // MARK: Spin

    /// Only taps on the brass hub trigger spin.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let p = touch.location(in: self), c = centre, hr = max(28, min(46, radius * 0.195)) + 8
        return hypot(p.x - c.x, p.y - c.y) <= hr && onHubTap != nil && !spinning
    }
    @objc private func hubTapped() {
        UIView.animate(withDuration: 0.10, animations: {
            self.hubView.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
        }) { _ in
            UIView.animate(withDuration: 0.24, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8, options: []) {
                self.hubView.transform = .identity
            }
        }
        onHubTap?()
    }

    /// Turns the wheel smoothly and stops with `slot` under the ruby-brass pointer; `done` after it settles.
    func spin(to slot: Int, duration: Double = 4.4, done: @escaping () -> Void) {
        guard !spinning, !slices.isEmpty else { return }
        spinning = true; clearWin()
        let a = WheelSlice.angles(slices)[slot]
        let jitter = CGFloat.random(in: -0.32...0.32) * a.width
        let current = angle.truncatingRemainder(dividingBy: 2 * .pi)
        var target = -(a.start + a.width / 2) + jitter
        while target < current { target += 2 * .pi }
        target += 2 * .pi * 7
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = current; anim.toValue = target; anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.14, 0.86, 0.12, 1)
        angle = target
        face.transform = CGAffineTransform(rotationAngle: target)
        face.layer.add(anim, forKey: "spin")
        chaseLights()
        lastTickSlice = -1
        let l = CADisplayLink(target: WheelTick(self), selector: #selector(WheelTick.tick)); l.add(to: .main, forMode: .common); link = l
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            guard let self else { return }
            self.link?.invalidate(); self.link = nil
            self.spinning = false
            self.blinkLights()
            done()
        }
    }

    /// While spinning: the ruby clapper physically flicks each time a brass sector peg passes under it.
    fileprivate func tick() {
        guard let rot = face.layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat, !slices.isEmpty else { return }
        var a = (-rot).truncatingRemainder(dividingBy: 2 * .pi); if a < 0 { a += 2 * .pi }
        let slice = WheelSlice.angles(slices).lastIndex { $0.start <= a } ?? 0
        if slice != lastTickSlice {
            lastTickSlice = slice
            let kick = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            kick.values = [0, -0.36, 0.08, 0]; kick.keyTimes = [0, 0.24, 0.72, 1]; kick.duration = 0.15
            pointerView.layer.add(kick, forKey: "tick")
        }
    }

    private func chaseLights() {
        let warm = Self.glassBulbImage(tint: UIColor(red: 1.0, green: 0.86, blue: 0.42, alpha: 1))
        for (i, b) in bulbs.enumerated() {
            b.contents = warm
            b.shadowColor = UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1).cgColor
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.24; a.duration = 0.30; a.autoreverses = true; a.repeatCount = .infinity
            a.beginTime = CACurrentMediaTime() + Double(i % 7) * 0.042
            b.add(a, forKey: "chase")
        }
    }

    private func blinkLights(tint: UIColor? = nil) {
        let sprite = tint.map { Self.glassBulbImage(tint: $0) }
        for b in bulbs {
            b.removeAnimation(forKey: "chase")
            if let sprite, let tint {
                b.contents = sprite
                b.shadowColor = tint.cgColor
            }
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.22; a.duration = 0.18; a.autoreverses = true; a.repeatCount = 4
            b.add(a, forKey: "blink")
        }
    }

    // MARK: Win

    private func clearWin() {
        winToken += 1
        winWedge.removeAllAnimations(); winWedge.opacity = 0; effects.removeAllAnimations(); effects.opacity = 1
        effects.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    private func fadeWinLater() {
        let token = winToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.winHold) { [weak self] in
            guard let self, self.winToken == token, !self.spinning else { return }
            let fade = CABasicAnimation(keyPath: "opacity"); fade.toValue = 0; fade.duration = 0.3
            fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
            self.winWedge.add(fade, forKey: "fade"); self.effects.add(fade, forKey: "fade")
            self.onWinFaded?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                guard let self, self.winToken == token else { return }
                self.clearWin()
                self.glow.shadowColor = UIColor(red: 0.24, green: 0.14, blue: 0.05, alpha: 1).cgColor
                let warm = Self.glassBulbImage(tint: UIColor(red: 1.0, green: 0.86, blue: 0.42, alpha: 1))
                for b in self.bulbs {
                    b.contents = warm
                    b.shadowColor = UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1).cgColor
                }
            }
        }
    }

    /// Lights the winning slice and plays the celebration of its rarity (brighter for rarer prizes).
    func celebrate(_ slot: Int) {
        guard slices.indices.contains(slot) else { return }
        let rarity = slices[slot].rarity, r = radius, c = centre
        let span = WheelSlice.angles(slices)[slot]
        let fc = CGPoint(x: r, y: r), start = -CGFloat.pi / 2 + span.start
        let wedge = UIBezierPath(); wedge.move(to: fc); wedge.addArc(withCenter: fc, radius: r - 1, startAngle: start, endAngle: start + span.width, clockwise: true); wedge.close()
        winWedge.path = wedge.cgPath; winWedge.lineWidth = 4
        let accent = rarity == .common ? UIColor(red: 0.96, green: 0.76, blue: 0.26, alpha: 1) : rarity.color
        winWedge.fillColor = accent.withAlphaComponent(0.32).cgColor
        winWedge.strokeColor = UIColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 1).cgColor
        winWedge.shadowColor = accent.cgColor; winWedge.shadowOpacity = 1; winWedge.shadowRadius = 12; winWedge.shadowOffset = .zero
        let pulse = CABasicAnimation(keyPath: "opacity"); pulse.fromValue = 1; pulse.toValue = 0.45; pulse.duration = 0.48; pulse.autoreverses = true; pulse.repeatCount = .infinity
        winWedge.opacity = 1; winWedge.add(pulse, forKey: "pulse")
        blinkLights(tint: accent)
        fadeWinLater()
        glow.shadowColor = accent.cgColor
        let top = CGPoint(x: c.x, y: c.y - r * 0.58)
        switch rarity {
        case .common:
            burst(at: top, color: UIColor(red: 1.0, green: 0.92, blue: 0.62, alpha: 1), count: 32, speed: 150, image: Self.dot)
        case .rare:
            shockwave(at: c, radius: r * 1.25, color: rarity.color)
            burst(at: top, color: rarity.color, count: 72, speed: 225, image: Self.star)
        case .epic:
            beam(at: c, height: bounds.height, color: rarity.color)
            shockwave(at: c, radius: r * 1.35, color: rarity.color)
            burst(at: c, color: rarity.color, count: 120, speed: 300, image: Self.star)
            rising(at: c, width: r * 1.6, color: rarity.color)
        case .legendary:
            flash()
            rays(at: c, radius: r * 1.6, color: rarity.color)
            beam(at: c, height: bounds.height, color: rarity.color)
            shockwave(at: c, radius: r * 1.5, color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
            burst(at: c, color: UIColor(red: 1, green: 0.82, blue: 0.3, alpha: 1), count: 165, speed: 360, image: Self.star)
            confetti(width: bounds.width)
        }
    }

    private func shockwave(at c: CGPoint, radius: CGFloat, color: UIColor) {
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(arcCenter: .zero, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
        ring.position = c; ring.fillColor = UIColor.clear.cgColor; ring.strokeColor = color.cgColor; ring.lineWidth = 8
        ring.shadowColor = color.cgColor; ring.shadowOpacity = 1; ring.shadowRadius = 10; ring.shadowOffset = .zero
        effects.addSublayer(ring)
        let g = CAAnimationGroup()
        let s = CABasicAnimation(keyPath: "transform.scale"); s.fromValue = 0.3; s.toValue = 1.15
        let o = CABasicAnimation(keyPath: "opacity"); o.fromValue = 1; o.toValue = 0
        let w = CABasicAnimation(keyPath: "lineWidth"); w.fromValue = 14; w.toValue = 1
        g.animations = [s, o, w]; g.duration = 0.9; g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        g.fillMode = .forwards; g.isRemovedOnCompletion = false
        ring.add(g, forKey: "wave")
    }
    private func beam(at c: CGPoint, height: CGFloat, color: UIColor) {
        let b = CAGradientLayer()
        b.colors = [color.withAlphaComponent(0).cgColor, color.withAlphaComponent(0.75).cgColor, UIColor.white.withAlphaComponent(0.9).cgColor, color.withAlphaComponent(0.75).cgColor, color.withAlphaComponent(0).cgColor]
        b.startPoint = CGPoint(x: 0, y: 0.5); b.endPoint = CGPoint(x: 1, y: 0.5)
        b.bounds = CGRect(x: 0, y: 0, width: 70, height: height * 1.2); b.position = CGPoint(x: c.x, y: c.y - height * 0.1)
        b.opacity = 0
        effects.insertSublayer(b, at: 0)
        let o = CAKeyframeAnimation(keyPath: "opacity"); o.values = [0, 0.95, 0.7, 0]; o.keyTimes = [0, 0.15, 0.6, 1]; o.duration = 1.8
        let s = CABasicAnimation(keyPath: "transform.scale.x"); s.fromValue = 0.2; s.toValue = 1.6; s.duration = 1.8
        let g = CAAnimationGroup(); g.animations = [o, s]; g.duration = 1.8; g.fillMode = .forwards; g.isRemovedOnCompletion = false
        b.add(g, forKey: "beam")
    }
    private func rays(at c: CGPoint, radius: CGFloat, color: UIColor) {
        let rays = CAShapeLayer(), path = UIBezierPath(), n = 16
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi, w: CGFloat = .pi / CGFloat(n) * 0.55
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: cos(a - w) * radius, y: sin(a - w) * radius))
            path.addLine(to: CGPoint(x: cos(a + w) * radius, y: sin(a + w) * radius)); path.close()
        }
        rays.path = path.cgPath; rays.position = c
        rays.fillColor = color.withAlphaComponent(0.4).cgColor
        rays.shadowColor = color.cgColor; rays.shadowOpacity = 0.8; rays.shadowRadius = 14; rays.shadowOffset = .zero
        effects.insertSublayer(rays, at: 0)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z"); spin.fromValue = 0; spin.toValue = 2 * CGFloat.pi; spin.duration = 6; spin.repeatCount = .infinity
        let grow = CABasicAnimation(keyPath: "transform.scale"); grow.fromValue = 0.2; grow.toValue = 1; grow.duration = 0.7; grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let breathe = CABasicAnimation(keyPath: "opacity"); breathe.fromValue = 1; breathe.toValue = 0.55; breathe.duration = 0.9; breathe.autoreverses = true; breathe.repeatCount = .infinity
        rays.add(spin, forKey: "spin"); rays.add(grow, forKey: "grow"); rays.add(breathe, forKey: "breathe")
    }
    private func flash() {
        let f = CALayer(); f.frame = bounds.insetBy(dx: -bounds.width, dy: -bounds.height); f.backgroundColor = UIColor.white.cgColor; f.opacity = 0
        effects.addSublayer(f)
        let o = CAKeyframeAnimation(keyPath: "opacity"); o.values = [0, 0.85, 0]; o.keyTimes = [0, 0.12, 1]; o.duration = 0.7
        o.fillMode = .forwards; o.isRemovedOnCompletion = false
        f.add(o, forKey: "flash")
    }
    private func burst(at p: CGPoint, color: UIColor, count: Float, speed: CGFloat, image: CGImage?) {
        let e = CAEmitterLayer(); e.emitterPosition = p; e.emitterShape = .point; e.renderMode = .additive
        let cell = CAEmitterCell()
        cell.contents = image; cell.birthRate = count * 6; cell.lifetime = 1.4; cell.lifetimeRange = 0.4
        cell.velocity = speed; cell.velocityRange = speed * 0.5; cell.emissionRange = 2 * .pi
        cell.yAcceleration = 260; cell.scale = 0.5; cell.scaleRange = 0.3; cell.scaleSpeed = -0.25
        cell.spin = 3; cell.spinRange = 6; cell.alphaSpeed = -0.7
        cell.color = color.cgColor
        e.emitterCells = [cell]
        effects.addSublayer(e)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { e.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { e.removeFromSuperlayer() }
    }
    private func rising(at c: CGPoint, width: CGFloat, color: UIColor) {
        let e = CAEmitterLayer(); e.emitterPosition = CGPoint(x: c.x, y: c.y + 30); e.emitterShape = .line; e.emitterSize = CGSize(width: width, height: 1)
        e.renderMode = .additive
        let cell = CAEmitterCell()
        cell.contents = Self.dot; cell.birthRate = 60; cell.lifetime = 2.2; cell.velocity = 90; cell.velocityRange = 40
        cell.emissionLongitude = -.pi / 2; cell.emissionRange = 0.3; cell.scale = 0.35; cell.scaleRange = 0.2; cell.alphaSpeed = -0.4
        cell.color = color.cgColor
        e.emitterCells = [cell]
        effects.addSublayer(e)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { e.birthRate = 0 }
    }
    private func confetti(width: CGFloat) {
        let e = CAEmitterLayer(); e.emitterPosition = CGPoint(x: bounds.midX, y: -20); e.emitterShape = .line; e.emitterSize = CGSize(width: width, height: 1)
        let colors: [UIColor] = [UIColor(red: 1, green: 0.78, blue: 0.2, alpha: 1), UIColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1),
                                 UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1), UIColor(red: 0.5, green: 0.85, blue: 0.45, alpha: 1), UIColor(red: 0.8, green: 0.55, blue: 1, alpha: 1)]
        e.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = Self.ribbon; cell.birthRate = 14; cell.lifetime = 5; cell.velocity = 160; cell.velocityRange = 60
            cell.emissionLongitude = .pi / 2; cell.emissionRange = 0.5; cell.yAcceleration = 90; cell.spin = 4; cell.spinRange = 8
            cell.scale = 0.6; cell.scaleRange = 0.3; cell.color = color.cgColor
            return cell
        }
        effects.addSublayer(e)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { e.birthRate = 0 }
    }

    /// Pre-renders a realistic 3D vintage glass marquee bulb sprite (amber filament core + glossy glass dome + brass edge).
    private static func glassBulbImage(tint: UIColor) -> CGImage? {
        let side: CGFloat = 32
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { rendererCtx in
            let ctx = rendererCtx.cgContext
            let c = CGPoint(x: side / 2, y: side / 2)
            let r = side * 0.42
            // Outer warm glass rim
            let sphere = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.saveGState()
            sphere.addClip()
            let core = tint.mixed(with: .white, 0.82)
            let mid = tint.mixed(with: .white, 0.28)
            let edge = tint.mixed(with: UIColor(red: 0.42, green: 0.22, blue: 0.04, alpha: 1), 0.48)
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                core.cgColor, mid.cgColor, edge.cgColor
            ] as CFArray, locations: [0.0, 0.55, 1.0])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - r * 0.16, y: c.y - r * 0.18), startRadius: 0.5, endCenter: c, endRadius: r, options: [])

            // Crisp specular glass dome highlight at top-left
            UIColor.white.withAlphaComponent(0.92).setFill()
            UIBezierPath(ovalIn: CGRect(x: c.x - r * 0.54, y: c.y - r * 0.62, width: r * 0.52, height: r * 0.38)).fill()
            ctx.restoreGState()

            // Fine dark bronze bezel edge around glass sphere
            UIColor(red: 0.32, green: 0.20, blue: 0.06, alpha: 0.78).setStroke()
            sphere.lineWidth = 1.4
            sphere.stroke()
        }
        return img.cgImage
    }

    private static let dot: CGImage? = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in
        let g = CGGradient(colorsSpace: nil, colors: [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        UIGraphicsGetCurrentContext()?.drawRadialGradient(g, startCenter: CGPoint(x: 8, y: 8), startRadius: 0, endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
    }.cgImage
    private static let star: CGImage? = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in
        let p = UIBezierPath()
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4 - .pi / 2, r: CGFloat = i % 2 == 0 ? 12 : 3.5
            let pt = CGPoint(x: 12 + cos(a) * r, y: 12 + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.close(); UIColor.white.setFill(); p.fill()
    }.cgImage
    private static let ribbon: CGImage? = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 18)).image { _ in
        UIColor.white.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 10, height: 18), cornerRadius: 2).fill()
    }.cgImage
}

private final class WheelTick: NSObject {
    weak var wheel: MeadowPrizeWheelView?
    init(_ wheel: MeadowPrizeWheelView) { self.wheel = wheel }
    @objc func tick() { wheel?.tick() }
}

// MARK: - Carved Burled-Walnut Bezel + Brass-Clasped Tabletop Stand

private final class WheelBezelView: UIView {
    var wheelCenter: CGPoint = .zero
    var wheelRadius: CGFloat = 0
    var rimWidth: CGFloat = 24
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; isUserInteractionEnabled = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), wheelRadius > 20 else { return }
        let c = wheelCenter, r = wheelRadius, rim = rimWidth
        let outerR = r + rim

        // 1. Carved Burled-Walnut & Machined-Brass Tabletop Cradle Stand.
        let baseY = min(bounds.height - 4, c.y + outerR + 12)
        let standTopY = c.y + r * 0.62
        let topHalfW = r * 0.34
        let botHalfW = r * 0.56

        // Dual-layer realistic table contact & ambient shadow under pedestal foot.
        ctx.saveGState()
        let wideShadow = CGRect(x: c.x - botHalfW * 1.18, y: baseY - 7, width: botHalfW * 2.36, height: 12)
        UIColor.black.withAlphaComponent(0.18).setFill()
        UIBezierPath(ovalIn: wideShadow).fill()
        let tightShadow = CGRect(x: c.x - botHalfW * 1.02, y: baseY - 4, width: botHalfW * 2.04, height: 6)
        UIColor.black.withAlphaComponent(0.32).setFill()
        UIBezierPath(ovalIn: tightShadow).fill()
        ctx.restoreGState()

        // Flared curved-shoulder wooden pedestal body filled with real walnut grain.
        let standPath = UIBezierPath()
        standPath.move(to: CGPoint(x: c.x - topHalfW, y: standTopY))
        standPath.addLine(to: CGPoint(x: c.x + topHalfW, y: standTopY))
        standPath.addCurve(
            to: CGPoint(x: c.x + botHalfW, y: baseY - 11),
            controlPoint1: CGPoint(x: c.x + topHalfW * 1.10, y: baseY - 28),
            controlPoint2: CGPoint(x: c.x + botHalfW * 0.88, y: baseY - 14)
        )
        standPath.addLine(to: CGPoint(x: c.x - botHalfW, y: baseY - 11))
        standPath.addCurve(
            to: CGPoint(x: c.x - topHalfW, y: standTopY),
            controlPoint1: CGPoint(x: c.x - botHalfW * 0.88, y: baseY - 14),
            controlPoint2: CGPoint(x: c.x - topHalfW * 1.10, y: baseY - 28)
        )
        standPath.close()

        let standRect = standPath.bounds
        ctx.saveGState()
        standPath.addClip()
        UIColor(red: 0.26, green: 0.14, blue: 0.07, alpha: 1).setFill()
        ctx.fill(standRect)
        WheelMaterials.drawCover(WheelMaterials.walnut, in: standRect, blend: .normal, alpha: 0.94)
        // Cylindrical wood bevel shading + cast shadow from wheel drum above.
        let standShade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 0.14, green: 0.06, blue: 0.02, alpha: 0.55).cgColor,
            UIColor(red: 1.00, green: 0.82, blue: 0.55, alpha: 0.14).cgColor,
            UIColor(red: 0.10, green: 0.04, blue: 0.01, alpha: 0.52).cgColor,
        ] as CFArray, locations: [0, 0.36, 1])!
        ctx.drawLinearGradient(standShade, start: CGPoint(x: standRect.minX, y: standRect.midY), end: CGPoint(x: standRect.maxX, y: standRect.midY), options: [])
        let overhangShadow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor.black.withAlphaComponent(0.58).cgColor,
            UIColor.clear.cgColor,
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(overhangShadow, start: CGPoint(x: c.x, y: c.y + outerR - 8), end: CGPoint(x: c.x, y: baseY - 10), options: [])
        ctx.restoreGState()
        UIColor(red: 0.78, green: 0.58, blue: 0.24, alpha: 0.82).setStroke()
        standPath.lineWidth = 1.6
        standPath.stroke()

        // Stepped carved-wood + brushed-brass tabletop plinth bar.
        let plinthRect = CGRect(x: c.x - botHalfW - 8, y: baseY - 12, width: (botHalfW + 8) * 2, height: 10)
        let plinthPath = UIBezierPath(roundedRect: plinthRect, cornerRadius: 4)
        ctx.saveGState()
        plinthPath.addClip()
        UIColor(red: 0.65, green: 0.48, blue: 0.18, alpha: 1).setFill()
        ctx.fill(plinthRect)
        WheelMaterials.drawCover(WheelMaterials.brushedBrass, in: plinthRect, blend: .normal, alpha: 0.92)
        let plinthLight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor.white.withAlphaComponent(0.45).cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.42).cgColor,
        ] as CFArray, locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(plinthLight, start: CGPoint(x: plinthRect.midX, y: plinthRect.minY), end: CGPoint(x: plinthRect.midX, y: plinthRect.maxY), options: [])
        ctx.restoreGState()
        UIColor(red: 0.30, green: 0.18, blue: 0.05, alpha: 0.85).setStroke()
        plinthPath.lineWidth = 1.2
        plinthPath.stroke()

        // Small riveted brass corner clasps on left & right plinth ends.
        for side: CGFloat in [-1, 1] {
            let rx = c.x + side * (botHalfW - 6)
            let ry = baseY - 7
            UIColor(red: 0.34, green: 0.20, blue: 0.05, alpha: 0.9).setFill()
            UIBezierPath(ovalIn: CGRect(x: rx - 2.3, y: ry - 2.3, width: 4.6, height: 4.6)).fill()
            UIColor(red: 1.0, green: 0.94, blue: 0.72, alpha: 0.9).setFill()
            UIBezierPath(ovalIn: CGRect(x: rx - 1.4, y: ry - 1.6, width: 2.2, height: 2.2)).fill()
        }

        // 2. Thick Multi-Stepped Carved Burled-Walnut Outer Bezel Ring.
        let bezelBounds = CGRect(x: c.x - outerR, y: c.y - outerR, width: outerR * 2, height: outerR * 2)

        // 2a. Outer Lathe-Turned Brass Outer Lip (r + rim - 4 ... outerR).
        let outerCircle = UIBezierPath(ovalIn: bezelBounds)
        ctx.saveGState()
        outerCircle.addClip()
        UIColor(red: 0.72, green: 0.54, blue: 0.20, alpha: 1).setFill()
        ctx.fill(bezelBounds)
        WheelMaterials.drawCover(WheelMaterials.radialBrass, in: bezelBounds, blend: .normal, alpha: 0.96)
        // Subtle 3D rim bevel lighting from top-left.
        let outerRimLight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 0.36).cgColor,
            UIColor.clear.cgColor,
            UIColor(red: 0.22, green: 0.12, blue: 0.02, alpha: 0.42).cgColor,
        ] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(outerRimLight, start: CGPoint(x: bezelBounds.minX, y: bezelBounds.minY), end: CGPoint(x: bezelBounds.maxX, y: bezelBounds.maxY), options: [])
        ctx.restoreGState()
        UIColor(red: 0.26, green: 0.15, blue: 0.04, alpha: 0.90).setStroke()
        outerCircle.lineWidth = 1.4
        outerCircle.stroke()

        // 2b. Carved Burled Walnut Wood Band (r + 4.2 ... outerR - 3.6).
        let woodOuterR = outerR - 3.6
        let woodInnerR = r + 4.2
        let woodRing = UIBezierPath(ovalIn: CGRect(x: c.x - woodOuterR, y: c.y - woodOuterR, width: woodOuterR * 2, height: woodOuterR * 2))
        woodRing.append(UIBezierPath(ovalIn: CGRect(x: c.x - woodInnerR, y: c.y - woodInnerR, width: woodInnerR * 2, height: woodInnerR * 2)).reversing())
        ctx.saveGState()
        woodRing.addClip()
        UIColor(red: 0.28, green: 0.15, blue: 0.07, alpha: 1).setFill()
        ctx.fill(bezelBounds)
        WheelMaterials.drawCover(WheelMaterials.walnut, in: bezelBounds, blend: .normal, alpha: 0.98)

        // Toroidal carved wood profile: light shoulders + deep concave recessed bulb channel!
        let bulbRingR = r + rim * 0.54
        let track = UIBezierPath(arcCenter: c, radius: bulbRingR, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        track.lineWidth = rim * 0.44
        UIColor(red: 0.10, green: 0.04, blue: 0.01, alpha: 0.56).setStroke()
        track.stroke()

        // Directional studio varnish sheen across the carved walnut rim.
        let woodVarnish = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 0.20).cgColor,
            UIColor.clear.cgColor,
            UIColor(red: 0.08, green: 0.03, blue: 0.01, alpha: 0.34).cgColor,
        ] as CFArray, locations: [0, 0.48, 1])!
        ctx.drawLinearGradient(woodVarnish, start: CGPoint(x: c.x - woodOuterR, y: c.y - woodOuterR), end: CGPoint(x: c.x + woodOuterR, y: c.y + woodOuterR), options: [])
        ctx.restoreGState()

        // Crisp beveled wood-to-brass groove hairlines.
        let outerGroove = UIBezierPath(arcCenter: c, radius: woodOuterR, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        outerGroove.lineWidth = 1.4
        UIColor(red: 0.16, green: 0.08, blue: 0.02, alpha: 0.80).setStroke()
        outerGroove.stroke()

        // 2c. 28 Machined Brass Socket Cups recessed inside the walnut channel.
        let socketR = max(5.2, min(7.2, rim * 0.28))
        for i in 0..<28 {
            let a = CGFloat(i) / 28.0 * 2 * .pi - .pi / 2
            let pt = CGPoint(x: c.x + cos(a) * bulbRingR, y: c.y + sin(a) * bulbRingR)
            // Countersunk dark recess
            UIColor(red: 0.09, green: 0.04, blue: 0.01, alpha: 0.88).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - socketR - 1, y: pt.y - socketR - 1, width: (socketR + 1) * 2, height: (socketR + 1) * 2)).fill()
            // Antique brass socket collar
            let collar = UIBezierPath(ovalIn: CGRect(x: pt.x - socketR, y: pt.y - socketR, width: socketR * 2, height: socketR * 2))
            UIColor(red: 0.72, green: 0.54, blue: 0.20, alpha: 0.95).setStroke()
            collar.lineWidth = 1.5
            collar.stroke()
        }

        // 2d. Inner Lathe-Turned Brass Bezel Ring framing the recessed spinning wheel face.
        let innerBrassOuter = r + 4.4
        let innerBrassRing = UIBezierPath(ovalIn: CGRect(x: c.x - innerBrassOuter, y: c.y - innerBrassOuter, width: innerBrassOuter * 2, height: innerBrassOuter * 2))
        innerBrassRing.append(UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).reversing())
        ctx.saveGState()
        innerBrassRing.addClip()
        WheelMaterials.drawCover(WheelMaterials.radialBrass, in: bezelBounds, blend: .normal, alpha: 0.96)
        ctx.restoreGState()

        let innerGoldHi = UIBezierPath(arcCenter: c, radius: r + 2.8, startAngle: -.pi * 0.85, endAngle: -.pi * 0.15, clockwise: true)
        innerGoldHi.lineWidth = 1.2
        UIColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 0.70).setStroke()
        innerGoldHi.stroke()

        let innerLip = UIBezierPath(arcCenter: c, radius: r + 0.5, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        innerLip.lineWidth = 1.8
        UIColor(red: 0.18, green: 0.10, blue: 0.03, alpha: 0.88).setStroke()
        innerLip.stroke()

        // 3. Top Cast-Brass Pointer Saddle Bracket bolted to 12 o'clock bezel!
        let bw: CGFloat = max(46, min(62, rim * 2.4))
        let bh: CGFloat = rim * 0.86
        let bracketRect = CGRect(x: c.x - bw / 2, y: c.y - outerR - 2, width: bw, height: bh)
        let bracket = UIBezierPath(roundedRect: bracketRect, cornerRadius: bh * 0.42)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.45).cgColor)
        UIColor(red: 0.62, green: 0.44, blue: 0.14, alpha: 1).setFill()
        bracket.fill()
        ctx.restoreGState()

        ctx.saveGState()
        bracket.addClip()
        WheelMaterials.drawCover(WheelMaterials.brushedBrass, in: bracketRect, blend: .normal, alpha: 0.96)
        let bLight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor.white.withAlphaComponent(0.36).cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.32).cgColor,
        ] as CFArray, locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(bLight, start: CGPoint(x: bracketRect.midX, y: bracketRect.minY), end: CGPoint(x: bracketRect.midX, y: bracketRect.maxY), options: [])
        ctx.restoreGState()
        UIColor(red: 0.28, green: 0.16, blue: 0.04, alpha: 0.92).setStroke()
        bracket.lineWidth = 1.4
        bracket.stroke()

        // Two small slotted brass mounting screws flanking the pointer pivot.
        for side: CGFloat in [-1, 1] {
            let sx = c.x + side * (bw * 0.34), sy = bracketRect.midY
            let sr: CGFloat = 3.0
            UIColor(red: 0.30, green: 0.18, blue: 0.04, alpha: 0.95).setFill()
            UIBezierPath(ovalIn: CGRect(x: sx - sr, y: sy - sr, width: sr * 2, height: sr * 2)).fill()
            UIColor(red: 0.98, green: 0.88, blue: 0.58, alpha: 0.95).setFill()
            UIBezierPath(ovalIn: CGRect(x: sx - sr * 0.72, y: sy - sr * 0.72, width: sr * 1.44, height: sr * 1.44)).fill()
            let slot = UIBezierPath()
            slot.move(to: CGPoint(x: sx - 1.6, y: sy - 0.8))
            slot.addLine(to: CGPoint(x: sx + 1.6, y: sy + 0.8))
            UIColor(red: 0.28, green: 0.16, blue: 0.04, alpha: 0.85).setStroke()
            slot.lineWidth = 0.9
            slot.stroke()
        }
    }
}

// MARK: - Stationary Overhead Lighting & Recessed Drum Shadow Overlay

/// Sits non-rotating above `WheelFaceView` so the bezel's cast inner shadow, hub drop shadow,
/// and gentle overhead studio sheen remain physically anchored to the light source while the drum spins!
private final class WheelDrumOverlayView: UIView {
    var hubRadius: CGFloat = 36
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; isUserInteractionEnabled = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 20 else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) / 2
        let circle = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

        ctx.saveGState()
        circle.addClip()

        // 1. Recessed bezel ambient occlusion around entire drum perimeter.
        let rimAO = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor.clear.cgColor,
            UIColor(red: 0.10, green: 0.05, blue: 0.01, alpha: 0.16).cgColor,
            UIColor(red: 0.08, green: 0.03, blue: 0.01, alpha: 0.44).cgColor,
        ] as CFArray, locations: [0.85, 0.95, 1.0])!
        ctx.drawRadialGradient(rimAO, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])

        // 2. Directional inner cast shadow from top-left thick walnut bezel onto the recessed drum.
        // Cutout hole matches exact radius `r` so only the soft shadow blur (never the caster edge) enters the drum!
        ctx.saveGState()
        let shadowCutout = UIBezierPath(rect: bounds.insetBy(dx: -28, dy: -28))
        shadowCutout.append(UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).reversing())
        ctx.setShadow(offset: CGSize(width: 4, height: 6), blur: 12, color: UIColor.black.withAlphaComponent(0.42).cgColor)
        UIColor.black.setFill()
        shadowCutout.fill()
        ctx.restoreGState()

        // 3. Soft directional top-left studio lacquer sheen (subtle so readability stays 100%).
        let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 1.0, green: 0.98, blue: 0.92, alpha: 0.10).cgColor,
            UIColor.clear.cgColor,
            UIColor(red: 0.14, green: 0.08, blue: 0.02, alpha: 0.08).cgColor,
        ] as CFArray, locations: [0.0, 0.46, 1.0])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: c.x - r, y: c.y - r), end: CGPoint(x: c.x + r, y: c.y + r), options: [])

        // 4. Soft cast shadow from the center brass hub onto the rotating drum.
        let hubShadow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 0.10, green: 0.05, blue: 0.01, alpha: 0.42).cgColor,
            UIColor.clear.cgColor,
        ] as CFArray, locations: [0.55, 1.0])!
        ctx.drawRadialGradient(hubShadow, startCenter: CGPoint(x: c.x + 2, y: c.y + 4), startRadius: hubRadius * 0.6, endCenter: CGPoint(x: c.x + 2, y: c.y + 4), endRadius: hubRadius * 1.48, options: [])

        ctx.restoreGState()
    }
}

// MARK: - Lathe-Turned Riveted Brass Center Hub

private final class WheelHubView: UIView {
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; isUserInteractionEnabled = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 16 else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) / 2 - 2
        let outerRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)

        // Drop shadow under hub flange.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 8, color: UIColor.black.withAlphaComponent(0.46).cgColor)
        UIColor(red: 0.46, green: 0.30, blue: 0.08, alpha: 1).setFill()
        UIBezierPath(ovalIn: outerRect).fill()
        ctx.restoreGState()

        // Outer concentric lathe-turned brushed brass flange.
        let outerPath = UIBezierPath(ovalIn: outerRect)
        ctx.saveGState()
        outerPath.addClip()
        UIColor(red: 0.78, green: 0.58, blue: 0.22, alpha: 1).setFill()
        ctx.fill(outerRect)
        WheelMaterials.drawCover(WheelMaterials.radialBrass, in: outerRect, blend: .normal, alpha: 0.96)
        let bevel = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 1.0, green: 0.97, blue: 0.80, alpha: 0.34).cgColor,
            UIColor.clear.cgColor,
            UIColor(red: 0.22, green: 0.12, blue: 0.02, alpha: 0.36).cgColor,
        ] as CFArray, locations: [0, 0.48, 1])!
        ctx.drawLinearGradient(bevel, start: CGPoint(x: outerRect.minX, y: outerRect.minY), end: CGPoint(x: outerRect.maxX, y: outerRect.maxY), options: [])
        ctx.restoreGState()

        UIColor(red: 0.30, green: 0.17, blue: 0.04, alpha: 0.92).setStroke()
        outerPath.lineWidth = 1.6
        outerPath.stroke()

        // Subtle lathe-turned concentric groove on flange.
        let groove = UIBezierPath(arcCenter: c, radius: r * 0.92, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        groove.lineWidth = 0.9
        UIColor(red: 0.32, green: 0.18, blue: 0.04, alpha: 0.45).setStroke()
        groove.stroke()

        // 8 machined brass rivets recessed in chamfer dimples along the flange.
        let rivetRing = r * 0.82
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            let pt = CGPoint(x: c.x + cos(a) * rivetRing, y: c.y + sin(a) * rivetRing)
            let rr: CGFloat = max(1.8, r * 0.068)
            UIColor(red: 0.26, green: 0.15, blue: 0.03, alpha: 0.92).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - rr - 0.5, y: pt.y - rr - 0.5, width: (rr + 0.5) * 2, height: (rr + 0.5) * 2)).fill()
            UIColor(red: 0.86, green: 0.68, blue: 0.30, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - rr * 0.82, y: pt.y - rr * 0.82, width: rr * 1.64, height: rr * 1.64)).fill()
            UIColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 0.96).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - rr * 0.58, y: pt.y - rr * 0.62, width: rr * 0.75, height: rr * 0.75)).fill()
        }

        // Recessed inner gold collar framing the domed enamel push-button.
        let collarR = r * 0.70
        let collar = UIBezierPath(ovalIn: CGRect(x: c.x - collarR, y: c.y - collarR, width: collarR * 2, height: collarR * 2))
        UIColor(red: 0.24, green: 0.12, blue: 0.03, alpha: 0.9).setStroke()
        collar.lineWidth = 3.2
        collar.stroke()

        // Inner domed crimson-enamel jewel button.
        let ir = r * 0.66
        let innerPath = UIBezierPath(ovalIn: CGRect(x: c.x - ir, y: c.y - ir, width: ir * 2, height: ir * 2))
        ctx.saveGState()
        innerPath.addClip()
        let dome = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 0.96, green: 0.32, blue: 0.22, alpha: 1).cgColor,
            UIColor(red: 0.70, green: 0.12, blue: 0.10, alpha: 1).cgColor,
            UIColor(red: 0.36, green: 0.04, blue: 0.05, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.56, 1])!
        ctx.drawRadialGradient(dome, startCenter: CGPoint(x: c.x - ir * 0.28, y: c.y - ir * 0.32), startRadius: 1, endCenter: c, endRadius: ir * 1.12, options: [])

        // Glossy vitreous enamel top crescent specular sheen.
        let sheen = UIBezierPath(ovalIn: CGRect(x: c.x - ir * 0.68, y: c.y - ir * 0.88, width: ir * 1.36, height: ir * 0.72))
        let sheenGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor.white.withAlphaComponent(0.42).cgColor,
            UIColor.white.withAlphaComponent(0.02).cgColor,
        ] as CFArray, locations: [0, 1])!
        ctx.saveGState(); sheen.addClip()
        ctx.drawLinearGradient(sheenGrad, start: CGPoint(x: c.x, y: c.y - ir * 0.88), end: CGPoint(x: c.x, y: c.y - ir * 0.16), options: [])
        ctx.restoreGState()
        ctx.restoreGState()

        UIColor(red: 0.98, green: 0.85, blue: 0.46, alpha: 1).setStroke()
        innerPath.lineWidth = 2.0
        innerPath.stroke()

        // Crisp embossed antique-gold "抽!" label.
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.55); shadow.shadowBlurRadius = 2.5; shadow.shadowOffset = CGSize(width: 0, height: 1.2)
        let title = NSAttributedString(string: "抽!", attributes: [
            .font: MeadowPreviewPalette.font(max(13, ir * 0.80), .heavy),
            .foregroundColor: UIColor(red: 1.0, green: 0.96, blue: 0.82, alpha: 1),
            .shadow: shadow,
        ])
        let sz = title.size()
        title.draw(at: CGPoint(x: c.x - sz.width / 2 + 1, y: c.y - sz.height / 2))
    }
}

// MARK: - Cast-Brass & Faceted Ruby Clapper Pointer

private final class WheelPointerView: UIView {
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; isUserInteractionEnabled = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 12 else { return }
        let w = bounds.width, h = bounds.height, cx = w / 2
        let headR = w * 0.40
        let headY = headR + 2

        let body = UIBezierPath()
        body.move(to: CGPoint(x: cx, y: h - 3))
        body.addCurve(to: CGPoint(x: cx - headR, y: headY), controlPoint1: CGPoint(x: cx - w * 0.15, y: h * 0.68), controlPoint2: CGPoint(x: cx - headR, y: headY + headR * 0.64))
        body.addArc(withCenter: CGPoint(x: cx, y: headY), radius: headR, startAngle: .pi, endAngle: 0, clockwise: true)
        body.addCurve(to: CGPoint(x: cx, y: h - 3), controlPoint1: CGPoint(x: cx + headR, y: headY + headR * 0.64), controlPoint2: CGPoint(x: cx + w * 0.15, y: h * 0.68))
        body.close()

        // Deep realistic drop shadow cast onto the spinning drum.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 1.5, height: 5), blur: 7, color: UIColor.black.withAlphaComponent(0.54).cgColor)
        UIColor(red: 0.54, green: 0.36, blue: 0.09, alpha: 1).setFill()
        body.fill()
        ctx.restoreGState()

        // Cast brushed-brass body with chiseled left/right bevel facets.
        ctx.saveGState()
        body.addClip()
        UIColor(red: 0.78, green: 0.58, blue: 0.22, alpha: 1).setFill()
        ctx.fill(bounds)
        WheelMaterials.drawCover(WheelMaterials.brushedBrass, in: bounds, blend: .normal, alpha: 0.94)
        // Left lit bevel facet + right shaded bevel facet
        let leftFacet = CGRect(x: 0, y: 0, width: cx, height: h)
        UIColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 0.26).setFill(); ctx.fill(leftFacet)
        let rightFacet = CGRect(x: cx, y: 0, width: cx, height: h)
        UIColor(red: 0.24, green: 0.12, blue: 0.02, alpha: 0.26).setFill(); ctx.fill(rightFacet)
        ctx.restoreGState()
        UIColor(red: 0.28, green: 0.16, blue: 0.04, alpha: 0.95).setStroke()
        body.lineWidth = 1.6
        body.stroke()

        // Faceted crimson ruby teardrop inlay set inside a recessed gold bezel.
        let gem = UIBezierPath()
        let gemR = headR * 0.62
        gem.move(to: CGPoint(x: cx, y: h - 10))
        gem.addCurve(to: CGPoint(x: cx - gemR, y: headY), controlPoint1: CGPoint(x: cx - w * 0.10, y: h * 0.66), controlPoint2: CGPoint(x: cx - gemR, y: headY + gemR * 0.58))
        gem.addArc(withCenter: CGPoint(x: cx, y: headY), radius: gemR, startAngle: .pi, endAngle: 0, clockwise: true)
        gem.addCurve(to: CGPoint(x: cx, y: h - 10), controlPoint1: CGPoint(x: cx + gemR, y: headY + gemR * 0.58), controlPoint2: CGPoint(x: cx + w * 0.10, y: h * 0.66))
        gem.close()
        ctx.saveGState()
        gem.addClip()
        let ruby = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 1.00, green: 0.45, blue: 0.48, alpha: 1).cgColor,
            UIColor(red: 0.80, green: 0.10, blue: 0.18, alpha: 1).cgColor,
            UIColor(red: 0.42, green: 0.03, blue: 0.07, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.52, 1])!
        ctx.drawRadialGradient(ruby, startCenter: CGPoint(x: cx - gemR * 0.30, y: headY - gemR * 0.25), startRadius: 1, endCenter: CGPoint(x: cx, y: headY + gemR), endRadius: h * 0.64, options: [])
        // Sharp gem facet highlight
        let facet = UIBezierPath()
        facet.move(to: CGPoint(x: cx - gemR * 0.52, y: headY + gemR * 0.1))
        facet.addLine(to: CGPoint(x: cx - gemR * 0.08, y: headY + gemR * 0.55))
        facet.addLine(to: CGPoint(x: cx - gemR * 0.22, y: h - 17))
        facet.close()
        UIColor.white.withAlphaComponent(0.32).setFill(); facet.fill()
        ctx.restoreGState()
        UIColor(red: 0.36, green: 0.20, blue: 0.04, alpha: 0.85).setStroke()
        gem.lineWidth = 1.1
        gem.stroke()

        // Domed machined brass pivot pin at hinge center.
        let pr = headR * 0.34
        let pivot = UIBezierPath(ovalIn: CGRect(x: cx - pr, y: headY - pr, width: pr * 2, height: pr * 2))
        UIColor(red: 0.98, green: 0.88, blue: 0.56, alpha: 1).setFill(); pivot.fill()
        UIColor(red: 0.36, green: 0.20, blue: 0.05, alpha: 0.92).setStroke(); pivot.lineWidth = 1.2; pivot.stroke()
        UIColor.white.withAlphaComponent(0.88).setFill()
        UIBezierPath(ovalIn: CGRect(x: cx - pr * 0.48, y: headY - pr * 0.56, width: pr * 0.56, height: pr * 0.56)).fill()
    }
}

// MARK: - Textured Skeuomorphic Wheel Face + Readability-First Narrow-Slice Simplification

/// The rotating drum face: each slice is finished with real tactile material textures
/// (antique cotton parchment / woven royal damask sapphire & amethyst / hammered antique gold leaf),
/// raised 3D brass ribs, physical 3D rim pegs, and strict geometry-driven progressive simplification so
/// narrow slices never overlap spokes or squish unreadable icons/text.
final class WheelFaceView: UIView {
    var slices: [WheelSlice] = []
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Exact inscribed perpendicular width inside a wedge of angular width `sector` at radial fraction `rho`,
    /// after subtracting spoke thickness and clean visual breathing margins on both sides.
    private func wedgeWidth(r: CGFloat, rho: CGFloat, sector: CGFloat, margin: CGFloat = 6.0) -> CGFloat {
        2 * (r * rho) * sin(min(sector, .pi) / 2) - margin
    }

    /// Material gradient pair (inner, outer) + high-contrast text ink + luxury trim tint for each slice.
    private func material(for slice: WheelSlice, index: Int, allTextCommon: Bool) -> (inner: UIColor, outer: UIColor, ink: UIColor, trim: UIColor?) {
        switch slice.rarity {
        case .legendary:
            return (
                UIColor(red: 1.00, green: 0.94, blue: 0.64, alpha: 1),
                UIColor(red: 0.84, green: 0.50, blue: 0.06, alpha: 1),
                UIColor(red: 0.24, green: 0.10, blue: 0.01, alpha: 1),
                UIColor(red: 1.00, green: 0.95, blue: 0.68, alpha: 1)
            )
        case .epic:
            return (
                UIColor(red: 0.54, green: 0.25, blue: 0.84, alpha: 1),
                UIColor(red: 0.28, green: 0.09, blue: 0.54, alpha: 1),
                UIColor(red: 1.00, green: 0.98, blue: 1.00, alpha: 1),
                UIColor(red: 0.92, green: 0.78, blue: 1.00, alpha: 1)
            )
        case .rare:
            return (
                UIColor(red: 0.20, green: 0.48, blue: 0.86, alpha: 1),
                UIColor(red: 0.08, green: 0.25, blue: 0.58, alpha: 1),
                UIColor(red: 0.98, green: 0.99, blue: 1.00, alpha: 1),
                UIColor(red: 0.76, green: 0.91, blue: 1.00, alpha: 1)
            )
        case .common:
            if slice.coins {
                return (
                    UIColor(red: 0.99, green: 0.94, blue: 0.79, alpha: 1),
                    UIColor(red: 0.88, green: 0.73, blue: 0.42, alpha: 1),
                    UIColor(red: 0.28, green: 0.14, blue: 0.02, alpha: 1),
                    UIColor(red: 0.72, green: 0.50, blue: 0.14, alpha: 0.45)
                )
            }
            if allTextCommon {
                let palettes: [(UIColor, UIColor)] = [
                    (UIColor(red: 0.99, green: 0.96, blue: 0.90, alpha: 1), UIColor(red: 0.91, green: 0.85, blue: 0.73, alpha: 1)),
                    (UIColor(red: 0.89, green: 0.94, blue: 0.90, alpha: 1), UIColor(red: 0.75, green: 0.85, blue: 0.79, alpha: 1)),
                    (UIColor(red: 0.98, green: 0.91, blue: 0.82, alpha: 1), UIColor(red: 0.88, green: 0.77, blue: 0.63, alpha: 1)),
                ]
                var k = index % palettes.count
                if index == slices.count - 1, slices.count > 1, k == 0 { k = (slices.count - 2) % palettes.count == 1 ? 2 : 1 }
                return (palettes[k].0, palettes[k].1, UIColor(red: 0.17, green: 0.12, blue: 0.08, alpha: 1), nil)
            }
            let odd = index % 2 == 1
            return (
                odd ? UIColor(red: 0.95, green: 0.91, blue: 0.82, alpha: 1) : UIColor(red: 0.99, green: 0.97, blue: 0.91, alpha: 1),
                odd ? UIColor(red: 0.85, green: 0.78, blue: 0.66, alpha: 1) : UIColor(red: 0.91, green: 0.85, blue: 0.74, alpha: 1),
                UIColor(red: 0.20, green: 0.14, blue: 0.09, alpha: 1),
                nil
            )
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), !slices.isEmpty else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) / 2
        let drumRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        let spans = WheelSlice.angles(slices)
        let allTextCommon = slices.allSatisfy { $0.icon == nil && !$0.coins }

        // 1. Paint every rarity-crafted sector with base radial gradient + real generated material texture overlay!
        for (i, s) in slices.enumerated() {
            let sector = spans[i].width
            guard sector > 0.001 else { continue }
            let start = -CGFloat.pi / 2 + spans[i].start, end = start + sector
            let wedge = UIBezierPath()
            wedge.move(to: c)
            wedge.addArc(withCenter: c, radius: r, startAngle: start, endAngle: end, clockwise: true)
            wedge.close()

            let mat = material(for: s, index: i, allTextCommon: allTextCommon)
            ctx.saveGState()
            wedge.addClip()

            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [mat.inner.cgColor, mat.outer.cgColor] as CFArray, locations: [0.16, 0.96])!
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: r * 0.12, endCenter: c, endRadius: r, options: [])

            // Overlay genuine tactile texture matched to rarity material while preserving crisp contrast!
            switch s.rarity {
            case .legendary:
                WheelMaterials.drawCover(WheelMaterials.hammeredGold, in: drumRect, blend: .softLight, alpha: 0.74)
                WheelMaterials.drawCover(WheelMaterials.royalDamask, in: drumRect, blend: .overlay, alpha: 0.24)
                // Delicate golden sunburst ray highlight down center of legendary wedge
                let mid = start + sector / 2
                let ray = UIBezierPath()
                ray.move(to: CGPoint(x: c.x + cos(mid) * r * 0.24, y: c.y + sin(mid) * r * 0.24))
                ray.addLine(to: CGPoint(x: c.x + cos(mid) * r * 0.90, y: c.y + sin(mid) * r * 0.90))
                ray.lineWidth = max(2, min(14, r * sector * 0.16))
                UIColor(red: 1.0, green: 0.98, blue: 0.80, alpha: 0.24).setStroke()
                ray.stroke()
            case .epic:
                WheelMaterials.drawCover(WheelMaterials.royalDamask, in: drumRect, blend: .overlay, alpha: 0.62)
            case .rare:
                WheelMaterials.drawCover(WheelMaterials.royalDamask, in: drumRect, blend: .overlay, alpha: 0.56)
            case .common:
                WheelMaterials.drawCover(WheelMaterials.parchment, in: drumRect, blend: .multiply, alpha: 0.58)
                if s.coins {
                    WheelMaterials.drawCover(WheelMaterials.hammeredGold, in: drumRect, blend: .softLight, alpha: 0.36)
                }
            }

            // Embossed ornamental filigree arcs near outer rim of sector.
            if let trim = mat.trim {
                let outerFiligree = UIBezierPath(arcCenter: c, radius: r * 0.905, startAngle: start, endAngle: end, clockwise: true)
                outerFiligree.lineWidth = s.rarity == .legendary ? 2.6 : 1.8
                trim.withAlphaComponent(0.84).setStroke()
                outerFiligree.stroke()

                if s.rarity >= .epic {
                    let innerFiligree = UIBezierPath(arcCenter: c, radius: r * 0.865, startAngle: start, endAngle: end, clockwise: true)
                    innerFiligree.lineWidth = 0.9
                    trim.withAlphaComponent(0.54).setStroke()
                    innerFiligree.stroke()
                }
            } else {
                // Subtle blind-debossed classical border line on parchment sectors.
                let parchTrim = UIBezierPath(arcCenter: c, radius: r * 0.905, startAngle: start, endAngle: end, clockwise: true)
                parchTrim.lineWidth = 1.0
                UIColor(red: 0.56, green: 0.44, blue: 0.28, alpha: 0.34).setStroke()
                parchTrim.stroke()
            }
            ctx.restoreGState()
        }

        // 2. Dimensional raised 3D machined brass divider ribs between sectors.
        let dense = slices.count >= 20
        for i in slices.indices {
            guard spans[i].width > 0.001 else { continue }
            let a = -CGFloat.pi / 2 + spans[i].start
            let p0 = CGPoint(x: c.x + cos(a) * r * 0.22, y: c.y + sin(a) * r * 0.22)
            let p1 = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            // Subtle offset cast shadow next to the raised brass wire
            let nx = -sin(a) * 0.9, ny = cos(a) * 0.9
            let cast = UIBezierPath()
            cast.move(to: CGPoint(x: p0.x + nx, y: p0.y + ny))
            cast.addLine(to: CGPoint(x: p1.x + nx, y: p1.y + ny))
            cast.lineWidth = dense ? 1.8 : 2.4
            UIColor.black.withAlphaComponent(0.26).setStroke()
            cast.stroke()

            // Dark antique bronze base
            let darkLine = UIBezierPath(); darkLine.move(to: p0); darkLine.addLine(to: p1)
            darkLine.lineWidth = dense ? 2.1 : 2.8
            UIColor(red: 0.30, green: 0.18, blue: 0.04, alpha: 0.82).setStroke()
            darkLine.stroke()

            // Brushed antique brass body
            let goldLine = UIBezierPath(); goldLine.move(to: p0); goldLine.addLine(to: p1)
            goldLine.lineWidth = dense ? 1.15 : 1.55
            UIColor(red: 0.92, green: 0.76, blue: 0.38, alpha: 0.96).setStroke()
            goldLine.stroke()

            // Thin bright champagne specular ridge
            let hiLine = UIBezierPath(); hiLine.move(to: p0); hiLine.addLine(to: p1)
            hiLine.lineWidth = 0.55
            UIColor(red: 1.0, green: 0.97, blue: 0.80, alpha: 0.78).setStroke()
            hiLine.stroke()
        }

        // 3. Inner engraved brass collar ring around center hub.
        let innerRingR = r * 0.248
        let innerRingShadow = UIBezierPath(arcCenter: c, radius: innerRingR, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        innerRingShadow.lineWidth = 4.2
        UIColor(red: 0.28, green: 0.16, blue: 0.04, alpha: 0.65).setStroke()
        innerRingShadow.stroke()
        let innerRing = UIBezierPath(arcCenter: c, radius: innerRingR, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        innerRing.lineWidth = 2.4
        UIColor(red: 0.93, green: 0.77, blue: 0.38, alpha: 0.96).setStroke()
        innerRing.stroke()

        // 4. Sector contents with strict readability-first progressive simplification!
        for (i, s) in slices.enumerated() {
            let sector = spans[i].width
            guard sector > 0.001 else { continue }
            let start = -CGFloat.pi / 2 + spans[i].start
            let mid = start + sector / 2
            let mat = material(for: s, index: i, allTextCommon: allTextCommon)
            let isDarkBg = s.rarity == .rare || s.rarity == .epic

            var simplified = false

            if let icon = s.icon {
                let w72 = wedgeWidth(r: r, rho: 0.71, sector: sector, margin: 6.5)
                let w77 = wedgeWidth(r: r, rho: 0.76, sector: sector, margin: 5.5)

                if w72 >= 26 {
                    // TIER 1 & 2: Clean brass-rimmed ivory-enamel medallion strictly inside the wedge (NEVER crosses spokes!).
                    let discD = min(r * 0.26, w72 * 0.88)
                    let discR = discD / 2
                    let side = discD * 0.70
                    let centerPt = CGPoint(x: c.x + cos(mid) * r * 0.71, y: c.y + sin(mid) * r * 0.71)

                    ctx.saveGState()
                    ctx.translateBy(x: centerPt.x, y: centerPt.y)
                    ctx.rotate(by: mid + .pi / 2)
                    drawIconMedallion(icon: icon, discR: discR, iconSide: side, rarity: s.rarity, ctx: ctx)
                    ctx.restoreGState()

                    // Badge (×2 etc.) placed radially INWARD toward the hub so it never touches side spokes.
                    if let badge = s.badge {
                        let badgeRho: CGFloat = 0.49
                        let wBadge = wedgeWidth(r: r, rho: badgeRho, sector: sector, margin: 5.0)
                        if wBadge >= 20 {
                            let bp = CGPoint(x: c.x + cos(mid) * r * badgeRho, y: c.y + sin(mid) * r * badgeRho)
                            ctx.saveGState()
                            ctx.translateBy(x: bp.x, y: bp.y)
                            ctx.rotate(by: cos(mid) < 0 ? mid + .pi : mid)
                            drawMiniBadge(badge, at: .zero, color: s.rarity.badgeColor)
                            ctx.restoreGState()
                        }
                    } else if w72 >= 70 {
                        // Very generous item slice (e.g. custom wheel 15%+ item): show short title radially inward
                        // ONLY when the full title fits cleanly without ugly ellipsis truncation!
                        let titleRho: CGFloat = 0.44
                        let wTitle = wedgeWidth(r: r, rho: titleRho, sector: sector, margin: 10.0)
                        let f = MeadowPreviewPalette.font(12.5, .heavy)
                        let fullW = NSAttributedString(string: s.title, attributes: [.font: f]).size().width
                        if fullW <= min(wTitle * 0.92, 92) {
                            let tp = CGPoint(x: c.x + cos(mid) * r * titleRho, y: c.y + sin(mid) * r * titleRho)
                            ctx.saveGState()
                            ctx.translateBy(x: tp.x, y: tp.y)
                            let rot = mid + .pi / 2
                            ctx.rotate(by: sin(mid) > 0.15 ? rot + .pi : rot)
                            drawText(s.title, at: .zero, size: 12.5, color: mat.ink, darkBg: isDarkBg)
                            ctx.restoreGState()
                        }
                    }
                } else if w77 >= 19.5 {
                    // TIER 3 (Compact): Frameless direct pixel icon with subtle contrast drop halo strictly inside the wedge.
                    let side = min(22, w77 * 0.86)
                    let pt = CGPoint(x: c.x + cos(mid) * r * 0.755, y: c.y + sin(mid) * r * 0.755)
                    ctx.saveGState()
                    ctx.translateBy(x: pt.x, y: pt.y)
                    ctx.rotate(by: mid + .pi / 2)
                    // Soft subtle halo disc behind icon (much sleeker than opaque sticker)
                    let haloR = side * 0.56
                    let halo = UIBezierPath(ovalIn: CGRect(x: -haloR, y: -haloR, width: haloR * 2, height: haloR * 2))
                    (isDarkBg ? UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 0.24) : UIColor.white.withAlphaComponent(0.42)).setFill()
                    halo.fill()
                    ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2.5, color: UIColor.black.withAlphaComponent(0.45).cgColor)
                    ctx.interpolationQuality = .none
                    icon.draw(in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
                    ctx.restoreGState()
                } else {
                    // TIER 4 (Simplified 简略显示): Slice too narrow for a clear icon -> clean aligned rarity emblem!
                    simplified = true
                    let rawOuter = 2 * (r * 0.82) * sin(min(sector, .pi) / 2)
                    drawSimplifiedSliceToken(rarity: s.rarity, coins: s.coins, c: c, r: r, mid: mid, outerWidth: w77, rawOuterChord: rawOuter, ctx: ctx)
                }
            } else {
                // Pure text OR coin/score slice: ALWAYS unified and radially oriented along the wedge!
                let (fullLabel, compactLabel) = unifiedTextLabels(for: s)
                simplified = drawRadialTextOrSimplify(
                    full: fullLabel,
                    compact: compactLabel,
                    c: c, r: r, mid: mid, sector: sector,
                    ink: mat.ink, isDark: isDarkBg, rarity: s.rarity, coins: s.coins, ctx: ctx
                )
            }

            // Outer ornamental rarity gem inlay ONLY on non-simplified slices with ample outer rim room.
            if !simplified, s.rarity >= .rare, wedgeWidth(r: r, rho: 0.885, sector: sector, margin: 4.0) >= 16 {
                let gemPt = CGPoint(x: c.x + cos(mid) * r * 0.885, y: c.y + sin(mid) * r * 0.885)
                drawRarityGem(s.rarity, at: gemPt, angle: mid + .pi / 2, size: min(8.2, max(5.2, r * 0.034)), ctx: ctx)
            }
        }

        // 5. Physical 3D machined brass boundary pegs around outer perimeter!
        let pegRingR = r * 0.952
        let minSector = spans.map(\.width).filter { $0 > 0.001 }.min() ?? 0.3
        let minPegSpacing = 2 * pegRingR * sin(min(minSector, .pi) / 2)
        let pegR = max(2.2, min(4.3, min(r * 0.019, minPegSpacing * 0.34)))
        for i in slices.indices {
            guard spans[i].width > 0.001 else { continue }
            let a = -CGFloat.pi / 2 + spans[i].start
            let pt = CGPoint(x: c.x + cos(a) * pegRingR, y: c.y + sin(a) * pegRingR)
            // Cast drop shadow onto drum
            UIColor.black.withAlphaComponent(0.42).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - pegR + 0.8, y: pt.y - pegR + 1.4, width: pegR * 2, height: pegR * 2)).fill()
            // Dark bronze collar
            UIColor(red: 0.34, green: 0.20, blue: 0.05, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - pegR, y: pt.y - pegR, width: pegR * 2, height: pegR * 2)).fill()
            // Warm machined brass pin head
            UIColor(red: 0.94, green: 0.78, blue: 0.38, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - pegR * 0.78, y: pt.y - pegR * 0.78, width: pegR * 1.56, height: pegR * 1.56)).fill()
            // Crisp specular catch-light dot
            UIColor.white.withAlphaComponent(0.92).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - pegR * 0.50, y: pt.y - pegR * 0.54, width: pegR * 0.56, height: pegR * 0.56)).fill()
        }
    }

    /// Combines `title` and `badge` cleanly without duplication (e.g. "+120" + "金币袋" -> "+120 金币", compact "+120").
    private func unifiedTextLabels(for s: WheelSlice) -> (full: String, compact: String) {
        guard let badge = s.badge, !badge.isEmpty else {
            return (s.title, s.title)
        }
        let cleanBadge = badge.trimmingCharacters(in: CharacterSet(charactersIn: "+ "))
        if !cleanBadge.isEmpty, s.title.contains(cleanBadge) {
            return (s.title, badge)
        }
        if s.coins {
            return ("\(badge) 金币", badge)
        }
        return ("\(s.title) \(badge)", badge)
    }

    /// Renders an antique-brass-rimmed ivory-parchment enamel medallion holding a crisp pixel sprite.
    private func drawIconMedallion(icon: UIImage, discR: CGFloat, iconSide: CGFloat, rarity: MeadowItemRarity, ctx: CGContext) {
        let discRect = CGRect(x: -discR, y: -discR, width: discR * 2, height: discR * 2)
        let disc = UIBezierPath(ovalIn: discRect)

        // Cast shadow anchoring the medallion onto the textured sector surface.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1.8), blur: 3.5, color: UIColor.black.withAlphaComponent(0.36).cgColor)
        UIColor(red: 0.97, green: 0.94, blue: 0.86, alpha: 0.94).setFill()
        disc.fill()
        ctx.restoreGState()

        // Warm recessed ivory-parchment enamel inlay with soft inner rim bevel.
        ctx.saveGState()
        disc.addClip()
        let fillGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 1.00, green: 0.99, blue: 0.95, alpha: 0.96).cgColor,
            UIColor(red: 0.93, green: 0.88, blue: 0.77, alpha: 0.96).cgColor,
        ] as CFArray, locations: [0.25, 1.0])!
        ctx.drawRadialGradient(fillGrad, startCenter: CGPoint(x: -discR * 0.2, y: -discR * 0.25), startRadius: 1, endCenter: .zero, endRadius: discR, options: [])
        WheelMaterials.drawCover(WheelMaterials.parchment, in: discRect, blend: .multiply, alpha: 0.28)
        ctx.restoreGState()

        // Double beveled metallic frame (dark antique outer edge + warm gilded brass/rarity bezel).
        let outerEdge = UIBezierPath(ovalIn: discRect.insetBy(dx: -0.6, dy: -0.6))
        UIColor(red: 0.30, green: 0.18, blue: 0.05, alpha: 0.65).setStroke()
        outerEdge.lineWidth = 1.0
        outerEdge.stroke()

        let bezelColor: UIColor = rarity == .legendary
            ? UIColor(red: 0.84, green: 0.56, blue: 0.10, alpha: 1)
            : rarity == .epic
                ? UIColor(red: 0.78, green: 0.58, blue: 0.96, alpha: 1)
                : rarity == .rare
                    ? UIColor(red: 0.58, green: 0.80, blue: 1.00, alpha: 1)
                    : UIColor(red: 0.76, green: 0.62, blue: 0.34, alpha: 1)
        bezelColor.setStroke()
        disc.lineWidth = rarity >= .epic ? 2.1 : 1.5
        disc.stroke()

        ctx.interpolationQuality = .none
        icon.draw(in: CGRect(x: -iconSide / 2, y: -iconSide / 2, width: iconSide, height: iconSide))
    }

    /// Simplified presentation (`简略显示`) when a slice is too narrow for an icon or full title:
    /// draws a crisp inlaid rarity emblem (or minimal golden/gem pearl for razor-thin slivers) along one graceful arc.
    private func drawSimplifiedSliceToken(rarity: MeadowItemRarity, coins: Bool, c: CGPoint, r: CGFloat, mid: CGFloat, outerWidth: CGFloat, rawOuterChord: CGFloat, ctx: CGContext) {
        if outerWidth >= 8.5 {
            let pt = CGPoint(x: c.x + cos(mid) * r * 0.77, y: c.y + sin(mid) * r * 0.77)
            let gemSize = min(8.2, max(5.0, outerWidth * 0.42))
            if rarity == .common {
                drawCommonPip(at: pt, size: gemSize * 0.72, gold: coins, ctx: ctx)
            } else {
                drawRarityGem(rarity, at: pt, angle: mid + .pi / 2, size: gemSize, ctx: ctx)
            }
        } else if rawOuterChord >= 5.5 {
            let pt = CGPoint(x: c.x + cos(mid) * r * 0.83, y: c.y + sin(mid) * r * 0.83)
            let dotR = max(1.7, min(3.0, rawOuterChord * 0.24))
            let fill: UIColor = rarity == .legendary
                ? UIColor(red: 1.0, green: 0.97, blue: 0.76, alpha: 0.96)
                : rarity == .epic
                    ? UIColor(red: 0.96, green: 0.84, blue: 1.0, alpha: 0.96)
                    : rarity == .rare
                        ? UIColor(red: 0.84, green: 0.95, blue: 1.0, alpha: 0.96)
                        : UIColor(red: 0.56, green: 0.40, blue: 0.16, alpha: 0.85)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 1.5, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            fill.setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - dotR, y: pt.y - dotR, width: dotR * 2, height: dotR * 2)).fill()
            ctx.restoreGState()
        }
    }

    private func drawCommonPip(at pt: CGPoint, size: CGFloat, gold: Bool, ctx: CGContext) {
        ctx.saveGState()
        let r = size * 0.72
        let oval = UIBezierPath(ovalIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
        (gold ? UIColor(red: 0.95, green: 0.74, blue: 0.24, alpha: 1) : UIColor(red: 0.74, green: 0.62, blue: 0.42, alpha: 1)).setFill()
        oval.fill()
        UIColor(red: 0.38, green: 0.24, blue: 0.08, alpha: 0.85).setStroke()
        oval.lineWidth = 1.1
        oval.stroke()
        ctx.restoreGState()
    }

    private func drawRarityGem(_ rarity: MeadowItemRarity, at pt: CGPoint, angle: CGFloat, size: CGFloat, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: pt.x, y: pt.y)
        ctx.rotate(by: angle)
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        let p = UIBezierPath()
        switch rarity {
        case .legendary:
            // Faceted 4-point royal gold star
            for k in 0..<8 {
                let a = CGFloat(k) * .pi / 4 - .pi / 2
                let rad = k % 2 == 0 ? size : size * 0.38
                let v = CGPoint(x: cos(a) * rad, y: sin(a) * rad)
                if k == 0 { p.move(to: v) } else { p.addLine(to: v) }
            }
            p.close()
            UIColor(red: 1.0, green: 0.98, blue: 0.80, alpha: 1).setFill()
            UIColor(red: 0.56, green: 0.26, blue: 0.02, alpha: 1).setStroke()
        case .epic:
            // Faceted royal amethyst crystal
            p.move(to: CGPoint(x: 0, y: -size))
            p.addLine(to: CGPoint(x: size * 0.66, y: -size * 0.28))
            p.addLine(to: CGPoint(x: size * 0.66, y: size * 0.28))
            p.addLine(to: CGPoint(x: 0, y: size))
            p.addLine(to: CGPoint(x: -size * 0.66, y: size * 0.28))
            p.addLine(to: CGPoint(x: -size * 0.66, y: -size * 0.28))
            p.close()
            UIColor(red: 0.96, green: 0.85, blue: 1.0, alpha: 1).setFill()
            UIColor(red: 0.32, green: 0.08, blue: 0.58, alpha: 1).setStroke()
        case .rare, .common:
            // Faceted sapphire diamond
            p.move(to: CGPoint(x: 0, y: -size * 0.92))
            p.addLine(to: CGPoint(x: size * 0.70, y: 0))
            p.addLine(to: CGPoint(x: 0, y: size * 0.92))
            p.addLine(to: CGPoint(x: -size * 0.70, y: 0))
            p.close()
            UIColor(red: 0.86, green: 0.96, blue: 1.0, alpha: 1).setFill()
            UIColor(red: 0.07, green: 0.24, blue: 0.58, alpha: 1).setStroke()
        }
        p.fill(); p.lineWidth = 1.1; p.stroke()
        ctx.restoreGState()
    }

    private func drawMiniBadge(_ text: String, at p: CGPoint, color: UIColor) {
        let attr = NSAttributedString(string: text, attributes: [
            .font: MeadowPreviewPalette.font(10, .heavy),
            .foregroundColor: UIColor.white,
        ])
        let sz = attr.size()
        let pill = CGRect(x: p.x - sz.width / 2 - 5, y: p.y - sz.height / 2 - 1.5, width: sz.width + 10, height: sz.height + 3)
        let path = UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2)
        color.setFill(); path.fill()
        UIColor(red: 1.0, green: 0.95, blue: 0.78, alpha: 0.75).setStroke(); path.lineWidth = 0.9; path.stroke()
        attr.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
    }

    /// Renders radial text cleanly when the wedge has readable height; smoothly abbreviates or simplifies
    /// to a refined rarity emblem when the slice is too narrow for readable typography.
    /// Returns `true` when simplified to an emblem.
    private func drawRadialTextOrSimplify(
        full: String,
        compact: String,
        c: CGPoint, r: CGFloat, mid: CGFloat, sector: CGFloat,
        ink: UIColor, isDark: Bool, rarity: MeadowItemRarity, coins: Bool, ctx: CGContext
    ) -> Bool {
        let midThick = wedgeWidth(r: r, rho: 0.62, sector: sector, margin: 5.5)
        let outerThick = wedgeWidth(r: r, rho: 0.78, sector: sector, margin: 5.0)

        // Razor-thin or too-cramped slice -> clean simplified rarity token!
        if outerThick < 11.5 || (midThick < 12.0 && compact.count > 3) {
            let rawOuter = 2 * (r * 0.82) * sin(min(sector, .pi) / 2)
            drawSimplifiedSliceToken(rarity: rarity, coins: coins, c: c, r: r, mid: mid, outerWidth: outerThick, rawOuterChord: rawOuter, ctx: ctx)
            return true
        }

        let font = { (size: CGFloat) in MeadowPreviewPalette.font(size, .heavy) }
        func textW(_ t: String, _ z: CGFloat) -> CGFloat {
            NSAttributedString(string: t, attributes: [.font: font(z)]).size().width
        }

        // Very narrow slice with short token (e.g. "+120", "VS", "一"): place concisely in the wider outer band.
        if midThick < 13.5 {
            let inner = r * 0.56, outer = r * 0.87, length = outer - inner
            let size = max(9.5, min(11.5, outerThick * 0.68))
            let label = truncate(compact, font: font(size), maxWidth: length * 0.90)
            ctx.saveGState()
            ctx.translateBy(x: c.x + cos(mid) * (inner + length * 0.50), y: c.y + sin(mid) * (inner + length * 0.50))
            ctx.rotate(by: cos(mid) < 0 ? mid + .pi : mid)
            drawText(label, at: .zero, size: size, color: ink, darkBg: isDark)
            ctx.restoreGState()
            return false
        }

        // Normal & wide slices: shift inner anchor slightly outward on medium-narrow wedges for extra breathing room.
        let innerRatio: CGFloat = midThick < 21 ? 0.40 : 0.32
        let outerRatio: CGFloat = rarity >= .rare ? 0.83 : 0.87
        let inner = r * innerRatio, outer = r * outerRatio, length = outer - inner
        let innerThick = wedgeWidth(r: r, rho: innerRatio + 0.08, sector: sector, margin: 5.5)
        let chosenText = (midThick < 19 && compact != full && textW(full, 11.5) > length * 0.88) ? compact : full

        var size = min(20, max(10.5, min(innerThick * 0.72, midThick * 0.62)))
        var lines = [chosenText]
        while size > 10.5, textW(chosenText, size) > length * 0.90 { size -= 1 }

        if textW(chosenText, size) > length * 0.90 {
            if innerThick >= 28 {
                // Ample angular height -> clean balanced 2-line radial wrap.
                let half = chosenText.count / 2
                let a = String(chosenText.prefix(half + chosenText.count % 2))
                let b = String(chosenText.suffix(half))
                var twoSize = min(16.5, innerThick * 0.40)
                while twoSize > 10.5, max(textW(a, twoSize), textW(b, twoSize)) > length * 0.90 { twoSize -= 1 }
                size = twoSize
                lines = [truncate(a, font: font(size), maxWidth: length * 0.92), truncate(b, font: font(size), maxWidth: length * 0.92)]
            } else {
                lines = [truncate(chosenText, font: font(size), maxWidth: length * 0.92)]
            }
        }

        ctx.saveGState()
        ctx.translateBy(x: c.x + cos(mid) * (inner + length * 0.50), y: c.y + sin(mid) * (inner + length * 0.50))
        ctx.rotate(by: cos(mid) < 0 ? mid + .pi : mid)
        let gap = size * 1.16
        for (k, line) in lines.enumerated() {
            drawText(line, at: CGPoint(x: 0, y: (CGFloat(k) - CGFloat(lines.count - 1) / 2) * gap), size: size, color: ink, darkBg: isDark)
        }
        ctx.restoreGState()
        return false
    }

    private func truncate(_ s: String, font: UIFont, maxWidth: CGFloat) -> String {
        var cur = s
        while cur.count > 1, NSAttributedString(string: cur + "…", attributes: [.font: font]).size().width > maxWidth {
            cur.removeLast()
        }
        return cur == s ? s : cur + "…"
    }

    private func drawFitted(_ s: String, at p: CGPoint, size: CGFloat, maxWidth: CGFloat, color: UIColor, darkBg: Bool) {
        let f = MeadowPreviewPalette.font(size, .heavy)
        let label = NSAttributedString(string: s, attributes: [.font: f]).size().width <= maxWidth ? s : truncate(s, font: f, maxWidth: maxWidth)
        drawText(label, at: p, size: size, color: color, darkBg: darkBg)
    }

    private func drawText(_ s: String, at p: CGPoint, size: CGFloat, color: UIColor, darkBg: Bool) {
        let shadow = NSShadow()
        shadow.shadowColor = darkBg ? UIColor.black.withAlphaComponent(0.72) : UIColor.white.withAlphaComponent(0.68)
        shadow.shadowBlurRadius = darkBg ? 3.2 : 1.4
        shadow.shadowOffset = CGSize(width: 0, height: darkBg ? 1.2 : 0.9)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: MeadowPreviewPalette.font(size, .heavy),
            .foregroundColor: color,
            .shadow: shadow,
        ]
        if darkBg {
            attrs[.strokeColor] = UIColor.black.withAlphaComponent(0.42)
            attrs[.strokeWidth] = -1.6
        }
        let a = NSAttributedString(string: s, attributes: attrs)
        let b = a.size()
        a.draw(at: CGPoint(x: p.x - b.width / 2, y: p.y - b.height / 2))
    }
}

// MARK: - Gilded Skeuomorphic Reveal Plaque

/// The prize that came up, popping in over the wheel as a parchment-and-brass award plaque with rarity ribbon and pedestal.
final class WheelPrizeCard: UIView {
    private let textureBg = UIImageView()
    private let innerFrame = UIView()
    private let topRibbon = UILabel()
    private let iconPedestal = UIView()
    private let icon = UIImageView()
    private let title = UILabel()
    private let subtitle = UILabel()
    private let starsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 3.5
        backgroundColor = UIColor(red: 0.99, green: 0.97, blue: 0.91, alpha: 0.98)
        layer.shadowOpacity = 0.72
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 8)

        textureBg.image = WheelMaterials.parchment
        textureBg.contentMode = .scaleAspectFill
        textureBg.alpha = 0.38
        textureBg.clipsToBounds = true
        textureBg.layer.cornerRadius = 19
        textureBg.layer.cornerCurve = .continuous

        innerFrame.isUserInteractionEnabled = false
        innerFrame.backgroundColor = .clear
        innerFrame.layer.cornerRadius = 16
        innerFrame.layer.cornerCurve = .continuous
        innerFrame.layer.borderWidth = 1.0
        innerFrame.layer.borderColor = UIColor(red: 0.76, green: 0.58, blue: 0.24, alpha: 0.52).cgColor

        topRibbon.font = MeadowPreviewPalette.font(14, .heavy)
        topRibbon.textAlignment = .center
        topRibbon.textColor = .white
        topRibbon.layer.cornerRadius = 11
        topRibbon.layer.cornerCurve = .continuous
        topRibbon.clipsToBounds = true

        iconPedestal.layer.cornerRadius = 20
        iconPedestal.layer.cornerCurve = .continuous
        iconPedestal.layer.borderWidth = 1.6

        icon.contentMode = .scaleAspectFit
        icon.layer.magnificationFilter = .nearest

        title.font = MeadowPreviewPalette.font(24, .heavy)
        title.textAlignment = .center
        title.numberOfLines = 2
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.65
        title.textColor = MeadowPreviewPalette.ink

        subtitle.font = MeadowPreviewPalette.font(14, .semibold)
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 2
        subtitle.textColor = MeadowPreviewPalette.muted

        starsLabel.font = MeadowPreviewPalette.font(15, .heavy)
        starsLabel.textAlignment = .center

        [textureBg, innerFrame, topRibbon, iconPedestal, icon, title, subtitle, starsLabel].forEach(addSubview)
        alpha = 0
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        textureBg.frame = bounds.insetBy(dx: 2, dy: 2)
        innerFrame.frame = bounds.insetBy(dx: 7, dy: 7)
        let hasIcon = icon.image != nil
        let hasSub = !(subtitle.text?.isEmpty ?? true)
        topRibbon.frame = CGRect(x: (w - 138) / 2, y: 14, width: 138, height: 24)
        if hasIcon {
            let side = min(86, h * 0.35)
            iconPedestal.isHidden = false
            iconPedestal.frame = CGRect(x: (w - side - 14) / 2, y: topRibbon.frame.maxY + 8, width: side + 14, height: side + 14)
            icon.frame = iconPedestal.frame.insetBy(dx: 7, dy: 7)
            title.frame = CGRect(x: 16, y: iconPedestal.frame.maxY + 8, width: w - 32, height: hasSub ? 32 : 44)
        } else {
            iconPedestal.isHidden = true
            icon.frame = .zero
            title.frame = CGRect(x: 16, y: topRibbon.frame.maxY + 26, width: w - 32, height: 66)
        }
        subtitle.isHidden = !hasSub
        subtitle.frame = CGRect(x: 16, y: title.frame.maxY + 2, width: w - 32, height: 34)
        starsLabel.frame = CGRect(x: 16, y: h - 32, width: w - 32, height: 22)
    }

    func show(_ s: WheelSlice, prefix: String? = nil) {
        icon.image = s.icon
        title.text = (prefix ?? "") + s.title + (s.icon != nil ? (s.badge.map { " " + $0 } ?? "") : (s.badge.map { " · " + $0 } ?? ""))
        subtitle.text = s.subtitle

        let accent = s.coins ? UIColor(red: 0.84, green: 0.54, blue: 0.08, alpha: 1) : s.rarity.badgeColor
        topRibbon.text = s.coins ? "金币奖励" : "\(s.rarity.title)奖励"
        topRibbon.backgroundColor = accent
        starsLabel.text = s.coins ? "✦ ✦ ✦" : s.rarity.stars
        starsLabel.textColor = s.coins ? UIColor(red: 0.80, green: 0.48, blue: 0.04, alpha: 1) : s.rarity.inkColor
        title.textColor = s.rarity >= .epic ? s.rarity.inkColor : MeadowPreviewPalette.ink

        backgroundColor = s.coins ? UIColor(red: 1.0, green: 0.97, blue: 0.88, alpha: 0.98) : s.rarity.surfaceTint.withAlphaComponent(0.98)
        iconPedestal.backgroundColor = UIColor.white.withAlphaComponent(0.84)
        iconPedestal.layer.borderColor = (s.coins ? UIColor(red: 0.90, green: 0.64, blue: 0.16, alpha: 1) : s.rarity.borderColor).cgColor
        layer.borderColor = (s.coins ? UIColor(red: 0.90, green: 0.64, blue: 0.16, alpha: 1) : s.rarity.borderColor).cgColor
        layer.shadowColor = accent.cgColor

        setNeedsLayout()
        transform = CGAffineTransform(scaleX: 0.35, y: 0.35)
        UIView.animate(withDuration: 0.52, delay: 0.08, usingSpringWithDamping: 0.56, initialSpringVelocity: 0.9, options: []) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func hide() { UIView.animate(withDuration: 0.2) { self.alpha = 0 } }
}

private extension UIColor {
    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        var a = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0)), b = a
        getRed(&a.0, green: &a.1, blue: &a.2, alpha: &a.3); other.getRed(&b.0, green: &b.1, blue: &b.2, alpha: &b.3)
        return UIColor(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t, alpha: 1)
    }
}
