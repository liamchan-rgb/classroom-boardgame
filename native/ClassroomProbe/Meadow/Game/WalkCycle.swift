import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Distance, rather than the atmospheric clock, drives planted-foot cadence.
struct WalkCycle {
    private(set) var distance: CGFloat = 0
    private(set) var facing = 0
    private(set) var moving = false
    private(set) var frame = 0
    var phase: CGFloat { distance.truncatingRemainder(dividingBy: 24) / 24 }
    // The authored contact and passing frames already contain their leg lift.
    // Adding a whole-body bob raises every contact sole off the trail.
    var lift: CGFloat { 0 }

    // Clockwise from screen-down. Art rows retain the original cardinal order.
    private static let rows = [0, 4, 3, 7, 2, 6, 1, 5]
    private var heading: CGFloat?

    mutating func advance(from old: CGPoint, to new: CGPoint) {
        let dx = new.x - old.x, dy = new.y - old.y
        let movement = hypot(dx, dy)
        moving = movement > 0.001
        guard moving else {
            // Idle is pose 0. Clear the distance phase too, so resuming from
            // idle begins at the first walk pose instead of jumping back into
            // the stale mid-cycle pose from before the pause.
            distance = 0
            frame = 0
            return
        }
        distance += movement / Self.projectedScale(dx: dx, dy: dy)
        let angle = atan2(dx, dy)
        let sector = .pi / CGFloat(4)
        let difference = heading.map { atan2(sin(angle - $0), cos(angle - $0)) }
        // Five degrees of hysteresis prevent artwork flickering on curved roads.
        if difference == nil || abs(difference!) > sector / 2 + .pi / 36 {
            let index = (Int((angle / sector).rounded()) + 8) % 8
            facing = Self.rows[index]
            heading = CGFloat(index) * sector
        }
        frame = Self.frame(at: distance)
    }

    static func frame(at distance: CGFloat) -> Int {
        // Projected diagonal travel can land a few ulps below an exact tick.
        1 + Int(floor(max(0, distance) / 24 * CGFloat(HeroFrames.walkFrameCount) + 0.000000001)) % HeroFrames.walkFrameCount
    }

    /// Map art uses an elevated camera: depth travel projects shorter than
    /// profile travel. Apply the same metric to simulation, gait and review.
    static func projectedScale(dx: CGFloat, dy: CGFloat) -> CGFloat {
        let screen = hypot(dx, dy)
        return screen > 0.0001 ? screen / hypot(dx, dy * 2) : 1
    }
}

/// Distance windows for the eight authored walk poses, per facing. Uniform is
/// 3 units per pose (24 per cycle). Foot-locked windows give each pose the
/// distance its planted sole actually travels in the art, so the foot stays
/// put instead of stalling and then sliding. The cycle stays 24 units and the
/// frame space stays the shared 24-tick clock, so shadows and rigs agree.
struct GaitTiming: Equatable {
    static let poseCount = 8
    static let cycle: CGFloat = 24
    /// [facing][pose] distance; every row sums to `cycle`.
    let windows: [[CGFloat]]

    static let uniform = GaitTiming(windows: Array(repeating: Array(repeating: cycle / CGFloat(poseCount), count: poseCount), count: 8))

