import UIKit

/// Draws the primitives of `MeadowSkillProcedural` with CoreGraphics: soft glows, rings, arcs, smooth ribbons.
/// Light is additive (`plusLighter`); solid ribbons use normal blending. Edges are feathered by drawing each shape twice
/// (a wide faint pass and the main pass), which stands in for the bloom of the offline preview.
enum MeadowSkillProceduralPainter {
    private static var glowCache: [Int: UIImage] = [:]

    /// White-tinted radial falloff `(1 - d)^1.4`, coloured on demand and cached per colour.
    private static func glow(_ c: MeadowSkillProcedural.RGB) -> UIImage {
        let key = Int(c.r.rounded()) << 16 | Int(c.g.rounded()) << 8 | Int(c.b.rounded())
        if let found = glowCache[key] { return found }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { context in
            let steps = 12
            var colors: [CGColor] = [], locations: [CGFloat] = []
            for i in 0...steps {
                let d = Double(i) / Double(steps)
                colors.append(UIColor(red: CGFloat(c.r / 255), green: CGFloat(c.g / 255), blue: CGFloat(c.b / 255), alpha: CGFloat(pow(max(0, 1 - d), 1.4))).cgColor)
                locations.append(CGFloat(d))
            }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 48, y: 48), startRadius: 0, endCenter: CGPoint(x: 48, y: 48), endRadius: 48, options: [])
        }
        glowCache[key] = image
        return image
    }

    private static func color(_ c: MeadowSkillProcedural.RGB, _ a: Double) -> CGColor {
        UIColor(red: CGFloat(c.r / 255), green: CGFloat(c.g / 255), blue: CGFloat(c.b / 255), alpha: CGFloat(min(1, max(0, a)))).cgColor
    }

    /// Draws a list of primitives into `ctx` (stage coordinates). `bounds` is the area a flash fills, unless a `flash` sink is given:
    /// then the full-screen flash is reported to the sink (the stage turns it into a pane-wide overlay, so it has no edge at the world rectangle).
    static func draw(_ prims: [MeadowSkillProcedural.Prim], in ctx: CGContext, bounds: CGRect, flash: ((MeadowSkillProcedural.RGB, Double) -> Void)? = nil) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for prim in prims {
            switch prim {
            case let .glow(x, y, rx, ry, c, a):
                guard a > 0.004, rx > 0.3, ry > 0.3 else { continue }
                ctx.saveGState(); ctx.setBlendMode(.plusLighter); ctx.setAlpha(CGFloat(min(1, a)))
                if let cg = glow(c).cgImage { ctx.draw(cg, in: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)) }
                ctx.restoreGState()
            case let .streak(x, y, rx, ry, ang, c, a):
                guard a > 0.004, rx > 0.3, ry > 0.3 else { continue }
                ctx.saveGState(); ctx.setBlendMode(.plusLighter); ctx.setAlpha(CGFloat(min(1, a)))
                ctx.translateBy(x: x, y: y); ctx.rotate(by: CGFloat(ang))
                if let cg = glow(c).cgImage { ctx.draw(cg, in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)) }
                ctx.restoreGState()
            case let .ring(x, y, rx, ry, w, c, a, rot):
                guard a > 0.004, rx > 0.5, ry > 0.5 else { continue }
                ctx.saveGState(); ctx.setBlendMode(.plusLighter)
                ctx.translateBy(x: x, y: y); if rot != 0 { ctx.rotate(by: CGFloat(rot)) }
                let rect = CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)
                ctx.setStrokeColor(color(c, a * 0.28)); ctx.setLineWidth(CGFloat(max(1.0, w * 2.6))); ctx.strokeEllipse(in: rect)
                ctx.setStrokeColor(color(c, a)); ctx.setLineWidth(CGFloat(max(0.6, w))); ctx.strokeEllipse(in: rect)
                ctx.restoreGState()
            case let .arc(x, y, rx, ry, a0, a1, w, c, a):
                guard a > 0.004, rx > 0.5, ry > 0.5, a1 > a0 else { continue }
                let steps = max(6, Int((a1 - a0) / 0.08))
                let path = CGMutablePath()
                for i in 0...steps {
                    let ang = a0 + (a1 - a0) * Double(i) / Double(steps)
                    let p = CGPoint(x: x + cos(ang) * rx, y: y + sin(ang) * ry)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                ctx.saveGState(); ctx.setBlendMode(.plusLighter)
                ctx.addPath(path); ctx.setStrokeColor(color(c, a * 0.28)); ctx.setLineWidth(CGFloat(max(1.0, w * 2.6))); ctx.strokePath()
                ctx.addPath(path); ctx.setStrokeColor(color(c, a)); ctx.setLineWidth(CGFloat(max(0.6, w))); ctx.strokePath()
                ctx.restoreGState()
            case let .ribbon(pts, ws, c, a, add, soft):
                guard a > 0.004, pts.count >= 2, pts.count == ws.count else { continue }
                ctx.saveGState(); ctx.setBlendMode(add ? .plusLighter : .normal)
                if soft > 1.4 { ctx.addPath(ribbonPath(pts, ws, grow: soft * 0.9)); ctx.setFillColor(color(c, a * 0.32)); ctx.fillPath() }
                ctx.addPath(ribbonPath(pts, ws, grow: 0)); ctx.setFillColor(color(c, a)); ctx.fillPath()
                ctx.restoreGState()
            case let .flash(c, a):
                guard a > 0.004 else { continue }
                if let flash { flash(c, a); continue }
                ctx.saveGState(); ctx.setBlendMode(.plusLighter); ctx.setFillColor(color(c, a)); ctx.fill(bounds); ctx.restoreGState()
            }
        }
    }

    /// A smooth variable-width strip along a polyline: the outline is the polyline offset left and right by half the width.
    private static func ribbonPath(_ pts: [MeadowSkillProcedural.Pt], _ ws: [Double], grow: Double) -> CGPath {
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0..<pts.count {
            let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)]
            var dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            if len < 1e-9 { dx = 1; dy = 0 } else { dx /= len; dy /= len }
            let half = max(0.25, ws[i] / 2 + grow)
            left.append(CGPoint(x: pts[i].x - dy * half, y: pts[i].y + dx * half))
            right.append(CGPoint(x: pts[i].x + dy * half, y: pts[i].y - dx * half))
        }
        let path = CGMutablePath()
        path.move(to: left[0])
        for p in left.dropFirst() { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    /// Stage-wide light that answers a skill: a tinted dim, a broad glow on the target and a pool of light on the floor.
    /// `fillBounds` false leaves the flat dim/wash to the stage (a pane-wide overlay), so the grade has no edge at the world rectangle.
    static func drawAmbient(skill id: String, t: Double, in ctx: CGContext, bounds: CGRect, target: CGPoint, floorY: CGFloat, rx: Double, fillBounds: Bool = true) {
        guard let info = MeadowSkillProcedural.info[id] else { return }
        let lit = MeadowSkillProcedural.light(skill: id, t: t)
        guard lit > 0.01 else { return }
        let tone = MeadowSkillProcedural.tone(id)
        ctx.saveGState()
        if fillBounds {
            // The stage view already dims during a cast; this adds a tinted share so the skill's own colour grades the scene.
            ctx.setFillColor(UIColor(red: CGFloat(info.dimTint.r) * 0.1, green: CGFloat(info.dimTint.g) * 0.1, blue: CGFloat(info.dimTint.b) * 0.12, alpha: CGFloat(lit * info.dim * 0.55)).cgColor)
            ctx.fill(bounds)
            ctx.setBlendMode(.plusLighter)
            ctx.setFillColor(color(tone, lit * 0.018)); ctx.fill(bounds)
        }
        ctx.setBlendMode(.plusLighter)
        if let cg = glow(tone).cgImage {
            ctx.setAlpha(CGFloat(lit * 0.16)); ctx.draw(cg, in: CGRect(x: target.x - CGFloat(rx) * 1.5, y: target.y - CGFloat(rx) * 1.2, width: CGFloat(rx) * 3, height: CGFloat(rx) * 2.4))
            ctx.setAlpha(CGFloat(lit * 0.3)); ctx.draw(cg, in: CGRect(x: target.x - CGFloat(rx) * 0.9, y: floorY - 22, width: CGFloat(rx) * 1.8, height: 44))
        }
        ctx.restoreGState()
    }
}
