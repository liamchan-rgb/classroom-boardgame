import SpriteKit
import Darwin
import ClassroomGameCore
import MeadowWorldSupport
import MeadowClassroomSupport

final class GameScene: SKScene {
    var classroomAdvanceTravel:((Double)throws->[OperationReceipt])?
    var selectingCampaignNode=false
    var onCampaignNodeSelected:((Int)->Void)?
    var onCampaignInteractionRequested:((Int)->Void)?
    var onCampaignEncounterSelected:((Int?)->Void)?
    private var lastCampaignUIUpdate:TimeInterval=0
    var campaign:MeadowCampaignSession?
    var onCampaignChanged:(()->Void)?
    var onCampaignError:((String)->Void)?
    var selectedCampaignPlayerID:String {guard let campaign else{return "p1"};return campaign.selectedPlayerID}
    var campaignCamera:MeadowCampaignCamera { .init(x:Double(cameraCenter.x),y:Double(cameraCenter.y),zoom:Double(zoom)) }
    private func campaignSiteSymbol(_ id:Int?)->String? {
        guard let id,let campaign,let kind=campaign.siteKind(node:id) else{return nil}
        if campaign.engine.state.map.nodes.first(where:{$0.id==id})?.siteResolved==true{return "✓"}
        return kind == .shop ? "商":kind == .spring ? "泉":"事"
    }
    func refreshCampaign() {
        guard let campaign,world != nil else{return}
        refreshProfileFrames()
        simulation.selected=campaign.playerIDs.firstIndex(of:campaign.selectedPlayerID) ?? 0
        for (index,d) in world.definition.discoveries.enumerated() {
            guard let id=d.nodeID,let node=campaign.engine.state.map.nodes.first(where:{$0.id==id}) else{continue}
            let cleared=node.rewardCompleted || ((node.kind == .combat || node.kind == .boss) && !campaign.engine.state.units.values.contains{$0.kind == .monster && $0.nodeID==id && $0.isAlive})
            discoveryNodes[index].children.compactMap{$0 as? SKLabelNode}.first?.text=cleared ? "✓":campaignSiteSymbol(id) ?? ["combat":"战","boss":"首","reward":"奖","empty":"空"][node.kind.rawValue]
        }
        refreshCampaignRoute()
        updateActors(before:nil)
    }

    private var world: LivingWorld!
    private var simulation: JourneySimulation!
    private var actors: [SKSpriteNode] = []
    private var actorRoots: [SKNode] = []
    private var actorLabels: [SKNode] = []
    private var frames: [[[SKTexture]]] = []
    private var profileFrames:[String:[[SKTexture]]]=[:]
    private var profileLocomotion=Array(repeating:AuthoredLocomotion(plan:HeroFrames.locomotionPlan),count:7)
    /// 任意一位旅人（不管有没有自定义外观）
    private func campaignUnit(_ index:Int)->GameUnit? {
        guard let campaign,campaign.playerIDs.indices.contains(index) else{return nil};return campaign.engine.state.units[campaign.playerIDs[index]]
    }
    private func profileUnit(_ index:Int)->GameUnit? {
        guard let campaign,campaign.playerIDs.indices.contains(index),let unit=campaign.engine.state.units[campaign.playerIDs[index]],unit.appearance != nil else{return nil};return unit
    }
    func refreshProfileFrames(){
        guard let campaign,world != nil else{return}
        var active=Set<String>()
        for (index,id) in campaign.playerIDs.enumerated() {
            guard let unit=campaign.engine.state.units[id],frames.indices.contains(index) else{continue}
            guard let look=unit.appearance else{
                // 像素人物：没有自定义外观的旅人也按身上的武器、护甲画（用预设旅人的样子）
                guard PixelHeroAtlas.enabled,id != "p1" else{continue}
                let key="preset\(index%3)-\(unit.equipment.weapon ?? "none")-\(unit.equipment.armor ?? "none")";active.insert(key)
                if profileFrames[key]==nil{profileFrames[key]=HeroFrames.load(index%3+1,weaponID:unit.equipment.weapon,armorID:unit.equipment.armor)}
                frames[index]=profileFrames[key]!
                continue
            }
            let ai=HeroFrames.appearanceIDs.firstIndex(of:look.body) ?? 0,armor=look.armor(worn:unit.equipment.armor)
            let key="\(look.visualKey)-\(unit.equipment.weapon ?? "none")-\(armor ?? "none")";active.insert(key)
            if profileFrames[key]==nil{profileFrames[key]=HeroFrames.load(1,appearanceIndex:ai,weaponID:unit.equipment.weapon,armorID:armor,hair:look.hair,face:look.face)}
            frames[index]=profileFrames[key]!
        }
        profileFrames=profileFrames.filter{active.contains($0.key)}
    }
    private var layeredP1Frames: [SKTexture]?
    private(set) var layeredPreview = false
    private var walks = [WalkCycle(), WalkCycle(), WalkCycle()]
    private var p1Locomotion = AuthoredLocomotion(plan: HeroFrames.locomotionPlan, timing: HeroFrames.p1GaitTiming)
    private var breathing = [HeroBreathing](repeating: HeroBreathing(), count: 3)
    private(set) var p1AppearanceIndex = 0
    private var p1AppearanceFrames: [String: [[SKTexture]]] = [:]
    private(set) var p1WeaponID:String?="trainingSword"
    private(set) var p1ArmorID:String?
    private(set) var gaitTest: GaitTest?
    private var gaitHiddenNodes: [(SKNode, Bool)] = []
    private var gaitMapCamera: (CGPoint, CGFloat)?
    private var battlePreviewCamera: (CGPoint, CGFloat)?
    private var gaitSunWasHidden = false
    private var discoveryNodes: [SKNode] = []
    private var discovered = Set<Int>()
    private var pendingDiscovery: Int?
    private var lastTime: TimeInterval = 0
    private var environmentTime: TimeInterval = 0
    private var frameWindowStart: TimeInterval = 0
    private var frameCounter = 0
    private var measuredFPS: Double = 0
    private var metricSamples: [[String: Any]] = []
    private var baseScale: CGFloat = 1
    private var referenceViewportSize: CGSize?
    private var cameraCenter = CGPoint(x: 640, y: 360)
    private var demoPhase = 0
    private(set) var zoom: CGFloat = 1
    var isRunning: Bool { if let campaign{return campaign.isMoving};return gaitTest.map { !$0.paused } ?? simulation?.isPlaying ?? false }
    var shadowReady = false
    var shadowFrames = 0
    var shadowMapSize = 0
    var gpuFallbackCount = 0
    var groundDrawableScale: Double = 1
    var startupMetrics: [String: Double] = [:]
    private(set) var setupTimings: [String: Double] = [:]
    var onForegroundReady: (() -> Void)?
    private var initialFrames = 0
    var onWorldReady: ((LivingWorld) -> Void)?
    var onPlaybackChanged: ((Bool) -> Void)?
    var onSelectionChanged: ((String) -> Void)?
    var onDiagnostics: ((String) -> Void)?
    var onMetrics: ((String) -> Void)?
    var onDiscovery: ((String) -> Void)?
    private let selectionRing = SKShapeNode(ellipseOf: CGSize(width: 30, height: 12))
    private let destinationRing = SKShapeNode(ellipseOf: CGSize(width: 25, height: 10))
    private let campaignRoute = SKShapeNode()

