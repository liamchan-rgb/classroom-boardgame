import Foundation

/// How hard a blow lands, for presentation only. Never feeds back into rules, dice or receipts.
enum MeadowBattleHitTier: Int, CaseIterable {
    case light, medium, heavy

    /// Light up to 5, medium 6-11, heavy 12+. A killing blow is at least medium.
    static func classify(damage: Int, killed: Bool = false) -> MeadowBattleHitTier {
        var tier: MeadowBattleHitTier = damage <= 5 ? .light : (damage <= 11 ? .medium : .heavy)
        if killed && tier == .light { tier = .medium }
        return tier
    }

    var intensity: Double {
        switch self { case .light: return 0.7; case .medium: return 1.0; case .heavy: return 1.45 }
    }
    var flareRadius: Double {
        switch self { case .light: return 34; case .medium: return 46; case .heavy: return 64 }
    }
    var sparkCount: Int {
        switch self { case .light: return 14; case .medium: return 22; case .heavy: return 34 }
    }
    var leafCount: Int {
        switch self { case .light: return 3; case .medium: return 6; case .heavy: return 10 }
    }
    var numberSize: Double {
        switch self { case .light: return 22; case .medium: return 25; case .heavy: return 30 }
    }
    var name: String {
        switch self { case .light: return "light"; case .medium: return "medium"; case .heavy: return "heavy" }
    }
}

enum MeadowBattleHapticStyle: String { case light, medium, heavy }

/// Presentation-only hit feel. This file is a literal port of `scripts/battle-hitfeel/hitfeel.py`; the pure Swift
/// regression compares every function with golden samples exported from that reference.
///
/// Layout units are the 760-wide battle canvas units. `age` is seconds since the impact fired and
/// `release(age)` is seconds since the shared hit-stop ended. Y grows downward. `direction` is +1 when the blow
/// travels to the right (hero toward monster) and -1 when it travels to the left.
enum MeadowBattleHitFeel {
    /// Shared with `MeadowBattleImpactClock`'s 0.10 s contact pose hold, so hero, monster and camera release together.
    static let hold = 0.10

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    static func smooth(_ x: Double) -> Double { let t = clamp01(x); return t * t * (3 - 2 * t) }
    static func easeOut(_ x: Double) -> Double { let t = clamp01(x); return 1 - (1 - t) * (1 - t) * (1 - t) }
    static func easeIn(_ x: Double) -> Double { let t = clamp01(x); return t * t }
    /// Deterministic pseudo-random in [0, 1): identical on every platform and frame rate.
    static func fraction(_ i: Int, _ salt: Int) -> Double {
        Double((i * 73 + salt * 37 + (i * i) * 11) % 101) / 100.0
    }
    static func release(_ age: Double) -> Double { max(0, age - hold) }

    // MARK: camera
    struct Camera: Equatable {
        var dx = 0.0, dy = 0.0, zoom = 0.0, rotation = 0.0
        static let zero = Camera()
    }

    /// Whole-world kick: frozen punch-in during the stop, then a damped push along the blow and back.
    static func camera(age: Double, tier: MeadowBattleHitTier, direction: Double = 1) -> Camera {
        guard age >= 0 else { return .zero }
        let k = tier.intensity
        if age < hold { return Camera(dx: 0, dy: 0, zoom: 0.032 * k * easeOut(age / 0.03), rotation: 0) }
        let r = release(age)
        return Camera(dx: direction * 6.0 * k * exp(-r * 10.0) * cos(r * 34.0),
                      dy: -2.2 * k * exp(-r * 12.0) * sin(r * 40.0 + 0.6),
                      zoom: 0.032 * k * exp(-r * 9.0),
                      rotation: direction * 0.0062 * k * exp(-r * 10.0) * sin(r * 30.0))
    }

    // MARK: monster reaction
    /// Horizontal displacement of the struck monster (+ = away from the attacker), in `canvasWidth` units.
    static func knockback(age: Double, tier: MeadowBattleHitTier, canvasWidth: Double = 760) -> Double {
        guard age >= hold else { return 0 }
        let k = tier.intensity
        let r = release(age)
        let distance = canvasWidth * 0.025 * (0.8 + 0.5 * (k - 0.7))
        return distance * 1.15 * (1 - exp(-r * 30.0)) * exp(-max(0, r - 0.10) * 5.5)
    }

    /// Squash and stretch about the monster's feet.
    static func squash(age: Double, tier: MeadowBattleHitTier) -> (x: Double, y: Double) {
        guard age >= 0 else { return (1, 1) }
        let k = tier.intensity
        let q: Double
        if age < hold { q = 0.6 * easeOut(age / 0.03) }
        else { let r = release(age); q = exp(-r * 10.0) * cos(r * 20.0) }
        return (1 + 0.05 * k * q, 1 - 0.07 * k * q)
    }

    /// Hit-flash alpha on the struck monster.
    static func flash(age: Double) -> Double {
        if age < 0 { return 0 }
        if age < 0.04 { return 1 }
        return 1 - smooth((age - 0.04) / 0.08)
    }

    // MARK: impact graphics
    struct Flare: Equatable { let radius: Double, alpha: Double }
    struct Ring: Equatable { let radius: Double, width: Double, alpha: Double }
    struct Spark: Equatable { let headX: Double, headY: Double, tailX: Double, tailY: Double, width: Double, alpha: Double, heat: Double }
    struct Dust: Equatable { let dx: Double, rx: Double, ry: Double, alpha: Double }
    struct Leaf: Equatable { let x: Double, y: Double, rotation: Double, size: Double, alpha: Double, tone: Int }
    struct NumberPop: Equatable { let scale: Double, yOffset: Double, alpha: Double, fontSize: Double }

