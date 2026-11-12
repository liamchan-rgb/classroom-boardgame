import Foundation

/// How a skill lights its surroundings: a stage-wide colour wash, a pool of light (and a squashed reflection of the
/// effect) on the floor, and glowing motes that drift over the characters. Presentation only; pure Foundation so
/// `scripts/battle-ambient-regression.swift` can compile it without UIKit. Layout units are points of the party stage.
enum MeadowSkillAmbientLight {
    struct Tone: Equatable { let r: Double, g: Double, b: Double }

    /// One glowing speck, relative to the skill's centre. `radius` is the halo radius, `core` the bright pixel size.
    struct Mote: Equatable { let id: Int, dx: Double, dy: Double, radius: Double, core: Double, alpha: Double, hot: Bool }

    static let skillIDs = ["starlightPulse", "rally", "sweep", "dragonSoulWard", "dragonScaleWard"]

    static func tone(for id: String) -> Tone {
        switch id {
        case "starlightPulse": return Tone(r: 0.46, g: 0.40, b: 1.0)
        case "rally": return Tone(r: 1.0, g: 0.76, b: 0.30)
        case "sweep": return Tone(r: 0.42, g: 0.78, b: 1.0)
        case "dragonSoulWard": return Tone(r: 0.29, g: 0.67, b: 1.0)
        default: return Tone(r: 1.0, g: 0.55, b: 0.18)
        }
    }

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    static func smooth(_ x: Double) -> Double { let t = clamp01(x); return t * t * (3 - 2 * t) }
    static func fraction(_ i: Int, _ salt: Int) -> Double { Double((i * 73 + salt * 37 + (i * i) * 11) % 101) / 100.0 }

    /// 0...1 light level: eases up to the peak frame, holds briefly, then fades by the end of the effect.
    static func level(age: Double, peak: Double, duration: Double) -> Double {
        guard age >= 0, age < duration else { return 0 }
        let rise = smooth(age / max(0.05, peak * 0.9))
        let fall = 1 - smooth((age - peak - 0.08) / max(0.05, duration - peak - 0.08))
        return clamp01(rise * (age <= peak ? 1 : fall))
    }

    static func moteCount(for id: String) -> Int { id == "sweep" ? 16 : 22 }

    /// Glowing specks; ids are fixed so every frame is a continuation of the previous one.
    static func motes(skill id: String, age: Double, duration: Double, spread: Double) -> [Mote] {
        guard age >= 0, age < duration else { return [] }
        var out: [Mote] = []
        for i in 0..<moteCount(for: id) {
            let born = fraction(i, 1) * duration * 0.55
            let life = 0.45 + 0.5 * fraction(i, 2)
            let t = (age - born) / life
            guard t >= 0, t < 1 else { continue }
            let a0 = fraction(i, 3) * 2 * Double.pi
            let r0 = spread * (0.15 + 0.85 * fraction(i, 4))
            var x = cos(a0) * r0, y = sin(a0) * r0 * 0.6
            var size = 22 + 20 * fraction(i, 5)
            switch id {
            case "starlightPulse":                       // twinkling dust drifting outward
                let push = 1 + 0.35 * t
                x *= push; y *= push; y -= 8 * t
            case "rally", "dragonScaleWard":             // embers lifting off and swaying
                y -= 46 * t * (0.6 + fraction(i, 6)); x += sin(t * 6 + Double(i)) * 6
            case "sweep":                                // spray flung from the arc
                x = spread * (0.2 + 1.0 * t) * (fraction(i, 7) > 0.5 ? 1 : 0.7); y = (fraction(i, 8) - 0.5) * spread * 1.1 + 14 * t * t
            default:                                     // soul ward: droplets circling up
                let th = a0 + t * 3.2
                x = cos(th) * r0; y = sin(th) * r0 * 0.5 - 40 * t
            }
            size *= id == "starlightPulse" ? 0.8 : 1
            var alpha = pow(sin(Double.pi * t), 0.8)
            if id == "starlightPulse" { alpha *= 0.55 + 0.45 * sin(age * 22 + Double(i) * 2) }
            out.append(Mote(id: i, dx: x, dy: y, radius: size, core: 1.5 + 1.5 * fraction(i, 9), alpha: clamp01(alpha), hot: fraction(i, 10) > 0.6))
        }
        return out
    }

    // MARK: stagecraft - the three generic layers around the sprite: charge-up, target reaction, afterglow

    /// Wards and buffs stay on their targets; the other skills strike and fade.
    static func isWard(_ id: String) -> Bool { ["rally", "dragonSoulWard", "dragonScaleWard"].contains(id) }

    /// Time the charge-up is drawn before the sprite starts. It lives entirely inside the existing cast motion.
    static let chargeWindow = 0.5
    static let reactionLife = 0.6, wardReactionLife = 1.7, afterglowLife = 0.9

