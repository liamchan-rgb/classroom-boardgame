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
    private(set) var terrainField: CGImage?
    private(set) var waterSystem: MeadowWaterSystem?
    private(set) var casterProps: [SceneDefinition.Prop] = []
    private(set) var shadowCount = 0
    private(set) var objectCount = 0
    private(set) var longestPopulateBatchSeconds: Double = 0

    init(definition: SceneDefinition, roadMask: CGImage? = nil, terrainField: CGImage? = nil,
         waterSystem: MeadowWaterSystem? = nil, props: [SceneDefinition.Prop]? = nil,
         textures: [String: SKTexture] = [:], effects preparedEffects: EnvironmentShaders? = nil,
         deferProps: Bool = false, renderTerrain: Bool = true,
         vegetationEnabled: Bool = true, atmosphereEnabled: Bool = true) {
        self.definition = definition
        self.textures = textures
        self.effects = preparedEffects ?? EnvironmentShaders(worldHeight:definition.worldBounds.height)
        self.vegetationEnabled = vegetationEnabled
        network = TrailNetwork(roads: definition.roads, patrolStart: definition.startNodeID)
        super.init()
        addChild(terrain)
        let nodePoints = definition.props.filter { $0.nodeID != nil }.map { CGPoint(x: $0.x, y: $0.y + 26) }
        let bossPoints = definition.props.filter { $0.nodeID != nil && $0.asset.hasPrefix("NodeBoss") }.map { CGPoint(x: $0.x, y: $0.y + 26) }
        let startPoint = definition.props.first(where: { $0.asset == "CampTent" }).map { CGPoint(x: $0.x, y: $0.y + 26) }
        let cobbleCenters: [(point: CGPoint, radius: CGFloat)] = definition.props.compactMap { p in
            guard p.nodeID != nil else { return nil }
            if p.asset.hasPrefix("NodeBoss") { return (CGPoint(x: p.x, y: p.y + 20), 175) }
            if p.asset == "CampTent" || p.asset == "NodeCombatTower" { return (CGPoint(x: p.x, y: p.y + 18), 125) }
            return nil
        }
        let water: MeadowWaterSystem?
        if let waterSystem {
            water = waterSystem
        } else if roadMask == nil {
            water = MeadowRoadMask.planWaterSystem(
                network: network, nodePoints: nodePoints, bossPoints: bossPoints,
                startPoint: startPoint, mapHeight: definition.mapHeight ?? 720, seed: definition.seed
            )
        } else {
            water = nil
        }
        self.waterSystem = water
        if let roadMask {
            self.roadMask = roadMask
            self.terrainField = terrainField
            if renderTerrain { buildGround(); buildRoads(mask: roadMask) }
        } else {
            let built = MeadowRoadMask.makeTerrainTextures(network: network, bounds: worldBounds, water: water, cobbleCenters: cobbleCenters)
            self.roadMask = built.roadMask
            self.terrainField = built.terrainField
            if renderTerrain { buildGround(); buildRoads(mask: built.roadMask) }
        }

        let safeBaseProps = water.map { w in
            definition.props.filter { prop in
                if prop.nodeID != nil { return true }
                let pt = CGPoint(x: prop.x, y: prop.y)
                if prop.asset == "MapPond", w.lake != nil, w.isNearWater(pt, margin: 165) { return false }
                if prop.asset == "MapCliffTerrace" || prop.asset == "MapCliffCorner", pt.y < 110 { return false }
                return !w.isNearWater(pt, margin: 18)
            }
        } ?? definition.props

        let allProps = props ?? (safeBaseProps
            + Self.worldDioramaProps(definition: definition, baseProps: safeBaseProps, network: network, water: water)
            + Self.meadowDetails(definition: definition, network: network)
            + Self.roadsideGrass(network: network, seed: definition.seed, water: water))
        if !deferProps { for prop in allProps { addProp(prop) } }

        // Real-time animated flowing waterfall cascade + rising mist anchored directly inside MapWaterfallGorge!
        if let water, let wf = water.waterfall, let plunge = water.plungePool {
            buildWaterfallCascade(at: wf, plunge: plunge)
        }

        if atmosphereEnabled {
            addOverlay(shader: effects.backMist, depth: 95)
            sunlightOverlay = effects.makeSunlightOverlay(size: .zero)
            addOverlay(shader: effects.frontMist, depth: 21000)
            buildMotes()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Real-time GPU animated flowing waterfall sheet + billowing mist spray pouring through MapWaterfallGorge
    /// directly into the Metal plunge pool's expanding concentric foam rings (100% unified color & motion).
    private func buildWaterfallCascade(at wf: CGPoint, plunge: CGPoint) {
        let gorgeBaseY = wf.y + 40
        // Cascade flows vertically down the central canyon chute of MapWaterfallGorge into the plunge pool
        let cascadeSize = CGSize(width: 72, height: 118)
        let cascadeCenter = CGPoint(x: wf.x, y: wf.y - 4)
        effects.waterfall.uniformNamed("u_wfOrigin")?.vectorFloat2Value = SIMD2(Float(cascadeCenter.x), Float(cascadeCenter.y))
        effects.waterfall.uniformNamed("u_wfExtent")?.vectorFloat2Value = SIMD2(Float(cascadeSize.width), Float(cascadeSize.height))
        let cascade = SKSpriteNode(color: .white, size: cascadeSize)
        cascade.name = "animatedWaterfall"
        cascade.position = Self.position(cascadeCenter)
        cascade.shader = effects.waterfall
        // Render directly over MapWaterfallGorge (z = 10000 + gorgeBaseY), below foreground trees/heroes
        cascade.zPosition = 10000 + gorgeBaseY + 2
        addChild(cascade)

        // Soft billowing sunlit mist cloud hovering right over the impact point in the plunge pool
        let mistSize = CGSize(width: 138, height: 84)
        let mistCenter = CGPoint(x: plunge.x, y: plunge.y - 4)
        effects.waterfallMist.uniformNamed("u_mistOrigin")?.vectorFloat2Value = SIMD2(Float(mistCenter.x), Float(mistCenter.y))
        effects.waterfallMist.uniformNamed("u_mistExtent")?.vectorFloat2Value = SIMD2(Float(mistSize.width), Float(mistSize.height))
        let mist = SKSpriteNode(color: .white, size: mistSize)
        mist.name = "waterfallMist"
        mist.position = Self.position(mistCenter)
        mist.shader = effects.waterfallMist
        mist.zPosition = 10000 + gorgeBaseY + 8
        addChild(mist)
    }

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
            let end = min(index + 12, props.count)
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
            case "MapBridgeHoriz", "MapBridgeVert", "MapBridgeWood": node.zPosition = 64
            case "MapStairsFront", "MapStairsSide", "MapStoneStairs": node.zPosition = 61
            case "MapWoodPier": node.zPosition = 58
            case "MapLakeIslet": node.zPosition = 56
            case "MapLakeFlora": node.zPosition = 55
            case "MapPond": node.zPosition = 54
            default: node.zPosition = 52
            }
        } else {
            node.zPosition = 10000 + prop.y
        }
        // Allow horizontal flip on flora, piers, side-ascending stairs (to face uphill!), and organic river rocks.
        let allowFlip = asset?.isFlower == true || prop.asset == "MapLakeFlora" || prop.asset == "MapWoodPier"
            || prop.asset == "MapStairsSide" || prop.asset == "MapRiverBoulders" || prop.asset == "MapTerraceCliff"
        node.xScale = prop.mirror && allowFlip ? -1 : 1
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

    /// Major HD-2D Overworld Overhaul:
    /// - Multi-layered towering northern alpine mountain massif & dark wet waterfall gorge (zero Lego block wall!)
    /// - Mathematically aligned horizontal/vertical bridges & road-tangent stone stairs
    /// - Interior terraced embankments, rolling hills, wet river boulders & lakeside willows
    /// - Lush multi-scale ecological biodiversity across 18+ distinct tree/shrub/fern/grass/flower species!
    static func worldDioramaProps(
        definition: SceneDefinition,
        baseProps: [SceneDefinition.Prop],
        network: TrailNetwork,
        water: MeadowWaterSystem?
    ) -> [SceneDefinition.Prop] {
        var added: [SceneDefinition.Prop] = []
        var random = MeadowRandom(seed: definition.seed ^ 0x44494f52414d42)
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
        func isBridgeOrStair(_ p: CGPoint, pad: CGFloat = 16) -> Bool {
            (water?.isNearBridge(p, padAlong: pad, padAcross: pad + 6) ?? false)
            || (water?.isNearStair(p, radius: 34 + pad * 0.5) ?? false)
        }

        func canPlaceMicro(_ p: CGPoint, roadClear: CGFloat = 24, propClear: CGFloat = 24, ignoreNodeID: Int? = nil) -> Bool {
            guard !isWater(p, margin: 12), !isBridgeOrStair(p, pad: 12) else { return false }
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

        // =====================================================================
        // 1. TOWERING MULTI-LAYERED NORTHERN ALPINE MOUNTAIN RANGE & WATERFALL GORGE
        //    Replaces flat repeated cliff blocks with majestic interlocking granite massifs!
        // =====================================================================
        // 1a. Back Alpine Skyline Layer (huge interlocking granite peaks rising high behind the valley!)
        let backPeakXs: [CGFloat] = [-80, 120, 325, 535, 745, 960, 1170, 1360]
        for (idx, baseX) in backPeakXs.enumerated() {
            let px = baseX + random.value(-26, 26)
            let py = random.value(-64, -22)
            let asset = (idx % 2 == 0) ? "MapMountainPeakA" : "MapMountainPeakB"
            let w = random.value(285, 365)
            added.append(SceneDefinition.Prop(asset: asset, x: px, y: py, width: w, mirror: false, wind: 0))
        }

        // 1b. Waterfall Canyon Gorge + Towering Source Mountain Peak Behind Gorge + Flanking Buttresses
        if let water, let wf = water.waterfall, let plunge = water.plungePool {
            // Soaring source mountain peak rising directly behind the waterfall chasm so water emerges from high peaks!
            added.append(SceneDefinition.Prop(asset: "MapMountainPeakA", x: wf.x - 10, y: wf.y - 42, width: 320, mirror: false, wind: 0))
            // Dry wet-rock gorge chute (our animated SKShader waterfall cascades straight through its center!)
            added.append(SceneDefinition.Prop(asset: "MapWaterfallGorge", x: wf.x, y: wf.y + 40, width: 156, mirror: false, wind: 0))

            // Towering mountain buttresses hugging left & right of the waterfall gorge to conceal its flanks organically
            for side in [CGFloat(-1), CGFloat(1)] {
                let bx = wf.x + side * 124
                let by = wf.y + 34
                let buttress = side < 0 ? "MapMountainPeakB" : "MapMountainPeakA"
                added.append(SceneDefinition.Prop(asset: buttress, x: bx, y: by, width: 225, mirror: false, wind: 0))
                // Clinging alpine cypresses & pines framing the cliff gorge shoulders
                for (dx, dy, tw, tAsset) in [
                    (side * 66, CGFloat(-22), CGFloat(56), "MapTreeCypress"),
                    (side * 82, CGFloat(32), CGFloat(66), "MapTreePineAlpine"),
                    (side * 120, CGFloat(46), CGFloat(74), "Pines")
                ] {
                    let pt = CGPoint(x: wf.x + dx, y: wf.y + dy)
                    if !isWater(pt, margin: 6) && network.project(pt).error > 42
                        && existing.allSatisfy({ $0.nodeID == nil || hypot($0.x - pt.x, $0.y - pt.y) > 96 }) {
                        added.append(SceneDefinition.Prop(asset: tAsset, x: pt.x, y: pt.y, width: tw, mirror: false, wind: 0.9))
                    }
                }
                // Wet mossy river boulders framing the base of the plunge pool!
                let rbPt = CGPoint(x: plunge.x + side * 46, y: plunge.y + 12)
                added.append(SceneDefinition.Prop(asset: "MapRiverBoulders", x: rbPt.x, y: rbPt.y, width: 54, mirror: side > 0, wind: 0))
                // Lush bank ferns clinging to the damp mossy gorge stones
                let fnPt = CGPoint(x: plunge.x + side * 62, y: plunge.y + 22)
                if !isWater(fnPt, margin: 2) {
                    added.append(SceneDefinition.Prop(asset: "MapFernsCluster", x: fnPt.x, y: fnPt.y, width: 32, mirror: side < 0, wind: 1.0))
                }
            }
        }

        // 1c. Mid-Mountain Foothill Crags & Dense Alpine Conifer Slopes across Northern Rim
        var foothillX: CGFloat = -70
        var fIdx = 0
        while foothillX <= 1350 {
            let fy = random.value(10, 56) + (fIdx % 2 == 0 ? -12 : 12)
            let fp = CGPoint(x: foothillX, y: fy)
            let clearWF = water?.waterfall.map { abs($0.x - foothillX) > 165 } ?? true
            if clearWF && !isWater(fp, margin: 18) && network.project(fp).error > 66
                && existing.allSatisfy({ $0.nodeID == nil || hypot($0.x - foothillX, $0.y - fy) > 114 }) {
                let roll = random.next()
                let asset = roll < 0.40 ? "MapMountainPeakB" : (roll < 0.72 ? "MapMountainPeakA" : "MapTerraceCliff")
                let w = asset == "MapTerraceCliff" ? random.value(165, 205) : random.value(185, 245)
                added.append(SceneDefinition.Prop(asset: asset, x: foothillX, y: fy, width: w, mirror: fIdx % 2 == 1, wind: 0))
            }
            foothillX += random.value(128, 168)
            fIdx += 1
        }
        // Rich conifer & alpine forest mantle sweeping along the mountain foothills
        let alpineForest = ["MapTreePineAlpine", "Pines", "MapTreeCypress", "MapTreeAncientOak", "MapTreeBirch"]
        var crownX: CGFloat = -110
        while crownX <= 1390 {
            for rowY in [CGFloat(-44), CGFloat(14), CGFloat(58)] {
                let tx = crownX + random.value(-22, 22)
                let ty = rowY + random.value(-12, 14)
                let pt = CGPoint(x: tx, y: ty)
                let clearWF = water?.waterfall.map { abs($0.x - tx) > 64 || ty < $0.y - 46 } ?? true
                guard clearWF, !isWater(pt, margin: 16), network.project(pt).error > 58 else { continue }
                guard existing.allSatisfy({ $0.nodeID == nil || hypot($0.x - tx, $0.y - ty) > 102 }) else { continue }
                let pick = alpineForest[Int(random.next() * CGFloat(alpineForest.count)) % alpineForest.count]
                let w: CGFloat = pick == "MapTreeCypress" ? random.value(48, 66) : random.value(68, 92)
                added.append(SceneDefinition.Prop(asset: pick, x: tx, y: ty, width: w, mirror: false, wind: 1.0))
            }
            crownX += random.value(58, 80)
        }

        // =====================================================================
        // 2. WATERFRONT ECOSYSTEM: LAKE, WILLOWS, RIVER BOULDERS & LOCKED BRIDGES/STAIRS
        // =====================================================================
        if let water {
            if let lake = water.lake {
                // Mossy woodland islet resting gracefully inside the dark alpine lake heart
                let isletX = lake.center.x + (lake.lobeCenter.x - lake.center.x) * 0.25
                let isletY = lake.center.y + 4
                added.append(SceneDefinition.Prop(asset: "MapLakeIslet", x: isletX, y: isletY, width: max(62, min(86, lake.rx * 0.60)), mirror: false, wind: 0))

                // IRONCLAD SHORELINE-LOCKED PIER: MapWoodPier's painted 3/4 deck runs along ~28° (NW->SE unmirrored, NE->SW mirrored).
                // Ray-march strictly along upper-right (NE, mirror=true) and upper-left (NW, mirror=false) bays
                // so the pier ALWAYS projects perpendicular from dry shore straight into the lake center!
                let pierAngles: [CGFloat] = [-0.50, -0.32, -.pi + 0.50, -.pi + 0.32, -0.15, -.pi + 0.15]
                var bestPier: (pt: CGPoint, mirror: Bool, score: CGFloat)?
                for ang in pierAngles {
                    let dx = cos(ang), dy = sin(ang)
                    var shoreDist: CGFloat? = nil
                    var r: CGFloat = 24
                    while r <= max(lake.rx, lake.lobeRx) * 2.2 {
                        let sample = CGPoint(x: lake.center.x + dx * r, y: lake.center.y + dy * r)
                        if water.waterDepthFactor(at: sample) < 0.24 {
                            shoreDist = r
                            break
                        }
                        r += 3
                    }
                    guard let sd = shoreDist else { continue }
                    // Shift pier center slightly waterward (-10px from exact waterline) so stone abutment (+18px) grips dry grass
                    // and wooden outer pilings (-36px) stand solidly in deep reflective lake water!
                    let cand = CGPoint(x: lake.center.x + dx * (sd - 10), y: lake.center.y + dy * (sd - 10))
                    let landCheck = CGPoint(x: lake.center.x + dx * (sd + 14), y: lake.center.y + dy * (sd + 14))
                    let waterCheck = CGPoint(x: lake.center.x + dx * (sd - 34), y: lake.center.y + dy * (sd - 34))
                    guard water.waterDepthFactor(at: landCheck) < 0.12 && water.waterDepthFactor(at: waterCheck) > 0.45 else { continue }
                    let roadClear = network.project(cand).error
                    let nodeClear = existing.filter { $0.nodeID != nil }.map { hypot($0.x - cand.x, $0.y - cand.y) }.min() ?? 300
                    let isletClear = hypot(cand.x - isletX, cand.y - isletY)
                    guard roadClear > 40 && nodeClear > 86 && isletClear > 54 else { continue }
                    let mirror = dx > 0
                    let alignBonus: CGFloat = abs(abs(ang) - 0.50) < 0.20 || abs(abs(ang) - (.pi - 0.50)) < 0.20 ? 45 : 15
                    let score = min(roadClear, 140) + min(nodeClear, 180) + alignBonus
                    if bestPier == nil || score > bestPier!.score {
                        bestPier = (cand, mirror, score)
                    }
                }
                let pierPt: CGPoint? = bestPier?.pt
                if let bp = bestPier {
                    added.append(SceneDefinition.Prop(asset: "MapWoodPier", x: bp.pt.x, y: bp.pt.y, width: 66, mirror: bp.mirror, wind: 0))
                }

                // Lily pads, pink lotuses & shoreline reeds inside the shallow lake edge
                for i in 0..<7 {
                    let ang = CGFloat(i) / 7.0 * .pi * 2 + random.value(-0.20, 0.20)
                    let radScale: CGFloat = i % 2 == 0 ? 0.66 : 0.86
                    let fx = lake.center.x + cos(ang) * lake.rx * radScale
                    let fy = lake.center.y + sin(ang) * lake.ry * radScale
                    if hypot(fx - isletX, fy - isletY) < 42 { continue }
                    if let pierPt, hypot(fx - pierPt.x, fy - pierPt.y) < 42 { continue }
                    added.append(SceneDefinition.Prop(asset: "MapLakeFlora", x: fx, y: fy, width: random.value(34, 46), mirror: i % 2 == 1, wind: 0.6))
                }

                // Lush lakeside ecosystem: weeping willows, wet river boulders, ferns, tall grass & bluebells!
                for i in 0..<14 {
                    let ang = CGFloat(i) / 14.0 * .pi * 2 + 0.14
                    let bx = lake.center.x + cos(ang) * (lake.rx + 26)
                    let by = lake.center.y + sin(ang) * (lake.ry + 22)
                    let bp = CGPoint(x: bx, y: by)
                    guard !isWater(bp, margin: 4), network.project(bp).error > 38,
                          existing.allSatisfy({ $0.nodeID == nil || hypot($0.x - bx, $0.y - by) > 94 }) else { continue }
                    switch i % 5 {
                    case 0:
                        let treePick = (i % 10 == 0) ? "MapTreeWillow" : "MapTreeBirch"
                        added.append(SceneDefinition.Prop(asset: treePick, x: bx, y: by, width: random.value(76, 94), mirror: false, wind: 1.0))
                    case 1:
                        added.append(SceneDefinition.Prop(asset: "MapRiverBoulders", x: bx, y: by, width: random.value(40, 54), mirror: i % 2 == 0, wind: 0))
                    case 2:
                        added.append(SceneDefinition.Prop(asset: "MapFernsCluster", x: bx, y: by, width: random.value(28, 38), mirror: i % 2 == 1, wind: 1.1))
                    case 3:
                        added.append(SceneDefinition.Prop(asset: "MapTallGrassTuft", x: bx, y: by, width: random.value(24, 34), mirror: i % 2 == 0, wind: 1.25))
                    default:
                        added.append(SceneDefinition.Prop(asset: "MapFlowersBlue", x: bx, y: by, width: random.value(16, 22), mirror: i % 2 == 0, wind: 1.1))
                    }
                }
            }

            // Riverbank boulders, drooping willows, ferns & reeds along river bends (strictly outside bridge OBB!)
            if water.riverPoints.count >= 6 {
                for idx in stride(from: 3, to: water.riverPoints.count - 2, by: 3) {
                    let rp = water.riverPoints[idx]
                    guard !isBridgeOrStair(rp, pad: 24) else { continue }
                    let side: CGFloat = idx % 2 == 0 ? 1 : -1
                    let bankPt = CGPoint(x: rp.x + side * 26, y: rp.y + 4)
                    guard !isBridgeOrStair(bankPt, pad: 20), network.project(bankPt).error > 32,
                          existing.allSatisfy({ $0.nodeID == nil || hypot($0.x - bankPt.x, $0.y - bankPt.y) > 88 }) else { continue }
                    if idx % 9 == 0 {
                        let willowPt = CGPoint(x: rp.x + side * 42, y: rp.y)
                        if !isWater(willowPt, margin: 12) && !isBridgeOrStair(willowPt, pad: 26) && network.project(willowPt).error > 52 {
                            added.append(SceneDefinition.Prop(asset: "MapTreeWillow", x: willowPt.x, y: willowPt.y, width: random.value(76, 90), mirror: false, wind: 1.0))
                        }
                    } else if idx % 6 == 0 {
                        added.append(SceneDefinition.Prop(asset: "MapRiverBoulders", x: bankPt.x, y: bankPt.y, width: random.value(34, 44), mirror: side < 0, wind: 0))
                    } else if idx % 3 == 0 {
                        added.append(SceneDefinition.Prop(asset: "MapLakeFlora", x: rp.x + side * 16, y: rp.y, width: 30, mirror: side < 0, wind: 0.6))
                        let tuftPt = CGPoint(x: rp.x + side * 32, y: rp.y + 6)
                        if !isWater(tuftPt, margin: 4) && !isBridgeOrStair(tuftPt, pad: 18) && network.project(tuftPt).error > 26 {
                            added.append(SceneDefinition.Prop(asset: idx % 2 == 0 ? "MapFernsCluster" : "MapTallGrassTuft", x: tuftPt.x, y: tuftPt.y, width: 26, mirror: side < 0, wind: 1.15))
                        }
                    }
                }
            }

            // IRONCLAD ALIGNED BRIDGES (strictly matched horizontal/vertical sprite, clean OBB clearance!)
            for bridge in water.bridges {
                let asset = bridge.orientation == .horizontal ? "MapBridgeHoriz" : "MapBridgeVert"
                let w: CGFloat = bridge.orientation == .horizontal ? 92 : 50
                added.append(SceneDefinition.Prop(
                    asset: asset, x: bridge.center.x, y: bridge.center.y,
                    width: w, mirror: bridge.mirror, wind: 0, rotation: bridge.angle
                ))
                // Place mossy bank boulders ONLY strictly outside the bridge railing OBB (|across| >= 46px along riverbank!)
                let perpX = -bridge.roadDir.dy, perpY = bridge.roadDir.dx
                for side in [CGFloat(-1), CGFloat(1)] {
                    let rockPt = CGPoint(
                        x: bridge.center.x + perpX * side * 48 + bridge.roadDir.dx * side * 18,
                        y: bridge.center.y + perpY * side * 48 + bridge.roadDir.dy * side * 18
                    )
                    if !bridge.contains(rockPt, padAlong: 10, padAcross: 18)
                        && network.project(rockPt).error > 28
                        && existing.allSatisfy({ $0.nodeID == nil || hypot($0.x - rockPt.x, $0.y - rockPt.y) > 62 }) {
                        added.append(SceneDefinition.Prop(asset: "MapRiverBoulders", x: rockPt.x, y: rockPt.y, width: 30, mirror: side < 0, wind: 0))
                    }
                }
            }

            // IRONCLAD CLIFF-EMBEDDED FRONT STONE STAIRS (placed ONLY where straight N-S road climbs a real 26px terrace wall!)
            for stair in water.stairs {
                added.append(SceneDefinition.Prop(
                    asset: "MapStairsFront", x: stair.center.x, y: stair.center.y,
                    width: 30, mirror: false, wind: 0, rotation: stair.angle
                ))
            }

            // Natural mossy boulders & ferns grounding elevated plateau cliff corners (strictly off-road & clear of stairs!)
            for plat in water.plateaus {
                for offsetX in [CGFloat(-plat.rx * 0.62), CGFloat(plat.rx * 0.62)] {
                    let ep = CGPoint(x: plat.center.x + offsetX, y: plat.center.y + plat.ry * 0.96)
                    if !isWater(ep, margin: 24) && !isBridgeOrStair(ep, pad: 24) && network.project(ep).error > 56
                        && existing.allSatisfy({ $0.nodeID == nil || hypot($0.x - ep.x, $0.y - ep.y) > 94 })
                        && added.allSatisfy({ (ShadowLabAsset(rawValue: $0.asset)?.isGroundDecal == true) || hypot($0.x - ep.x, $0.y - ep.y) > 84 }) {
                        let outcrop = offsetX < 0 ? "RockLow" : "MapRiverBoulders"
                        added.append(SceneDefinition.Prop(asset: outcrop, x: ep.x, y: ep.y, width: random.value(54, 72), mirror: offsetX < 0, wind: 0))
                        added.append(SceneDefinition.Prop(asset: "MapFernsCluster", x: ep.x + (offsetX < 0 ? 22 : -22), y: ep.y + 8, width: 28, mirror: offsetX > 0, wind: 1.1))
                    }
                }
            }
        }

        // Rolling sculpted grassy hills & mossy outcrops scaled to map height (breaks flat meadow organically!)
        let mapScale = max(1.0, mapH / 760.0)
        let maxHills = min(14, Int((6.0 * mapScale).rounded()))
        var hillsPlaced = 0
        for _ in 0..<(maxHills * 18) where hillsPlaced < maxHills {
            let edge = hillsPlaced % 4
            let hx: CGFloat
            let hy: CGFloat
            if edge == 0 { hx = random.value(-40, 190); hy = random.value(150, mapH - 70) }
            else if edge == 1 { hx = random.value(1090, 1320); hy = random.value(150, mapH - 70) }
            else if edge == 2 { hx = random.value(160, 1120); hy = random.value(mapH - 70, mapH + 60) }
            else { hx = random.value(180, 1100); hy = random.value(160, mapH - 110) }
            let hp = CGPoint(x: hx, y: hy)
            guard !isWater(hp, margin: 38), network.project(hp).error > 84 else { continue }
            guard existing.allSatisfy({ hypot($0.x - hx, $0.y - hy) > ($0.nodeID != nil ? 136 : 64) }) else { continue }
            guard added.allSatisfy({ (ShadowLabAsset(rawValue: $0.asset)?.isGroundDecal == true) || hypot($0.x - hx, $0.y - hy) > 96 }) else { continue }
            let hAsset = hillsPlaced % 3 == 0 ? "MapHillMound" : (hillsPlaced % 3 == 1 ? "RockLow" : "MapRockSlate")
            let hw: CGFloat = hAsset == "MapHillMound" ? random.value(112, 140) : random.value(68, 92)
            added.append(SceneDefinition.Prop(asset: hAsset, x: hx, y: hy, width: hw, mirror: hillsPlaced % 2 == 1, wind: 0))
            hillsPlaced += 1
        }

        // =====================================================================
        // 3. NODE PLAZAS & STORYTELLING MICRO-PROPS AROUND LANDMARKS
        // =====================================================================
        for prop in existing where prop.nodeID != nil {
            let nid = prop.nodeID!
            let basePoint = CGPoint(x: prop.x, y: prop.y)

            if prop.asset.hasPrefix("NodeBoss") || prop.asset == "CampTent" || prop.asset == "NodeCombatTower" {
                let plazaW = prop.width * (prop.asset == "CampTent" ? 1.14 : 1.08)
                added.append(SceneDefinition.Prop(asset: "MapGroundStonePlaza", x: prop.x, y: prop.y - 4, width: plazaW, mirror: false, wind: 0))
            }

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

        // 4. Rustic roadside trail fences along clean horizontal road shoulders
        var fencesPlaced = 0
        for edge in network.edges where fencesPlaced < 5 {
            guard edge.trail.length > 130 else { continue }
            let d = edge.trail.length * 0.48
            let pt = edge.trail.point(at: d)
            let a = edge.trail.point(at: d - 12), b = edge.trail.point(at: d + 12)
            guard abs(b.y - a.y) < abs(b.x - a.x) * 0.30 else { continue }
            let fPt = CGPoint(x: pt.x, y: pt.y - 25)
            if canPlaceMicro(fPt, roadClear: 20, propClear: 34) {
                added.append(SceneDefinition.Prop(asset: "MapTrailFence", x: fPt.x, y: fPt.y, width: 48, mirror: false, wind: 0))
                fencesPlaced += 1
            }
        }

        // =====================================================================
        // 5. LUSH MULTI-LAYERED ECOLOGICAL GROVES & UNDERGROWTH BIODIVERSITY
        //    18+ species: Ancient Oak, Willow, Birch, Cypress, Blossom, Maple, Alpine Pine,
        //    Berry Bushes, Woodland Ferns, Tall Meadow Grass, Mossy Logs & 4-Color Wildflowers!
        // =====================================================================
        let phase = Double(definition.seed % 1024) * 0.61803398875
        func biomePalette(at pt: CGPoint) -> (trees: [String], shrubs: [String], ground: [String]) {
            if bossPoints.contains(where: { hypot($0.x - pt.x, $0.y - pt.y) < 255 }) {
                return (
                    ["MapTreeCypress", "MapTreePineAlpine", "Pines", "MapTreeAncientOak"],
                    ["Shrub", "MapBerryBush"],
                    ["MapFernsCluster", "MapTallGrassTuft", "MapFlowersLavender", "MapFlowersBlue"]
                )
            }
            let n1 = sin(Double(pt.x) * 0.0029 + phase) * cos(Double(pt.y) * 0.0031 - phase * 0.7)
            let n2 = sin((Double(pt.x) * 0.0017 - Double(pt.y) * 0.0021) + phase * 1.3)
            let b = max(0, min(1, 0.5 + 0.34 * n1 + 0.22 * n2))
            if b > 0.58 {
                return (
                    ["MapTreeAutumnOak", "MapTreeAutumnMaple", "MapTreeBirch", "MapTreeAncientOak"],
                    ["MapShrubAutumn", "MapBerryBush"],
                    ["MapTallGrassTuft", "MapFernsCluster", "MapFlowersCrimson", "Flowers"]
                )
            }
            if b < 0.38 {
                return (
                    ["MapTreeBlossom", "MapTreeBirch", "MapTreeWillow", "OakB"],
                    ["MapBerryBush", "Shrub"],
                    ["MapFernsCluster", "MapTallGrassTuft", "MapFlowersBlue", "MapFlowersLavender", "Flowers"]
                )
            }
            return (
                ["MapTreeAncientOak", "MapTreeBirch", "OakA", "OakB", "MapTreeCypress", "Pines", "MapTreeBlossom", "MapTreeAutumnOak"],
                ["MapBerryBush", "Shrub", "MapShrubAutumn"],
                ["MapTallGrassTuft", "MapFernsCluster", "Flowers", "MapFlowersBlue", "MapFlowersCrimson", "MapFlowersLavender"]
            )
        }

        // 5a. Cohesive multi-layer woodland groves scaled to map height (lush from north to south on both compact & epic maps!)
        let maxGroves = min(245, Int((110.0 * mapScale).rounded()))
        var grovesPlaced = 0
        for _ in 0..<(maxGroves * 6) where grovesPlaced < maxGroves {
            let pt = CGPoint(x: random.value(-80, 1360), y: random.value(75, mapH + 95))
            guard !isWater(pt, margin: 22), !isBridgeOrStair(pt, pad: 22) else { continue }
            guard network.project(pt).error > 56 else { continue }
            guard existing.allSatisfy({ hypot($0.x - pt.x, $0.y - pt.y) > ($0.nodeID != nil ? 106 : 32) }) else { continue }
            guard added.allSatisfy({ other in
                if ShadowLabAsset(rawValue: other.asset)?.isGroundDecal == true { return true }
                let minD: CGFloat = (other.asset.hasPrefix("MapMountain") || other.asset == "MapWaterfallGorge") ? 88 : 28
                return hypot(other.x - pt.x, other.y - pt.y) > minD
            }) else { continue }

            let (trees, shrubs, ground) = biomePalette(at: pt)
            let roll = random.next()
            let asset: String
            let w: CGFloat
            let wind: Float
            if roll < 0.52 {
                asset = trees[Int(random.next() * CGFloat(trees.count)) % trees.count]
                switch asset {
                case "MapTreeAncientOak": w = random.value(84, 106)
                case "MapTreeCypress": w = random.value(48, 66)
                case "MapTreeBirch": w = random.value(62, 82)
                case "MapTreeWillow": w = random.value(74, 92)
                default: w = random.value(64, 88)
                }
                wind = 1.0
            } else if roll < 0.70 {
                asset = shrubs[Int(random.next() * CGFloat(shrubs.count)) % shrubs.count]
                w = random.value(28, 42)
                wind = 1.0
            } else if roll < 0.76 {
                asset = "MapLogMushrooms"
                w = random.value(42, 54)
                wind = 0
            } else {
                asset = ground[Int(random.next() * CGFloat(ground.count)) % ground.count]
                w = (asset == "MapFernsCluster" || asset == "MapTallGrassTuft") ? random.value(22, 34) : random.value(15, 23)
                wind = 1.2
            }
            added.append(SceneDefinition.Prop(asset: asset, x: pt.x, y: pt.y, width: w, mirror: random.next() > 0.5, wind: wind))
            grovesPlaced += 1

            // Ground every tree naturally with 2-3 companion trees / berry bushes / ferns / tall grass tufts!
            if roll < 0.52 && grovesPlaced < maxGroves {
                let compCount = random.next() > 0.35 ? 3 : 2
                for ci in 0..<compCount where grovesPlaced < maxGroves {
                    let ang = random.value(0, .pi * 2)
                    let rad = ci == 0 ? random.value(34, 54) : random.value(20, 38)
                    let cp = CGPoint(x: pt.x + cos(ang) * rad, y: pt.y + sin(ang) * rad * 0.72)
                    guard !isWater(cp, margin: 18), network.project(cp).error > 42 else { continue }
                    guard existing.allSatisfy({ hypot($0.x - cp.x, $0.y - cp.y) > ($0.nodeID != nil ? 100 : 26) }) else { continue }
                    let cAsset: String
                    let cw: CGFloat
                    if ci == 0 && random.next() < 0.62 && network.project(cp).error > 56 {
                        cAsset = trees[Int(random.next() * CGFloat(trees.count)) % trees.count]
                        cw = cAsset == "MapTreeCypress" ? random.value(44, 60) : random.value(56, 78)
                    } else if ci == 1 {
                        cAsset = shrubs[Int(random.next() * CGFloat(shrubs.count)) % shrubs.count]
                        cw = random.value(24, 36)
                    } else {
                        cAsset = ground[Int(random.next() * CGFloat(ground.count)) % ground.count]
                        cw = (cAsset == "MapFernsCluster" || cAsset == "MapTallGrassTuft") ? random.value(20, 32) : random.value(14, 22)
                    }
                    added.append(SceneDefinition.Prop(asset: cAsset, x: cp.x, y: cp.y, width: cw, mirror: random.next() > 0.5, wind: 1.1))
                    grovesPlaced += 1
                }
            }
        }

        // 5b. Interior Meadow Wild-Grass, Fern & Wildflower Carpets scaled to map height!
        let maxTufts = min(195, Int((78.0 * mapScale).rounded()))
        var tuftsPlaced = 0
        for _ in 0..<(maxTufts * 4) where tuftsPlaced < maxTufts {
            let pt = CGPoint(x: random.value(20, 1260), y: random.value(100, mapH - 20))
            guard !isWater(pt, margin: 14), !isBridgeOrStair(pt, pad: 16), network.project(pt).error > 26 else { continue }
            guard existing.allSatisfy({ hypot($0.x - pt.x, $0.y - pt.y) > ($0.nodeID != nil ? 76 : 22) }) else { continue }
            guard added.allSatisfy({ (ShadowLabAsset(rawValue: $0.asset)?.isGroundDecal == true) || hypot($0.x - pt.x, $0.y - pt.y) > 22 }) else { continue }
            let (_, shrubs, ground) = biomePalette(at: pt)
            let r = random.next()
            let asset: String
            let w: CGFloat
            if r < 0.42 {
                asset = "MapTallGrassTuft"; w = random.value(22, 32)
            } else if r < 0.72 {
                asset = "MapFernsCluster"; w = random.value(22, 32)
            } else if r < 0.84 && network.project(pt).error > 42 {
                asset = shrubs[Int(random.next() * CGFloat(shrubs.count)) % shrubs.count]; w = random.value(24, 34)
            } else {
                asset = ground[Int(random.next() * CGFloat(ground.count)) % ground.count]
                w = (asset == "MapFernsCluster" || asset == "MapTallGrassTuft") ? random.value(20, 28) : random.value(14, 21)
            }
            added.append(SceneDefinition.Prop(asset: asset, x: pt.x, y: pt.y, width: w, mirror: random.next() > 0.5, wind: 1.25))
            tuftsPlaced += 1
        }

        return added
    }

    static func meadowDetails(definition: SceneDefinition, network: TrailNetwork) -> [SceneDefinition.Prop] {
        if definition.startNodeID != nil { return [] }
        var props: [SceneDefinition.Prop] = []
        var random = MeadowRandom(seed: definition.seed)
        for index in 0..<110 {
            let point = CGPoint(x: random.value(definition.worldBounds.minX, definition.worldBounds.maxX),
                                y: random.value(definition.worldBounds.minY, definition.worldBounds.maxY))
            if network.project(point).error < 38 { continue }
            if CGRect(x: 215, y: 275, width: 360, height: 160).contains(point) { continue }
            if definition.props.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 23 }) { continue }
            let name = index % 9 == 0 ? "Shrub" : (index % 3 == 0 ? "MapTallGrassTuft" : "Flowers")
            let width = name == "Shrub" ? random.value(23, 34) : (name == "MapTallGrassTuft" ? random.value(20, 28) : random.value(12, 23))
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
        let palette = ["MapTallGrassTuft", "MapFernsCluster", "Flowers", "MapFlowersBlue", "MapFlowersCrimson", "MapFlowersLavender", "MapTallGrassTuft"]
        for edge in network.edges {
            var distance: CGFloat = 14
            while distance < edge.trail.length - 14 {
                let point = edge.trail.point(at: distance)
                let ahead = edge.trail.point(at: distance + 1)
                let dx = ahead.x - point.x
                let dy = ahead.y - point.y
                let length = max(0.1, (dx * dx + dy * dy).squareRoot())
                let side: CGFloat = random.next() > 0.5 ? 1 : -1
                let offset = edge.width / 2 + random.value(2, 7)
                let px = point.x - dy / length * offset * side
                let py = point.y + dx / length * offset * side
                let pt = CGPoint(x: px, y: py)
                let clearBridge = !(water?.isNearBridge(pt, padAlong: 18, padAcross: 22) ?? false)
                let clearStair = !(water?.isNearStair(pt, radius: 34) ?? false)
                if clearBridge && clearStair && water?.isNearWater(pt, margin: 10) != true {
                    let pick = palette[Int(random.next() * CGFloat(palette.count)) % palette.count]
                    let w: CGFloat = (pick == "MapTallGrassTuft" || pick == "MapFernsCluster") ? random.value(17, 25) : random.value(12, 18)
                    props.append(SceneDefinition.Prop(asset: pick, x: px, y: py, width: w, mirror: random.next() > 0.5, wind: 1.25))
                }
                distance += random.value(26, 46)
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
