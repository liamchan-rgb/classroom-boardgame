import SpriteKit

/// Only launched by CI's -gaitReview argument; uses the production shaders,
/// textures and distance-to-pose mapping at a size suitable for visual checking.
final class GaitReviewScene: SKScene {
    var onReviewAccessibilityValue: ((String) -> Void)?
    private let effects = EnvironmentShaders()
    private let content = SKNode()
    private let ground = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
    private let canvas = CGSize(width: 1280, height: 720)
    private var frames: [[[SKTexture]]] = []
    private var actors: [SKSpriteNode] = []
    private var shadows: [ProjectedShadow] = []
    private var contacts: [SKSpriteNode] = []
    private var labels: [SKLabelNode] = []
    private var feet: [CGPoint] = []
    private let heading = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
    private var began: TimeInterval?

    override func didMove(to view: SKView) {
        guard actors.isEmpty else { return }
        // UIKit may present this scene before the SKView has a nonzero frame.
        // Build at stable logical dimensions and fit the content on every resize.
        let scale: CGFloat = 1
        let size = canvas
        ground.texture = SKTexture(imageNamed: "MeadowGround")
        ground.shader = effects.ground
        addChild(ground)
        addChild(content)
        let road = SKShapeNode(rect: CGRect(x: -10, y: size.height * 0.36 - 14 * scale, width: size.width + 20, height: 35 * scale))
        road.fillColor = .white
        road.strokeColor = .clear
        road.fillTexture = SKTexture(imageNamed: "MeadowGround")
        road.fillShader = effects.soil
        road.attributeValues = ["a_origin": SKAttributeValue(vectorFloat2: SIMD2(640, 442)),
                                "a_extent": SKAttributeValue(vectorFloat2: SIMD2(1280, 35))]
        road.zPosition = 10
        content.addChild(road)
        for index in 0..<3 {
            let directions = HeroFrames.load(index + 1)
            frames.append(directions)
            let sprite = SKSpriteNode(texture: directions[0][0], size: CGSize(width: 192 * scale, height: 192 * scale))
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.125)
            let foot = CGPoint(x: size.width * CGFloat(index + 1) / 4, y: size.height * 0.36)
            feet.append(foot)
            sprite.position = foot
            sprite.zPosition = 100
            content.addChild(sprite)
            actors.append(sprite)
            let shadow = ProjectedShadow(texture: directions[0][0], body: sprite.size, anchorY: sprite.anchorPoint.y,
                                         ratio: 0.82, softness: 2.0, opacity: 0.52, shader: effects.shadow)
            content.addChild(shadow)
            shadows.append(shadow)
            let contact = SKSpriteNode(color: .white, size: CGSize(width: 44 * scale, height: 13 * scale))
            contact.position = foot
            contact.shader = effects.contact
            contact.zPosition = 45
            content.addChild(contact)
            contacts.append(contact)
            let label = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
            label.text = "P\(index + 1)"
            label.position = CGPoint(x: foot.x, y: foot.y - 58 * scale)
            label.fontSize = 22 * scale
            label.fontColor = SKColor(red: 1, green: 0.96, blue: 0.80, alpha: 1)
            label.zPosition = 200
            content.addChild(label)
            labels.append(label)
        }
        heading.position = CGPoint(x: size.width / 2, y: size.height * 0.86)
        heading.fontSize = 30 * scale
        heading.fontColor = SKColor(red: 1, green: 0.96, blue: 0.80, alpha: 1)
        heading.zPosition = 200
        content.addChild(heading)
        layoutContent()
    }

    override func didChangeSize(_ oldSize: CGSize) { layoutContent() }

    private func layoutContent() {
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(size.width / canvas.width, size.height / canvas.height)
        ground.size = size
        ground.position = CGPoint(x: size.width / 2, y: size.height / 2)
        content.setScale(scale)
        content.position = CGPoint(x: (size.width - canvas.width * scale) / 2,
                                   y: (size.height - canvas.height * scale) / 2)
    }

    override func update(_ currentTime: TimeInterval) {
        if began == nil { began = currentTime }
        let elapsed = (currentTime - (began ?? currentTime)) * (ProcessInfo.processInfo.arguments.contains("-slowGaitReview") ? 0.25 : 1)
        effects.update(time: elapsed)
        let direction = [0, 4, 3, 7, 2, 6, 1, 5][Int(elapsed / 3) % 8]
        let names = ["正面", "向左", "背面", "向右", "右下", "左下", "左上", "右上"]
        let distance = CGFloat(elapsed) * HeroFrames.reviewSpeed
        let frame = WalkCycle.frame(at: distance)
        let phase = distance.truncatingRemainder(dividingBy: 24) / 24
        let angle = CGFloat(Int(elapsed / 3) % 8) * .pi / 4
        let travel = CGFloat(elapsed.truncatingRemainder(dividingBy: 3) - 1.5) * 126
        let projection = WalkCycle.projectedScale(dx: sin(angle), dy: cos(angle))
        let offset = CGPoint(x: sin(angle) * travel * projection, y: -cos(angle) * travel * projection)
        heading.text = "八方向步态 · " + names[direction]
        // UI verification can identify the fitted, visible review instead of
        // accepting a successfully launched app with all sprites off-screen.
        let viewport = CGRect(origin: .zero, size: size)
        let visible = actors.count == 3 && actors.allSatisfy { actor in
            let frame = actor.frame
            return actor.size.width > 100 && actor.size.height > 100
                && viewport.contains(content.convert(CGPoint(x: frame.minX, y: frame.minY), to: self))
                && viewport.contains(content.convert(CGPoint(x: frame.maxX, y: frame.maxY), to: self))
        }
        if let view, visible, content.xScale > 0, size.width > 100, size.height > 100 {
            let description = "步态验收：三位人物 · " + names[direction]
            if view.accessibilityValue != description {
                view.accessibilityValue = description
                onReviewAccessibilityValue?(description)
            }
        }
        for index in actors.indices {
            let texture = frames[index][direction][frame]
            let pose = HeroPose(heroIndex: index, facing: direction, frame: frame, phase: phase)
            actors[index].texture = texture
            actors[index].xScale = HeroFrames.isMirrored(direction) ? -1 : 1
            actors[index].warpGeometry = nil
            let foot = CGPoint(x: feet[index].x + offset.x, y: feet[index].y + offset.y)
            let poseOffset = pose.bodyOffset(size: actors[index].size)
            actors[index].position = CGPoint(x: foot.x + poseOffset.x, y: foot.y + poseOffset.y)
            contacts[index].position = foot
            labels[index].position = CGPoint(x: foot.x, y: foot.y - 58)
            let gait = SIMD2(Float(direction), Float(frame))
            effects.apply(effects.vegetation, to: actors[index], origin: CGPoint(x: actors[index].position.x, y: -actors[index].position.y - 50),
                          extent: actors[index].size, gait: gait)
            shadows[index].update(foot: actors[index].position, texture: texture, gait: gait, sun: effects.currentCast)
        }
    }
}