    static func easeOut(_ x: Double) -> Double { let t = clamp01(x); return 1 - (1 - t) * (1 - t) * (1 - t) }

    /// Light gathering on the caster: specks converging on the chest and a ring contracting on the floor.
    struct Charge: Equatable { let level: Double, ringRadius: Double, ringAlpha: Double, motes: [Mote] }

    /// `progress` runs 0 -> 1 over the charge window. Positions are relative to the caster's chest.
    static func charge(skill id: String, progress p: Double) -> Charge? {
        guard p > 0, p <= 1 else { return nil }
        var motes: [Mote] = []
        for i in 0..<12 {
            let a0 = fraction(i, 3) * 2 * Double.pi
            let start = 70 + 50 * fraction(i, 4)
            let t = clamp01((p - 0.35 * fraction(i, 1)) / (1 - 0.35 * fraction(i, 1)))
            let r = start * (1 - easeOut(t))
            let swirl = a0 + t * 2.4
            let alpha = clamp01(p * 3) * (0.5 + 0.5 * fraction(i, 2)) * (1 - smooth((t - 0.9) / 0.1))
            motes.append(Mote(id: i, dx: cos(swirl) * r, dy: sin(swirl) * r * 0.7, radius: 14 + 10 * fraction(i, 5), core: 1.5 + 1.5 * fraction(i, 9), alpha: alpha, hot: fraction(i, 10) > 0.55))
        }
        return Charge(level: smooth(p) * 0.9, ringRadius: 12 + 58 * (1 - easeOut(p)), ringAlpha: clamp01(p * 2.5) * (1 - 0.4 * p), motes: motes)
    }

    /// What the target does when the skill lands: strikes flash and spit sparks, wards put on a turning aura.
    struct Reaction: Equatable { let glow: Double, aura: Double, spin: Double, motes: [Mote] }

    /// `age` is seconds since the impact. Positions are relative to the target's chest.
    static func reaction(skill id: String, age: Double) -> Reaction? {
        let ward = isWard(id)
        guard age >= 0, age < (ward ? wardReactionLife : reactionLife) else { return nil }
        var motes: [Mote] = []
        if ward {
            for i in 0..<8 {
                let th = fraction(i, 3) * 2 * Double.pi + age * (2.2 + fraction(i, 4))
                let rise = fraction(i, 5) * 30 - 14 + sin(age * 3 + Double(i)) * 5
                let alpha = clamp01(age / 0.25) * (1 - smooth((age - 1.1) / 0.6))
                motes.append(Mote(id: i, dx: cos(th) * 34, dy: sin(th) * 12 + rise, radius: 14, core: 1.8 + fraction(i, 9), alpha: alpha, hot: fraction(i, 10) > 0.6))
            }
            let aura = smooth(age / 0.2) * (1 - smooth((age - 1.1) / 0.6))
            return Reaction(glow: (1 - smooth(age / 0.4)) * 0.8, aura: aura, spin: age * 2.2, motes: motes)
        }
        for i in 0..<9 {
            let life = 0.3 + 0.3 * fraction(i, 2), t = age / life
            guard t < 1 else { continue }
            let a = fraction(i, 3) * 2 * Double.pi
            let d = (14 + 40 * fraction(i, 4)) * easeOut(t)
            motes.append(Mote(id: i, dx: cos(a) * d, dy: sin(a) * d * 0.8 - 6 * t, radius: 12 + 8 * fraction(i, 5), core: 1.6 + 1.4 * fraction(i, 9), alpha: pow(1 - t, 0.8), hot: fraction(i, 10) > 0.5))
        }
        return Reaction(glow: pow(1 - age / reactionLife, 2) * 0.9, aura: 0, spin: 0, motes: motes)
    }

    /// Light that lingers on the floor after the sprite has ended; `age` runs 0 -> afterglowLife. Positions are relative to the skill centre.
    struct Afterglow: Equatable { let pool: Double, motes: [Mote] }

    static func afterglow(skill id: String, age: Double, spread: Double) -> Afterglow? {
        guard age >= 0, age < afterglowLife else { return nil }
        let t = age / afterglowLife
        var motes: [Mote] = []
        for i in 0..<10 {
            let a0 = fraction(i, 3) * 2 * Double.pi
            let r = spread * (0.2 + 0.8 * fraction(i, 4))
            motes.append(Mote(id: i, dx: cos(a0) * r + sin(age * 2 + Double(i)) * 4, dy: sin(a0) * r * 0.5 - age * (14 + 22 * fraction(i, 6)), radius: 12 + 8 * fraction(i, 5), core: 1.4 + 1.2 * fraction(i, 9), alpha: (1 - t) * (0.4 + 0.6 * fraction(i, 2)), hot: false))
        }
        return Afterglow(pool: pow(1 - t, 1.5) * 0.5, motes: motes)
    }
}