    private func refreshCampaignRoute() {
        guard world != nil else{return}
        guard let route=campaign?.routeReadout,let end=route.points.last,!route.arrived else{
            campaignRoute.isHidden=true;destinationRing.isHidden=true;return
        }
        let path=CGMutablePath()
        for (index,p) in route.points.enumerated() {
            let point=LivingWorld.position(CGPoint(x:p.x,y:p.y))
            if index==0{path.move(to:point)}else{path.addLine(to:point)}
        }
        campaignRoute.path=path;campaignRoute.isHidden=false
        destinationRing.position=LivingWorld.position(CGPoint(x:end.x,y:end.y));destinationRing.isHidden=false
    }
    func travelCampaign(to node:Int) {
        guard let campaign else{return}
        do {
            let plan=try campaign.beginTravel(to:node,actor:selectedCampaignPlayerID)
            onCampaignEncounterSelected?(node);refreshCampaignRoute()
            onDiscovery?(plan.message);onPlaybackChanged?(true);onCampaignChanged?()
        }catch{onCampaignError?(error.localizedDescription)}
    }
    private let reviewMode = ProcessInfo.processInfo.arguments.contains("-visualReview")
    private let demoMode = ProcessInfo.processInfo.arguments.contains("-visualDemo")

    func prepare(_ prepared: PreparedMeadow, progress: @escaping (Double) -> Void, completion: @escaping () -> Void) {
        let began = ProcessInfo.processInfo.systemUptime
        let staged = LivingWorld(definition: prepared.definition, roadMask: prepared.roadMask,
            props: prepared.props, textures: prepared.textures, effects: prepared.effects,
            deferProps: true, renderTerrain: prepared.renderer == nil)
        setupTimings["worldInit"] = ProcessInfo.processInfo.systemUptime - began
        staged.populate(prepared.props, progress: progress) { [weak self] in
            let began = ProcessInfo.processInfo.systemUptime
            self?.installWorld(staged, heroes: prepared.heroes)
            self?.setupTimings["markersActorsReset"] = ProcessInfo.processInfo.systemUptime - began
            self?.setupTimings["propsBatchMax"] = staged.longestPopulateBatchSeconds
            completion()
        }
    }

    func refreshDiagnostics() { publishDiagnostics() }

    private func installWorld(_ prepared: LivingWorld, heroes: [[[SKTexture]]]? = nil) {
        world = prepared
        if let heroes { frames = heroes }
        addChild(world)
        simulation = JourneySimulation(network: world.network, spawn: world.definition.spawn?.point)
        buildMarkers(); buildActors(); reset()
    }

    override func didMove(to view: SKView) {
        activate(background: SKColor(red: 0.31, green: 0.38, blue: 0.15, alpha: 1))
    }

    func activateForMetalRenderer() { activate(background: .clear) }

    private func activate(background: SKColor) {
        backgroundColor = background
        if world == nil { installWorld(LivingWorld(definition: .load())) }
        layoutWorld()
        onWorldReady?(world)
        if ProcessInfo.processInfo.arguments.contains("-alignmentReview") {
            world.children.forEach { $0.isHidden = true }
            world.sunlightOverlay?.isHidden = true
            for point in [CGPoint(x: 540, y: 300), CGPoint(x: 740, y: 300), CGPoint(x: 640, y: 440)] {
                let marker = SKShapeNode(circleOfRadius: 3)
                marker.fillColor = .red; marker.strokeColor = .clear
                marker.position = LivingWorld.position(point); marker.zPosition = 100000
                world.addChild(marker)
            }
        }
        if demoMode && world.definition.startNodeID == nil { togglePlayback() }
    }

