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
    /// Coins / score: drawn in warm honey-gold brass.
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

/// Skeuomorphic wooden-and-brass fantasy prize wheel:
/// carved walnut bezel + tabletop pedestal base, double machined brass trim rings, recessed warm marquee bulbs,
/// physical brass sector pegs on the spinning drum, luxury rarity-coded sector materials (cream parchment / sapphire
/// satin / amethyst velvet / imperial sunburst gold), faceted ruby-inlaid brass clapper pointer, and riveted brass hub.
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
        glow.shadowOpacity = 0.45
        glow.shadowRadius = 24
        glow.shadowOffset = CGSize(width: 0, height: 8)
        glow.shadowColor = UIColor(red: 0.42, green: 0.28, blue: 0.10, alpha: 1).cgColor
        layer.addSublayer(glow)

        addSubview(bezelView)
        addSubview(face)

        winWedge.fillColor = UIColor.white.withAlphaComponent(0.0).cgColor
        winWedge.strokeColor = UIColor(red: 1.0, green: 0.94, blue: 0.68, alpha: 1).cgColor
        winWedge.opacity = 0
        face.layer.addSublayer(winWedge)

        addSubview(hubView)
        addSubview(pointerView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(hubTapped))
        tap.delegate = self
        addGestureRecognizer(tap)

        layer.addSublayer(effects)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var radius: CGFloat {
        // Reserve room at top for pointer bracket, left/right for walnut rim, and bottom for tabletop stand foot.
        let maxR = min(bounds.width / 2 - 22, (bounds.height - 44) / 2)
        return max(40, maxR)
    }
    private var centre: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY + 2) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = radius, c = centre
        guard r > 20 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)

        bezelView.frame = bounds
        bezelView.wheelCenter = c
        bezelView.wheelRadius = r
        bezelView.setNeedsDisplay()

        face.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        face.center = c
        face.transform = CGAffineTransform(rotationAngle: angle)

        glow.frame = CGRect(x: c.x - (r + 14), y: c.y - (r + 14), width: 2 * (r + 14), height: 2 * (r + 14))
        glow.shadowPath = UIBezierPath(ovalIn: glow.bounds).cgPath

        // 28 warm tungsten marquee bulbs recessed inside the walnut-brass bezel track.
        let count = 28
        if bulbs.count != count {
            bulbs.forEach { $0.removeFromSuperlayer() }
            bulbs = (0..<count).map { _ in
                let b = CALayer()
                b.backgroundColor = UIColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 1).cgColor
                b.borderWidth = 1
                b.borderColor = UIColor(red: 0.65, green: 0.44, blue: 0.14, alpha: 0.95).cgColor
                b.shadowColor = UIColor(red: 1.0, green: 0.80, blue: 0.30, alpha: 1).cgColor
                b.shadowOpacity = 0.95
                b.shadowRadius = 4.5
                b.shadowOffset = .zero
                layer.insertSublayer(b, above: face.layer)
                return b
            }
        }
        let bulbRingR = r + 10.5
        let bulbSize: CGFloat = max(6.5, min(9.5, r * 0.042))
        for (i, b) in bulbs.enumerated() {
            let a = CGFloat(i) / CGFloat(count) * 2 * .pi - .pi / 2
            b.bounds = CGRect(x: 0, y: 0, width: bulbSize, height: bulbSize)
            b.cornerRadius = bulbSize / 2
            b.position = CGPoint(x: c.x + cos(a) * bulbRingR, y: c.y + sin(a) * bulbRingR)
            b.opacity = i % 2 == 0 ? 1.0 : 0.42
        }

        let hr = max(26, min(44, r * 0.195))
        hubView.bounds = CGRect(x: 0, y: 0, width: 2 * hr, height: 2 * hr)
        hubView.center = c
        hubView.setNeedsDisplay()

        // Sculpted ruby-brass clapper pointer mounted at 12 o'clock bezel edge.
        let pw: CGFloat = max(30, min(44, r * 0.175))
        let ph: CGFloat = pw * 1.48
        pointerView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.22)
        pointerView.bounds = CGRect(x: 0, y: 0, width: pw, height: ph)
        pointerView.center = CGPoint(x: c.x, y: c.y - r - 12)
        pointerView.setNeedsDisplay()

        bringSubviewToFront(hubView)
        bringSubviewToFront(pointerView)
        effects.frame = bounds
        layer.addSublayer(effects)
        CATransaction.commit()
    }

    // MARK: Spin

    /// Only taps on the brass hub trigger spin.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let p = touch.location(in: self), c = centre, hr = max(26, min(44, radius * 0.195)) + 8
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
        for (i, b) in bulbs.enumerated() {
            b.backgroundColor = UIColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 1).cgColor
            b.shadowColor = UIColor(red: 1.0, green: 0.80, blue: 0.30, alpha: 1).cgColor
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.22; a.duration = 0.30; a.autoreverses = true; a.repeatCount = .infinity
            a.beginTime = CACurrentMediaTime() + Double(i % 7) * 0.042
            b.add(a, forKey: "chase")
        }
    }

    private func blinkLights(tint: UIColor? = nil) {
        for b in bulbs {
            b.removeAnimation(forKey: "chase")
            if let tint {
                b.backgroundColor = tint.mixed(with: .white, 0.55).cgColor
                b.shadowColor = tint.cgColor
            }
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.20; a.duration = 0.18; a.autoreverses = true; a.repeatCount = 4
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
                self.glow.shadowColor = UIColor(red: 0.42, green: 0.28, blue: 0.10, alpha: 1).cgColor
                for b in self.bulbs {
                    b.backgroundColor = UIColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 1).cgColor
                    b.shadowColor = UIColor(red: 1.0, green: 0.80, blue: 0.30, alpha: 1).cgColor
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

// MARK: - Skeuomorphic Walnut Bezel + Tabletop Pedestal Stand

private final class WheelBezelView: UIView {
    var wheelCenter: CGPoint = .zero
    var wheelRadius: CGFloat = 0
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; isUserInteractionEnabled = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), wheelRadius > 20 else { return }
        let c = wheelCenter, r = wheelRadius
        let outerR = r + 18.5

        // 1. Subtle carved mahogany & brass tabletop stand at the base of the wheel.
        let baseY = min(bounds.height - 3, c.y + outerR + 6)
        let standTopY = c.y + r * 0.74
        let topHalfW = r * 0.30
        let botHalfW = r * 0.52

        // Cast ground shadow beneath pedestal.
        ctx.saveGState()
        let shadowRect = CGRect(x: c.x - botHalfW * 1.12, y: baseY - 6, width: botHalfW * 2.24, height: 12)
        UIColor.black.withAlphaComponent(0.22).setFill()
        UIBezierPath(ovalIn: shadowRect).fill()
        ctx.restoreGState()

        let standPath = UIBezierPath()
        standPath.move(to: CGPoint(x: c.x - topHalfW, y: standTopY))
        standPath.addLine(to: CGPoint(x: c.x + topHalfW, y: standTopY))
        standPath.addQuadCurve(to: CGPoint(x: c.x + botHalfW, y: baseY - 4), controlPoint: CGPoint(x: c.x + topHalfW * 1.15, y: baseY - 12))
        standPath.addLine(to: CGPoint(x: c.x - botHalfW, y: baseY - 4))
        standPath.addQuadCurve(to: CGPoint(x: c.x - topHalfW, y: standTopY), controlPoint: CGPoint(x: c.x - topHalfW * 1.15, y: baseY - 12))
        standPath.close()

        ctx.saveGState()
        standPath.addClip()
        let woodGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 0.25, green: 0.14, blue: 0.07, alpha: 1).cgColor,
            UIColor(red: 0.44, green: 0.27, blue: 0.14, alpha: 1).cgColor,
            UIColor(red: 0.28, green: 0.16, blue: 0.08, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.48, 1])!
        ctx.drawLinearGradient(woodGrad, start: CGPoint(x: c.x - botHalfW, y: standTopY), end: CGPoint(x: c.x + botHalfW, y: standTopY), options: [])
        ctx.restoreGState()
        UIColor(red: 0.84, green: 0.65, blue: 0.28, alpha: 0.85).setStroke()
        standPath.lineWidth = 2
        standPath.stroke()

        // Brass plinth lip along bottom foot.
        let footRect = CGRect(x: c.x - botHalfW - 6, y: baseY - 9, width: (botHalfW + 6) * 2, height: 8)
        let footPath = UIBezierPath(roundedRect: footRect, cornerRadius: 4)
        ctx.saveGState(); footPath.addClip()
        let brassGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 0.65, green: 0.45, blue: 0.16, alpha: 1).cgColor,
            UIColor(red: 0.96, green: 0.83, blue: 0.46, alpha: 1).cgColor,
            UIColor(red: 0.56, green: 0.37, blue: 0.11, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(brassGrad, start: CGPoint(x: footRect.minX, y: footRect.midY), end: CGPoint(x: footRect.maxX, y: footRect.midY), options: [])
        ctx.restoreGState()

        // 2. Carved Walnut Outer Bezel Ring.
        let bezelRing = UIBezierPath(ovalIn: CGRect(x: c.x - outerR, y: c.y - outerR, width: outerR * 2, height: outerR * 2))
        ctx.saveGState()
        bezelRing.addClip()
        let walnutGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 0.24, green: 0.13, blue: 0.06, alpha: 1).cgColor,
            UIColor(red: 0.46, green: 0.27, blue: 0.13, alpha: 1).cgColor,
            UIColor(red: 0.32, green: 0.18, blue: 0.08, alpha: 1).cgColor,
            UIColor(red: 0.18, green: 0.09, blue: 0.04, alpha: 1).cgColor,
        ] as CFArray, locations: [0.0, 0.32, 0.72, 1.0])!
        ctx.drawLinearGradient(walnutGrad, start: CGPoint(x: c.x - outerR, y: c.y - outerR), end: CGPoint(x: c.x + outerR, y: c.y + outerR), options: [])

        // Recessed channel track for the marquee bulbs.
        let track = UIBezierPath(arcCenter: c, radius: r + 10.5, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        track.lineWidth = 10
        UIColor(red: 0.18, green: 0.10, blue: 0.04, alpha: 0.65).setStroke()
        track.stroke()
        ctx.restoreGState()

        // 3. Outer & Inner Machined Brass Trim Rings (metallic bevel).
        let outerTrim = UIBezierPath(arcCenter: c, radius: outerR - 1.5, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        outerTrim.lineWidth = 3.2
        UIColor(red: 0.90, green: 0.73, blue: 0.35, alpha: 1).setStroke()
        outerTrim.stroke()

        let outerSpec = UIBezierPath(arcCenter: c, radius: outerR - 2.6, startAngle: -.pi * 0.85, endAngle: -.pi * 0.15, clockwise: true)
        outerSpec.lineWidth = 1.4
        UIColor(red: 1.0, green: 0.95, blue: 0.76, alpha: 0.78).setStroke()
        outerSpec.stroke()

        let innerBrass = UIBezierPath(arcCenter: c, radius: r + 2.2, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        innerBrass.lineWidth = 4.0
        UIColor(red: 0.88, green: 0.70, blue: 0.30, alpha: 1).setStroke()
        innerBrass.stroke()

        let innerLip = UIBezierPath(arcCenter: c, radius: r + 0.5, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        innerLip.lineWidth = 1.5
        UIColor(red: 0.22, green: 0.12, blue: 0.04, alpha: 0.85).setStroke()
        innerLip.stroke()
    }
}

// MARK: - Riveted Machined Brass Center Hub

private final class WheelHubView: UIView {
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; isUserInteractionEnabled = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 16 else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) / 2 - 2

        // Drop shadow under hub flange.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 8, color: UIColor.black.withAlphaComponent(0.42).cgColor)
        UIColor(red: 0.55, green: 0.38, blue: 0.12, alpha: 1).setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        ctx.restoreGState()

        // Outer brushed brass flange.
        let outerPath = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.saveGState(); outerPath.addClip()
        let brass = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 1.00, green: 0.93, blue: 0.66, alpha: 1).cgColor,
            UIColor(red: 0.85, green: 0.64, blue: 0.24, alpha: 1).cgColor,
            UIColor(red: 0.54, green: 0.35, blue: 0.10, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.52, 1])!
        ctx.drawLinearGradient(brass, start: CGPoint(x: c.x - r, y: c.y - r), end: CGPoint(x: c.x + r, y: c.y + r), options: [])
        ctx.restoreGState()
        UIColor(red: 0.36, green: 0.22, blue: 0.06, alpha: 0.85).setStroke()
        outerPath.lineWidth = 1.4; outerPath.stroke()

        // 8 machined mini brass rivets along the flange.
        let rivetRing = r * 0.84
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            let pt = CGPoint(x: c.x + cos(a) * rivetRing, y: c.y + sin(a) * rivetRing)
            let rr: CGFloat = max(1.6, r * 0.065)
            UIColor(red: 0.36, green: 0.22, blue: 0.06, alpha: 0.9).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - rr, y: pt.y - rr, width: rr * 2, height: rr * 2)).fill()
            UIColor(red: 1.0, green: 0.94, blue: 0.72, alpha: 0.95).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - rr * 0.65, y: pt.y - rr * 0.65, width: rr * 1.1, height: rr * 1.1)).fill()
        }

        // Inner domed crimson-gold jewel button.
        let ir = r * 0.70
        let innerPath = UIBezierPath(ovalIn: CGRect(x: c.x - ir, y: c.y - ir, width: ir * 2, height: ir * 2))
        ctx.saveGState(); innerPath.addClip()
        let dome = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 0.94, green: 0.35, blue: 0.25, alpha: 1).cgColor,
            UIColor(red: 0.72, green: 0.14, blue: 0.12, alpha: 1).cgColor,
            UIColor(red: 0.42, green: 0.06, blue: 0.07, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.58, 1])!
        ctx.drawRadialGradient(dome, startCenter: CGPoint(x: c.x - ir * 0.28, y: c.y - ir * 0.32), startRadius: 1, endCenter: c, endRadius: ir * 1.1, options: [])

        // Glass top specular sheen.
        let sheen = UIBezierPath(ovalIn: CGRect(x: c.x - ir * 0.72, y: c.y - ir * 0.88, width: ir * 1.44, height: ir * 0.78))
        UIColor.white.withAlphaComponent(0.28).setFill()
        sheen.fill()
        ctx.restoreGState()

        UIColor(red: 0.96, green: 0.82, blue: 0.42, alpha: 1).setStroke()
        innerPath.lineWidth = 2; innerPath.stroke()

        // Crisp embossed "抽!" label.
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.45); shadow.shadowBlurRadius = 2; shadow.shadowOffset = CGSize(width: 0, height: 1)
        let title = NSAttributedString(string: "抽!", attributes: [
            .font: MeadowPreviewPalette.font(max(13, ir * 0.78), .heavy),
            .foregroundColor: UIColor(red: 1.0, green: 0.96, blue: 0.82, alpha: 1),
            .shadow: shadow,
        ])
        let sz = title.size()
        title.draw(at: CGPoint(x: c.x - sz.width / 2 + 1, y: c.y - sz.height / 2))
    }
}

