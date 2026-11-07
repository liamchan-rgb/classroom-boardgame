import simd
import Foundation

/// The lab uses one world: X right, Y along the ground, Z height; ground is Z=0.
/// Sprite landmarks and shadow geometry share the same per-instance ground root.
struct ShadowLabVertex {
    var position: SIMD4<Float>
    var uvWind: SIMD4<Float>
    var color: SIMD4<Float>
}

struct ShadowLabUniforms {
    var camera: simd_float4x4
    var light: simd_float4x4
    var sunTime: SIMD4<Float>
    var options: SIMD4<Float> // shadow on, inverse map size, wind on, unused
}

struct ShadowLabFrame {
    var time: Float = 0
    var sunAngle: Float = -0.65
    var shadows = true
    var wind = true
    var artwork = true
    var models = false
    var zoom: Float = 1
    var seed: UInt64 = 1
    var heroFrame: Int? = nil
}

enum ShadowLabAsset: String {
    case tree = "OakA", oakB = "OakB", pines = "Pines", tower = "WatchTower", hero = "Hero1Directions"
    case tent = "CampTent", fence = "Fence", rockLow = "RockLow", rockHigh = "RockHigh", rockSmall = "RockSmall", shrub = "Shrub", flowers = "Flowers", banner = "Banner"
    case combatOutpost = "NodeCombatOutpost", bossSanctum = "NodeBossSanctum", rewardCache = "NodeRewardCache", waystone = "NodeWaystone"
    var isNodeLandmark: Bool { [.combatOutpost,.bossSanctum,.rewardCache,.waystone].contains(self) }
    var casterKind: Float {
        switch self { case .tree, .oakB, .pines: return 0; case .tower: return 1; case .hero: return 2
        case .tent, .combatOutpost, .bossSanctum, .rewardCache, .waystone: return 3; case .fence: return 4; case .rockLow, .rockHigh, .rockSmall: return 5
        case .shrub: return 6; case .flowers: return 7; case .banner: return 8 }
    }
    var isTree: Bool { casterKind == 0 }
    /// Centers of the painted post bases in Fence.png (top-origin UV).
    /// This fence recedes diagonally across the ground, unlike a symmetric rock.
    static let fencePostBases: [SIMD2<Float>] = [SIMD2(0.17, 0.50), SIMD2(0.50, 0.68), SIMD2(0.83, 0.86)]
    static func fenceGroundV(at u: Float) -> Float {
        let left = fencePostBases[0], right = fencePostBases[2]
        return left.y + (u - left.x) * (right.y - left.y) / (right.x - left.x)
    }
    var anchorY: Float {
        switch self { case .tree, .oakB, .pines: return 0.09; case .tower: return 0.14
        case .combatOutpost, .bossSanctum, .rewardCache, .waystone: return 0.08
        case .hero: return 0.125; case .tent: return 0.10; case .rockLow, .rockHigh, .rockSmall: return 0.10
        case .fence: return 0.08; case .shrub, .flowers: return 0.04; case .banner: return 0.04 }
    }
}

struct ShadowLabInstance {
    let asset: ShadowLabAsset
    let root: SIMD3<Float>
    let width: Float
    let aspect: Float
    /// Normalized image coordinates measured from the lower-left corner.
    let anchor: SIMD2<Float>
    var screenHeight: Float { width * aspect }
    var cardHeight: Float { screenHeight / ShadowLabMath.cameraUp.z }
    var height: Float { cardHeight * (1 - anchor.y) }
    /// Painted post bases, clockwise around the footprint; coordinates are asset metadata.
    var towerFeet: [SIMD3<Float>] {
        [SIMD2<Float>(0.48, 0.86), SIMD2(0.24, 0.78), SIMD2(0.50, 0.70), SIMD2(0.73, 0.77)].map { p in
            pointOnPlane(p.x, p.y, height: 0)
        }
    }
    var proxyCenter: SIMD3<Float> {
        asset == .tower ? towerFeet.reduce(SIMD3<Float>.zero, +) / 4 : root
    }
    var proxyHeight: Float {
        height - (proxyCenter.y - root.y) * ShadowLabMath.cameraUp.y / ShadowLabMath.cameraUp.z
    }