    /// Short, sharp contact flare.
    static func flare(age: Double, tier: MeadowBattleHitTier) -> Flare? {
        guard age >= 0, age <= 0.14 else { return nil }
        let grow = 0.55 + 0.45 * easeOut(age / 0.04)
        let alpha = age < 0.06 ? 1.0 : 1 - easeIn((age - 0.06) / 0.08)
        return Flare(radius: tier.flareRadius * grow, alpha: alpha)
    }

    /// Expanding shock ring.
    static func ring(age: Double, tier: MeadowBattleHitTier) -> Ring? {
        let life = 0.26
        guard age >= 0, age <= life else { return nil }
        let t = age / life
        return Ring(radius: 8 + tier.flareRadius * 2.1 * easeOut(t), width: 4.0 * (1 - t) + 0.6, alpha: pow(1 - t, 1.3) * 0.85)
    }

    /// Directional streaks, relative to the impact point.
    static func sparks(age: Double, tier: MeadowBattleHitTier, direction: Double = 1) -> [Spark] {
        var out: [Spark] = []
        let k = tier.intensity
        for i in 0..<tier.sparkCount {
            let life = 0.16 + 0.22 * fraction(i, 3)
            if age < 0 || age >= life { continue }
            var angle = (direction > 0 ? 0.0 : Double.pi) + (fraction(i, 1) - 0.5) * 2 * (70.0 * Double.pi / 180)
            angle -= direction * 0.2
            let speed = (320 + 340 * fraction(i, 2)) * k
            let drag = 6.0
            let travel = speed * (1 - exp(-age * drag)) / drag
            let gravity = fraction(i, 4) > 0.55 ? 380.0 : 0.0
            let hx = cos(angle) * travel
            let hy = sin(angle) * travel + 0.5 * gravity * age * age
            let now = speed * exp(-age * drag)
            let length = max(4.0, min(46.0, now * 0.055))
            let lifeT = age / life
            out.append(Spark(headX: hx, headY: hy, tailX: hx - cos(angle) * length, tailY: hy - sin(angle) * length,
                             width: 3.2 - 2.0 * lifeT, alpha: pow(1 - lifeT, 0.8), heat: clamp01(lifeT * 1.4)))
        }
        return out
    }

    /// Ground puffs at the monster's feet once the stop releases.
    static func dust(age: Double, tier: MeadowBattleHitTier) -> [Dust] {
        let r = release(age)
        guard age >= hold, r <= 0.45 else { return [] }
        let k = tier.intensity
        let count = tier == .light ? 3 : 5
        let middle = tier == .light ? 1 : 2
        var out: [Dust] = []
        for i in 0..<count {
            let side = Double(i - middle) * 0.9
            let t = easeOut(r / 0.36)
            out.append(Dust(dx: side * 22 * k * t, rx: (10 + 36 * t) * (0.8 + 0.2 * k), ry: (10 + 36 * t) * 0.26,
                            alpha: 0.22 * (1 - clamp01(r / 0.45))))
        }
        return out
    }

    /// Foliage shed by the Forest Warden, relative to the impact point.
    static func leaves(age: Double, tier: MeadowBattleHitTier, direction: Double = 1) -> [Leaf] {
        var out: [Leaf] = []
        let k = tier.intensity
        for i in 0..<tier.leafCount {
            let life = 0.55 + 0.5 * fraction(i, 6)
            if age < 0 || age >= life { continue }
            let angle = (direction > 0 ? 0.0 : Double.pi) + (fraction(i, 8) - 0.5) * 2 * (80.0 * Double.pi / 180) - direction * 0.5
            let speed = (90 + 110 * fraction(i, 9)) * k
            let t = age
            let x = cos(angle) * speed * (1 - exp(-t * 3.2)) / 3.2 + sin(t * 7 + Double(i)) * 6
            let y = sin(angle) * speed * (1 - exp(-t * 3.2)) / 3.2 + 120.0 * t * t * (0.5 + fraction(i, 10)) + cos(t * 6 + Double(i)) * 3
            let spin = t * (6 + 8 * fraction(i, 11)) * (i % 2 == 1 ? 1.0 : -1.0)
            out.append(Leaf(x: x, y: y, rotation: spin, size: 5 + 4 * fraction(i, 12), alpha: 1 - easeIn(age / life), tone: i % 3))
        }
        return out
    }

    /// Damage number pop: overshoot scale, eased rise, late fade.
    static func number(age: Double, tier: MeadowBattleHitTier) -> NumberPop? {
        guard age >= 0, age <= 0.9 else { return nil }
        let pop = age < 0.09 ? 1.7 - 0.7 * easeOut(age / 0.09) : 1.0
        let rise = 34.0 * easeOut(min(age, 0.5) / 0.5)
        let alpha = age < 0.55 ? 1.0 : 1 - smooth((age - 0.55) / 0.35)
        return NumberPop(scale: pop, yOffset: -rise, alpha: alpha, fontSize: tier.numberSize)
    }

    // MARK: haptics
    static func haptic(tier: MeadowBattleHitTier) -> (style: MeadowBattleHapticStyle, intensity: Double) {
        switch tier {
        case .light: return (.light, 0.7)
        case .medium: return (.medium, 0.85)
        case .heavy: return (.heavy, 1.0)
        }
    }
}