// MARK: - Faceted Ruby-Inlaid Brass Clapper Pointer

private final class WheelPointerView: UIView {
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; isUserInteractionEnabled = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 12 else { return }
        let w = bounds.width, h = bounds.height, cx = w / 2
        let headR = w * 0.42
        let headY = headR + 2

        let body = UIBezierPath()
        body.move(to: CGPoint(x: cx, y: h - 3))
        body.addCurve(to: CGPoint(x: cx - headR, y: headY), controlPoint1: CGPoint(x: cx - w * 0.14, y: h * 0.70), controlPoint2: CGPoint(x: cx - headR, y: headY + headR * 0.65))
        body.addArc(withCenter: CGPoint(x: cx, y: headY), radius: headR, startAngle: .pi, endAngle: 0, clockwise: true)
        body.addCurve(to: CGPoint(x: cx, y: h - 3), controlPoint1: CGPoint(x: cx + headR, y: headY + headR * 0.65), controlPoint2: CGPoint(x: cx + w * 0.14, y: h * 0.70))
        body.close()

        // Cast drop shadow onto wheel drum.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 6, color: UIColor.black.withAlphaComponent(0.48).cgColor)
        UIColor(red: 0.62, green: 0.42, blue: 0.12, alpha: 1).setFill()
        body.fill()
        ctx.restoreGState()

