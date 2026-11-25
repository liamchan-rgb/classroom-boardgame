import SpriteKit

final class LivingWorld: SKNode {
    static let bounds = CGRect(x: -160, y: -220, width: 1600, height: 1160)
    static let towerBannerRoofAnchorY: CGFloat = 0.91
    var worldBounds: CGRect { definition.worldBounds }
    let definition: SceneDefinition
    let network: TrailNetwork
    let effects: EnvironmentShaders
    private let vegetationEnabled: Bool
    private var textures: [String: SKTexture] = [:]
    let terrain = SKNode()
    private(set) var sunlightOverlay: SKSpriteNode?
    private(set) var roadMask: CGImage!
    private(set) var casterProps: [SceneDefinition.Prop] = []
    private(set) var shadowCount = 0
    private(set) var objectCount = 0
    private(set) var longestPopulateBatchSeconds: Double = 0

    init(definition: SceneDefinition, roadMask: CGImage? = nil, props: [SceneDefinition.Prop]? = nil, textures: [String: SKTexture] = [:], effects preparedEffects: EnvironmentShaders? = nil, deferProps: Bool = false, renderTerrain: Bool = true,
         vegetationEnabled: Bool = true, atmosphereEnabled: Bool = true) {
        self.definition = definition
        self.textures = textures
        self.effects = preparedEffects ?? EnvironmentShaders(worldHeight:definition.worldBounds.height)
        self.vegetationEnabled = vegetationEnabled
        network = TrailNetwork(roads: definition.roads, patrolStart: definition.startNodeID)
        super.init()
        addChild(terrain)
        let nodePoints = definition.props.filter { $0.nodeID != nil }.map { CGPoint(x: $0.x, y: $0.y + 26) }
        let cobbleCenters: [(point: CGPoint, radius: CGFloat)] = definition.props.compactMap { p in
            guard p.nodeID != nil else { return nil }
            if p.asset.hasPrefix("NodeBoss") { return (CGPoint(x: p.x, y: p.y + 20), 175) }
            if p.asset == "CampTent" || p.asset == "NodeCombatTower" { return (CGPoint(x: p.x, y: p.y + 18), 125) }
            return nil
        }
        let water = roadMask == nil ? MeadowRoadMask.planWaterSystem(network: network, nodePoints: nodePoints, mapHeight: definition.mapHeight ?? 720, seed: definition.seed) : nil
        if renderTerrain { buildGround(); buildRoads(mask: roadMask ?? MeadowRoadMask.makeWithWater(network: network, bounds: worldBounds, water: water, cobbleCenters: cobbleCenters)) }
        else { self.roadMask = roadMask ?? MeadowRoadMask.makeWithWater(network: network, bounds: worldBounds, water: water, cobbleCenters: cobbleCenters) }
        let safeBaseProps = water.map { w in
            definition.props.filter { prop in
                if prop.nodeID != nil { return true }
                let pt = CGPoint(x: prop.x, y: prop.y)
                if prop.asset == "MapPond", w.lake != nil, w.isNearWater(pt, margin: 145) { return false }
                return !w.isNearWater(pt, margin: 16)
            }
        } ?? definition.props
        let allProps = props ?? (safeBaseProps
            + Self.worldDioramaProps(definition: definition, baseProps: safeBaseProps, network: network, water: water)
            + Self.meadowDetails(definition: definition, network: network)
            + Self.roadsideGrass(network: network, seed: definition.seed, water: water))
        if !deferProps { for prop in allProps { addProp(prop) } }
        if atmosphereEnabled {
            addOverlay(shader: effects.backMist, depth: 95)
            sunlightOverlay = effects.makeSunlightOverlay(size: .zero)
            addOverlay(shader: effects.frontMist, depth: 21000)
            buildMotes()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The sun belongs to the viewport, not the world transform. Both production
    /// and diagnostic scenes attach this same overlay directly to the scene.
    func attachSunlight(to scene: SKScene) {
        guard let sunlightOverlay else { return }
        if sunlightOverlay.parent !== scene {
            sunlightOverlay.removeFromParent()
            scene.addChild(sunlightOverlay)
        }
        effects.layoutSunlight(sunlightOverlay, size: scene.size)
    }

    /// Keep UIKit's run loop available while attaching hundreds of prepared
    /// nodes. This world is not presented until the final batch is attached.
    func populate(_ props: [SceneDefinition.Prop], progress: @escaping (Double) -> Void, completion: @escaping () -> Void) {
        var index = 0
        func batch() {
            let began = ProcessInfo.processInfo.systemUptime
            let end = min(index + 8, props.count)
            while index < end { addProp(props[index]); index += 1 }
            longestPopulateBatchSeconds = max(longestPopulateBatchSeconds, ProcessInfo.processInfo.systemUptime - began)
            progress(Double(index) / Double(max(1, props.count)))
            if index < props.count { DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { batch() } }
            else { completion() }
        }
        batch()
    }

    func texture(_ name: String) -> SKTexture {
        if let texture = textures[name] { return texture }
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .linear
        textures[name] = texture
        return texture
    }

    static func position(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: -point.y) }

    private func buildGround() {
        let node = SKSpriteNode(texture: texture("MeadowGround"), size: worldBounds.size)
        node.position = Self.position(CGPoint(x: worldBounds.midX, y: worldBounds.midY))
        node.shader = effects.ground
        node.zPosition = 0
        terrain.addChild(node)
    }

    private func buildRoads(mask prepared: CGImage?) {
        let mask = prepared ?? MeadowRoadMask.make(network: network, bounds: worldBounds)
        roadMask = mask
        let road = SKSpriteNode(texture: SKTexture(cgImage: mask), size: worldBounds.size)
        road.position = Self.position(CGPoint(x: worldBounds.midX, y: worldBounds.midY))
        road.shader = effects.soil
        road.zPosition = 11
        terrain.addChild(road)
    }

    func makeContact(foot: CGPoint, width: CGFloat, depth: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(color: .white, size: CGSize(width: width, height: depth))
        node.position = foot
        node.shader = effects.contact
        node.zPosition = 45
        addChild(node)
        return node
    }

    private static var warmGlowTexture: SKTexture = {
        let format = UIGraphicsImageRendererFormat(); format.preferredRange = .standard; format.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
            let colors = [UIColor(red: 1.0, green: 0.78, blue: 0.34, alpha: 0.65).cgColor,
                          UIColor(red: 1.0, green: 0.54, blue: 0.16, alpha: 0.18).cgColor,
                          UIColor(red: 1.0, green: 0.40, blue: 0.10, alpha: 0.0).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) {
                ctx.cgContext.drawRadialGradient(grad, startCenter: CGPoint(x: 32, y: 32), startRadius: 2,
                                                 endCenter: CGPoint(x: 32, y: 32), endRadius: 31, options: [])
            }
        }
        return SKTexture(image: img)
    }()

