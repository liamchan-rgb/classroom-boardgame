import Foundation

/// Chooses healing VFX from the HP the target actually gained after clamping.
public enum HealingEffectTier: String, CaseIterable, Codable, Equatable {
    case micro, standard, strong

    public static let frameCount = 20
    public static let framesPerSecond = 20.0
    public static let duration = Double(frameCount) / framesPerSecond

    public static func classify(actualHPGained: Int) -> HealingEffectTier? {
        guard actualHPGained > 0 else { return nil }
        if actualHPGained <= 3 { return .micro }
        if actualHPGained <= 8 { return .standard }
        return .strong
    }

    /// The original art is authored at 20 FPS. Crossfade adjacent frames so
    /// the animation advances smoothly on the battle display's 60 Hz clock.
    public func frameBlend(at age: Double) -> HealingEffectFrameBlend? {
        guard age.isFinite, age >= 0, age < Self.duration else { return nil }
        let position = age * Self.framesPerSecond
        let lower = min(Self.frameCount - 1, max(0, Int(position)))
        let upper = min(Self.frameCount - 1, lower + 1)
        let fraction = position - Double(lower)
        let weight = fraction * fraction * (3 - 2 * fraction)
        return HealingEffectFrameBlend(lower: lower, upper: upper, upperWeight: weight)
    }

    /// A short green spill follows the sprite sequence and lights the receiver
    /// and the ground. Strong healing gets a broader, brighter environmental lift.
    public func lightEnvelope(at age: Double) -> Double {
        guard age.isFinite, age >= 0, age < Self.duration else { return 0 }
        func smooth(_ value: Double) -> Double {
            let t = min(1, max(0, value))
            return t * t * (3 - 2 * t)
        }
        let rise = smooth(age / 0.10)
        let fade = 1 - smooth((age - 0.46) / 0.54)
        let tierScale: Double
        switch self {
        case .micro: tierScale = 0.48
        case .standard: tierScale = 0.78
        case .strong: tierScale = 1.0
        }
        return rise * fade * tierScale
    }

    /// Keeps authored white-green cores readable over the actor sprite.
    /// Vertical anchor measured from the top of the original cell.
    /// The strong variant's ellipse is authored near y=0.66, so that ring
    /// registers to the ground while its branches rise over the recipient.
    public var canvasGroundAnchorY: Double {
        switch self {
        case .micro: return 1.0
        case .standard: return 0.90
        case .strong: return 0.66
        }
    }

    public var artOpacity: Double {
        switch self {
        case .micro: return 0.92
        case .standard: return 0.48
        case .strong: return 0.62
        }
    }
}

public struct HealingEffectFrameBlend: Equatable {
    public let lower: Int
    public let upper: Int
    public let upperWeight: Double

    public init(lower: Int, upper: Int, upperWeight: Double) {
        self.lower = lower
        self.upper = upper
        self.upperWeight = upperWeight
    }
}