        // Machined gold-brass outer frame.
        ctx.saveGState(); body.addClip()
        let brass = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 1.0, green: 0.93, blue: 0.64, alpha: 1).cgColor,
            UIColor(red: 0.88, green: 0.66, blue: 0.22, alpha: 1).cgColor,
            UIColor(red: 0.56, green: 0.36, blue: 0.09, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.48, 1])!
        ctx.drawLinearGradient(brass, start: CGPoint(x: cx - headR, y: 0), end: CGPoint(x: cx + headR, y: h), options: [])
        ctx.restoreGState()
        UIColor(red: 0.34, green: 0.20, blue: 0.05, alpha: 0.95).setStroke()
        body.lineWidth = 1.6; body.stroke()

        // Faceted crimson ruby teardrop inlay inside the brass frame.
        let gem = UIBezierPath()
        let gemR = headR * 0.64
        gem.move(to: CGPoint(x: cx, y: h - 9))
        gem.addCurve(to: CGPoint(x: cx - gemR, y: headY), controlPoint1: CGPoint(x: cx - w * 0.10, y: h * 0.68), controlPoint2: CGPoint(x: cx - gemR, y: headY + gemR * 0.6))
        gem.addArc(withCenter: CGPoint(x: cx, y: headY), radius: gemR, startAngle: .pi, endAngle: 0, clockwise: true)
        gem.addCurve(to: CGPoint(x: cx, y: h - 9), controlPoint1: CGPoint(x: cx + gemR, y: headY + gemR * 0.6), controlPoint2: CGPoint(x: cx + w * 0.10, y: h * 0.68))
        gem.close()
        ctx.saveGState(); gem.addClip()
        let ruby = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(red: 1.0, green: 0.42, blue: 0.46, alpha: 1).cgColor,
            UIColor(red: 0.84, green: 0.12, blue: 0.20, alpha: 1).cgColor,
            UIColor(red: 0.48, green: 0.04, blue: 0.09, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.55, 1])!
        ctx.drawRadialGradient(ruby, startCenter: CGPoint(x: cx - gemR * 0.3, y: headY - gemR * 0.3), startRadius: 1, endCenter: CGPoint(x: cx, y: headY + gemR), endRadius: h * 0.65, options: [])
        ctx.restoreGState()

        // Brass pivot rivet cap at top mount.
        let pr = headR * 0.34
        let pivot = UIBezierPath(ovalIn: CGRect(x: cx - pr, y: headY - pr, width: pr * 2, height: pr * 2))
        UIColor(red: 0.98, green: 0.88, blue: 0.55, alpha: 1).setFill(); pivot.fill()
        UIColor(red: 0.44, green: 0.27, blue: 0.08, alpha: 0.9).setStroke(); pivot.lineWidth = 1.2; pivot.stroke()
        UIColor.white.withAlphaComponent(0.85).setFill()
        UIBezierPath(ovalIn: CGRect(x: cx - pr * 0.45, y: headY - pr * 0.55, width: pr * 0.55, height: pr * 0.55)).fill()
    }
}