    private func buildMarkers() {
        let start = SKShapeNode(circleOfRadius: 10)
        start.position = LivingWorld.position(world.definition.landmarkBadgePoint(nodeID:world.definition.startNodeID) ?? world.definition.spawn?.point ?? CGPoint(x: 285, y: 442))
        start.fillColor = SKColor(red: 0.96, green: 0.85, blue: 0.52, alpha: 1)
        start.strokeColor = SKColor(red: 0.40, green: 0.24, blue: 0.11, alpha: 1)
        start.lineWidth = 2.5
        start.name = world.definition.startNodeID.map { "landmark-\($0)" }
        start.zPosition = world.definition.startNodeID == nil ? 65:22500
        if world.definition.startNodeID != nil {
            let text=SKLabelNode(fontNamed:"Georgia-Bold");text.text="起";text.fontSize=15
            text.fontColor = .black;text.verticalAlignmentMode = .center;start.addChild(text)
        }
        world.addChild(start)
        for (index, discovery) in world.definition.discoveries.enumerated() {
            let root = SKNode()
            root.position = LivingWorld.position(world.definition.landmarkBadgePoint(nodeID:discovery.nodeID) ?? (discovery.kind == nil ? CGPoint(x: discovery.x + 28, y: discovery.y - 40) : CGPoint(x:discovery.x,y:discovery.y-24)))
            root.zPosition = 22500
            root.name = "discovery-\(index)"
            let diamond = SKShapeNode(circleOfRadius: 13)
            diamond.fillColor = SKColor(red: 0.25, green: 0.27, blue: 0.23, alpha: 0.9)
            diamond.strokeColor = SKColor(red: 0.87, green: 0.73, blue: 0.46, alpha: 1)
            diamond.lineWidth = 1.5
            diamond.name = root.name
            root.addChild(diamond)
            let label = SKLabelNode(fontNamed: "Georgia-Bold")
            label.text = campaignSiteSymbol(discovery.nodeID) ?? ["combat":"战","boss":"首","reward":"奖","empty":"空"][discovery.kind ?? ""] ?? "?"
            label.fontSize = 20
            label.fontColor = SKColor(red: 1, green: 0.95, blue: 0.81, alpha: 1)
            label.verticalAlignmentMode = .center
            label.name = root.name
            root.addChild(label)
            world.addChild(root)
            discoveryNodes.append(root)
            let footprint = SKShapeNode(ellipseOf: CGSize(width: 18, height: 8))
            footprint.position = LivingWorld.position(CGPoint(x: discovery.x, y: discovery.y))
            footprint.fillColor = .clear
            footprint.strokeColor = SKColor(red: 0.87, green: 0.73, blue: 0.46, alpha: 0.55)
            footprint.lineWidth = 1
            footprint.zPosition = 65
            world.addChild(footprint)
        }
        selectionRing.fillColor = .clear
        selectionRing.strokeColor = SKColor(red: 1, green: 0.89, blue: 0.56, alpha: 0.9)
        selectionRing.lineWidth = 1.5
        selectionRing.zPosition = 66
        selectionRing.isHidden = true
        world.addChild(selectionRing)
        destinationRing.strokeColor = selectionRing.strokeColor
        destinationRing.fillColor = .clear
        destinationRing.lineWidth = 2
        destinationRing.zPosition = 67
        destinationRing.isHidden = true
        world.addChild(destinationRing)
        campaignRoute.strokeColor=SKColor(red:1,green:0.85,blue:0.42,alpha:0.65)
        campaignRoute.lineWidth=2;campaignRoute.glowWidth=0;campaignRoute.zPosition=64
        campaignRoute.isHidden=true;world.addChild(campaignRoute)
    }

    private func buildActors() {
        walks=Array(repeating:WalkCycle(),count:max(3,campaign?.playerIDs.count ?? 3))
        for index in 0..<(campaign?.playerIDs.count ?? 3) {
            if frames.count <= index { frames.append(HeroFrames.load(index%3 + 1)) }
            let directions = frames[index]
            let root = SKNode()
            root.name = "hero-\(index)"
            let sprite = SKSpriteNode(texture: directions[0][0], size: CGSize(width: 64, height: 64))
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.125)
            sprite.name = root.name
            sprite.zPosition = 1
            root.addChild(sprite)
            world.addChild(root)
            actorRoots.append(root)
            actors.append(sprite)
            let plate = SKShapeNode(rectOf: CGSize(width: 23, height: 14), cornerRadius: 3)
            plate.fillColor = .init(red: 0.18, green: 0.23, blue: 0.25, alpha: 0.9)
            plate.strokeColor = SKColor(red: 0.78, green: 0.70, blue: 0.46, alpha: 0.25)
            plate.lineWidth = 0.6
            plate.name = root.name
            let label = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
            label.text = "P\(index + 1)"
            label.fontSize = 10
            label.verticalAlignmentMode = .center
            label.fontColor = .white
            label.name = root.name
            plate.addChild(label)
            plate.zPosition = 23000
            world.addChild(plate)
            actorLabels.append(plate)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) { layoutWorld() }

    /// Keep map object sizes tied to the app canvas when its viewport narrows.
    /// The renderer continues to capture this scene's actual transform for terrain and shadows.
    func resizeMapViewport(to viewportSize: CGSize, referenceSize: CGSize) {
        guard size != viewportSize || referenceViewportSize != referenceSize else { return }
        referenceViewportSize = referenceSize
        if size != viewportSize { size = viewportSize }
        else { layoutWorld() }
        publishDiagnostics()
    }