    private func addProp(_ prop: SceneDefinition.Prop) {
        let propTexture = texture(prop.asset)
        let height = prop.width * propTexture.size().height / propTexture.size().width
        let asset = ShadowLabAsset(rawValue: prop.asset)
        let node = SKSpriteNode(texture: propTexture, size: CGSize(width: prop.width, height: height))
        node.name = prop.nodeID.map { "landmark-\($0)" } ?? prop.asset
        node.anchorPoint = CGPoint(x: 0.5, y: CGFloat(asset?.anchorY ?? 0.04))
        node.position = Self.position(CGPoint(x: prop.x, y: prop.y))
        if let rotation = prop.rotation { node.zRotation = rotation }
        if asset?.isGroundDecal == true {
            switch prop.asset {
            case "MapBridgeWood": node.zPosition = 62
            case "MapStoneStairs": node.zPosition = 60
            case "MapWoodPier": node.zPosition = 58
            case "MapLakeIslet": node.zPosition = 56
            case "MapLakeFlora": node.zPosition = 55
            case "MapPond": node.zPosition = 54
            default: node.zPosition = 52
            }
        } else {
            node.zPosition = 10000 + prop.y
        }
        // Preserve upper-left painted highlights on solid objects; allow subtle horizontal flip on flora & hill mounds.
        node.xScale = prop.mirror && (asset?.isFlower == true || prop.asset == "MapLakeFlora" || prop.asset == "MapWoodPier") ? -1 : 1
        let vegetationShader = (asset?.isFlower == true || asset?.isShrub == true) ? effects.meadowPlants : effects.vegetation
        if vegetationEnabled { effects.apply(vegetationShader, to: node,
                      origin: CGPoint(x: prop.x, y: prop.y - height * (0.5 - node.anchorPoint.y)),
                      extent: CGSize(width: prop.width * node.xScale, height: height),
                      wind: prop.wind, phase: Float(prop.x * 0.03 + prop.y * 0.017)) }
        addChild(node)
        objectCount += 1
        if asset?.isGroundDecal != true {
            casterProps.append(prop)
            shadowCount += 1
        }
        // Subtle warm firelight / lantern glow flicker for living HD-2D warmth
        if prop.asset == "MapPropCampfire" || prop.asset == "MapPropLanternPost" {
            let glowSize = prop.asset == "MapPropCampfire" ? prop.width * 1.65 : prop.width * 1.45
            let glow = SKSpriteNode(texture: Self.warmGlowTexture, size: CGSize(width: glowSize, height: glowSize * 0.78))
            glow.blendMode = .add
            glow.alpha = prop.asset == "MapPropCampfire" ? 0.52 : 0.42
            glow.position = prop.asset == "MapPropCampfire"
                ? CGPoint(x: 0, y: height * 0.36)
                : CGPoint(x: -prop.width * 0.16, y: height * 0.60)
            glow.zPosition = 2
            let phase = Double(Int(abs(prop.x * 13 + prop.y * 7)) % 10) * 0.12
            let pulse = SKAction.repeatForever(.sequence([
                .group([.fadeAlpha(to: glow.alpha * 1.24, duration: 0.75 + phase * 0.2), .scale(to: 1.09, duration: 0.75 + phase * 0.2)]),
                .group([.fadeAlpha(to: glow.alpha * 0.80, duration: 0.85 + phase * 0.2), .scale(to: 0.94, duration: 0.85 + phase * 0.2)])
            ]))
            glow.run(pulse)
            node.addChild(glow)
        }
        // CampTent already contains its stitched banner. The tower needs a
        // separate flag, anchored at the roof peak instead of the image top.
        if prop.asset == "WatchTower" {
            let bannerTexture = texture("Banner")
            let width = min(34, max(22, prop.width * 0.40))
            let banner = SKSpriteNode(texture: bannerTexture,
                                      size: CGSize(width: width, height: width * bannerTexture.size().height / bannerTexture.size().width))
            banner.name = "banner"
            banner.anchorPoint = CGPoint(x: 0.035, y: 0.04)
            banner.position = CGPoint(x: 0, y: height * (Self.towerBannerRoofAnchorY - node.anchorPoint.y))
            banner.zPosition = -1
            if vegetationEnabled { effects.apply(effects.vegetation, to: banner,
                          origin: CGPoint(x: prop.x + width * 0.465,
                                          y: prop.y - height * (Self.towerBannerRoofAnchorY - node.anchorPoint.y) - banner.size.height * 0.46),
                          extent: banner.size, wind: 2, phase: Float(prop.x * 0.03)) }
            node.addChild(banner)
        }
    }

