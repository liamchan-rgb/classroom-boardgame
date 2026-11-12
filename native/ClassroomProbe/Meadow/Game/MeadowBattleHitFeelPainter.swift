import UIKit

/// Draws the impact graphics of `MeadowBattleHitFeel` with CoreGraphics. Shared by the single-hero landscape
/// view and the party stage; each passes its own `unit` so the effect keeps its proportion to the character art.
enum MeadowBattleHitFeelPainter {
    /// Layout units that match one landscape canvas unit (canvas width / 760) to the party stage world, where the
    /// hero scale is 0.83 per art pixel against about 0.898 in the 760-wide landscape layout.
    static let partyStageUnit: CGFloat = 0.83 / 0.898

    /// - Parameters:
    ///   - impact: contact point on the struck monster.
    ///   - floorY / footX: ground contact under the monster, for dust.
    ///   - unit: drawing units per layout unit.
    static func draw(in ctx: CGContext, age: Double, tier: MeadowBattleHitTier, direction: Double,
                     impact: CGPoint, floorY: CGFloat, footX: CGFloat, unit: CGFloat, leaves: Bool = true) {
        guard age >= 0 else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        // Soft ground puffs and foliage use normal blending.
        let puffs = MeadowBattleHitFeel.dust(age: age, tier: tier)
        if !puffs.isEmpty {
            ctx.setBlendMode(.normal)
            for puff in puffs {
                let cx = footX + CGFloat(puff.dx) * unit + 10 * unit
                let rx = CGFloat(puff.rx) * unit, ry = CGFloat(puff.ry) * unit
                ctx.setFillColor(UIColor(red: 190 / 255, green: 175 / 255, blue: 140 / 255, alpha: CGFloat(puff.alpha)).cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - rx, y: floorY - ry, width: rx * 2, height: ry * 2))
            }
        }
        if leaves {
            let tones: [UIColor] = [UIColor(red: 86 / 255, green: 142 / 255, blue: 62 / 255, alpha: 1),
                                    UIColor(red: 128 / 255, green: 176 / 255, blue: 74 / 255, alpha: 1),
                                    UIColor(red: 60 / 255, green: 112 / 255, blue: 52 / 255, alpha: 1)]
            for leaf in MeadowBattleHitFeel.leaves(age: age, tier: tier, direction: direction) {
                let cx = impact.x + CGFloat(leaf.x) * unit, cy = impact.y + CGFloat(leaf.y) * unit
                let size = CGFloat(leaf.size) * unit
                let ca = CGFloat(cos(leaf.rotation)), sa = CGFloat(sin(leaf.rotation))
                let path = CGMutablePath()
                path.move(to: CGPoint(x: cx + ca * size, y: cy + sa * size))
                path.addLine(to: CGPoint(x: cx - sa * size * 0.45, y: cy + ca * size * 0.45))
                path.addLine(to: CGPoint(x: cx - ca * size, y: cy - sa * size))
                path.addLine(to: CGPoint(x: cx + sa * size * 0.45, y: cy - ca * size * 0.45))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(tones[leaf.tone % 3].withAlphaComponent(CGFloat(leaf.alpha * 235 / 255)).cgColor)
                ctx.fillPath()
            }
        }