    func imagePoint(_ u: Float, _ vFromTop: Float) -> SIMD3<Float> {
        root + SIMD3((u - anchor.x) * width, 0, (1 - vFromTop - anchor.y) * cardHeight)
    }

    func pointOnPlane(_ u: Float, _ vFromTop: Float, height: Float) -> SIMD3<Float> {
        let screenUp = (1 - vFromTop - anchor.y) * screenHeight
        return root + SIMD3((u - anchor.x) * width,
                            (screenUp - height * ShadowLabMath.cameraUp.z) / ShadowLabMath.cameraUp.y, height)
    }
}

enum ShadowLabMath {
    static let cameraUp = simd_normalize(SIMD3<Float>(0, 28, 20))

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(target - eye)
        let r = simd_normalize(simd_cross(f, up))
        let u = simd_cross(r, f)
        return simd_float4x4(columns: (
            SIMD4(r.x, u.x, -f.x, 0), SIMD4(r.y, u.y, -f.y, 0),
            SIMD4(r.z, u.z, -f.z, 0), SIMD4(-simd_dot(r, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)))
    }

    /// Right-handed orthographic projection with Metal's 0...1 depth interval.
    static func orthographic(halfWidth: Float, halfHeight: Float, near: Float, far: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(1 / halfWidth, 0, 0, 0), SIMD4(0, 1 / halfHeight, 0, 0),
                              SIMD4(0, 0, 1 / (near - far), 0), SIMD4(0, 0, near / (near - far), 1)))
    }

    static func camera(aspect: Float, zoom: Float) -> simd_float4x4 {
        let target = SIMD3<Float>(0, 0, 2.8)
        let view = lookAt(eye: target + SIMD3(0, -20, 28), target: target, up: SIMD3(0, 0, 1))
        let halfHeight = max(6.1, 11.4 / max(aspect, 0.1)) / zoom
        return orthographic(halfWidth: halfHeight * aspect, halfHeight: halfHeight, near: 0.1, far: 100) * view
    }

    static func sun(angle: Float) -> SIMD3<Float> {
        simd_normalize(SIMD3(sin(angle) * 0.85, cos(angle) * 0.85, 1.2))
    }

    static func light(sun: SIMD3<Float>) -> simd_float4x4 {
        let target = SIMD3<Float>(0, 0, 2)
        return orthographic(halfWidth: 18, halfHeight: 18, near: 0.1, far: 80)
            * lookAt(eye: target + sun * 35, target: target, up: SIMD3(0, 0, 1))
    }

    static func instances(seed: UInt64, time: Float) -> [ShadowLabInstance] {
        // One shared record drives both passes; re-layout never places art and shadows separately.
        let offset: Float = seed == 1 ? 0 : Float(Int(seed % 5) - 2) * 0.38
        let depth: Float = seed == 1 ? 0 : Float(Int((seed / 3) % 5) - 2) * 0.28
        let travel = (time * 0.75).truncatingRemainder(dividingBy: 14)
        let heroX = travel <= 7 ? 3.5 - travel : travel - 10.5
        return [
            ShadowLabInstance(asset: .tree, root: SIMD3(-5.2 + offset, 1 + depth, 0), width: 5,
                              aspect: 553.0 / 516, anchor: SIMD2(0.50, 0.09)),
            ShadowLabInstance(asset: .tower, root: SIMD3(4.0 - offset, 1.1 - depth, 0), width: 4.4,
                              aspect: 499.0 / 388, anchor: SIMD2(0.50, 0.14)),
            ShadowLabInstance(asset: .hero, root: SIMD3(heroX, -3.0 + depth, 0), width: 2.6,
                              aspect: 1, anchor: SIMD2(0.50, 0.125))
        ]
    }

    static func heroFrame(time: Float) -> Int { WalkCycle.frame(at: CGFloat(max(0, time)) * HeroFrames.reviewSpeed) }
    static func heroMovingRight(time: Float) -> Bool { (time * 0.75).truncatingRemainder(dividingBy: 14) > 7 }
}

