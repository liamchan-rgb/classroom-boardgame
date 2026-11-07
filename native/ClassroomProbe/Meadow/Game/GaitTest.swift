import Foundation

/// Straight lanes bypass the map roads, while the scene still uses production
/// textures, WalkCycle, HeroPose and the Metal caster.
struct GaitTest {
    static let names = ["下 ↓", "左 ←", "上 ↑", "右 →", "右下 ↘", "左下 ↙", "左上 ↖", "右上 ↗"]
    static let menuOrder = [2, 7, 3, 4, 0, 5, 1, 6]
    private static let directions: [CGVector] = [
        CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0),
        CGVector(dx: 0.70710678, dy: 0.70710678), CGVector(dx: -0.70710678, dy: 0.70710678),
        CGVector(dx: -0.70710678, dy: -0.70710678), CGVector(dx: 0.70710678, dy: -0.70710678)
    ]
    private(set) var facing = 6
    private(set) var distance: CGFloat = 0
    var paused = false
    var slow = false
    var projection: CGFloat {
        let d = Self.directions[facing]
        return WalkCycle.projectedScale(dx: d.dx, dy: d.dy)
    }
    var phase: CGFloat { distance.truncatingRemainder(dividingBy: 24) / 24 }
    var frame: Int { WalkCycle.frame(at: distance) }
    var speed: CGFloat { HeroFrames.reviewSpeed * (slow ? 0.25 : 1) }

    mutating func select(_ facing: Int) {
        self.facing = min(7, max(0, facing)); distance = 0
    }
    mutating func advance(_ seconds: TimeInterval) {
        guard !paused else { return }
        distance = (distance + speed * CGFloat(seconds)).truncatingRemainder(dividingBy: 144)
    }
    mutating func step() {
        paused = true
        distance = (distance + 24 / CGFloat(HeroFrames.authoredFrameCount(heroIndex: 0))).truncatingRemainder(dividingBy: 144)
    }
    func point(for hero: Int) -> CGPoint {
        let direction = Self.directions[facing], travel = (distance - 72) * projection
        return CGPoint(x: 530 + CGFloat(hero) * 110 + direction.dx * travel, y: 400 + direction.dy * travel)
    }
}
