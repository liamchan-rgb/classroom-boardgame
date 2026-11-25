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
        let brook = roadMask == nil ? MeadowRoadMask.findBrookCrossing(network: network, nodePoints: nodePoints, seed: definition.seed) : nil
        if renderTerrain { buildGround(); buildRoads(mask: roadMask ?? MeadowRoadMask.makeWithBrook(network: network, bounds: worldBounds, brook: brook)) }
        else { self.roadMask = roadMask ?? MeadowRoadMask.makeWithBrook(network: network, bounds: worldBounds, brook: brook) }
        let allProps = props ?? (definition.props
            + Self.worldDioramaProps(definition: definition, network: network, bridge: brook)
            + Self.meadowDetails(definition: definition, network: network)
            + Self.roadsideGrass(network: network, seed: definition.seed))
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
        if asset?.isGroundDecal == true {
            node.zPosition = prop.asset == "MapBridgeWood" ? 62 : (prop.asset == "MapPond" ? 54 : 52)
        } else {
            node.zPosition = 10000 + prop.y
        }
        // Preserve upper-left painted highlights on solid objects.
        node.xScale = prop.mirror && (asset?.isFlower == true) ? -1 : 1
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

    /// Live micro-diorama dressing around landmarks, crossroads, and the meadow brook.
    /// Runs deterministically for both newly generated maps and legacy saved campaigns.
    static func worldDioramaProps(definition: SceneDefinition, network: TrailNetwork, bridge: MeadowBrookCrossing?) -> [SceneDefinition.Prop] {
        var added: [SceneDefinition.Prop] = []
        var random = MeadowRandom(seed: definition.seed ^ 0x44494f52414d41)
        let existing = definition.props

        // Compute node road degree so we place signposts at genuine forks (degree >= 3)
        var degree: [Int: Int] = [:]
        for r in definition.roads {
            degree[r.from, default: 0] += 1
            degree[r.to, default: 0] += 1
        }

        func canPlaceMicro(_ p: CGPoint, roadClear: CGFloat = 24, propClear: CGFloat = 24, ignoreNodeID: Int? = nil) -> Bool {
            guard network.project(p).error > roadClear else { return false }
            for other in existing {
                if let ignoreNodeID, other.nodeID == ignoreNodeID { continue }
                let minD: CGFloat = other.nodeID != nil ? max(56, other.width * 0.56) : propClear
                if hypot(other.x - p.x, other.y - p.y) < minD { return false }
            }
            for other in added where other.asset != "MapGroundStonePlaza" && other.asset != "MapBridgeWood" {
                if hypot(other.x - p.x, other.y - p.y) < propClear { return false }
            }
            return true
        }

        // 1. Arched wooden bridge centered cleanly over the sparkling brook crossing
        if let bridge {
            added.append(SceneDefinition.Prop(asset: "MapBridgeWood", x: bridge.center.x, y: bridge.center.y, width: 82, mirror: false, wind: 0))
            // Tuck 2 bluebells beside bridge abutments
            for side in [CGFloat(-1), CGFloat(1)] {
                let fp = CGPoint(x: bridge.center.x + side * 42, y: bridge.center.y + 18)
                if network.project(fp).error > 16 {
                    added.append(SceneDefinition.Prop(asset: "MapFlowersBlue", x: fp.x, y: fp.y, width: 15, mirror: side < 0, wind: 1.1))
                }
            }
        }

        // 2. Node plazas & storytelling micro-props around landmarks
        for prop in existing where prop.nodeID != nil {
            let nid = prop.nodeID!
            let basePoint = CGPoint(x: prop.x, y: prop.y)

            // Mossy cobblestone plaza underlay tightly framing Boss Sanctums, Start Camp, and Stone Watchkeeps
            if prop.asset.hasPrefix("NodeBoss") || prop.asset == "CampTent" || prop.asset == "NodeCombatTower" {
                let plazaW = prop.width * (prop.asset == "CampTent" ? 1.12 : 1.06)
                added.append(SceneDefinition.Prop(asset: "MapGroundStonePlaza", x: prop.x, y: prop.y - 4, width: plazaW, mirror: false, wind: 0))
            }

            // Starting camp vignette: warm campfire + supply pile + trail lantern
            if prop.asset == "CampTent" {
                let candidates: [(String, CGPoint, CGFloat)] = [
                    ("MapPropCampfire", CGPoint(x: basePoint.x - 54, y: basePoint.y + 22), 34),
                    ("MapPropSupplies", CGPoint(x: basePoint.x + 56, y: basePoint.y + 10), 36),
                    ("MapPropLanternPost", CGPoint(x: basePoint.x + 48, y: basePoint.y - 24), 22)
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

            // Reward nodes: supply crate/barrel cluster tucked neatly alongside
            if prop.asset.hasPrefix("NodeReward") {
                for side in [CGFloat(-1), CGFloat(1)] {
                    let pt = CGPoint(x: basePoint.x + side * (prop.width * 0.56), y: basePoint.y + 8)
                    if canPlaceMicro(pt, roadClear: 22, propClear: 26, ignoreNodeID: nid) {
                        added.append(SceneDefinition.Prop(asset: "MapPropSupplies", x: pt.x, y: pt.y, width: 30, mirror: false, wind: 0))
                        break
                    }
                }
            }

            // Rest/Waystone nodes: glowing roadside lantern post
            if prop.asset == "NodeWaystone" || prop.asset == "NodeShrine" || prop.asset == "NodePavilion" {
                for side in [CGFloat(-1), CGFloat(1)] {
                    let pt = CGPoint(x: basePoint.x + side * (prop.width * 0.54), y: basePoint.y + 6)
                    if canPlaceMicro(pt, roadClear: 22, propClear: 24, ignoreNodeID: nid) {
                        added.append(SceneDefinition.Prop(asset: "MapPropLanternPost", x: pt.x, y: pt.y, width: 22, mirror: false, wind: 0))
                        break
                    }
                }
            }

            // Boss nodes: weathered gold-trim ruined pillar framing one side
            if prop.asset.hasPrefix("NodeBoss") {
                for side in [CGFloat(-1), CGFloat(1)] {
                    let pt = CGPoint(x: basePoint.x + side * (prop.width * 0.62), y: basePoint.y + 4)
                    if canPlaceMicro(pt, roadClear: 24, propClear: 28, ignoreNodeID: nid) {
                        added.append(SceneDefinition.Prop(asset: "MapPropRuinedPillar", x: pt.x, y: pt.y, width: 34, mirror: false, wind: 0))
                        break
                    }
                }
            }

            // Crossroads / road forks (degree >= 3): wooden directional trail signpost
            if (degree[nid] ?? 0) >= 3 && !prop.asset.hasPrefix("NodeBoss") {
                let side: CGFloat = random.next() > 0.5 ? -1 : 1
                let pt = CGPoint(x: basePoint.x + side * (prop.width * 0.58), y: basePoint.y + 24)
                if canPlaceMicro(pt, roadClear: 22, propClear: 26, ignoreNodeID: nid) {
                    added.append(SceneDefinition.Prop(asset: "MapPropSignpost", x: pt.x, y: pt.y, width: 24, mirror: false, wind: 0))
                }
            }
        }

        // 3. Outer woodland rim & quiet-clearing framing groves (gives rich storybook depth on both new & saved maps)
        let mapH = definition.mapHeight ?? 720
        let rimPalette = ["OakA", "OakB", "Pines", "MapTreeAutumnOak", "MapTreeAutumnMaple", "MapTreeBlossom", "MapTreePineAlpine", "MapShrubAutumn", "MapFlowersBlue", "MapFlowersCrimson", "MapFlowersLavender"]
        var rimPlaced = 0
        for _ in 0..<240 where rimPlaced < 28 {
            let pt = CGPoint(x: random.value(-40, 1320), y: random.value(-40, mapH + 60))
            guard network.project(pt).error > 84 else { continue }
            guard existing.allSatisfy({ hypot($0.x - pt.x, $0.y - pt.y) > ($0.nodeID != nil ? 132 : 48) }) else { continue }
            guard added.allSatisfy({ ($0.asset == "MapGroundStonePlaza") || hypot($0.x - pt.x, $0.y - pt.y) > 46 }) else { continue }
            if let bridge, hypot(bridge.center.x - pt.x, bridge.center.y - pt.y) < 110 { continue }
            let idx = Int(random.next() * CGFloat(rimPalette.count)) % rimPalette.count
            let asset = rimPalette[idx]
            let isFlower = asset.hasPrefix("MapFlowers")
            let isShrub = asset == "MapShrubAutumn"
            let w: CGFloat = isFlower ? random.value(16, 24) : (isShrub ? random.value(28, 38) : random.value(64, 88))
            added.append(SceneDefinition.Prop(asset: asset, x: pt.x, y: pt.y, width: w, mirror: random.next() > 0.5, wind: 1.0))
            rimPlaced += 1
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

    static func roadsideGrass(network: TrailNetwork, seed: UInt64 = 39281) -> [SceneDefinition.Prop] {
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
                let pickIdx = Int(random.next() * CGFloat(palette.count)) % palette.count
                props.append(SceneDefinition.Prop(asset: palette[pickIdx], x: px, y: py,
                                             width: random.value(8, 15), mirror: random.next() > 0.5, wind: 1.2))
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