struct ShadowLabMesh {
    var vertices: [ShadowLabVertex] = []
    var wind: Float = 0
    var phase: Float = 0
    var color = SIMD4<Float>(0.85, 0.66, 0.29, 0.55)

    mutating func meadowCaster(_ instance: ShadowLabInstance, mirrored: Bool = false, wind: Float, phase: Float) {
        let start = vertices.count
        imageCaster(instance, mirrored: mirrored)
        for index in start..<vertices.count {
            vertices[index].uvWind.z = wind
            vertices[index].uvWind.w = phase
        }
    }

    /// A relief surface derived from image coordinates: changing ground-depth Y
    /// solves height Z to preserve the artwork's projection in the fixed camera.
    /// Fine silhouette detail comes from alpha testing, not extra sphere geometry.
    mutating func imageCaster(_ instance: ShadowLabInstance, mirrored: Bool = false, pose: HeroPose? = nil) {
        func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
            let t = max(0, min(1, (x - a) / (b - a)))
            return t * t * (3 - 2 * t)
        }
        let small = instance.asset == .flowers || instance.asset == .shrub || instance.asset == .fence || instance.asset == .banner
        let columns = small ? 4 : (instance.asset == .hero ? 8 : 16)
        let rows = small ? 8 : 32
        let roofDepth = instance.asset == .tower ? instance.proxyCenter.y - instance.root.y : 0
        vertices.reserveCapacity(vertices.count + columns * rows * 6)
        func vertex(_ u: Float, _ v: Float, destination: SIMD2<Float>? = nil) -> ShadowLabVertex {
            let point = destination ?? SIMD2(u, 1 - v)
            let screenUp = (point.y - instance.anchor.y) * instance.screenHeight
            var depth: Float
            switch instance.asset {
            case .tree, .oakB, .pines:
                let canopy = 1 - smooth(0.70, 0.86, v)
                let back = 1 - smooth(0.23, 0.39, v)
                let front = smooth(0.57, 0.72, v)
                depth = (0.10 + 0.36 * back - 0.38 * front + sin(u * .pi) * 0.16) * canopy
            case .tower:
                let groundV: Float
                if u < 0.48 {
                    let t = max(0, min(1, (u - 0.24) / 0.24))
                    groundV = 0.78 + t * 0.08
                } else {
                    let t = max(0, min(1, (u - 0.48) / 0.25))
                    groundV = 0.86 - t * 0.09
                }
                let footDepth = (1 - groundV - instance.anchor.y) * instance.screenHeight / ShadowLabMath.cameraUp.y
                let roof = 1 - smooth(0.20, 0.30, v)
                depth = footDepth * (1 - roof) + roofDepth * roof
            case .hero:
                depth = (u - 0.5) * 0.20 * (1 - smooth(0.52, 0.70, v))
                if let pose {
                    depth += (pose.groundLine(at: point) - instance.anchor.y) * instance.screenHeight / ShadowLabMath.cameraUp.y
                }
            case .fence:
                let groundV = ShadowLabAsset.fenceGroundV(at: u)
                depth = (1 - groundV - instance.anchor.y) * instance.screenHeight / ShadowLabMath.cameraUp.y
            case .tent, .rockLow, .rockHigh, .rockSmall, .shrub, .flowers, .banner, .combatOutpost, .bossSanctum, .rewardCache, .waystone:
                // A sloping footprint keeps the lower art on the receiver;
                // raised details retain their alpha silhouette above it.
                let footV = 1 - instance.anchor.y - 0.09 * abs(u - 0.5) * 2
                let footprint = (1 - footV - instance.anchor.y) * instance.screenHeight / ShadowLabMath.cameraUp.y
                let volume: Float = (instance.asset == .tent || instance.asset.isNodeLandmark) ? 0.18 : 0.07
                depth = footprint + sin(u * .pi) * volume * instance.width * (1 - smooth(0.40, 0.88, v))
            }
            var height = (screenUp - depth * ShadowLabMath.cameraUp.y) / ShadowLabMath.cameraUp.z
            // The painted ground apron is placed ON the receiver, then excluded
            // by the caster fragment; it cannot become a standing grass rectangle.
            if height < 0 { height = 0; depth = screenUp / ShadowLabMath.cameraUp.y }
            var x = (point.x - instance.anchor.x) * instance.width
            if mirrored { x = -x }
            let position = instance.root + SIMD3(x, depth, height)
            let bend = instance.asset.isTree ? max(0, (1 - v - instance.anchor.y) / (1 - instance.anchor.y)) : 0
            let tint: SIMD4<Float> = instance.asset.isTree ? SIMD4(0.80, 1, 0.45, 1)
                : (instance.asset == .tower ? SIMD4(1, 0.72, 0.28, 1) : SIMD4(0.38, 0.83, 1, 1))
            return ShadowLabVertex(position: SIMD4(position, 1), uvWind: SIMD4(u, v, bend, 0.4), color: tint)
        }
        if let pose {
            let source = pose.sourcePositions, destination = pose.destinationPositions()
            let stride = HeroPose.gridColumns + 1
            for row in 0..<HeroPose.gridRows { for column in 0..<HeroPose.gridColumns {
                let a = row * stride + column, b = a + stride, c = b + 1, d = a + 1
                for index in [a, b, c, a, c, d] {
                    vertices.append(vertex(source[index].x, 1 - source[index].y, destination: destination[index]))
                }
            } }
            return
        }
        let fence = instance.asset == .fence
        let uStops = fence ? [Float(0)] + ShadowLabAsset.fencePostBases.map(\.x) + [Float(1)]
            : (0...columns).map { Float($0) / Float(columns) }
        func rowV(_ u: Float, _ row: Int) -> Float {
            if fence { return row > rows ? 1 : Float(row) / Float(rows) * ShadowLabAsset.fenceGroundV(at: u) }
            return Float(row) / Float(rows)
        }
        // Include the sloping ground line itself as a mesh row. Everything
        // below it lies on Z=0 and cannot cast a raised grass-apron shadow.
        for row in 0..<(rows + (fence ? 1 : 0)) { for column in 0..<(uStops.count - 1) {
            let u0 = uStops[column], u1 = uStops[column + 1]
            let a = vertex(u0, rowV(u0, row)), b = vertex(u0, rowV(u0, row + 1))
            let c = vertex(u1, rowV(u1, row + 1)), d = vertex(u1, rowV(u1, row))
            vertices += [a, b, c, a, c, d]
        } }
    }

    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        for p in [a, b, c] {
            vertices.append(ShadowLabVertex(position: SIMD4(p, 1), uvWind: SIMD4(0, 0, wind > 0 ? max(0, p.z / wind) : 0, phase), color: color))
        }
    }

    mutating func card(_ instance: ShadowLabInstance, rows: Int = 1, windPhase: Float = 0) {
        func vertex(_ u: Float, _ v: Float) -> ShadowLabVertex {
            let z = (1 - v - instance.anchor.y) * instance.cardHeight
            return ShadowLabVertex(position: SIMD4(instance.root + SIMD3((u - instance.anchor.x) * instance.width, 0, z), 1),
                                   uvWind: SIMD4(u, v, instance.asset.isTree ? max(0, z / instance.height) : 0, windPhase), color: SIMD4(repeating: 1))
        }
        for row in 0..<rows {
            let lo = Float(row) / Float(rows), hi = Float(row + 1) / Float(rows)
            vertices += [vertex(0, lo), vertex(0, hi), vertex(1, hi), vertex(0, lo), vertex(1, hi), vertex(1, lo)]
        }
    }
}
