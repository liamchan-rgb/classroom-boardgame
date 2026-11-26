import SpriteKit
import UIKit

/// Living HD-2D ambient wildlife & biome-matched wind-blown foliage particles:
/// - Meadow rabbits (MapCritterBunny) nibbling & hopping gently in grassy pockets
/// - Woodland squirrels (MapCritterSquirrel) darting & bobbing near oaks & mossy logs
/// - Woodland ducks (MapCritterDuck) gliding across the lake with subtle expanding wake rings
/// - Forest songbirds (MapCritterBird) soaring in wide arcs high over the valley canopy
/// - Animated 2-wing flapping butterflies over wildflower beds & blossom groves
/// - Skimming emerald/cyan dragonflies over the clear river & reeds
/// - Vegetation-driven wind-blown sakura petals, autumn leaves, fresh green leaves & grass blades!
final class MeadowAmbientLife: SKNode {

    private struct HopCritter {
        let node: SKSpriteNode
        let shadow: SKSpriteNode
        let home: CGPoint          // Map coords (+X right, +Y down)
        let target: CGPoint        // Secondary nearby clearing point
        let baseScale: CGFloat
        let cycleLen: Double       // Full idle + hop cycle duration
        let phase: Double
        let hopHeight: CGFloat
        let isSquirrel: Bool
    }

    private struct LakeDuck {
        let node: SKSpriteNode
        let wake: SKSpriteNode
        let center: CGPoint        // Map coords
        let rx: CGFloat
        let ry: CGFloat
        let speed: Double
        let phase: Double
        let baseSize: CGSize
    }

    private struct SoaringBird {
        let node: SKSpriteNode
        let shadow: SKSpriteNode
        let center: CGPoint
        let rx: CGFloat
        let ry: CGFloat
        let speed: Double
        let phase: Double
        let baseSize: CGSize
    }

    private struct WingInsect {
        let root: SKNode
        let leftWing: SKSpriteNode
        let rightWing: SKSpriteNode
        let home: CGPoint
        let rx: CGFloat
        let ry: CGFloat
        let speed: Double
        let flapRate: Double
        let phase: Double
        let isDragonfly: Bool
    }

    private struct WindFoliageParticle {
        let node: SKSpriteNode
        let origin: CGPoint        // Source vegetation position (map coords)
        let travelX: CGFloat
        let travelY: CGFloat
        let period: Double
        let phase: Double
        let flutterAmp: CGFloat
        let flutterFreq: Double
        let tumbleFreq: Double
        let baseAlpha: CGFloat
        let baseScale: CGFloat
    }

    private var hoppers: [HopCritter] = []
    private var ducks: [LakeDuck] = []
    private var birds: [SoaringBird] = []
    private var insects: [WingInsect] = []
    private var windParticles: [WindFoliageParticle] = []