        // Light: additive.
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        if let ring = MeadowBattleHitFeel.ring(age: age, tier: tier) {
            let r = CGFloat(ring.radius) * unit
            ctx.setStrokeColor(UIColor(red: 1, green: 0.88, blue: 0.59, alpha: CGFloat(ring.alpha)).cgColor)
            ctx.setLineWidth(max(0.5, CGFloat(ring.width) * unit))
            ctx.strokeEllipse(in: CGRect(x: impact.x - r, y: impact.y - r * 0.82, width: r * 2, height: r * 1.64))
        }
        for spark in MeadowBattleHitFeel.sparks(age: age, tier: tier, direction: direction) {
            let heat = CGFloat(spark.heat)
            ctx.setStrokeColor(UIColor(red: 1, green: (255 - 90 * heat) / 255, blue: (215 - 175 * heat) / 255, alpha: CGFloat(spark.alpha)).cgColor)
            ctx.setLineWidth(max(0.5, CGFloat(spark.width) * unit))
            ctx.move(to: CGPoint(x: impact.x + CGFloat(spark.tailX) * unit, y: impact.y + CGFloat(spark.tailY) * unit))
            ctx.addLine(to: CGPoint(x: impact.x + CGFloat(spark.headX) * unit, y: impact.y + CGFloat(spark.headY) * unit))
            ctx.strokePath()
        }
        if let flare = MeadowBattleHitFeel.flare(age: age, tier: tier) {
            let R = CGFloat(flare.radius) * unit
            ctx.setFillColor(UIColor(red: 1, green: 235 / 255, blue: 170 / 255, alpha: CGFloat(flare.alpha)).cgColor)
            for (length, thick, angle) in [(R * 2.2, R * 0.16, -0.30), (R * 1.25, R * 0.13, 1.2), (R * 1.0, R * 0.10, -1.45)] {
                let ca = CGFloat(cos(angle)), sa = CGFloat(sin(angle))
                let path = CGMutablePath()
                path.move(to: CGPoint(x: impact.x + ca * length, y: impact.y + sa * length))
                path.addLine(to: CGPoint(x: impact.x - sa * thick, y: impact.y + ca * thick))
                path.addLine(to: CGPoint(x: impact.x - ca * length, y: impact.y - sa * length))
                path.addLine(to: CGPoint(x: impact.x + sa * thick, y: impact.y - ca * thick))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.fillPath()
            }
            ctx.setFillColor(UIColor(white: 1, alpha: CGFloat(flare.alpha)).cgColor)
            let core = R * 0.30
            ctx.fillEllipse(in: CGRect(x: impact.x - core, y: impact.y - core, width: core * 2, height: core * 2))
        }
    }

    /// Damage number with a pop, an eased rise and a late fade. Drawn with normal blending, centred on `impact`.
    static func drawNumber(in ctx: CGContext, text: String, age: Double, tier: MeadowBattleHitTier, impact: CGPoint, unit: CGFloat) {
        guard let pop = MeadowBattleHitFeel.number(age: age, tier: tier) else { return }
        let color: UIColor = tier == .heavy ? UIColor(red: 1, green: 0.886, blue: 0.51, alpha: 1) : .white
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: CGFloat(pop.fontSize) * unit, weight: .heavy),
            .foregroundColor: color.withAlphaComponent(CGFloat(pop.alpha)),
            .strokeColor: UIColor(red: 0.15, green: 0.10, blue: 0.04, alpha: CGFloat(pop.alpha)),
            .strokeWidth: -3
        ]
        let label = NSAttributedString(string: text, attributes: attrs)
        let size = label.size()
        ctx.saveGState()
        ctx.setBlendMode(.normal)
        ctx.translateBy(x: impact.x, y: impact.y + CGFloat(pop.yOffset) * unit - 6 * unit)
        ctx.scaleBy(x: CGFloat(pop.scale), y: CGFloat(pop.scale))
        label.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        ctx.restoreGState()
    }
}

/// One shared set of impact generators; prepared when a blow starts so the tap lands on the contact frame.
enum MeadowBattleHaptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

    /// Phone vibration is off: the lens shake is the feedback.
    static let enabled = false
    static func prepare() { guard enabled else { return }; light.prepare(); medium.prepare(); heavy.prepare(); rigid.prepare() }

    static func hit(_ tier: MeadowBattleHitTier, killed: Bool = false) {
        guard enabled else { return }
        let h = MeadowBattleHitFeel.haptic(tier: tier)
        switch h.style {
        case .light: light.impactOccurred(intensity: CGFloat(h.intensity))
        case .medium: medium.impactOccurred(intensity: CGFloat(h.intensity))
        case .heavy: heavy.impactOccurred(intensity: CGFloat(h.intensity))
        }
        if killed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { rigid.impactOccurred(intensity: 0.9) }
        }
    }

    /// A blocked blow: a short, soft tap.
    static func blocked() { guard enabled else { return }; light.impactOccurred(intensity: 0.5) }
    /// The natural 20: three heavy taps and a success buzz.
    static func naturalTwenty() {
        guard enabled else { return }
        heavy.prepare(); rigid.prepare()
        heavy.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { rigid.impactOccurred(intensity: 1.0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { heavy.impactOccurred(intensity: 0.8) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }
}
