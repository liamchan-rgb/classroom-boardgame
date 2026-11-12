import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Subtle idle breathing: a vertical swell about the sprite's ground anchor
/// (anchorPoint y = 0.125, below the soles), so feet stay planted. It eases in
/// only while standing and eases out as soon as any start, walk or stop pose
/// plays. The Metal shadow caster receives the same scale.
struct HeroBreathing: Equatable {
    static let amplitude: CGFloat = 0.012
    static let period: TimeInterval = 3.4
    static let easeIn: TimeInterval = 0.6
    static let easeOut: TimeInterval = 0.15
    /// Pixel-alignment captures must stay at the authored size.
    static let enabled = !ProcessInfo.processInfo.arguments.contains("-alignmentReview")
        && !ProcessInfo.processInfo.arguments.contains("-noBreathing")
    private(set) var weight: CGFloat = 0

    mutating func advance(idle: Bool, seconds: TimeInterval) {
        let rate = CGFloat(max(0, seconds) / (idle ? Self.easeIn : Self.easeOut))
        weight = idle ? min(1, weight + rate) : max(0, weight - rate)
    }

    /// 1 when exhaled or moving; at most 1 + amplitude at full inhale.
    /// Party members are offset so they do not breathe in unison.
    func yScale(time: TimeInterval, index: Int) -> CGFloat {
        guard weight > 0 else { return 1 }
        let phase = (time / Self.period + Double(index) * 0.37) * 2 * Double.pi
        let breath = CGFloat(0.5 - 0.5 * cos(phase))
        let eased = weight * weight * (3 - 2 * weight)
        return 1 + Self.amplitude * breath * eased
    }
}