// MARK: - Skeuomorphic Rarity-Crafted Wheel Face

/// The rotating drum face: each slice is painted in a tactile rarity material (parchment / royal sapphire / amethyst
/// velvet / imperial sunburst gold) with beveled brass spokes, outer rarity gem inlays, physical brass pegs at every
/// sector boundary, and smart anti-collision staggered icon medallions (never collapsing readable items into "-").
final class WheelFaceView: UIView {
    var slices: [WheelSlice] = []
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Material gradient pair (inner, outer) + high-contrast text ink + ornament tint for each slice.
    private func material(for slice: WheelSlice, index: Int, allTextCommon: Bool) -> (inner: UIColor, outer: UIColor, ink: UIColor, trim: UIColor?) {
        switch slice.rarity {
        case .legendary:
            return (
                UIColor(red: 1.00, green: 0.93, blue: 0.58, alpha: 1),
                UIColor(red: 0.85, green: 0.50, blue: 0.05, alpha: 1),
                UIColor(red: 0.30, green: 0.13, blue: 0.01, alpha: 1),
                UIColor(red: 1.00, green: 0.94, blue: 0.62, alpha: 1)
            )
        case .epic:
            return (
                UIColor(red: 0.64, green: 0.36, blue: 0.92, alpha: 1),
                UIColor(red: 0.35, green: 0.14, blue: 0.64, alpha: 1),
                UIColor(red: 0.99, green: 0.96, blue: 1.00, alpha: 1),
                UIColor(red: 0.90, green: 0.74, blue: 1.00, alpha: 1)
            )
        case .rare:
            return (
                UIColor(red: 0.28, green: 0.60, blue: 0.94, alpha: 1),
                UIColor(red: 0.12, green: 0.34, blue: 0.72, alpha: 1),
                UIColor(red: 0.96, green: 0.99, blue: 1.00, alpha: 1),
                UIColor(red: 0.74, green: 0.90, blue: 1.00, alpha: 1)
            )
        case .common:
            if slice.coins {
                return (
                    UIColor(red: 0.99, green: 0.94, blue: 0.78, alpha: 1),
                    UIColor(red: 0.90, green: 0.76, blue: 0.44, alpha: 1),
                    UIColor(red: 0.36, green: 0.20, blue: 0.03, alpha: 1),
                    nil
                )
            }
            if allTextCommon {
                // Classic board-game parchment trio for text-only classroom wheels.
                let palettes: [(UIColor, UIColor)] = [
                    (UIColor(red: 0.99, green: 0.96, blue: 0.89, alpha: 1), UIColor(red: 0.92, green: 0.86, blue: 0.74, alpha: 1)),
                    (UIColor(red: 0.89, green: 0.95, blue: 0.91, alpha: 1), UIColor(red: 0.76, green: 0.86, blue: 0.80, alpha: 1)),
                    (UIColor(red: 0.98, green: 0.91, blue: 0.82, alpha: 1), UIColor(red: 0.90, green: 0.79, blue: 0.65, alpha: 1)),
                ]
                var k = index % palettes.count
                if index == slices.count - 1, slices.count > 1, k == 0 { k = (slices.count - 2) % palettes.count == 1 ? 2 : 1 }
                return (palettes[k].0, palettes[k].1, UIColor(red: 0.18, green: 0.14, blue: 0.10, alpha: 1), nil)
            }
            // Alternating warm parchment & sand ivory for common item slots so Rare/Epic/Legendary leap off the wheel!
            let odd = index % 2 == 1
            return (
                odd ? UIColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1) : UIColor(red: 0.99, green: 0.97, blue: 0.92, alpha: 1),
                odd ? UIColor(red: 0.86, green: 0.80, blue: 0.69, alpha: 1) : UIColor(red: 0.92, green: 0.87, blue: 0.77, alpha: 1),
                UIColor(red: 0.22, green: 0.17, blue: 0.12, alpha: 1),
                nil
            )
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), !slices.isEmpty else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) / 2
        let spans = WheelSlice.angles(slices)
        let allTextCommon = slices.allSatisfy { $0.icon == nil && !$0.coins }

        // 1. Paint every rarity-crafted sector.
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
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [mat.inner.cgColor, mat.outer.cgColor] as CFArray, locations: [0.18, 0.96])!
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: r * 0.12, endCenter: c, endRadius: r, options: [])

            // Subtle luxury filigree inner-rim trim & subtle sheen for Rare / Epic / Legendary sectors.
            if let trim = mat.trim {
                let outerFiligree = UIBezierPath(arcCenter: c, radius: r * 0.915, startAngle: start, endAngle: end, clockwise: true)
                outerFiligree.lineWidth = s.rarity == .legendary ? 3.0 : 2.0
                trim.withAlphaComponent(0.85).setStroke()
                outerFiligree.stroke()

                if s.rarity >= .epic {
                    let innerFiligree = UIBezierPath(arcCenter: c, radius: r * 0.865, startAngle: start, endAngle: end, clockwise: true)
                    innerFiligree.lineWidth = 1.0
                    trim.withAlphaComponent(0.55).setStroke()
                    innerFiligree.stroke()
                }
            }
            ctx.restoreGState()
        }

        // 2. Subtle recessed drum vignette near outer bezel & hub collar for authentic 3D depth.
        ctx.saveGState()
        let drumClip = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        drumClip.addClip()
        let outerShade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor.clear.cgColor,
            UIColor(red: 0.16, green: 0.09, blue: 0.03, alpha: 0.24).cgColor,
        ] as CFArray, locations: [0.84, 1.0])!
        ctx.drawRadialGradient(outerShade, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        ctx.restoreGState()

        // 3. Beveled brass sector dividers (dark shadow + bright brass ridge).
        for i in slices.indices {
            guard spans[i].width > 0.001 else { continue }
            let a = -CGFloat.pi / 2 + spans[i].start
            let p0 = CGPoint(x: c.x + cos(a) * r * 0.22, y: c.y + sin(a) * r * 0.22)
            let p1 = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)

            let darkLine = UIBezierPath(); darkLine.move(to: p0); darkLine.addLine(to: p1)
            darkLine.lineWidth = 2.4
            UIColor(red: 0.36, green: 0.22, blue: 0.07, alpha: 0.65).setStroke()
            darkLine.stroke()

            let goldLine = UIBezierPath(); goldLine.move(to: p0); goldLine.addLine(to: p1)
            goldLine.lineWidth = 1.15
            UIColor(red: 0.95, green: 0.82, blue: 0.46, alpha: 0.92).setStroke()
            goldLine.stroke()
        }

        // 4. Inner brass decorative ring around hub.
        let innerRing = UIBezierPath(arcCenter: c, radius: r * 0.245, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        innerRing.lineWidth = 2.6
        UIColor(red: 0.88, green: 0.70, blue: 0.30, alpha: 0.92).setStroke()
        innerRing.stroke()

        // 5. Sector contents (staggered medallions for tight item slices, crisp radial text for custom text wheels).
        let tightWheel = slices.count >= 12
        for (i, s) in slices.enumerated() {
            let sector = spans[i].width
            guard sector > 0.001 else { continue }
            let start = -CGFloat.pi / 2 + spans[i].start
            let mid = start + sector / 2
            let mat = material(for: s, index: i, allTextCommon: allTextCommon)

            // Outer rarity gem inlay (diamond for Rare, crystal for Epic, 4-point star for Legendary).
            if s.rarity >= .rare, r * 0.88 * sector >= 8 {
                let gemPt = CGPoint(x: c.x + cos(mid) * r * 0.885, y: c.y + sin(mid) * r * 0.885)
                drawRarityGem(s.rarity, at: gemPt, angle: mid + .pi / 2, size: min(9, max(5.5, r * 0.038)), ctx: ctx)
            }

            if s.icon == nil, s.badge == nil {
                radial(s.title, c: c, r: r, mid: mid, sector: sector, ink: mat.ink, isDark: s.rarity == .rare || s.rarity == .epic, rarity: s.rarity, ctx: ctx)
                continue
            }

            // Stagger radial distance on dense lottery wheels so adjacent icons never collide!
            let chordAtOuter = r * 0.72 * sector
            let radialRatio: CGFloat = (tightWheel && chordAtOuter < 36) ? (i % 2 == 0 ? 0.73 : 0.55) : 0.65
            let effectiveChord = r * radialRatio * sector

            ctx.saveGState()
            ctx.translateBy(x: c.x + cos(mid) * r * radialRatio, y: c.y + sin(mid) * r * radialRatio)
            ctx.rotate(by: mid + .pi / 2)

            if let icon = s.icon {
                let side = max(16, min(r * 0.24, max(effectiveChord * 0.82, tightWheel ? 22 : 20)))
                if effectiveChord < 11 {
                    // Ultra-thin sliver: crisp mini rarity gem token instead of ugly "-".
                    drawRarityGem(s.rarity, at: .zero, angle: 0, size: 7, ctx: ctx)
                } else {
                    // Frosted ivory/gold medallion disc behind the pixel icon for crystal clarity.
                    let discR = side * 0.58
                    let discRect = CGRect(x: -discR, y: -discR, width: discR * 2, height: discR * 2)
                    let disc = UIBezierPath(ovalIn: discRect)
                    ctx.saveGState()
                    ctx.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.26).cgColor)
                    (s.rarity == .common ? UIColor.white.withAlphaComponent(0.84) : UIColor(red: 1.0, green: 0.98, blue: 0.92, alpha: 0.90)).setFill()
                    disc.fill()
                    ctx.restoreGState()
                    (s.rarity == .common ? UIColor(red: 0.72, green: 0.62, blue: 0.44, alpha: 0.85) : s.rarity.borderColor).setStroke()
                    disc.lineWidth = s.rarity >= .epic ? 1.8 : 1.2
                    disc.stroke()

                    ctx.interpolationQuality = .none
                    icon.draw(in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))

                    if let badge = s.badge, effectiveChord >= 22 {
                        drawMiniBadge(badge, at: CGPoint(x: 0, y: discR + 7), color: s.rarity.badgeColor)
                    }
                }
            } else if let badge = s.badge {
                if effectiveChord < 14 {
                    drawRarityGem(s.rarity, at: .zero, angle: 0, size: 7, ctx: ctx)
                } else {
                    // If the title already includes the badge (e.g. "10 金币", "+2 积分"), render it once cleanly along the slice!
                    let cleanBadge = badge.trimmingCharacters(in: CharacterSet(charactersIn: "+"))
                    let redundant = !cleanBadge.isEmpty && s.title.contains(cleanBadge)
                    if redundant {
                        ctx.restoreGState()
                        radial(s.title, c: c, r: r, mid: mid, sector: sector, ink: mat.ink, isDark: s.rarity == .rare || s.rarity == .epic, rarity: s.rarity, ctx: ctx)
                        continue
                    }
                    // Keep text right-side-up on the bottom half of the wheel too!
                    if sin(mid) > 0.15 { ctx.rotate(by: .pi) }
                    let mainSize = max(12, min(22, effectiveChord * 0.42))
                    drawText(badge, at: CGPoint(x: 0, y: -5), size: mainSize, color: mat.ink, darkBg: s.rarity == .rare || s.rarity == .epic)
                    if effectiveChord >= 26 {
                        drawFitted(s.title, at: CGPoint(x: 0, y: mainSize * 0.66), size: max(9.5, mainSize * 0.56), maxWidth: effectiveChord * 0.92, color: mat.ink, darkBg: s.rarity == .rare || s.rarity == .epic)
                    }
                }
            }
            ctx.restoreGState()
        }

        // 6. Physical 3D machined brass pegs along the outer track at every sector boundary!
        let pegRingR = r * 0.955
        let pegR = max(2.8, min(4.6, r * 0.021))
        for i in slices.indices {
            guard spans[i].width > 0.001 else { continue }
            let a = -CGFloat.pi / 2 + spans[i].start
            let pt = CGPoint(x: c.x + cos(a) * pegRingR, y: c.y + sin(a) * pegRingR)
            // Tiny cast shadow
            UIColor.black.withAlphaComponent(0.38).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - pegR, y: pt.y - pegR + 1.2, width: pegR * 2, height: pegR * 2)).fill()
            // Dark bronze base
            UIColor(red: 0.42, green: 0.26, blue: 0.07, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - pegR, y: pt.y - pegR, width: pegR * 2, height: pegR * 2)).fill()
            // Warm gold cap
            UIColor(red: 0.96, green: 0.82, blue: 0.42, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - pegR * 0.78, y: pt.y - pegR * 0.78, width: pegR * 1.56, height: pegR * 1.56)).fill()
            // Specular highlight dot
            UIColor.white.withAlphaComponent(0.9).setFill()
            UIBezierPath(ovalIn: CGRect(x: pt.x - pegR * 0.48, y: pt.y - pegR * 0.52, width: pegR * 0.55, height: pegR * 0.55)).fill()
        }
    }

    private func drawRarityGem(_ rarity: MeadowItemRarity, at pt: CGPoint, angle: CGFloat, size: CGFloat, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: pt.x, y: pt.y)
        ctx.rotate(by: angle)
        let p = UIBezierPath()
        switch rarity {
        case .legendary:
            // 4-point radiant gold star
            for k in 0..<8 {
                let a = CGFloat(k) * .pi / 4 - .pi / 2
                let rad = k % 2 == 0 ? size : size * 0.38
                let v = CGPoint(x: cos(a) * rad, y: sin(a) * rad)
                if k == 0 { p.move(to: v) } else { p.addLine(to: v) }
            }
            p.close()
            UIColor(red: 1.0, green: 0.97, blue: 0.76, alpha: 1).setFill()
            UIColor(red: 0.62, green: 0.30, blue: 0.02, alpha: 1).setStroke()
        case .epic:
            // Faceted crystal hexagon
            p.move(to: CGPoint(x: 0, y: -size))
            p.addLine(to: CGPoint(x: size * 0.68, y: -size * 0.3))
            p.addLine(to: CGPoint(x: size * 0.68, y: size * 0.3))
            p.addLine(to: CGPoint(x: 0, y: size))
            p.addLine(to: CGPoint(x: -size * 0.68, y: size * 0.3))
            p.addLine(to: CGPoint(x: -size * 0.68, y: -size * 0.3))
            p.close()
            UIColor(red: 0.95, green: 0.82, blue: 1.0, alpha: 1).setFill()
            UIColor(red: 0.34, green: 0.10, blue: 0.62, alpha: 1).setStroke()
        case .rare, .common:
            // Sapphire diamond
            p.move(to: CGPoint(x: 0, y: -size * 0.9))
            p.addLine(to: CGPoint(x: size * 0.72, y: 0))
            p.addLine(to: CGPoint(x: 0, y: size * 0.9))
            p.addLine(to: CGPoint(x: -size * 0.72, y: 0))
            p.close()
            UIColor(red: 0.84, green: 0.95, blue: 1.0, alpha: 1).setFill()
            UIColor(red: 0.08, green: 0.28, blue: 0.64, alpha: 1).setStroke()
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
        color.setFill()
        UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).fill()
        attr.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
    }

    private func radial(_ s: String, c: CGPoint, r: CGFloat, mid: CGFloat, sector: CGFloat, ink: UIColor, isDark: Bool, rarity: MeadowItemRarity, ctx: CGContext) {
        let inner = r * 0.28, outer = r * 0.88, length = outer - inner
        let across = 2 * (inner + length * 0.22) * sin(min(sector, .pi) / 2) * 0.88
        if across < 10 {
            let pt = CGPoint(x: c.x + cos(mid) * (inner + length * 0.6), y: c.y + sin(mid) * (inner + length * 0.6))
            drawRarityGem(rarity, at: pt, angle: mid + .pi / 2, size: 6.5, ctx: ctx)
            return
        }
        let font = { (size: CGFloat) in MeadowPreviewPalette.font(size, .heavy) }
        func width(_ t: String, _ z: CGFloat) -> CGFloat { NSAttributedString(string: t, attributes: [.font: font(z)]).size().width }
        var size = min(20, max(9.5, across * 0.72)), lines = [s]
        while size > 9.5, width(s, size) > length * 0.90 { size -= 1 }
        if width(s, size) > length * 0.90 {
            if across >= 22 {
                let half = s.count / 2, a = String(s.prefix(half + s.count % 2)), b = String(s.suffix(half))
                var twoSize = min(16, across * 0.42)
                while twoSize > 9.5, max(width(a, twoSize), width(b, twoSize)) > length * 0.90 { twoSize -= 1 }
                size = twoSize
                lines = [truncate(a, font: font(size), maxWidth: length * 0.92), truncate(b, font: font(size), maxWidth: length * 0.92)]
            } else {
                lines = [truncate(s, font: font(size), maxWidth: length * 0.92)]
            }
        }
        ctx.saveGState()
        ctx.translateBy(x: c.x + cos(mid) * (inner + length * 0.50), y: c.y + sin(mid) * (inner + length * 0.50))
        ctx.rotate(by: cos(mid) < 0 ? mid + .pi : mid)
        let gap = size * 1.15
        for (k, line) in lines.enumerated() {
            drawText(line, at: CGPoint(x: 0, y: (CGFloat(k) - CGFloat(lines.count - 1) / 2) * gap), size: size, color: ink, darkBg: isDark)
        }
        ctx.restoreGState()
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
        shadow.shadowColor = darkBg ? UIColor.black.withAlphaComponent(0.55) : UIColor.white.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = darkBg ? 2.5 : 1.0
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        let a = NSAttributedString(string: s, attributes: [
            .font: MeadowPreviewPalette.font(size, .heavy),
            .foregroundColor: color,
            .shadow: shadow,
        ])
        let b = a.size()
        a.draw(at: CGPoint(x: p.x - b.width / 2, y: p.y - b.height / 2))
    }
}

