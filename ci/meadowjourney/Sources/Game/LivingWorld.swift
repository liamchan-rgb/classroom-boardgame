import SpriteKit

final class LivingWorld: SKNode {
    static let bounds = CGRect(x: -160, y: -220, width: 1600, height: 1160)
    let definition: SceneDefinition
    let network: TrailNetwork
    let effects = EnvironmentShaders()
    private var textures: [String: SKTexture] = [:]
    private var shadows: [SKSpriteNode] = []
    private var lastShadowUpdate: TimeInterval = -1
    private(set) var objectCount = 0

    init(definition: SceneDefinition) {
        self.definition = definition
        network = TrailNetwork(roads: definition.roads)
        super.init()
        buildGround()
        buildRoads()
        for prop in definition.props { addProp(prop) }
        buildMeadowDetails()
        buildRoadsideGrass()
        addOverlay(shader: effects.backMist, depth: 95)
        addOverlay(shader: effects.sunlight, depth: 20000, additive: true)
        addOverlay(shader: effects.frontMist, depth: 21000)
        buildMotes()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func texture(_ name: String) -> SKTexture {
        if let texture = textures[name] { return texture }
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .linear
        textures[name] = texture
        return texture
    }

    static func position(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: -point.y) }

    private func buildGround() {
        let tile: CGFloat = 320
        let groundTexture = texture("MeadowGround")
        for row in 0..<4 {
            for column in 0..<5 {
                let x = Self.bounds.minX + CGFloat(column) * tile
                let y = Self.bounds.minY + CGFloat(row) * tile
                let node = SKSpriteNode(texture: groundTexture, size: CGSize(width: tile, height: tile))
                node.position = Self.position(CGPoint(x: x + tile / 2, y: y + tile / 2))
                let flipX: CGFloat = column % 2 == 0 ? 1 : -1
                let flipY: CGFloat = row % 2 == 0 ? 1 : -1
                node.xScale = flipX
                node.yScale = flipY
                node.zPosition = 0
                effects.apply(effects.ground, to: node,
                              origin: CGPoint(x: x + tile / 2, y: y + tile / 2),
                              extent: CGSize(width: tile * flipX, height: tile * flipY))
                addChild(node)
            }
        }
    }

    private func roadPolygon(_ trail: Trail, width: CGFloat) -> CGPath {
        var left: [CGPoint] = [], right: [CGPoint] = []
        for index in trail.points.indices {
            let before = trail.points[max(0, index - 1)]
            let after = trail.points[min(trail.points.count - 1, index + 1)]
            let dx = after.x - before.x
            let dy = after.y - before.y
            let length = max(0.1, (dx * dx + dy * dy).squareRoot())
            let half = width / 2 * (1 + sin(CGFloat(index) * 0.85) * 0.10)
            let offset = CGPoint(x: -dy / length * half, y: dx / length * half)
            let p = trail.points[index]
            left.append(Self.position(CGPoint(x: p.x + offset.x, y: p.y + offset.y)))
            right.append(Self.position(CGPoint(x: p.x - offset.x, y: p.y - offset.y)))
        }
        let path = CGMutablePath()
        path.addLines(between: left + Array(right.reversed()))
        path.closeSubpath()
        return path
    }

    private func buildRoads() {
        for edge in network.edges {
            let border = SKShapeNode(path: roadPolygon(edge.trail, width: edge.width + 6))
            border.fillColor = SKColor(red: 0.59, green: 0.48, blue: 0.22, alpha: 0.40)
            border.strokeColor = .clear
            border.zPosition = 10
            addChild(border)
            let road = SKShapeNode(path: roadPolygon(edge.trail, width: edge.width))
            road.fillColor = SKColor(red: 0.89, green: 0.72, blue: 0.44, alpha: 1)
            road.strokeColor = .clear
            road.fillShader = effects.soil
            road.zPosition = 11
            addChild(road)
        }
    }

