import UIKit
import ClassroomGameCore

/// One slice of a prize wheel: what it shows and how rare it is (the rarer, the brighter the slice and the bigger the
/// celebration when it comes up).
struct WheelSlice {
    var title: String
    var icon: UIImage?
    /// Small text under the icon (×2, an amount); nil for none.
    var badge: String?
    var rarity: MeadowItemRarity
    /// Coins / score: drawn in amber.
    var coins: Bool = false
    /// How likely it is: the slice's share of the wheel (the odds are seen, not written).
    var weight: Double = 1

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

/// The wheel with its rim lights, pointer, hub and win effects. The face is drawn once; spinning, the chasing lights,
/// the pointer ticks and the bursts are Core Animation layers and particle emitters (the GPU does the frames).
final class MeadowPrizeWheelView: UIView {
    var slices: [WheelSlice] = [] { didSet { face.slices = slices; face.setNeedsDisplay(); clearWin() } }
    private(set) var spinning = false

    private let glow = CALayer()
    private let face = WheelFaceView()
    private let rim = CAShapeLayer()
    private let rimInner = CAShapeLayer()
    private var bulbs: [CALayer] = []
    private let pointer = CAShapeLayer()
    private let hub = CAGradientLayer()
    private let hubStar = CATextLayer()
    private let winWedge = CAShapeLayer()
    private let effects = CALayer()
    private var link: CADisplayLink?
    private var lastTickSlice = -1
    private var angle: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        glow.shadowOpacity = 0.55; glow.shadowRadius = 26; glow.shadowOffset = .zero
        glow.shadowColor = UIColor(red: 0.45, green: 0.55, blue: 1, alpha: 1).cgColor
        layer.addSublayer(glow)
        addSubview(face)
        rim.fillColor = UIColor.clear.cgColor
        rim.strokeColor = UIColor(red: 0.16, green: 0.19, blue: 0.42, alpha: 1).cgColor
        rimInner.fillColor = UIColor.clear.cgColor
        rimInner.strokeColor = UIColor.white.cgColor
        [rim, rimInner].forEach(layer.addSublayer)
        winWedge.fillColor = UIColor.white.withAlphaComponent(0.0).cgColor
        winWedge.strokeColor = UIColor.white.cgColor
        winWedge.opacity = 0
        face.layer.addSublayer(winWedge)
        hub.colors = [UIColor(red: 0.42, green: 0.48, blue: 0.98, alpha: 1).cgColor, UIColor(red: 0.16, green: 0.19, blue: 0.42, alpha: 1).cgColor]
        hub.type = .radial; hub.startPoint = CGPoint(x: 0.35, y: 0.3); hub.endPoint = CGPoint(x: 1, y: 1)
        hub.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor; hub.borderWidth = 3
        hub.shadowColor = UIColor.black.cgColor; hub.shadowOpacity = 0.35; hub.shadowRadius = 6; hub.shadowOffset = CGSize(width: 0, height: 3)
        hubStar.string = "★"; hubStar.alignmentMode = .center; hubStar.foregroundColor = UIColor.white.cgColor
        hubStar.contentsScale = UIScreen.main.scale
        hub.addSublayer(hubStar)
        layer.addSublayer(hub)
        pointer.fillColor = UIColor(red: 1, green: 0.30, blue: 0.40, alpha: 1).cgColor
        pointer.strokeColor = UIColor.white.cgColor; pointer.lineWidth = 3
        pointer.shadowColor = UIColor.black.cgColor; pointer.shadowOpacity = 0.45; pointer.shadowRadius = 5; pointer.shadowOffset = CGSize(width: 0, height: 3)
        layer.addSublayer(pointer)
        layer.addSublayer(effects)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var radius: CGFloat { min(bounds.width, bounds.height) / 2 - 18 }
    private var centre: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY + 8) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = radius, c = centre
        guard r > 20 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        face.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r); face.center = c
        face.transform = CGAffineTransform(rotationAngle: angle)
        glow.frame = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        glow.shadowPath = UIBezierPath(ovalIn: glow.bounds).cgPath
        rim.path = UIBezierPath(arcCenter: c, radius: r + 6, startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath; rim.lineWidth = 14
        rimInner.path = UIBezierPath(arcCenter: c, radius: r + 0.5, startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath; rimInner.lineWidth = 2
        // Rim lights.
        let count = 28
        if bulbs.count != count {
            bulbs.forEach { $0.removeFromSuperlayer() }
            bulbs = (0..<count).map { _ in
                let b = CALayer(); b.backgroundColor = UIColor.white.cgColor
                b.shadowColor = UIColor(red: 0.75, green: 0.85, blue: 1, alpha: 1).cgColor; b.shadowOpacity = 0.9; b.shadowRadius = 4; b.shadowOffset = .zero
                layer.insertSublayer(b, above: rim); return b
            }
        }
        for (i, b) in bulbs.enumerated() {
            let a = CGFloat(i) / CGFloat(count) * 2 * .pi
            b.bounds = CGRect(x: 0, y: 0, width: 7, height: 7); b.cornerRadius = 3.5
            b.position = CGPoint(x: c.x + cos(a) * (r + 6), y: c.y + sin(a) * (r + 6))
            b.opacity = i % 2 == 0 ? 1 : 0.35
        }
        let hr = max(22, r * 0.17)
        hub.frame = CGRect(x: c.x - hr, y: c.y - hr, width: 2 * hr, height: 2 * hr); hub.cornerRadius = hr
        hubStar.fontSize = hr * 0.95; hubStar.frame = CGRect(x: 0, y: hr * 0.42, width: 2 * hr, height: hr * 1.3)
        // Pointer: a gold drop pointing down onto the wheel, pivoting at its top.
        let pw: CGFloat = max(24, r * 0.13), ph = pw * 1.45, top = c.y - r - 20
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: ph)); p.addCurve(to: CGPoint(x: -pw / 2, y: pw * 0.42), controlPoint1: CGPoint(x: -pw * 0.18, y: ph * 0.72), controlPoint2: CGPoint(x: -pw / 2, y: pw * 0.8))
        p.addArc(withCenter: CGPoint(x: 0, y: pw * 0.42), radius: pw / 2, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addCurve(to: CGPoint(x: 0, y: ph), controlPoint1: CGPoint(x: pw / 2, y: pw * 0.8), controlPoint2: CGPoint(x: pw * 0.18, y: ph * 0.72))
        pointer.path = p.cgPath
        pointer.bounds = CGRect(x: -pw / 2, y: 0, width: pw, height: ph)
        pointer.anchorPoint = CGPoint(x: 0.5, y: 0.2)
        pointer.position = CGPoint(x: c.x, y: top + ph * 0.2)
        effects.frame = bounds
        CATransaction.commit()
    }

    // MARK: Spin

    /// Turns the wheel a few times and stops with slot `slot` under the pointer; `done` after it settles.
    func spin(to slot: Int, duration: Double = 4.4, done: @escaping () -> Void) {
        guard !spinning, !slices.isEmpty else { return }
        spinning = true; clearWin()
        let a = WheelSlice.angles(slices)[slot]
        let jitter = CGFloat.random(in: -0.34...0.34) * a.width
        let current = angle.truncatingRemainder(dividingBy: 2 * .pi)
        // The slice's middle is at start + width / 2 clockwise from the top: rotate it back to the top, plus turns.
        var target = -(a.start + a.width / 2) + jitter
        while target < current { target += 2 * .pi }
        target += 2 * .pi * 7
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = current; anim.toValue = target; anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.85, 0.12, 1)
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
    /// While spinning: the pointer flicks each time a slice edge passes under it.
    fileprivate func tick() {
        guard let rot = face.layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat, !slices.isEmpty else { return }
        var a = (-rot).truncatingRemainder(dividingBy: 2 * .pi); if a < 0 { a += 2 * .pi }
        let slice = WheelSlice.angles(slices).lastIndex { $0.start <= a } ?? 0
        if slice != lastTickSlice {
            lastTickSlice = slice
            let kick = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            kick.values = [0, -0.32, 0.06, 0]; kick.keyTimes = [0, 0.25, 0.7, 1]; kick.duration = 0.16
            pointer.add(kick, forKey: "tick")
        }
    }
    private func chaseLights() {
        for (i, b) in bulbs.enumerated() {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.2; a.duration = 0.32; a.autoreverses = true; a.repeatCount = .infinity
            a.beginTime = CACurrentMediaTime() + Double(i % 7) * 0.045
            b.add(a, forKey: "chase")
        }
    }
    private func blinkLights() {
        for b in bulbs {
            b.removeAnimation(forKey: "chase")
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.15; a.duration = 0.18; a.autoreverses = true; a.repeatCount = 4
            b.add(a, forKey: "blink")
        }
    }

    // MARK: Win

    private func clearWin() { winWedge.removeAllAnimations(); winWedge.opacity = 0; effects.sublayers?.forEach { $0.removeFromSuperlayer() } }

    /// Lights the winning slice and plays the celebration of its rarity (brighter for rarer prizes).
    func celebrate(_ slot: Int) {
        guard slices.indices.contains(slot) else { return }
        let rarity = slices[slot].rarity, r = radius, c = centre
        let span = WheelSlice.angles(slices)[slot]
        // The wedge in face coordinates (it turns with the face).
        let fc = CGPoint(x: r, y: r), start = -CGFloat.pi / 2 + span.start
        let wedge = UIBezierPath(); wedge.move(to: fc); wedge.addArc(withCenter: fc, radius: r - 1, startAngle: start, endAngle: start + span.width, clockwise: true); wedge.close()
        winWedge.path = wedge.cgPath; winWedge.lineWidth = 4
        winWedge.fillColor = rarity.color.withAlphaComponent(0.35).cgColor; winWedge.strokeColor = UIColor.white.cgColor
        winWedge.shadowColor = rarity.color.cgColor; winWedge.shadowOpacity = 1; winWedge.shadowRadius = 12; winWedge.shadowOffset = .zero
        let pulse = CABasicAnimation(keyPath: "opacity"); pulse.fromValue = 1; pulse.toValue = 0.45; pulse.duration = 0.5; pulse.autoreverses = true; pulse.repeatCount = .infinity
        winWedge.opacity = 1; winWedge.add(pulse, forKey: "pulse")
        glow.shadowColor = rarity.color.cgColor
        let top = CGPoint(x: c.x, y: c.y - r * 0.55)
        switch rarity {
        case .common:
            burst(at: top, color: UIColor(white: 1, alpha: 1), count: 30, speed: 140, image: Self.dot)
        case .rare:
            shockwave(at: c, radius: r * 1.25, color: rarity.color)
            burst(at: top, color: rarity.color, count: 70, speed: 220, image: Self.star)
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
            burst(at: c, color: UIColor(red: 1, green: 0.82, blue: 0.3, alpha: 1), count: 160, speed: 360, image: Self.star)
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
        // A short burst: stop emitting after a sixth of a second, let the sparks fly out.
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

    // Particle pictures, drawn once.
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

/// The wheel face, drawn once per set of slices: each slice shaded in its rarity's colour (light centre to deep rim),
/// its picture or words near the rim.
final class WheelFaceView: UIView {
    var slices: [WheelSlice] = []
    override init(frame: CGRect) { super.init(frame: frame); isOpaque = false; contentMode = .redraw }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// Bright candy colours, one per slice in turn (neighbours never share one); rarity shows as the rim band.
    private static let palette: [UIColor] = [
        UIColor(red: 1.00, green: 0.42, blue: 0.45, alpha: 1), UIColor(red: 1.00, green: 0.63, blue: 0.22, alpha: 1),
        UIColor(red: 0.98, green: 0.80, blue: 0.16, alpha: 1), UIColor(red: 0.20, green: 0.80, blue: 0.56, alpha: 1),
        UIColor(red: 0.20, green: 0.66, blue: 1.00, alpha: 1), UIColor(red: 0.50, green: 0.44, blue: 0.98, alpha: 1),
        UIColor(red: 0.96, green: 0.40, blue: 0.74, alpha: 1),
    ]
    private static func color(_ index: Int, count: Int) -> UIColor {
        var k = index % palette.count
        // The last slice next to the first: never the same colour.
        if index == count - 1, count > 1, k == 0 { k = (count - 2) % palette.count == 1 ? 2 : 1 }
        return palette[k]
    }
    private static func band(_ r: MeadowItemRarity) -> UIColor? {
        switch r {
        case .common: return nil
        case .rare: return UIColor(red: 0.25, green: 0.62, blue: 1, alpha: 1)
        case .epic: return UIColor(red: 0.66, green: 0.38, blue: 1, alpha: 1)
        case .legendary: return UIColor(red: 1, green: 0.78, blue: 0.18, alpha: 1)
        }
    }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), !slices.isEmpty else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) / 2
        let spans = WheelSlice.angles(slices)
        for (i, s) in slices.enumerated() {
            let sector = spans[i].width
            guard sector > 0.001 else { continue }
            let start = -CGFloat.pi / 2 + spans[i].start, end = start + sector
            let wedge = UIBezierPath(); wedge.move(to: c); wedge.addArc(withCenter: c, radius: r, startAngle: start, endAngle: end, clockwise: true); wedge.close()
            ctx.saveGState(); wedge.addClip()
            let base = Self.color(i, count: slices.count)
            let light = base.mixed(with: .white, 0.35)
            let g = CGGradient(colorsSpace: nil, colors: [light.cgColor, base.cgColor] as CFArray, locations: [0.2, 0.9])!
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            // Rarity: a glowing band along the rim (rare blue, epic purple, legendary gold).
            if let band = Self.band(s.rarity) {
                let ring = UIBezierPath(arcCenter: c, radius: r * 0.93, startAngle: start, endAngle: end, clockwise: true)
                ring.lineWidth = r * 0.1; band.setStroke(); ring.stroke()
                UIColor.white.withAlphaComponent(0.55).setStroke()
                let edge = UIBezierPath(arcCenter: c, radius: r * 0.875, startAngle: start, endAngle: end, clockwise: true); edge.lineWidth = 1.2; edge.stroke()
            }
            ctx.restoreGState()
            UIColor.white.setStroke(); wedge.lineWidth = 2; wedge.stroke()
            // Picture or words near the rim, upright along the slice; when they do not fit, a "-".
            let mid = start + sector / 2, chord = r * sector
            ctx.saveGState(); ctx.translateBy(x: c.x + cos(mid) * r * 0.68, y: c.y + sin(mid) * r * 0.68); ctx.rotate(by: mid + .pi / 2)
            let side = min(r * 0.3, chord * 0.62)
            if chord < 22 {
                text("-", at: .zero, size: max(10, min(16, chord * 0.8)), color: .white)
            } else if let icon = s.icon {
                icon.draw(in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
                if let badge = s.badge { fitted(badge, at: CGPoint(x: 0, y: side / 2 + side * 0.18), size: max(9, side * 0.3), width: chord * 0.85) }
            } else if let badge = s.badge {
                fitted(badge, at: CGPoint(x: 0, y: -side * 0.05), size: max(10, side * 0.42), width: chord * 0.85)
                fitted(s.title, at: CGPoint(x: 0, y: side * 0.42), size: max(8, side * 0.22), width: chord * 0.85)
            } else {
                // Words only (a prize outside the game): a few characters per line along the slice.
                wrapped(s.title, width: max(40, chord * 0.75), size: max(9, min(side * 0.3, 20)), room: r * 0.5)
            }
            ctx.restoreGState()
        }
        // Inner ring.
        UIColor.white.withAlphaComponent(0.7).setStroke()
        let inner = UIBezierPath(arcCenter: c, radius: r * 0.27, startAngle: 0, endAngle: 2 * .pi, clockwise: true); inner.lineWidth = 2.5; inner.stroke()
    }
    /// One line of words, or "-" when it is wider than the slice.
    private func fitted(_ s: String, at p: CGPoint, size: CGFloat, width: CGFloat) {
        let w = NSAttributedString(string: s, attributes: [.font: MeadowPreviewPalette.font(size, .heavy)]).size().width
        text(w <= width ? s : "-", at: p, size: size, color: .white)
    }
    private func text(_ s: String, at p: CGPoint, size: CGFloat, color: UIColor) {
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.35); shadow.shadowBlurRadius = 2; shadow.shadowOffset = CGSize(width: 0, height: 1)
        let a = NSAttributedString(string: s, attributes: [.font: MeadowPreviewPalette.font(size, .heavy), .foregroundColor: color, .shadow: shadow])
        let b = a.size(); a.draw(at: CGPoint(x: p.x - b.width / 2, y: p.y - b.height / 2))
    }
    private func wrapped(_ s: String, width: CGFloat, size: CGFloat, room: CGFloat) {
        let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byCharWrapping
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.4); shadow.shadowBlurRadius = 2; shadow.shadowOffset = CGSize(width: 0, height: 1)
        let a = NSAttributedString(string: s, attributes: [.font: MeadowPreviewPalette.font(size, .heavy), .foregroundColor: UIColor.white, .paragraphStyle: style, .shadow: shadow])
        let box = a.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        // More lines than the slice holds: a "-" rather than cut-off words.
        guard box.height <= min(size * 4.6, room) else { text("-", at: .zero, size: size * 1.4, color: .white); return }
        a.draw(with: CGRect(x: -width / 2, y: -box.height / 2, width: width, height: min(box.height, size * 4)), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
}

