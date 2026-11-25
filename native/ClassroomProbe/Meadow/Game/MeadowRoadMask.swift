import UIKit

struct MeadowWaterSystem {
    struct Lake {
        let center: CGPoint
        let rx: CGFloat
        let ry: CGFloat
        let lobeCenter: CGPoint
        let lobeRx: CGFloat
        let lobeRy: CGFloat
    }
    struct Bridge {
        let center: CGPoint
        let angle: CGFloat
    }
    let waterfall: CGPoint?
    let plungePool: CGPoint?
    let riverPoints: [CGPoint]
    let lake: Lake?
    let bridges: [Bridge]

    /// Signed distance-like check: returns true if `p` falls inside or within `margin` of the waterfall, river, or lake.
    func isNearWater(_ p: CGPoint, margin: CGFloat = 18) -> Bool {
        if let plunge = plungePool, hypot(p.x - plunge.x, p.y - plunge.y) < 42 + margin { return true }
        if let wf = waterfall, abs(p.x - wf.x) < 62 + margin && abs(p.y - wf.y) < 52 + margin { return true }
        if let lake {
            let d1 = hypot((p.x - lake.center.x) / max(1, lake.rx + margin), (p.y - lake.center.y) / max(1, lake.ry + margin))
            if d1 < 1.0 { return true }
            let d2 = hypot((p.x - lake.lobeCenter.x) / max(1, lake.lobeRx + margin), (p.y - lake.lobeCenter.y) / max(1, lake.lobeRy + margin))
            if d2 < 1.0 { return true }
        }
        if riverPoints.count >= 2 {
            let riverR: CGFloat = 24 + margin
            for (a, b) in zip(riverPoints, riverPoints.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                let l2 = max(0.001, dx * dx + dy * dy)
                let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
                if hypot(p.x - a.x - t * dx, p.y - a.y - t * dy) < riverR { return true }
            }
        }
        return false
    }
}

/// Union of distances to every road segment, in world pixels.
/// - Red channel: road coverage (feathered in shader)
/// - Green channel: 0..0.45 rural wheel wear, 0.52..1.0 weathered cobblestone paving
/// - Blue channel: connected valley water system depth field (mountain waterfall -> winding river -> woodland lake)
enum MeadowRoadMask {
    private static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let l2 = max(0.001, dx * dx + dy * dy)
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    private static func segmentIntersection(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let r = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let s = CGPoint(x: d.x - c.x, y: d.y - c.y)
        let denom = r.x * s.y - r.y * s.x
        guard abs(denom) > 1e-4 else { return nil }
        let u = ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / denom
        let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denom
        guard t >= 0.05 && t <= 0.95 && u >= 0.0 && u <= 1.0 else { return nil }
        return CGPoint(x: a.x + t * r.x, y: a.y + t * r.y)
    }