    private func addProp(_ prop: SceneDefinition.Prop) {
        let propTexture = texture(prop.asset)
        let height = prop.width * propTexture.size().height / propTexture.size().width
        let node = SKSpriteNode(texture: propTexture, size: CGSize(width: prop.width, height: height))
        node.anchorPoint = CGPoint(x: 0.5, y: 0.02)
        node.position = Self.position(CGPoint(x: prop.x, y: prop.y))
        node.zPosition = 10000 + prop.y
        node.xScale = prop.mirror ? -1 : 1
        effects.apply(effects.vegetation, to: node,
                      origin: CGPoint(x: prop.x, y: prop.y - height * 0.48),
                      extent: CGSize(width: prop.width * node.xScale, height: height),
                      wind: prop.wind, phase: Float(prop.x * 0.03 + prop.y * 0.017))
        addChild(node)
        objectCount += 1
        if prop.asset != "Flowers" {
            let shadow = SKSpriteNode(texture: propTexture, size: CGSize(width: prop.width * 0.85, height: height * 0.50))
            shadow.anchorPoint = CGPoint(x: 0.5, y: 0.02)
            shadow.position = Self.position(CGPoint(x: prop.x + 3, y: prop.y + 3))
            shadow.xScale = node.xScale
            shadow.zRotation = -2.2
            shadow.shader = effects.shadow
            shadow.zPosition = 40
            addChild(shadow)
            shadows.append(shadow)
        }
        if prop.asset == "WatchTower" || prop.asset == "CampTent" {
            let bannerTexture = texture("Banner")
            let width: CGFloat = prop.asset == "WatchTower" ? 43 : 35
            let banner = SKSpriteNode(texture: bannerTexture,
                                      size: CGSize(width: width, height: width * bannerTexture.size().height / bannerTexture.size().width))
            banner.anchorPoint = CGPoint(x: 0, y: 0.04)
            banner.position = CGPoint(x: prop.asset == "WatchTower" ? 0 : -prop.width * 0.18, y: height - 5)
            banner.zPosition = 1
            effects.apply(effects.vegetation, to: banner,
                          origin: CGPoint(x: prop.x + width / 2, y: prop.y - height),
                          extent: banner.size, wind: 2, phase: Float(prop.x * 0.03))
            node.addChild(banner)
        }
    }

    private func buildMeadowDetails() {
        var random = MeadowRandom(seed: definition.seed)
        for index in 0..<230 {
            let point = CGPoint(x: random.value(Self.bounds.minX, Self.bounds.maxX),
                                y: random.value(Self.bounds.minY, Self.bounds.maxY))
            if network.project(point).error < 23 { continue }
            if CGRect(x: 220, y: 285, width: 330, height: 125).contains(point) { continue }
            let name = index % 5 == 0 ? "Shrub" : "Flowers"
            let width = name == "Shrub" ? random.value(28, 43) : random.value(17, 32)
            addProp(SceneDefinition.Prop(asset: name, x: point.x, y: point.y, width: width,
                                         mirror: random.next() > 0.5, wind: 1.15))
        }
    }

    private func addOverlay(shader: SKShader, depth: CGFloat, additive: Bool = false) {
        let node = SKSpriteNode(color: .white, size: Self.bounds.size)
        node.position = Self.position(CGPoint(x: Self.bounds.midX, y: Self.bounds.midY))
        node.shader = shader
        node.zPosition = depth
        if additive { node.blendMode = .add }
        addChild(node)
    }

    private func buildRoadsideGrass() {
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
                addProp(SceneDefinition.Prop(asset: "Flowers", x: point.x - dy / length * offset * side,
                                             y: point.y + dx / length * offset * side,
                                             width: random.value(7, 14), mirror: random.next() > 0.5, wind: 1.2))
                distance += random.value(10, 20)
            }
        }
    }

    private func buildMotes() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let dot = renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 4, y: 4, width: 8, height: 8))
        }
        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(image: dot)
        emitter.particleBirthRate = 2.5
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
        effects.time.floatValue = Float(time)
        if time - lastShadowUpdate > 0.10 {
            let angle = CGFloat(-2.2 + sin(time * 0.035) * 0.12)
            for shadow in shadows { shadow.zRotation = angle }
            lastShadowUpdate = time
        }
    }
}
