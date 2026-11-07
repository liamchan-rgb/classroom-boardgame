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

/// Plays only authored entry/exit paths. Travel still owns the walk phase.
/// On arrival, finish the current cycle at its designated exit before stop art.
struct AuthoredLocomotion {
    struct Plan: Decodable {
        struct Direction: Decodable { let entryPhase: Int; let exitPhase: Int }
        let walkPhaseCount: Int
        let frameMs: Double
        let finishSpeed: CGFloat
        let startFrames: [Int]
        let stopFrames: [Int]
        let directions: [Direction]
    }
    enum State: String { case idle, starting, walking, settling, stopping }
    let plan: Plan?
    private(set) var state = State.idle
    private(set) var frame = 0
    private(set) var facing = 0
    private(set) var distance: CGFloat = 0
    private var heading = WalkCycle()
    private var elapsed: TimeInterval = 0
    private var remaining: CGFloat = 0
    var phase: CGFloat { distance.truncatingRemainder(dividingBy: 24) / 24 }

    init(plan: Plan?) {
        if let plan {
            precondition(plan.walkPhaseCount == 8 && plan.frameMs > 0 && plan.finishSpeed > 0)
            precondition(plan.startFrames.count == 2 && plan.stopFrames.count == 2 && plan.directions.count == 8)
            precondition(plan.directions.allSatisfy { (0..<8).contains($0.entryPhase) && (0..<8).contains($0.exitPhase) })
        }
        self.plan = plan
    }

    func allowsTravel(requested: Bool) -> Bool {
        plan == nil || state == .idle || state == .walking || (state == .settling && requested)
    }

    mutating func reset() { self = AuthoredLocomotion(plan: plan) }

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
        let dt = max(0, seconds), duration = plan.frameMs / 1000
        let poseDistance = CGFloat(24) / CGFloat(plan.walkPhaseCount)
        switch state {
        case .idle:
            guard requested else { return }
            facing = heading.facing; state = .starting; elapsed = 0
            frame = plan.startFrames[0]
        case .starting:
            elapsed += dt
            if elapsed + 0.000000001 < duration * 2 {
                frame = plan.startFrames[min(1, Int((elapsed + 0.000000001) / duration))]
            } else {
                // The first walk pose is this direction's ORIGINAL walk01.
                // Do not substitute global phase0 after cyclic normalization.
                distance = CGFloat(plan.directions[facing].entryPhase) * poseDistance
                frame = WalkCycle.frame(at: distance); state = .walking
            }
        case .walking:
            distance += movement / WalkCycle.projectedScale(dx: dx, dy: dy)
            if requested {
                facing = heading.facing
                frame = WalkCycle.frame(at: distance)
            } else {
                let exitEnd = CGFloat(plan.directions[facing].exitPhase + 1) * poseDistance
                remaining = (exitEnd - distance.truncatingRemainder(dividingBy: 24) + 24)
                    .truncatingRemainder(dividingBy: 24)
                // At an exit boundary the visible pose is already the next
                // phase; finish one cycle rather than teleporting backwards.
                if remaining < 0.000001 { remaining = 24 }
                state = .settling
            }
        case .settling:
            if requested {
                state = .walking; facing = heading.facing
                distance += movement / WalkCycle.projectedScale(dx: dx, dy: dy)
                frame = WalkCycle.frame(at: distance)
            } else {
                let step = plan.finishSpeed * CGFloat(dt)
                if step + 0.000001 < remaining {
                    distance += step; remaining -= step; frame = WalkCycle.frame(at: distance)
                } else {
                    // Exit pose has had its full interval; stop01 follows it.
                    distance += remaining; elapsed = Double(max(0, step - remaining) / plan.finishSpeed)
                    state = .stopping; frame = plan.stopFrames[min(1, Int(elapsed / duration))]
                }
            }
        case .stopping:
            elapsed += dt
            if elapsed + 0.000000001 < duration * 2 { frame = plan.stopFrames[min(1, Int((elapsed + 0.000000001) / duration))] }
            else { state = .idle; distance = 0; frame = 0; elapsed = 0 }
        }
    }
}
