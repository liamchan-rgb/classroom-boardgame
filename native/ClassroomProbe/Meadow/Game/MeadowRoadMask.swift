import UIKit

struct MeadowBrookCrossing {
    let center: CGPoint
    let points: [CGPoint]
}

/// Union of distances to every road segment, in world pixels. Junctions share
/// one mask/material, so overlapping paths never create a seam or dark stripe.
/// The unused blue channel carries an optional winding woodland brook that crosses
/// one horizontal road segment underneath a `MapBridgeWood` sprite.
enum MeadowRoadMask {
    static func findBrookCrossing(network: TrailNetwork, nodePoints: [CGPoint], seed: UInt64) -> MeadowBrookCrossing? {
        struct Candidate { let point: CGPoint; let score: CGFloat }
        var best: Candidate?
        for edge in network.edges {
            let total = edge.trail.length
            guard total >= 125 else { continue }
            // Sample middle band away from both node aprons
            for frac in [CGFloat(0.45), 0.50, 0.55] {
                let d = total * frac
                let p = edge.trail.point(at: d)
                let a = edge.trail.point(at: max(0, d - 14))
                let b = edge.trail.point(at: min(total, d + 14))
                let dx = b.x - a.x, dy = b.y - a.y
                let len = hypot(dx, dy)
                guard len > 10 else { continue }
                let slope = abs(dy) / max(1, abs(dx))
                guard slope < 0.30 else { continue } // Closely matches MapBridgeWood's horizontal orientation
                guard nodePoints.allSatisfy({ hypot($0.x - p.x, $0.y - p.y) > 115 }) else { continue }
                // Ensure no OTHER road edge passes too close to the brook crossing
                let otherTooClose = network.edges.contains { other in
                    if other.from == edge.from && other.to == edge.to { return false }
                    for (sa, sb) in zip(other.trail.points, other.trail.points.dropFirst()) {
                        let sdx = sb.x - sa.x, sdy = sb.y - sa.y
                        let sl2 = max(0.001, sdx * sdx + sdy * sdy)
                        let st = max(0, min(1, ((p.x - sa.x) * sdx + (p.y - sa.y) * sdy) / sl2))
                        if hypot(p.x - sa.x - st * sdx, p.y - sa.y - st * sdy) < 92 { return true }
                    }
                    return false
                }
                if otherTooClose { continue }
                let centerBonus = 1 - abs(p.x - 640) / 800
                let score = (0.35 - slope) * 2.5 + centerBonus + CGFloat((seed &+ UInt64(edge.from * 31 + edge.to)) % 7) * 0.03
                if best == nil || score > best!.score { best = Candidate(point: p, score: score) }
            }
        }
        guard let pick = best else { return nil }
        // Build a natural gently winding N-S brook passing straight under the bridge, stopping cleanly before any building
        let swayDir: CGFloat = (seed & 1) == 0 ? 1 : -1
        func traceHalf(sign: CGFloat) -> [CGPoint] {
            var pts: [CGPoint] = []
            for step in 1...10 {
                let f = CGFloat(step) / 10.0
                let dist = f * 108
                let bend = sin(f * .pi) * 24 * swayDir * sign
                let pt = CGPoint(x: pick.point.x + bend, y: pick.point.y + sign * dist)
                // Stop brook cleanly before touching any building footprint (building sits at nodePoint.y - 26)
                let hitsNode = nodePoints.contains { hypot($0.x - pt.x, ($0.y - 26) - pt.y) < 92 || hypot($0.x - pt.x, $0.y - pt.y) < 88 }
                if hitsNode { break }
                pts.append(pt)
            }
            return pts
        }
        let north = traceHalf(sign: -1).reversed()
        let south = traceHalf(sign: 1)
        let curve = Array(north) + [pick.point] + south
        guard curve.count >= 5 else { return nil }
        return MeadowBrookCrossing(center: pick.point, points: curve)
    }

    static func make(network: TrailNetwork, bounds: CGRect, progress: ((Double) -> Void)? = nil) -> CGImage {
        makeWithBrook(network: network, bounds: bounds, brook: nil, progress: progress)
    }

