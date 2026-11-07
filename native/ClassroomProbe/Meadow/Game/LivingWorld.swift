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
        if renderTerrain { buildGround(); buildRoads(mask: roadMask) }
        else { self.roadMask = roadMask ?? MeadowRoadMask.make(network: network, bounds: worldBounds) }
        let allProps = props ?? (definition.props + Self.meadowDetails(definition: definition, network: network) + Self.roadsideGrass(network: network))
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

    private func addProp(_ prop: SceneDefinition.Prop) {
        let propTexture = texture(prop.asset)
        let height = prop.width * propTexture.size().height / propTexture.size().width
        let node = SKSpriteNode(texture: propTexture, size: CGSize(width: prop.width, height: height))
        node.name = prop.nodeID.map { "landmark-\($0)" } ?? prop.asset
        node.anchorPoint = CGPoint(x: 0.5, y: CGFloat(ShadowLabAsset(rawValue: prop.asset)?.anchorY ?? 0.04))
        node.position = Self.position(CGPoint(x: prop.x, y: prop.y))
        node.zPosition = 10000 + prop.y
        // Preserve upper-left painted highlights on solid objects.
        node.xScale = prop.mirror && prop.asset == "Flowers" ? -1 : 1
        let vegetationShader = prop.asset == "Flowers" || prop.asset == "Shrub" ? effects.meadowPlants : effects.vegetation
        if vegetationEnabled { effects.apply(vegetationShader, to: node,
                      origin: CGPoint(x: prop.x, y: prop.y - height * (0.5 - node.anchorPoint.y)),
                      extent: CGSize(width: prop.width * node.xScale, height: height),
                      wind: prop.wind, phase: Float(prop.x * 0.03 + prop.y * 0.017)) }
        addChild(node)
        objectCount += 1
        casterProps.append(prop)
        shadowCount += 1
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

    static func roadsideGrass(network: TrailNetwork) -> [SceneDefinition.Prop] {
        var props: [SceneDefinition.Prop] = []
        var random = MeadowRandom(seed: 39281)
        for edge in network.edges {
            var distance: CGFloat = 12
            while distance < edge.trail.length - 12 {
                let point = edge.trail.point(at: distance)
                let ahead = edge.trail.point(at: distance + 1)
                let dx = ahead.x - point.x
                let dy = ahead.y - point.y
                let length = max(0.1, (dx * dx + dy * dy).squareRoot())
                let side: CGFloat = random.next() > 0.5 ? 1 : -1
                let offset = edge.width / 2 + random.value(0, 3)
                props.append(SceneDefinition.Prop(asset: "Flowers", x: point.x - dy / length * offset * side,
                                             y: point.y + dx / length * offset * side,
                                             width: random.value(7, 14), mirror: random.next() > 0.5, wind: 1.2))
                distance += random.value(22, 38)
            }
        }
        return props
    }

    private func buildMotes() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
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