    /// Screen travel per facing row (art rows: down, left, up, right, then
    /// down-right, down-left, up-left, up-right). +y is screen-down.
    static let travel: [CGPoint] = [CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0),
                                    CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1), CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1)]

    /// - Parameters:
    ///   - soles: [facing][pose] two sole points in world points (sprite space).
    ///   - minimumStride: below this planted travel per cycle the art cannot
    ///     be foot-locked by timing alone; keep that facing uniform.
    ///   - strength: 0 = uniform, 1 = fully foot-locked.
    static func footLocked(soles: [[[CGPoint]]], minimumStride: CGFloat = 12, strength: CGFloat = 0.6) -> GaitTiming {
        precondition(soles.count == 8 && soles.allSatisfy { poses in poses.count == poseCount && poses.allSatisfy { pair in pair.count == 2 } })
        let rows = (0..<8).map { facing -> [CGFloat] in
            let v = travel[facing], length = hypot(v.x, v.y)
            let unit = CGPoint(x: v.x / length, y: v.y / length)
            let metric = hypot(unit.x, unit.y * 2)   // WalkCycle.projectedScale's inverse
            let planted = (0..<poseCount).map { pose -> CGFloat in
                let a = soles[facing][pose], b = soles[facing][(pose + 1) % poseCount]
                // The planted sole moves backward relative to the body.
                let back = (0..<2).map { -((b[$0].x - a[$0].x) * unit.x + (b[$0].y - a[$0].y) * unit.y) }
                return max(0, back.max()!) * metric
            }
            let total = planted.reduce(0, +)
            guard total >= minimumStride else { return Array(repeating: cycle / CGFloat(poseCount), count: poseCount) }
            let average = total / CGFloat(poseCount)
            let clamped = planted.map { min(max($0, average * 0.45), average * 1.8) }
            let scaled = clamped.map { $0 * cycle / clamped.reduce(0, +) }
            let blended = scaled.map { cycle / CGFloat(poseCount) + ($0 - cycle / CGFloat(poseCount)) * strength }
            let sum = blended.reduce(0, +)
            let row = blended.map { $0 * cycle / sum }
            // Keep uniform timing unless the windows actually reduce sole slip.
            let even = cycle / CGFloat(poseCount)
            let uniformSlip = planted.map { abs($0 - even) }.reduce(0, +)
            let lockedSlip = zip(planted, row).map { abs($0 - $1) }.reduce(0, +)
            return lockedSlip < uniformSlip - 0.01 ? row : Array(repeating: even, count: poseCount)
        }
        return GaitTiming(windows: rows)
    }

    /// P1 sole points per facing and walk pose, in sprite world points, from
    /// hero-gait.json `heroes[0]` (the same data the shadow caster reads).
    /// Pose p is sampled at tick 1 + 3p of the shared 24-tick clock.
    static func p1Soles(rigJSON data: Data, spriteSize: CGFloat = 64) -> [[[CGPoint]]]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let heroes = object["heroes"] as? [Any], let p1 = heroes.first as? [Any], p1.count == 8 else { return nil }
        var result: [[[CGPoint]]] = []
        for direction in p1 {
            guard let ticks = direction as? [[String: Any]], ticks.count >= 1 + 3 * poseCount else { return nil }
            var poses: [[CGPoint]] = []
            for pose in 0..<poseCount {
                guard let feet = ticks[1 + 3 * pose]["feet"] as? [[Double]], feet.count == 2,
                      feet.allSatisfy({ $0.count >= 2 }) else { return nil }
                poses.append(feet.map { CGPoint(x: CGFloat($0[0]) * spriteSize, y: CGFloat($0[1]) * spriteSize) })
            }
            result.append(poses)
        }
        return result
    }

    /// Cycle distance at which `pose` (0...8, 8 = full cycle) begins.
    func poseStart(facing: Int, pose: Int) -> CGFloat {
        windows[facing].prefix(max(0, min(Self.poseCount, pose))).reduce(0, +)
    }

    /// Same 1...24 frame space as `WalkCycle.frame(at:)`: pose p covers ticks
    /// 3p+1...3p+3, subdivided by progress through its window.
    func frame(at distance: CGFloat, facing: Int) -> Int {
        let row = windows[facing]
        // Uniform rows keep the exact original sampling, ulp handling included.
        if row.allSatisfy({ $0 == Self.cycle / CGFloat(Self.poseCount) }) { return WalkCycle.frame(at: distance) }
        var local = max(0, distance).truncatingRemainder(dividingBy: Self.cycle) + 0.000000001
        for pose in 0..<Self.poseCount {
            if local < row[pose] || pose == Self.poseCount - 1 {
                let ticks = HeroFrames.walkFrameCount / Self.poseCount
                let sub = min(ticks - 1, Int(floor(min(1, local / max(row[pose], 0.000001)) * CGFloat(ticks))))
                return 1 + pose * ticks + sub
            }
            local -= row[pose]
        }
        return 1
    }
}

/// Responsive P1 locomotion over the authored start/walk/stop art.
/// - Travel is never held back: the two start poses play over the first two
///   pose-distances of real movement, then the walk continues from this
///   facing's authored entry pose.
/// - Arrival stops at once: two quick stop poses, no stepping in place.
/// - Turns of 90° or more step through the intermediate facings (180° turns
///   go round via the camera-facing side) while the walk phase continues.
struct AuthoredLocomotion {
    struct Plan: Decodable {
        struct Direction: Decodable { let entryPhase: Int; let exitPhase: Int }
        let walkPhaseCount: Int
        let frameMs: Double
        let finishSpeed: CGFloat
        let startFrames: [Int]
        let stopFrames: [Int]
        let directions: [Direction]
        /// "uniform" when the art is foot-locked by construction (model v3), so
        /// pose windows must stay even instead of being re-timed from the soles.
        var timing: String? = nil
    }
    enum State: String { case idle, starting, walking, stopping }
    /// Each stop pose is held this long (half the authored 120 ms pose).
    static let stopHold: TimeInterval = 0.06
    /// Each intermediate facing during a wide turn is held this long.
    static let turnStep: TimeInterval = 0.045
    /// Sector (clockwise from screen-down) of each art row; inverse of WalkCycle.rows.
    static let sectorOfRow = [0, 6, 4, 2, 1, 7, 5, 3]
    static let rowOfSector = [0, 4, 3, 7, 2, 6, 1, 5]

    let plan: Plan?
    /// Per-facing pose windows; uniform unless the caller supplies foot-locked timing.
    let timing: GaitTiming
    private(set) var state = State.idle
    private(set) var frame = 0
    /// Displayed facing (art row); eases toward the heading during wide turns.
    private(set) var facing = 0
    private(set) var distance: CGFloat = 0
    private var heading = WalkCycle()
    private var elapsed: TimeInterval = 0
    private var startTravel: CGFloat = 0
    private var turnClock: TimeInterval = AuthoredLocomotion.turnStep
    var phase: CGFloat { distance.truncatingRemainder(dividingBy: 24) / 24 }