    static func planWaterSystem(network: TrailNetwork, nodePoints: [CGPoint], mapHeight: CGFloat, seed: UInt64) -> MeadowWaterSystem {
        let safeH = max(720, mapHeight)

        // 1. Find the largest scenic off-road clearing for a generous organic woodland lake
        var bestLakeCenter: CGPoint?
        var bestLakeClear: CGFloat = 0
        let stepX: CGFloat = 48, stepY: CGFloat = 44
        var y: CGFloat = max(190, safeH * 0.28)
        while y <= safeH - 70 {
            var x: CGFloat = 150
            while x <= 1130 {
                let p = CGPoint(x: x, y: y)
                let minNode = nodePoints.map { hypot($0.x - p.x, ($0.y - 14) - p.y) }.min() ?? 500
                let minRoad = network.project(p).error
                let clear = min(minNode - 58, minRoad * 1.48)
                // Gentle preference for lower-right / lower-flank scenic bays
                let flankBonus: CGFloat = (x > 700 ? 12 : 0) + (y > safeH * 0.45 ? 10 : 0)
                let score = clear + flankBonus
                if clear > 76 && score > bestLakeClear {
                    bestLakeClear = score
                    bestLakeCenter = p
                }
                x += stepX
            }
            y += stepY
        }

        let lake: MeadowWaterSystem.Lake?
        if let lc = bestLakeCenter {
            let minNode = nodePoints.map { hypot($0.x - lc.x, ($0.y - 14) - lc.y) }.min() ?? 260
            let minRoad = network.project(lc).error
            let usable = min(minNode - 64, minRoad * 1.28)
            let rx = max(76, min(142, usable * 0.92))
            let ry = rx * 0.64
            // Secondary bay lobe shifted toward the side with MORE open space
            let leftClear = nodePoints.map { hypot($0.x - (lc.x - rx * 0.45), $0.y - lc.y) }.min() ?? 200
            let rightClear = nodePoints.map { hypot($0.x - (lc.x + rx * 0.45), $0.y - lc.y) }.min() ?? 200
            let lobeDir: CGFloat = rightClear >= leftClear ? 1 : -1
            let lobeCenter = CGPoint(x: lc.x + lobeDir * rx * 0.38, y: lc.y + ry * 0.14)
            lake = MeadowWaterSystem.Lake(
                center: lc, rx: rx, ry: ry,
                lobeCenter: lobeCenter, lobeRx: rx * 0.64, lobeRy: ry * 0.60
            )
        } else {
            lake = nil
        }

        // 2. Choose northern highland cliff waterfall source upstream from the lake
        let targetFlowX = lake.map { $0.center.x > 640 ? max(180, $0.center.x - 280) : min(1100, $0.center.x + 280) } ?? 380
        var bestWF: CGPoint?
        var bestWFScore: CGFloat = -1e9
        for candX in stride(from: CGFloat(140), through: CGFloat(1140), by: 45) {
            for candY in [CGFloat(22), CGFloat(56), CGFloat(88)] {
                let p = CGPoint(x: candX, y: candY)
                let minNode = nodePoints.map { hypot($0.x - p.x, ($0.y - 20) - p.y) }.min() ?? 500
                let minRoad = network.project(p).error
                guard minNode > 108 && minRoad > 54 else { continue }
                let alignScore = -abs(candX - targetFlowX) * 0.35 - candY * 0.4
                let score = min(minNode, 240) + alignScore
                if score > bestWFScore {
                    bestWFScore = score
                    bestWF = p
                }
            }
        }
        let plungePool = bestWF.map { CGPoint(x: $0.x, y: $0.y + 34) }

        // 3. Trace graceful winding river from waterfall plunge pool down to the woodland lake
        var river: [CGPoint] = []
        if let start = plungePool, let end = lake?.center {
            let steps = 24
            let swayDir: CGFloat = (seed & 1) == 0 ? 1 : -1
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let bx = start.x + (end.x - start.x) * t
                let by = start.y + (end.y - start.y) * t
                let perpX = -(end.y - start.y)
                let perpY = (end.x - start.x)
                let plen = max(1, hypot(perpX, perpY))
                let sway = sin(t * .pi * 2.0) * 44 * swayDir * sin(t * .pi)
                river.append(CGPoint(x: bx + perpX / plen * sway, y: by + perpY / plen * sway))
            }
            // Gently deflect river curve around every node building footprint while keeping it silky smooth
            for _ in 0..<22 {
                for i in 1..<(river.count - 1) {
                    var p = river[i]
                    for n in nodePoints {
                        let bCenter = CGPoint(x: n.x, y: n.y - 16)
                        let dx = p.x - bCenter.x, dy = p.y - bCenter.y
                        let d = hypot(dx, dy)
                        let minClear: CGFloat = 104
                        if d < minClear && d > 0.1 {
                            let push = (minClear - d) * 0.42
                            p.x += dx / d * push
                            p.y += dy / d * push
                        }
                    }
                    // Laplacian smoothing for natural meandering bends
                    let prev = river[i - 1], next = river[i + 1]
                    p.x = p.x * 0.62 + (prev.x + next.x) * 0.19
                    p.y = p.y * 0.62 + (prev.y + next.y) * 0.19
                    p.x = max(70, min(1210, p.x))
                    p.y = max(30, min(safeH - 40, p.y))
                    river[i] = p
                }
            }
        }