    /// Live valley topography, connected waterfall-river-lake features, roadside construction,
    /// and lush overlapping perimeter woodlands. Runs deterministically for both new and legacy saves.
    static func worldDioramaProps(
        definition: SceneDefinition,
        baseProps: [SceneDefinition.Prop],
        network: TrailNetwork,
        water: MeadowWaterSystem?
    ) -> [SceneDefinition.Prop] {
        var added: [SceneDefinition.Prop] = []
        var random = MeadowRandom(seed: definition.seed ^ 0x44494f52414d41)
        let existing = baseProps
        let mapH = definition.mapHeight ?? 720
        let bossPoints = existing.filter { $0.asset.hasPrefix("NodeBoss") }.map { CGPoint(x: $0.x, y: $0.y + 26) }

        var degree: [Int: Int] = [:]
        for r in definition.roads {
            degree[r.from, default: 0] += 1
            degree[r.to, default: 0] += 1
        }

        func isWater(_ p: CGPoint, margin: CGFloat = 14) -> Bool {
            water?.isNearWater(p, margin: margin) ?? false
        }

        func canPlaceMicro(_ p: CGPoint, roadClear: CGFloat = 24, propClear: CGFloat = 24, ignoreNodeID: Int? = nil) -> Bool {
            guard !isWater(p, margin: 12) else { return false }
            guard network.project(p).error > roadClear else { return false }
            for other in existing {
                if let ignoreNodeID, other.nodeID == ignoreNodeID { continue }
                let minD: CGFloat = other.nodeID != nil ? max(56, other.width * 0.56) : propClear
                if hypot(other.x - p.x, other.y - p.y) < minD { return false }
            }
            for other in added where ShadowLabAsset(rawValue: other.asset)?.isGroundDecal != true {
                if hypot(other.x - p.x, other.y - p.y) < propClear { return false }
            }
            return true
        }

        // 1. Connected Mountain Waterfall + Flanking Cliff Ridge + Woodland Lake Features + Bridges
        if let water {
            if let wf = water.waterfall {
                added.append(SceneDefinition.Prop(asset: "MapWaterfall", x: wf.x, y: wf.y + 38, width: 128, mirror: false, wind: 0))
                // Frame the waterfall seamlessly with tightly joined flanking cliff terraces & highland pines
                for side in [CGFloat(-1), CGFloat(1)] {
                    let cx = wf.x + side * 102
                    let cy = wf.y + 26
                    if !isWater(CGPoint(x: cx, y: cy), margin: 2) && network.project(CGPoint(x: cx, y: cy)).error > 44
                        && existing.allSatisfy({ $0.nodeID == nil || hypot($0.x - cx, $0.y - cy) > 100 }) {
                        let cAsset = side > 0 ? "MapCliffCorner" : "MapCliffTerrace"
                        added.append(SceneDefinition.Prop(asset: cAsset, x: cx, y: cy, width: 148, mirror: false, wind: 0))
                    }
                    for tOff in [CGFloat(54), CGFloat(116)] {
                        let tx = wf.x + side * tOff
                        let ty = wf.y - 36 + random.value(-14, 8)
                        if network.project(CGPoint(x: tx, y: ty)).error > 46 {
                            let tAsset = random.next() > 0.40 ? "MapTreePineAlpine" : "OakA"
                            added.append(SceneDefinition.Prop(asset: tAsset, x: tx, y: ty, width: random.value(74, 94), mirror: false, wind: 1.0))
                        }
                    }
                }
            }

            if let lake = water.lake {
                // Mossy woodland islet resting gracefully inside the lake heart
                let isletX = lake.center.x + (lake.lobeCenter.x - lake.center.x) * 0.25
                let isletY = lake.center.y + 4
                added.append(SceneDefinition.Prop(asset: "MapLakeIslet", x: isletX, y: isletY, width: max(62, min(86, lake.rx * 0.62)), mirror: false, wind: 0))

                // Rustic lakeside wooden pier projecting cleanly into the turquoise lake water
                let rightShore = CGPoint(x: lake.center.x + lake.rx * 0.72, y: lake.center.y + lake.ry * 0.14)
                let leftShore = CGPoint(x: lake.center.x - lake.rx * 0.72, y: lake.center.y + lake.ry * 0.14)
                let useRight = network.project(rightShore).error >= network.project(leftShore).error
                let pierPt = useRight ? rightShore : leftShore
                added.append(SceneDefinition.Prop(asset: "MapWoodPier", x: pierPt.x, y: pierPt.y, width: 70, mirror: useRight, wind: 0))

                // Lily pads, pink lotuses & shoreline cattails scattered organically around the lake
                for i in 0..<6 {
                    let ang = CGFloat(i) / 6.0 * .pi * 2 + random.value(-0.22, 0.22)
                    let radScale = i % 2 == 0 ? 0.64 : 0.86
                    let fx = lake.center.x + cos(ang) * lake.rx * radScale
                    let fy = lake.center.y + sin(ang) * lake.ry * radScale
                    if hypot(fx - isletX, fy - isletY) < 42 || hypot(fx - pierPt.x, fy - pierPt.y) < 38 { continue }
                    added.append(SceneDefinition.Prop(asset: "MapLakeFlora", x: fx, y: fy, width: random.value(34, 46), mirror: i % 2 == 1, wind: 0.6))
                }
                // Lush shoreline boulders, flowers & trees framing the lake bank
                for i in 0..<10 {
                    let ang = CGFloat(i) / 10.0 * .pi * 2 + 0.18
                    let bx = lake.center.x + cos(ang) * (lake.rx + 28)
                    let by = lake.center.y + sin(ang) * (lake.ry + 24)
                    let bp = CGPoint(x: bx, y: by)
                    guard !isWater(bp, margin: 4), network.project(bp).error > 42,
                          existing.allSatisfy({ $0.nodeID == nil || hypot($0.x - bx, $0.y - by) > 96 }) else { continue }
                    if i % 3 == 0 {
                        let treePick = ["MapTreeBlossom", "OakA", "MapTreeAutumnOak", "MapTreePineAlpine"][i % 4]
                        added.append(SceneDefinition.Prop(asset: treePick, x: bx, y: by, width: random.value(62, 82), mirror: false, wind: 1.0))
                    } else if i % 3 == 1 {
                        added.append(SceneDefinition.Prop(asset: "MapFlowersBlue", x: bx, y: by, width: random.value(16, 22), mirror: i % 2 == 0, wind: 1.1))
                    } else {
                        added.append(SceneDefinition.Prop(asset: "Shrub", x: bx, y: by, width: random.value(28, 38), mirror: false, wind: 1.0))
                    }
                }
            }

            // Shoreline water flora along river bends + bridges over every road-river crossing
            if water.riverPoints.count >= 6 {
                for idx in stride(from: 4, to: water.riverPoints.count - 3, by: 5) {
                    let rp = water.riverPoints[idx]
                    guard water.bridges.allSatisfy({ hypot($0.center.x - rp.x, $0.center.y - rp.y) > 54 }) else { continue }
                    let side: CGFloat = idx % 2 == 0 ? 1 : -1
                    added.append(SceneDefinition.Prop(asset: "MapLakeFlora", x: rp.x + side * 18, y: rp.y, width: 32, mirror: side < 0, wind: 0.6))
                }
            }
            for bridge in water.bridges {
                added.append(SceneDefinition.Prop(asset: "MapBridgeWood", x: bridge.center.x, y: bridge.center.y, width: 88, mirror: false, wind: 0, rotation: bridge.angle))
                for side in [CGFloat(-1), CGFloat(1)] {
                    let fp = CGPoint(x: bridge.center.x + side * 44, y: bridge.center.y + 18)
                    if !isWater(fp, margin: 2) && network.project(fp).error > 16 {
                        added.append(SceneDefinition.Prop(asset: "MapFlowersBlue", x: fp.x, y: fp.y, width: 16, mirror: side < 0, wind: 1.1))
                    }
                }
            }
        }

        // 2. Sculpted Continuous Northern Mountain Cliff Rim + Lush Highland Forest Crown
        var cliffX: CGFloat = -40
        var cliffIndex = 0
        while cliffX <= 1320 {
            let cy = random.value(-26, 26) + (cliffIndex % 2 == 0 ? -8 : 10)
            let cp = CGPoint(x: cliffX, y: cy)
            let clearWF = water?.waterfall.map { hypot($0.x - cliffX, $0.y - cy) > 125 } ?? true
            if clearWF && !isWater(cp, margin: 14) && network.project(cp).error > 64
                && existing.allSatisfy({ $0.nodeID == nil || hypot($0.x - cliffX, $0.y - cy) > 106 }) {
                let roll = random.next()
                let cAsset = roll < 0.42 ? "MapCliffTerrace" : (roll < 0.72 ? "MapCliffCorner" : "MapHillMound")
                added.append(SceneDefinition.Prop(asset: cAsset, x: cliffX, y: cy, width: random.value(144, 174), mirror: false, wind: 0))
            }
            cliffX += random.value(92, 118)
            cliffIndex += 1
        }
        // Dense continuous highland woodland wall crowning the plateau behind the northern cliff rim
        let highlandTrees = ["MapTreePineAlpine", "Pines", "OakA", "MapTreeAutumnOak", "MapTreeAutumnMaple", "OakB"]
        var crownX: CGFloat = -110
        while crownX <= 1390 {
            for rowY in [CGFloat(-118), CGFloat(-74), CGFloat(-38)] {
                let tx = crownX + random.value(-22, 22)
                let ty = rowY + random.value(-12, 12)
                let pt = CGPoint(x: tx, y: ty)
                let clearWFTop = water?.waterfall.map { abs($0.x - tx) > 48 || ty < $0.y - 34 } ?? true
                guard clearWFTop, !isWater(pt, margin: 12), network.project(pt).error > 58 else { continue }
                let pick = highlandTrees[Int(random.next() * CGFloat(highlandTrees.count)) % highlandTrees.count]
                added.append(SceneDefinition.Prop(asset: pick, x: tx, y: ty, width: random.value(72, 98), mirror: false, wind: 1.0))
            }
            crownX += random.value(54, 72)
        }

        // Rolling grassy hills across quiet flanks & southern corners (breaks flat meadow!)
        var hillsPlaced = 0
        for _ in 0..<110 where hillsPlaced < 7 {
            let edge = hillsPlaced % 4
            let hx: CGFloat
            let hy: CGFloat
            if edge == 0 { hx = random.value(-55, 160); hy = random.value(140, mapH - 80) }
            else if edge == 1 { hx = random.value(1120, 1335); hy = random.value(140, mapH - 80) }
            else if edge == 2 { hx = random.value(140, 1140); hy = random.value(mapH - 70, mapH + 65) }
            else { hx = random.value(160, 1120); hy = random.value(140, mapH - 120) }
            let hp = CGPoint(x: hx, y: hy)
            guard !isWater(hp, margin: 38), network.project(hp).error > 84 else { continue }
            guard existing.allSatisfy({ hypot($0.x - hx, $0.y - hy) > ($0.nodeID != nil ? 138 : 66) }) else { continue }
            guard added.allSatisfy({ (ShadowLabAsset(rawValue: $0.asset)?.isGroundDecal == true) || hypot($0.x - hx, $0.y - hy) > 95 }) else { continue }
            added.append(SceneDefinition.Prop(asset: "MapHillMound", x: hx, y: hy, width: random.value(118, 152), mirror: false, wind: 0))
            hillsPlaced += 1
        }

        // 3. Node plazas, stone stairs, trail fences & storytelling micro-props around landmarks
        for prop in existing where prop.nodeID != nil {
            let nid = prop.nodeID!
            let basePoint = CGPoint(x: prop.x, y: prop.y)

            // Mossy cobblestone plaza underlay tightly framing Boss Sanctums, Start Camp, and Stone Watchkeeps
            if prop.asset.hasPrefix("NodeBoss") || prop.asset == "CampTent" || prop.asset == "NodeCombatTower" {
                let plazaW = prop.width * (prop.asset == "CampTent" ? 1.14 : 1.08)
                added.append(SceneDefinition.Prop(asset: "MapGroundStonePlaza", x: prop.x, y: prop.y - 4, width: plazaW, mirror: false, wind: 0))
            }

            // Carved stone stairs leading up to Boss Sanctum terrace when approach road lies to the south
            if prop.asset.hasPrefix("NodeBoss") {
                let stairPt = CGPoint(x: basePoint.x, y: basePoint.y + 30)
                if !isWater(stairPt, margin: 10) && network.project(stairPt).error < 28 {
                    added.append(SceneDefinition.Prop(asset: "MapStoneStairs", x: stairPt.x, y: stairPt.y, width: 46, mirror: false, wind: 0))
                }
            }

            // Starting camp vignette: warm campfire + supply pile + trail lantern + rustic trail fence
            if prop.asset == "CampTent" {
                let candidates: [(String, CGPoint, CGFloat)] = [
                    ("MapPropCampfire", CGPoint(x: basePoint.x - 54, y: basePoint.y + 22), 34),
                    ("MapPropSupplies", CGPoint(x: basePoint.x + 56, y: basePoint.y + 10), 36),
                    ("MapPropLanternPost", CGPoint(x: basePoint.x + 48, y: basePoint.y - 24), 22),
                    ("MapTrailFence", CGPoint(x: basePoint.x - 68, y: basePoint.y - 12), 54)
                ]
                for (asset, pt, w) in candidates {
                    if canPlaceMicro(pt, roadClear: 22, propClear: 26, ignoreNodeID: nid) {
                        added.append(SceneDefinition.Prop(asset: asset, x: pt.x, y: pt.y, width: w, mirror: false, wind: 0))
                    } else {
                        let alt = CGPoint(x: basePoint.x - (pt.x - basePoint.x), y: pt.y)
                        if canPlaceMicro(alt, roadClear: 22, propClear: 26, ignoreNodeID: nid) {
                            added.append(SceneDefinition.Prop(asset: asset, x: alt.x, y: alt.y, width: w, mirror: false, wind: 0))
                        }
                    }
                }
                continue
            }

            if prop.asset.hasPrefix("NodeReward") {
                for side in [CGFloat(-1), CGFloat(1)] {
                    let pt = CGPoint(x: basePoint.x + side * (prop.width * 0.56), y: basePoint.y + 8)
                    if canPlaceMicro(pt, roadClear: 22, propClear: 26, ignoreNodeID: nid) {
                        added.append(SceneDefinition.Prop(asset: "MapPropSupplies", x: pt.x, y: pt.y, width: 30, mirror: false, wind: 0))
                        break
                    }
                }
            }

            if prop.asset == "NodeWaystone" || prop.asset == "NodeShrine" || prop.asset == "NodePavilion" {
                for side in [CGFloat(-1), CGFloat(1)] {
                    let pt = CGPoint(x: basePoint.x + side * (prop.width * 0.54), y: basePoint.y + 6)
                    if canPlaceMicro(pt, roadClear: 22, propClear: 24, ignoreNodeID: nid) {
                        added.append(SceneDefinition.Prop(asset: "MapPropLanternPost", x: pt.x, y: pt.y, width: 22, mirror: false, wind: 0))
                        break
                    }
                }
            }

            if prop.asset.hasPrefix("NodeBoss") {
                for side in [CGFloat(-1), CGFloat(1)] {
                    let pt = CGPoint(x: basePoint.x + side * (prop.width * 0.62), y: basePoint.y + 4)
                    if canPlaceMicro(pt, roadClear: 24, propClear: 28, ignoreNodeID: nid) {
                        added.append(SceneDefinition.Prop(asset: "MapPropRuinedPillar", x: pt.x, y: pt.y, width: 34, mirror: false, wind: 0))
                        break
                    }
                }
            }

            if (degree[nid] ?? 0) >= 3 && !prop.asset.hasPrefix("NodeBoss") {
                let side: CGFloat = random.next() > 0.5 ? -1 : 1
                let pt = CGPoint(x: basePoint.x + side * (prop.width * 0.58), y: basePoint.y + 24)
                if canPlaceMicro(pt, roadClear: 22, propClear: 26, ignoreNodeID: nid) {
                    added.append(SceneDefinition.Prop(asset: "MapPropSignpost", x: pt.x, y: pt.y, width: 24, mirror: false, wind: 0))
                }
            }
        }

        // 4. Rustic roadside trail fences along scenic horizontal road shoulders
        var fencesPlaced = 0
        for edge in network.edges where fencesPlaced < 5 {
            guard edge.trail.length > 130 else { continue }
            let d = edge.trail.length * 0.48
            let pt = edge.trail.point(at: d)
            let a = edge.trail.point(at: d - 12), b = edge.trail.point(at: d + 12)
            guard abs(b.y - a.y) < abs(b.x - a.x) * 0.35 else { continue }
            let fPt = CGPoint(x: pt.x, y: pt.y - 25)
            if canPlaceMicro(fPt, roadClear: 20, propClear: 34) {
                added.append(SceneDefinition.Prop(asset: "MapTrailFence", x: fPt.x, y: fPt.y, width: 48, mirror: false, wind: 0))
                fencesPlaced += 1
            }
        }

        // 5. Lush Overlapping Woodland Groves & Wildflower Meadows (cohesive biome pockets, zero bald grass!)
        let phase = Double(definition.seed % 1024) * 0.61803398875
        func biomeTrees(at pt: CGPoint) -> ([String], [String], String) {
            if bossPoints.contains(where: { hypot($0.x - pt.x, $0.y - pt.y) < 250 }) {
                return (["MapTreePineAlpine", "Pines", "OakA"], ["MapFlowersLavender", "MapFlowersBlue"], "Shrub")
            }
            let n1 = sin(Double(pt.x) * 0.0029 + phase) * cos(Double(pt.y) * 0.0031 - phase * 0.7)
            let n2 = sin((Double(pt.x) * 0.0017 - Double(pt.y) * 0.0021) + phase * 1.3)
            let b = max(0, min(1, 0.5 + 0.34 * n1 + 0.22 * n2))
            if b > 0.58 {
                return (["MapTreeAutumnOak", "MapTreeAutumnMaple", "OakA"], ["MapFlowersCrimson", "Flowers"], "MapShrubAutumn")
            }
            if b < 0.38 {
                return (["MapTreeBlossom", "OakB", "OakA"], ["MapFlowersBlue", "MapFlowersLavender", "Flowers"], "Shrub")
            }
            return (["OakA", "OakB", "Pines", "MapTreeAutumnOak", "MapTreeBlossom"], ["Flowers", "MapFlowersBlue", "MapFlowersCrimson", "MapFlowersLavender"], "Shrub")
        }

        var grovesPlaced = 0
        for _ in 0..<520 where grovesPlaced < 76 {
            // Bias slightly toward framing the valley edges & quiet open meadows while keeping central roads crisp
            let pt = CGPoint(x: random.value(-85, 1365), y: random.value(-85, mapH + 100))
            guard !isWater(pt, margin: 24) else { continue }
            guard network.project(pt).error > 66 else { continue }
            guard existing.allSatisfy({ hypot($0.x - pt.x, $0.y - pt.y) > ($0.nodeID != nil ? 114 : 38) }) else { continue }
            guard added.allSatisfy({ other in
                if ShadowLabAsset(rawValue: other.asset)?.isGroundDecal == true { return true }
                let minD: CGFloat = (other.asset.hasPrefix("MapCliff") || other.asset == "MapWaterfall") ? 58 : 34
                return hypot(other.x - pt.x, other.y - pt.y) > minD
            }) else { continue }

            let (trees, flowers, shrub) = biomeTrees(at: pt)
            let roll = random.next()
            let asset: String
            let w: CGFloat
            let wind: Float
            if roll < 0.58 {
                asset = trees[Int(random.next() * CGFloat(trees.count)) % trees.count]
                w = random.value(62, 90)
                wind = 1.0
            } else if roll < 0.74 {
                asset = shrub
                w = random.value(28, 40)
                wind = 1.0
            } else if roll < 0.80 {
                asset = "MapLogMushrooms"
                w = random.value(44, 56)
                wind = 0
            } else {
                asset = flowers[Int(random.next() * CGFloat(flowers.count)) % flowers.count]
                w = random.value(15, 24)
                wind = 1.15
            }
            added.append(SceneDefinition.Prop(asset: asset, x: pt.x, y: pt.y, width: w, mirror: random.next() > 0.5, wind: wind))
            grovesPlaced += 1

            // Tuck 1-2 overlapping companion trees/shrubs/flower clusters directly beside grove seeds for true lush forest walls!
            if roll < 0.58 && grovesPlaced < 76 {
                let compCount = random.next() > 0.45 ? 2 : 1
                for _ in 0..<compCount where grovesPlaced < 76 {
                    let ang = random.value(0, .pi * 2)
                    let rad = random.value(34, 56)
                    let cp = CGPoint(x: pt.x + cos(ang) * rad, y: pt.y + sin(ang) * rad * 0.72)
                    guard !isWater(cp, margin: 22), network.project(cp).error > 64 else { continue }
                    guard existing.allSatisfy({ hypot($0.x - cp.x, $0.y - cp.y) > ($0.nodeID != nil ? 112 : 32) }) else { continue }
                    guard added.allSatisfy({ (ShadowLabAsset(rawValue: $0.asset)?.isGroundDecal == true) || hypot($0.x - cp.x, $0.y - cp.y) > 28 }) else { continue }
                    let subRoll = random.next()
                    let cAsset = subRoll < 0.55 ? asset : (subRoll < 0.80 ? shrub : flowers[Int(random.next() * CGFloat(flowers.count)) % flowers.count])
                    let cw: CGFloat = cAsset.hasPrefix("MapFlowers") || cAsset == "Flowers" ? random.value(15, 23) : (cAsset == shrub ? random.value(26, 36) : random.value(58, 82))
                    added.append(SceneDefinition.Prop(asset: cAsset, x: cp.x, y: cp.y, width: cw, mirror: random.next() > 0.5, wind: 1.0))
                    grovesPlaced += 1
                }
            }
        }
        return added
    }

