import Foundation

/// Continuous procedural skill effects: a literal port of `scripts/battle-vfx/procfx.py` (the reference and the art spec).
/// Every effect is a closed-form function of time returning drawing primitives (soft glows, elongated glows, rings, arcs,
/// smooth tapered ribbons, flashes), so motion is continuous at any frame rate. Pure Foundation; `scripts/battle-procedural-regression.swift`
/// compares this port with golden samples exported from the Python reference.
///
/// Coordinates are stage points (y grows downward). `t` is seconds since the effect's own start.
enum MeadowSkillProcedural {
    struct RGB: Equatable { let r: Double, g: Double, b: Double; init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b } }
    struct Pt: Equatable { var x: Double, y: Double; init(_ x: Double, _ y: Double) { self.x = x; self.y = y } }
    struct Target: Equatable { var chest: Pt, foot: Pt }
    struct Geometry: Equatable { var caster: Pt, casterFoot: Pt, targets: [Target], ground: Double; var power = 1.0
        /// For the standing shield shell: seconds since it last blocked a blow (negative: none), where on the shell that blow landed, and the body-width factor.
        var hitAge = -1.0, hitAngle = 0.0, wide = 1.0 }

    enum Prim: Equatable {
        case glow(x: Double, y: Double, rx: Double, ry: Double, c: RGB, a: Double)
        case ring(x: Double, y: Double, rx: Double, ry: Double, w: Double, c: RGB, a: Double, rot: Double)
        case streak(x: Double, y: Double, rx: Double, ry: Double, ang: Double, c: RGB, a: Double)
        case arc(x: Double, y: Double, rx: Double, ry: Double, a0: Double, a1: Double, w: Double, c: RGB, a: Double)
        case ribbon(pts: [Pt], ws: [Double], c: RGB, a: Double, add: Bool, soft: Double)
        case flash(c: RGB, a: Double)
    }

    // MARK: skill table

    struct Info { let duration: Double, release: Double, dim: Double, dimTint: RGB, support: Bool }
    static let skillIDs = ["starlightPulse", "dragonSoulWard", "dragonScaleWard", "runeSlash", "runeWard", "battleRune", "dragonFlame", "dragonOrder",
                           "healMicro", "healStandard", "healStrong", "rally", "sweep",
                           "shieldShell", "shieldShellHit", "shieldBreak", "deathBurst",
                           "hitSlime", "hitWolf", "hitArrowM", "hitStone", "hitTroll", "hitDragon",
                           "deathSlime", "deathWolf", "deathGoblin", "deathStone", "deathTroll", "deathDragon", "playerDown", "downAura", "revive", "buffAura", "projBow", "projStaff", "projArcher", "projDragon",
                           "natural20", "shieldDome", "hitBlade", "hitGreat", "hitBow", "hitStaff", "hitClaw", "hitAmbush", "hitWard"]
    static let info: [String: Info] = [
        "starlightPulse": Info(duration: 1.6, release: 0.75, dim: 0.34, dimTint: RGB(0.80, 0.76, 1.0), support: false),
        "dragonSoulWard": Info(duration: 2.0, release: 0.38, dim: 0.32, dimTint: RGB(0.74, 0.88, 1.0), support: true),
        "dragonScaleWard": Info(duration: 2.2, release: 0.56, dim: 0.28, dimTint: RGB(1.0, 0.88, 0.7), support: true),
        "runeSlash": Info(duration: 2.4, release: 1.048, dim: 0.30, dimTint: RGB(0.8, 0.92, 1.0), support: false),
        "runeWard": Info(duration: 2.4, release: 0.72, dim: 0.28, dimTint: RGB(0.8, 0.92, 1.0), support: true),
        "battleRune": Info(duration: 2.1, release: 0.56, dim: 0.28, dimTint: RGB(1.0, 0.88, 0.72), support: true),
        "dragonFlame": Info(duration: 2.2, release: 0.46, dim: 0.34, dimTint: RGB(1.0, 0.78, 0.62), support: false),
        "dragonOrder": Info(duration: 2.1, release: 0.56, dim: 0.32, dimTint: RGB(1.0, 0.78, 0.72), support: true),
        "healMicro": Info(duration: 1.35, release: 0.1, dim: 0.26, dimTint: RGB(0.82, 0.96, 0.86), support: true),
        "healStandard": Info(duration: 1.8, release: 0.1, dim: 0.28, dimTint: RGB(0.8, 0.96, 0.85), support: true),
        "healStrong": Info(duration: 2.3, release: 0.1, dim: 0.32, dimTint: RGB(0.78, 0.95, 0.84), support: true),
        "rally": Info(duration: 2.0, release: 0.56, dim: 0.24, dimTint: RGB(1.0, 0.94, 0.8), support: true),
        "sweep": Info(duration: 2.0, release: 1.048, dim: 0.26, dimTint: RGB(0.82, 0.9, 1.0), support: false),
        "natural20": Info(duration: 2.8, release: 0.05, dim: 0.5, dimTint: RGB(1.0, 0.92, 0.7), support: false),
        "shieldDome": Info(duration: 1.9, release: 0.46, dim: 0.26, dimTint: RGB(0.8, 0.92, 1.0), support: true),
        "shieldShell": Info(duration: 3.0, release: 0.5, dim: 0.0, dimTint: RGB(1, 1, 1), support: true),
        "shieldShellHit": Info(duration: 3.0, release: 0.5, dim: 0.0, dimTint: RGB(1, 1, 1), support: true),
        "shieldBreak": Info(duration: 1.2, release: 0.03, dim: 0.0, dimTint: RGB(1, 1, 1), support: false),
        "deathSlime": deathInfo(1.8), "deathWolf": deathInfo(1.8), "deathGoblin": deathInfo(1.8), "deathStone": deathInfo(2.0), "deathTroll": deathInfo(1.8), "deathDragon": deathInfo(2.4),
        "playerDown": Info(duration: 2.2, release: 0.05, dim: 0.0, dimTint: RGB(1, 1, 1), support: false),
        "buffAura": Info(duration: 3.0, release: 0.3, dim: 0.0, dimTint: RGB(1, 1, 1), support: true),
        "revive": Info(duration: 1.8, release: 0.3, dim: 0.0, dimTint: RGB(1, 1, 1), support: true),
        "downAura": Info(duration: 3.0, release: 0.5, dim: 0.0, dimTint: RGB(1, 1, 1), support: true),
        "hitSlime": hitInfo, "hitWolf": hitInfo, "hitArrowM": hitInfo, "hitStone": hitInfo, "hitTroll": hitInfo, "hitDragon": hitInfo,
        "deathBurst": Info(duration: 1.8, release: 0.04, dim: 0.0, dimTint: RGB(1, 1, 1), support: false),
        "projBow": projInfo(0.0, 0.19), "projStaff": projInfo(0.49, 0.21), "projArcher": projInfo(0.0, 0.22), "projDragon": projInfo(0.0, 0.22),
        "hitBlade": hitInfo, "hitGreat": hitInfo, "hitBow": hitInfo, "hitStaff": hitInfo, "hitClaw": hitInfo, "hitAmbush": hitInfo, "hitWard": hitInfo
    ]
    private static func projInfo(_ charge: Double, _ flight: Double) -> Info { Info(duration: charge + flight + 0.35, release: charge + flight, dim: 0.0, dimTint: RGB(1, 1, 1), support: false) }
    /// Effects that belong to a single blow or flight: no dim, no wash, no soft ambient light, no lens work of their own.
    static func isBlow(_ id: String) -> Bool { id.hasPrefix("hit") || id.hasPrefix("proj") || id.hasPrefix("shieldShell") || id.hasPrefix("death") || id == "downAura" || id == "buffAura" || id == "shieldBreak" }
    private static func deathInfo(_ d: Double) -> Info { Info(duration: d, release: 0.04, dim: 0.0, dimTint: RGB(1, 1, 1), support: false) }
    private static let hitInfo = Info(duration: 1.1, release: 0.05, dim: 0.0, dimTint: RGB(1, 1, 1), support: false)
    /// The procedural skill that draws a party action, if any (the two shield actions and the ally support share the shield dome).
    static func procID(for action: String) -> String? {
        if info[action] != nil && !action.hasPrefix("hit") && action != "natural20" && action != "shieldDome" { return action }
        switch action { case "simpleGuard", "shieldPotion", "support": return "shieldDome"; default: return nil }
    }
    /// Dominant colour of each skill (for the ambient light, floor pool and motes).
    static func tone(_ id: String) -> RGB {
        switch id {
        case "starlightPulse": return RGB(160, 136, 255)
        case "dragonSoulWard": return RGB(56, 140, 255)
        case "dragonScaleWard": return Pal.scale.mid
        case "runeSlash", "runeWard": return Pal.rune.mid
        case "battleRune": return Pal.battle.mid
        case "dragonFlame": return Pal.flame.mid
        case "dragonOrder": return Pal.order.mid
        case "rally": return Pal.rally.mid
        case "sweep": return Pal.sweep.mid
        case "natural20": return Pal.gold.mid
        case "shieldDome", "hitWard": return Pal.ward.mid
        case "deathBurst": return Pal.dust.mid
        case "deathSlime": return Pal.goo.mid
        case "deathWolf": return Pal.wolf.mid
        case "deathGoblin": return Pal.goblin.mid
        case "deathStone": return Pal.stone.mid
        case "deathTroll": return Pal.troll.mid
        case "deathDragon": return Pal.ward.mid
        case "playerDown": return Pal.down.mid
        case "downAura", "revive": return Pal.gold.mid
        case "buffAura": return Pal.fury.mid
        case "hitSlime": return Pal.goo.mid
        case "hitWolf": return Pal.wolf.mid
        case "hitArrowM": return Pal.goblin.mid
        case "hitStone": return Pal.stone.mid
        case "hitTroll": return Pal.troll.mid
        case "hitDragon": return Pal.ward.mid
        case "shieldBreak", "shieldShell", "shieldShellHit": return Pal.ward.mid
        case "projBow": return Pal.bow.mid
        case "projStaff": return Pal.staff.mid
        case "projArcher": return Pal.claw.mid
        case "projDragon": return Pal.ward.mid
        case "hitBlade": return Pal.blade.mid
        case "hitGreat": return Pal.great.mid
        case "hitBow": return Pal.bow.mid
        case "hitStaff": return Pal.staff.mid
        case "hitClaw": return Pal.claw.mid
        case "hitAmbush": return Pal.ambush.mid
        default: return Pal.heal.mid
        }
    }

    // MARK: maths

    static func clamp01(_ x: Double) -> Double { min(1.0, max(0.0, x)) }
    static func smooth(_ x: Double) -> Double { let t = clamp01(x); return t * t * (3 - 2 * t) }
    static func easeOut(_ x: Double) -> Double { let t = clamp01(x); return 1 - pow(1 - t, 3) }
    static func easeIn(_ x: Double) -> Double { let t = clamp01(x); return t * t }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    static func frac(_ i: Int, _ salt: Int) -> Double { Double((i * 73 + salt * 37 + (i * i) * 11) % 101) / 100.0 }
    /// Python-style modulo for floats (the result has the sign of the divisor).
    static func pm(_ a: Double, _ b: Double) -> Double { a - (a / b).rounded(.down) * b }
    static func b2d(_ v: Bool) -> Double { v ? 1.0 : 0.0 }
    static func pw(_ x: Double, _ y: Double) -> Double { pow(max(0, x), y) }

    // MARK: palettes

    struct Pal { let deep: RGB, body: RGB, mid: RGB, light: RGB, a1: RGB, a2: RGB
        static let rune = Pal(deep: RGB(14, 40, 92), body: RGB(40, 150, 235), mid: RGB(90, 215, 255), light: RGB(205, 248, 255), a1: RGB(255, 214, 120), a2: RGB(150, 110, 255))
        static let battle = Pal(deep: RGB(110, 40, 10), body: RGB(230, 120, 30), mid: RGB(255, 180, 60), light: RGB(255, 236, 170), a1: RGB(255, 90, 60), a2: RGB(255, 230, 160))
        static let flame = Pal(deep: RGB(120, 20, 8), body: RGB(235, 70, 20), mid: RGB(255, 150, 40), light: RGB(255, 225, 140), a1: RGB(255, 250, 220), a2: RGB(255, 90, 40))
        static let scale = Pal(deep: RGB(96, 44, 10), body: RGB(214, 120, 28), mid: RGB(255, 180, 70), light: RGB(255, 230, 160), a1: RGB(255, 120, 60), a2: RGB(255, 214, 120))
        static let order = Pal(deep: RGB(90, 10, 30), body: RGB(200, 40, 50), mid: RGB(255, 110, 70), light: RGB(255, 210, 150), a1: RGB(255, 220, 120), a2: RGB(255, 150, 90))
        static let rally = Pal(deep: RGB(120, 60, 8), body: RGB(240, 150, 30), mid: RGB(255, 213, 96), light: RGB(255, 250, 215), a1: RGB(255, 255, 255), a2: RGB(255, 196, 70))
        static let sweep = Pal(deep: RGB(20, 50, 140), body: RGB(92, 170, 255), mid: RGB(190, 232, 255), light: RGB(255, 255, 255), a1: RGB(255, 214, 120), a2: RGB(150, 200, 255))
        static let dust = Pal(deep: RGB(70, 55, 40), body: RGB(210, 170, 110), mid: RGB(245, 215, 150), light: RGB(255, 245, 220), a1: RGB(255, 255, 255), a2: RGB(255, 170, 80))
        static let goo = Pal(deep: RGB(20, 70, 30), body: RGB(90, 210, 90), mid: RGB(170, 250, 140), light: RGB(235, 255, 215), a1: RGB(255, 255, 200), a2: RGB(60, 170, 110))
        static let wolf = Pal(deep: RGB(60, 50, 70), body: RGB(200, 200, 225), mid: RGB(235, 235, 250), light: RGB(255, 255, 255), a1: RGB(255, 90, 80), a2: RGB(170, 60, 60))
        static let goblin = Pal(deep: RGB(100, 60, 10), body: RGB(230, 160, 40), mid: RGB(255, 210, 110), light: RGB(255, 245, 200), a1: RGB(255, 255, 230), a2: RGB(180, 220, 90))
        static let stone = Pal(deep: RGB(60, 55, 50), body: RGB(150, 140, 125), mid: RGB(205, 195, 175), light: RGB(245, 240, 225), a1: RGB(255, 230, 160), a2: RGB(110, 100, 90))
        static let troll = Pal(deep: RGB(80, 50, 20), body: RGB(180, 120, 60), mid: RGB(225, 170, 100), light: RGB(255, 235, 190), a1: RGB(255, 200, 120), a2: RGB(120, 80, 40))
        static let fury = Pal(deep: RGB(110, 20, 10), body: RGB(240, 90, 40), mid: RGB(255, 170, 70), light: RGB(255, 235, 190), a1: RGB(255, 80, 50), a2: RGB(255, 210, 100))
        static let down = Pal(deep: RGB(90, 20, 30), body: RGB(220, 60, 60), mid: RGB(255, 150, 130), light: RGB(255, 235, 225), a1: RGB(255, 255, 255), a2: RGB(255, 210, 120))
        static let blade = Pal(deep: RGB(70, 80, 110), body: RGB(190, 205, 235), mid: RGB(235, 242, 255), light: RGB(255, 255, 255), a1: RGB(255, 225, 150), a2: RGB(160, 200, 255))
        static let great = Pal(deep: RGB(110, 60, 20), body: RGB(255, 170, 70), mid: RGB(255, 215, 140), light: RGB(255, 250, 225), a1: RGB(255, 255, 255), a2: RGB(255, 140, 60))
        static let bow = Pal(deep: RGB(20, 90, 50), body: RGB(110, 230, 150), mid: RGB(190, 255, 200), light: RGB(240, 255, 240), a1: RGB(255, 240, 170), a2: RGB(120, 255, 220))
        static let staff = Pal(deep: RGB(30, 40, 140), body: RGB(110, 150, 255), mid: RGB(170, 200, 255), light: RGB(240, 245, 255), a1: RGB(255, 230, 170), a2: RGB(190, 130, 255))
        static let claw = Pal(deep: RGB(110, 20, 16), body: RGB(230, 60, 40), mid: RGB(255, 130, 90), light: RGB(255, 225, 190), a1: RGB(255, 255, 230), a2: RGB(255, 170, 60))
        static let ambush = Pal(deep: RGB(20, 90, 40), body: RGB(120, 235, 110), mid: RGB(220, 255, 130), light: RGB(250, 255, 210), a1: RGB(255, 245, 140), a2: RGB(160, 255, 190))
        static let ward = Pal(deep: RGB(10, 50, 110), body: RGB(60, 170, 255), mid: RGB(140, 225, 255), light: RGB(225, 248, 255), a1: RGB(255, 255, 255), a2: RGB(120, 200, 255))
        static let gold = Pal(deep: RGB(130, 80, 10), body: RGB(255, 190, 50), mid: RGB(255, 225, 120), light: RGB(255, 250, 220), a1: RGB(255, 255, 255), a2: RGB(255, 170, 40))
        static let heal = Pal(deep: RGB(8, 66, 40), body: RGB(40, 190, 100), mid: RGB(110, 235, 150), light: RGB(215, 255, 228), a1: RGB(255, 232, 150), a2: RGB(120, 240, 222))
    }
    static let magenta = RGB(255, 128, 226), cyan = RGB(130, 224, 255), gold = RGB(255, 232, 160), white = RGB(255, 255, 255)
    static let starlightTone = [RGB(255, 255, 255), RGB(222, 212, 255), RGB(160, 136, 255), RGB(96, 70, 235), RGB(44, 26, 150)]
    static let soulTone = [RGB(235, 250, 255), RGB(130, 210, 255), RGB(56, 140, 255), RGB(24, 70, 190)]

    // MARK: output builder

    struct Out {
        var prims: [Prim] = []
        mutating func g(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ c: RGB, _ a: Double) { prims.append(.glow(x: x, y: y, rx: rx, ry: ry, c: c, a: a)) }
        mutating func r(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ w: Double, _ c: RGB, _ a: Double, _ rot: Double = 0) { prims.append(.ring(x: x, y: y, rx: rx, ry: ry, w: w, c: c, a: a, rot: rot)) }
        mutating func e(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ ang: Double, _ c: RGB, _ a: Double) { prims.append(.streak(x: x, y: y, rx: rx, ry: ry, ang: ang, c: c, a: a)) }
        mutating func arc(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double, _ w: Double, _ c: RGB, _ a: Double) { prims.append(.arc(x: x, y: y, rx: rx, ry: ry, a0: a0, a1: a1, w: w, c: c, a: a)) }
        mutating func k(_ pts: [Pt], _ ws: [Double], _ c: RGB, _ a: Double, add: Bool, soft: Double) { prims.append(.ribbon(pts: pts, ws: ws, c: c, a: a, add: add, soft: soft)) }
        mutating func f(_ c: RGB, _ a: Double) { prims.append(.flash(c: c, a: a)) }
        /// Gradient ribbon: several passes, each (width scale, colour, additive, alpha), outer to inner.
        mutating func stack(_ pts: [Pt], _ ws: [Double], _ layers: [(Double, RGB, Bool, Double)], _ alpha: Double = 1.0) {
            for (sc, col, add, a) in layers { k(pts, ws.map { $0 * sc }, col, a * alpha, add: add, soft: max(1.2, 2.4 * sc)) }
        }
        mutating func thinRing(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ w: Double, _ c: RGB, _ a: Double) { r(x, y, rx, ry, w, c, a) }
    }

    static func ell(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a: Double) -> Pt { Pt(cx + cos(a) * rx, cy + sin(a) * ry) }

    /// Floor seal made only of rings, arcs and petals (no straight lines).
    static func sigil2(_ o: inout Out, _ cx: Double, _ cy: Double, _ R: Double, _ ratio: Double, _ t: Double, _ env: Double, _ cols: (RGB, RGB, RGB), _ petals: Int = 8, _ spin: Double = 1.0) {
        if env <= 0.01 { return }
        let (c1, c2, c3) = cols
        o.g(cx, cy, R * 1.18, R * 1.18 * ratio, c2, 0.30 * env); o.g(cx, cy, R * 0.6, R * 0.6 * ratio, c1, 0.22 * env)
        o.r(cx, cy, R, R * ratio, 2.6, c1, 0.85 * env); o.r(cx, cy, R * 0.93, R * 0.93 * ratio, 1.1, c3, 0.6 * env)
        o.r(cx, cy, R * 0.62, R * 0.62 * ratio, 1.6, c1, 0.7 * env); o.r(cx, cy, R * 0.3, R * 0.3 * ratio, 1.2, c3, 0.6 * env)
        for k in 0..<6 {
            let a0 = spin * t * 0.7 + Double(k) * Double.pi / 3
            o.arc(cx, cy, R * 0.8, R * 0.8 * ratio, a0, a0 + 0.72, 3.0, c1, 0.85 * env)
        }
        for k in 0..<4 {
            let a0 = -spin * t * 1.1 + Double(k) * Double.pi / 2
            o.arc(cx, cy, R * 0.46, R * 0.46 * ratio, a0, a0 + 0.9, 2.2, c3, 0.8 * env)
        }
        for k in 0..<petals {
            let a = Double(k) * 2 * Double.pi / Double(petals) - spin * t * 0.4, d = R * 0.5
            let px = cx + cos(a) * d, py = cy + sin(a) * d * ratio
            o.r(px, py, R * 0.3, R * 0.11 * (1 + 1.2 * (1 - ratio)), 1.2, c2, 0.5 * env, a)
            o.e(px, py, R * 0.26, R * 0.08, a, c1, 0.16 * env)
        }
        for k in 0..<16 {
            let a = Double(k) * Double.pi / 8 + spin * t * 0.5
            o.g(cx + cos(a) * R * 0.72, cy + sin(a) * R * 0.72 * ratio, 5, 5, c3, 0.85 * env * (0.55 + 0.45 * sin(t * 5 + Double(k))))
        }
    }

    static func aurora(_ o: inout Out, _ cx: Double, _ cy: Double, _ t: Double, _ env: Double, _ cols: [RGB], _ spread: Double = 150, _ h: Double = 120) {
        if env <= 0.01 { return }
        for k in 0..<3 {
            var pts: [Pt] = [], ws: [Double] = []
            for j in 0..<48 {
                let u = Double(j) / 47, x = cx + (u - 0.5) * spread * 2
                let y = cy - h - 26 * Double(k) + 22 * sin(u * 5 + t * 1.3 + Double(k) * 2) + 9 * sin(u * 11 - t * 2 + Double(k))
                pts.append(Pt(x, y)); ws.append(30 * pw(sin(Double.pi * u), 0.8) * (1 - 0.18 * Double(k)) + 2)
            }
            o.k(pts, ws, cols[k % cols.count], 0.16 * env, add: true, soft: 9)
            o.k(pts, ws.map { $0 * 0.4 }, cols[(k + 1) % cols.count], 0.12 * env, add: true, soft: 6)
        }
    }

    static func arcPts(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double, _ n: Int = 40, _ roll: Double = 0) -> [Pt] {
        (0..<n).map { j in
            let a = lerp(a0, a1, Double(j) / Double(n - 1)), x = cos(a) * rx, y = sin(a) * ry
            return Pt(cx + x * cos(roll) - y * sin(roll), cy + x * sin(roll) + y * cos(roll))
        }
    }

    /// A crackling arc between two points: a jittering smooth ribbon, a bright thin core and a soft halo.
    static func bolt(_ o: inout Out, _ A: Pt, _ B: Pt, _ t: Double, _ seed: Double, _ P: Pal, _ amp: Double = 14, _ n: Int = 16, _ w: Double = 3.2, _ alpha: Double = 1.0, _ rate: Double = 30) {
        var pts: [Pt] = [], ws: [Double] = []
        let dx = B.x - A.x, dy = B.y - A.y, L0 = hypot(dx, dy), L = L0 == 0 ? 1.0 : L0, nx = -dy / L, ny = dx / L
        for j in 0..<n {
            let u = Double(j) / Double(n - 1), env = pw(sin(Double.pi * u), 0.8)
            let jj = Double(j)
            let d = amp * env * (sin(jj * 1.9 + t * rate + seed * 7.1) * 0.6 + sin(jj * 3.3 - t * rate * 1.3 + seed * 3.7) * 0.4)
            pts.append(Pt(A.x + dx * u + nx * d, A.y + dy * u + ny * d)); ws.append(w * (0.55 + 0.45 * env))
        }
        o.stack(pts, ws, [(2.6, P.body, true, 0.22), (1.0, P.mid, true, 0.55), (0.4, P.light, true, 0.95)], alpha)
    }

    static func flame(_ o: inout Out, _ bx: Double, _ by: Double, _ h: Double, _ w: Double, _ t: Double, _ seed: Double, _ P: Pal, _ alpha: Double = 1.0, _ n: Int = 26) {
        var pts: [Pt] = [], ws: [Double] = []
        for j in 0..<n {
            let u = Double(j) / Double(n - 1)
            pts.append(Pt(bx + sin(u * 6 + t * 9 + seed * 3.3) * w * 0.5 * u + sin(u * 13 - t * 14 + seed) * w * 0.15 * u, by - u * h)); ws.append(w * pw(1 - u, 0.85) + 0.8)
        }
        o.stack(pts, ws, [(1.5, P.deep, true, 0.22), (1.0, P.body, true, 0.55), (0.5, P.mid, true, 0.8), (0.18, P.a1, true, 0.95)], alpha)
    }

    // MARK: entry point

    /// Every target gets the effect; caster-side parts (charge-up, seal under the caster, stage flash) are drawn once, for the first target.
    static func primitives(skill id: String, t: Double, geo: Geometry) -> [Prim] {
        guard !geo.targets.isEmpty else { return [] }
        var all: [Prim] = []
        for ti in geo.targets.indices {
            switch id {
            case "starlightPulse": all += starlight(t, geo, ti)
            case "dragonSoulWard": all += soul(t, geo, ti)
            case "dragonScaleWard": all += scaleWard(t, geo, ti)
            case "runeSlash": all += runeSlash(t, geo, ti)
            case "runeWard": all += runeWard(t, geo, ti)
            case "battleRune": all += battleRune(t, geo, ti)
            case "dragonFlame": all += dragonFlame(t, geo, ti)
            case "dragonOrder": all += dragonOrder(t, geo, ti)
            case "healMicro": all += healMicro(t, geo, ti)
            case "healStandard": all += healStandard(t, geo, ti)
            case "healStrong": all += healStrong(t, geo, ti)
            case "rally": all += rallyCall(t, geo, ti)
            case "sweep": all += sweepArc(t, geo, ti)
            case "natural20": all += natural20(t, geo, ti)
            case "shieldDome": all += shieldDome(t, geo, ti)
            case "hitBlade", "hitGreat", "hitBow", "hitStaff", "hitClaw", "hitAmbush", "hitWard", "hitSlime", "hitWolf", "hitArrowM", "hitStone", "hitTroll", "hitDragon": all += hitEffect(id, t, geo, ti)
            case "deathBurst", "deathSlime", "deathWolf", "deathGoblin", "deathStone", "deathTroll", "deathDragon": all += deathEffect(id, t, geo, ti)
            case "playerDown": all += playerDown(t, geo, ti)
            case "downAura": all += downAura(t, geo, ti)
            case "revive": all += revive(t, geo, ti)
            case "buffAura": all += buffAura(t, geo, ti)
            case "projBow", "projStaff", "projArcher", "projDragon": all += projectile(id, t, geo, ti)
            case "shieldBreak": all += shieldBreak(t, geo, ti)
            case "shieldShell": all += shieldShell(t, geo, ti)
            case "shieldShellHit": var g = geo; g.hitAge = t * 0.5; g.hitAngle = 0.4; g.power = 0.3; all += shieldShell(t, g, ti)
            default: return []
            }
        }
        return all + atmosphere(skill: id, t: t, geo: geo)
    }

    // MARK: starlight pulse

    static func starlight(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let C = geo.caster, CF = geo.casterFoot, T = geo.targets[ti].chest, TF = geo.targets[ti].foot, imp = 0.75
        let V = starlightTone, DEEP = RGB(40, 24, 140)
        let sig = smooth(t / 0.2) * (1 - smooth((t - 0.42) / 0.25)) * (ti == 0 ? 1.0 : 0.0)
        sigil2(&o, CF.x, CF.y - 2, 66, 0.3, t, sig, (V[2], V[3], V[1]), 8, 1.2)
        if t < 0.55 && ti == 0 {
            for i in 0..<22 {
                let ph = frac(i, 1), u = pm(t * 0.9 + ph, 1.0), di = Double(i)
                let x = CF.x + sin(u * 6 + di) * (24 + 30 * frac(i, 2)), y = CF.y - 6 - u * 130
                let al = sig * pw(sin(Double.pi * u), 0.7)
                o.g(x, y, 8, 8, [V[2], magenta, cyan][i % 3], 0.55 * al); o.g(x, y, 3, 3, V[0], 0.9 * al)
            }
        }
        func path(_ tt: Double) -> (Double, Double, Double) {
            let s = pw(easeIn(clamp01(tt / imp)), 0.8)
            let x = lerp(C.x, T.x, s), y = lerp(C.y, T.y, s)
            return (x, y - 70 * sin(Double.pi * s) * (1 - 0.3 * s), s)
        }
        if t < imp + 0.02 {
            let (hx, hy, _) = path(t)
            let N = 60
            var pts: [Pt] = [], ws: [Double] = [], nrm: [(Double, Double, Double, Int)] = []
            for i in stride(from: N - 1, through: 0, by: -1) {
                let tt = t - Double(i) * 0.0105
                if tt < 0 { continue }
                let (x, y, _) = path(tt), (x2, y2, _) = path(tt + 0.006)
                let dx = x2 - x, dy = y2 - y, L0 = hypot(dx, dy), L = L0 == 0 ? 1.0 : L0, nx = -dy / L, ny = dx / L
                let u = Double(i) / Double(N), lat = 5 * u * sin(tt * 22 + Double(i) * 0.45)
                pts.append(Pt(x + nx * lat, y + ny * lat)); nrm.append((nx, ny, tt, i))
                ws.append(((17 * pw(1 - u, 0.85) + 1.2) * (0.45 + 0.55 * clamp01(tt * 7))) * 2)
            }
            if pts.count > 3 {
                for k in stride(from: 0, to: pts.count, by: 5) { o.g(pts[k].x, pts[k].y, ws[k] * 1.9, ws[k] * 1.9, [V[3], magenta, cyan][(k / 5) % 3], 0.1) }
                o.stack(pts, ws, [(1.25, DEEP, false, 0.5), (1.0, V[4], false, 0.7), (0.72, V[3], false, 0.85), (0.5, V[2], true, 0.55), (0.22, V[1], true, 0.85)])
                for (k, col) in [magenta, cyan, V[1]].enumerated() {
                    var sp: [Pt] = [], sw: [Double] = []
                    for idx in 0..<pts.count {
                        let (nx, ny, tt, i) = nrm[idx], w = ws[idx], px = pts[idx].x, py = pts[idx].y
                        let ang = tt * 18 + Double(i) * 0.3 + Double(k) * 2.094, off = w * 0.62 + 2
                        sp.append(Pt(px + nx * cos(ang) * off, py + ny * cos(ang) * off + sin(ang) * off * 0.3)); sw.append(max(0.8, w * 0.12))
                    }
                    o.k(sp, sw, col, 0.8, add: true, soft: 2.0)
                }
            }
            for i in 0..<34 {
                let tb = frac(i, 1) * imp * 0.95
                if !(0 <= t - tb && t - tb < 0.6) { continue }
                let tt = t - tb, (px, py, _) = path(tb), r = tt / 0.6
                let x = px + (frac(i, 2) - 0.5) * 44 * r, y = py + (frac(i, 3) - 0.3) * 44 * r + 34 * r * r
                let col = [V[0], gold, magenta, cyan][i % 4], k = (1 - r) * (0.6 + 0.4 * sin(tt * 30 + Double(i)))
                o.g(x, y, 8, 8, col, 0.7 * k); o.e(x, y, 8 + 4 * frac(i, 4), 1.1, tt * 3 + Double(i), V[0], 0.8 * k); o.e(x, y, 8 + 4 * frac(i, 4), 1.1, tt * 3 + Double(i) + 1.571, V[0], 0.8 * k)
            }
            let fade = clamp01((imp - t) / 0.05), pulse = 1 + 0.08 * sin(t * 25)
            o.g(hx, hy, 74, 74, V[3], 0.3 * fade); o.g(hx, hy, 40, 40, V[2], 0.42 * fade)
            o.r(hx, hy, 26 * pulse, 26 * pulse, 1.5, V[2], 0.5 * fade); o.r(hx, hy, 34, 34, 1.0, magenta, 0.35 * fade)
            o.g(hx, hy, 24, 24, V[1], 0.75 * fade); o.g(hx, hy, 12, 12, V[0], 1.0 * fade)
            o.e(hx, hy, 110, 3.2, 0, V[1], 0.45 * fade); o.e(hx, hy, 70, 2.4, 0, V[0], 0.5 * fade)
            for k in 0..<4 { o.e(hx, hy, 42 - 10 * Double(k % 2), 2.4, t * 3 + Double(k) * 0.785, V[0], 0.6 * fade) }
            for k in 0..<7 {
                let a = t * 9 + Double(k) * 2 * Double.pi / 7, rr = 24 + 5 * sin(t * 6 + Double(k))
                o.g(hx + cos(a) * rr, hy + sin(a) * rr * 0.6, 6, 6, [V[0], magenta, cyan][k % 3], 0.8 * fade)
            }
        }
        let a = t - imp
        if a >= 0 {
            let cx = T.x, cy = T.y
            if a < 0.2 && ti == 0 { o.f(V[2], 0.12 * exp(-a * 18)) }
            o.g(cx, cy, 170 * (0.5 + easeOut(a / 0.35)), 170 * (0.5 + easeOut(a / 0.35)), V[3], 0.4 * (1 - easeIn(a / 0.8)))
            o.g(cx, cy, 60, 60, V[2], 0.5 * (1 - easeIn(a / 0.35)))
            o.g(cx, cy, 22, 22, V[1], 0.6 * (1 - easeIn(a / 0.22))); o.g(cx, cy, 10, 10, V[0], 0.9 * (1 - easeIn(a / 0.16)))
            o.e(cx, cy, 230 * easeOut(a / 0.2), 4.5, 0, V[1], 0.55 * (1 - easeIn(a / 0.45)))
            o.e(cx, cy, 110 * easeOut(a / 0.2), 3.2, 0, V[0], 0.55 * (1 - easeIn(a / 0.35)))
            o.e(cx, cy, 90 * easeOut(a / 0.2), 3.0, 1.571, V[1], 0.4 * (1 - easeIn(a / 0.35)))
            for k in 0..<40 {
                let ang = Double(k) * 2 * Double.pi / 40 + a * 0.4
                let L = (60 + 100 * frac(k, 2)) * easeOut(a / 0.16) * (1 - easeIn((a - 0.1) / 0.6))
                if L > 3 { o.e(cx + cos(ang) * L / 2, cy + sin(ang) * L / 2, L / 2, 1.8, ang, [V[2], magenta, cyan, V[1]][k % 4], 0.55 * (1 - a / 0.7)) }
            }
            for (d, col) in [(0.0, V[2]), (0.07, magenta), (0.14, cyan), (0.22, V[1])] where a - d >= 0 {
                let r = 12 + 150 * easeOut((a - d) / 0.6)
                o.r(cx, cy, r, r * 0.8, 3.0 * (1 - (a - d) / 0.65) + 0.6, col, 0.85 * (1 - easeIn((a - d) / 0.65)))
            }
            let lotus: [(Int, RGB, Double, Double)] = [(12, V[2], 0.0, 120), (8, magenta, 0.39, 82), (12, cyan, 0.13, 150)]
            for (layer, (nP, col, rot0, size)) in lotus.enumerated() {
                let k = easeOut((a - Double(layer) * 0.05) / 0.3) * (1 - easeIn((a - 0.22 - Double(layer) * 0.05) / 0.5))
                if k > 0.02 {
                    for q in 0..<nP {
                        let ang = Double(q) * 2 * Double.pi / Double(nP) + rot0 + a * (0.9 - 0.3 * Double(layer)), L = size * k
                        let px = cx + cos(ang) * L * 0.5, py = cy + sin(ang) * L * 0.5 * 0.82
                        o.r(px, py, L * 0.5, L * 0.13, 1.4, col, 0.6 * k, ang); o.e(px, py, L * 0.42, L * 0.1, ang, col, 0.2 * k)
                    }
                }
            }
            let sg2 = smooth(a / 0.08) * (1 - easeIn((a - 0.22) / 0.6))
            sigil2(&o, TF.x, TF.y - 2, 46 + 62 * easeOut(a / 0.3), 0.3, a + imp, sg2, (V[2], V[3], V[1]), 8, 1.6)
            for q in 0..<3 {
                var pts: [Pt] = [], ws: [Double] = []
                for j in 0..<40 {
                    let u = Double(j) / 39, ang = Double(q) * 2.094 + u * 7 + a * 5, rr = 36 + 40 * u
                    pts.append(Pt(TF.x + cos(ang) * rr, TF.y - 8 - u * 150 * easeOut(a / 0.5) + sin(ang) * rr * 0.3)); ws.append(5 * pw(sin(Double.pi * u), 0.8) + 0.6)
                }
                o.k(pts, ws, [V[2], magenta, cyan][q], 0.55 * (1 - easeIn((a - 0.15) / 0.6)), add: true, soft: 3.0)
            }
            for i in 0..<90 {
                let life = 0.55 + 0.6 * frac(i, 2), tt = a - 0.02 * frac(i, 5)
                if !(0 <= tt && tt < life) { continue }
                let ang = frac(i, 3) * 6.283, spd = 160 + 300 * frac(i, 4), tr = tt / life
                let d = spd * (1 - exp(-tt * 5)) / 5, v = spd * exp(-tt * 5)
                let x = cx + cos(ang) * d, y = cy + sin(ang) * d * 0.8 + 140 * tt * tt * b2d(frac(i, 6) > 0.5)
                let tw = 0.6 + 0.4 * sin(tt * 40 + Double(i)), col = [V[0], gold, magenta, cyan, V[1]][i % 5]
                o.e(x - cos(ang) * v * 0.014, y - sin(ang) * v * 0.014 * 0.8, max(3.0, v * 0.03), 1.9 * (1 - 0.5 * tr), ang, col, 0.9 * (1 - tr) * tw)
                o.g(x, y, 7, 7, col, 0.5 * (1 - tr) * tw)
            }
            for i in 0..<34 {
                let tb = 0.06 + 0.55 * frac(i, 1), tt = a - tb
                if !(0 <= tt && tt < 0.9) { continue }
                let x = cx + (frac(i, 2) - 0.5) * 210, y = cy - 130 + tt * (70 + 40 * frac(i, 3)), r = tt / 0.9
                let col = [V[0], gold, V[1], cyan][i % 4], k = sin(Double.pi * r) * (0.6 + 0.4 * sin(tt * 30 + Double(i)))
                let sz = 5 + 6 * frac(i, 4)
                o.g(x, y, sz, sz, col, 0.7 * k); o.e(x, y, sz * 1.7, 1.1, tt * 2 + Double(i), V[0], 0.8 * k); o.e(x, y, sz * 1.7, 1.1, tt * 2 + Double(i) + 1.571, V[0], 0.8 * k)
            }
            aurora(&o, cx, cy - 20, a * 1.4, smooth(a / 0.25) * (1 - smooth((a - 0.4) / 0.5)), [V[3], magenta, cyan], 140, 100)
        }
        return o.prims
    }

    // MARK: dragon soul ward (power and presence, nothing literal)

    static func soul(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let D = soulTone, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot, fx = foot.x, fy = foot.y, gy = foot.y
        let cx = chest.x, cy = chest.y
        let BODY = RGB(34, 98, 220), MID = RGB(70, 150, 255), LIGHT = RGB(170, 225, 255)
        let REL = 0.38
        let pre = clamp01(t / REL), post = t - REL
        let sg = smooth(t / 0.22) * (1 - smooth((t - 1.55) / 0.4))
        sigil2(&o, fx, gy - 2, 74 - 14 * easeIn(pre) * b2d(post < 0) + 8 * easeOut(post / 0.3), 0.28, t, sg, (D[2], RGB(36, 90, 220), D[1]), 10, 1.0 + 3 * easeIn(pre) * b2d(post < 0))
        if t < REL + 0.05 {
            for i in 0..<34 {
                let ph = frac(i, 1), tt = clamp01((t - ph * 0.12) / (REL - ph * 0.12))
                let a = frac(i, 2) * 6.283 + tt * 4.5, r = (120 + 80 * frac(i, 3)) * pw(1 - easeIn(tt), 1.4)
                let x = cx + cos(a) * r, y = cy + 20 + sin(a) * r * 0.55 - 20 * easeIn(tt)
                let k = pw(sin(Double.pi * min(1, tt * 1.05)), 0.6)
                o.e(x, y, 9 + 18 * (1 - tt), 1.8, a + 1.571 + tt * 4.5, [D[0], D[1], gold][i % 3], 0.8 * k)
                o.g(x, y, 6, 6, D[0], 0.8 * k)
            }
            let k = easeIn(pre) * b2d(post < 0)
            o.g(cx, cy, 70 - 40 * k + 20, 90 - 50 * k + 20, D[3], 0.22 + 0.22 * k); o.g(cx, cy, 20, 26, D[1], 0.5 * k)
        }
        if post >= 0 {
            if post < 0.22 && ti == 0 { o.f(D[2], 0.12 * exp(-post * 14)) }
            let waves: [(Double, Double)] = [(0, 7.0), (0.08, 5.0), (0.17, 3.4), (0.28, 2.2)]
            for (j, (d, wd)) in waves.enumerated() where post - d >= 0 {
                let r = 14 + 190 * easeOut((post - d) / 0.7)
                o.r(fx, gy - 2, r, r * 0.27, wd * (1 - (post - d) / 0.75) + 0.5, [D[1], D[2], D[2], D[1]][j], 0.8 * (1 - easeIn((post - d) / 0.75)))
            }
            for j in 0..<2 where post - Double(j) * 0.1 >= 0 {
                let pj = post - Double(j) * 0.1, r = 26 + 120 * easeOut(pj / 0.5)
                o.r(cx, cy, r, r * 1.25, 2.4 * (1 - pj / 0.55) + 0.5, D[1], 0.6 * (1 - easeIn(pj / 0.55)))
            }
            let colEnv = smooth(post / 0.12) * (1 - smooth((post - 0.95) / 0.55))
            let layers: [(Double, RGB, Double)] = [(84, D[3], 0.12), (52, BODY, 0.12), (26, D[2], 0.12), (9, MID, 0.3)]
            let us = (0..<41).map { Double($0) / 40 }
            for (lyr, (w, c_, a)) in layers.enumerated() {
                let top = fy - 250 * easeOut(post / 0.2), dl = Double(lyr)
                let pts = us.map { u in Pt(fx + sin(u * 7 + t * 4 + dl) * 3 * (1 - u), fy - u * (fy - top)) }
                let ws = us.map { u in w * (0.5 + 0.5 * pw(sin(Double.pi * (u * 0.9 + 0.1)), 0.5)) * (1 + 0.06 * sin(t * 20 + dl)) }
                o.k(pts, ws, c_, a * colEnv, add: true, soft: lyr < 2 ? 14 : 6)
            }
            for q in 0..<6 {
                let sgn: Double = q % 2 == 0 ? 1 : -1, dq = Double(q)
                var pts: [Pt] = [], ws: [Double] = []
                let head = easeOut(clamp01(post / 0.5)), tail = easeIn(clamp01((post - 0.9) / 0.6))
                for j in 0..<72 {
                    let u = Double(j) / 71
                    if u > head || u < tail * 0.9 { continue }
                    let ang = dq * 1.047 + sgn * (u * (7 + 0.7 * dq) - post * (4.5 + 0.4 * dq)), rr = 40 + 30 * sin(u * 3 + dq) + 34 * u * (1 + 0.15 * dq)
                    pts.append(Pt(fx + cos(ang) * rr, fy - 8 - u * 215 + sin(ang) * rr * 0.3)); ws.append((11 * pw(1 - u, 0.9) + 1.4) * (1 - tail) * (0.75 + 0.25 * sin(u * 9 + dq)))
                }
                if pts.count > 3 {
                    o.stack(pts, ws, [(1.7, D[3], true, 0.30), (1.0, BODY, true, 0.5), (0.5, MID, true, 0.7), (0.16, LIGHT, true, 0.8)], colEnv)
                    o.k(pts, ws.map { $0 * 3.0 }, D[3], 0.1 * colEnv, add: true, soft: 12)
                }
            }
            for i in 0..<44 {
                let tb = 0.02 + 0.5 * frac(i, 1), tt = post - tb
                if !(0 <= tt && tt < 0.9) { continue }
                let a = frac(i, 3) * 6.283, r = (60 + 160 * frac(i, 4)) * easeOut(tt / 0.6)
                let x = cx + cos(a) * r, y = cy + 40 + sin(a) * r * 0.3 - 70 * tt * (0.5 + frac(i, 5)), k = (1 - tt / 0.9) * (0.6 + 0.4 * sin(tt * 30 + Double(i)))
                o.e(x, y, 10, 1.7, a, [D[0], gold, D[1]][i % 3], 0.8 * k); o.g(x, y, 6, 6, D[0], 0.7 * k)
            }
            for k in 0..<26 {
                let a = Double(k) * 2 * Double.pi / 26 + 0.3 * frac(k, 2), L = 40 + 60 * frac(k, 3), r = (30 + 160 * easeOut(post / 0.6)) * (0.7 + 0.5 * frac(k, 4))
                o.e(fx + cos(a) * r, gy - 4 + sin(a) * r * 0.27, L, 1.8, a, D[2], 0.5 * (1 - easeIn(post / 0.8)))
            }
        }
        let aura = post > 0 ? smooth((post - 0.1) / 0.4) * (1 - smooth((t - 1.6) / 0.4)) : 0.0
        if aura > 0.01 {
            let pulse = 1 + 0.05 * sin(t * 6), RX = 56 * pulse, RY = 86 * pulse
            o.g(cx, cy, RX * 1.6, RY * 1.3, D[3], 0.22 * aura); o.g(cx, cy, RX * 1.05, RY * 1.0, D[2], 0.08 * aura)
            for (sc, w, c_, al) in [(1.0, 3.0, D[1], 0.55), (0.94, 1.6, D[2], 0.5), (1.1, 1.4, D[2], 0.35)] { o.r(cx, cy, RX * sc, RY * sc, w, c_, al * aura) }
            for k in 0..<5 {
                let dk = Double(k), a0 = t * (1.3 + 0.35 * dk) + dk * 1.3
                o.arc(cx, cy, RX * (1 + 0.03 * dk), RY * (1 + 0.03 * dk), a0, a0 + 1.0, 2.8, D[1], 0.6 * aura)
            }
            for i in 0..<16 {
                let di = Double(i), ph = frac(i, 1), u0 = pm(t * 0.55 + ph, 1.0), a = frac(i, 2) * 6.283
                let bx = cx + cos(a) * RX * 0.7, by = cy + RY * 0.75
                var pts: [Pt] = [], ws: [Double] = []
                for j in 0..<22 {
                    let u = Double(j) / 21, y = by - u * (90 + 70 * frac(i, 3)) * (0.35 + 0.65 * u0)
                    pts.append(Pt(bx + sin(u * 5 + t * 3 + di) * 9 * u + (frac(i, 4) - 0.5) * 20 * u, y)); ws.append(8 * pw(1 - u, 1.1) + 0.4)
                }
                let fade = pw(sin(Double.pi * u0), 0.8)
                o.k(pts, ws, [D[2], D[1], D[2]][i % 3], 0.4 * aura * fade, add: true, soft: 3.0)
            }
            for i in 0..<30 {
                let u = pm(t * 0.4 + frac(i, 1), 1.0), a = frac(i, 2) * 6.283 + t * 0.8
                let x = cx + cos(a) * RX * 0.95 * frac(i, 3), y = cy + RY * (1 - 2 * u), k = aura * sin(Double.pi * u)
                o.g(x, y, 8, 8, [D[0], D[1], gold][i % 3], 0.65 * k); o.g(x, y, 3, 3, white, 0.9 * k)
            }
            let halo = aura * (0.7 + 0.3 * sin(t * 5))
            o.r(cx, cy - RY - 14, 34, 9, 2.2, gold, 0.75 * halo); o.g(cx, cy - RY - 14, 50, 16, gold, 0.28 * halo)
        }
        return o.prims
    }

    // MARK: spellblade: rune slash

    static func runeSlash(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.rune, C = geo.caster, T = geo.targets[ti].chest, imp = 1.048
        let pre = clamp01((t - 0.25) / (imp - 0.25)), cx = T.x, cy = T.y
        let ANG: [Double] = [-0.95, 0.35, 1.25, -0.2, -1.75]
        for k in 0..<(ti == 0 ? 5 : 0) {
            let dk = Double(k), e = smooth((t - 0.2 - dk * 0.09) / 0.35)
            if e <= 0.01 || t >= imp + 0.05 * dk { continue }
            let sp = 3 + 14 * pre * pre, a = t * sp + dk * 1.2566, R = 52 + 10 * sin(t * 5 + dk)
            let px = C.x + 24 + cos(a) * R, py = C.y + sin(a) * R * 0.55, ang = a + 1.571
            let pts = (0..<12).map { i -> Pt in let s_ = Double(i) / 11 - 0.5; return Pt(px + cos(ang) * s_ * 24, py + sin(ang) * s_ * 24 * 0.55) }
            let ws = (0..<12).map { i in 9 * pw(sin(Double.pi * (Double(i) / 11)), 0.8) + 0.6 }
            o.stack(pts, ws, [(2.2, P.body, true, 0.25), (1.0, P.mid, true, 0.6), (0.4, P.light, true, 0.95)], e)
        }
        if t < imp && ti == 0 {
            o.g(C.x + 24, C.y, 40 + 30 * pre, 50 + 30 * pre, P.body, 0.22 + 0.25 * pre); o.g(C.x + 24, C.y, 14, 18, P.light, 0.8 * pre)
        }
        let last = imp + 0.06 * 4
        for k in 0..<5 {
            let dk = Double(k), a = t - imp - 0.06 * dk
            if a < 0 { continue }
            let th = ANG[k], L = 150 + 30 * Double(k % 2)
            let reveal = easeOut(clamp01(a / 0.07))
            let env = 1 - easeIn((a - 0.06) / 0.55)
            let ux = cos(th), uy = sin(th) * 0.8, nx = -uy, ny = ux
            var pts: [Pt] = [], ws: [Double] = []
            for j in 0..<30 {
                let u = Double(j) / 29, s_ = (u - 0.5) * 2, bow = (1 - s_ * s_) * 16
                pts.append(Pt(cx + ux * s_ * L * reveal + nx * bow, cy + uy * s_ * L * reveal + ny * bow)); ws.append(10 * pw(sin(Double.pi * u), 0.75) + 0.5)
            }
            if env > 0.01 {
                o.stack(pts, ws, [(2.4, P.deep, true, 0.3), (1.2, P.body, true, 0.5), (0.6, P.mid, true, 0.7), (0.22, P.light, true, 0.95)], env)
                let col = k % 2 == 0 ? P.a1 : P.light
                o.g(cx, cy, 44, 44, col, 0.4 * env * (1 - easeIn(a / 0.3))); o.e(cx, cy, 120, 3.0, th, P.mid, 0.5 * (1 - easeIn(a / 0.22)))
            }
            for i in 0..<8 {
                let ang2 = th + (frac(i + 9 * k, 3) - 0.5) * 1.4 + (i % 2 == 1 ? Double.pi : 0), d = (30 + 80 * frac(i + 9 * k, 4)) * easeOut(a / 0.4)
                o.e(cx + cos(ang2) * d, cy + sin(ang2) * d * 0.8, 9, 1.5, ang2, i % 2 == 0 ? P.light : P.a1, 0.8 * (1 - easeIn(a / 0.5)))
            }
        }
        if t - last > 0 {
            let a = t - last
            if ti == 0 { o.f(P.light, 0.1 * exp(-a * 20)) }
            let r = 20 + 100 * easeOut(a / 0.35); o.r(cx, cy, r, r * 0.8, 2.4 * (1 - a / 0.4) + 0.4, P.mid, 0.7 * (1 - easeIn(a / 0.4)))
            for i in 0..<26 {
                let ang2 = frac(i, 3) * 6.283, d = (40 + 130 * frac(i, 4)) * easeOut(a / 0.6), tr = a / 0.9
                o.e(cx + cos(ang2) * d, cy + sin(ang2) * d * 0.8 + 40 * a * a, 12, 1.4, ang2 + 1.2 * a, [P.light, P.a1, P.mid][i % 3], 0.8 * (1 - tr))
            }
        }
        return o.prims
    }

    // MARK: spellblade: rune ward

    static func runeWard(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.rune, foot = geo.targets[ti].foot, chest = geo.targets[ti].chest, fx = foot.x, fy = foot.y, cy = chest.y, imp = 0.72
        let N = 6, H = 150.0
        let close = t >= imp ? easeOut(clamp01((t - imp) / 0.4)) : 0.0
        let appear = smooth(t / 0.4), fadeout = 1 - smooth((t - 1.9) / 0.45)
        let R = t >= imp ? lerp(112, 50, close) : 112 - 6 * sin(t * 6)
        let spin = t * (0.5 + 4 * (1 - close)) * (t < imp ? 1.0 : (1 - close))
        for k in 0..<N {
            let dk = Double(k), a = spin + dk * 2 * Double.pi / Double(N), half = Double.pi / Double(N) * (0.86 + 0.14 * close)
            var ptsB: [Pt] = []
            for j in 0..<26 {
                let u = Double(j) / 25, aa = a + (u - 0.5) * 2 * half * (t >= imp ? 1.0 : 0.6)
                ptsB.append(Pt(fx + cos(aa) * R, fy - 4 + sin(aa) * R * 0.28))
            }
            let depth = sin(a)
            for j in stride(from: 0, to: 26, by: 3) {
                let x0 = ptsB[j].x, y0 = ptsB[j].y, u = Double(j) / 25, h = H * (0.92 + 0.08 * sin(u * Double.pi)) * (t < imp ? appear : 1.0)
                let pwp = (0..<15).map { q in Pt(x0, y0 - Double(q) * h / 14 + sin(Double(q) * 0.5 + t * 3 + dk) * 1.5) }
                let ww = (0..<15).map { q in 6 + 2 * sin(Double(q) / 14 * Double.pi) }
                o.k(pwp, ww, depth < 0 ? P.body : P.mid, (depth < 0 ? 0.2 : 0.34) * appear * fadeout, add: true, soft: 5.0)
            }
            let top = ptsB.map { Pt($0.x, $0.y - H * (t < imp ? appear : 1.0)) }
            o.k(top, [Double](repeating: 3.2, count: top.count), P.light, (depth >= 0 ? 0.5 : 0.3) * appear * fadeout, add: true, soft: 2.0)
            o.k(ptsB, [Double](repeating: 3.2, count: ptsB.count), P.light, (depth >= 0 ? 0.55 : 0.3) * appear * fadeout, add: true, soft: 2.0)
            let ca = cos(a), sa = sin(a)
            for m in 0..<3 {
                let uu = pm(t * 0.35 + Double(m) / 3 + dk * 0.13, 1.0), x = fx + ca * R, y = fy - 4 + sa * R * 0.28 - uu * H
                o.g(x, y, 7, 7, P.a1, 0.7 * appear * fadeout * sin(Double.pi * uu))
            }
        }
        if t >= imp {
            let a = t - imp
            if a < 0.5 {
                if ti == 0 { o.f(P.light, 0.1 * exp(-a * 16)) }
                let r = 30 + 120 * easeOut(a / 0.45); o.r(fx, fy - 2, r, r * 0.28, 3.4 * (1 - a / 0.5) + 0.5, P.light, 0.8 * (1 - easeIn(a / 0.5)))
            }
            for k in 0..<N {
                let dk = Double(k), ph = pm(t * 1.4 - dk / Double(N), 1.0), ang = dk * 2 * Double.pi / Double(N) + spin + Double.pi / Double(N)
                let x = fx + cos(ang) * R, y = fy - 4 + sin(ang) * R * 0.28
                let pts = (0..<13).map { q in Pt(x, y - Double(q) * H / 12) }
                o.k(pts, [Double](repeating: 2.6, count: 13), P.light, (0.9 * exp(-ph * 4)) * fadeout, add: true, soft: 2.0)
            }
            o.g(fx, cy, 70, 100, P.body, 0.12 * fadeout)
        }
        if t < imp {
            for i in 0..<30 {
                let ph = frac(i, 1), a = frac(i, 2) * 6.283 + t * 2, r = 120 + 40 * ph
                o.g(fx + cos(a) * r, fy - 6 - frac(i, 3) * H + sin(a) * r * 0.28, 6, 6, P.mid, 0.6 * appear * (1 - clamp01((t - imp + 0.1) / 0.1)))
            }
        }
        return o.prims
    }

    // MARK: spellblade: battle rune

    static func battleRune(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.battle, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot, fx = foot.x, fy = foot.y, cx = chest.x, cy = chest.y, imp = 0.56
        let pre = clamp01((t - 0.05) / (imp - 0.05)), post = t - imp, fade = 1 - smooth((t - 1.75) / 0.35)
        let NODES = (0..<6).map { k -> Pt in let a = Double(k) * Double.pi / 3 + 0.4; return Pt(cx + cos(a) * 46, cy + sin(a) * 58) }
        if t < imp {
            for k in 0..<Int(3 + 9 * pre) {
                let ia = k % 6, ib = (k * 5 + 2) % 6
                if ia != ib { bolt(&o, NODES[ia], NODES[ib], t, Double(k), P, 6 + 6 * pre, 10, 1.6, 0.5 + 0.5 * pre) }
            }
            o.g(cx, cy, 70, 90, P.body, 0.15 + 0.2 * pre)
        }
        if post >= 0 {
            if post < 0.15 && ti == 0 { o.f(P.light, 0.2 * exp(-post * 18)) }
            let env = smooth(post / 0.08) * fade
            for k in 0..<16 {
                let ph = Int(t * 24) + k * 7, r1 = frac(ph, 1), r2 = frac(ph, 2)
                let a1 = Double(k) * 0.393 + r1 * 0.5, ang2 = a1 + 1.2 + r2 * 2.2
                let A = Pt(cx + cos(a1) * (30 + 20 * r1), cy + sin(a1) * (40 + 20 * r1))
                var B = Pt(fx + cos(ang2) * (70 + 60 * r2), fy - 4 + sin(ang2) * 18)
                if k % 3 == 0 { B = Pt(cx + cos(ang2) * (90 + 40 * r2), cy + sin(ang2) * (100 + 30 * r2) - 20) }
                bolt(&o, A, B, t, Double(k + 1), P, 22, 16, 3.0, env * (0.45 + 0.55 * frac(ph, 3)) * (1 - easeIn(post / 1.6) * 0.6))
            }
            for q in 0..<4 {
                let d = Double(q) * 0.06, aa = post - d
                if 0 <= aa && aa < 0.5 {
                    let y = fy - 170 * easeOut(aa / 0.45), w = 62 * (1 - aa / 0.6)
                    let us = (0..<21).map { Double($0) / 20 }
                    let pts = us.map { u in Pt(cx + (u - 0.5) * 2 * w, y + 8 * sin(u * 3.1)) }
                    o.k(pts, us.map { 3.4 * sin(Double.pi * $0) + 0.4 }, [P.light, P.a1, P.mid, P.body][q], 0.8 * (1 - aa / 0.5), add: true, soft: 3.0)
                }
            }
            for i in 0..<34 {
                let tb = frac(i, 1) * 0.6, tt = post - tb
                if !(0 <= tt && tt < 0.8) { continue }
                let ang = frac(i, 3) * 6.283, d = (50 + 120 * frac(i, 4)) * easeOut(tt / 0.5)
                let x = cx + cos(ang) * d, y = cy + sin(ang) * d * 0.6 - 60 * tt * (0.4 + frac(i, 5)) + 120 * tt * tt * b2d(frac(i, 6) > 0.5), k = 1 - tt / 0.8
                o.e(x, y, 8, 1.5, ang, [P.light, P.a1, P.mid][i % 3], 0.8 * k); o.g(x, y, 5, 5, P.light, 0.7 * k)
            }
            for k in 0..<6 {
                let dk = Double(k), ang = dk * 1.047 + 0.3, x = fx + cos(ang) * 60, y = fy - 4 + sin(ang) * 16
                o.g(x, y, 26, 8, P.deep, 0.35 * fade); o.g(x, y, 10, 4, P.mid, 0.5 * fade * (0.5 + 0.5 * sin(t * 25 + dk * 2)))
            }
        }
        return o.prims
    }

    // MARK: dragon knight: dragon flame

    static func dragonFlame(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.flame, C = geo.caster, T = geo.targets[ti].chest, TF = geo.targets[ti].foot, imp = 0.46
        let cx = T.x, cy = T.y, post = t - imp, d: Double = cx >= C.x ? 1.0 : -1.0
        let SX = cx - 170 * d, SY = cy - 330
        o.g(SX, SY, 160, 120, P.body, 0.22 * smooth(t / 0.2) * (1 - smooth(post / 0.3)))
        if post < 0.4 { o.g(SX, SY, 70, 60, P.mid, 0.25 * smooth(t / 0.2) * (1 - smooth(post / 0.3))) }
        func path(_ tt: Double) -> (Double, Double, Double) {
            let s = pw(easeIn(clamp01(tt / imp)), 1.5)
            return (lerp(SX, cx, s) + sin(s * 5) * 8 * (1 - s), lerp(SY, cy, s), s)
        }
        if t < imp + 0.03 {
            let (hx, hy, _) = path(t)
            var pts: [Pt] = [], ws: [Double] = []
            for i in stride(from: 48, through: 0, by: -1) {
                let tt = t - Double(i) * 0.012
                if tt < 0 { continue }
                let (x, y, _) = path(tt), u = Double(i) / 48, di = Double(i)
                pts.append(Pt(x + sin(tt * 40 + di * 0.6) * 5 * u, y + cos(tt * 33 + di * 0.4) * 5 * u)); ws.append((13 * pw(1 - u, 0.9) + 1.0) * (0.5 + 0.5 * clamp01(tt * 6)))
            }
            if pts.count > 3 { o.stack(pts, ws, [(1.8, P.deep, true, 0.22), (1.0, P.body, true, 0.5), (0.5, P.mid, true, 0.8), (0.2, P.a1, true, 0.95)]) }
            for q in 0..<12 {
                let dq = Double(q)
                var fp: [Pt] = [], fw: [Double] = []
                for j in 0..<18 {
                    let u = Double(j) / 17
                    fp.append(Pt(hx - (cx - SX) / 380 * u * 90 + sin(u * 7 + t * 20 + dq * 1.1) * 10 * u + (dq - 5.5) * 3, hy - (cy - SY) / 380 * u * 90 + cos(u * 6 + t * 17 + dq) * 8 * u)); fw.append(6 * pw(1 - u, 0.9) + 0.4)
                }
                o.k(fp, fw, [P.mid, P.a2, P.body][q % 3], 0.5, add: true, soft: 1.6)
            }
            o.g(hx, hy, 70, 70, P.body, 0.5); o.g(hx, hy, 34, 34, P.mid, 0.8); o.g(hx, hy, 14, 14, P.a1, 1.0)
        }
        if post >= 0 {
            if post < 0.25 && ti == 0 { o.f(P.mid, 0.26 * exp(-post * 12)) }
            o.g(cx, cy, 290 * (0.5 + easeOut(post / 0.3)), 190 * (0.5 + easeOut(post / 0.3)), P.body, 0.45 * (1 - easeIn(post / 0.7)))
            o.g(cx, cy, 70, 60, P.a1, 0.8 * (1 - easeIn(post / 0.22)))
            for k in 0..<18 {
                let dk = Double(k), a = dk * 2 * Double.pi / 18 + 0.2 * frac(k, 2), L = (120 + 110 * frac(k, 3)) * easeOut(post / 0.45)
                let x = TF.x + cos(a) * L, y = TF.y - 4 + sin(a) * L * 0.27
                flame(&o, x, y, 40 + 60 * frac(k, 4) * (1 - easeIn(post / 1.4)), 10, t, dk, P, (1 - easeIn((post - 0.4) / 1.2)) * smooth(post / 0.1))
            }
            for i in 0..<36 {
                let di = Double(i), ang = frac(i, 5) * 6.283, rr = 20 + 150 * frac(i, 6), x = TF.x + cos(ang) * rr * 1.1, y = TF.y - 3 + sin(ang) * rr * 0.27
                let born = 0.15 + 0.5 * frac(i, 7), lifeA = clamp01((post - born) / 0.2) * (1 - clamp01((post - born - 0.9 - 0.5 * frac(i, 8)) / 0.5))
                if lifeA > 0.01 { flame(&o, x, y, (26 + 44 * frac(i, 9)) * (0.7 + 0.3 * sin(t * 11 + di)), 5.5 + 4 * frac(i, 1), t, di + 20, P, lifeA, 18) }
            }
            for i in 0..<14 {
                let u = clamp01((post - 0.2 - 0.05 * Double(i)) / 1.3)
                if 0 < u && u < 1 { o.g(TF.x + (frac(i, 1) - 0.5) * 100, TF.y - 30 - u * 190, 36 + 34 * u, 30 + 26 * u, P.deep, 0.24 * sin(Double.pi * u)) }
            }
            o.g(TF.x, TF.y - 2, 120, 26, P.deep, 0.36 * smooth(post / 0.3) * (1 - smooth((post - 1.6) / 0.6)))
            for i in 0..<60 {
                let tb = 0.02 + 0.5 * frac(i, 1), tt = post - tb
                if !(0 <= tt && tt < 1.2) { continue }
                let a = frac(i, 3) * 6.283, r = (40 + 190 * frac(i, 4)) * easeOut(tt / 0.6), k = 1 - tt / 1.2
                o.e(cx + cos(a) * r, cy + 20 + sin(a) * r * 0.4 - 130 * tt * (0.4 + frac(i, 5)) + 90 * tt * tt, 9, 1.6, a - 1.2 * tt, [P.a1, P.mid, P.a2][i % 3], 0.85 * k * (0.6 + 0.4 * sin(tt * 30 + Double(i))))
            }
        }
        if t < imp + 0.9 && ti == 0 {
            let e = smooth((t - 0.05) / 0.2) * (1 - smooth((t - imp - 0.5) / 0.4)); o.g(C.x + 26 * d, C.y - 6, 36, 40, P.mid, 0.25 * e)
        }
        return o.prims
    }

    // MARK: dragon knight: dragon scale ward

    static func scaleWard(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.scale, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot, fx = foot.x, fy = foot.y, cx = chest.x, cy = chest.y, imp = 0.56
        let fadeout = 1 - smooth((t - 1.85) / 0.4)
        let ORB: [(Double, Double, Double, Int)] = [(60, 0.35, 1.0, 5), (74, 1.15, -0.65, 5), (86, -1.2, 0.5, 5)]
        let BR = RGB(96, 52, 14)
        for (oi, (R, tilt, spd, n)) in ORB.enumerated() {
            let doi = Double(oi)
            let lock = t >= imp - 0.3 ? easeOut(clamp01((t - imp + 0.16 * (2 - doi) - 0.1) / 0.34)) : 0.0
            for k in 0..<n {
                let dk = Double(k)
                let drop = clamp01((t - 0.05 * dk - 0.08 * doi) / (imp - 0.1)), fall = pw(1 - easeOut(drop), 1.5)
                let a0 = spd * t * (1 + 1.5 * (1 - lock)) + dk * 2 * Double.pi / Double(n) + doi
                let half = 0.30 - 0.03 * doi
                var pts: [Pt] = []
                for j in 0..<24 {
                    let a = a0 + (Double(j) / 23 - 0.5) * 2 * half, x = cos(a) * R, z = sin(a) * R
                    let y = z * sin(tilt) * 1.0 + fall * -170, px = cx + x * cos(tilt * 0.6), py = cy + y * 1.05 + z * 0.12
                    pts.append(Pt(px, py))
                }
                let depth = sin(a0) * cos(tilt)
                let alpha = (depth > -0.3 ? 1.0 : 0.55) * fadeout * smooth(drop * 3)
                let ws = (0..<24).map { j in 8.5 * pw(sin(Double.pi * (Double(j) / 23)), 0.6) + 1.6 }
                o.stack(pts, ws, [(1.3, BR, false, 0.9), (1.0, P.body, false, 1.0), (0.5, P.mid, false, 0.85), (0.16, P.light, true, 0.95)], alpha)
                o.k(pts, ws.map { $0 * 2.4 }, P.body, 0.12 * alpha, add: true, soft: 6)
                o.k(pts, [Double](repeating: 1.0, count: pts.count), P.light, 0.5 * alpha, add: true, soft: 1.0)
            }
        }
        if t >= imp {
            let a = t - imp
            if a < 0.5 {
                if ti == 0 { o.f(P.mid, 0.12 * exp(-a * 16)) }
                let r = 24 + 130 * easeOut(a / 0.45); o.r(fx, fy - 2, r, r * 0.28, 6 * (1 - a / 0.5) + 0.6, P.light, 0.8 * (1 - easeIn(a / 0.5)))
                let r2 = 40 + 90 * easeOut(a / 0.35); o.r(cx, cy, r2, r2 * 1.25, 3 * (1 - a / 0.4) + 0.5, P.mid, 0.6 * (1 - easeIn(a / 0.4)))
            }
            for (oi, (R, tilt, _, _)) in ORB.enumerated() {
                let ph = pm(t * 1.1 - Double(oi) * 0.18, 1.0)
                let pts = arcPts(cx, cy, R * cos(tilt * 0.6), R * sin(abs(tilt)) * 1.05 + 2, 0, 6.283, 60, 0)
                o.k(pts, [Double](repeating: 1.1, count: pts.count), P.a2, (0.5 * exp(-ph * 3.5) + 0.14) * fadeout, add: true, soft: 1.2)
            }
            o.g(cx, cy, 80, 110, P.body, 0.1 * fadeout)
            for i in 0..<20 {
                let u = pm(t * 0.35 + frac(i, 1), 1.0), ang = frac(i, 2) * 6.283 + t * 0.5
                o.g(cx + cos(ang) * 80 * frac(i, 3), fy - 6 - u * 190, 7, 7, [P.light, P.a1, P.mid][i % 3], 0.6 * fadeout * sin(Double.pi * u))
            }
        }
        return o.prims
    }

    // MARK: dragon knight: dragon order

    static func dragonOrder(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.order, C = geo.caster, CF = geo.casterFoot, imp = 0.56
        let BEATS = [imp, imp + 0.3, imp + 0.6], fadeout = 1 - smooth((t - 1.85) / 0.3)
        if t < imp && ti == 0 {
            for k in 0..<3 {
                let tap = max(0.0, 1 - abs(t - (0.15 + Double(k) * 0.17)) / 0.06); o.g(C.x, C.y, 44 + 30 * tap, 54 + 30 * tap, P.body, 0.12 + 0.3 * tap)
            }
        }
        for (bi, tb) in BEATS.enumerated() {
            let a = t - tb
            if a < 0 { continue }
            let big = 1.0 + 0.5 * b2d(bi == 2), dbi = Double(bi)
            if a < 0.14 && ti == 0 { o.f(P.mid, (0.1 + 0.08 * dbi) * exp(-a * 24)) }
            for rI in 0..<(ti == 0 ? 3 : 0) {
                let d = Double(rI) * 0.05, tt = a - d
                if tt < 0 { continue }
                let r = (40 + 470 * easeOut(tt / 0.85)) * big, fade = 1 - easeIn(tt / 0.9)
                o.arc(C.x + 20, C.y, r, r * 0.52, -1.15, 1.15, (7.0 - Double(rI) * 1.8) * fade + 0.8, [P.light, P.a1, P.mid][rI], 0.85 * fade)
            }
            if ti == 0 { let r = 20 + 130 * big * easeOut(a / 0.5); o.r(CF.x, CF.y - 2, r, r * 0.27, 6 * (1 - a / 0.55) + 0.6, P.mid, 0.8 * (1 - easeIn(a / 0.55))) }
            for (n, tg) in [(ti, geo.targets[ti])] {
                let hit = a - 0.1 - 0.05 * Double(n)
                if hit < 0 { continue }
                let cx = tg.chest.x, cy = tg.chest.y, fx = tg.foot.x, fy = tg.foot.y
                let R0 = 130 * big, rr = R0 * (1 - easeOut(hit / 0.26)) + 14, al = (1 - easeIn(hit / 0.3)) * smooth(hit / 0.04)
                o.r(cx, cy, rr * 0.8, rr * 1.3, 4.0 * al + 0.5, [P.a1, P.light, P.mid][bi], 0.9 * al)
                o.r(fx, fy - 2, rr * 1.4, rr * 1.4 * 0.27, 3.4 * al + 0.5, P.mid, 0.7 * al)
                if hit < 0.3 {
                    o.g(cx, cy, 70 * (1 - easeIn(hit / 0.3)) + 36, 92 * (1 - easeIn(hit / 0.3)) + 46, P.a1, 0.45 * al * (1 + 0.4 * dbi)); o.g(cx, cy, 24, 32, white, 0.5 * al)
                }
                for i in 0..<10 {
                    let ang = frac(i + 11 * bi, 3) * 6.283, d = (30 + 70 * frac(i + 11 * bi, 4)) * easeOut(hit / 0.4)
                    o.e(cx + cos(ang) * d, cy + sin(ang) * d * 0.8 - 20 * hit, 9, 1.5, ang, [P.a1, P.light, P.a2][i % 3], 0.8 * (1 - easeIn(hit / 0.55)))
                }
            }
        }
        let last = t - BEATS[2]
        for (n, tg) in [(ti, geo.targets[ti])] {
            if last < 0.15 { continue }
            let cx = tg.chest.x, cy = tg.chest.y, ph = pm(t * 2.0 - Double(n) * 0.2, 1.0), env = smooth((last - 0.15) / 0.25) * fadeout
            o.g(cx, cy, 52 + 14 * exp(-ph * 5), 80 + 18 * exp(-ph * 5), P.body, (0.14 + 0.3 * exp(-ph * 5)) * env)
            o.r(cx, cy, 44 + 30 * ph, 70 + 40 * ph, 1.8 * (1 - ph) + 0.4, P.a1, 0.7 * (1 - ph) * env)
            for i in 0..<12 {
                let u = pm(t * 0.5 + frac(i, 1), 1.0), ang = frac(i, 2) * 6.283
                o.g(cx + cos(ang) * 40 * frac(i, 3), tg.foot.y - 6 - u * 150, 7, 7, [P.a1, P.light, P.mid][i % 3], 0.6 * env * sin(Double.pi * u))
            }
        }
        return o.prims
    }

    // MARK: healing (micro, standard, strong)

    static func healMicro(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.heal, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot, fx = foot.x, fy = foot.y, cx = chest.x, cy = chest.y
        let fade = 1 - smooth((t - 1.1) / 0.25)
        let r = 10 + 40 * easeOut(t / 0.6); o.thinRing(fx, fy - 2, r, r * 0.27, 1.5 * (1 - t / 0.7) + 0.4, P.mid, 0.7 * (1 - easeIn(t / 0.7)))
        let pulse = exp(-pow((t - 0.28) / 0.13, 2)); o.g(cx, cy, 60, 74, P.body, 0.4 * pulse); o.g(cx, cy, 18, 22, P.light, 0.6 * pulse)
        o.thinRing(cx, cy, 14 + 40 * easeOut((t - 0.2) / 0.45), 18 + 52 * easeOut((t - 0.2) / 0.45), 1.2, P.light, 0.6 * (1 - easeIn((t - 0.2) / 0.5)) * smooth((t - 0.2) / 0.05))
        for i in 0..<7 {
            let di = Double(i), u = clamp01((t - 0.05 * di) / 1.0)
            if u <= 0 || u >= 1 { continue }
            func pos(_ uu: Double) -> Pt { Pt(fx + (frac(i, 2) - 0.5) * 44 + sin(uu * 5.5 + di * 1.7) * (11 + 9 * frac(i, 3)), fy - 8 - uu * (110 + 50 * frac(i, 4))) }
            let pts = (0..<12).map { q in pos(max(0.0, u - 0.16 * (1 - Double(q) / 11))) }
            let env = pw(sin(Double.pi * u), 0.8) * fade
            o.k(pts, (0..<12).map { q in 0.5 + 3.2 * (Double(q) / 11) }, P.mid, 0.9 * env, add: true, soft: 1.2)
            let p = pos(u), col = [P.light, P.a1, P.mid][i % 3]
            o.g(p.x, p.y, 15, 15, col, 0.7 * env); o.g(p.x, p.y, 4.6, 4.6, white, 1.0 * env)
        }
        return o.prims
    }

    static func healStandard(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.heal, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot, fx = foot.x, fy = foot.y, cx = chest.x, cy = chest.y
        let fade = 1 - smooth((t - 1.45) / 0.3)
        for q in 0..<2 {
            let head = easeOut(clamp01(t / 0.9)), tail = easeIn(clamp01((t - 0.7) / 0.8))
            var pts: [Pt] = [], ws: [Double] = []
            for j in 0..<80 {
                let u = Double(j) / 79
                if u > head || u < tail * 0.9 { continue }
                let ang = Double(q) * Double.pi + u * 11 - t * 3.2, rr = 38 - 8 * u
                pts.append(Pt(fx + cos(ang) * rr, fy - 6 - u * 170 + sin(ang) * rr * 0.3)); ws.append(3.2 * pw(sin(Double.pi * u), 0.6) + 0.6)
            }
            if pts.count > 3 { o.stack(pts, ws, [(3.0, P.body, true, 0.16), (1.0, P.mid, true, 0.6), (0.4, P.light, true, 0.95)], fade) }
        }
        if t > 0.3 {
            let a = t - 0.3
            for k in 0..<2 {
                let d = Double(k) * 0.12, aa = a - d
                if aa >= 0 {
                    let r = 20 + 80 * easeOut(aa / 0.6); o.thinRing(fx, fy - 2, r, r * 0.27, 1.8 * (1 - aa / 0.7) + 0.4, k == 0 ? P.mid : P.a2, 0.75 * (1 - easeIn(aa / 0.7)))
                    o.thinRing(cx, cy, r * 0.6, r * 1.1, 1.2, k == 0 ? P.light : P.mid, 0.5 * (1 - easeIn(aa / 0.7)))
                }
            }
            o.g(cx, cy, 70 * (0.5 + easeOut(a / 0.5)), 100 * (0.5 + easeOut(a / 0.5)), P.body, 0.22 * (1 - easeIn(a / 1.0)))
        }
        for i in 0..<46 {
            let tb = 0.3 + 0.9 * frac(i, 1), tt = t - tb
            if !(0 <= tt && tt < 0.7) { continue }
            let x = fx + (frac(i, 2) - 0.5) * 150, y = cy - 150 + tt * (190 + 60 * frac(i, 3)), k = pw(sin(Double.pi * tt / 0.7), 0.8) * fade
            o.e(x, y, 1.2, 8 + 5 * frac(i, 4), 0, [P.light, P.mid, P.a1][i % 3], 0.8 * k); o.g(x, y, 5, 5, P.mid, 0.4 * k)
        }
        for i in 0..<8 {
            let tb = 0.4 + 0.8 * frac(i, 1), tt = t - tb
            if 0 <= tt && tt < 0.4 {
                let ang = frac(i, 2) * 6.283, x = cx + cos(ang) * 28 * frac(i, 3), y = cy + sin(ang) * 50 * frac(i, 4), k = sin(Double.pi * tt / 0.4) * fade
                o.e(x, y, 11, 1.1, 0, P.light, 0.9 * k); o.e(x, y, 11, 1.1, 1.571, P.light, 0.9 * k); o.g(x, y, 7, 7, P.mid, 0.5 * k)
            }
        }
        return o.prims
    }

    static func healStrong(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.heal, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot, fx = foot.x, fy = foot.y, cx = chest.x, cy = chest.y
        let fade = 1 - smooth((t - 1.85) / 0.4)
        for q in 0..<4 {
            let dq = Double(q), env = smooth((t - 0.1 - 0.06 * dq) / 0.5) * fade
            var pts: [Pt] = [], ws: [Double] = []
            for j in 0..<50 {
                let u = Double(j) / 49
                pts.append(Pt(fx + (dq - 1.5) * 34 + sin(u * 4 + t * 1.6 + dq * 2) * (14 + 12 * u), fy - 4 - u * (150 + 40 * frac(q, 1)))); ws.append(20 * pw(sin(Double.pi * (u * 0.85 + 0.08)), 0.8) + 2)
            }
            o.k(pts, ws, [P.body, P.a2, P.mid, P.body][q], 0.3 * env, add: true, soft: 10)
            o.k(pts, ws.map { $0 * 0.1 + 0.5 }, q % 2 == 0 ? P.light : P.mid, 0.4 * env, add: true, soft: 1.0)
        }
        for (k, tb) in [0.3, 0.62].enumerated() {
            let a = t - tb
            if a >= 0 {
                let r = 14 + 130 * easeOut(a / 0.6)
                o.thinRing(cx, cy, r * 0.9, r * 1.15, 1.8 * (1 - a / 0.65) + 0.4, k == 0 ? P.light : P.mid, 0.8 * (1 - easeIn(a / 0.65)))
                o.thinRing(fx, fy - 2, r * 1.2, r * 1.2 * 0.27, 1.8 * (1 - a / 0.65) + 0.4, P.mid, 0.7 * (1 - easeIn(a / 0.65)))
                o.g(cx, cy, 60 * (1 - easeIn(a / 0.3)) + 30, 80 * (1 - easeIn(a / 0.3)) + 40, k == 1 ? P.a1 : P.body, 0.35 * (1 - easeIn(a / 0.35)))
            }
        }
        if t > 0.3 && t < 1.5 {
            let env = smooth((t - 0.3) / 0.2) * (1 - smooth((t - 1.1) / 0.4))
            for k in 0..<30 {
                let dk = Double(k), ang = dk * 2 * Double.pi / 30 + t * 0.25, L = 70 + 80 * frac(k, 2), s = 1 + 0.08 * sin(t * 4 + dk)
                o.e(cx + cos(ang) * L * s / 2, cy + sin(ang) * L * s / 2 * 0.95, L * s / 2, 1.1, ang, [P.mid, P.light, P.a2, P.mid][k % 4], 0.4 * env)
            }
        }
        if t > 0.3 && ti == 0 { o.f(P.a1, 0.1 * exp(-(t - 0.3) * 14)) }
        for i in 0..<44 {
            let tb = 0.25 + 0.5 * frac(i, 1), tt = t - tb
            if !(0 <= tt && tt < 1.3) { continue }
            let vx = (frac(i, 2) - 0.5) * 120, vy = -(170 + 100 * frac(i, 3))
            let x = fx + vx * tt, y = fy - 10 + vy * tt + 230 * tt * tt, vyn = vy + 460 * tt
            let k = pw(sin(Double.pi * clamp01(tt / 1.3)), 0.6) * fade, col = [P.light, P.mid, P.a1, P.a2][i % 4]
            let sp = hypot(vx, vyn)
            o.e(x - vx * 0.012, y - vyn * 0.012, max(3, sp * 0.02), 1.2, atan2(vyn, vx), col, 0.85 * k); o.g(x, y, 6, 6, col, 0.5 * k); o.g(x, y, 2.4, 2.4, white, 0.9 * k)
        }
        o.g(cx, cy, 80 + 6 * sin(t * 5), 110 + 6 * sin(t * 5), P.body, 0.14 * smooth((t - 0.3) / 0.4) * fade)
        return o.prims
    }

    // MARK: rally (a call that rolls out over every ally and lifts them)

    static func rallyCall(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.rally, C = geo.caster, CF = geo.casterFoot, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot, imp = 0.56
        let fx = foot.x, fy = foot.y, cx = chest.x, cy = chest.y
        if ti == 0 {
            let gat = smooth(t / (imp * 0.9)) * (1 - smooth((t - imp - 0.1) / 0.3))
            o.g(C.x, C.y - 10, 50 * gat + 4, 70 * gat + 4, P.body, 0.35 * gat)
            o.e(C.x, C.y - 70 * gat, 130 * gat + 6, 7, -1.5708, P.mid, 0.8 * gat)
            o.e(C.x, C.y - 70 * gat, 90 * gat + 4, 3, -1.5708, P.light, gat)
            let waveCols = [P.mid, P.a2, P.light]
            for w in 0..<3 {
                let u = (t - imp - 0.16 * Double(w)) / 0.8
                if u > 0 && u < 1 {
                    let r = 30 + 330 * easeOut(u)
                    o.r(CF.x, CF.y - 2, r, r * 0.26, 3.2 * (1 - u) + 0.8, waveCols[w], 0.85 * (1 - easeIn(u)))
                }
            }
            if t >= imp && t < imp + 0.25 { o.f(P.mid, 0.2 * exp(-(t - imp) * 14)) }
        }
        let reach = imp + 0.1 + 0.3 * clamp01(abs(fx - CF.x) / 420.0), tt = t - reach
        if tt >= 0 {
            let env = smooth(tt / 0.18) * (1 - smooth((tt - 1.0) / 0.5)), grow = smooth(tt / 0.25)
            o.g(fx, fy - 2, 70 * env + 4, 20 * env + 2, P.body, 0.5 * env)
            o.e(fx, fy - 90 * grow, 110 * grow + 4, 22, -1.5708, P.body, 0.30 * env)
            o.e(fx, fy - 90 * grow, 110 * grow + 4, 12, -1.5708, P.mid, 0.5 * env)
            o.e(fx, fy - 90 * grow, 108 * grow + 4, 5, -1.5708, P.light, 0.8 * env)
            let r = 14 + 60 * easeOut(tt / 0.4)
            o.r(fx, fy - 2, r, r * 0.3, 2.4 * (1 - easeIn(tt / 0.9)) + 0.8, P.mid, 0.9 * (1 - easeIn(tt / 1.1)))
            o.g(cx, cy, 70 * env + 4, 95 * env + 4, P.body, 0.22 * env)
            o.r(cx, cy - 78, 26 * grow + 2, 8 * grow + 1, 1.6, P.a1, 0.7 * env)
            for k in 0..<3 {
                let u = pm(tt * 0.9 + Double(k) / 3.0, 1.0), y = fy - 20 - u * 130, al = env * sin(Double.pi * u)
                o.e(cx - 8, y + 5, 12, 2.6, -0.75, P.light, al); o.e(cx + 8, y + 5, 12, 2.6, 0.75, P.light, al)
                o.g(cx, y, 16, 12, P.mid, 0.35 * al)
            }
        }
        return o.prims
    }

    // MARK: sweep (one huge crescent swung through every enemy)

    static func sweepArc(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.sweep, C = geo.caster, T = geo.targets[ti].chest, TF = geo.targets[ti].foot, imp = 1.048
        let d: Double = geo.targets[0].chest.x >= C.x ? 1.0 : -1.0
        let far = geo.targets.map { abs($0.chest.x - C.x) }.max() ?? 0, R = max(220.0, far + 90.0), RY = 100.0, ex = C.x + d * 30, ey = C.y + 25
        let post = t - imp
        func pt(_ th: Double, _ k: Double = 1.0) -> Pt { Pt(ex + d * cos(th) * R * k, ey + sin(th) * RY * k) }
        if ti == 0 {
            let gat = smooth(t / (imp * 0.85)) * (1 - smooth(post / 0.15))
            o.g(C.x + d * 26, C.y - 6, 30 * gat + 3, 34 * gat + 3, P.mid, 0.45 * gat)
            o.e(C.x + d * 26, C.y - 6, 48 * gat + 2, 2.2, -0.9 * d, P.light, 0.9 * gat)
            if post >= -0.05 && post < 1.0 {
                let head = lerp(3.4, 6.2, easeOut(clamp01(post / 0.24))), env = 1 - smooth((post - 0.24) / 0.5)
                for echo in 0..<2 {
                    let h = head - 0.35 * Double(echo), k = 1 - 0.07 * Double(echo)
                    var pts: [Pt] = [], ws: [Double] = []
                    for j in 0..<40 {
                        let u = Double(j) / 39.0, th = max(3.4, h - 1.5 * u)
                        pts.append(pt(th, k)); ws.append(26 * pw(1 - u, 0.8) * (0.5 + 0.5 * sin(Double.pi * clamp01((th - 3.4) / 2.8))) + 2)
                    }
                    o.stack(pts, ws, [(2.2, P.deep, true, 0.25), (1.0, P.body, true, 0.55), (0.5, P.mid, true, 0.85), (0.2, P.light, true, 0.95)], env * (echo == 0 ? 1.0 : 0.55))
                }
                let hp = pt(head)
                if post < 0.5 { o.g(hp.x, hp.y, 40, 40, P.body, 0.5 * env); o.g(hp.x, hp.y, 20, 20, P.light, 0.8 * env) }
            }
            if t >= imp && t < imp + 0.25 { o.f(P.mid, 0.22 * exp(-post * 14)) }
        }
        let hit = imp + 0.02 + 0.22 * clamp01(abs(T.x - C.x) / R), hq = t - hit
        if hq >= 0 && hq < 0.7 {
            let k = 1 - easeIn(hq / 0.5)
            o.g(T.x, T.y, 150 * (0.6 + easeOut(hq / 0.2)), 100 * (0.6 + easeOut(hq / 0.2)), P.body, 0.5 * k)
            o.g(T.x, T.y, 60, 50, P.light, 0.8 * (1 - easeIn(hq / 0.18)))
            o.e(T.x, T.y, 90 * easeOut(hq / 0.12), 4, -0.55 * d, P.light, 1 - easeIn(hq / 0.4))
            o.e(T.x, T.y, 70 * easeOut(hq / 0.12), 3, 0.45 * d, P.mid, 1 - easeIn(hq / 0.4))
            let shardCols = [P.light, P.mid, P.a1]
            for j in 0..<10 {
                let jj = j + 31 * ti, a = frac(jj, 3) * 6.2832, r = (30 + 110 * frac(jj, 4)) * easeOut(hq / 0.4)
                o.e(T.x + cos(a) * r, T.y + sin(a) * r * 0.6, 10, 1.6, a, shardCols[j % 3], max(0.0, 1 - hq / 0.6))
            }
            let rr = 20 + 120 * easeOut(hq / 0.5)
            o.r(TF.x, TF.y - 2, rr, rr * 0.26, 2.4 * max(0.0, 1 - hq / 0.6) + 0.6, P.mid, 0.7 * (1 - easeIn(hq / 0.6)))
        }
        return o.prims
    }

    // MARK: blows (one generator, a style per weapon / attacker)

    private static func hitStyle(_ id: String) -> (Pal, String)? {
        switch id {
        case "hitBlade": return (.blade, "blade")
        case "hitGreat": return (.great, "great")
        case "hitBow": return (.bow, "bow")
        case "hitStaff": return (.staff, "staff")
        case "hitClaw": return (.claw, "claw")
        case "hitAmbush": return (.ambush, "ambush")
        case "hitWard": return (.ward, "ward")
        case "hitSlime": return (.goo, "goo")
        case "hitWolf": return (.wolf, "bite")
        case "hitArrowM": return (.goblin, "bow")
        case "hitStone": return (.stone, "crumble")
        case "hitTroll": return (.troll, "slam")
        case "hitDragon": return (.ward, "magic")
        default: return nil
        }
    }

    static func hitEffect(_ id: String, _ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        guard let hs = hitStyle(id) else { return [] }
        var o = Out(); let P = hs.0, st = hs.1, C = geo.caster, T = geo.targets[ti].chest, TF = geo.targets[ti].foot
        let pwr = geo.power, d: Double = T.x >= C.x ? 1.0 : -1.0, k = t - 0.05
        if k < 0 { return [] }
        let ang0 = atan2(T.y - C.y, T.x - C.x), cs = cos(ang0), sn = sin(ang0)
        let S = 0.85 + 0.3 * pwr, fade = 1 - easeIn(k / 0.85)
        o.g(T.x, T.y, 120 * S * (0.5 + easeOut(k / 0.15)), 90 * S * (0.5 + easeOut(k / 0.15)), P.body, 0.55 * (1 - easeIn(k / 0.45)))
        o.g(T.x, T.y, 46 * S, 40 * S, P.light, 0.9 * (1 - easeIn(k / 0.14)))
        o.g(T.x, T.y, 150 * S, 70 * S, P.deep, 0.25 * fade)
        let u = easeOut(k / 0.1)
        switch st {
        case "blade":
            for (ang, ln) in [(-0.7 * d, 1.0), (0.55 * d, 0.8)] {
                o.e(T.x, T.y, 78 * S * u * ln, 4.5 * S, ang, P.light, 1 - easeIn(k / 0.35))
                o.e(T.x, T.y, 90 * S * u * ln, 9 * S, ang, P.body, 0.5 * (1 - easeIn(k / 0.4)))
            }
        case "great":
            for (ang, ln) in [(-0.6 * d, 1.0), (0.4 * d, 0.7), (-1.2 * d, 0.55)] {
                o.e(T.x, T.y, 130 * S * u * ln, 8 * S, ang, P.light, 1 - easeIn(k / 0.4))
                o.e(T.x, T.y, 150 * S * u * ln, 18 * S, ang, P.body, 0.5 * (1 - easeIn(k / 0.5)))
            }
            let r = 40 + 210 * S * easeOut(k / 0.45)
            o.r(T.x, T.y, r, r, 3.0 * (1 - k / 0.6) + 0.6, P.mid, 0.8 * (1 - easeIn(k / 0.6)))
            for j in 0..<5 {
                let a = Double(j - 2) * 0.5 + (d > 0 ? 0.0 : Double.pi)
                o.e(TF.x + cos(a) * 60 * u, TF.y - 2 + sin(a) * 12, 70 * S * u, 2.2, a * 0.3, P.a1, 0.8 * fade)
            }
        case "bow":
            let a = atan2(T.y - C.y, T.x - C.x), L = 150 * S * u
            o.e(T.x - cos(a) * L * 0.5, T.y - sin(a) * L * 0.5, L * 0.5 + 1, 3.0, a, P.light, 1 - easeIn(k / 0.3))
            o.e(T.x - cos(a) * L * 0.5, T.y - sin(a) * L * 0.5, L * 0.5 + 1, 8.0, a, P.body, 0.5 * (1 - easeIn(k / 0.4)))
            for q in 0..<2 { o.e(T.x, T.y, 40 * S * u, 2.0, Double(q) * 1.5708, P.light, 1 - easeIn(k / 0.4)) }
        case "staff":
            for w in 0..<2 {
                let uu = (k - 0.08 * Double(w)) / 0.45
                if uu > 0 && uu < 1 {
                    let r = 20 + 120 * S * easeOut(uu)
                    o.r(T.x, T.y, r, r, 2.6 * (1 - uu) + 0.6, w == 0 ? P.mid : P.a2, 0.9 * (1 - easeIn(uu)))
                }
            }
            for q in 0..<6 {
                let a = Double(q) * 1.0472 + k * 3, rr = 34 * S * u
                o.e(T.x + cos(a) * rr, T.y + sin(a) * rr, 14 * S, 1.6, a, P.light, 1 - easeIn(k / 0.45))
            }
        case "claw":
            for q in 0..<3 {
                let kk = k - 0.035 * Double(q)
                if kk < 0 { continue }
                let off = Double(q - 1) * 20, ang = 0.9 * d, ox = -sin(ang) * off, oy = cos(ang) * off, uq = easeOut(kk / 0.09)
                o.e(T.x + ox, T.y + oy, 95 * S * uq, 4.0 * S, ang, P.light, 1 - easeIn(kk / 0.35))
                o.e(T.x + ox, T.y + oy, 105 * S * uq, 9.0 * S, ang, P.body, 0.55 * (1 - easeIn(kk / 0.4)))
            }
        case "ambush":
            for (si, ang) in [-0.35 * d, 0.35 * d].enumerated() {
                let kk = k - 0.05 * Double(si)
                if kk < 0 { continue }
                let uq = easeOut(kk / 0.08)
                o.e(T.x, T.y, 120 * S * uq, 3.2 * S, ang, P.light, 1 - easeIn(kk / 0.35))
                o.e(T.x, T.y, 135 * S * uq, 8.0 * S, ang, P.body, 0.5 * (1 - easeIn(kk / 0.4)))
            }
            for q in 0..<6 {
                let a = Double(q) * 1.0472 + 0.5, rr = (30 + 50 * frac(q, 2)) * S * u
                o.e(T.x + cos(a) * rr, T.y + sin(a) * rr * 0.8, 9 * S, 1.6, a, P.a1, 1 - easeIn(k / 0.5))
            }
        case "goo":
            let e = easeOut(k / 0.2)
            o.r(T.x, TF.y - 2, 70 * S * e, 26 * S * e, 4 * max(0.0, 1 - k / 0.4) + 0.8, P.mid, 0.9 * (1 - easeIn(k / 0.45)))
            for j in 0..<7 {
                let jj = j + 31 * ti, a = ang0 + (frac(jj, 3) - 0.5) * 2.2, r = (40 + 110 * frac(jj, 4)) * S * easeOut(k / 0.3)
                let bx = T.x + cos(a) * r, by = T.y + sin(a) * r * 0.5 + 120 * k * k * (1 + frac(jj, 6)), sz = (10 + 10 * frac(jj, 5)) * S, al = max(0.0, 1 - k / 0.7)
                o.g(bx, by, sz, sz, P.body, al); o.g(bx, by, sz * 0.5, sz * 0.5, P.light, al * 0.8)
            }
            for j in 0..<5 { o.e(T.x + (frac(j, 2) - 0.5) * 50, T.y - 10 + 140 * k * (0.6 + frac(j, 3)), 10, 2.0, 1.5708, P.mid, max(0.0, 1 - k / 0.6)) }
        case "bite":
            let c = easeOut(k / 0.08), al = 1 - easeIn(k / 0.35)
            o.arc(T.x, T.y - 34 * (1 - c) - 6, 46 * S, 30 * S, Double.pi + 0.4, 2 * Double.pi - 0.4, 4.0 * S, P.light, al)
            o.arc(T.x, T.y + 34 * (1 - c) + 6, 46 * S, 30 * S, 0.4, Double.pi - 0.4, 4.0 * S, P.light, al)
            for q in 0..<4 {
                o.e(T.x + (Double(q) - 1.5) * 16, T.y - 12 - 22 * (1 - c), 9 * S, 1.8, 1.5708, P.light, al); o.e(T.x + (Double(q) - 1.5) * 16, T.y + 12 + 22 * (1 - c), 9 * S, 1.8, -1.5708, P.light, al)
            }
            for q in 0..<3 {
                let kk = k - 0.03 * Double(q)
                if kk < 0 { continue }
                let off = Double(q - 1) * 16
                o.e(T.x - sin(0.9 * d) * off, T.y + cos(0.9 * d) * off, 70 * S * easeOut(kk / 0.09), 3.0 * S, 0.9 * d, P.a1, 1 - easeIn(kk / 0.35))
            }
        case "crumble":
            let chunkCols = [P.mid, P.a2]
            for j in 0..<8 {
                let jj = j + 31 * ti, a = ang0 + (frac(jj, 3) - 0.5) * 1.6, r = (30 + 120 * frac(jj, 4)) * S * easeOut(k / 0.4)
                o.e(T.x + cos(a) * r, T.y + sin(a) * r * 0.6 + 220 * k * k * frac(jj, 6), 11 + 7 * frac(jj, 5), 6 + 3 * frac(jj, 5), k * (4 + 6 * frac(jj, 2)) + Double(j), chunkCols[j % 2], max(0.0, 1 - k / 0.8))
            }
            for j in 0..<4 { o.g(T.x + (frac(j, 2) - 0.5) * 80, T.y + 10 - 60 * k * (0.5 + frac(j, 3)), 34 + 12 * frac(j, 4), 26 + 10 * frac(j, 4), P.deep, 0.4 * max(0.0, 1 - k / 0.7)) }
            for j in 0..<6 {
                let a = Double(j - 2) * 0.4 - 0.2 + (d > 0 ? 0.0 : Double.pi), r = (80 + 90 * frac(j, 4)) * easeOut(k / 0.3)
                o.e(TF.x + cos(a) * r * 0.5, TF.y - 2 + sin(a) * 10, r * 0.5 + 1, 1.6, a * 0.15, P.a1, max(0.0, 1 - k / 0.7))
            }
            let r = 40 + 170 * S * easeOut(k / 0.4)
            o.r(TF.x, TF.y - 2, r, r * 0.26, 4.0 * max(0.0, 1 - k / 0.5) + 0.6, P.mid, 0.8 * (1 - easeIn(k / 0.5)))
        case "slam":
            let ringCols = [P.mid, P.light], chunkCols = [P.mid, P.a2]
            for w in 0..<2 {
                let uu = (k - 0.08 * Double(w)) / 0.6
                if uu > 0 && uu < 1 {
                    let R = 40 + 300 * S * easeOut(uu)
                    o.r(TF.x, TF.y - 2, R, R * 0.24, 6.0 * (1 - uu) + 1.0, ringCols[w], 0.9 * (1 - easeIn(uu)))
                }
            }
            o.e(T.x, T.y - 20, 150 * u, 22 * S, -1.5708, P.body, 0.6 * (1 - easeIn(k / 0.4))); o.e(T.x, T.y - 20, 140 * u, 7, -1.5708, P.light, 1 - easeIn(k / 0.3))
            for j in 0..<14 { o.g(TF.x + (frac(j, 2) - 0.5) * 160, TF.y - 120 * k * (0.5 + frac(j, 3)), 24 + 10 * frac(j, 4), 20 + 8 * frac(j, 4), P.deep, 0.45 * max(0.0, 1 - k / 0.8)) }
            for j in 0..<8 {
                let jj = j + 31 * ti, a = -Double.pi / 2 + (frac(jj, 3) - 0.5) * 2.4, r = (60 + 150 * frac(jj, 4)) * S * easeOut(k / 0.45)
                o.e(TF.x + cos(a) * r, TF.y + sin(a) * r + 260 * k * k * frac(jj, 6), 14 + 8 * frac(jj, 5), 8 + 3 * frac(jj, 5), k * (3 + 6 * frac(jj, 2)) + Double(j), chunkCols[j % 2], max(0.0, 1 - k / 0.85))
            }
        case "magic":
            let ringCols = [P.mid, P.light, P.a2]
            for w in 0..<3 {
                let uu = (k - 0.07 * Double(w)) / 0.5
                if uu > 0 && uu < 1 {
                    let r = 20 + 150 * S * easeOut(uu)
                    o.r(T.x, T.y, r, r, 3.0 * (1 - uu) + 0.6, ringCols[w], 0.9 * (1 - easeIn(uu)))
                }
            }
            for q in 0..<12 {
                let a = Double(q) * 0.5236 + k, L2 = 110 * S * easeOut(k / 0.15)
                o.e(T.x + cos(a) * L2 * 0.5, T.y + sin(a) * L2 * 0.5, L2 * 0.5 + 1, 2.2, a, P.light, 1 - easeIn(k / 0.4))
            }
        default:
            for w in 0..<2 {
                let uu = (k - 0.07 * Double(w)) / 0.5
                if uu > 0 && uu < 1 {
                    let r = 30 + 90 * easeOut(uu)
                    o.r(T.x, T.y, r * 0.8, r, 2.4 * (1 - uu) + 0.6, w == 0 ? P.mid : P.light, 0.9 * (1 - easeIn(uu)))
                }
            }
            for q in 0..<6 {
                let a0 = k * 2 + Double(q) * 1.0472
                o.arc(T.x, T.y, 54 * S, 70 * S, a0, a0 + 0.5, 3.0, P.light, 0.8 * (1 - easeIn(k / 0.5)))
            }
        }
        let shardCols = [P.light, P.mid, P.a1]
        o.e(T.x - cs * 50 * S * u, T.y - sn * 50 * S * u, 140 * S * u + 1, 3.2 * S, ang0, P.light, 1 - easeIn(k / 0.25))
        for q in 0..<8 {
            let a = Double(q) * 0.7854 + 0.2
            o.e(T.x + cos(a) * 22 * S, T.y + sin(a) * 22 * S * 0.8, 16 * S * (1 - easeIn(k / 0.14)) + 0.4, 1.4, a, P.light, 1 - easeIn(k / 0.14))
        }
        for j in 0..<Int(16 + 10 * pwr) {
            let jj = j + 31 * ti, a = ang0 + (frac(jj, 3) - 0.5) * 1.9, r = (50 + 210 * frac(jj, 4)) * S * easeOut(k / 0.4)
            o.e(T.x + cos(a) * r, T.y + sin(a) * r * 0.7 + 60 * k * k * frac(jj, 6), (14 + 24 * frac(jj, 5)) * S * (1 - 0.5 * easeIn(k / 0.5)), 2.2, a, shardCols[j % 3], max(0.0, 1 - k / 0.6))
        }
        for j in 0..<4 {
            let jj = j + 50, a = frac(jj, 3) * 6.2832, r = (20 + 60 * frac(jj, 4)) * S * easeOut(k / 0.35)
            o.g(T.x + cos(a) * r, T.y + sin(a) * r * 0.6, 5 * S, 5 * S, P.light, max(0.0, 1 - k / 0.5))
        }
        for j in 0..<6 {
            let x = TF.x + cs * (30 + 120 * frac(j, 2)) * easeOut(k / 0.5)
            o.g(x, TF.y - 4 - 10 * frac(j, 3), 14 * S, 7 * S, P.deep, 0.35 * max(0.0, 1 - k / 0.6))
        }
        let rr = 20 + 100 * S * easeOut(k / 0.4)
        o.r(TF.x, TF.y - 2, rr, rr * 0.26, 2.4 * max(0.0, 1 - k / 0.5) + 0.6, P.mid, 0.6 * fade)
        return o.prims
    }

    // MARK: natural 20 (the roll that ends the fight)

    static func natural20(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.gold, T = geo.targets[ti].chest, TF = geo.targets[ti].foot
        if ti == 0 {
            o.f(RGB(255, 255, 255), 0.95 * exp(-t * 8))
            if t >= 0.1 { o.f(P.mid, 0.5 * exp(-(t - 0.1) * 6)) }
        }
        let env = smooth(t / 0.12) * (1 - smooth((t - 1.5) / 1.0)), grow = smooth(t / 0.3)
        o.e(T.x, TF.y - 190, 420, 46 * env + 0.4, -1.5708, P.body, 0.55 * env)
        o.e(T.x, TF.y - 190, 420, 14 * env + 0.4, -1.5708, P.light, 0.95 * env)
        o.g(T.x, T.y, 300 * (0.4 + easeOut(t / 0.2)), 240 * (0.4 + easeOut(t / 0.2)), P.body, 0.6 * (1 - easeIn(t / 1.4)))
        o.g(T.x, T.y, 110, 100, P.light, 0.95 * (1 - easeIn(t / 0.5)))
        let rayCols = [P.light, P.mid, P.a1]
        for i in 0..<28 {
            let a = Double(i) * 6.2832 / 28 + 0.25 * t * (i % 2 != 0 ? 1.0 : -1.0), L = (180 + 220 * frac(i, 3)) * easeOut(t / 0.22) * (1 - easeIn((t - 0.15) / 1.6))
            if L <= 2 { continue }
            o.e(T.x + cos(a) * L * 0.5, T.y + sin(a) * L * 0.5, L * 0.5, 3 + 3 * frac(i, 5), a, rayCols[i % 3], 0.85 * (1 - easeIn(t / 1.8)))
        }
        let waveCols = [P.light, P.mid, P.a1, P.body]
        for w in 0..<4 {
            let u = (t - 0.06 * Double(w)) / 1.0
            if u > 0 && u < 1 {
                let R = 40 + 560 * easeOut(u), col = waveCols[w]
                o.r(T.x, T.y, R, R, 6.0 * (1 - u) + 1.0, col, 0.9 * (1 - easeIn(u)))
                o.r(T.x, TF.y - 2, R * 1.4, R * 1.4 * 0.24, 5.0 * (1 - u) + 1.0, col, 0.8 * (1 - easeIn(u)))
            }
        }
        o.r(T.x, T.y - 120, 90 * grow + 1, 28 * grow + 1, 3.0, P.a1, 0.9 * env)
        o.r(T.x, T.y - 120, 62 * grow + 1, 18 * grow + 1, 1.6, P.mid, 0.8 * env)
        for i in 0..<24 {
            let u = (t - 0.1 - 0.4 * frac(i, 2)) / 1.2
            if u > 0 && u < 1 { o.e(T.x + (frac(i, 3) - 0.5) * 120, TF.y - u * (260 + 160 * frac(i, 4)), 14, 2.0, -1.5708, P.light, 0.9 * (1 - u)) }
        }
        return o.prims
    }

    // MARK: shield dome (a shell of light closes around the unit)

    static func shieldDome(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.ward, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot, imp = 0.46
        let fx = foot.x, fy = foot.y, cx = chest.x, cy = chest.y
        let gr = smooth(t / 0.25) * (1 - smooth((t - 1.2) / 0.3))
        o.g(fx, fy - 2, 90 * gr + 4, 24 * gr + 2, P.body, 0.45 * gr)
        let ringCols = [P.mid, P.light, P.a2], scales = [1.0, 0.72, 0.45]
        for ri in 0..<3 {
            let e = 0.4 + 0.6 * easeOut(t / 0.4)
            o.r(fx, fy - 2, 70 * scales[ri] * e, 70 * scales[ri] * 0.28 * e, 2.2 - 0.5 * Double(ri), ringCols[ri], 0.8 * gr)
        }
        if t >= imp - 0.05 {
            let env = smooth((t - imp + 0.05) / 0.2) * (1 - smooth((t - 1.2) / 0.3))
            if ti == 0 && t >= imp - 0.05 && t < imp + 0.2 { o.f(P.mid, 0.14 * (1 - (t - imp + 0.05) / 0.25)) }
            for q in 0..<10 {
                let ph = frac(q + 20 * ti, 1), a = ph * 6.2832 + t * 1.5, uu = pm(t * 0.6 + ph, 1.0)
                o.e(cx + cos(a) * 60, cy + 80 - uu * 170, 8, 1.4, -1.5708, P.light, env * sin(Double.pi * uu))
            }
        }
        return o.prims
    }

    // MARK: the shield itself (one shell that is generated, stands, blocks and breaks)

    static func shieldShell(_ t0: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.ward, cx = geo.targets[ti].chest.x, cy = geo.targets[ti].chest.y, fx = geo.targets[ti].foot.x, fy = geo.targets[ti].foot.y
        let L = min(1.6, max(0.2, geo.power)), hitAge = geo.hitAge, ha = geo.hitAngle, t = max(0.0, t0)
        let ry0 = max(70.0, (fy - cy) * 1.55), rx0 = ry0 * 0.72 * geo.wide, ccy = fy - ry0 * 0.92
        let g = easeOut(t / 0.5), over = 1 + 0.1 * sin(min(1.0, t / 0.5) * Double.pi), sc = (0.25 + 0.75 * g) * over
        let RX = rx0 * sc, RY = ry0 * sc
        let A = smooth(t / 0.25) * (0.55 + 0.45 * min(1.0, L)), flick = L >= 0.4 ? 1.0 : 0.75 + 0.25 * sin(t * 23)
        o.g(cx, ccy, RX * 1.25, RY * 1.2, P.body, 0.24 * A)
        o.r(cx, ccy, RX, RY, 2.8, P.mid, 1.0 * A * flick); o.r(cx, ccy, RX * 0.94, RY * 0.94, 1.1, P.light, 0.6 * A)
        for q in 0..<4 {
            let a0 = t * 0.9 + Double(q) * 1.5708
            o.arc(cx, ccy, RX, RY, a0, a0 + 0.5, 3.4, P.light, 0.8 * A * (0.6 + 0.4 * sin(t * 3 + Double(q))))
        }
        o.r(cx, ccy, RX, RY * 0.3, 1.2, P.a2, 0.45 * A, 0.3 * sin(t * 0.7))
        for q in 0..<6 {
            let ph = frac(q + 8 * ti, 1), uu = pm(t * 0.4 + ph, 1.0)
            o.e(cx + cos(ph * 6.2832 + t * 0.8) * RX * 0.8, ccy + RY * 0.7 - uu * RY * 1.4, 8, 1.3, -1.5708, P.light, A * 0.8 * sin(Double.pi * uu))
        }
        o.r(fx, fy - 2, RX * 0.9, RX * 0.9 * 0.26, 1.6, P.mid, 0.5 * A); o.g(fx, fy - 2, RX, 16, P.body, 0.25 * A)
        if t < 0.7 {
            let u = t / 0.7
            o.r(cx, ccy, RX * (1 + 0.5 * u), RY * (1 + 0.5 * u), 3.0 * (1 - u) + 0.5, P.light, 0.8 * (1 - u))
            for q in 0..<10 {
                let ph = frac(q + 8 * ti, 2), a = ph * 6.2832
                o.e(cx + cos(a) * RX * 0.95, ccy + sin(a) * RY * 0.95 - u * 50, 9, 1.4, -1.5708, P.light, (1 - u) * 0.9)
            }
        }
        if hitAge >= 0 && hitAge < 0.7 {
            let k = hitAge, hx = cx + cos(ha) * RX, hy = ccy + sin(ha) * RY
            o.g(hx, hy, 50 * (1 - 0.4 * easeOut(k / 0.4)), 50 * (1 - 0.4 * easeOut(k / 0.4)), P.light, 0.9 * (1 - easeIn(k / 0.35)))
            for w in 0..<3 {
                let sp = 0.3 + 1.4 * easeOut((k - 0.05 * Double(w)) / 0.5)
                o.arc(cx, ccy, RX * (1 + 0.03 * Double(w)), RY * (1 + 0.03 * Double(w)), ha - sp, ha + sp, 3.0 * (1 - k / 0.6) + 0.8, P.mid, 0.9 * (1 - easeIn((k - 0.05 * Double(w)) / 0.55)))
            }
            o.r(cx, ccy, RX, RY, 5.0, P.light, 0.6 * (1 - easeIn(k / 0.3)))
            for j in 0..<8 {
                let a = ha + (frac(j, 3) - 0.5) * 1.6, r = (20 + 90 * frac(j, 4)) * easeOut(k / 0.3)
                o.e(hx + cos(a) * r, hy + sin(a) * r, 10, 1.6, a, P.light, max(0.0, 1 - k / 0.45))
            }
        }
        if L < 0.45 {
            let warn = min(1.0, (0.45 - L) / 0.25)
            o.r(cx, ccy, RX, RY, 4.5, RGB(255, 170, 90), 0.9 * A * warn * (0.5 + 0.5 * sin(t * 19)))
            for q in 0..<8 {
                let ac = frac(q + 3 * ti, 2) * 6.2832 + Double(q) * 0.4, sx = cx + cos(ac) * RX, sy = ccy + sin(ac) * RY
                var pts: [Pt] = [], ws: [Double] = []
                for j in 0..<5 {
                    let u = Double(j) / 4.0, jit = (frac(q * 7 + j, 3) - 0.5) * 16 * (j > 0 ? 1.0 : 0.0)
                    pts.append(Pt(sx - cos(ac) * RX * 0.6 * u - sin(ac) * jit, sy - sin(ac) * RY * 0.6 * u + cos(ac) * jit)); ws.append(3.4 * (1 - u) + 0.8)
                }
                let al = A * (0.75 + 0.25 * sin(t * 13 + Double(q)))
                o.k(pts, ws.map { $0 * 2.4 }, P.mid, 0.35 * al, add: true, soft: 1.2); o.k(pts, ws, P.light, al, add: true, soft: 1.2)
            }
            for q in 0..<4 {
                let ac = frac(q + 9, 4) * 6.2832, u = pm(t * 1.3 + frac(q, 4), 1.0)
                o.e(cx + cos(ac) * RX, ccy + sin(ac) * RY + u * 60, 6, 2.0, u * 6, P.light, (1 - u) * 0.8 * A)
            }
        }
        return o.prims
    }

    // MARK: projectiles (arrows and orbs with a direction, a trail and a launch)

    private static func projSpec(_ id: String) -> (Pal, Bool, Double, Double)? {
        switch id {
        case "projBow": return (.bow, true, 0.0, 0.19)
        case "projStaff": return (.staff, false, 0.49, 0.21)
        case "projArcher": return (.claw, true, 0.0, 0.22)
        case "projDragon": return (.ward, false, 0.0, 0.22)
        default: return nil
        }
    }

    static func projectile(_ id: String, _ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        guard ti == 0, let ps = projSpec(id) else { return [] }
        var o = Out(); let P = ps.0, isArrow = ps.1, L = ps.2, F = ps.3, C = geo.caster, T = geo.targets[0].chest
        let cols = [P.light, P.mid, P.a1]
        func path(_ u: Double) -> (Double, Double) { (lerp(C.x, T.x, u), lerp(C.y, T.y, u) - (isArrow ? 6.0 : 40.0) * sin(Double.pi * u)) }
        let u = clamp01((t - L) / F)
        if L > 0 && t < L + 0.05 {
            let ch = smooth(t / L), fade = 1 - smooth((t - L) / 0.05)
            o.g(C.x, C.y, 10 + 34 * ch, 10 + 34 * ch, P.body, 0.5 * ch * fade); o.g(C.x, C.y, 5 + 14 * ch, 5 + 14 * ch, P.light, 0.9 * ch * fade)
            o.arc(C.x, C.y, 18 + 10 * ch, 18 + 10 * ch, t * 6, t * 6 + 3.4, 1.6, P.light, 0.8 * ch * fade)
            for j in 0..<14 {
                let e = smooth((t - 0.03 - 0.25 * L * frac(j, 3)) / (L * 0.85))
                if e > 0 && e < 1 {
                    let a = frac(j, 1) * 6.2832 + t * 3, r = (70 + 60 * frac(j, 2)) * pw(1 - e, 1.4)
                    o.g(C.x + cos(a) * r, C.y + sin(a) * r * 0.7, 6, 6, cols[j % 3], 0.8 * smooth(e * 5))
                }
            }
        }
        if t >= L {
            let mf = t - L
            if mf < 0.15 {
                let q = 1 - mf / 0.15
                o.g(C.x, C.y, 40 * q + 8, 40 * q + 8, P.light, 0.8 * q); o.r(C.x, C.y, 12 + 40 * (1 - q), 12 + 40 * (1 - q), 2.0 * q + 0.5, P.mid, 0.7 * q)
            }
            if t < L + F + 0.12 {
                let (hx, hy) = path(u), (x1, y1) = path(clamp01(u - 0.02)), (x2, y2) = path(clamp01(u + 0.02)), ang = atan2(y2 - y1, x2 - x1)
                let fade = 1 - smooth((t - L - F) / 0.12), ca = cos(ang), sa = sin(ang)
                var pts: [Pt] = [], ws: [Double] = []
                for i in stride(from: 24, through: 0, by: -1) {
                    let tt = t - Double(i) * 0.006
                    if tt < L { continue }
                    let (x, y) = path(clamp01((tt - L) / F)), q = Double(i) / 24.0
                    pts.append(Pt(x, y)); ws.append((isArrow ? 5.0 : 11.0) * pw(1 - q, 0.9) + 0.8)
                }
                if pts.count > 3 { o.stack(pts, ws, [(2.2, P.deep, true, 0.25), (1.0, P.body, true, 0.6), (0.5, P.mid, true, 0.85), (0.2, P.light, true, 0.95)], fade) }
                if isArrow {
                    o.e(hx - ca * 20, hy - sa * 20, 22, 2.2, ang, P.light, fade); o.e(hx - ca * 20, hy - sa * 20, 26, 6.0, ang, P.body, 0.5 * fade)
                    o.g(hx, hy, 10, 10, P.light, 0.9 * fade)
                    for q in 0..<3 { let off = Double(q - 1) * 7; o.e(hx - ca * 34 - sa * off, hy - sa * 34 + ca * off, 26, 1.1, ang, P.mid, 0.5 * fade) }
                } else {
                    o.g(hx, hy, 30, 30, P.body, 0.55 * fade); o.g(hx, hy, 15, 15, P.light, 0.95 * fade)
                    for q in 0..<2 { let a0 = t * 9 + Double(q) * Double.pi; o.arc(hx, hy, 16, 16, a0, a0 + 2.2, 2.0, q == 0 ? P.light : P.a2, 0.85 * fade) }
                    for j in 0..<8 {
                        let (x, y) = path(clamp01(u - 0.08 * Double(j) / 8.0)), w = sin(t * 30 + Double(j) * 1.7) * 10 * (Double(j) / 8.0)
                        o.g(x - sa * w, y + ca * w, 5, 5, cols[j % 3], 0.6 * (1 - Double(j) / 8.0) * fade)
                    }
                }
            }
        }
        return o.prims
    }

    // MARK: shield break (the shell bursts apart and its plates are thrown along the blow)

    static func shieldBreak(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.ward, C = geo.caster, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot
        let cx = chest.x, cy = chest.y, fx = foot.x, fy = foot.y, k = t - 0.03
        if k < 0 { return [] }
        let S = 0.85 + 0.3 * geo.power, ang0 = atan2(cy - C.y, cx - C.x), cs = cos(ang0), sn = sin(ang0)
        o.g(cx, cy, 130 * S * (0.5 + easeOut(k / 0.12)), 150 * S * (0.5 + easeOut(k / 0.12)), P.body, 0.6 * (1 - easeIn(k / 0.35)))
        o.g(cx, cy, 60, 70, P.light, 0.9 * (1 - easeIn(k / 0.12)))
        o.r(cx, cy, 64 + 110 * easeOut(k / 0.3), 94 + 140 * easeOut(k / 0.3), 3.5 * (1 - k / 0.45) + 0.6, P.mid, 0.9 * (1 - easeIn(k / 0.45)))
        o.r(cx, cy, 58 + 80 * easeOut(k / 0.3), 88 + 100 * easeOut(k / 0.3), 1.4, P.light, 0.7 * (1 - easeIn(k / 0.35)))
        for j in 0..<14 {
            let a0 = Double(j) * 6.2832 / 14 + 0.1 * frac(j, 2), rad = 1 + 1.6 * easeOut(k / 0.55), sp = easeOut(k / 0.55) * (0.4 + frac(j, 3)), spin = a0 + k * (2 + 4 * frac(j, 5))
            o.arc(cx + cs * 130 * sp, cy + sn * 130 * sp + 90 * k * k * frac(j, 4), 64 * rad, 94 * rad, spin, spin + 0.38, 3.0 * (1 - easeIn(k / 0.6)) + 0.6, P.light, max(0.0, 1 - k / 0.65))
        }
        let shardCols = [P.light, P.mid, P.a2]
        for j in 0..<16 {
            let jj = j + 31 * ti, a = ang0 + (frac(jj, 3) - 0.5) * 2.4, r = (60 + 200 * frac(jj, 4)) * S * easeOut(k / 0.45)
            o.e(cx + cos(a) * r, cy + sin(a) * r * 0.7 + 70 * k * k * frac(jj, 6), (10 + 14 * frac(jj, 5)) * S, 1.6, a, shardCols[j % 3], max(0.0, 1 - k / 0.65))
        }
        o.e(cx - cs * 40 * S, cy - sn * 40 * S, 110 * S * easeOut(k / 0.1) + 1, 2.6 * S, ang0, P.light, 1 - easeIn(k / 0.3))
        let rr = 20 + 130 * S * easeOut(k / 0.45)
        o.r(fx, fy - 2, rr, rr * 0.26, 2.4 * max(0.0, 1 - k / 0.5) + 0.6, P.mid, 0.6 * (1 - easeIn(k / 0.8)))
        o.g(fx, fy - 2, 80, 18, P.deep, 0.3 * (1 - easeIn(k / 1.0)))
        return o.prims
    }

    // MARK: monster death (the body comes apart in the way of its species)

    private static func deathStyle(_ id: String) -> (Pal, String) {
        switch id {
        case "deathSlime": return (.goo, "goo")
        case "deathWolf": return (.wolf, "dust")
        case "deathGoblin": return (.goblin, "dust")
        case "deathStone": return (.stone, "crumble")
        case "deathTroll": return (.troll, "dust")
        case "deathDragon": return (.ward, "rise")
        default: return (.dust, "dust")
        }
    }

    static func deathEffect(_ id: String, _ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let ds = deathStyle(id), P = ds.0, mode = ds.1, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot
        let cx = chest.x, cy = chest.y, fx = foot.x, fy = foot.y, hgt = max(40.0, (fy - cy) * 2.0), wid = hgt * 0.7
        o.g(cx, cy, 100 * (0.5 + easeOut(t / 0.2)), 100 * (0.5 + easeOut(t / 0.2)), P.body, 0.5 * (1 - easeIn(t / 0.5)))
        o.g(cx, cy, 40, 40, P.light, 0.8 * (1 - easeIn(t / 0.2)))
        o.g(fx, fy - 2, 90, 20, P.deep, 0.25 * (1 - easeIn(t / 1.6)))
        let cols = [P.light, P.mid, P.a2]
        switch mode {
        case "dust":
            for i in 0..<Int(52 + 20 * geo.power) {
                let hy = frac(i, 2), born = 0.04 + 0.55 * frac(i, 1) * (1 - 0.5 * hy), tt = t - born, life = 0.9 + 0.6 * frac(i, 3)
                if !(tt >= 0 && tt < life) { continue }
                let x0 = cx + (frac(i, 4) - 0.5) * wid, y0 = fy - hy * hgt
                let drift = (60 + 200 * frac(i, 5)) * easeOut(tt / 0.9) * (0.6 + 0.8 * hy)
                let x = x0 + drift, y = y0 - 40 * tt * (0.4 + frac(i, 6)) + 9 * sin(tt * 5 + Double(i))
                let vx = 200 * (0.6 + 0.8 * hy) * (1 - tt / life) + 40, vy = -40.0, a = pw(1 - tt / life, 0.8) * smooth(tt / 0.05)
                o.e(x, y, 22 + 24 * frac(i, 7), 2.4 + 1.6 * frac(i, 8), atan2(vy, vx), cols[i % 3], a * 0.95); o.g(x, y, 9, 9, P.body, a * 0.4)
            }
            for q in 0..<6 {
                let tt = t - 0.1 - 0.1 * Double(q)
                if tt > 0 && tt < 0.8 {
                    let u = easeOut(tt / 0.8)
                    o.e(cx + 40 + 220 * u, fy - (Double(q) + 0.5) * hgt / 6, 40 + 30 * frac(q, 2), 1.2, 0.0, P.light, 0.5 * (1 - tt / 0.8))
                }
            }
        case "goo":
            for i in 0..<22 {
                let tt = t - 0.03 - 0.12 * frac(i, 1), life = 1.0 + 0.4 * frac(i, 3)
                if !(tt >= 0 && tt < life) { continue }
                let a = -1.5708 + (frac(i, 4) - 0.5) * 3.4, sp = 80 + 160 * frac(i, 5)
                let x = cx + (frac(i, 6) - 0.3) * 30 + cos(a) * sp * easeOut(tt / 0.5) + 60 * tt
                var y = cy + sin(a) * sp * easeOut(tt / 0.5) + 300 * tt * tt * (0.5 + frac(i, 7))
                y = min(y, fy - 2)
                let sz = 9 + 12 * frac(i, 8), al = pw(1 - tt / life, 0.6) * smooth(tt / 0.04)
                o.g(x, y, sz, sz, P.body, al); o.g(x, y, sz * 0.5, sz * 0.5, P.light, al * 0.8)
            }
            o.g(fx + 20, fy - 2, 50 + 110 * easeOut(t / 0.8), 12 + 14 * easeOut(t / 0.8), P.body, 0.55 * (1 - easeIn((t - 0.3) / 1.4)))
        case "crumble":
            let chunkCols = [P.mid, P.a2, P.body]
            for i in 0..<16 {
                let tt = t - 0.04 - 0.25 * frac(i, 1), life = 1.3
                if !(tt >= 0 && tt < life) { continue }
                let x0 = cx + (frac(i, 4) - 0.5) * wid, y0 = fy - frac(i, 2) * hgt
                let x = x0 + (frac(i, 5) - 0.3) * 60 * easeOut(tt / 0.6) + 60 * tt, y = min(fy - 3, y0 + 300 * tt * tt * (0.6 + frac(i, 6)))
                let al = pw(1 - tt / life, 0.6)
                o.e(x, y, 11 + 8 * frac(i, 7), 6 + 4 * frac(i, 8), tt * (3 + 5 * frac(i, 2)) + Double(i), chunkCols[i % 3], al)
                if y >= fy - 4 { o.g(x, fy - 6, 22, 12, P.deep, 0.35 * al) }
            }
            for q in 0..<5 {
                let tt = t - 0.15 * Double(q)
                if tt > 0 && tt < 1.0 { o.g(cx + (frac(q, 2) - 0.5) * wid, fy - 8 - 30 * tt, 40 + 20 * frac(q, 3), 24 + 10 * frac(q, 3), P.deep, 0.4 * (1 - tt / 1.0)) }
            }
        default:
            o.e(fx, fy - 150, 300 * smooth(t / 0.3), 18 * (1 - smooth((t - 0.8) / 0.8)) + 0.4, -1.5708, P.mid, 0.6 * (1 - easeIn(t / 1.6)))
            o.e(fx, fy - 150, 300 * smooth(t / 0.3), 6 + 0.4, -1.5708, P.light, 0.9 * (1 - easeIn(t / 1.4)))
            let r = 30 + 220 * easeOut(t / 0.8)
            o.r(fx, fy - 2, r, r * 0.26, 4.0 * max(0.0, 1 - t / 0.9) + 0.6, P.mid, 0.8 * (1 - easeIn(t / 0.9)))
            for i in 0..<44 {
                let tt = t - 0.04 - 0.4 * frac(i, 1), life = 1.2 + 0.5 * frac(i, 3)
                if !(tt >= 0 && tt < life) { continue }
                let x = cx + (frac(i, 4) - 0.5) * wid + sin(tt * 4 + Double(i)) * 14, y = fy - frac(i, 2) * hgt - 250 * tt * (0.4 + frac(i, 6)), a = pw(1 - tt / life, 0.8) * smooth(tt / 0.05)
                o.e(x, y, 14 + 12 * frac(i, 7), 2.0, -1.5708, cols[i % 3], a * 0.9); o.g(x, y, 8, 8, P.body, a * 0.4)
            }
            o.g(cx, cy - 120 * easeOut(t / 1.2), 50 * (1 - easeIn(t / 1.6)) + 4, 50 * (1 - easeIn(t / 1.6)) + 4, P.light, 0.8 * (1 - easeIn(t / 1.6)))
        }
        for j in 0..<8 {
            let tt = t - 0.05 - 0.3 * frac(j, 1)
            if tt > 0 && tt < 1.0 {
                let x = fx + (frac(j, 2) - 0.3) * 60 + (50 + 220 * frac(j, 3)) * easeOut(tt / 0.8)
                o.g(x, fy - 4 - 8 * frac(j, 4), 16, 7, P.deep, 0.4 * (1 - tt / 1.0))
            }
        }
        return o.prims
    }

    // MARK: a hero goes down (a shock, a soul rising, and a light that waits)

    static func playerDown(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.down, chest = geo.targets[ti].chest, foot = geo.targets[ti].foot, cx = chest.x, cy = chest.y, fx = foot.x, fy = foot.y
        if ti == 0 {
            o.f(RGB(255, 255, 255), 0.5 * exp(-t * 10))
            o.f(P.body, 0.25 * exp(-t * 6))
        }
        o.g(cx, cy, 140 * (0.5 + easeOut(t / 0.2)), 140 * (0.5 + easeOut(t / 0.2)), P.body, 0.6 * (1 - easeIn(t / 0.5)))
        o.g(cx, cy, 60, 60, P.light, 0.9 * (1 - easeIn(t / 0.18)))
        let ringCols = [P.mid, P.a2]
        for w in 0..<2 {
            let u = (t - 0.1 * Double(w)) / 0.9
            if u > 0 && u < 1 {
                let R = 40 + 360 * easeOut(u)
                o.r(fx, fy - 2, R, R * 0.26, 5.0 * (1 - u) + 1.0, ringCols[w], 0.8 * (1 - easeIn(u)))
            }
        }
        for q in 0..<8 {
            let a = Double(q) * 0.7854 + 0.2, r = (50 + 120 * frac(q, 2)) * easeOut(t / 0.5)
            o.e(fx + cos(a) * r, fy - 4 + sin(a) * r * 0.2, 20, 2.0, a * 0.2, P.deep, 0.6 * max(0.0, 1 - t / 0.7))
        }
        o.e(fx, fy - 130, 140 * smooth(t / 0.4), 16 * smooth(t / 0.4) + 0.4, -1.5708, P.mid, 0.35 * (1 - easeIn(t / 1.6)))
        let soulCols = [P.a2, P.light]
        for q in 0..<10 {
            let u = (t - 0.15 - 0.12 * Double(q)) / 1.6
            if u > 0 && u < 1 {
                let x = fx + sin(u * 5 + Double(q)) * 28 * (0.4 + u), y = fy - 20 - u * 260 * (0.6 + 0.4 * frac(q, 2)), al = sin(Double.pi * u), col = soulCols[q % 2]
                o.g(x, y, 10, 10, col, 0.8 * al); o.g(x, y + 14, 7, 7, col, 0.5 * al); o.g(x, y + 26, 5, 5, col, 0.3 * al)
            }
        }
        return o.prims
    }

    /// A fallen hero is hidden; in their place a soul crystal floats over a sigil, with a beam above it, until a revival. `t0`: time since the fall.
    static func downAura(_ t0: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.gold, fx = geo.targets[ti].foot.x, fy = geo.targets[ti].foot.y, t = max(0.0, t0)
        let A = smooth((t - 0.3) / 0.6), bob = sin(t * 2) * 4, cy = fy - 70 + bob
        o.g(fx, fy - 4, 70, 16, P.body, 0.3 * A)
        o.r(fx, fy - 2, 46, 13, 2.2, P.mid, 0.7 * A); o.r(fx, fy - 2, 32, 9, 1.2, P.light, 0.6 * A)
        for q in 0..<3 { let a0 = t * 0.8 + Double(q) * 2.094; o.arc(fx, fy - 2, 56, 16, a0, a0 + 1.0, 2.2, P.a2, 0.7 * A) }
        o.e(fx, fy - 160, 160, 4.0, -1.5708, P.light, 0.35 * A * (0.7 + 0.3 * sin(t * 1.5)))
        o.g(fx, cy, 40, 50, P.body, 0.45 * A * (0.8 + 0.2 * sin(t * 3)))
        let ys: [Double] = [-28, -12, 0, 12, 28], wd: [Double] = [0.5, 16, 22, 16, 0.5]
        o.k(ys.map { Pt(fx, cy + $0) }, wd, P.mid, 0.85 * A, add: true, soft: 1.4)
        o.k(ys.map { Pt(fx, cy + $0) }, wd.map { $0 * 0.45 }, P.light, 0.9 * A, add: true, soft: 1.2)
        for q in 0..<5 { let a = t * 2 + Double(q) * 1.2566; o.g(fx + cos(a) * 30, cy + sin(a) * 10, 5, 5, P.a2, 0.8 * A) }
        return o.prims
    }

    // MARK: damage buff (a standing fury around a unit while its damage is raised)

    /// `t0`: time since the buff was granted (large = standing); `geo.power`: the buff's strength (amount / 3).
    static func buffAura(_ t0: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.fury, cx = geo.targets[ti].chest.x, cy = geo.targets[ti].chest.y, fx = geo.targets[ti].foot.x, fy = geo.targets[ti].foot.y, t = max(0.0, t0)
        let L = min(1.6, max(0.4, geo.power)), A = smooth(t / 0.3) * (0.6 + 0.4 * min(1.0, L))
        o.g(cx, cy, 50 * L + 10, 70 * L + 12, P.body, 0.16 * A * (0.8 + 0.2 * sin(t * 4)))
        o.r(fx, fy - 2, 40, 11, 1.8, P.a1, 0.55 * A)
        for q in 0..<2 {
            let a0 = t * (q == 0 ? 1.4 : -1.1) + Double(q) * Double.pi
            o.arc(fx, fy - 2, 48, 14, a0, a0 + 1.6, 2.4, q == 0 ? P.mid : P.a2, 0.7 * A)
        }
        let flameCols = [P.a1, P.a2, P.mid]
        for q in 0..<Int(6 + 4 * L) {
            let ph = frac(q + 6 * ti, 1), u = pm(t * (0.7 + 0.3 * frac(q, 2)) + ph, 1.0)
            let x = fx + cos(ph * 6.2832 + t * 0.5) * 30, y = fy - 6 - u * (140 + 30 * L)
            o.e(x, y, 12 + 6 * L, 2.2, -1.5708, flameCols[q % 3], 0.85 * A * sin(Double.pi * u))
        }
        for q in 0..<2 {
            let u = pm(t * 0.5 + Double(q) * 0.5, 1.0), y = cy - 70 - u * 40, al = A * sin(Double.pi * u)
            o.e(cx - 7, y + 4, 10, 2.4, -0.75, P.light, al); o.e(cx + 7, y + 4, 10, 2.4, 0.75, P.light, al)
        }
        if t < 0.6 {
            let u = t / 0.6
            o.g(cx, cy, 90, 110, P.mid, 0.5 * (1 - u))
            o.r(fx, fy - 2 - 120 * easeOut(u), 50 * (1 + u), 14 * (1 + u), 3.0 * (1 - u) + 0.5, P.a2, 0.9 * (1 - u))
        }
        return o.prims
    }

    // MARK: revive (a beam comes down, the light gathers into the body, the hero returns)

    static func revive(_ t: Double, _ geo: Geometry, _ ti: Int) -> [Prim] {
        var o = Out(); let P = Pal.gold, fx = geo.targets[ti].foot.x, fy = geo.targets[ti].foot.y, cx = geo.targets[ti].chest.x, cy = geo.targets[ti].chest.y
        if ti == 0 && t >= 0.28 && t < 0.9 { o.f(P.light, 0.45 * exp(-max(0.0, t - 0.3) * 10)) }
        let fade = 1 - smooth((t - 0.9) / 0.6), h = 420 * easeOut(t / 0.3)
        o.e(fx, fy - 420 + h / 2, h / 2 + 1, 20 * fade + 0.4, -1.5708, P.body, 0.6 * fade)
        o.e(fx, fy - 420 + h / 2, h / 2 + 1, 6.0, -1.5708, P.light, 0.9 * fade)
        let r = 30 + 90 * easeOut(t / 0.5)
        o.r(fx, fy - 2, r, r * 0.28, 3.0 * max(0.0, 1 - t / 1.2) + 0.8, P.mid, 0.9 * (1 - easeIn(t / 1.4)))
        for q in 0..<4 { let a0 = t * 2 + Double(q) * 1.5708; o.arc(fx, fy - 2, r * 1.2, r * 0.34, a0, a0 + 0.9, 2.4, P.a2, 0.8 * (1 - easeIn(t / 1.4))) }
        for i in 0..<20 {
            let a = frac(i, 1) * 6.2832
            if t < 0.35 {
                let e = smooth(t / 0.35), rr = 120 * (1 - e)
                o.g(cx + cos(a) * rr, cy + sin(a) * rr * 0.7, 6, 6, P.a2, 0.9 * e)
            } else {
                let u = (t - 0.35) / 0.9
                if u < 1 { o.e(cx + cos(a) * 90 * easeOut(u), cy + sin(a) * 50 * easeOut(u) - 60 * u, 10, 1.6, a, P.light, 1 - u) }
            }
        }
        o.g(cx, cy, 70, 90, P.body, 0.4 * smooth((t - 0.3) / 0.1) * (1 - smooth((t - 1.0) / 0.6)))
        return o.prims
    }

    // MARK: atmosphere (themed particles over the whole stage)

    /// Three layers per skill: particles that gather into the caster while the power builds, a field that fills the whole stage with the
    /// skill's own weather (embers, falling stars, wisps, flakes, glyph fragments...), and a burst from every target at the release.
    struct AtmosSpec { let kind: String, motion: String, palette: String, field: Int, gather: Int, burst: Int, rate: Double, size: Double, release: Double }
    static let atmos: [String: AtmosSpec] = [
        "starlightPulse": AtmosSpec(kind: "star", motion: "fall", palette: "starlight", field: 70, gather: 28, burst: 22, rate: 0.42, size: 1.3, release: 0.75),
        "dragonSoulWard": AtmosSpec(kind: "wisp", motion: "rise", palette: "soul", field: 64, gather: 28, burst: 18, rate: 0.34, size: 1.4, release: 0.38),
        "dragonScaleWard": AtmosSpec(kind: "flake", motion: "fall", palette: "scale", field: 60, gather: 24, burst: 22, rate: 0.30, size: 1.3, release: 0.56),
        "runeSlash": AtmosSpec(kind: "rune", motion: "gust", palette: "rune", field: 66, gather: 26, burst: 24, rate: 0.55, size: 1.3, release: 1.048),
        "runeWard": AtmosSpec(kind: "rune", motion: "rise", palette: "rune", field: 60, gather: 26, burst: 18, rate: 0.30, size: 1.3, release: 0.72),
        "battleRune": AtmosSpec(kind: "spark", motion: "orbit", palette: "battle", field: 60, gather: 26, burst: 24, rate: 0.50, size: 1.3, release: 0.56),
        "dragonFlame": AtmosSpec(kind: "ember", motion: "rise", palette: "flame", field: 64, gather: 22, burst: 20, rate: 0.50, size: 1.45, release: 0.46),
        "dragonOrder": AtmosSpec(kind: "ember", motion: "gust", palette: "order", field: 66, gather: 28, burst: 22, rate: 0.50, size: 1.3, release: 0.56),
        "rally": AtmosSpec(kind: "star", motion: "rise", palette: "rally", field: 60, gather: 24, burst: 18, rate: 0.34, size: 1.3, release: 0.56),
        "sweep": AtmosSpec(kind: "ember", motion: "gust", palette: "sweep", field: 60, gather: 22, burst: 20, rate: 0.60, size: 1.2, release: 1.048),
        "natural20": AtmosSpec(kind: "star", motion: "fall", palette: "gold", field: 90, gather: 0, burst: 40, rate: 0.40, size: 1.7, release: 0.05),
        "shieldDome": AtmosSpec(kind: "flake", motion: "orbit", palette: "ward", field: 44, gather: 22, burst: 0, rate: 0.45, size: 1.1, release: 0.46),
        "healMicro": AtmosSpec(kind: "mote", motion: "rise", palette: "heal", field: 20, gather: 0, burst: 0, rate: 0.30, size: 1.1, release: 0.3),
        "healStandard": AtmosSpec(kind: "mote", motion: "rise", palette: "heal", field: 28, gather: 0, burst: 0, rate: 0.30, size: 1.25, release: 0.3),
        "healStrong": AtmosSpec(kind: "mote", motion: "rise", palette: "heal", field: 36, gather: 0, burst: 0, rate: 0.30, size: 1.4, release: 0.3),
    ]

    static func atmosCols(_ name: String) -> [RGB] {
        switch name {
        case "starlight": return [RGB(255, 255, 255), RGB(222, 212, 255), RGB(160, 136, 255), RGB(255, 255, 255)]
        case "soul": return [RGB(235, 250, 255), RGB(130, 210, 255), RGB(56, 140, 255), RGB(235, 250, 255)]
        default:
            let P: Pal
            switch name { case "gold": P = .gold; case "ward": P = .ward; case "rally": P = .rally; case "sweep": P = .sweep; case "rune": P = .rune; case "battle": P = .battle; case "flame": P = .flame; case "scale": P = .scale; case "order": P = .order; default: P = .heal }
            return [P.light, P.mid, P.a2, P.a1]
        }
    }

    private static func particle(_ o: inout Out, _ kind: String, _ x: Double, _ y: Double, _ vx: Double, _ vy: Double, _ a: Double, _ s: Double, _ col: RGB, _ t: Double, _ i: Int) {
        if a < 0.012 { return }
        let di = Double(i)
        switch kind {
        case "ember":
            o.e(x, y, 18 * s, 3 * s, atan2(vy, vx), col, a * 0.95); o.g(x, y, 11 * s, 11 * s, col, a * 0.4)
        case "star":
            let tw = 0.55 + 0.45 * sin(t * 9 + di * 1.7), L = 22 * s * (0.6 + 0.4 * tw)
            o.e(x, y, L, 1.8 * s, 0.0, col, a * tw); o.e(x, y, L * 0.8, 1.6 * s, 1.5708, col, a * tw); o.g(x, y, 10 * s, 10 * s, col, a * tw * 0.35)
        case "wisp":
            o.g(x, y, 13 * s, 13 * s, col, a * 0.85); o.g(x - vx * 0.06, y - vy * 0.06, 9 * s, 9 * s, col, a * 0.55); o.g(x - vx * 0.12, y - vy * 0.12, 6.5 * s, 6.5 * s, col, a * 0.35)
        case "flake":
            let tum = t * 3 + di
            o.e(x, y, 13 * s * (0.35 + 0.65 * abs(cos(tum))), 5 * s, tum * 0.7, col, a); o.g(x, y, 7 * s, 7 * s, col, a * 0.25)
        case "rune":
            let a0 = t * 2 + di
            o.arc(x, y, 11 * s, 11 * s, a0, a0 + 4.2, 2.0, col, a); o.g(x, y, 14 * s, 14 * s, col, a * 0.35)
        case "spark":
            o.e(x, y, 13 * s, 2.2 * s, sin(t * 40 + di) * 1.5, col, a); o.g(x, y, 9 * s, 9 * s, col, a * 0.5)
        default:
            o.g(x, y, 9 * s, 9 * s, col, a * 0.8); o.g(x, y, 3.5 * s, 3.5 * s, col, a)
        }
    }

    static func atmosphere(skill id: String, t: Double, geo: Geometry) -> [Prim] {
        guard let sp = atmos[id], let info = info[id], t >= 0, t < info.duration, !geo.targets.isEmpty else { return [] }
        let imp = sp.release, cols = atmosCols(sp.palette)
        var o = Out()
        let C = geo.caster, Ts = geo.targets.map { $0.chest }, gy = geo.ground
        let xs = [C.x] + Ts.map { $0.x }, x0 = (xs.min() ?? C.x) - 170, x1 = (xs.max() ?? C.x) + 170, top = gy - 330
        let mx = Ts.reduce(0.0) { $0 + $1.x } / Double(Ts.count), my = Ts.reduce(0.0) { $0 + $1.y } / Double(Ts.count)
        let d: Double = Ts[0].x >= C.x ? 1.0 : -1.0
        let amb = smooth(t / (imp * 0.8 + 0.05)) * (1 - smooth((t - info.duration * 0.62) / (info.duration * 0.34)))
        let lvl = amb * (0.45 + 0.55 * smooth((t - imp * 0.7) / 0.4))
        for i in 0..<sp.field {
            let di = Double(i)
            let rate = (0.55 + 0.9 * frac(i, 3)) * sp.rate, q = t * rate + frac(i, 2), lane = Int(floor(q)), cyc = q - Double(lane)
            let ux = frac(i + 17 * lane, 5), vz = frac(i, 4), sway = sin(cyc * 6.2832 * (1 + vz) + di)
            var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
            switch sp.motion {
            case "rise":
                let H = 240 + 90 * vz
                x = x0 + (x1 - x0) * ux + sway * 16 * (0.4 + cyc); y = gy + 10 - cyc * H; vx = sway * 10; vy = -H * rate
            case "fall":
                let H = gy - top + 20
                x = x0 + (x1 - x0) * ux + sway * 22 * (0.4 + cyc); y = top - 20 + cyc * H; vx = sway * 12; vy = H * rate
            case "gust":
                let W = x1 - x0 + 180
                x = (d > 0 ? x0 - 90 : x1 + 90) + d * cyc * W; y = gy - 30 - 230 * frac(i + 7 * lane, 6) + sway * 14; vx = d * W * rate; vy = 0.0
            default:
                let w = (0.8 + 1.2 * vz) * (i % 2 == 0 ? 1.0 : -1.0), ang = t * w + di * 2.399, R = 60 + 190 * ux
                x = mx + cos(ang) * R * 1.2; y = my + sin(ang) * R * 0.35 - 40 * cyc; vx = -sin(ang) * R * 1.2 * w; vy = cos(ang) * R * 0.35 * w - 40 * rate
            }
            let a = lvl * pw(sin(Double.pi * cyc), 0.8) * (0.65 + 0.35 * frac(i, 7))
            particle(&o, sp.kind, x, y, vx, vy, a, sp.size * (0.7 + 0.6 * vz), cols[i % 4], t, i)
        }
        if sp.gather > 0 && t < imp + 0.02 {
            for j in 0..<sp.gather {
                let e = smooth((t - 0.04 - 0.3 * imp * frac(j, 3)) / (imp * 0.8))
                if e <= 0.01 || e >= 1 { continue }
                let a0 = frac(j, 1) * 6.2832 + t * (1.4 + frac(j, 2)), R0 = 130 + 150 * frac(j, 2), r = R0 * pw(1 - e, 1.4)
                let x = C.x + cos(a0) * r, y = C.y + sin(a0) * r * 0.6
                let a = smooth(e * 6) * (1 - smooth((e - 0.85) / 0.15)) * smooth(t / 0.12) * 0.9
                particle(&o, sp.kind, x, y, C.x - x, C.y - y, a, sp.size, cols[j % 4], t, j + 100)
            }
        }
        let post = t - imp
        if sp.burst > 0 && post > 0 {
            for (ti, T) in Ts.enumerated() {
                for j in 0..<sp.burst {
                    let jj = j + 31 * ti, tt = post - (0.02 + 0.22 * frac(jj, 5)), life = 1.0 + 0.6 * frac(jj, 6)
                    if !(tt >= 0 && tt < life) { continue }
                    let ang = frac(jj, 7) * 6.2832, spd = 80 + 170 * frac(jj, 8), rr = spd * easeOut(tt / 0.7), slow = 1 - clamp01(tt / 0.7)
                    let dy: Double, gv: Double
                    if sp.motion == "fall" { dy = 90 * tt * tt; gv = 180 * tt } else { dy = -70 * tt; gv = -70.0 }
                    let x = T.x + cos(ang) * rr, y = T.y + sin(ang) * rr * 0.55 + dy
                    let a = pw(1 - tt / life, 0.8) * smooth(tt / 0.05) * 0.95
                    particle(&o, sp.kind, x, y, cos(ang) * spd * slow, sin(ang) * spd * 0.55 * slow + gv, a, sp.size * 1.1, cols[jj % 4], t, jj + 200)
                }
            }
        }
        return o.prims
    }

    /// The soft light a skill casts on the stage (a wide glow around the targets, a pool on the floor), as primitives: the same shapes the
    /// CoreGraphics painter draws in `drawAmbient`, for the GPU path. The flat dim and wash are the stage's pane-wide overlays.
    static func ambient(skill id: String, t: Double, target: Pt, floorY: Double, rx: Double) -> [Prim] {
        guard info[id] != nil, !isBlow(id) else { return [] }
        let lit = light(skill: id, t: t)
        guard lit > 0.01 else { return [] }
        let col = tone(id)
        return [.glow(x: target.x, y: target.y, rx: rx * 1.5, ry: rx * 1.2, c: col, a: lit * 0.16),
                .glow(x: target.x, y: floorY, rx: rx * 0.9, ry: 22, c: col, a: lit * 0.3)]
    }

    // MARK: camera (how the lens answers each skill)

    struct Camera: Equatable { var dx = 0.0, dy = 0.0, zoom = 0.0, rotation = 0.0
        static let zero = Camera()
        static func + (a: Camera, b: Camera) -> Camera { Camera(dx: a.dx + b.dx, dy: a.dy + b.dy, zoom: a.zoom + b.zoom, rotation: a.rotation + b.rotation) }
    }

    /// A damped thump: amplitude `a` at `t0`, decaying at rate `k`, ringing at `w` rad/s.
    private static func thump(_ t: Double, _ t0: Double, _ a: Double, _ k: Double, _ w: Double, _ phase: Double = 0) -> Double {
        let r = t - t0
        return r < 0 ? 0 : a * exp(-r * k) * cos(r * w + phase)
    }

    /// Lens kick in layout units (the same units as `MeadowBattleHitFeel.camera`). `direction` is +1 when the effect travels to the right.
    static func camera(skill id: String, t: Double, direction: Double) -> Camera {
        guard t >= 0, let i = info[id], t < i.duration, !isBlow(id) else { return .zero }
        var c = Camera()
        switch id {
        case "starlightPulse":
            c.zoom = 0.008 * smooth(t / 0.75) * b2d(t < 0.75) + max(0, thump(t, 0.75, 0.024, 7, 0))
            c.dx = direction * thump(t, 0.75, 3.0, 9, 30); c.dy = -thump(t, 0.75, 1.6, 10, 34, 0.6)
        case "dragonSoulWard":
            c.zoom = 0.014 * smooth(t / 0.38) * b2d(t < 0.38) + max(0, thump(t, 0.38, 0.03, 6, 0))
            c.dy = -thump(t, 0.38, 3.0, 8, 34, 0.6); c.rotation = thump(t, 0.38, 0.004, 9, 24)
        case "runeSlash":
            for k in 0..<5 {
                let t0 = 1.048 + 0.06 * Double(k), s: Double = k % 2 == 0 ? 1 : -1
                c.dx += direction * s * thump(t, t0, 3.4, 26, 62); c.dy += -s * thump(t, t0, 1.6, 24, 70, 0.4)
            }
            c.zoom = max(0, thump(t, 1.35, 0.03, 8, 0)); c.rotation = direction * thump(t, 1.35, 0.006, 10, 28)
        case "runeWard":
            c.zoom = max(0, thump(t, 1.12, 0.02, 10, 0)); c.dy = -thump(t, 1.12, 2.2, 12, 40, 0.6); c.zoom += 0.006 * smooth(t / 0.72) * b2d(t < 1.12)
        case "battleRune":
            let r = t - 0.56
            if r >= 0 { c.dx = 2.6 * sin(t * 71) * exp(-r * 2.2); c.dy = 2.0 * sin(t * 83 + 1) * exp(-r * 2.4); c.zoom = max(0, thump(t, 0.56, 0.02, 8, 0)) }
        case "dragonFlame":
            c.dx = direction * thump(t, 0.46, 7.0, 7, 28); c.dy = -thump(t, 0.46, 4.0, 8, 36, 0.6)
            c.zoom = max(0, thump(t, 0.46, 0.045, 6, 0)); c.rotation = direction * thump(t, 0.46, 0.008, 8, 26)
            let r = t - 0.9
            if r >= 0 && r < 1.0 { c.dy += 0.9 * sin(t * 47) * (1 - r) }
        case "dragonScaleWard":
            c.zoom = max(0, thump(t, 0.56, 0.032, 9, 0)); c.dy = -thump(t, 0.56, 3.2, 10, 30, 0.6)
        case "playerDown":
            c.zoom = max(0, thump(t, 0, 0.06, 4, 0)); c.dx = direction * thump(t, 0, 10, 4, 30); c.dy = -thump(t, 0, 8, 4.5, 36, 0.6); c.rotation = -direction * thump(t, 0, 0.016, 4, 22)
        case "natural20":
            c.zoom = max(0, thump(t, 0, 0.07, 5, 0)); c.dx = direction * thump(t, 0, 12, 4.5, 34); c.dy = -thump(t, 0, 8, 5, 40, 0.6)
            c.rotation = direction * thump(t, 0, 0.02, 5, 24)
            let r = t - 0.4
            if r >= 0 && r < 1.2 { c.dy += 1.2 * sin(t * 53) * (1 - r / 1.2) }
        case "sweep":
            c.dx = direction * thump(t, 1.048, 6.0, 9, 30); c.dy = -thump(t, 1.048, 2.4, 10, 40, 0.6)
            c.zoom = max(0, thump(t, 1.048, 0.035, 7, 0)); c.rotation = direction * thump(t, 1.048, 0.006, 9, 26)
        case "rally":
            c.zoom = max(0, thump(t, 0.56, 0.03, 9, 0)); c.dy = -thump(t, 0.56, 2.0, 12, 40, 0.5)
        case "dragonOrder":
            for (k, amp) in [0.02, 0.022, 0.036].enumerated() {
                let t0 = 0.56 + 0.3 * Double(k)
                c.zoom += max(0, thump(t, t0, amp, 12, 0)); c.dy += -thump(t, t0, 1.6 + Double(k), 14, 40, 0.5)
            }
        default:
            c.zoom = 0.006 * sin(Double.pi * t / i.duration)
        }
        return c
    }

    // MARK: trauma (how hard an effect shakes the world)

    /// 0...1.2: the shake an effect adds to the world `t` seconds into it. It jumps up at the release and dies away; the stage turns the summed
    /// trauma into a continuous multi-axis shake (offset, tilt, a little zoom), so a hit reads as a hit even on a small screen.
    static func trauma(skill id: String, t: Double, power: Double) -> Double {
        guard let i = info[id], t >= 0, !id.hasPrefix("hit"), !id.hasPrefix("proj"), !id.hasPrefix("heal"), !id.hasPrefix("shieldShell"), id != "downAura", id != "buffAura", id != "shieldDome" else { return 0 }
        let amp: Double, rate: Double
        switch id {
        case "dragonFlame": amp = 0.95; rate = 3.2
        case "natural20": amp = 1.0; rate = 1.7
        case "playerDown": amp = 0.9; rate = 2.6
        case "sweep": amp = 0.8; rate = 4.0
        case "runeSlash": amp = 0.7; rate = 4.5
        case "starlightPulse", "dragonScaleWard", "dragonOrder": amp = 0.5; rate = 4.0
        case "shieldBreak": amp = 0.6; rate = 4.5
        case "deathDragon": amp = 0.8; rate = 3.0
        case "deathTroll": amp = 0.6; rate = 3.6
        case "deathStone": amp = 0.7; rate = 3.4
        case "deathSlime", "deathWolf", "deathGoblin", "deathBurst": amp = 0.4; rate = 4.5
        default: amp = 0.42; rate = 4.5
        }
        let r = t - i.release
        guard r >= -0.01 else { return 0 }
        let rise = smooth((r + 0.01) / 0.03)
        let boost = id == "dragonFlame" && r > 0 && r < 1.2 ? 0.3 * (1 - r / 1.2) : 0
        return (amp * min(1.6, max(0.6, power)) * exp(-max(0, r) * rate) + boost) * rise
    }

    /// The continuous shake for a trauma level at scene time `time`: offset in layout units, tilt in radians, zoom.
    static func shake(trauma tr: Double, time: Double) -> (dx: Double, dy: Double, rotation: Double, zoom: Double) {
        let k = min(1.0, max(0.0, tr)), s = pow(k, 1.5)
        func n(_ seed: Double) -> Double { sin(time * 43 + seed) * 0.55 + sin(time * 71 + seed * 2.1) * 0.3 + sin(time * 109 + seed * 3.7) * 0.15 }
        return (26 * s * n(1.3), 18 * s * n(4.1), 0.028 * s * n(7.7), 0.035 * k)
    }

    // MARK: director shot (the lens follows the story of the skill)

    /// A framing request for the stage: lean the lens toward `focus` (stage coordinates) by `weight` (0...1) and push in by `zoom`.
    struct Shot: Equatable { var focusX = 0.0, focusY = 0.0, weight = 0.0, zoom = 0.0
        static let idle = Shot()
    }

    /// Close-up on the caster while the power gathers, a swing to the targets as it is released, then a slow pull back.
    /// Healing micro-effects have no director shot - they are the stage's background, not a cast.
    static func shot(skill id: String, t: Double, geo: Geometry) -> Shot {
        guard !id.hasPrefix("heal"), !isBlow(id), t >= 0, let i = info[id], t < i.duration, !geo.targets.isEmpty else { return .idle }
        if id == "playerDown" {
            // A hero falls: the lens drifts in on the body and holds for a while.
            let n = Double(geo.targets.count)
            let w = smooth(t / 0.2) * (1 - smooth((t - 1.0) / 0.8))
            return Shot(focusX: geo.targets.reduce(0) { $0 + $1.foot.x } / n, focusY: geo.targets.reduce(0) { $0 + $1.foot.y - 30 } / n, weight: w, zoom: w * 0.22)
        }
        if id == "natural20" {
            // The roll that ends the fight: straight in on the target, a long hold, a slow release.
            let n = Double(geo.targets.count)
            let w = smooth(t / 0.12) * (1 - smooth((t - 1.3) / 0.9))
            return Shot(focusX: geo.targets.reduce(0) { $0 + $1.chest.x } / n, focusY: geo.targets.reduce(0) { $0 + $1.chest.y } / n, weight: w, zoom: w * 0.34)
        }
        let rel = max(0.2, i.release)
        let n = Double(geo.targets.count)
        let tx = geo.targets.reduce(0) { $0 + $1.chest.x } / n, ty = geo.targets.reduce(0) { $0 + $1.chest.y } / n
        let spread = geo.targets.map { abs($0.chest.x - tx) }.max() ?? 0
        // Weight: ease in over the first half of the build-up, hold through the release, ease out afterwards.
        let hold = rel + 0.9
        let weight = smooth(t / (rel * 0.45)) * (1 - smooth((t - hold) / min(1.0, max(0.5, i.duration - hold))))
        // Swing: caster -> targets around the release (support skills swing too: the allies are the targets).
        let swing = smooth((t - rel * 0.55) / (rel * 0.6 + 0.12))
        let fx = geo.caster.x + (tx - geo.caster.x) * swing, fy = geo.caster.y + (ty - geo.caster.y) * swing
        // Zoom: a tight close-up on the caster, relaxing to a wider frame that still holds a group of targets.
        let wide = 1 - clamp01(spread / 420)
        let closeUp = 0.30, atTargets = 0.13 + 0.08 * wide
        return Shot(focusX: fx, focusY: fy, weight: weight, zoom: weight * (closeUp + (atTargets - closeUp) * swing))
    }

    /// Scales the thump part of the lens kick by how hard the hit actually was (`power` ~0.7 light, 1 medium, 1.45 heavy),
    /// without touching the build-up before the release (so there is no jump when the damage becomes known).
    static func scaled(_ c: Camera, skill id: String, t: Double, power: Double) -> Camera {
        guard let i = info[id] else { return c }
        // A medium blow shakes 1.6x the base thump, a heavy one 2.3x, a light one barely more than the base.
        let k = 1 + (power * 1.6 - 1) * smooth((t - i.release) / 0.12)
        return Camera(dx: c.dx * k, dy: c.dy * k, zoom: c.zoom * k, rotation: c.rotation * k)
    }

    // MARK: ambient light (the stage answers each skill)

    /// 0...1 light level driven by the skill's own phases: it builds into the release, holds, and fades with the effect.
    static func light(skill id: String, t: Double) -> Double {
        guard let i = info[id], t >= 0, t < i.duration else { return 0 }
        let rise = smooth(t / max(0.1, i.release * 0.8))
        let fall = 1 - smooth((t - i.duration * 0.62) / (i.duration * 0.38))
        return clamp01(rise * fall)
    }
}
