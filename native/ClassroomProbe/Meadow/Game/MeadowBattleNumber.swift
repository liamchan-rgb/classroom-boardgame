import Foundation

/// The floating numbers of the party battle (damage, healing, shield, buffs): how big they are and how they move.
/// Pure maths - no UIKit - so `scripts/battle-number-regression.swift` can check it on any machine.
///
/// Every number lives `life` seconds. It springs in (a damped overshoot, no pop-and-freeze), floats up on an eased curve that
/// keeps drifting until it is gone, and fades late. Heavier hits are bigger and spring harder.
enum MeadowBattleNumber {
    enum Kind: Int { case damage, block, heal, shield, buff, crit }

    static let life = 1.8

    /// Font size in world units (the stage is 1000 wide). Damage grows with the hit tier (0 light, 1 medium, 2 heavy).
    static func fontSize(kind: Kind, rank: Int) -> Double {
        let r = Double(min(2, max(0, rank)))
        switch kind {
        case .damage: return 50 + 12 * r
        case .block: return 44
        case .heal: return 42
        case .shield: return 36
        case .buff: return 34
        case .crit: return 120
        }
    }

    /// Vertical distance between stacked support numbers (heal / shield / buff beside one unit).
    static func lineHeight(kind: Kind, rank: Int) -> Double { fontSize(kind: kind, rank: rank) * 1.04 }

    static func easeOutCubic(_ x: Double) -> Double { let u = 1 - min(1, max(0, x)); return 1 - u * u * u }
    static func smooth(_ x: Double) -> Double { let u = min(1, max(0, x)); return u * u * (3 - 2 * u) }

    /// Scale over the number's age: 0 before it is born, springs past 1 and settles. `rank` adds a short extra punch to hits.
    static func scale(age: Double, kind: Kind, rank: Int) -> Double {
        guard age >= 0 else { return 0 }
        let spring = 1 - exp(-15 * age) * cos(26 * age)
        let punch = kind == .damage || kind == .crit ? (0.16 + 0.08 * Double(min(2, max(0, rank)))) * exp(-7 * age) : 0
        return max(0, spring * (1 + punch))
    }

    /// How far the number has floated up (world units): fast at first, then a long gentle drift until it is gone.
    static func rise(age: Double, kind: Kind) -> Double {
        let top = kind == .damage || kind == .crit || kind == .block ? 70.0 : 48.0
        return top * easeOutCubic(age / life)
    }

    /// Opacity: a very short fade-in, a full hold, a late smooth fade.
    static func alpha(age: Double) -> Double {
        guard age >= 0, age < life else { return 0 }
        return smooth(age / 0.06) * (1 - smooth((age - 1.2) / (life - 1.2)))
    }

    /// A soft sideways wobble that dies out, so numbers from a crowd of hits do not travel in lock-step.
    static func sway(age: Double, seed: Int) -> Double {
        let s = Double(seed % 7) - 3
        return s * 1.6 * smooth(age / 0.25) + 3 * sin(age * 4 + Double(seed)) * exp(-age * 1.6)
    }
}
