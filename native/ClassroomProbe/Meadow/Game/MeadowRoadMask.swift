import UIKit

/// Complete deterministic terrain, elevation, water flow, bridge, and staircase layout
/// computed from the map's road network and landmarks. Works identically for new & legacy saves.
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
        let radius: CGFloat
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

    /// Deterministic continuous terrain elevation in [0, 1] at any map coordinate `p`:
    /// - 0.02..0.20: carved sunken river gorge & woodland lake basin
    /// - 0.28..0.40: valley meadow floor
    /// - 0.42..0.68: rolling exploration hills & elevated terraced plateaus (Boss/Highlands)
    /// - 0.72..1.00: northern alpine mountain massif & waterfall cliff rim
    func elevation(at p: CGPoint) -> CGFloat {
        let phase = Double(seed % 1024) * 0.61803398875
        let px = Double(p.x), py = Double(p.y)

        // 1. Broad rolling valley undulation across the entire exploration zone (never a flat plane!)
        let macro1: Double = sin(px * 0.0052 + phase) * cos(py * 0.0058 - phase * 0.6)
        let macro2: Double = sin((px * 0.0088 + py * 0.0064) + phase * 1.35)
        let ridge: Double  = 1.0 - abs(sin(px * 0.0044 - py * 0.0049 + phase * 0.85))
        let baseDelta: Double = macro1 * 0.075 + macro2 * 0.048 + (ridge - 0.5) * 0.055
        var h: CGFloat = 0.34 + CGFloat(baseDelta)

        // 2. Sculpted interior exploration knolls & flanking rolling hills
        for hill in hills {
            let nx = (p.x - hill.center.x) / max(1, hill.rx)
            let ny = (p.y - hill.center.y) / max(1, hill.ry)
            let r2 = nx * nx + ny * ny
            if r2 < 1.0 {
                let t = 1.0 - r2
                h += hill.height * t * t * (3.0 - 2.0 * t)
            }
        }

        // 3. Elevated organic highland plateaus (domain-warped gentle rise — NO artificial circular rings!)
        for plat in plateaus {
            let warpX = CGFloat(24.0 * sin(py * 0.011 + phase) + 12.0 * cos(px * 0.019 - phase))
            let warpY = CGFloat(22.0 * cos(px * 0.012 - phase * 0.7) + 10.0 * sin(py * 0.017 + phase))
            let dx = (p.x + warpX) - plat.center.x
            let dy = ((p.y + warpY) - plat.center.y) * 1.18
            let d = hypot(dx, dy)
            if d < plat.radius * 1.65 {
                let ang = atan2(Double(dy), Double(dx))
                let wob = CGFloat(1.0 + 0.16 * sin(ang * 2.0 + phase) + 0.09 * cos(ang * 3.0 - phase * 1.2))
                let nd = d / max(1, plat.radius * wob)
                let t = max(0, min(1, (1.42 - nd) / 0.86))
                let terrace = t * t * (3.0 - 2.0 * t)
                h = max(h, 0.34 + plat.height * terrace)
            }
        }

        // 4. Majestic Northern Alpine Mountain Massif rise
        let northLine = CGFloat(88 + 26 * sin(px * 0.0055 + phase) + 14 * cos(px * 0.013 - phase))
        if p.y < northLine + 65 {
            let t = max(0, min(1, (northLine + 65 - p.y) / 165.0))
            let mountain = t * t * (3.0 - 2.0 * t)
            let crags = CGFloat(0.055 * sin(px * 0.022 + phase) + 0.035 * cos(px * 0.041 - py * 0.02))
            h = max(h, 0.36 + (0.62 + crags) * mountain)
        }
        // Subtle alpine gorge notch right behind the waterfall so water pours down a canyon cleft
        if let wf = waterfall, p.y < wf.y + 38 {
            let gx = abs(p.x - wf.x)
            if gx < 76 {
                let notch = max(0, 1 - gx / 76)
                let yRamp = max(0, min(1, (p.y - (wf.y - 65)) / 95.0))
                h -= notch * notch * 0.26 * yRamp
            }
        }

        // 5. Carve sunken river gorge & woodland lake basin BELOW the meadow level!
        let waterCarve = waterDepthFactor(at: p)
        if waterCarve > 0.001 {
            // Smooth bank drop from meadow height down into recessed riverbed / lake bed
            let carve = pow(waterCarve, 0.58)
            h = h * (1.0 - carve * 0.82) + 0.04 * carve
        }

        return max(0.01, min(1.0, h))
    }

    /// Continuous smooth water depth factor in [0, 1] used by both heightfield carving & GPU water mask.
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
                // Gently widen river along its journey and flare smoothly into a natural delta estuary at the lake mouth!
                let estuaryFlare = pow(max(0, (u - 0.80) / 0.20), 2.0) * 18.0
                let radius = 23 + 12 * u + sin(u * .pi * 4.0) * 3.5 + estuaryFlare
                let dist = hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
                if dist < radius {
                    best = max(best, pow(1.0 - dist / radius, 0.66) * 0.88)
                }
            }
        }
        return best
    }

    /// Signed distance-like check: returns true if `p` falls inside or within `margin` of the waterfall, river, or lake.
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
            let riverR: CGFloat = 26 + margin
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
/// - `roadMask` (full-res RGBA):
///   - R: road coverage (cleanly cleared over open river water beneath bridges)
///   - G: 0..0.44 rural packed earth & wheel wear, 0.52..1.0 weathered cobblestone paving (nodes, bridges, stairs)
///   - B: connected mountain waterfall plunge -> winding river -> woodland lake water depth field
///   - A: water turbulence & foam energy (plunge pool churn + narrow rapids)
/// - `terrainField` (half-res RGBA, bilinear interpolated on GPU):
///   - R: continuous 3D elevation heightfield H(x,y) for directional hillshading & terrace relief
///   - G: water flow velocity X (0.5 + 0.5 * vx, downstream)
///   - B: water flow velocity Y (0.5 + 0.5 * vy, downstream)
///   - A: steep terrace / riverbank rock embankment exposure mask
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
        // Waterfall plunges from mountain gorge base into a deep rocky plunge pool
        let plungePool = bestWF.map { CGPoint(x: $0.x, y: $0.y + 42) }

        // 3. Trace smooth winding mountain river from waterfall plunge pool down to the woodland lake
        var river: [CGPoint] = []
        if let start = plungePool, let end = lake?.center {
            let distTotal = hypot(end.x - start.x, end.y - start.y)
            let steps = max(28, min(64, Int(distTotal / 34.0)))
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
            for _ in 0..<24 {
                for i in 1..<(river.count - 1) {
                    var p = river[i]
                    for n in nodePoints {
                        let bCenter = CGPoint(x: n.x, y: n.y - 16)
                        let dx = p.x - bCenter.x, dy = p.y - bCenter.y
                        let d = hypot(dx, dy)
                        let minClear: CGFloat = 114
                        if d < minClear && d > 0.1 {
                            let push = (minClear - d) * 0.44
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

        // 4. Detect ALL road-river bridge crossings & steer local river perpendicular to the road for lock-tight alignment!
        var bridges: [MeadowWaterSystem.Bridge] = []
        if river.count >= 4 {
            struct RawCrossing {
                let hit: CGPoint
                let roadDir: CGVector
                let riverSegIdx: Int
            }
            var candidates: [RawCrossing] = []
            for edge in network.edges {
                for (ra, rb) in zip(edge.trail.points, edge.trail.points.dropFirst()) {
                    for segIdx in 0..<(river.count - 1) {
                        guard let hit = segmentIntersection(ra, rb, river[segIdx], river[segIdx + 1]) else { continue }
                        // Keep bridge clear of building centers, while NEVER leaving a bare road wading into water!
                        guard nodePoints.allSatisfy({ hypot($0.x - hit.x, ($0.y - 14) - hit.y) > 42 }) else { continue }
                        guard candidates.allSatisfy({ hypot($0.hit.x - hit.x, $0.hit.y - hit.y) > 85 }) else { continue }
                        let dAt = edge.trail.distance(nearestTo: hit)
                        let p0 = edge.trail.point(at: max(0, dAt - 18))
                        let p1 = edge.trail.point(at: min(edge.trail.length, dAt + 18))
                        let rdx = p1.x - p0.x, rdy = p1.y - p0.y
                        let rlen = max(0.001, hypot(rdx, rdy))
                        candidates.append(RawCrossing(hit: hit, roadDir: CGVector(dx: rdx / rlen, dy: rdy / rlen), riverSegIdx: segIdx))
                    }
                }
            }

            // Bridge up to 6 crossings so even tall epic maps NEVER leave a road wading through bare water!
            for cand in candidates.prefix(6) {
                let i = cand.riverSegIdx
                if i >= 1 && i + 1 < river.count - 1 {
                    let curDirX = river[i + 1].x - river[i].x
                    let curDirY = river[i + 1].y - river[i].y
                    // Choose perpendicular to roadDir that points same general way as current river flow
                    var px = -cand.roadDir.dy
                    var py = cand.roadDir.dx
                    if px * curDirX + py * curDirY < 0 { px = -px; py = -py }
                    let halfSpan: CGFloat = 24
                    let targetA = CGPoint(x: cand.hit.x - px * halfSpan, y: cand.hit.y - py * halfSpan)
                    let targetB = CGPoint(x: cand.hit.x + px * halfSpan, y: cand.hit.y + py * halfSpan)
                    river[i] = CGPoint(x: river[i].x * 0.45 + targetA.x * 0.55, y: river[i].y * 0.45 + targetA.y * 0.55)
                    river[i + 1] = CGPoint(x: river[i + 1].x * 0.45 + targetB.x * 0.55, y: river[i + 1].y * 0.45 + targetB.y * 0.55)
                }

                // Compute EXACT SpriteKit zRotation from map tangent (dx, dy):
                // LivingWorld maps (x, y) -> (x, -y), so road vector in SpriteKit is (dx, -dy)!
                var dx = cand.roadDir.dx
                var dy = cand.roadDir.dy
                let orientation: MeadowWaterSystem.Bridge.Orientation
                let skAngle: CGFloat
                let mirror: Bool
                if abs(dx) >= abs(dy) * 0.85 {
                    orientation = .horizontal
                    // Canonicalize direction to point right (+X) so bridge never flips upside-down
                    if dx < 0 { dx = -dx; dy = -dy }
                    skAngle = atan2(-dy, dx) // Exact SpriteKit angle around +X axis!
                    mirror = false
                } else {
                    orientation = .vertical
                    // Canonicalize direction to point down (+Y in map = -Y in SpriteKit)
                    if dy < 0 { dx = -dx; dy = -dy }
                    // Vertical sprite's natural span axis is along Y (angle -pi/2 in SpriteKit)
                    let raw = atan2(-dy, dx) // near -pi/2
                    skAngle = raw + .pi / 2
                    mirror = false
                }
                bridges.append(MeadowWaterSystem.Bridge(
                    center: cand.hit,
                    roadDir: CGVector(dx: dx, dy: dy),
                    angle: max(-0.62, min(0.62, skAngle)),
                    orientation: orientation,
                    mirror: mirror
                ))
            }
        }

        // 5. Design terraced elevation plateaus (Boss Sanctums + scenic high-ground nodes) & interior rolling hills!
        var plateaus: [MeadowWaterSystem.Plateau] = []
        for bp in bossPoints {
            plateaus.append(.init(center: CGPoint(x: bp.x, y: bp.y - 16), radius: 112, height: 0.28))
        }
        // Elevate 2-3 scenic non-start, non-lake-adjacent landmarks onto mid-valley terraced plateaus!
        for np in nodePoints {
            if let sp = startPoint, hypot(np.x - sp.x, np.y - sp.y) < 110 { continue }
            if bossPoints.contains(where: { hypot($0.x - np.x, $0.y - np.y) < 140 }) { continue }
            if plateaus.contains(where: { hypot($0.center.x - np.x, $0.center.y - np.y) < 220 }) { continue }
            if let lc = lake?.center, hypot(lc.x - np.x, lc.y - np.y) < 210 { continue }
            if np.y < safeH * 0.68 && plateaus.count < bossPoints.count + 3 {
                plateaus.append(.init(center: CGPoint(x: np.x, y: np.y - 14), radius: 96, height: 0.21))
            }
        }

        // Sculpt 10 organic rolling hills & ridges across the valley & exploration clearings
        var hills: [MeadowWaterSystem.Hill] = []
        for _ in 0..<40 where hills.count < 10 {
            let hx = rng.value(40, 1240)
            let hy = rng.value(125, safeH - 40)
            let hp = CGPoint(x: hx, y: hy)
            if let lc = lake?.center, hypot(lc.x - hx, lc.y - hy) < 155 { continue }
            if hills.contains(where: { hypot($0.center.x - hx, $0.center.y - hy) < 165 }) { continue }
            let rx = rng.value(105, 190)
            let ry = rx * rng.value(0.62, 0.85)
            let hh = rng.value(0.11, 0.19)
            hills.append(.init(center: hp, rx: rx, ry: ry, height: hh))
        }

        // Build provisional system to query exact elevation gradient along every road for mathematically locked stone stairs!
        let provisional = MeadowWaterSystem(
            waterfall: bestWF, plungePool: plungePool, riverPoints: river, lake: lake,
            bridges: bridges, stairs: [], plateaus: plateaus, hills: hills, seed: seed, mapHeight: safeH
        )

        // 6. Place road-centerline-locked Stone Stairs ONLY where roads physically climb/descend terrace slopes!
        var stairs: [MeadowWaterSystem.Stair] = []
        struct StairCandidate {
            let center: CGPoint
            let uphill: CGVector
            let slope: CGFloat
            let nearPlateau: Bool
        }
        var stairCands: [StairCandidate] = []
        for edge in network.edges {
            guard edge.trail.length > 88 else { continue }
            var d: CGFloat = 38
            while d <= edge.trail.length - 38 {
                let pt = edge.trail.point(at: d)
                if !provisional.isNearWater(pt, margin: 34)
                    && bridges.allSatisfy({ hypot($0.center.x - pt.x, $0.center.y - pt.y) > 70 })
                    && nodePoints.allSatisfy({ hypot($0.x - pt.x, ($0.y - 10) - pt.y) > 40 }) {
                    let pBack = edge.trail.point(at: max(0, d - 16))
                    let pFwd  = edge.trail.point(at: min(edge.trail.length, d + 16))
                    let hBack = provisional.elevation(at: pBack)
                    let hFwd  = provisional.elevation(at: pFwd)
                    let dH = hFwd - hBack
                    let absSlope = abs(dH)
                    let nearPlat = plateaus.contains(where: {
                        let dist = hypot(pt.x - $0.center.x, pt.y - $0.center.y)
                        return dist > $0.radius * 0.65 && dist < $0.radius * 1.40
                    })
                    if absSlope > (nearPlat ? 0.036 : 0.048) {
                        let sgn: CGFloat = dH >= 0 ? 1 : -1
                        let ux = (pFwd.x - pBack.x) * sgn
                        let uy = (pFwd.y - pBack.y) * sgn
                        let ulen = max(0.001, hypot(ux, uy))
                        stairCands.append(StairCandidate(
                            center: pt,
                            uphill: CGVector(dx: ux / ulen, dy: uy / ulen),
                            slope: absSlope + (nearPlat ? 0.04 : 0),
                            nearPlateau: nearPlat
                        ))
                    }
                }
                d += 14
            }
        }
        stairCands.sort { $0.slope > $1.slope }
        for cand in stairCands where stairs.count < 5 {
            guard stairs.allSatisfy({ hypot($0.center.x - cand.center.x, $0.center.y - cand.center.y) > 135 }) else { continue }
            let ux = cand.uphill.dx, uy = cand.uphill.dy
            let orientation: MeadowWaterSystem.Stair.Orientation
            let skAngle: CGFloat
            let mirror: Bool
            // Only place front stairs on crisp straight N-S climbs (ascending upward on screen, |ux| small)
            // and side stairs ONLY on clean straight E-W climbs near elevated plateaus so stairs NEVER float on curves!
            if abs(uy) >= abs(ux) * 1.15 {
                guard uy < -0.62 else { continue }
                orientation = .front
                let raw = atan2(-uy, ux)
                skAngle = max(-0.34, min(0.34, raw - .pi / 2))
                mirror = false
            } else if cand.nearPlateau && abs(ux) >= abs(uy) * 1.45 {
                orientation = .side
                mirror = ux < 0
                let adjX = mirror ? -ux : ux
                let adjY = mirror ? -uy : uy
                let raw = atan2(-adjY, adjX)
                skAngle = max(-0.22, min(0.22, mirror ? -raw : raw))
            } else {
                continue
            }
            stairs.append(MeadowWaterSystem.Stair(
                center: cand.center,
                uphillDir: cand.uphill,
                angle: skAngle,
                orientation: orientation,
                mirror: mirror
            ))
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
            // Crisp cobblestone entry pads anchored to BOTH abutments of every bridge & stair landing!
            for b in water.bridges {
                allCobbles.append((CGPoint(x: b.center.x - b.roadDir.dx * 34, y: b.center.y - b.roadDir.dy * 34), 48))
                allCobbles.append((CGPoint(x: b.center.x + b.roadDir.dx * 34, y: b.center.y + b.roadDir.dy * 34), 48))
            }
            for s in water.stairs {
                allCobbles.append((s.center, 58))
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

        // 2. Rasterize water depth (B) and turbulence/foam energy (A) into roadMask
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
                    let maxRadius: CGFloat = 38
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
                        let radius = 23 + 12 * u + sin(u * .pi * 4.0) * 3.5 + estuaryFlare
                        let distance = hypot(px - a.x - t * dx, py - a.y - t * dy)
                        guard distance < radius else { continue }
                        let val = pow(max(0, 1 - distance / radius), 0.66) * 0.88
                        let bVal = UInt8(min(255, max(0, Int(val * 255))))
                        // Rapids turbulence strongest near upper mountain stream & center channel
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

            // Clear muddy road dirt strictly over the open river channel underneath each bridge deck
            for bridge in water.bridges {
                let rad: CGFloat = 24
                let minX = max(0, Int(floor(bridge.center.x - rad - bounds.minX)))
                let maxX = min(width - 1, Int(ceil(bridge.center.x + rad - bounds.minX)))
                let minY = max(0, Int(floor(bridge.center.y - rad - bounds.minY)))
                let maxY = min(height - 1, Int(ceil(bridge.center.y + rad - bounds.minY)))
                guard minX <= maxX, minY <= maxY else { continue }
                for y in minY...maxY { for x in minX...maxX {
                    let i = (y * width + x) * 4
                    if rgba[i + 2] > 60 {
                        let px = CGFloat(x) + bounds.minX + 0.5, py = CGFloat(y) + bounds.minY + 0.5
                        let along = abs((px - bridge.center.x) * bridge.roadDir.dx + (py - bridge.center.y) * bridge.roadDir.dy)
                        if along < 24 {
                            let fade = max(0, min(1, (along - 14) / 10.0))
                            rgba[i] = UInt8(CGFloat(rgba[i]) * fade)
                        }
                    }
                } }
            }
        }
        progress?(0.74)

        // 3. Generate half-res Terrain Field (R=elevation, G=flowX, B=flowY, A=water turbulence/foam energy)
        let fw = max(1, width / 2), fh = max(1, height / 2)
        var tBytes = [UInt8](repeating: 0, count: fw * fh * 4)

        // Precompute river segment tangents for fast O(N) downstream flow lookup
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
                let hVal: CGFloat = water?.elevation(at: p) ?? 0.34
                // Pull turbulence directly from the full-res water raster so plunge pool & rapids align pixel-for-pixel
                let sx = min(width - 1, fx * 2), sy = min(height - 1, fy * 2)
                let turbByte = rgba[(sy * width + sx) * 4 + 3]

                // Compute smooth downstream flow vector (vx, vy) in [-1, 1]
                var vx: CGFloat = 0, vy: CGFloat = 0.65
                if let water {
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

                let idx = (fy * fw + fx) * 4
                tBytes[idx] = UInt8(min(255, max(0, Int(hVal * 255))))
                tBytes[idx + 1] = UInt8(min(255, max(0, Int((vx * 0.5 + 0.5) * 255))))
                tBytes[idx + 2] = UInt8(min(255, max(0, Int((vy * 0.5 + 0.5) * 255))))
                tBytes[idx + 3] = turbByte
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