/// The prize that came up, popping in over the wheel in its rarity's colour.
final class WheelPrizeCard: UIView {
    private let icon = UIImageView()
    private let title = UILabel()
    private let rarityTag = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 22; layer.cornerCurve = .continuous; layer.borderWidth = 3
        backgroundColor = UIColor.white.withAlphaComponent(0.94)
        layer.shadowOpacity = 0.9; layer.shadowRadius = 22; layer.shadowOffset = .zero
        icon.contentMode = .scaleAspectFit
        title.font = MeadowPreviewPalette.font(26, .heavy); title.textAlignment = .center; title.numberOfLines = 2; title.adjustsFontSizeToFitWidth = true; title.minimumScaleFactor = 0.6
        title.textColor = MeadowPreviewPalette.ink
        rarityTag.font = MeadowPreviewPalette.font(15, .heavy); rarityTag.textAlignment = .center; rarityTag.textColor = .white; rarityTag.layer.cornerRadius = 11; rarityTag.clipsToBounds = true
        [icon, title, rarityTag].forEach(addSubview); alpha = 0; isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let hasIcon = icon.image != nil
        icon.frame = hasIcon ? CGRect(x: (w - h * 0.42) / 2, y: 14, width: h * 0.42, height: h * 0.42) : .zero
        title.frame = CGRect(x: 14, y: hasIcon ? icon.frame.maxY + 4 : h * 0.18, width: w - 28, height: hasIcon ? h * 0.24 : h * 0.42)
        rarityTag.frame = CGRect(x: (w - 96) / 2, y: h - 38, width: 96, height: 24)
    }
    func show(_ s: WheelSlice, prefix: String? = nil) {
        icon.image = s.icon; title.text = (prefix ?? "") + s.title + (s.icon != nil ? (s.badge.map { " " + $0 } ?? "") : "")
        rarityTag.text = s.coins ? "奖励" : s.rarity.title; rarityTag.backgroundColor = s.coins ? UIColor(red: 0.85, green: 0.58, blue: 0.16, alpha: 1) : s.rarity.color.withAlphaComponent(s.rarity == .common ? 0.0 : 1)
        if s.rarity == .common && !s.coins { rarityTag.backgroundColor = MeadowPreviewPalette.primary }
        layer.borderColor = (s.coins ? UIColor(red: 0.95, green: 0.72, blue: 0.25, alpha: 1) : s.rarity.color).cgColor
        layer.shadowColor = layer.borderColor
        setNeedsLayout()
        transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        UIView.animate(withDuration: 0.55, delay: 0.1, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.9, options: []) { self.alpha = 1; self.transform = .identity }
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