    static func meadowDetails(definition: SceneDefinition, network: TrailNetwork) -> [SceneDefinition.Prop] {
        if definition.startNodeID != nil { return [] } // Generated decorations already reserve node/road clearances.
        var props: [SceneDefinition.Prop] = []
        var random = MeadowRandom(seed: definition.seed)
        for index in 0..<110 {
            let point = CGPoint(x: random.value(definition.worldBounds.minX, definition.worldBounds.maxX),
                                y: random.value(definition.worldBounds.minY, definition.worldBounds.maxY))
            if network.project(point).error < 38 { continue }
            if CGRect(x: 215, y: 275, width: 360, height: 160).contains(point) { continue }
            if definition.props.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 23 }) { continue }
            let name = index % 9 == 0 ? "Shrub" : "Flowers"
            let width = name == "Shrub" ? random.value(23, 34) : random.value(12, 23)
            props.append(SceneDefinition.Prop(asset: name, x: point.x, y: point.y, width: width,
                                         mirror: random.next() > 0.5, wind: 1.15))
        }
        return props
    }

    private func addOverlay(shader: SKShader, depth: CGFloat, additive: Bool = false) {
        let node = SKSpriteNode(color: .white, size: worldBounds.size)
        node.position = Self.position(CGPoint(x: worldBounds.midX, y: worldBounds.midY))
        node.shader = shader
        node.zPosition = depth
        if additive { node.blendMode = .add }
        addChild(node)
    }

    static func roadsideGrass(network: TrailNetwork, seed: UInt64 = 39281, water: MeadowWaterSystem? = nil) -> [SceneDefinition.Prop] {
        var props: [SceneDefinition.Prop] = []
        var random = MeadowRandom(seed: seed ^ 0x39281)
        let palette = ["Flowers", "MapFlowersBlue", "MapFlowersCrimson", "MapFlowersLavender"]
        for edge in network.edges {
            var distance: CGFloat = 14
            while distance < edge.trail.length - 14 {
                let point = edge.trail.point(at: distance)
                let ahead = edge.trail.point(at: distance + 1)
                let dx = ahead.x - point.x
                let dy = ahead.y - point.y
                let length = max(0.1, (dx * dx + dy * dy).squareRoot())
                let side: CGFloat = random.next() > 0.5 ? 1 : -1
                let offset = edge.width / 2 + random.value(1, 5)
                let px = point.x - dy / length * offset * side
                let py = point.y + dx / length * offset * side
                if water?.isNearWater(CGPoint(x: px, y: py), margin: 8) != true {
                    let pickIdx = Int(random.next() * CGFloat(palette.count)) % palette.count
                    props.append(SceneDefinition.Prop(asset: palette[pickIdx], x: px, y: py,
                                                 width: random.value(8, 15), mirror: random.next() > 0.5, wind: 1.2))
                }
                distance += random.value(22, 38)
            }
        }
        return props
    }

    private func buildMotes() {
        // Standard range: on a wide-colour Mac display the default (extended) bitmap loses its transparent edge in
        // SpriteKit and the motes draw as small flickering squares.
        let format = UIGraphicsImageRendererFormat(); format.preferredRange = .standard; format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
        let dot = renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 4, y: 4, width: 8, height: 8))
        }
        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(image: dot)
        emitter.particleBirthRate = 4
        emitter.particleLifetime = 16
        emitter.particleLifetimeRange = 5
        emitter.particlePositionRange = CGVector(dx: 1400, dy: 920)
        emitter.position = CGPoint(x: 620, y: -380)
        emitter.particleSpeed = 5
        emitter.particleSpeedRange = 4
        emitter.emissionAngle = 0.35
        emitter.emissionAngleRange = 0.6
        emitter.particleAlpha = 0.40
        emitter.particleAlphaRange = 0.15
        emitter.particleAlphaSpeed = -0.02
        emitter.particleScale = 0.20
        emitter.particleScaleRange = 0.10
        emitter.particleColor = SKColor(red: 1, green: 0.88, blue: 0.50, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.zPosition = 20500
        emitter.advanceSimulationTime(10)
        addChild(emitter)
    }

    func update(time: TimeInterval) {
        effects.update(time: time)
    }
}
