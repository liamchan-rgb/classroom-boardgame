import UIKit

/// The mark under a picked target on the battle stage: a disc of light lying on the ground with a bright rim, four bracket arcs turning
/// around it and a ripple spreading outwards. It sits *under* the characters (the old ring was drawn over their feet), is sized to the
/// unit, and is drawn as a circle squashed to the ground's perspective - so the turning brackets read as a ring lying flat.
final class MeadowTargetMarkerView: UIView {
    private let glow = CAGradientLayer(), rim = CAShapeLayer(), brackets = CAShapeLayer(), ripple = CAShapeLayer()
    private var radius: CGFloat = 0
    private var tint = UIColor.clear

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; isHidden = true
        glow.type = .radial; glow.startPoint = CGPoint(x: 0.5, y: 0.5); glow.endPoint = CGPoint(x: 1, y: 1)
        for shape in [ripple, rim, brackets] { shape.fillColor = nil; shape.lineCap = .round }
        [glow, ripple, rim, brackets].forEach(layer.addSublayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Puts the mark at `foot` (world units) for a unit about `radius` wide; `color` says whose side it is.
    func show(at foot: CGPoint, radius r: CGFloat, color: UIColor) {
        if r != radius || color != tint {
            radius = r; tint = color
            let side = r * 2.5, box = CGRect(x: 0, y: 0, width: side, height: side), mid = CGPoint(x: side / 2, y: side / 2)
            transform = .identity; bounds = box
            func circle(_ k: CGFloat) -> CGPath { UIBezierPath(arcCenter: mid, radius: r * k, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath }
            for l in [glow, rim, brackets, ripple] as [CALayer] { l.frame = box }
            glow.colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0.22).cgColor, color.withAlphaComponent(0).cgColor]
            glow.locations = [0, 0.55, 0.82]
            rim.path = circle(1); rim.strokeColor = UIColor.white.withAlphaComponent(0.92).cgColor; rim.lineWidth = 5
            rim.shadowColor = color.cgColor; rim.shadowRadius = 9; rim.shadowOpacity = 1; rim.shadowOffset = .zero
            // Four bracket arcs just outside the rim.
            let arc = UIBezierPath()
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2
                arc.move(to: CGPoint(x: mid.x + cos(a - 0.42) * r * 1.17, y: mid.y + sin(a - 0.42) * r * 1.17))
                arc.addArc(withCenter: mid, radius: r * 1.17, startAngle: a - 0.42, endAngle: a + 0.42, clockwise: true)
            }
            brackets.path = arc.cgPath; brackets.strokeColor = color.cgColor; brackets.lineWidth = 9
            ripple.path = circle(1); ripple.strokeColor = color.cgColor; ripple.lineWidth = 4
            // Lying on the ground: the vertical axis is squashed.
            transform = CGAffineTransform(scaleX: 1, y: 0.3)
            animate()
        }
        center = foot
        if isHidden { isHidden = false; animate(); alpha = 0; UIView.animate(withDuration: 0.18) { self.alpha = 1 } }
    }
    func hide() { if !isHidden { isHidden = true } }

    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { animate() } }

    private func animate() {
        guard radius > 0 else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z"); spin.fromValue = 0; spin.toValue = CGFloat.pi * 2; spin.duration = 5; spin.repeatCount = .infinity
        brackets.add(spin, forKey: "spin")
        let grow = CABasicAnimation(keyPath: "transform.scale"); grow.fromValue = 1; grow.toValue = 1.22
        let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0.9; fade.toValue = 0
        let wave = CAAnimationGroup(); wave.animations = [grow, fade]; wave.duration = 1.3; wave.repeatCount = .infinity; wave.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.add(wave, forKey: "ripple")
        let breathe = CABasicAnimation(keyPath: "opacity"); breathe.fromValue = 1; breathe.toValue = 0.6; breathe.duration = 0.8; breathe.autoreverses = true; breathe.repeatCount = .infinity
        glow.add(breathe, forKey: "breathe")
    }
}