        // 4. Detect clean road-river bridge crossings
        var bridges: [MeadowWaterSystem.Bridge] = []
        if river.count >= 2 {
            for edge in network.edges {
                for (ra, rb) in zip(edge.trail.points, edge.trail.points.dropFirst()) {
                    for (wa, wb) in zip(river, river.dropFirst()) {
                        guard let hit = segmentIntersection(ra, rb, wa, wb) else { continue }
                        guard nodePoints.allSatisfy({ hypot($0.x - hit.x, $0.y - hit.y) > 76 }) else { continue }
                        guard bridges.allSatisfy({ hypot($0.center.x - hit.x, $0.center.y - hit.y) > 115 }) else { continue }
                        let angle = atan2(rb.y - ra.y, rb.x - ra.x)
                        // Normalize heading into [-pi/2, pi/2] and softly clamp visual rotation so 3/4 bridge stays natural
                        var norm = angle
                        if norm > .pi / 2 { norm -= .pi }
                        if norm < -.pi / 2 { norm += .pi }
                        let clamped = max(-0.42, min(0.42, -norm)) // SpriteKit Y-up flips sign
                        bridges.append(MeadowWaterSystem.Bridge(center: hit, angle: clamped))
                        if bridges.count >= 2 { break }
                    }
                    if bridges.count >= 2 { break }
                }
                if bridges.count >= 2 { break }
            }
        }

