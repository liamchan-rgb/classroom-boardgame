import SpriteKit
import UIKit
import CoreImage

final class GrassScene: SKScene {
    private let geometry = WorldGeometry()
    private var graph = DisplayGraph.sample()
    private var store: AssetStore?
    private let world = SKNode()
    private let sunLayer = SKNode()
    private let cameraNode = SKCameraNode()
    private var renderer: HD2DRenderer?
    private var effects = HD2DSettings()
    private let atmosphereLayer = SKNode()
    private var contactNodes: [SKSpriteNode] = []
    private var windNodes: [SKSpriteNode] = []
    private var bloomNodes: [SKSpriteNode] = []
    private var communityNodes: [(SKSpriteNode, Bool)] = []
    private var groundEffectsByEntity: [ObjectIdentifier: [SKNode]] = [:]
    private var heroContact: SKSpriteNode?
    private var contactTexture: SKTexture?
    private var glowTexture: SKTexture?
    private let foreground = SKNode()
    private var foregroundEffects: [SKEffectNode] = []
    private var foregroundSprites: [SKSpriteNode] = []
    private var terrainNodes: [SKNode] = []
    private var protectedRoads: [RoadCurve] = []
    private var lastTick: TimeInterval?
    private var litSprites: [(SKSpriteNode, String)] = []
    private var shadowNodes: [SKSpriteNode] = []
    private var hero: SKSpriteNode?
    private var heroShadow: SKSpriteNode?
    private var heroLabel: SKLabelNode?
    private var focusRing: SKShapeNode?
    private var gate = PresentationGate()
    private var active: DemoPresentation?
    private var built = false
    private var zoom: CGFloat = 1
    private var follow = false
    private var mode: LightingMode = .sunlight
    private var strength: CGFloat = 0.75
    private var reducedMotion = false
    private var lastFrame = -1
    private var heroFrameIndex = 7
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?
    var onArrival: (() -> Void)?
    var reviewState: [String: Any] {
        ["heroX": Double(hero?.position.x ?? 0), "heroY": Double(hero?.position.y ?? 0),
         "lighting": mode.rawValue, "zoom": Double(zoom), "follow": follow,
         "moving": active != nil, "publicRoadCount": graph.publicEdges.count,
         "viewWidth": Double(size.width), "viewHeight": Double(size.height)]
    }
    private var points: [Int: CGPoint] { Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, geometry.point($0.point)) }) }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.49, green: 0.58, blue: 0.26, alpha: 1)
    }
    required init?(coder: NSCoder) { fatalError("Use init(size:)") }
    override func didMove(to view: SKView) {
        guard !built else { return }
        do {
            store = try AssetStore()
            addChild(world); world.addChild(sunLayer); sunLayer.zPosition = 8
            addChild(cameraNode); camera = cameraNode; cameraNode.position = CGPoint(x: 800, y: 768)
            world.addChild(atmosphereLayer); atmosphereLayer.zPosition = 9
            let roads = graph.publicEdges.compactMap { edge -> RoadCurve? in
                guard let a = points[edge.a], let b = points[edge.b] else { return nil }
                return RoadCurve(a: a, b: b, bend: edge.a == 1 ? -28 : 20)
            }
            let field = MeadowField(seed: graph.decorationSeed, roads: roads,
                                    landmarks: graph.nodes.filter(\.revealed).map { geometry.point($0.point) })
            renderer = HD2DRenderer(field: store!.meadowField(field),terrainField:store!.terrainField(field))
            contactTexture = store!.radialTexture(); glowTexture = store!.radialTexture(warm: true)
            try populate(); try setupForeground()
            for index in 0..<10 { _ = try store?.hero(index) }
            built = true; fitCamera(); applyLighting()
            let textures = litSprites.compactMap { $0.0.texture } + (0..<10).compactMap { try? store?.hero($0).texture }
            SKTexture.preload(textures) { [weak self] in self?.onReady?() }
        } catch { onError?(error.localizedDescription) }
    }
    override func didChangeSize(_ oldSize: CGSize) { if built { fitCamera() } }
    private func fitCamera() {
        let scale = geometry.fitScale(view: size) / zoom
        cameraNode.setScale(scale)
        positionForeground()
    }
    func setZoom(_ value: CGFloat) { zoom = min(2.4, max(1, value)); fitCamera() }
    func magnify(by factor: CGFloat) { setZoom(zoom * factor) }
    func pan(dx: CGFloat, dy: CGFloat) {
        follow = false
        cameraNode.position.x = min(1600, max(0, cameraNode.position.x - dx * cameraNode.xScale))
        cameraNode.position.y = min(1600, max(0, cameraNode.position.y + dy * cameraNode.yScale))
        updateForeground()
    }
    func overview() { follow = false; zoom = 1; cameraNode.position=CGPoint(x:800,y:768);fitCamera() }
    func followHero(_ value: Bool) { follow = value; if value, let hero { cameraNode.position = hero.position }; updateForeground() }
    func setReducedMotion(_ value: Bool) {
        reducedMotion = value
        if value, let event = active { finish(event) }
        if built { applyLighting() }
    }
    func setLighting(_ mode: LightingMode, strength: CGFloat) {
        self.mode = mode; self.strength = min(1, max(0, strength)); if built { applyLighting() }
    }
    func setEffects(_ value: HD2DSettings) { effects = value.bounded(); if built { applyLighting() } }
    private func applyLighting() {
        let enabled = mode != .flat
        sunLayer.isHidden = !enabled
        sunLayer.alpha = strength
        renderer?.update(settings: effects, mode: mode, strength: strength, reducedMotion: reducedMotion)
        for (sprite, id) in litSprites {
            renderer?.apply(to: sprite, id: id)
            if !enabled { sprite.shader = nil }
        }
        for shadow in shadowNodes {
            shadow.isHidden = !effects.directionalLight
            shadow.alpha=CGFloat(effects.shadowStrength)*(shadow.userData?["opacity-base"] as? CGFloat ?? 0.23)
        }
        for node in contactNodes { node.isHidden = !effects.contactShadows }
        heroShadow?.isHidden = !enabled || !effects.directionalLight
        heroShadow?.alpha = CGFloat(effects.shadowStrength)*0.20
        heroContact?.isHidden = !effects.contactShadows
        atmosphereLayer.isHidden = !enabled || !effects.bloom
        atmosphereLayer.alpha = CGFloat(effects.bloomStrength)*strength
        for node in bloomNodes { node.isHidden = !enabled || !effects.bloom; node.alpha = CGFloat(effects.bloomStrength)*strength*0.24 }
        for (node, inCommunity) in communityNodes {
            node.isHidden = enabled && effects.vegetation && !inCommunity
            for effect in groundEffectsByEntity[ObjectIdentifier(node)] ?? [] {
                if node.isHidden { effect.isHidden = true }
                else if let shadow = effect as? SKSpriteNode, shadowNodes.contains(where: { $0 === shadow }) { effect.isHidden = !effects.directionalLight }
                else if let contact = effect as? SKSpriteNode, contactNodes.contains(where: { $0 === contact }) { effect.isHidden = !effects.contactShadows }
                else { effect.isHidden = !effects.bloom }
            }
        }
        // Lighting mode and blur toggles never remove the foreground geometry.
        foreground.isHidden = !effects.foregroundTrees
        for effect in foregroundEffects {
            effect.shouldEnableEffects = effects.edgeDepth && effects.depthRadius > 0
            effect.filter?.setValue(effects.depthRadius,forKey:kCIInputRadiusKey)
        }
        for node in terrainNodes {
            node.isHidden = !effects.terrain
            for effect in groundEffectsByEntity[ObjectIdentifier(node)] ?? [] { effect.isHidden = !effects.terrain || !effects.contactShadows }
        }
        updateWind(); updateForeground()
    }
    private func updateWind() {
        let moving = mode != .flat && effects.environmentalMotion && !reducedMotion
        for (index, node) in windNodes.enumerated() {
            node.removeAction(forKey: "leaf-wind"); node.zRotation = 0
            guard moving else { continue }
            let amount = CGFloat(effects.motionStrength)*0.004
            let right = SKAction.rotate(toAngle: amount, duration: 2.4), left = SKAction.rotate(toAngle: -amount, duration: 2.4)
            right.timingMode = .easeInEaseOut; left.timingMode = .easeInEaseOut
            let sway = SKAction.sequence([right, left])
            node.run(.sequence([.wait(forDuration: Double(index%7)*0.3), .repeatForever(sway)]), withKey: "leaf-wind")
        }
    }
    private func populate() throws {
        guard let store else { throw AssetError.missing("store") }
        // Eight reusable native materials; finer terrain pixel pitch and 16-point overlap.
        for row in -6...11 { for column in -6...11 {
            let key = abs(row * 31 + column * 17 + Int(graph.decorationSeed)) % 8
            let sprite = SKSpriteNode(texture: try store.groundVariant(key))
            sprite.anchorPoint = .zero; sprite.size = CGSize(width: 256, height: 256)
            sprite.position = CGPoint(x: column * 240, y: row * 240); sprite.zPosition = 0
            world.addChild(sprite); litSprites.append((sprite, "ground-\(key)"))
        } }
        let positions = points
        let roads: [RoadCurve] = graph.publicEdges.compactMap { edge in
            guard let a = positions[edge.a], let b = positions[edge.b] else { return nil }
            return RoadCurve(a: a, b: b, bend: edge.a == 1 ? -28 : 20)
        }
        for (index, curve) in roads.enumerated() {
            let (texture, bounds) = try store.roadTexture(curve: curve)
            let road = SKSpriteNode(texture: texture); road.size = bounds.size; road.anchorPoint = .zero
            road.position = bounds.origin; road.zPosition = 4; world.addChild(road); litSprites.append((road, "road-\(index)"))
        }
        protectedRoads = roads
        let field = MeadowField(seed:graph.decorationSeed,roads:roads,landmarks:Array(positions.values))
        var occupied:[CGPoint]=[]
        for candidate in SceneryRecipe(field:field).candidates() {
            let point=candidate.point,width=candidate.width,asset=try store.module(candidate.id)
            let kind=SurfaceKind.asset(asset.id),low=kind == .lowPlant
            let scale=width/CGFloat(asset.image.width)
            let rect=CGRect(x:point.x-asset.anchorTop.x*scale,
                            y:point.y-(CGFloat(asset.image.height)-asset.anchorTop.y)*scale,
                            width:width,height:CGFloat(asset.image.height)*scale).insetBy(dx:-10,dy:-12)
            if positions.values.contains(where:{ hypot($0.x-point.x,$0.y-point.y)<(low ? 38:74) || rect.contains($0) }) { continue }
            if roads.contains(where:{ curve in (0...60).contains { rect.contains(curve.point(Double($0)/60)) } }) { continue }
            if !low && !candidate.terrain && occupied.contains(where:{ hypot($0.x-point.x,$0.y-point.y)<43 }) { continue }
            let entity=try addEntity(asset,foot:point,width:width,casts:kind == .foliage || kind == .rock)
            if candidate.terrain { entity.zPosition=3;terrainNodes.append(entity) }
            else if !low { occupied.append(point) }
            communityNodes.append((entity,low ? field.community(point)>0.45:true))
        }
        for node in graph.nodes {
            guard let foot = positions[node.id] else { continue }
            let marker = SKShapeNode(circleOfRadius: node.revealed ? 13 : 18)
            marker.position = foot; marker.zPosition = 2800; marker.lineWidth = 2
            marker.fillColor = node.revealed ? SKColor(red: 0.76, green: 0.64, blue: 0.33, alpha: 1) : SKColor(red: 0.18, green: 0.32, blue: 0.38, alpha: 1)
            marker.strokeColor=SKColor(red:0.78,green:0.68,blue:0.44,alpha:0.92); world.addChild(marker)
            if !node.revealed {
                let unknown = SKLabelNode(text: "?"); unknown.fontName = "HelveticaNeue-Medium"; unknown.fontSize = 20
                unknown.verticalAlignmentMode = .center; marker.addChild(unknown)
                continue // No hidden visual lookup or shadow allocation.
            }
            guard let id = node.visual else { continue }
            let asset = try store.module(id), width: CGFloat = node.id == 1 ? 220 : 148
            let candidates = [CGPoint(x: foot.x, y: foot.y+48), CGPoint(x: foot.x-100, y: foot.y+48), CGPoint(x: foot.x+100, y: foot.y+48)]
            let scale = width / CGFloat(asset.image.width)
            let location = candidates.first { candidate in
                let rect = CGRect(x: candidate.x-asset.anchorTop.x*scale, y: candidate.y-(CGFloat(asset.image.height)-asset.anchorTop.y)*scale,
                                  width: width, height: CGFloat(asset.image.height)*scale).insetBy(dx: -10, dy: -10)
                return !roads.contains { curve in (0...80).contains { rect.contains(curve.point(Double($0)/80)) } }
            } ?? CGPoint(x: foot.x-125, y: foot.y+48)
            let clearing=SKSpriteNode(texture:try store.campClearing())
            clearing.position=location;clearing.size=CGSize(width:node.id==1 ? 330:210,height:node.id==1 ? 170:115)
            clearing.zPosition=2;clearing.alpha=node.id==1 ? 0.78:0.50;world.addChild(clearing)
            litSprites.append((clearing,"road-clearing"))
            // Original graph keys resolve to new neutral-lit modules, without painted cast shadows.
            try addEntity(asset,foot:location,width:width,casts:true)
        }
        if let p2 = positions[3] { try addActor(try store.referenceActor("ranger"), id: "P2", foot: p2) }
        if let p3 = positions[2] { try addActor(try store.referenceActor("spellblade"), id: "P3", foot: CGPoint(x: p3.x+34, y: p3.y-18)) }
        let first = try store.hero(7)
        let player = SKSpriteNode(texture: first.texture); apply(first, to: player, scale: first.actorScale)
        player.position = positions[1] ?? .zero; world.addChild(player); hero = player
        litSprites.append((player, "hero-7"))
        let label = makeLabel("P1"); world.addChild(label); heroLabel = label
        let ring=SKShapeNode(ellipseOf:CGSize(width:34,height:12))
        ring.fillColor = .clear;ring.strokeColor=SKColor(red:0.93,green:0.79,blue:0.42,alpha:0.65)
        ring.lineWidth=1.4;ring.zPosition=10;world.addChild(ring);focusRing=ring
        let shadow = makeShadow(first, foot: player.position, scale: first.actorScale, opacity: 0.14)
        sunLayer.addChild(shadow); heroShadow = shadow
        heroContact = addContact(foot: player.position, width: 27, opacity: 0.46)
        updateHeroDepth()
    }
    private func apply(_ asset: SpriteAsset, to sprite: SKSpriteNode, scale: CGFloat) {
        sprite.texture = asset.texture; sprite.anchorPoint = asset.anchor
        sprite.size = CGSize(width: CGFloat(asset.image.width)*scale, height: CGFloat(asset.image.height)*scale)
    }
    @discardableResult private func addEntity(_ asset: SpriteAsset, foot: CGPoint, width: CGFloat, casts: Bool) throws -> SKSpriteNode {
        let scale = width / CGFloat(asset.image.width), sprite = SKSpriteNode(texture: asset.texture)
        apply(asset, to: sprite, scale: scale); sprite.position = foot; sprite.zPosition = depth(foot)
        world.addChild(sprite); litSprites.append((sprite, asset.id))
        let kind = SurfaceKind.asset(asset.id)
        var groundEffects: [SKNode] = []
        groundEffects.append(addContact(foot: foot, width: width*(kind == .foliage ? 0.30 : (kind == .actor ? 0.55:0.68)),opacity:kind == .foliage ? 0.38:0.30))
        if kind == .foliage { windNodes.append(sprite) }
        if casts {
            let shadow = makeShadow(asset, foot: foot, scale: scale, opacity: kind == .foliage ? 0.15:0.12)
            shadow.userData=["opacity-base":kind == .foliage ? CGFloat(0.25):CGFloat(0.20)]
            sunLayer.addChild(shadow); shadowNodes.append(shadow); groundEffects.append(shadow)
            if kind == .foliage {
                groundEffects.append(addContact(foot: CGPoint(x: foot.x+width*0.18, y: foot.y-width*0.13), width: width*0.85, opacity: 0.10))
            }
            if kind != .actor {
                // Restrained, local diffuse highlights under the objects, never over the actors.
                let glow = SKSpriteNode(texture: glowTexture)
                glow.size = CGSize(width: width*1.1, height: width*0.6)
                glow.position = CGPoint(x: foot.x-width*0.35, y: foot.y+width*0.25)
                glow.alpha = 0.20; glow.blendMode = .add; atmosphereLayer.addChild(glow); groundEffects.append(glow)
                if let highlight = store?.highlightBloom(asset) {
                    let bloom = SKSpriteNode(texture: highlight); bloom.anchorPoint = sprite.anchorPoint; bloom.size = sprite.size
                    bloom.blendMode = .add; bloom.zPosition = 0.1; sprite.addChild(bloom); bloomNodes.append(bloom)
                }
            }
        }
        groundEffectsByEntity[ObjectIdentifier(sprite)] = groundEffects
        return sprite
    }
    @discardableResult private func addContact(foot: CGPoint, width: CGFloat, opacity: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(texture: contactTexture)
        node.size = CGSize(width: width, height: width*0.35); node.position = foot; node.alpha = opacity
        sunLayer.addChild(node); contactNodes.append(node); return node
    }
    private func makeShadow(_ asset: SpriteAsset, foot: CGPoint, scale: CGFloat, opacity: CGFloat) -> SKSpriteNode {
        let source = store!.projectedShadow(asset)
        let sprite = SKSpriteNode(texture: source.texture); sprite.size = CGSize(width: source.size.width*scale, height: source.size.height*scale)
        sprite.anchorPoint = source.anchor; sprite.position = foot; sprite.alpha = opacity
        return sprite
    }
    private func addActor(_ asset: SpriteAsset, id: String, foot: CGPoint) throws {
        let width=CGFloat(asset.image.width)*asset.actorScale
        try addEntity(asset,foot:foot,width:width,casts:true)
        let label = makeLabel(id); label.position = CGPoint(x: foot.x, y: foot.y-18); world.addChild(label)
    }
    private func makeLabel(_ text: String) -> SKLabelNode {
        let label = SKLabelNode(text: text); label.fontName = "AvenirNext-DemiBold"; label.fontSize = 14
        label.fontColor = .white; label.zPosition = 3000
        let plate = SKShapeNode(rectOf: CGSize(width: 30, height: 22), cornerRadius: 5)
        plate.fillColor=SKColor(red:0.12,green:0.20,blue:0.20,alpha:0.88)
        plate.strokeColor=SKColor(red:0.73,green:0.64,blue:0.40,alpha:0.70);plate.lineWidth=0.8
        plate.position.y = 6; plate.zPosition = -1; label.addChild(plate); return label
    }
    private func depth(_ foot: CGPoint) -> CGFloat { 2500 - foot.y }
    private func updateHeroDepth() {
        guard let hero else { return }; hero.zPosition = depth(hero.position)
        hero.setValue(SKAttributeValue(float: Float(hero.position.y)), forAttribute: "a_depth")
        heroShadow?.position = hero.position; heroContact?.position = hero.position;focusRing?.position=hero.position; heroLabel?.position = CGPoint(x: hero.position.x, y: hero.position.y-18)
        if follow { cameraNode.position = hero.position }; updateForeground()
    }
    private func setupForeground() throws {
        guard let store else { return }
        // Camera children have stable viewport dimensions. Only the tree receives edge blur.
        foreground.zPosition=600;cameraNode.addChild(foreground)
        for (index,id) in ["fir_single","oak_single"].enumerated() {
            let asset=try store.module(id),tree=SKSpriteNode(texture:asset.texture),effect=SKEffectNode()
            effect.filter=CIFilter(name:"CIGaussianBlur",parameters:[kCIInputRadiusKey:effects.depthRadius])
            effect.shouldRasterize=false;effect.name="corner-\(index)";foreground.addChild(effect)
            apply(asset,to:tree,scale:ForegroundGeometry.height(view:size)/CGFloat(asset.image.height))
            tree.name="front-\(index)";tree.alpha=ForegroundGeometry.maximumOpacity
            effect.addChild(tree);foregroundEffects.append(effect);foregroundSprites.append(tree)
            // Same material shader as the meadow trees. No full-grove yellow sticker.
            litSprites.append((tree,id));windNodes.append(tree)
        }
        positionForeground()
    }
    private func positionForeground() {
        for (index,tree) in foregroundSprites.enumerated() {
            let height=ForegroundGeometry.height(view:size),ratio=tree.size.width/max(1,tree.size.height)
            tree.size=CGSize(width:height*ratio,height:height)
            foregroundEffects[index].position=ForegroundGeometry.foot(index:index,view:size)
        }
        updateForeground()
    }
    private func updateForeground(delta:TimeInterval=0) {
        let scale=cameraNode.xScale,position=cameraNode.position
        var protected=points.values.map { ForegroundGeometry.screen($0,camera:position,scale:scale) }
        if let hero { protected.append(ForegroundGeometry.screen(hero.position,camera:position,scale:scale)) }
        for road in protectedRoads { for t in 0...30 { protected.append(ForegroundGeometry.screen(road.point(Double(t)/30),camera:position,scale:scale)) } }
        for (index,tree) in foregroundSprites.enumerated() {
            let foot=foregroundEffects[index].position
            let rect=CGRect(x:foot.x-tree.size.width*tree.anchorPoint.x,
                            y:foot.y-tree.size.height*tree.anchorPoint.y,
                            width:tree.size.width,height:tree.size.height)
            let target=ForegroundGeometry.opacity(rect:rect,protected:protected)
            // No isHidden toggle when zooming/panning. Even overlap retains a soft frame.
            if delta>0 { tree.alpha += (target-tree.alpha)*min(1,CGFloat(delta)*10) }
            tree.setValue(SKAttributeValue(float:0),forAttribute:"a_depth")
        }
    }
    func playFixture() {
        guard built, active == nil, let a = points[1], let b = points[2] else { return }
        // A new explicitly requested display fixture, not a submitted game command.
        hero?.position = a; lastFrame = -1
        let event = DemoPresentation(id: UUID().uuidString, start: Date(), duration: 1.8, curve: RoadCurve(a: a, b: b, bend: -28))
        present(event)
    }
    func present(_ event: DemoPresentation) {
        guard gate.accept(event, now: Date()) else { return }
        if reducedMotion { finish(event) } else { active = event }
    }
    // Call this on archive restoration before accepting display events; no history replay.
    func suppressRestoredEvents(_ ids: [String]) { gate.suppress(ids); active = nil }
    override func update(_ currentTime: TimeInterval) {
        let delta=lastTick.map { min(0.1,max(0,currentTime-$0)) } ?? 1.0/30
        lastTick=currentTime;updateForeground(delta:delta)
        guard let event = active, Date() >= event.start else { return }
        let age = max(0, Date().timeIntervalSince(event.start)), progress = min(1, age / event.duration)
        hero?.position = event.curve.point(progress)
        let frame = Int(age / 0.15) % 4
        if frame != lastFrame { updateHeroFrame(frame); lastFrame = frame }
        updateHeroDepth()
        if progress >= 1 { finish(event) }
    }
    private func updateHeroFrame(_ index: Int) {
        guard let store, let hero, let asset = try? store.hero(index) else { return }
        heroFrameIndex = index; apply(asset, to: hero, scale: asset.actorScale)
        renderer?.apply(to: hero, id: asset.id)
        if mode == .flat { hero.shader = nil }
        heroShadow?.removeFromParent()
        let shadow = makeShadow(asset, foot: hero.position, scale: asset.actorScale, opacity: 0.14)
        shadow.isHidden = mode == .flat || !effects.directionalLight
        shadow.alpha = CGFloat(effects.shadowStrength)*0.20
        sunLayer.addChild(shadow); heroShadow = shadow
    }
    private func finish(_ event: DemoPresentation) {
        hero?.position = event.curve.b; active = nil; updateHeroFrame(7); updateHeroDepth()
        onArrival?()
    }
}