    static func makeWithBrook(network: TrailNetwork, bounds: CGRect, brook: MeadowBrookCrossing?, progress: ((Double) -> Void)? = nil) -> CGImage {
        let width = Int(bounds.width), height = Int(bounds.height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let segments = network.edges.reduce(0) { $0 + max(0, $1.trail.points.count - 1) }
        var completed = 0
        for edge in network.edges {
            let radius = edge.width * 0.5 + 9
            for (a, b) in zip(edge.trail.points, edge.trail.points.dropFirst()) {
                defer { completed += 1; progress?(Double(completed) / Double(max(1, segments))) }
                let dx = b.x - a.x, dy = b.y - a.y
                let length2 = dx * dx + dy * dy
                guard length2 > 0.001 else { continue }
                let minX = max(0, Int(floor(min(a.x, b.x) - radius - bounds.minX)))
                let maxX = min(width - 1, Int(ceil(max(a.x, b.x) + radius - bounds.minX)))
                let minY = max(0, Int(floor(min(a.y, b.y) - radius - bounds.minY)))
                let maxY = min(height - 1, Int(ceil(max(a.y, b.y) + radius - bounds.minY)))
                guard minX <= maxX, minY <= maxY else { continue }
                for y in minY...maxY { for x in minX...maxX {
                    let px = CGFloat(x) + bounds.minX + 0.5, py = CGFloat(y) + bounds.minY + 0.5
                    let t = max(0, min(1, ((px - a.x) * dx + (py - a.y) * dy) / length2))
                    let distance = hypot(px - a.x - t * dx, py - a.y - t * dy)
                    guard distance < radius else { continue }
                    let coverage = UInt8(min(255, max(0, (1 - distance / radius) * 255)))
                    let rutDistance = abs(distance - edge.width * 0.22)
                    let rut = UInt8(max(0, 1 - rutDistance / max(2, edge.width * 0.10)) * 255)
                    let i = (y * width + x) * 4
                    rgba[i] = max(rgba[i], coverage)
                    rgba[i + 1] = max(rgba[i + 1], rut)
                    rgba[i + 3] = 255
                } }
            }
        }
        // Rasterize optional woodland brook into the blue channel with tapered natural ends
        if let brook, brook.points.count >= 2 {
            let count = brook.points.count - 1
            for (segIdx, (a, b)) in zip(brook.points, brook.points.dropFirst()).enumerated() {
                let dx = b.x - a.x, dy = b.y - a.y
                let length2 = dx * dx + dy * dy
                guard length2 > 0.001 else { continue }
                let maxRadius: CGFloat = 22
                let minX = max(0, Int(floor(min(a.x, b.x) - maxRadius - bounds.minX)))
                let maxX = min(width - 1, Int(ceil(max(a.x, b.x) + maxRadius - bounds.minX)))
                let minY = max(0, Int(floor(min(a.y, b.y) - maxRadius - bounds.minY)))
                let maxY = min(height - 1, Int(ceil(max(a.y, b.y) + maxRadius - bounds.minY)))
                guard minX <= maxX, minY <= maxY else { continue }
                for y in minY...maxY { for x in minX...maxX {
                    let px = CGFloat(x) + bounds.minX + 0.5, py = CGFloat(y) + bounds.minY + 0.5
                    let t = max(0, min(1, ((px - a.x) * dx + (py - a.y) * dy) / length2))
                    let u = (CGFloat(segIdx) + t) / CGFloat(count) // 0 ... 1 along stream
                    let taper = sin(u * .pi)
                    let radius = 8 + 13 * pow(max(0, taper), 0.55)
                    let distance = hypot(px - a.x - t * dx, py - a.y - t * dy)
                    guard distance < radius else { continue }
                    let water = UInt8(min(255, max(0, (1 - distance / radius) * min(1, taper * 3.2) * 255)))
                    let i = (y * width + x) * 4
                    rgba[i + 2] = max(rgba[i + 2], water)
                } }
            }
        }
        // Keep coverage in RGB, not premultiplied alpha; the shader owns feathering.
        for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 255 }
        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { fatalError("Road mask allocation failed") }
        return image
    }
}