// MARK: - Gilded Skeuomorphic Reveal Plaque

/// The prize that came up, popping in over the wheel as a gilded award plaque with rarity ribbon and icon pedestal.
final class WheelPrizeCard: UIView {
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
        backgroundColor = UIColor(red: 0.99, green: 0.97, blue: 0.92, alpha: 0.98)
        layer.shadowOpacity = 0.72
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 8)

        topRibbon.font = MeadowPreviewPalette.font(14, .heavy)
        topRibbon.textAlignment = .center
        topRibbon.textColor = .white
        topRibbon.layer.cornerRadius = 11
        topRibbon.layer.cornerCurve = .continuous
        topRibbon.clipsToBounds = true

        iconPedestal.layer.cornerRadius = 20
        iconPedestal.layer.cornerCurve = .continuous
        iconPedestal.layer.borderWidth = 1.5

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

        [topRibbon, iconPedestal, icon, title, subtitle, starsLabel].forEach(addSubview)
        alpha = 0
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let hasIcon = icon.image != nil
        let hasSub = !(subtitle.text?.isEmpty ?? true)
        topRibbon.frame = CGRect(x: (w - 138) / 2, y: 12, width: 138, height: 24)
        if hasIcon {
            let side = min(88, h * 0.36)
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
        starsLabel.frame = CGRect(x: 16, y: h - 30, width: w - 32, height: 22)
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