        return MeadowWaterSystem(waterfall: bestWF, plungePool: plungePool, riverPoints: river, lake: lake, bridges: bridges)
    }

    static func make(network: TrailNetwork, bounds: CGRect, progress: ((Double) -> Void)? = nil) -> CGImage {
        makeWithWater(network: network, bounds: bounds, water: nil, cobbleCenters: [], progress: progress)
    }

    static func makeWithWater(
        network: TrailNetwork,
        bounds: CGRect,
        water: MeadowWaterSystem?,
        cobbleCenters: [(point: CGPoint, radius: CGFloat)],
        progress: ((Double) -> Void)? = nil
    ) -> CGImage {
        let width = Int(bounds.width), height = Int(bounds.height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let segments = network.edges.reduce(0) { $0 + max(0, $1.trail.points.count - 1) }
        var completed = 0

        // Combine landmark cobble zones + bridge approach cobble zones
        var allCobbles = cobbleCenters
        if let water {
            for b in water.bridges { allCobbles.append((b.center, 86)) }
        }

        // 1. Rasterize road coverage (R) + wheel wear / cobblestone paving (G)
        for edge in network.edges {
            let radius = edge.width * 0.5 + 10
            for (a, b) in zip(edge.trail.points, edge.trail.points.dropFirst()) {
                defer { completed += 1; progress?(Double(completed) / Double(max(1, segments)) * 0.72) }
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
                    // Compute cobblestone paving strength (0.55..1.0 in green channel) near landmarks/bridges
                    var cobble: CGFloat = 0
                    for zone in allCobbles {
                        let cd = hypot(px - zone.point.x, py - zone.point.y)
                        if cd < zone.radius {
                            cobble = max(cobble, 1 - cd / zone.radius)
                        }
                    }
                    let greenByte: UInt8
                    if cobble > 0.05 {
                        greenByte = UInt8(min(255, max(136, Int(136 + cobble * 119))))
                    } else {
                        let rutDistance = abs(distance - edge.width * 0.22)
                        let rut = max(0, 1 - rutDistance / max(2, edge.width * 0.10))
                        greenByte = UInt8(min(115, max(0, Int(rut * 115))))
                    }
                    let i = (y * width + x) * 4
                    rgba[i] = max(rgba[i], coverage)
                    rgba[i + 1] = max(rgba[i + 1], greenByte)
                    rgba[i + 3] = 255
                } }
            }
        }

        // 2. Rasterize connected mountain waterfall plunge pool -> winding river -> woodland lake into Blue channel
        if let water {
            func paintWaterDisc(center: CGPoint, rx: CGFloat, ry: CGFloat, maxDepth: CGFloat = 1.0) {
                let pad: CGFloat = 16
                let minX = max(0, Int(floor(center.x - rx - pad - bounds.minX)))
                let maxX = min(width - 1, Int(ceil(center.x + rx + pad - bounds.minX)))
                let minY = max(0, Int(floor(center.y - ry - pad - bounds.minY)))
                let maxY = min(height - 1, Int(ceil(center.y + ry + pad - bounds.minY)))
                guard minX <= maxX, minY <= maxY else { return }
                for y in minY...maxY { for x in minX...maxX {
                    let px = CGFloat(x) + bounds.minX + 0.5, py = CGFloat(y) + bounds.minY + 0.5
                    let nx = (px - center.x) / max(1, rx)
                    let ny = (py - center.y) / max(1, ry)
                    let ang = atan2(ny, nx)
                    let wobble = 1.0 + 0.09 * sin(ang * 3.0 + 0.7) + 0.05 * cos(ang * 5.0 - 0.4)
                    let d = hypot(nx, ny) / wobble
                    guard d < 1.0 else { continue }
                    let val = pow(max(0, 1 - d), 0.62) * maxDepth
                    let bVal = UInt8(min(255, max(0, Int(val * 255))))
                    let i = (y * width + x) * 4
                    rgba[i + 2] = max(rgba[i + 2], bVal)
                } }
            }

            if let plunge = water.plungePool {
                paintWaterDisc(center: plunge, rx: 58, ry: 40, maxDepth: 0.94)
            }
            if water.riverPoints.count >= 2 {
                let count = water.riverPoints.count - 1
                for (segIdx, (a, b)) in zip(water.riverPoints, water.riverPoints.dropFirst()).enumerated() {
                    let dx = b.x - a.x, dy = b.y - a.y
                    let length2 = dx * dx + dy * dy
                    guard length2 > 0.001 else { continue }
                    let maxRadius: CGFloat = 34
                    let minX = max(0, Int(floor(min(a.x, b.x) - maxRadius - bounds.minX)))
                    let maxX = min(width - 1, Int(ceil(max(a.x, b.x) + maxRadius - bounds.minX)))
                    let minY = max(0, Int(floor(min(a.y, b.y) - maxRadius - bounds.minY)))
                    let maxY = min(height - 1, Int(ceil(max(a.y, b.y) + maxRadius - bounds.minY)))
                    guard minX <= maxX, minY <= maxY else { continue }
                    for y in minY...maxY { for x in minX...maxX {
                        let px = CGFloat(x) + bounds.minX + 0.5, py = CGFloat(y) + bounds.minY + 0.5
                        let t = max(0, min(1, ((px - a.x) * dx + (py - a.y) * dy) / length2))
                        let u = (CGFloat(segIdx) + t) / CGFloat(count)
                        // River gently widens as it flows from mountain waterfall toward the woodland lake!
                        let radius = 21 + 11 * u + sin(u * .pi * 3) * 2.5
                        let distance = hypot(px - a.x - t * dx, py - a.y - t * dy)
                        guard distance < radius else { continue }
                        let val = pow(max(0, 1 - distance / radius), 0.72) * 0.86
                        let bVal = UInt8(min(255, max(0, Int(val * 255))))
                        let i = (y * width + x) * 4
                        rgba[i + 2] = max(rgba[i + 2], bVal)
                    } }
                }
            }
            if let lake = water.lake {
                paintWaterDisc(center: lake.center, rx: lake.rx, ry: lake.ry, maxDepth: 1.0)
                paintWaterDisc(center: lake.lobeCenter, rx: lake.lobeRx, ry: lake.lobeRy, maxDepth: 0.96)
            }
        }
        progress?(1.0)

        // Keep coverage in RGB, not premultiplied alpha; the shader owns feathering.
        for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 255 }
        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { fatalError("Road mask allocation failed") }
        return image
    }
}