    init(plan: Plan?, timing: GaitTiming = .uniform) {
        if let plan {
            precondition(plan.walkPhaseCount == 8 && plan.frameMs > 0 && plan.finishSpeed > 0)
            precondition(plan.startFrames.count == 2 && plan.stopFrames.count == 2 && plan.directions.count == 8)
            precondition(plan.directions.allSatisfy { (0..<8).contains($0.entryPhase) && (0..<8).contains($0.exitPhase) })
        }
        self.plan = plan
        self.timing = timing
    }

    /// Movement is never gated by the animation.
    func allowsTravel(requested: Bool) -> Bool { true }

    mutating func reset() { self = AuthoredLocomotion(plan: plan, timing: timing) }

    /// Next displayed facing toward `target`: adjacent sectors switch at once,
    /// wider turns advance one sector per `turnStep`, 180° via screen-down.
    private mutating func turn(toward target: Int, seconds: TimeInterval) {
        let current = Self.sectorOfRow[facing], goal = Self.sectorOfRow[target]
        var delta = (goal - current + 8) % 8
        if delta > 4 { delta -= 8 }
        // A settled facing primes the clock so a new wide turn moves at once.
        if abs(delta) <= 1 { facing = target; turnClock = Self.turnStep; return }
        if abs(delta) == 4 { delta = current >= 4 ? 1 : -1 }   // round via the camera-facing side
        turnClock += seconds
        guard turnClock >= Self.turnStep else { return }
        turnClock = min(turnClock - Self.turnStep, Self.turnStep)
        facing = Self.rowOfSector[(current + (delta > 0 ? 1 : -1) + 8) % 8]
    }

    private mutating func beginStop(_ plan: Plan) {
        state = .stopping; elapsed = 0; startTravel = 0
        frame = plan.stopFrames[0]
    }

    mutating func advance(from old: CGPoint, to new: CGPoint, seconds: TimeInterval,
                          requested: Bool, headingHint: CGPoint = .zero) {
        let dx = new.x - old.x, dy = new.y - old.y, movement = hypot(dx, dy)
        if movement > 0.001 { heading.advance(from: old, to: new) }
        else if requested && hypot(headingHint.x, headingHint.y) > 0.001 {
            heading.advance(from: .zero, to: headingHint)
        }
        guard let plan else {
            if movement <= 0.001 { heading.advance(from: old, to: new) }
            facing = heading.facing; frame = heading.frame; distance = heading.distance
            state = heading.moving ? .walking : .idle
            return
        }
        let dt = max(0, seconds), moving = movement > 0.001
        let travelled = moving ? movement / WalkCycle.projectedScale(dx: dx, dy: dy) : 0
        let poseDistance = GaitTiming.cycle / CGFloat(plan.walkPhaseCount)
        if state == .idle && !(requested || moving) { return }
        if state == .idle || state == .stopping {
            if requested || moving {
                turn(toward: heading.facing, seconds: dt)
                elapsed = 0
                if state == .stopping {
                    // Re-order while the feet are still closing: keep striding, no new start.
                    state = .walking; distance += travelled
                    frame = timing.frame(at: distance, facing: facing)
                    return
                }
                // Standing: step off over the first two pose-distances of real travel.
                state = .starting; startTravel = travelled
                frame = plan.startFrames[startTravel < poseDistance ? 0 : 1]
                if startTravel >= poseDistance * 2 { enterWalk(plan, carry: startTravel - poseDistance * 2) }
                return
            }
            // Finish any wide turn while the feet close, then stand facing the heading.
            turn(toward: heading.facing, seconds: dt)
            elapsed += dt
            if elapsed + 0.000000001 < Self.stopHold * 2 {
                frame = plan.stopFrames[min(1, Int((elapsed + 0.000000001) / Self.stopHold))]
            } else { state = .idle; distance = 0; frame = 0; elapsed = 0; facing = heading.facing; turnClock = Self.turnStep }
            return
        }
        turn(toward: heading.facing, seconds: dt)
        if !requested && !moving { beginStop(plan); return }
        switch state {
        case .starting:
            startTravel += travelled
            if startTravel >= poseDistance * 2 { enterWalk(plan, carry: startTravel - poseDistance * 2) }
            else { frame = plan.startFrames[startTravel < poseDistance ? 0 : 1] }
        default:
            state = .walking
            distance += travelled
            frame = timing.frame(at: distance, facing: facing)
        }
    }

    /// The first walk pose is this direction's ORIGINAL walk01 (its entry phase).
    private mutating func enterWalk(_ plan: Plan, carry: CGFloat) {
        state = .walking
        distance = timing.poseStart(facing: facing, pose: plan.directions[facing].entryPhase) + carry
        frame = timing.frame(at: distance, facing: facing)
    }
}
