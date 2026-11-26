import UIKit

/// Complete deterministic terrain, elevation, terraced plateaus, water flow,
/// strictly aligned bridge, and cliff-embedded staircase layout.
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
        enum Orientation { case horizontal, vertical }
        let center: CGPoint
        /// Unit tangent along the road in map coordinates (+X right, +Y down).
        let roadDir: CGVector
        /// Exact SpriteKit zRotation aligning the chosen sprite axis to the road tangent.
        let angle: CGFloat
        let orientation: Orientation
        let mirror: Bool
        let halfSpan: CGFloat
        let halfWidth: CGFloat

        /// Oriented bounding box containment test so no boulders/trees/flowers ever clip bridge deck or railings.
        func contains(_ p: CGPoint, padAlong: CGFloat = 12, padAcross: CGFloat = 18) -> Bool {
            let dx = p.x - center.x, dy = p.y - center.y
            let along = abs(dx * roadDir.dx + dy * roadDir.dy)
            let across = abs(-dx * roadDir.dy + dy * roadDir.dx)
            return along < halfSpan + padAlong && across < halfWidth + padAcross
        }
    }
    struct Stair {
        enum Orientation { case front, side }
        let center: CGPoint
        /// Unit tangent pointing strictly UPHILL along the road in map coordinates.
        let uphillDir: CGVector
        let angle: CGFloat
        let orientation: Orientation
        let mirror: Bool
    }
    struct Plateau {
        let center: CGPoint
        let rx: CGFloat
        let ry: CGFloat
        let height: CGFloat
    }
    struct Hill {
        let center: CGPoint
        let rx: CGFloat
        let ry: CGFloat
        let height: CGFloat
    }

    let waterfall: CGPoint?
    let plungePool: CGPoint?
    let riverPoints: [CGPoint]
    let lake: Lake?
    let bridges: [Bridge]
    let stairs: [Stair]
    let plateaus: [Plateau]
    let hills: [Hill]
    let seed: UInt64
    let mapHeight: CGFloat

    /// Smooth continuous rolling valley elevation in [0, 1] (ZERO sharp max() creases / black hairlines!):
    /// Used for silky broad sunlit-vs-shaded hillside undulation across the entire meadow.
    func elevation(at p: CGPoint) -> CGFloat {
        let phase = Double(seed % 1024) * 0.61803398875
        let px = Double(p.x), py = Double(p.y)

        // 1. Broad silky rolling meadow swells (pure smooth C-infinity harmonics, no sharp abs() creases!)
        let swell1: Double = sin(px * 0.0042 + phase) * cos(py * 0.0046 - phase * 0.6)
        let swell2: Double = sin((px * 0.0068 + py * 0.0052) + phase * 1.35)
        let swell3: Double = cos((px * 0.0031 - py * 0.0059) + phase * 0.45)
        let baseDelta: Double = swell1 * 0.085 + swell2 * 0.048 + swell3 * 0.042
        var h: CGFloat = 0.36 + CGFloat(baseDelta)

        // 2. Wide, smooth additive Gaussian hills (never hard-creased!)
        for hill in hills {
            let nx = (p.x - hill.center.x) / max(1, hill.rx)
            let ny = (p.y - hill.center.y) / max(1, hill.ry)
            let r2 = nx * nx + ny * ny
            if r2 < 3.2 {
                h += hill.height * CGFloat(exp(-Double(r2) * 1.35))
            }
        }

        // 3. Gentle smooth elevation boost over highland plateaus (true vertical cliff wall comes from plateauMask!)
        let platMask = plateauMask(at: p)
        h += platMask * 0.14

        // 4. Smooth Northern Alpine Foothill rise
        let northLine = CGFloat(92 + 24 * sin(px * 0.0052 + phase) + 12 * cos(px * 0.012 - phase))
        if p.y < northLine + 90 {
            let t = max(0, min(1, (northLine + 90 - p.y) / 195.0))
            let smooth = t * t * (3.0 - 2.0 * t)
            h += 0.42 * smooth
        }

        // 5. Recessed river gorge & lake basin smoothly carved below meadow level
        let waterCarve = waterDepthFactor(at: p)
        if waterCarve > 0.001 {
            let carve = pow(waterCarve, 0.70)
            h = h * (1.0 - carve * 0.72) + 0.05 * carve
        }

        return max(0.02, min(1.0, h))
    }

    /// Crisp organic elevated terrace plateau footprint in [0, 1]:
    /// - 1.0 = flat elevated upper highland plateau
    /// - 0.0 = lower meadow valley
    /// Rendered by `meadowGroundFragment` as a TRUE 3/4 vertical 24px stratified mossy cliff wall
    /// on the south-facing drop, with sunlit overhanging grass lip and directional SE cast shadow!
    func plateauMask(at p: CGPoint) -> CGFloat {
        guard !plateaus.isEmpty else { return 0 }
        let phase = Double(seed % 1024) * 0.61803398875
        let px = Double(p.x), py = Double(p.y)
        let warpX = CGFloat(20.0 * sin(py * 0.013 + phase) + 9.0 * cos(px * 0.021 - phase))
        let warpY = CGFloat(14.0 * cos(px * 0.014 - phase * 0.7) + 7.0 * sin(py * 0.019 + phase))

        var best: CGFloat = 0
        for plat in plateaus {
            let dx = (p.x + warpX) - plat.center.x
            let dy = (p.y + warpY) - plat.center.y
            let nx = dx / max(1, plat.rx)
            let ny = dy / max(1, plat.ry)
            let ang = atan2(Double(ny), Double(nx))
            let wob = CGFloat(1.0 + 0.11 * sin(ang * 2.0 + phase) + 0.06 * cos(ang * 3.0 - phase * 1.1))
            let d = hypot(nx, ny) / wob
            if d < 1.16 {
                // Crisp terrace lip transition (0.88..1.08) so GPU draws a sharp sunlit cliff edge + 24px rock face!
                let t = max(0, min(1, (1.08 - d) / 0.20))
                let smooth = t * t * (3.0 - 2.0 * t)
                best = max(best, smooth)
            }
        }
        return best
    }

    /// Continuous smooth water depth factor in [0, 1] used by both heightfield carving, pier ray-marching & GPU water mask.
    func waterDepthFactor(at p: CGPoint) -> CGFloat {
        var best: CGFloat = 0
        if let plunge = plungePool {
            let nx = (p.x - plunge.x) / 60.0
            let ny = (p.y - plunge.y) / 42.0
            let ang = atan2(ny, nx)
            let wob = 1.0 + 0.08 * sin(ang * 3.0 + 0.5) + 0.05 * cos(ang * 5.0 - 0.3)
            let d = hypot(nx, ny) / wob
            if d < 1.0 { best = max(best, pow(1.0 - d, 0.62) * 0.96) }
        }
        if let lake {
            let d1: CGFloat = {
                let nx = (p.x - lake.center.x) / max(1, lake.rx)
                let ny = (p.y - lake.center.y) / max(1, lake.ry)
                let ang = atan2(ny, nx)
                let wob = 1.0 + 0.09 * sin(ang * 3.0 + 0.7) + 0.05 * cos(ang * 5.0 - 0.4)
                return hypot(nx, ny) / wob
            }()
            if d1 < 1.0 { best = max(best, pow(1.0 - d1, 0.58)) }
            let d2: CGFloat = {
                let nx = (p.x - lake.lobeCenter.x) / max(1, lake.lobeRx)
                let ny = (p.y - lake.lobeCenter.y) / max(1, lake.lobeRy)
                let ang = atan2(ny, nx)
                let wob = 1.0 + 0.08 * sin(ang * 4.0 - 0.6) + 0.04 * cos(ang * 6.0 + 0.2)
                return hypot(nx, ny) / wob
            }()
            if d2 < 1.0 { best = max(best, pow(1.0 - d2, 0.60) * 0.95) }
        }
        if riverPoints.count >= 2 {
            let count = riverPoints.count - 1
            for (segIdx, (a, b)) in zip(riverPoints, riverPoints.dropFirst()).enumerated() {
                let dx = b.x - a.x, dy = b.y - a.y
                let l2 = max(0.001, dx * dx + dy * dy)
                let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
                let u = (CGFloat(segIdx) + t) / CGFloat(count)
                let estuaryFlare = pow(max(0, (u - 0.80) / 0.20), 2.0) * 18.0
                var radius = 22 + 10 * u + sin(u * .pi * 4.0) * 3.0 + estuaryFlare
                // Keep channel neatly pinched to uniform 22px right under bridges so both abutments sit firmly on dry bank!
                for br in bridges {
                    let bd = hypot(p.x - br.center.x, p.y - br.center.y)
                    if bd < 52 {
                        let w = max(0, 1 - bd / 52)
                        radius = radius * (1 - w * 0.65) + 21.0 * (w * 0.65)
                    }
                }
                let dist = hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
                if dist < radius {
                    best = max(best, pow(1.0 - dist / radius, 0.66) * 0.88)
                }
            }
        }
        return best
    }

    func isNearBridge(_ p: CGPoint, padAlong: CGFloat = 14, padAcross: CGFloat = 20) -> Bool {
        bridges.contains { $0.contains(p, padAlong: padAlong, padAcross: padAcross) }
    }

    func isNearStair(_ p: CGPoint, radius: CGFloat = 34) -> Bool {
        stairs.contains { hypot($0.center.x - p.x, $0.center.y - p.y) < radius }
    }

    func isNearWater(_ p: CGPoint, margin: CGFloat = 18) -> Bool {
        if let plunge = plungePool, hypot(p.x - plunge.x, p.y - plunge.y) < 48 + margin { return true }
        if let wf = waterfall, abs(p.x - wf.x) < 70 + margin && abs(p.y - wf.y) < 62 + margin { return true }
        if let lake {
            let d1 = hypot((p.x - lake.center.x) / max(1, lake.rx + margin), (p.y - lake.center.y) / max(1, lake.ry + margin))
            if d1 < 1.0 { return true }
            let d2 = hypot((p.x - lake.lobeCenter.x) / max(1, lake.lobeRx + margin), (p.y - lake.lobeCenter.y) / max(1, lake.lobeRy + margin))
            if d2 < 1.0 { return true }
        }
        if riverPoints.count >= 2 {
            let riverR: CGFloat = 25 + margin
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

/// Synchronized GPU world masks:
/// - `roadMask` (full-res RGBA, opaque A=255):
///   - R: road coverage (cleanly cleared over open river water beneath bridges)
///   - G: 0..0.44 rural packed earth & wheel wear, 0.52..1.0 weathered cobblestone paving (nodes, bridges, stairs)
///   - B: connected mountain waterfall plunge -> winding river -> woodland lake water depth field
/// - `terrainField` (half-res RGBA, raw unpremultiplied):
///   - R: smooth continuous rolling elevation heightfield H(x,y) for silky hillshading
///   - G: water flow velocity X (0.5 + 0.5 * vx) inside water; OR 0.5 on dry land
///   - B: water flow velocity Y (0.5 + 0.5 * vy) inside water; OR 0.5 on dry land
///   - A: DUAL-USE CHANNEL! Inside water (roadMask.b > 0.02): water turbulence/foam energy;
///        On dry land: crisp elevated terrace plateau mask P(x,y) driving true 3/4 24px vertical cliff walls!
enum MeadowRoadMask {
    struct TerrainTextures {
        let roadMask: CGImage
        let terrainField: CGImage
    }

    private static func segmentIntersection(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let r = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let s = CGPoint(x: d.x - c.x, y: d.y - c.y)
        let denom = r.x * s.y - r.y * s.x
        guard abs(denom) > 1e-4 else { return nil }
        let u = ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / denom
        let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denom
        guard t >= 0.04 && t <= 0.96 && u >= 0.0 && u <= 1.0 else { return nil }
        return CGPoint(x: a.x + t * r.x, y: a.y + t * r.y)
    }

    static func planWaterSystem(
        network: TrailNetwork,
        nodePoints: [CGPoint],
        bossPoints: [CGPoint] = [],
        startPoint: CGPoint? = nil,
        mapHeight: CGFloat,
        seed: UInt64
    ) -> MeadowWaterSystem {
        let safeH = max(720, mapHeight)
        var rng = MeadowRandom(seed: seed ^ 0x5741544552504c41)

        // 1. Find the largest scenic off-road clearing for a generous organic mountain lake
        var bestLakeCenter: CGPoint?
        var bestLakeClear: CGFloat = 0
        let stepX: CGFloat = 46, stepY: CGFloat = 42
        var y: CGFloat = max(210, safeH * 0.30)
        while y <= safeH - 65 {
            var x: CGFloat = 150
            while x <= 1130 {
                let p = CGPoint(x: x, y: y)
                let minNode = nodePoints.map { hypot($0.x - p.x, ($0.y - 14) - p.y) }.min() ?? 500
                let minRoad = network.project(p).error
                let clear = min(minNode - 58, minRoad * 1.48)
                let flankBonus: CGFloat = (y > safeH * 0.48 ? 14 : 0) + (abs(x - 640) > 180 ? 10 : 0)
                let score = clear + flankBonus
                if clear > 74 && score > bestLakeClear {
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
            let usable = min(minNode - 62, minRoad * 1.30)
            let rx = max(82, min(148, usable * 0.94))
            let ry = rx * 0.66
            let leftClear = nodePoints.map { hypot($0.x - (lc.x - rx * 0.45), $0.y - lc.y) }.min() ?? 200
            let rightClear = nodePoints.map { hypot($0.x - (lc.x + rx * 0.45), $0.y - lc.y) }.min() ?? 200
            let lobeDir: CGFloat = rightClear >= leftClear ? 1 : -1
            let lobeCenter = CGPoint(x: lc.x + lobeDir * rx * 0.40, y: lc.y + ry * 0.14)
            lake = MeadowWaterSystem.Lake(
                center: lc, rx: rx, ry: ry,
                lobeCenter: lobeCenter, lobeRx: rx * 0.66, lobeRy: ry * 0.62
            )
        } else {
            lake = nil
        }

        // 2. Choose northern mountain gorge waterfall source upstream from the lake
        let targetFlowX = lake.map { $0.center.x > 640 ? max(180, $0.center.x - 260) : min(1100, $0.center.x + 260) } ?? 420
        var bestWF: CGPoint?
        var bestWFScore: CGFloat = -1e9
        for candX in stride(from: CGFloat(150), through: CGFloat(1130), by: 40) {
            for candY in [CGFloat(16), CGFloat(44), CGFloat(74)] {
                let p = CGPoint(x: candX, y: candY)
                let minNode = nodePoints.map { hypot($0.x - p.x, ($0.y - 20) - p.y) }.min() ?? 500
                let minRoad = network.project(p).error
                guard minNode > 112 && minRoad > 58 else { continue }
                let alignScore = -abs(candX - targetFlowX) * 0.34 - candY * 0.48
                let score = min(minNode, 240) + alignScore
                if score > bestWFScore {
                    bestWFScore = score
                    bestWF = p
                }
            }
        }
        let plungePool = bestWF.map { CGPoint(x: $0.x, y: $0.y + 42) }

        // 3. Trace smooth winding mountain river from waterfall plunge pool down to woodland lake,
        //    deflecting cleanly away from ALL buildings AND sharp road junctions!
        var river: [CGPoint] = []
        if let start = plungePool, let end = lake?.center {
            let distTotal = hypot(end.x - start.x, end.y - start.y)
            let steps = max(32, min(72, Int(distTotal / 30.0)))
            let waves = max(2.0, min(4.5, distTotal / 360.0))
            let swayDir: CGFloat = (seed & 1) == 0 ? 1 : -1
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let bx = start.x + (end.x - start.x) * t
                let by = start.y + (end.y - start.y) * t
                let perpX = -(end.y - start.y)
                let perpY = (end.x - start.x)
                let plen = max(1, hypot(perpX, perpY))
                let sway = sin(t * .pi * waves) * 62 * swayDir * sin(t * .pi)
                river.append(CGPoint(x: bx + perpX / plen * sway, y: by + perpY / plen * sway))
            }
            for _ in 0..<28 {
                for i in 1..<(river.count - 1) {
                    var p = river[i]
                    for n in nodePoints {
                        // Push river at least 124px away from every node/building apron so bridges NEVER crowd a building or road junction!
                        let bCenter = CGPoint(x: n.x, y: n.y - 12)
                        let dx = p.x - bCenter.x, dy = p.y - bCenter.y
                        let d = hypot(dx, dy)
                        let minClear: CGFloat = 124
                        if d < minClear && d > 0.1 {
                            let push = (minClear - d) * 0.48
                            p.x += dx / d * push
                            p.y += dy / d * push
                        }
                    }
                    let prev = river[i - 1], next = river[i + 1]
                    p.x = p.x * 0.62 + (prev.x + next.x) * 0.19
                    p.y = p.y * 0.62 + (prev.y + next.y) * 0.19
                    p.x = max(72, min(1208, p.x))
                    p.y = max(36, min(safeH - 42, p.y))
                    river[i] = p
                }
            }
        }

        // 4. IRONCLAD BRIDGE PLACEMENT:
        //    - Every crossing MUST lie on a straight road span (no sharp turns/corners under bridge!)
        //    - BOTH bridge abutments (hit ± roadDir * 44) MUST stay clear of buildings (> 52px)
        //    - Steer a full 4-point (±50px) river corridor cleanly PERPENDICULAR (90°) to the road so BOTH
        //      sides of BOTH stone abutments always rest 100% solidly on dry banks!
        var bridges: [MeadowWaterSystem.Bridge] = []
        if river.count >= 6 {
            struct RawCrossing {
                let hit: CGPoint
                let roadDir: CGVector
                let riverSegIdx: Int
                let edge: TrailNetwork.Edge
                let edgeDist: CGFloat
            }
            var candidates: [RawCrossing] = []
            for edge in network.edges {
                for (ra, rb) in zip(edge.trail.points, edge.trail.points.dropFirst()) {
                    for segIdx in 1..<(river.count - 2) {
                        guard let hit = segmentIntersection(ra, rb, river[segIdx], river[segIdx + 1]) else { continue }
                        let dAt = edge.trail.distance(nearestTo: hit)
                        // Require bridge to sit well away from road endpoints (where buildings & sharp junctions live)
                        let safeD = max(46, min(edge.trail.length - 46, dAt))
                        guard edge.trail.length >= 92 else { continue }
                        // If the raw crossing was close to a road turn/endpoint, shift crossing gently along the road onto the straighter span!
                        let shifted = abs(safeD - dAt) < 38 ? edge.trail.point(at: safeD) : hit
                        let pBack = edge.trail.point(at: max(0, safeD - 30))
                        let pFwd  = edge.trail.point(at: min(edge.trail.length, safeD + 30))
                        let inDx = shifted.x - pBack.x, inDy = shifted.y - pBack.y
                        let outDx = pFwd.x - shifted.x, outDy = pFwd.y - shifted.y
                        let inLen = max(0.001, hypot(inDx, inDy)), outLen = max(0.001, hypot(outDx, outDy))
                        let straightDot = (inDx * outDx + inDy * outDy) / (inLen * outLen)
                        guard straightDot > 0.86 else { continue } // Reject sharp hairpin turns under a bridge!

                        let rdx = pFwd.x - pBack.x, rdy = pFwd.y - pBack.y
                        let rlen = max(0.001, hypot(rdx, rdy))
                        let rDir = CGVector(dx: rdx / rlen, dy: rdy / rlen)

                        // Check BOTH stone abutment endpoints clear every node/building cleanly
                        let endA = CGPoint(x: shifted.x - rDir.dx * 42, y: shifted.y - rDir.dy * 42)
                        let endB = CGPoint(x: shifted.x + rDir.dx * 42, y: shifted.y + rDir.dy * 42)
                        let clearBuildings = nodePoints.allSatisfy { n in
                            let bc = CGPoint(x: n.x, y: n.y - 16)
                            return hypot(bc.x - shifted.x, bc.y - shifted.y) > 66
                                && hypot(bc.x - endA.x, bc.y - endA.y) > 48
                                && hypot(bc.x - endB.x, bc.y - endB.y) > 48
                        }
                        guard clearBuildings else { continue }
                        guard candidates.allSatisfy({ hypot($0.hit.x - shifted.x, $0.hit.y - shifted.y) > 105 }) else { continue }
                        candidates.append(RawCrossing(hit: shifted, roadDir: rDir, riverSegIdx: segIdx, edge: edge, edgeDist: safeD))
                    }
                }
            }

            // Steer river cleanly perpendicular across a full ±48px corridor at every bridge crossing!
            for cand in candidates.prefix(6) {
                let i = cand.riverSegIdx
                let curDirX = river[min(river.count - 1, i + 2)].x - river[max(0, i - 1)].x
                let curDirY = river[min(river.count - 1, i + 2)].y - river[max(0, i - 1)].y
                var px = -cand.roadDir.dy
                var py = cand.roadDir.dx
                if px * curDirX + py * curDirY < 0 { px = -px; py = -py }

                // Lock river center onto `cand.hit` and force 4 local control points cleanly perpendicular across ±56px!
                let offsets: [(Int, CGFloat, CGFloat)] = [
                    (i - 1, -56, 0.88),
                    (i,     -22, 1.00),
                    (i + 1, +22, 1.00),
                    (i + 2, +56, 0.88)
                ]
                for (idx, off, w) in offsets where idx > 0 && idx < river.count - 1 {
                    let target = CGPoint(x: cand.hit.x + px * off, y: cand.hit.y + py * off)
                    river[idx] = CGPoint(
                        x: river[idx].x * (1 - w) + target.x * w,
                        y: river[idx].y * (1 - w) + target.y * w
                    )
                }

                // Compute EXACT SpriteKit zRotation from canonicalized road tangent:
                var dx = cand.roadDir.dx
                var dy = cand.roadDir.dy
                let orientation: MeadowWaterSystem.Bridge.Orientation
                let skAngle: CGFloat
                let halfSpan: CGFloat
                let halfWidth: CGFloat
                if abs(dx) >= abs(dy) * 0.92 {
                    orientation = .horizontal
                    if dx < 0 { dx = -dx; dy = -dy }
                    skAngle = max(-0.46, min(0.46, atan2(-dy, dx)))
                    halfSpan = 46; halfWidth = 24
                } else {
                    orientation = .vertical
                    if dy < 0 { dx = -dx; dy = -dy }
                    let raw = atan2(-dy, dx)
                    skAngle = max(-0.46, min(0.46, raw + .pi / 2))
                    halfSpan = 46; halfWidth = 24
                }
                bridges.append(MeadowWaterSystem.Bridge(
                    center: cand.hit,
                    roadDir: CGVector(dx: dx, dy: dy),
                    angle: skAngle,
                    orientation: orientation,
                    mirror: false,
                    halfSpan: halfSpan,
                    halfWidth: halfWidth
                ))
            }
        }

        // 5. Design organic elevated highland plateaus (rendered as TRUE 24px 3/4 vertical stone-cliff terraces!)
        //    Rule: Keep plateau footprints strictly clear of the river/lake AND ensure NO neighboring building straddles a cliff wall!
        var plateaus: [MeadowWaterSystem.Plateau] = []
        let tempWater = MeadowWaterSystem(
            waterfall: bestWF, plungePool: plungePool, riverPoints: river, lake: lake,
            bridges: bridges, stairs: [], plateaus: [], hills: [], seed: seed, mapHeight: safeH
        )
        func tryAddPlateau(center: CGPoint, rx: CGFloat, ry: CGFloat, height: CGFloat) {
            // Never overlap a plateau cliff with the river or lake!
            let checkRadius = max(rx, ry) + 28
            guard !tempWater.isNearWater(center, margin: checkRadius * 0.72) else { return }
            guard plateaus.allSatisfy({ hypot($0.center.x - center.x, $0.center.y - center.y) > ($0.rx + rx) * 1.15 }) else { return }
            // Shrink slightly if any neighboring building apron OR roof sits inside the 26px south cliff wall band!
            func nodeStraddlesCliff(_ n: CGPoint, _ rxv: CGFloat, _ ryv: CGFloat) -> Bool {
                for probe in [n, CGPoint(x: n.x, y: n.y - 36), CGPoint(x: n.x, y: n.y - 68)] {
                    let d = hypot((probe.x - center.x) / max(1, rxv), (probe.y - center.y) / max(1, ryv))
                    if d > 0.70 && d < 1.34 { return true }
                }
                return false
            }
            var adjRx = rx, adjRy = ry
            if nodePoints.contains(where: { nodeStraddlesCliff($0, adjRx, adjRy) }) {
                adjRx *= 0.78; adjRy *= 0.78
            }
            guard adjRx >= 76 else { return }
            guard !nodePoints.contains(where: { nodeStraddlesCliff($0, adjRx, adjRy) }) else { return }
            plateaus.append(.init(center: center, rx: adjRx, ry: adjRy, height: height))
        }

        for bp in bossPoints {
            tryAddPlateau(center: CGPoint(x: bp.x, y: bp.y - 18), rx: 128, ry: 96, height: 0.24)
        }
        for np in nodePoints {
            if let sp = startPoint, hypot(np.x - sp.x, np.y - sp.y) < 130 { continue }
            if bossPoints.contains(where: { hypot($0.x - np.x, $0.y - np.y) < 160 }) { continue }
            if np.y > 180 && np.y < safeH - 180 && plateaus.count < bossPoints.count + 2 {
                tryAddPlateau(center: CGPoint(x: np.x, y: np.y - 16), rx: 112, ry: 84, height: 0.20)
            }
        }

        // Wide, silky rolling hills across the meadow (large radii 150-240px for smooth painterly undulation, ZERO black lines!)
        var hills: [MeadowWaterSystem.Hill] = []
        let hillTarget = min(14, max(8, Int(safeH / 160)))
        for _ in 0..<80 where hills.count < hillTarget {
            let hx = rng.value(40, 1240)
            let hy = rng.value(140, safeH - 50)
            if let lc = lake?.center, hypot(lc.x - hx, lc.y - hy) < 165 { continue }
            if hills.contains(where: { hypot($0.center.x - hx, $0.center.y - hy) < 195 }) { continue }
            let rx = rng.value(145, 230)
            let ry = rx * rng.value(0.68, 0.88)
            hills.append(.init(center: CGPoint(x: hx, y: hy), rx: rx, ry: ry, height: rng.value(0.08, 0.14)))
        }

        let provisional = MeadowWaterSystem(
            waterfall: bestWF, plungePool: plungePool, riverPoints: river, lake: lake,
            bridges: bridges, stairs: [], plateaus: plateaus, hills: hills, seed: seed, mapHeight: safeH
        )

        // 6. IRONCLAD STAIRCASE PLACEMENT (ZERO floating side-wall stairs on flat grass!):
        //    Place `MapStairsFront` ONLY where a straight, predominantly vertical N-S road
        //    physically climbs UP a REAL south-facing 24px terrace cliff wall (`pNorth > 0.72` && `pSouth < 0.28`)!
        var stairs: [MeadowWaterSystem.Stair] = []
        for edge in network.edges {
            guard edge.trail.length >= 88 else { continue }
            var bestAtEdge: (center: CGPoint, uphill: CGVector, angle: CGFloat, score: CGFloat)?
            var d: CGFloat = 40
            while d <= edge.trail.length - 40 {
                let pt = edge.trail.point(at: d)
                // Must sit RIGHT on a real south-facing terrace cliff drop!
                let pNorth = provisional.plateauMask(at: CGPoint(x: pt.x, y: pt.y - 22))
                let pSouth = provisional.plateauMask(at: CGPoint(x: pt.x, y: pt.y + 18))
                let pCenter = provisional.plateauMask(at: pt)
                if pNorth > 0.72 && pSouth < 0.28 && pCenter > 0.18 && pCenter < 0.82 {
                    let pBack = edge.trail.point(at: max(0, d - 26))
                    let pFwd  = edge.trail.point(at: min(edge.trail.length, d + 26))
                    let inDx = pt.x - pBack.x, inDy = pt.y - pBack.y
                    let outDx = pFwd.x - pt.x, outDy = pFwd.y - pt.y
                    let inLen = max(0.001, hypot(inDx, inDy)), outLen = max(0.001, hypot(outDx, outDy))
                    let straightDot = (inDx * outDx + inDy * outDy) / (inLen * outLen)

                    // Point uphill toward the higher plateau (north = negative Y in map coords!)
                    let pBackPlat = provisional.plateauMask(at: pBack)
                    let pFwdPlat  = provisional.plateauMask(at: pFwd)
                    let sgn: CGFloat = pFwdPlat >= pBackPlat ? 1 : -1
                    let ux0 = (pFwd.x - pBack.x) * sgn
                    let uy0 = (pFwd.y - pBack.y) * sgn
                    let ulen = max(0.001, hypot(ux0, uy0))
                    let ux = ux0 / ulen, uy = uy0 / ulen

                    // STRICT RULES: straight road (dot > 0.93), cleanly ascending northward (uy < -0.78 => within ±38° of vertical!),
                    // strictly clear of buildings (>54px), water (>42px), bridges (>85px)!
                    let clearAll = straightDot > 0.93
                        && uy < -0.78
                        && !provisional.isNearWater(pt, margin: 38)
                        && !provisional.isNearBridge(pt, padAlong: 48, padAcross: 48)
                        && nodePoints.allSatisfy { hypot($0.x - pt.x, ($0.y - 12) - pt.y) > 54 }
                    if clearAll {
                        // Place stair centered squarely on the 24px cliff wall (shifted +10px south of the 0.50 contour lip)
                        let stairCenter = CGPoint(x: pt.x - ux * 8, y: pt.y - uy * 8)
                        let raw = atan2(-uy, ux) // near +pi/2
                        let skAngle = max(-0.36, min(0.36, raw - .pi / 2))
                        let score = (pNorth - pSouth) + (-uy) * 0.5
                        if bestAtEdge == nil || score > bestAtEdge!.score {
                            bestAtEdge = (stairCenter, CGVector(dx: ux, dy: uy), skAngle, score)
                        }
                    }
                }
                d += 6
            }
            if let hit = bestAtEdge,
               stairs.allSatisfy({ hypot($0.center.x - hit.center.x, $0.center.y - hit.center.y) > 120 }) {
                stairs.append(MeadowWaterSystem.Stair(
                    center: hit.center,
                    uphillDir: hit.uphill,
                    angle: hit.angle,
                    orientation: .front,
                    mirror: false
                ))
            }
        }

        return MeadowWaterSystem(
            waterfall: bestWF, plungePool: plungePool, riverPoints: river, lake: lake,
            bridges: bridges, stairs: stairs, plateaus: plateaus, hills: hills, seed: seed, mapHeight: safeH
        )
    }

    static func make(network: TrailNetwork, bounds: CGRect, progress: ((Double) -> Void)? = nil) -> CGImage {
        makeTerrainTextures(network: network, bounds: bounds, water: nil, cobbleCenters: [], progress: progress).roadMask
    }

    static func makeWithWater(
        network: TrailNetwork,
        bounds: CGRect,
        water: MeadowWaterSystem?,
        cobbleCenters: [(point: CGPoint, radius: CGFloat)],
        progress: ((Double) -> Void)? = nil
    ) -> CGImage {
        makeTerrainTextures(network: network, bounds: bounds, water: water, cobbleCenters: cobbleCenters, progress: progress).roadMask
    }

    static func makeTerrainTextures(
        network: TrailNetwork,
        bounds: CGRect,
        water: MeadowWaterSystem?,
        cobbleCenters: [(point: CGPoint, radius: CGFloat)],
        progress: ((Double) -> Void)? = nil
    ) -> TerrainTextures {
        let width = Int(bounds.width), height = Int(bounds.height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let segments = network.edges.reduce(0) { $0 + max(0, $1.trail.points.count - 1) }
        var completed = 0

        var allCobbles = cobbleCenters
        if let water {
            for b in water.bridges {
                allCobbles.append((CGPoint(x: b.center.x - b.roadDir.dx * 40, y: b.center.y - b.roadDir.dy * 40), 42))
                allCobbles.append((CGPoint(x: b.center.x + b.roadDir.dx * 40, y: b.center.y + b.roadDir.dy * 40), 42))
            }
            for s in water.stairs {
                allCobbles.append((s.center, 46))
            }
        }

        // 1. Rasterize road coverage (R) + rural wear / cobblestone paving (G)
        for edge in network.edges {
            let radius = edge.width * 0.5 + 10
            for (a, b) in zip(edge.trail.points, edge.trail.points.dropFirst()) {
                defer { completed += 1; progress?(Double(completed) / Double(max(1, segments)) * 0.52) }
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
                } }
            }
        }

        // 2. Rasterize water depth (B) and temporary turbulence (A) into roadMask
        if let water {
            func paintWaterDisc(center: CGPoint, rx: CGFloat, ry: CGFloat, maxDepth: CGFloat, turb: CGFloat, lobes: CGFloat = 3.0) {
                let pad: CGFloat = 18
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
                    let wobble = 1.0 + 0.09 * sin(ang * lobes + 0.7) + 0.05 * cos(ang * (lobes + 2.0) - 0.4)
                    let d = hypot(nx, ny) / wobble
                    guard d < 1.0 else { continue }
                    let val = pow(max(0, 1 - d), 0.58) * maxDepth
                    let bVal = UInt8(min(255, max(0, Int(val * 255))))
                    let tVal = UInt8(min(255, max(0, Int(pow(max(0, 1 - d), 0.75) * turb * 255))))
                    let i = (y * width + x) * 4
                    rgba[i + 2] = max(rgba[i + 2], bVal)
                    rgba[i + 3] = max(rgba[i + 3], tVal)
                } }
            }

            if let plunge = water.plungePool {
                paintWaterDisc(center: plunge, rx: 60, ry: 42, maxDepth: 0.96, turb: 1.0, lobes: 3.0)
            }
            if water.riverPoints.count >= 2 {
                let count = water.riverPoints.count - 1
                for (segIdx, (a, b)) in zip(water.riverPoints, water.riverPoints.dropFirst()).enumerated() {
                    let dx = b.x - a.x, dy = b.y - a.y
                    let length2 = dx * dx + dy * dy
                    guard length2 > 0.001 else { continue }
                    let maxRadius: CGFloat = 40
                    let minX = max(0, Int(floor(min(a.x, b.x) - maxRadius - bounds.minX)))
                    let maxX = min(width - 1, Int(ceil(max(a.x, b.x) + maxRadius - bounds.minX)))
                    let minY = max(0, Int(floor(min(a.y, b.y) - maxRadius - bounds.minY)))
                    let maxY = min(height - 1, Int(ceil(max(a.y, b.y) + maxRadius - bounds.minY)))
                    guard minX <= maxX, minY <= maxY else { continue }
                    for y in minY...maxY { for x in minX...maxX {
                        let px = CGFloat(x) + bounds.minX + 0.5, py = CGFloat(y) + bounds.minY + 0.5
                        let t = max(0, min(1, ((px - a.x) * dx + (py - a.y) * dy) / length2))
                        let u = (CGFloat(segIdx) + t) / CGFloat(count)
                        let estuaryFlare = pow(max(0, (u - 0.80) / 0.20), 2.0) * 18.0
                        var radius = 22 + 10 * u + sin(u * .pi * 4.0) * 3.0 + estuaryFlare
                        for br in water.bridges {
                            let bd = hypot(px - br.center.x, py - br.center.y)
                            if bd < 52 {
                                let w = max(0, 1 - bd / 52)
                                radius = radius * (1 - w * 0.65) + 21.0 * (w * 0.65)
                            }
                        }
                        let distance = hypot(px - a.x - t * dx, py - a.y - t * dy)
                        guard distance < radius else { continue }
                        let val = pow(max(0, 1 - distance / radius), 0.66) * 0.88
                        let bVal = UInt8(min(255, max(0, Int(val * 255))))
                        let rapid = (0.34 + 0.30 * (1.0 - u)) * pow(max(0, 1 - distance / radius), 0.85)
                        let tVal = UInt8(min(255, max(0, Int(rapid * 255))))
                        let i = (y * width + x) * 4
                        rgba[i + 2] = max(rgba[i + 2], bVal)
                        rgba[i + 3] = max(rgba[i + 3], tVal)
                    } }
                }
            }
            if let lake = water.lake {
                paintWaterDisc(center: lake.center, rx: lake.rx, ry: lake.ry, maxDepth: 1.0, turb: 0.14, lobes: 3.0)
                paintWaterDisc(center: lake.lobeCenter, rx: lake.lobeRx, ry: lake.lobeRy, maxDepth: 0.96, turb: 0.10, lobes: 4.0)
            }

            // Clear muddy road dirt cleanly under the entire open water span beneath every bridge!
            for bridge in water.bridges {
                let rad: CGFloat = 34
                let minX = max(0, Int(floor(bridge.center.x - rad - bounds.minX)))
                let maxX = min(width - 1, Int(ceil(bridge.center.x + rad - bounds.minX)))
                let minY = max(0, Int(floor(bridge.center.y - rad - bounds.minY)))
                let maxY = min(height - 1, Int(ceil(bridge.center.y + rad - bounds.minY)))
                guard minX <= maxX, minY <= maxY else { continue }
                for y in minY...maxY { for x in minX...maxX {
                    let i = (y * width + x) * 4
                    if rgba[i + 2] > 40 {
                        let px = CGFloat(x) + bounds.minX + 0.5, py = CGFloat(y) + bounds.minY + 0.5
                        let along = abs((px - bridge.center.x) * bridge.roadDir.dx + (py - bridge.center.y) * bridge.roadDir.dy)
                        if along < 30 {
                            let fade = max(0, min(1, (along - 18) / 12.0))
                            rgba[i] = UInt8(CGFloat(rgba[i]) * fade)
                        }
                    }
                } }
            }
        }
        progress?(0.74)

        // 3. Generate half-res Terrain Field:
        //    - R = smooth rolling elevation H(x,y)
        //    - G = downstream flowX (in water) / 0.5 (dry land)
        //    - B = downstream flowY (in water) / 0.5 (dry land)
        //    - A = water turbulence (when roadMask.b > 4) OR crisp plateauMask P(x,y) (on dry land!)
        let fw = max(1, width / 2), fh = max(1, height / 2)
        var tBytes = [UInt8](repeating: 0, count: fw * fh * 4)

        var segInfo: [(a: CGPoint, b: CGPoint, dx: CGFloat, dy: CGFloat, l2: CGFloat, ux: CGFloat, uy: CGFloat)] = []
        if let water, water.riverPoints.count >= 2 {
            for (a, b) in zip(water.riverPoints, water.riverPoints.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y
                let l2 = max(0.001, dx * dx + dy * dy)
                let len = sqrt(l2)
                segInfo.append((a, b, dx, dy, l2, dx / len, dy / len))
            }
        }

        for fy in 0..<fh {
            let py = bounds.minY + (CGFloat(fy) + 0.5) * 2.0
            for fx in 0..<fw {
                let px = bounds.minX + (CGFloat(fx) + 0.5) * 2.0
                let p = CGPoint(x: px, y: py)
                let hVal: CGFloat = water?.elevation(at: p) ?? 0.36
                let sx = min(width - 1, fx * 2), sy = min(height - 1, fy * 2)
                let waterByte = rgba[(sy * width + sx) * 4 + 2]
                let turbByte = rgba[(sy * width + sx) * 4 + 3]

                var vx: CGFloat = 0, vy: CGFloat = 0.65
                if let water, waterByte > 2 {
                    var bestDist: CGFloat = .greatestFiniteMagnitude
                    for seg in segInfo {
                        let t = max(0, min(1, ((px - seg.a.x) * seg.dx + (py - seg.a.y) * seg.dy) / seg.l2))
                        let d = hypot(px - seg.a.x - t * seg.dx, py - seg.a.y - t * seg.dy)
                        if d < bestDist {
                            bestDist = d
                            vx = seg.ux
                            vy = seg.uy
                        }
                    }
                    if let plunge = water.plungePool {
                        let pd = hypot(px - plunge.x, py - plunge.y)
                        if pd < 66 {
                            let w = max(0, 1 - pd / 66)
                            let rdx = (px - plunge.x) / max(1, pd)
                            let rdy = (py - plunge.y) / max(1, pd)
                            vx = vx * (1 - w * 0.7) + rdx * w * 0.7
                            vy = vy * (1 - w * 0.7) + (rdy * 0.45 + 0.78) * w * 0.7
                        }
                    }
                    if let lake = water.lake {
                        let ld = hypot((px - lake.center.x) / max(1, lake.rx), (py - lake.center.y) / max(1, lake.ry))
                        if ld < 1.15 && bestDist > 26 {
                            let calm: CGFloat = 0.25
                            vx *= calm
                            vy = vy * calm + 0.10
                        }
                    }
                    let vlen = hypot(vx, vy)
                    if vlen > 1.0 { vx /= vlen; vy /= vlen }
                }

                // On dry land, store crisp elevated terrace plateau mask P(x,y) in Alpha for GPU 3/4 vertical cliff wall rendering!
                let aByte: UInt8
                if waterByte > 4 {
                    aByte = turbByte
                } else {
                    let platVal = water?.plateauMask(at: p) ?? 0
                    aByte = UInt8(min(255, max(0, Int(platVal * 255))))
                }

                let idx = (fy * fw + fx) * 4
                tBytes[idx] = UInt8(min(255, max(0, Int(hVal * 255))))
                tBytes[idx + 1] = UInt8(min(255, max(0, Int((vx * 0.5 + 0.5) * 255))))
                tBytes[idx + 2] = UInt8(min(255, max(0, Int((vy * 0.5 + 0.5) * 255))))
                tBytes[idx + 3] = aByte
            }
        }
        // Keep roadMask opaque (A=255) so SpriteKit fallback never premultiplies away road/water RGB.
        for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 255 }
        progress?(1.0)

        let roadData = Data(rgba) as CFData
        let terrData = Data(tBytes) as CFData
        guard let roadProvider = CGDataProvider(data: roadData),
              let roadImg = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: roadProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ),
              let terrProvider = CGDataProvider(data: terrData),
              let terrImg = CGImage(
                width: fw, height: fh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: fw * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: terrProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { fatalError("Terrain mask allocation failed") }
        return TerrainTextures(roadMask: roadImg, terrainField: terrImg)
    }
}
