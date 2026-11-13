import Foundation

/// Map coordinates use the reference image's top-left origin (1280 × 720).
struct Trail {
    let points: [CGPoint]
    let segmentLengths: [CGFloat]
    let length: CGFloat

    init(points: [CGPoint]) {
        precondition(points.count >= 2, "A trail needs two points")
        self.points = points
        segmentLengths = zip(points, points.dropFirst()).map { a, b in
            let dx = b.x - a.x
            let dy = b.y - a.y
            return (dx * dx + dy * dy).squareRoot()
        }
        length = segmentLengths.reduce(0, +)
    }

    func point(at distance: CGFloat) -> CGPoint {
        if distance <= 0 { return points.first! }
        if distance >= length { return points.last! }
        var remaining = max(0, min(distance, length))
        for index in segmentLengths.indices {
            let segment = segmentLengths[index]
            if remaining <= segment && segment > 0 {
                let t = remaining / segment
                return CGPoint(x: points[index].x + (points[index + 1].x - points[index].x) * t,
                               y: points[index].y + (points[index + 1].y - points[index].y) * t)
            }
            remaining -= segment
        }
        return points.last!
    }

    /// Project a tap onto the road, so characters never cut across the grass.
    func distance(nearestTo point: CGPoint) -> CGFloat {
        var bestSquared = CGFloat.greatestFiniteMagnitude
        var bestDistance: CGFloat = 0
        var traversed: CGFloat = 0
        for index in segmentLengths.indices {
            let a = points[index]
            let b = points[index + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let squared = dx * dx + dy * dy
            let t = squared > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / squared)) : 0
            let x = a.x + dx * t
            let y = a.y + dy * t
            let error = (point.x - x) * (point.x - x) + (point.y - y) * (point.y - y)
            if error < bestSquared {
                bestSquared = error
                bestDistance = traversed + segmentLengths[index] * t
            }
            traversed += segmentLengths[index]
        }
        return bestDistance
    }

    func subsection(from start: CGFloat, to end: CGFloat) -> [CGPoint] {
        let low = min(start, end)
        let high = max(start, end)
        var result = [point(at: low)]
        var distance: CGFloat = 0
        for index in segmentLengths.indices {
            distance += segmentLengths[index]
            if distance > low && distance < high { result.append(points[index + 1]) }
        }
        result.append(point(at: high))
        return start <= end ? result : Array(result.reversed())
    }

    static func smooth(_ controls: [CGPoint], steps: Int = 8) -> Trail {
        guard controls.count > 2 else { return Trail(points: controls) }
        var output: [CGPoint] = []
        for index in 0..<(controls.count - 1) {
            let a = controls[max(index - 1, 0)]
            let b = controls[index]
            let c = controls[index + 1]
            let d = controls[min(index + 2, controls.count - 1)]
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                let t2 = t * t
                let t3 = t2 * t
                func interpolate(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                output.append(CGPoint(x: interpolate(a.x, b.x, c.x, d.x),
                                      y: interpolate(a.y, b.y, c.y, d.y)))
            }
        }
        output.append(controls.last!)
        return Trail(points: output)
    }

    static let meadow = Trail(points: [
        CGPoint(x: 285, y: 442), CGPoint(x: 330, y: 447),
        CGPoint(x: 383, y: 448), CGPoint(x: 440, y: 444),
        CGPoint(x: 503, y: 445), CGPoint(x: 555, y: 441),
        CGPoint(x: 578, y: 412), CGPoint(x: 601, y: 378),
        CGPoint(x: 629, y: 346), CGPoint(x: 655, y: 313),
        CGPoint(x: 684, y: 282), CGPoint(x: 713, y: 252),
        CGPoint(x: 735, y: 223), CGPoint(x: 744, y: 209)
    ])
}

struct Traveler {
    var distance: CGFloat
    var direction: CGFloat
    var destination: CGFloat?
    var isWaiting = false
    let speed: CGFloat

    /// Reflect at endpoints, including large timesteps; an explicit destination stops on arrival.
    mutating func advance(by seconds: TimeInterval, on trail: Trail) {
        guard seconds > 0, trail.length > 0, !isWaiting else { return }
        let step = speed * CGFloat(seconds)
        if let target = destination {
            let delta = target - distance
            direction = delta >= 0 ? 1 : -1
            if abs(delta) <= step {
                distance = target
                destination = nil
                isWaiting = true
            } else {
                distance += direction * step
            }
        } else {
            let period = trail.length * 2
            let unfolded = direction >= 0 ? distance : period - distance
            let phase = (unfolded + step).truncatingRemainder(dividingBy: period)
            distance = phase <= trail.length ? phase : period - phase
            direction = phase < trail.length ? 1 : -1
        }
        distance = max(0, min(trail.length, distance))
    }
}