    private func layoutWorld() {
        guard world != nil, size.width > 0, size.height > 0 else { return }
        if gaitTest != nil {
            let scale = max(0.1, min(size.width / 470, (size.height - 220) / 270))
            world.setScale(scale)
            world.position = CGPoint(x: size.width / 2 - 640 * scale, y: size.height / 2 + 400 * scale)
            world.attachSunlight(to: self)
            return
        }
        let bounds = world.worldBounds
        if battlePreviewCamera != nil {
            // Crop a useful map window instead of shrinking the whole map into it.
            let reference = referenceViewportSize ?? size
            baseScale = max(min(reference.width / 1280, reference.height / (campaign == nil ? (world.definition.mapHeight ?? 720):720)),
                            max(size.width / bounds.width, size.height / bounds.height))
        } else {
            baseScale = min(size.width / 1280, size.height / (campaign == nil ? (world.definition.mapHeight ?? 720):720))
        }
        let scale = baseScale * zoom
        let halfWidth = size.width / scale / 2
        let halfHeight = size.height / scale / 2
        func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat, fallback: CGFloat) -> CGFloat {
            low <= high ? min(high, max(low, value)) : fallback
        }
        cameraCenter.x = clamp(cameraCenter.x, low: bounds.minX + halfWidth,
                               high: bounds.maxX - halfWidth, fallback: bounds.midX)
        cameraCenter.y = clamp(cameraCenter.y, low: bounds.minY + halfHeight,
                               high: bounds.maxY - halfHeight, fallback: bounds.midY)
        world.setScale(scale)
        world.position = CGPoint(x: size.width / 2 - cameraCenter.x * scale,
                                 y: size.height / 2 + cameraCenter.y * scale)
        world.attachSunlight(to: self)
    }

    func setZoom(_ value: CGFloat, anchorInView: CGPoint? = nil) {
        guard world != nil, gaitTest == nil else { return }
        let anchor = anchorInView.map { CGPoint(x: $0.x, y: size.height - $0.y) }
            ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let previous = world.convert(anchor, from: self)
        zoom = min(1.8, max(1, value))
        let scale = baseScale * zoom
        cameraCenter = CGPoint(x: previous.x - (anchor.x - size.width / 2) / scale,
                               y: -previous.y + (anchor.y - size.height / 2) / scale)
        layoutWorld()
        publishDiagnostics()
    }

    /// Focus the selected traveller without changing the map's object scale.
    /// The original zoom and camera center are restored when the pane closes.
    func beginBattlePreviewCamera() {
        guard world != nil, gaitTest == nil, battlePreviewCamera == nil else { return }
        battlePreviewCamera = (cameraCenter, zoom)
        cameraCenter = actorPoint(simulation.selected)
        layoutWorld()
        publishDiagnostics()
    }

    func endBattlePreviewCamera() {
        guard let saved = battlePreviewCamera else { return }
        cameraCenter = saved.0
        zoom = saved.1
        battlePreviewCamera = nil
        layoutWorld()
        publishDiagnostics()
    }

    func panBy(_ translation: CGPoint) {
        guard world != nil, gaitTest == nil else { return }
        let scale = baseScale * zoom
        cameraCenter.x -= translation.x / scale
        cameraCenter.y -= translation.y / scale
        layoutWorld()
        publishDiagnostics()
    }

    func togglePlayback() {
        if gaitTest != nil { gaitTest?.paused.toggle(); return }
        simulation.togglePlayback()
        onPlaybackChanged?(simulation.isPlaying)
        publishDiagnostics()
    }

    func toggleGaitTest() {
        guard world != nil, simulation != nil else { return }
        if gaitTest == nil {
            gaitMapCamera = (cameraCenter, zoom)
            gaitTest = GaitTest()
            gaitHiddenNodes = world.children.filter { node in
                !actorRoots.contains(where: { $0 === node }) && !actorLabels.contains(where: { $0 === node })
            }.map { ($0, $0.isHidden) }
            for (node, _) in gaitHiddenNodes { node.isHidden = true }
            gaitSunWasHidden = world.sunlightOverlay?.isHidden ?? false
            world.sunlightOverlay?.isHidden = true
        } else {
            layeredPreview = false
            gaitTest = nil
            for (node, hidden) in gaitHiddenNodes { node.isHidden = hidden }
            gaitHiddenNodes.removeAll()
            world.sunlightOverlay?.isHidden = gaitSunWasHidden
            if let saved = gaitMapCamera { cameraCenter = saved.0; zoom = saved.1 }
            gaitMapCamera = nil
        }
        layoutWorld(); updateActors(before: nil)
        onPlaybackChanged?(isRunning)
        publishDiagnostics()
    }

    func setGaitDirection(_ direction: Int) {
        guard gaitTest != nil else { return }
        guard !layeredPreview || direction == 0 else { return }
        gaitTest?.select(direction); updateActors(before: nil); publishDiagnostics()
    }

    func toggleLayeredPreview() {
        guard gaitTest != nil, HeroFrames.layeredPrototypeAvailable else { return }
        if !layeredPreview {
            if layeredP1Frames == nil { layeredP1Frames = HeroFrames.loadLayeredP1BlueVariant() }
            layeredPreview = true
            gaitTest?.select(0)
        } else {
            layeredPreview = false
        }
        updateActors(before: nil)
        publishDiagnostics()
    }
    func toggleGaitPause() { gaitTest?.paused.toggle(); publishDiagnostics() }
    func selectP1Appearance(_ index:Int) {
        guard HeroFrames.appearanceTitles.indices.contains(index) else { return }
        p1AppearanceIndex=index;refreshP1EquipmentFrames()
    }
    func selectP1Loadout(appearance:Int,weapon:String?,armor:String?) {
        guard HeroFrames.appearanceIDs.indices.contains(appearance) else { return }
        p1AppearanceIndex=appearance;p1WeaponID=weapon;p1ArmorID=armor
        if world != nil { refreshP1EquipmentFrames() }
    }
    func selectP1Armor(_ id:String?) { p1ArmorID=id;refreshP1EquipmentFrames() }
    func selectP1Weapon(_ id:String?) { p1WeaponID=id;refreshP1EquipmentFrames() }
    private func refreshP1EquipmentFrames() {
        let key="\(p1AppearanceIndex)-\(p1WeaponID ?? "none")-\(p1ArmorID ?? "none")"
        if p1AppearanceFrames[key]==nil { p1AppearanceFrames[key]=HeroFrames.load(1,appearanceIndex:p1AppearanceIndex,weaponID:p1WeaponID,armorID:p1ArmorID) }
        frames[0]=p1AppearanceFrames[key]!
        p1AppearanceFrames=p1AppearanceFrames.filter { $0.key==key }
        // Same route, facing, distance phase and sole markers; only the texture changes.
        updateActors(before:nil);publishDiagnostics()
    }
    func toggleGaitSlow() { gaitTest?.slow.toggle(); publishDiagnostics() }
    func stepGait() {
        guard gaitTest != nil else { return }
        gaitTest?.step(); updateActors(before: nil); publishDiagnostics()
    }

    func reset() {
        guard world != nil else { return }
        if let gaitTest { setGaitDirection(layeredPreview ? 0 : gaitTest.facing); return }
        simulation.reset()
        if let campaign {
            simulation.selected=campaign.playerIDs.firstIndex(of:campaign.selectedPlayerID) ?? 0
            cameraCenter=CGPoint(x:campaign.snapshot.camera?.x ?? campaign.position(of:"p1").x,y:campaign.snapshot.camera?.y ?? campaign.position(of:"p1").y)
            zoom=CGFloat(campaign.snapshot.camera?.zoom ?? 1);walks=Array(repeating:WalkCycle(),count:max(3,campaign.playerIDs.count));p1Locomotion.reset()
            layoutWorld();refreshCampaign();onPlaybackChanged?(campaign.isMoving);return
        }
        pendingDiscovery = nil
        discovered.removeAll()
        for (index,node) in discoveryNodes.enumerated() {
            node.alpha = 1
            let kind=world.definition.discoveries[index].kind ?? ""
            node.children.compactMap { $0 as? SKLabelNode }.first?.text = ["combat":"战","boss":"首","reward":"奖","empty":"空"][kind] ?? "?"
            node.children.compactMap { $0 as? SKShapeNode }.first?.fillColor = .init(red: 0.25, green: 0.27, blue: 0.23, alpha: 0.9)
        }
        selectionRing.isHidden = true
        destinationRing.isHidden = true
        walks = [WalkCycle(), WalkCycle(), WalkCycle()]
        p1Locomotion.reset()
        cameraCenter = CGPoint(x: 640, y: (world.definition.mapHeight ?? 720)/2)
        zoom = 1
        layoutWorld()
        updateActors(before: nil)
        onPlaybackChanged?(false)
        onSelectionChanged?("P1")
        publishDiagnostics()
    }

    override func update(_ currentTime: TimeInterval) {
        guard world != nil else { return }
        defer { lastTime = currentTime }
        guard lastTime > 0 else {
            frameWindowStart = currentTime
            return
        }
        let rawDelta = max(0, currentTime - lastTime)
        let delta = min(rawDelta, 0.1)
        environmentTime += delta
        world.update(time: environmentTime)
        if gaitTest != nil {
            gaitTest?.advance(delta)
            updateActors(before: nil)
        } else if let campaign {
            let previous=actors.indices.map{actorPoint($0)},wasMoving=campaign.isMoving
            let p1Requested=campaign.isMoving && campaign.travel?.actors.contains("p1")==true
            if campaign.isMoving && (!p1Requested || p1Locomotion.allowsTravel(requested:true)) {
                let h=campaign.heading,projection=WalkCycle.projectedScale(dx:CGFloat(h.x),dy:CGFloat(h.y))
                let speed=(campaign.travel?.actors.compactMap{campaign.playerIDs.firstIndex(of:$0)}.map{JourneySimulation.speed(for:$0)}.min()) ?? JourneySimulation.speed(for:0)
                do {
                    let amount=delta*Double(speed*projection)
                    let receipts=try classroomAdvanceTravel?(amount) ?? campaign.advanceTravel(distance:amount)
                    if let receipt=receipts.last {
                        refreshCampaign();onCampaignChanged?()
                        let coins=receipt.after.players.reduce(0){$0+$1.coins}-receipt.before.players.reduce(0){$0+$1.coins}
                        if coins>0 {onDiscovery?("小队获得金币 ＋\(coins)")}
                        else if campaign.travel==nil{onDiscovery?("已抵达，可点击交互地点或继续前进")}
                    }
                } catch {campaign.pauseAfterFailure();onCampaignError?(error.localizedDescription)}
            }
            updateActors(before:previous,seconds:delta)
            if (wasMoving || campaign.isMoving) && environmentTime-lastCampaignUIUpdate>=0.1 {lastCampaignUIUpdate=environmentTime;refreshCampaignRoute();onCampaignChanged?()}
            if wasMoving && !campaign.isMoving && campaign.travel != nil && campaign.movementRemaining<=0.000001{onCampaignError?("移动条耗尽，点击补充移动后可继续原路线。")}
            if wasMoving != campaign.isMoving {onPlaybackChanged?(campaign.isMoving);onCampaignChanged?()}
        } else {
            let previous = actors.indices.map { simulation.point(for: $0) }
            let wasPlaying = simulation.isPlaying
            let requested = simulation.isPlaying && !simulation.travelers[0].isWaiting
            simulation.advance(delta, p1CanTravel: p1Locomotion.allowsTravel(requested: requested))
            updateActors(before: previous, seconds: delta)
            if wasPlaying != simulation.isPlaying { onPlaybackChanged?(simulation.isPlaying) }
            if let discovery = pendingDiscovery, simulation.travelers[simulation.selected].isWaiting {
                completeDiscovery(discovery)
                pendingDiscovery = nil
            }
            if !simulation.isPlaying && simulation.mode == .destination { destinationRing.isHidden = true }
            if demoMode { updateDemo() }
        }
        frameCounter += 1
        if currentTime - frameWindowStart >= 1 {
            measuredFPS = Double(frameCounter) / (currentTime - frameWindowStart)
            frameCounter = 0
            frameWindowStart = currentTime
            publishDiagnostics(record: true)
        }
    }

    override func didFinishUpdate() {
        guard world != nil, simulation != nil else { return }
        initialFrames += 1
        if initialFrames == 1 { DispatchQueue.main.async { [weak self] in self?.onForegroundReady?() } }
    }

    func metalFrame(viewSize: CGSize) -> MeadowFrameState? {
        guard let world, simulation != nil else { return nil }
        let heroIndices = campaign != nil ? Array(0..<campaign!.playerIDs.count):(layeredPreview ? [0, 1] : Array(actors.indices))
        let heroes = heroIndices.map { index -> MeadowHeroCaster in
            let pose = actorPose(index)
            let u=profileUnit(index),look=u?.appearance
            // 像素人物：没有自定义外观的旅人投影也要带上身上的武器、护甲（和地图上画的一致）
            let worn=PixelHeroAtlas.enabled && u == nil ? campaignUnit(index):nil
            return MeadowHeroCaster(index: layeredPreview || look != nil ? 0 : index%3, foot: actorPoint(index), facing: pose.facing,
                                    frame: pose.frame, phase: pose.phase, hairID:look?.hair,faceID:look?.face,appearanceIndex: look.flatMap{HeroFrames.appearanceIDs.firstIndex(of:$0.body)} ?? (index == 0 ? p1AppearanceIndex : 0),weaponID:u != nil ? u!.equipment.weapon:(worn != nil ? worn!.equipment.weapon:(index == 0 ? p1WeaponID:"trainingSword")),armorID:look != nil ? look!.armor(worn:u?.equipment.armor):(worn != nil ? worn!.equipment.armor:(index == 0 ? p1ArmorID:nil)),
                                    breath: index < actors.count ? actors[index].yScale : 1)
        }
        return MeadowFrameState(world: world, camera: MeadowViewport(world: world, scene: self, viewSize: viewSize), time: environmentTime, heroes: heroes, includeEnvironment: gaitTest == nil)
    }

    private func actorPoint(_ index: Int) -> CGPoint {
        if let campaign,index<campaign.playerIDs.count {let p=campaign.position(of:campaign.playerIDs[index]);return CGPoint(x:p.x+Double(campaign.playerIDs.count<=2 ? (index==0 ? -10:10):((index%3)-1)*24),y:p.y+Double(campaign.playerIDs.count<=2 ? 0:(index/3)*25))}
        return gaitTest?.point(for:index) ?? simulation.point(for:index)
    }
    private func actorPose(_ index: Int) -> HeroPose {
        if index != 0,profileUnit(index) != nil {
            let p=profileLocomotion[index]
            return HeroPose(heroIndex:0,facing:p.facing,frame:p.frame,phase:p.phase)
        }
        let modular = index == 0 && HeroFrames.locomotionPlan != nil
        return HeroPose(heroIndex: (layeredPreview && index < 2) || profileUnit(index) != nil ? 0 : index%3,
                        facing: gaitTest?.facing ?? (modular ? p1Locomotion.facing : walks[index].facing),
                        frame: gaitTest?.frame ?? (modular ? p1Locomotion.frame : walks[index].frame),
                        phase: gaitTest?.phase ?? (modular ? p1Locomotion.phase : walks[index].phase))
    }

    private func updateActors(before: [CGPoint]?, seconds: TimeInterval = 0) {
        for index in actors.indices {
            let point = actorPoint(index)
            if gaitTest == nil, let before {
                walks[index].advance(from: before[index], to: point)
                if index != 0,profileUnit(index) != nil {
                    profileLocomotion[index].advance(from:before[index],to:point,seconds:seconds,requested:campaign.map{$0.isMoving && $0.travel?.actors.contains($0.playerIDs[index])==true} ?? false,headingHint:campaign.map{CGPoint(x:$0.heading.x,y:$0.heading.y)} ?? .zero)
                }
                if index == 0 {
                    p1Locomotion.advance(from: before[index], to: point, seconds: seconds,
                        requested: campaign.map{$0.isMoving && $0.travel?.actors.contains("p1")==true} ?? (simulation.isPlaying && !simulation.travelers[0].isWaiting),
                        headingHint: campaign.map{CGPoint(x:$0.heading.x,y:$0.heading.y)} ?? simulation.heading(for:0))
                }
            }
            let pose = actorPose(index)
            let visible = campaign != nil ? index<campaign!.playerIDs.count:(!layeredPreview || index < 2)
            actors[index].isHidden = !visible
            if let campaign,index<campaign.playerIDs.count {actors[index].alpha=campaign.engine.state.units[campaign.playerIDs[index]]?.isAlive==true ? 1:0.35}
            actorLabels[index].isHidden = !visible
            let gait = SIMD2(Float(pose.facing), Float(pose.frame))
            let texture: SKTexture
            if layeredPreview && index == 1, let layeredP1Frames {
                texture = layeredP1Frames[min(layeredP1Frames.count - 1, max(0, pose.frame - 1))]
            } else {
                texture = frames[layeredPreview ? 0 : index][pose.facing][pose.frame]
            }
            actors[index].texture = texture
            actors[index].xScale = HeroFrames.isMirrored(pose.facing) ? -1 : 1
            let alive = campaign.map { index < $0.playerIDs.count && $0.engine.state.units[$0.playerIDs[index]]?.isAlive == true } ?? true
            // The classroom draws up to 7 heroes: grow the breathing list with the cast.
            while breathing.count <= index { breathing.append(HeroBreathing()) }
            breathing[index].advance(idle: HeroBreathing.enabled && pose.frame == 0 && alive, seconds: seconds)
            actors[index].yScale = breathing[index].yScale(time: environmentTime, index: index)
            actors[index].warpGeometry = nil
            actors[index].position = pose.bodyOffset(size: actors[index].size)
            actorRoots[index].position = LivingWorld.position(point)
            actorRoots[index].zPosition = 10000 + point.y
            actorLabels[index].position = actorRoots[index].position + CGPoint(x: 0, y: -13)
            actorLabels[index].children.compactMap { $0 as? SKLabelNode }.first?.text = layeredPreview
                ? (index == 0 ? "P1 原图" : "P1 分层蓝靴") : "P\(index + 1)"
            world.effects.apply(world.effects.vegetation, to: actors[index],
                                origin: CGPoint(x: point.x, y: point.y - 24), extent: actors[index].size, gait: gait)
        }
        selectionRing.position = actorRoots[simulation.selected].position
    }

    func selectCampaignPlayer(_ id:String)throws {
        guard let campaign,let index=campaign.playerIDs.firstIndex(of:id) else{return}
        try campaign.selectPlayer(id);simulation.selected=index;selectionRing.position=actorRoots[index].position;onCampaignChanged?()
    }
    private func order(to point: CGPoint, discovery: Int? = nil) {
        if let campaign {
            let actor=selectedCampaignPlayerID
            if let discovery,let target=world.definition.discoveries[discovery].nodeID {
                if selectingCampaignNode{onCampaignNodeSelected?(target);return}
                onCampaignEncounterSelected?(target)
                if campaign.isCompleted{onDiscovery?("行程已结算，可查看结果或返回设置");return}
                if campaign.travel==nil && campaign.engine.state.units[actor]?.nodeID==target{onCampaignInteractionRequested?(target);return}
                travelCampaign(to:target)
            }else{
                onCampaignEncounterSelected?(nil)
                if campaign.isCompleted{onDiscovery?("行程已结算，可查看结果或返回设置");return}
                if selectingCampaignNode{onDiscovery?("请点击需要编辑的建筑");return}
                do{let plan=try campaign.beginTravel(toRoadPoint:.init(Double(point.x),Double(point.y)),actor:actor);refreshCampaignRoute();onDiscovery?(plan.message);onPlaybackChanged?(true);onCampaignChanged?()}catch{onCampaignError?(error.localizedDescription)}
            }
            return
        }
        simulation.orderSelected(to: point)
        pendingDiscovery = discovery
        selectionRing.isHidden = false
        let goal = simulation.routes[simulation.selected].points.last!
        destinationRing.position = LivingWorld.position(goal)
        destinationRing.isHidden = false
        onPlaybackChanged?(simulation.isPlaying)
        publishDiagnostics()
    }

    private func completeDiscovery(_ index: Int) {
        guard !discovered.contains(index) else { return }
        discovered.insert(index)
        let marker = discoveryNodes[index]
        marker.children.compactMap { $0 as? SKLabelNode }.first?.text = "✓"
        marker.children.compactMap { $0 as? SKShapeNode }.first?.fillColor = .init(red: 0.62, green: 0.45, blue: 0.19, alpha: 0.95)
        for particle in 0..<24 {
            let dot = SKShapeNode(circleOfRadius: 1.4)
            dot.fillColor = SKColor(red: 1, green: 0.9, blue: 0.6, alpha: 1)
            dot.strokeColor = .clear
            dot.position = marker.position
            dot.zPosition = 23100
            world.addChild(dot)
            let angle = CGFloat(particle) * .pi / 12
            dot.run(.sequence([.group([
                .moveBy(x: cos(angle) * 35, y: sin(angle) * 20 + 16, duration: 1.6),
                .fadeOut(withDuration: 1.6)
            ]), .removeFromParent()]))
        }
        onDiscovery?("发现 · " + world.definition.discoveries[index].title)
        publishDiagnostics()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, world != nil, gaitTest == nil else { return }
        handleWorldTap(touch.location(in: world))
    }

    func handleTap(inView point: CGPoint) {
        guard world != nil, gaitTest == nil else { return }
        handleWorldTap(world.convert(CGPoint(x: point.x, y: size.height - point.y), from: self))
    }

    func classroomWorldPoint(_ point:CGPoint)->CGPoint? {
        guard let world else{return nil}
        let projection=MeadowViewport(world:world,scene:self,viewSize:size)
        return ClassroomCanvas.unproject(point,origin:projection.origin,
            xAxis:CGPoint(x:projection.xAxis.dx,y:projection.xAxis.dy),yAxis:CGPoint(x:projection.yAxis.dx,y:projection.yAxis.dy))
    }

    func classroomNode(atWorldPoint point:CGPoint)->Int? {
        guard let world else{return nil}
        let location=LivingWorld.position(point)
        // Badges and sprite frames use their real world positions, anchors and
        // dimensions. A roof is not approximated by the nearest node center.
        for (index,marker) in discoveryNodes.enumerated() where marker.calculateAccumulatedFrame().insetBy(dx:-6,dy:-6).contains(location) {
            if let id=world.definition.discoveries[index].nodeID{return id}
        }
        for node in world.children.sorted(by:{$0.zPosition>$1.zPosition}) {
            guard let name=node.name,name.hasPrefix("landmark-"),let id=Int(name.dropFirst(9)) else{continue}
            if node.frame.insetBy(dx:-6,dy:-6).contains(location){return id}
        }
        return nil
    }

    private func handleWorldTap(_ location: CGPoint) {
        if let index = actorRoots.indices.filter({campaign == nil || $0<campaign!.playerIDs.count}).min(by: {
            hypot(actorRoots[$0].position.x - location.x, actorRoots[$0].position.y + 17 - location.y) <
            hypot(actorRoots[$1].position.x - location.x, actorRoots[$1].position.y + 17 - location.y)
        }), hypot(actorRoots[index].position.x - location.x, actorRoots[index].position.y + 17 - location.y) < 30 {
            if let campaign {do{try campaign.selectPlayer(campaign.playerIDs[index])}catch{onCampaignError?(error.localizedDescription);return}}
            simulation.selected = index
            selectionRing.isHidden = false
            selectionRing.position = actorRoots[index].position
            onSelectionChanged?("P\(index + 1)")
            publishDiagnostics()
            return
        }
        for index in discoveryNodes.indices where hypot(discoveryNodes[index].position.x - location.x,
                                                        discoveryNodes[index].position.y - location.y) < 25 {
            let item = world.definition.discoveries[index]
            order(to: CGPoint(x: item.x, y: item.y), discovery: index)
            return
        }
        if let name=world.nodes(at:location).first(where: { $0.name?.hasPrefix("landmark-") == true })?.name,
           let id=Int(name.dropFirst("landmark-".count)) {
            if let index=world.definition.discoveries.firstIndex(where:{$0.nodeID==id}) {
                let item=world.definition.discoveries[index]
                order(to:CGPoint(x:item.x,y:item.y),discovery:index);return
            }
            if let spawn=world.definition.spawn { order(to:spawn.point);return }
        }
        let point = CGPoint(x: location.x, y: -location.y)
        let projection = world.network.project(point)
        if projection.error <= 24 { order(to: projection.point) }
    }

    private func updateDemo() {
        guard world.definition.startNodeID == nil else { return }
        if environmentTime > 3, demoPhase == 0 {
            demoPhase = 1
            run(.customAction(withDuration: 1.4) { [weak self] _, elapsed in
                self?.setZoom(1 + CGFloat(elapsed) / 1.4 * 0.35)
            })
        }
        if environmentTime > 6, demoPhase == 1 {
            demoPhase = 2
            simulation.selected = 2
            let target = world.definition.discoveries[1]
            order(to: CGPoint(x: target.x, y: target.y), discovery: 1)
        }
        if environmentTime > 10, demoPhase == 2 {
            demoPhase = 3
            run(.customAction(withDuration: 1.5) { [weak self] _, elapsed in
                self?.setZoom(1.35 - CGFloat(elapsed) / 1.5 * 0.35)
            })
        }
    }

    private func residentMemoryMiB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / (1024 * 1024) : 0
    }

    private func publishDiagnostics(record: Bool = false) {
        guard world != nil, simulation != nil, size.width > 0, size.height > 0 else { return }
        let heroTargets = actors.indices.map { index -> [String: Double] in
            let local = actorRoots[index].position + CGPoint(x: 0, y: 17)
            let point = world.convert(local, to: self)
            return ["x": Double(point.x / size.width), "y": Double(1 - point.y / size.height)]
        }
        let goal = simulation.routes[min(simulation.routes.count-1,simulation.selected)].points.last!
        let orderPoint = world.convert(LivingWorld.position(CGPoint(x: 713, y: 252)), to: self)
        let memory = residentMemoryMiB()
        let metrics: [String: Any] = [
            "fps": measuredFPS, "residentMemoryMiB": memory,
            "startup": startupMetrics,
            "textureBudgetMiB": world.definition.textureBudgetMiB,
            "independentProps": gaitTest == nil ? world.objectCount : 0, "roads": gaitTest == nil ? world.network.edges.count : 0,
            "projectedShadows": (gaitTest == nil ? world.shadowCount : 0) + (layeredPreview ? 2 : actors.count), "shadowRenderer": "image-alpha relief Metal depth map", "shadowReady": shadowReady, "shadowFrames": shadowFrames,
            "shadowMapSize": shadowMapSize, "gpuFallbackCount": gpuFallbackCount, "groundDrawableScale": groundDrawableScale,
            "sunDirection": ["x": Double(world.effects.currentCast.dx), "y": Double(world.effects.currentCast.dy)],
            "environmentTime": environmentTime, "zoom": Double(zoom),
            "camera": ["scale": Double(baseScale * zoom),
                       "centerX": Double(cameraCenter.x), "centerY": Double(cameraCenter.y)],
            "selected": simulation.selected, "isPlaying": isRunning,
            "mode": gaitTest != nil ? "gaitTest" : (simulation.mode == .patrol ? "patrol" : "destination"),
            "gaitFacing": gaitTest?.facing ?? -1, "gaitPhase": Double(gaitTest?.phase ?? 0),
            "gaitFrame": gaitTest?.frame ?? -1, "gaitPaused": gaitTest?.paused ?? false,
            "gaitPoseCount": HeroFrames.authoredFrameCount(heroIndex: 0),
            "gaitAuthoredPose": gaitTest.map { HeroFrames.sourceColumn(frame: $0.frame) } ?? -1,
            "layeredPreview": layeredPreview, "layeredPreviewFrameCount": layeredP1Frames?.count ?? 0,
            "goal": ["x": Double(goal.x), "y": Double(goal.y)],
            "heroTargets": heroTargets,
            "orderPoint": ["x": Double(orderPoint.x / size.width), "y": Double(1 - orderPoint.y / size.height)],
            "discoveries": discovered.count
        ]
        if let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { onDiagnostics?(text) }
        onMetrics?(String(format: "%.0f FPS  ·  %d 物件\n纹理 %.1f MiB  ·  内存 %.0f MiB",
                          measuredFPS, world.objectCount, world.definition.textureBudgetMiB, memory))
        if record && reviewMode {
            metricSamples.append(metrics)
            if metricSamples.count > 30 { metricSamples.removeFirst() }
            if let data = try? JSONSerialization.data(withJSONObject: metricSamples, options: [.sortedKeys]) {
                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try? data.write(to: directory.appendingPathComponent("RuntimeMetrics.json"), options: .atomic)
            }
        }
    }
}

private extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
}