    // Standard-range cached procedural textures (prevents Mac wide-color flickering squares)
    private static let shadowDotTexture: SKTexture = makePixelTexture(size: CGSize(width: 24, height: 14)) { ctx in
        UIColor(red: 0.05, green: 0.08, blue: 0.05, alpha: 0.34).setFill()
        ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 10))
    }

    private static let wakeRingTexture: SKTexture = makePixelTexture(size: CGSize(width: 48, height: 28)) { ctx in
        ctx.setStrokeColor(UIColor(red: 0.88, green: 0.98, blue: 0.99, alpha: 0.65).cgColor)
        ctx.setLineWidth(2.2)
        ctx.strokeEllipse(in: CGRect(x: 4, y: 4, width: 40, height: 20))
    }

    private static let petalTexture: SKTexture = makePixelTexture(size: CGSize(width: 14, height: 10)) { ctx in
        UIColor.white.setFill()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 2, y: 5))
        path.addQuadCurve(to: CGPoint(x: 12, y: 4), controlPoint: CGPoint(x: 7, y: 0.5))
        path.addQuadCurve(to: CGPoint(x: 2, y: 5), controlPoint: CGPoint(x: 7, y: 9.5))
        path.close()
        ctx.addPath(path.cgPath)
        ctx.fillPath()
    }

    private static let leafTexture: SKTexture = makePixelTexture(size: CGSize(width: 16, height: 12)) { ctx in
        UIColor.white.setFill()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 1.5, y: 6))
        path.addCurve(to: CGPoint(x: 14.5, y: 6), controlPoint1: CGPoint(x: 5, y: 0.5), controlPoint2: CGPoint(x: 11, y: 1.5))
        path.addCurve(to: CGPoint(x: 1.5, y: 6), controlPoint1: CGPoint(x: 11, y: 10.5), controlPoint2: CGPoint(x: 5, y: 11.5))
        path.close()
        ctx.addPath(path.cgPath)
        ctx.fillPath()
    }

    private static let grassBladeTexture: SKTexture = makePixelTexture(size: CGSize(width: 16, height: 6)) { ctx in
        UIColor.white.setFill()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 1, y: 4))
        path.addQuadCurve(to: CGPoint(x: 15, y: 2), controlPoint: CGPoint(x: 8, y: 0.5))
        path.addQuadCurve(to: CGPoint(x: 1, y: 5.2), controlPoint: CGPoint(x: 8, y: 3.5))
        path.close()
        ctx.addPath(path.cgPath)
        ctx.fillPath()
    }

    private static let wingTexture: SKTexture = makePixelTexture(size: CGSize(width: 12, height: 14)) { ctx in
        UIColor.white.setFill()
        ctx.fillEllipse(in: CGRect(x: 1, y: 1, width: 10, height: 8))
        ctx.fillEllipse(in: CGRect(x: 2, y: 7, width: 7, height: 6))
    }

    private static func makePixelTexture(size: CGSize, draw: (CGContext) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(ctx.cgContext)
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }

    init(
        definition: SceneDefinition,
        props: [SceneDefinition.Prop],
        network: TrailNetwork,
        water: MeadowWaterSystem?,
        textureProvider: (String) -> SKTexture
    ) {
        super.init()
        name = "meadowAmbientLife"
        let mapH = definition.mapHeight ?? 720
        let mapScale = max(1.0, mapH / 760.0)
        var rng = MeadowRandom(seed: definition.seed ^ 0x414d4249454e54)

        let landmarks = props.filter { $0.nodeID != nil }
        func isSafeLand(_ pt: CGPoint, roadClear: CGFloat = 32) -> Bool {
            if water?.isNearWater(pt, margin: 20) == true { return false }
            if water?.isNearBridge(pt, padAlong: 18, padAcross: 22) == true { return false }
            if water?.isOnCliffWall(pt, margin: 16) == true { return false }
            if network.project(pt).error < roadClear { return false }
            if landmarks.contains(where: { hypot($0.x - pt.x, $0.y - pt.y) < 76 }) { return false }
            return true
        }

        // 1. Meadow Rabbits (MapCritterBunny) in grassy clearings & clover patches
        let bunnyTex = textureProvider("MapCritterBunny")
        let bunnyTargetCount = min(9, max(4, Int((3.6 * mapScale).rounded())))
        var placedBunnies: [CGPoint] = []
        for _ in 0..<(bunnyTargetCount * 18) where placedBunnies.count < bunnyTargetCount {
            let p = CGPoint(x: rng.value(90, 1190), y: rng.value(150, mapH - 60))
            guard isSafeLand(p, roadClear: 34) else { continue }
            guard placedBunnies.allSatisfy({ hypot($0.x - p.x, $0.y - p.y) > 165 }) else { continue }
            let ang = rng.value(0, .pi * 2)
            let hopDist = rng.value(28, 52)
            let target = CGPoint(x: p.x + cos(ang) * hopDist, y: p.y + sin(ang) * hopDist * 0.65)
            guard isSafeLand(target, roadClear: 26) else { continue }

            let w: CGFloat = rng.value(17, 21)
            let h = w * bunnyTex.size().height / max(1, bunnyTex.size().width)
            let shadow = SKSpriteNode(texture: Self.shadowDotTexture, size: CGSize(width: w * 0.85, height: w * 0.42))
            shadow.zPosition = 9998 + p.y
            shadow.position = LivingWorld.position(p)
            addChild(shadow)

            let sprite = SKSpriteNode(texture: bunnyTex, size: CGSize(width: w, height: h))
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
            sprite.position = LivingWorld.position(p)
            sprite.zPosition = 10000 + p.y
            addChild(sprite)

            hoppers.append(HopCritter(
                node: sprite, shadow: shadow, home: p, target: target,
                baseScale: 1.0, cycleLen: Double(rng.value(6.5, 11.5)),
                phase: Double(rng.value(0, 12)), hopHeight: rng.value(7.5, 11.5), isSquirrel: false
            ))
            placedBunnies.append(p)
        }

        // 2. Woodland Squirrels (MapCritterSquirrel) near oaks, autumn trees & mossy logs
        let sqTex = textureProvider("MapCritterSquirrel")
        let treeHomes = props.filter {
            $0.asset == "MapTreeAncientOak" || $0.asset == "OakA" || $0.asset == "MapTreeAutumnOak"
            || $0.asset == "MapTreeAutumnMaple" || $0.asset == "MapLogMushrooms"
        }
        let sqCount = min(7, max(3, Int((2.8 * mapScale).rounded())))
        var placedSq: [CGPoint] = []
        if !treeHomes.isEmpty {
            for _ in 0..<(sqCount * 14) where placedSq.count < sqCount {
                let host = treeHomes[Int(rng.next() * CGFloat(treeHomes.count)) % treeHomes.count]
                let side: CGFloat = rng.next() > 0.5 ? 1 : -1
                let p = CGPoint(x: host.x + side * rng.value(20, 36), y: host.y + rng.value(8, 22))
                guard p.x > 60 && p.x < 1220 && p.y > 120 && p.y < mapH - 40 else { continue }
                guard isSafeLand(p, roadClear: 26) else { continue }
                guard placedSq.allSatisfy({ hypot($0.x - p.x, $0.y - p.y) > 180 }) else { continue }
                let target = CGPoint(x: host.x - side * rng.value(16, 30), y: host.y + rng.value(10, 26))
                guard isSafeLand(target, roadClear: 22) else { continue }

                let w: CGFloat = rng.value(16, 19)
                let h = w * sqTex.size().height / max(1, sqTex.size().width)
                let shadow = SKSpriteNode(texture: Self.shadowDotTexture, size: CGSize(width: w * 0.80, height: w * 0.38))
                shadow.zPosition = 9998 + p.y
                shadow.position = LivingWorld.position(p)
                addChild(shadow)

                let sprite = SKSpriteNode(texture: sqTex, size: CGSize(width: w, height: h))
                sprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
                sprite.position = LivingWorld.position(p)
                sprite.zPosition = 10000 + p.y
                addChild(sprite)

                hoppers.append(HopCritter(
                    node: sprite, shadow: shadow, home: p, target: target,
                    baseScale: 1.0, cycleLen: Double(rng.value(5.0, 9.0)),
                    phase: Double(rng.value(0, 10)), hopHeight: rng.value(5.0, 8.0), isSquirrel: true
                ))
                placedSq.append(p)
            }
        }

        // 3. Woodland Mallard Ducks (MapCritterDuck) gliding gracefully across the crystal lake
        if let lake = water?.lake {
            let duckTex = textureProvider("MapCritterDuck")
            let duckConfigs: [(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, spd: Double, w: CGFloat)] = [
                (lake.center.x - lake.rx * 0.28, lake.center.y - lake.ry * 0.26, lake.rx * 0.24, lake.ry * 0.16, 0.26, 22),
                (lake.lobeCenter.x + lake.lobeRx * 0.08, lake.lobeCenter.y + lake.lobeRy * 0.20, lake.lobeRx * 0.24, lake.lobeRy * 0.16, -0.22, 19),
                (lake.center.x - lake.rx * 0.18, lake.center.y + lake.ry * 0.36, lake.rx * 0.22, lake.ry * 0.12, 0.30, 17)
            ]
            for (idx, cfg) in duckConfigs.enumerated() {
                let w = cfg.w
                let h = w * duckTex.size().height / max(1, duckTex.size().width)
                let wake = SKSpriteNode(texture: Self.wakeRingTexture, size: CGSize(width: w * 1.45, height: w * 0.85))
                wake.zPosition = 57
                wake.alpha = 0.45
                addChild(wake)

                let sprite = SKSpriteNode(texture: duckTex, size: CGSize(width: w, height: h))
                sprite.anchorPoint = CGPoint(x: 0.5, y: 0.25)
                sprite.zPosition = 60
                addChild(sprite)

                ducks.append(LakeDuck(
                    node: sprite, wake: wake,
                    center: CGPoint(x: cfg.cx, y: cfg.cy), rx: cfg.rx, ry: cfg.ry,
                    speed: cfg.spd, phase: Double(idx) * 2.1 + Double(rng.value(0, 3)),
                    baseSize: CGSize(width: w, height: h)
                ))
            }
        }

        // 4. Forest Songbirds (MapCritterBird) soaring peacefully across the valley canopy
        let birdTex = textureProvider("MapCritterBird")
        let birdCount = min(5, max(3, Int((2.2 * mapScale).rounded())))
        for i in 0..<birdCount {
            let cy = mapH * (0.14 + 0.72 * (CGFloat(i) + 0.5) / CGFloat(birdCount))
            let cx = rng.value(360, 920)
            let w: CGFloat = rng.value(17, 21)
            let h = w * birdTex.size().height / max(1, birdTex.size().width)
            let shadow = SKSpriteNode(texture: Self.shadowDotTexture, size: CGSize(width: w * 0.72, height: w * 0.36))
            shadow.alpha = 0.26
            shadow.zPosition = 85
            addChild(shadow)

            let sprite = SKSpriteNode(texture: birdTex, size: CGSize(width: w, height: h))
            sprite.zPosition = 19600
            addChild(sprite)

            birds.append(SoaringBird(
                node: sprite, shadow: shadow,
                center: CGPoint(x: cx, y: cy),
                rx: rng.value(190, 320), ry: rng.value(75, 135),
                speed: Double(rng.value(0.24, 0.36)) * (i % 2 == 0 ? 1 : -1),
                phase: Double(rng.value(0, 6.28)),
                baseSize: CGSize(width: w, height: h)
            ))
        }

        // 5. Animated 2-Wing Butterflies fluttering over wildflower beds, flowering shrubs & cherry blossoms
        let flowerHosts = props.filter {
            $0.asset == "MapWildflowerBed" || $0.asset == "MapFloweringShrub" || $0.asset == "MapTreeBlossom"
            || $0.asset == "MapFlowersLavender" || $0.asset == "MapFlowersBlue" || $0.asset == "MapFlowersCrimson" || $0.asset == "Flowers"
        }
        let butterflyPalette: [SKColor] = [
            SKColor(red: 1.00, green: 0.90, blue: 0.48, alpha: 1),
            SKColor(red: 0.98, green: 0.74, blue: 0.84, alpha: 1),
            SKColor(red: 0.66, green: 0.86, blue: 1.00, alpha: 1),
            SKColor(red: 1.00, green: 0.97, blue: 0.86, alpha: 1)
        ]
        let butterflyCount = min(22, max(10, Int((8.5 * mapScale).rounded())))
        if !flowerHosts.isEmpty {
            for i in 0..<butterflyCount {
                let host = flowerHosts[Int(rng.next() * CGFloat(flowerHosts.count)) % flowerHosts.count]
                let home = CGPoint(x: host.x + rng.value(-14, 14), y: host.y - rng.value(8, 22))
                let col = host.asset == "MapTreeBlossom"
                    ? butterflyPalette[1]
                    : butterflyPalette[i % butterflyPalette.count]
                let root = SKNode()
                root.zPosition = 18500
                let lw = SKSpriteNode(texture: Self.wingTexture, size: CGSize(width: 5.5, height: 6.5))
                lw.anchorPoint = CGPoint(x: 1.0, y: 0.5)
                lw.color = col; lw.colorBlendFactor = 1.0
                let rw = SKSpriteNode(texture: Self.wingTexture, size: CGSize(width: 5.5, height: 6.5))
                rw.anchorPoint = CGPoint(x: 0.0, y: 0.5)
                rw.color = col; rw.colorBlendFactor = 1.0
                root.addChild(lw); root.addChild(rw)
                addChild(root)
                insects.append(WingInsect(
                    root: root, leftWing: lw, rightWing: rw, home: home,
                    rx: rng.value(18, 36), ry: rng.value(12, 24),
                    speed: Double(rng.value(0.75, 1.35)), flapRate: Double(rng.value(11.0, 15.5)),
                    phase: Double(rng.value(0, 6.28)), isDragonfly: false
                ))
            }
        }

        // 6. Shimmering Dragonflies skimming over the crystal river & woodland lake
        if let water, water.riverPoints.count >= 6 {
            let dfCount = min(9, max(5, Int((3.6 * mapScale).rounded())))
            for i in 0..<dfCount {
                let home: CGPoint
                if i < 2, let lake = water.lake {
                    let ang = rng.value(0, .pi * 2)
                    home = CGPoint(x: lake.center.x + cos(ang) * lake.rx * 0.55, y: lake.center.y + sin(ang) * lake.ry * 0.55)
                } else {
                    let idx = max(2, min(water.riverPoints.count - 2, Int(rng.next() * CGFloat(water.riverPoints.count - 4)) + 2))
                    home = water.riverPoints[idx]
                }
                let col = i % 2 == 0
                    ? SKColor(red: 0.36, green: 0.92, blue: 0.90, alpha: 0.92)
                    : SKColor(red: 0.56, green: 0.96, blue: 0.68, alpha: 0.92)
                let root = SKNode()
                root.zPosition = 18600
                let body = SKSpriteNode(color: col, size: CGSize(width: 7.5, height: 1.8))
                let lw = SKSpriteNode(texture: Self.wingTexture, size: CGSize(width: 5.0, height: 3.0))
                lw.position = CGPoint(x: 0.5, y: 1.5); lw.color = .white; lw.colorBlendFactor = 1.0; lw.alpha = 0.72
                let rw = SKSpriteNode(texture: Self.wingTexture, size: CGSize(width: 5.0, height: 3.0))
                rw.position = CGPoint(x: 0.5, y: -1.5); rw.color = .white; rw.colorBlendFactor = 1.0; rw.alpha = 0.72
                root.addChild(body); root.addChild(lw); root.addChild(rw)
                addChild(root)
                insects.append(WingInsect(
                    root: root, leftWing: lw, rightWing: rw, home: home,
                    rx: rng.value(22, 42), ry: rng.value(14, 28),
                    speed: Double(rng.value(1.25, 2.05)), flapRate: Double(rng.value(24.0, 32.0)),
                    phase: Double(rng.value(0, 6.28)), isDragonfly: true
                ))
            }
        }

        // 7. VEGETATION-DRIVEN WIND-BLOWN PETALS, LEAVES & GRASS BLADES!
        //    Spawn localized drifting particles matched strictly to the surrounding tree & grass species!
        let blossomSources = props.filter { $0.asset == "MapTreeBlossom" || $0.asset == "MapFloweringShrub" }
        let autumnSources  = props.filter { $0.asset == "MapTreeAutumnMaple" || $0.asset == "MapTreeAutumnOak" || $0.asset == "MapShrubAutumn" }
        let greenSources   = props.filter { $0.asset == "OakA" || $0.asset == "OakB" || $0.asset == "MapTreeAncientOak" || $0.asset == "MapTreeBirch" || $0.asset == "MapTreeWillow" }
        let grassSources   = props.filter { $0.asset == "MapTallGrassTuft" || $0.asset == "MapReedsCattail" || $0.asset == "MapWildflowerBed" || $0.asset == "MapFernsCluster" }

        func spawnFoliageStream(
            sources: [SceneDefinition.Prop],
            count: Int,
            texture: SKTexture,
            colors: [SKColor],
            sizeRange: ClosedRange<CGFloat>,
            travelXRange: ClosedRange<CGFloat>,
            travelYRange: ClosedRange<CGFloat>,
            periodRange: ClosedRange<Double>,
            originLift: CGFloat
        ) {
            guard !sources.isEmpty else { return }
            for i in 0..<count {
                let src = sources[Int(rng.next() * CGFloat(sources.count)) % sources.count]
                let ox = src.x + rng.value(-src.width * 0.35, src.width * 0.35)
                let oy = src.y - originLift + rng.value(-16, 12)
                let sz = rng.value(sizeRange.lowerBound, sizeRange.upperBound)
                let aspect = texture.size().height / max(1, texture.size().width)
                let sp = SKSpriteNode(texture: texture, size: CGSize(width: sz, height: sz * aspect))
                sp.color = colors[i % colors.count]
                sp.colorBlendFactor = 1.0
                sp.zPosition = 19200
                addChild(sp)
                windParticles.append(WindFoliageParticle(
                    node: sp,
                    origin: CGPoint(x: ox, y: oy),
                    travelX: rng.value(travelXRange.lowerBound, travelXRange.upperBound),
                    travelY: rng.value(travelYRange.lowerBound, travelYRange.upperBound),
                    period: Double(rng.value(CGFloat(periodRange.lowerBound), CGFloat(periodRange.upperBound))),
                    phase: Double(rng.value(0, 1)),
                    flutterAmp: rng.value(6.0, 15.0),
                    flutterFreq: Double(rng.value(1.6, 3.0)),
                    tumbleFreq: Double(rng.value(2.4, 4.8)),
                    baseAlpha: rng.value(0.72, 0.94),
                    baseScale: rng.value(0.85, 1.15)
                ))
            }
        }

        // 7a. Sakura & Hydrangea Petals drifting from blossom trees & flowering shrubs
        spawnFoliageStream(
            sources: blossomSources,
            count: min(38, max(16, Int((15.0 * mapScale).rounded()))),
            texture: Self.petalTexture,
            colors: [
                SKColor(red: 1.00, green: 0.78, blue: 0.86, alpha: 1),
                SKColor(red: 1.00, green: 0.88, blue: 0.92, alpha: 1),
                SKColor(red: 0.96, green: 0.68, blue: 0.80, alpha: 1),
                SKColor(red: 0.80, green: 0.90, blue: 1.00, alpha: 1)
            ],
            sizeRange: 5.5...8.5,
            travelXRange: 105...185,
            travelYRange: 34...74,
            periodRange: 6.5...11.5,
            originLift: 34
        )

        // 7b. Crimson, Amber & Golden Autumn Leaves swirling from autumn maples & golden oaks
        spawnFoliageStream(
            sources: autumnSources,
            count: min(36, max(14, Int((14.0 * mapScale).rounded()))),
            texture: Self.leafTexture,
            colors: [
                SKColor(red: 0.92, green: 0.36, blue: 0.18, alpha: 1),
                SKColor(red: 0.96, green: 0.58, blue: 0.18, alpha: 1),
                SKColor(red: 0.98, green: 0.78, blue: 0.24, alpha: 1),
                SKColor(red: 0.80, green: 0.26, blue: 0.16, alpha: 1)
            ],
            sizeRange: 6.5...10.0,
            travelXRange: 95...175,
            travelYRange: 38...82,
            periodRange: 6.0...10.5,
            originLift: 38
        )

        // 7c. Fresh Sunlit Forest Green Leaves fluttering from oaks, birches & willows
        spawnFoliageStream(
            sources: greenSources,
            count: min(36, max(14, Int((14.0 * mapScale).rounded()))),
            texture: Self.leafTexture,
            colors: [
                SKColor(red: 0.48, green: 0.78, blue: 0.30, alpha: 1),
                SKColor(red: 0.62, green: 0.84, blue: 0.36, alpha: 1),
                SKColor(red: 0.38, green: 0.68, blue: 0.28, alpha: 1)
            ],
            sizeRange: 6.0...9.0,
            travelXRange: 95...165,
            travelYRange: 32...70,
            periodRange: 6.5...11.0,
            originLift: 36
        )

        // 7d. Wind-Blown Meadow Grass Blades & Sunlit Meadow Seeds sweeping over tall grass & reeds
        spawnFoliageStream(
            sources: grassSources,
            count: min(40, max(18, Int((16.0 * mapScale).rounded()))),
            texture: Self.grassBladeTexture,
            colors: [
                SKColor(red: 0.62, green: 0.82, blue: 0.34, alpha: 1),
                SKColor(red: 0.76, green: 0.86, blue: 0.42, alpha: 1),
                SKColor(red: 0.94, green: 0.92, blue: 0.68, alpha: 1)
            ],
            sizeRange: 7.0...11.0,
            travelXRange: 85...155,
            travelYRange: 14...42,
            periodRange: 4.8...8.5,
            originLift: 8
        )

        update(time: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(time: TimeInterval) {
        let t = time

        // 1. Rabbits & Squirrels (calm idle breathing + periodic natural parabolic hops between clearing spots)
        for c in hoppers {
            let cyc = (t + c.phase).truncatingRemainder(dividingBy: c.cycleLen)
            let half = c.cycleLen * 0.5
            let hopDur = c.isSquirrel ? 0.65 : 0.85
            let pos: CGPoint
            let lift: CGFloat
            let facingRight: Bool

            if cyc < hopDur {
                // Hop from home -> target
                let u = CGFloat(cyc / hopDur)
                let su = u * u * (3 - 2 * u)
                pos = CGPoint(x: c.home.x + (c.target.x - c.home.x) * su, y: c.home.y + (c.target.y - c.home.y) * su)
                let hops: CGFloat = c.isSquirrel ? 2.0 : 2.0
                lift = abs(sin(u * .pi * hops)) * c.hopHeight
                facingRight = (c.target.x - c.home.x) >= 0
            } else if cyc < half {
                // Rest & nibble at target
                pos = c.target
                lift = 0
                facingRight = (c.target.x - c.home.x) >= 0
            } else if cyc < half + hopDur {
                // Hop back from target -> home
                let u = CGFloat((cyc - half) / hopDur)
                let su = u * u * (3 - 2 * u)
                pos = CGPoint(x: c.target.x + (c.home.x - c.target.x) * su, y: c.target.y + (c.home.y - c.target.y) * su)
                lift = abs(sin(u * .pi * 2.0)) * c.hopHeight
                facingRight = (c.home.x - c.target.x) >= 0
            } else {
                // Rest & nibble at home
                pos = c.home
                lift = 0
                facingRight = (c.home.x - c.target.x) >= 0
            }

            let skGround = LivingWorld.position(pos)
            let breath = lift > 0.2 ? 1.0 + (lift / max(1, c.hopHeight)) * 0.08 : 1.0 + CGFloat(sin(t * (c.isSquirrel ? 5.2 : 3.4) + c.phase)) * 0.04
            c.node.position = CGPoint(x: skGround.x, y: skGround.y + lift)
            c.node.xScale = (facingRight ? 1 : -1) * c.baseScale
            c.node.yScale = breath * c.baseScale
            c.node.zPosition = 10000 + pos.y

            c.shadow.position = skGround
            c.shadow.zPosition = 9998 + pos.y
            let shScale = max(0.55, 1.0 - lift / 28.0)
            c.shadow.setScale(shScale)
        }

        // 2. Woodland Ducks gliding gently on the lake with subtle expanding water wake rings
        for d in ducks {
            let ang = t * d.speed + d.phase
            let mx = d.center.x + CGFloat(cos(ang)) * d.rx
            let my = d.center.y + CGFloat(sin(ang * 2.0)) * d.ry * 0.55
            let vx = -sin(ang) * d.speed
            let bob = CGFloat(sin(t * 2.8 + d.phase)) * 1.1
            let skP = LivingWorld.position(CGPoint(x: mx, y: my))
            d.node.position = CGPoint(x: skP.x, y: skP.y + bob)
            d.node.xScale = vx >= 0 ? 1 : -1

            let wakeCycle = CGFloat((t * 0.65 + d.phase).truncatingRemainder(dividingBy: 1.0))
            d.wake.position = CGPoint(x: skP.x - (vx >= 0 ? 3 : -3), y: skP.y - 3)
            d.wake.xScale = 0.72 + wakeCycle * 0.75
            d.wake.yScale = 0.72 + wakeCycle * 0.75
            d.wake.alpha = (1.0 - wakeCycle) * 0.50
        }

        // 3. Forest Songbirds gliding peacefully above the canopy
        for b in birds {
            let ang = t * b.speed + b.phase
            let mx = b.center.x + CGFloat(cos(ang)) * b.rx
            let my = b.center.y + CGFloat(sin(ang)) * b.ry
            let vx = -sin(ang) * b.speed
            let flap = CGFloat(sin(t * 7.8 + b.phase))
            let lift = CGFloat(sin(t * 1.4 + b.phase)) * 6.0
            let skP = LivingWorld.position(CGPoint(x: mx, y: my))
            b.node.position = CGPoint(x: skP.x, y: skP.y + 42 + lift)
            b.node.xScale = vx >= 0 ? 1 : -1
            b.node.yScale = 0.84 + flap * 0.20
            b.node.zRotation = CGFloat(cos(ang)) * 0.14 * (vx >= 0 ? 1 : -1)
            b.shadow.position = CGPoint(x: skP.x + 28, y: skP.y - 18)
        }

        // 4. Butterflies & Dragonflies
        for ins in insects {
            let ang = t * ins.speed + ins.phase
            let dx = CGFloat(sin(ang)) * ins.rx
            let dy = CGFloat(sin(ang * 2.0 + 0.7)) * ins.ry * 0.65
            let flutterY = CGFloat(sin(t * 4.5 + ins.phase)) * (ins.isDragonfly ? 1.5 : 3.2)
            let skP = LivingWorld.position(CGPoint(x: ins.home.x + dx, y: ins.home.y + dy))
            ins.root.position = CGPoint(x: skP.x, y: skP.y + flutterY)
            let flap = 0.25 + 0.75 * abs(CGFloat(sin(t * ins.flapRate + ins.phase)))
            if ins.isDragonfly {
                ins.leftWing.yScale = flap
                ins.rightWing.yScale = flap
                ins.root.zRotation = CGFloat(cos(ang)) * 0.35
            } else {
                ins.leftWing.xScale = flap
                ins.rightWing.xScale = flap
                ins.root.zRotation = CGFloat(cos(ang)) * 0.25
            }
        }

        // 5. Biome-matched wind-blown petals, autumn leaves, green leaves & grass blades
        let globalGust = CGFloat(0.84 + 0.24 * sin(t * 0.48))
        for p in windParticles {
            let u = (t / p.period + p.phase).truncatingRemainder(dividingBy: 1.0)
            let uf = CGFloat(u < 0 ? u + 1.0 : u)
            let gustDrift = sin(t * p.flutterFreq + p.phase * 12.0)
            let mx = p.origin.x + p.travelX * uf * globalGust + CGFloat(gustDrift) * p.flutterAmp * 0.55
            let my = p.origin.y + p.travelY * uf + CGFloat(cos(t * p.flutterFreq * 0.85 + p.phase * 9.0)) * p.flutterAmp
            p.node.position = LivingWorld.position(CGPoint(x: mx, y: my))
            // Smooth fade-in from canopy/tuft and graceful fade-out at end of gust
            let fadeIn = min(1.0, uf / 0.14)
            let fadeOut = min(1.0, (1.0 - uf) / 0.20)
            p.node.alpha = p.baseAlpha * fadeIn * fadeOut
            // 3D tumbling illusion via cos xScale + gentle rotation
            let tumble = CGFloat(cos(t * p.tumbleFreq + p.phase * 15.0))
            p.node.xScale = p.baseScale * (tumble >= 0 ? max(0.28, tumble) : min(-0.28, tumble))
            p.node.yScale = p.baseScale * (0.85 + 0.15 * abs(tumble))
            p.node.zRotation = CGFloat(sin(t * (p.tumbleFreq * 0.6) + p.phase * 8.0)) * 0.85 - 0.32
        }
    }
}
