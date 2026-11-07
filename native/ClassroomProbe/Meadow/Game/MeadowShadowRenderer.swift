import MetalKit
import SpriteKit
import simd

/// One MTKView, one queue and one submitted frame own both the native backdrop
/// and SKRenderer foreground. No rendering is submitted from an SKScene callback.
final class MeadowShadowRenderer: NSObject, MTKViewDelegate {
    private struct HeroState: Equatable {
        let index: Int
        let foot: CGPoint
        let facing: Int
        let frame: Int
        let phase: CGFloat
        let appearanceIndex: Int
        let weaponID:String?
        let armorID:String?

        init(_ hero: MeadowHeroCaster) {
            index = hero.index
            foot = hero.foot
            facing = hero.facing
            frame = hero.frame
            phase = hero.phase
            appearanceIndex = hero.appearanceIndex
            weaponID=hero.weaponID;armorID=hero.armorID
        }
    }

    private struct Draw {
        let buffer: MTLBuffer
        let count: Int
        let texture: MTLTexture
        let kind: Float
        var uvRect = SIMD4<Float>(0, 0, 1, 1)
    }
    static let units: Float = 32
    let device: MTLDevice
    private static let shadowResolution = 2048
    var shadowSize: Int { Self.shadowResolution }
    let shadowsEnabled = true
    private let queue: MTLCommandQueue
    private let depthTexture: MTLTexture
    private let depthPipeline: MTLRenderPipelineState
    private let receiverPipeline: MTLRenderPipelineState
    private let presentationPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let receiver: MTLBuffer
    private let receiverBounds: CGRect
    private var staticDraws: [Draw] = []
    private var textures: [String: MTLTexture] = [:]
    private var backgroundTarget: MTLTexture?
    private var foregroundRenderer: SKRenderer?
    private weak var gameScene: GameScene?
    var alignmentReview = false
    var onFirstFrameCompleted: (() -> Void)?
    var onFrameFailed: ((Error) -> Void)?
    // Keep at most one complete map frame queued. If the GPU is busy, the next
    // display callback skips submission instead of accumulating work.
    private let inFlight = DispatchSemaphore(value: 1)
    private(set) var casterCount = 0
    private(set) var submittedFrames = 0
    private(set) var textureUploadCount = 0
    private var lastRenderTime: TimeInterval = -.infinity
    private var lastCamera: MeadowViewport?
    private var lastHeroes: [HeroState] = []
    private var lastIncludesEnvironment: Bool?
    private var firstFrameReported = false
    private var gpuStopped = false

    convenience init(device: MTLDevice, world: LivingWorld) throws {
        try self.init(device: device, props: world.casterProps, roadMask: world.roadMask, bounds: world.worldBounds)
        world.terrain.removeFromParent()
    }

    init(device: MTLDevice, props: [SceneDefinition.Prop], roadMask: CGImage,
         bounds: CGRect = LivingWorld.bounds, images: [String: CGImage] = [:], progress: ((Double, String) -> Void)? = nil) throws {
        self.receiverBounds = bounds
        self.device = device
        progress?(0.02, "准备投影队列")
        guard let queue = device.makeCommandQueue(), let library = device.makeDefaultLibrary() else { throw ShadowLabError.setup("地图 Metal 初始化失败") }
        self.queue = queue
        progress?(0.06, "分配阴影深度图")
        guard let depth = Self.makeDepthTexture(device: device, size: Self.shadowResolution) else { throw ShadowLabError.setup("地图深度贴图分配失败") }
        depthTexture = depth
        progress?(0.10, "编译阴影着色器")
        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.vertexFunction = library.makeFunction(name: "labCutoutShadowVertex")
        pipeline.fragmentFunction = library.makeFunction(name: "meadowCutoutShadowFragment")
        pipeline.depthAttachmentPixelFormat = .depth32Float
        depthPipeline = try device.makeRenderPipelineState(descriptor: pipeline)
        progress?(0.20, "编译地面着色器")
        let color = MTLRenderPipelineDescriptor()
        color.vertexFunction = library.makeFunction(name: "labColorVertex")
        color.fragmentFunction = library.makeFunction(name: "meadowGroundFragment")
        color.colorAttachments[0].pixelFormat = .bgra8Unorm
        let attachment = color.colorAttachments[0]!
        attachment.isBlendingEnabled = false
        attachment.sourceRGBBlendFactor = .one; attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one; attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        receiverPipeline = try device.makeRenderPipelineState(descriptor: color)
        let presentation = MTLRenderPipelineDescriptor()
        presentation.vertexFunction = library.makeFunction(name: "meadowBackdropVertex")
        presentation.fragmentFunction = library.makeFunction(name: "meadowBackdropFragment")
        presentation.colorAttachments[0].pixelFormat = .bgra8Unorm
        presentationPipeline = try device.makeRenderPipelineState(descriptor: presentation)
        progress?(0.27, "准备地面深度状态")
        let state = MTLDepthStencilDescriptor(); state.depthCompareFunction = .lessEqual; state.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: state) else { throw ShadowLabError.setup("地图深度状态失败") }
        self.depthState = depthState
        var mesh = ShadowLabMesh()
        let b = bounds
        let a = Self.root(CGPoint(x: b.minX, y: b.minY)), c = Self.root(CGPoint(x: b.maxX, y: b.maxY))
        mesh.triangle(a, SIMD3(c.x, a.y, 0), c); mesh.triangle(a, c, SIMD3(a.x, c.y, 0))
        guard let buffer = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * MemoryLayout<ShadowLabVertex>.stride) else { throw ShadowLabError.setup("地图接收网格失败") }
        receiver = buffer
        super.init()
        progress?(0.32, "生成物件投影网格")
        // Group static instances by their original art; the depth pass needs one draw per asset.
        var groups: [String: ShadowLabMesh] = [:]
        var art = images
        func assetImage(_ name: String) -> CGImage? {
            if let cached = art[name] { return cached }
            let loaded = UIImage(named: name)?.cgImage; art[name] = loaded; return loaded
        }
        for (index, prop) in props.enumerated() {
            guard let asset = ShadowLabAsset(rawValue: prop.asset), let image = assetImage(prop.asset) else { throw ShadowLabError.setup("未配置投影素材：\(prop.asset)") }
            let instance = ShadowLabInstance(asset: asset, root: Self.root(CGPoint(x: prop.x, y: prop.y)), width: Float(prop.width) / Self.units,
                                             aspect: Float(image.height) / Float(image.width), anchor: SIMD2(0.5, asset.anchorY))
            // Mutate the grouped value in place: extracting a mesh from the
            // dictionary then appending copied all preceding vertices per prop.
            groups[prop.asset, default: ShadowLabMesh()].meadowCaster(instance,
                mirrored: prop.mirror && asset == .flowers, wind: prop.wind, phase: Float(prop.x * 0.03 + prop.y * 0.017))
            progress?(0.32 + 0.40 * Double(index + 1) / Double(max(1, props.count)), "生成物件投影网格")
            casterCount += 1
        }
        // The pole and cloth also cast through their own transparent artwork.
        for prop in props where prop.asset == "WatchTower" {
            guard let image = assetImage("Banner"), let tower = assetImage("WatchTower") else { throw ShadowLabError.setup("旗帜投影素材缺失") }
            let height = Float(prop.width) * Float(tower.height) / Float(tower.width)
            let root = Self.root(CGPoint(x: prop.x, y: prop.y)) + SIMD3<Float>(0, 0, height * (Float(LivingWorld.towerBannerRoofAnchorY) - ShadowLabAsset.tower.anchorY) / Self.units / ShadowLabMath.cameraUp.z)
            let width = min(34, max(22, Float(prop.width) * 0.40)) / Self.units
            let instance = ShadowLabInstance(asset: .banner, root: root, width: width, aspect: Float(image.height) / Float(image.width), anchor: SIMD2(0.035, 0.04))
            groups["Banner", default: ShadowLabMesh()].meadowCaster(instance, wind: 2, phase: Float(prop.x * 0.03))
            casterCount += 1
        }
        for (index, group) in groups.sorted(by: { $0.key < $1.key }).enumerated() {
            let (name, mesh) = group
            let texture = try upload(assetImage(name)!)
            textures[name] = texture
            staticDraws.append(try draw(mesh, texture: texture, kind: ShadowLabAsset(rawValue: name)!.casterKind))
            progress?(0.72 + 0.13 * Double(index + 1) / Double(max(1, groups.count)), "上传环境投影素材")
        }
        // Upload each hero atlas once during loading. Changing a walk frame
        // only changes UV bounds; it never decodes/crops/uploads on a live frame.
        for (index, name) in HeroFrames.atlasNames.enumerated() {
            guard let atlas = assetImage(name) else { throw ShadowLabError.setup("人物投影素材缺失") }
            textures[name] = try upload(atlas)
            progress?(0.85 + Double(index + 1) / Double(HeroFrames.atlasNames.count) * 0.13, "上传人物投影图集")
        }
        guard let grass = assetImage("MeadowGround") else { throw ShadowLabError.setup("地表素材缺失") }
        textures["MeadowGround"] = try upload(grass)
        textures["RoadMask"] = try upload(roadMask)
        progress?(1, "完成地表投影")
    }

    static func root(_ point: CGPoint) -> SIMD3<Float> {
        SIMD3((Float(point.x) - 640) / units, (360 - Float(point.y)) / (units * ShadowLabMath.cameraUp.y), 0)
    }

    private static func makeDepthTexture(device: MTLDevice, size: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: size, height: size, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        return device.makeTexture(descriptor: descriptor)
    }

    private func draw(_ mesh: ShadowLabMesh, texture: MTLTexture, kind: Float) throws -> Draw {
        guard let buffer = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * MemoryLayout<ShadowLabVertex>.stride) else { throw ShadowLabError.setup("地图投影网格上传失败") }
        return Draw(buffer: buffer, count: mesh.vertices.count, texture: texture, kind: kind)
    }

    private func upload(_ image: CGImage) throws -> MTLTexture {
        // The same premultiplied decode and top-origin UV convention as the approved lab.
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let ok = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.storageMode = .shared; d.usage = .shaderRead
        guard ok, let texture = device.makeTexture(descriptor: d) else { throw ShadowLabError.setup("地图素材上传失败") }
        rgba.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: w * 4) }
        textureUploadCount += 1
        return texture
    }

    // Equipment changes prewarm only the selected two atlases, outside combat.
    // Do not preload the entire armor x appearance x weapon Cartesian product.
    func prepareP1Equipment(appearance:Int,weapon:String?,armor:String?,retainingCurrent:Bool=false) throws {
        let names=[false,true].map { HeroFrames.atlasName(heroIndex:0,diagonal:$0,appearanceIndex:appearance,weaponID:weapon,armorID:armor) }
        var prepared:[String:MTLTexture]=[:]
        for name in names where textures[name]==nil {
            guard let image=UIImage(named:name)?.cgImage else { throw ShadowLabError.setup("护甲投影素材缺失") }
            prepared[name]=try upload(image)
        }
        for name in Array(textures.keys) where !retainingCurrent && HeroFrames.armorAtlasNames.contains(name) && !names.contains(name) { textures.removeValue(forKey:name) }
        for (name,texture) in prepared { textures[name]=texture }
    }
    private func heroTexture(_ hero: MeadowHeroCaster) throws -> MTLTexture {
        let name = HeroFrames.atlasName(heroIndex: hero.index, diagonal: hero.facing >= 4,
                                       appearanceIndex: hero.appearanceIndex,weaponID:hero.weaponID,armorID:hero.armorID)
        guard let texture = textures[name] else { throw ShadowLabError.setup("人物投影图集未加载") }
        return texture
    }

    private func encode(command: MTLCommandBuffer, target: MTLRenderPassDescriptor, camera: MeadowViewport,
                        time: TimeInterval, sunCast: CGVector, heroes: [MeadowHeroCaster], shadows: Bool = true, roads: Bool = true, alignment: Bool = false, includeEnvironment: Bool = true) throws {
        let renderShadows = shadows && shadowsEnabled
        if renderShadows {
            try encodeShadowDepth(command: command, draws: shadowDraws(heroes: heroes, includeEnvironment: includeEnvironment), camera: camera, time: time, sunCast: sunCast)
        }
        try encodeGround(command: command, target: target, camera: camera, time: time, sunCast: sunCast,
                         shadows: renderShadows, roads: roads && includeEnvironment, alignment: alignment)
    }

    private func shadowDraws(heroes: [MeadowHeroCaster], includeEnvironment: Bool = true) throws -> [Draw] {
        var draws = includeEnvironment ? staticDraws : []
        for hero in heroes {
            let texture = try heroTexture(hero)
            var mesh = ShadowLabMesh()
            let pose = HeroPose(heroIndex: hero.index, facing: hero.facing, frame: hero.frame, phase: hero.phase)
            let offset = pose.bodyOffset()
            let foot = CGPoint(x: hero.foot.x + offset.x, y: hero.foot.y - offset.y)
            let instance = ShadowLabInstance(asset: .hero, root: Self.root(foot), width: 64 / Self.units, aspect: 1, anchor: SIMD2(0.5, 0.125))
            mesh.imageCaster(instance, mirrored: HeroFrames.isMirrored(hero.facing), pose: pose)
            var item = try draw(mesh, texture: texture, kind: 2)
            item.uvRect = HeroFrames.atlasRect(facing: hero.facing, frame: hero.frame, heroIndex: hero.index)
            draws.append(item)
        }
        return draws
    }

    private func encodeGround(command: MTLCommandBuffer, target: MTLRenderPassDescriptor, camera: MeadowViewport,
                              time: TimeInterval, sunCast: CGVector, shadows: Bool, roads: Bool = true, alignment: Bool = false) throws {
        var u = makeUniforms(camera: camera, time: time, sunCast: sunCast, shadows: shadows)
        target.colorAttachments[0].loadAction = .clear; target.colorAttachments[0].storeAction = .store
        target.colorAttachments[0].clearColor = MTLClearColor(red: 0.15, green: 0.20, blue: 0.08, alpha: 1)
        guard let color = command.makeRenderCommandEncoder(descriptor: target) else { throw ShadowLabError.setup("地图接收通道失败") }
        color.label = shadows ? "Opaque grass + road material + PCF reception" : "Opaque grass + road material; no shadow sampling"
        color.setRenderPipelineState(receiverPipeline); color.setCullMode(.none)
        color.setVertexBuffer(receiver, offset: 0, index: 0)
        color.setVertexBytes(&u, length: MemoryLayout<ShadowLabUniforms>.stride, index: 1)
        color.setFragmentBytes(&u, length: MemoryLayout<ShadowLabUniforms>.stride, index: 1)
        color.setFragmentTexture(textures["MeadowGround"], index: 0)
        color.setFragmentTexture(depthTexture, index: 1)
        color.setFragmentTexture(textures["RoadMask"], index: 2)
        var settings = SIMD4<Float>(roads ? 1 : 0, alignment ? 1 : 0, Float(receiverBounds.height), 0)
        color.setFragmentBytes(&settings, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
        color.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6); color.endEncoding()
    }

    private func makeUniforms(camera: MeadowViewport, time: TimeInterval, sunCast: CGVector, shadows: Bool) -> ShadowLabUniforms {
        let up = ShadowLabMath.cameraUp
        let sun = simd_normalize(SIMD3(-Float(sunCast.dx) * up.z, Float(sunCast.dy) * up.z / up.y, 1))
        let light = ShadowLabMath.orthographic(halfWidth: max(46, Float(receiverBounds.height)/32), halfHeight: max(46, Float(receiverBounds.height)/32), near: 0.1, far: 180)
            * ShadowLabMath.lookAt(eye: sun * 85, target: .zero, up: SIMD3(0, 0, 1))
        return ShadowLabUniforms(camera: camera.matrix, light: light, sunTime: SIMD4(sun, Float(time)), options: SIMD4(shadows ? 1 : 0, 1 / Float(shadowSize), 1, 1))
    }

    private func encodeShadowDepth(command: MTLCommandBuffer, draws: [Draw], camera: MeadowViewport,
                                   time: TimeInterval, sunCast: CGVector) throws {
        var u = makeUniforms(camera: camera, time: time, sunCast: sunCast, shadows: true)
        let pass = MTLRenderPassDescriptor(); pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .store; pass.depthAttachment.clearDepth = 1
        guard let depth = command.makeRenderCommandEncoder(descriptor: pass) else { throw ShadowLabError.setup("地图深度通道失败") }
        depth.label = "All meadow assets: alpha relief depth"
        depth.setRenderPipelineState(depthPipeline); depth.setDepthStencilState(depthState); depth.setCullMode(.none)
        depth.setVertexBytes(&u, length: MemoryLayout<ShadowLabUniforms>.stride, index: 1)
        depth.setFragmentBytes(&u, length: MemoryLayout<ShadowLabUniforms>.stride, index: 1)
        for item in draws {
            var settings = SIMD4<Float>(item.kind, 0.32, 0, 0)
            depth.setVertexBuffer(item.buffer, offset: 0, index: 0); depth.setFragmentTexture(item.texture, index: 0)
            depth.setFragmentBytes(&settings, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            var uvRect = item.uvRect
            depth.setFragmentBytes(&uvRect, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
            depth.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: item.count)
        }
        depth.endEncoding()
    }

    func start(in view: MTKView, scene: GameScene) {
        gameScene = scene
        let foreground = SKRenderer(device: device)
        foreground.scene = scene
        foregroundRenderer = foreground
        lastCamera = nil; lastRenderTime = -.infinity; lastHeroes = []; lastIncludesEnvironment = nil
        view.delegate = self
        view.preferredFramesPerSecond = 60
        view.isPaused = false
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !gpuStopped, let foreground = foregroundRenderer, let scene = gameScene,
              inFlight.wait(timeout: .now()) == .success else { return }
        if scene.size != view.bounds.size { scene.size = view.bounds.size }
        foreground.update(atTime: CACurrentMediaTime())
        guard let frame = scene.metalFrame(viewSize: view.bounds.size),
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { inFlight.signal(); return }
        let frameNumber = submittedFrames + 1
        do {
            let command = try MeadowGPUDiagnostics.command(queue: queue, label: "C02 单视图完整组合 #\(frameNumber)")
            try encodeComposite(command: command, target: pass, frame: frame, foreground: foreground)
            let semaphore = inFlight
            command.addCompletedHandler { [weak self] buffer in
                if let error = buffer.error {
                    let failure = MeadowGPUDiagnostics.shared.failed(error, stage: "C02 单视图完整组合", command: buffer,
                        context: ["frame": frameNumber, "environmentTime": frame.time, "gaitTest": !frame.includeEnvironment,
                                  "shadowMap": self?.shadowSize ?? 0, "cameraPoints": [Double(frame.camera.size.width), Double(frame.camera.size.height)]])
                    DispatchQueue.main.async {
                        self?.gpuStopped = true; self?.onFrameFailed?(failure); semaphore.signal()
                    }
                    return
                }
                semaphore.signal()
                guard buffer.status == .completed else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    let record = frameNumber <= 2 || frameNumber == 60
                    MeadowGPUDiagnostics.shared.passed("C02 组合帧 #\(frameNumber)", command: buffer, recordEvent: record, group: "liveComposite")
                    if !self.firstFrameReported {
                        self.firstFrameReported = true
                        self.onFirstFrameCompleted?()
                    }
                }
            }
            command.present(drawable); command.commit(); submittedFrames = frameNumber
            scene.shadowFrames = submittedFrames
        } catch {
            inFlight.signal(); gpuStopped = true; onFrameFailed?(error)
        }
    }

    /// The offscreen repeated probe and the live drawable use this same path.
    /// Keep terrain at one pixel per point and foreground at native Retina size.
    func encodeComposite(command: MTLCommandBuffer, target: MTLRenderPassDescriptor, frame: MeadowFrameState,
                         foreground: SKRenderer, forceBackground: Bool = false) throws {
        let width = max(1, Int(frame.camera.size.width.rounded(.up)))
        let height = max(1, Int(frame.camera.size.height.rounded(.up)))
        var recreated = false
        if backgroundTarget?.width != width || backgroundTarget?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private; descriptor.usage = [.renderTarget, .shaderRead]
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw ShadowLabError.setup("组合地表目标分配失败") }
            texture.label = "Meadow point-resolution backdrop"
            backgroundTarget = texture; recreated = true
        }
        let heroes = frame.heroes.map(HeroState.init)
        let heroChanged = heroes != lastHeroes
        let environmentChanged = frame.includeEnvironment != lastIncludesEnvironment
        // Moving casters are part of this cached backdrop, including their
        // shadows. Track foot roots as well as poses so a stationary gait frame
        // cannot leave the shadow behind while the SpriteKit actor advances.
        // Time-varying lighting and fog follow each submitted 60 Hz scene sample.
        // Reuse a static gait-test backdrop; never gate animated scenery at 30 Hz.
        let environmentAdvanced = frame.includeEnvironment && frame.time != lastRenderTime
        if forceBackground || recreated || frame.camera != lastCamera || environmentChanged
            || heroChanged || environmentAdvanced {
            let backdrop = MTLRenderPassDescriptor(); backdrop.colorAttachments[0].texture = backgroundTarget
            try encode(command: command, target: backdrop, camera: frame.camera, time: frame.time,
                       sunCast: frame.world.effects.currentCast, heroes: frame.heroes, alignment: alignmentReview, includeEnvironment: frame.includeEnvironment)
            lastRenderTime = frame.time; lastCamera = frame.camera
            lastHeroes = heroes; lastIncludesEnvironment = frame.includeEnvironment
        }
        target.colorAttachments[0].loadAction = .clear; target.colorAttachments[0].storeAction = .store
        guard let present = command.makeRenderCommandEncoder(descriptor: target), let output = target.colorAttachments[0].texture else { throw ShadowLabError.setup("组合背景呈现编码失败") }
        present.label = "Point-resolution backdrop to Retina target"
        present.setRenderPipelineState(presentationPipeline)
        present.setFragmentTexture(backgroundTarget, index: 0)
        present.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        present.endEncoding()
        target.colorAttachments[0].loadAction = .load
        foreground.render(withViewport: CGRect(x: 0, y: 0, width: output.width, height: output.height), commandBuffer: command, renderPassDescriptor: target)
    }

    /// Run only on the loader's worker queue, before any SpriteKit texture
    /// preload/rendering. Separate command buffers identify the failed native pass.
    func diagnoseStartup(size: CGSize, diagnostics: MeadowGPUDiagnostics = .shared,
                         progress: (Double, String) -> Void = { _, _ in }) throws {
        let pixels = CGSize(width: max(1, size.width.rounded(.up)), height: max(1, size.height.rounded(.up)))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(pixels.width), height: Int(pixels.height), mipmapped: false)
        descriptor.storageMode = .private; descriptor.usage = .renderTarget
        guard let target = device.makeTexture(descriptor: descriptor) else { throw ShadowLabError.setup("地表诊断目标分配失败") }
        let camera = MeadowViewport(size: size, center: CGPoint(x: 640, y: 360), scale: min(size.width / 1280, size.height / 720))
        let heroes = (0..<3).map { MeadowHeroCaster(index: $0, foot: CGPoint(x: 300 + $0 * 100, y: 442), facing: 0, frame: 0) }
        let labels = ["A01 原生 Metal 清屏", "A02 地表材质（无阴影）", "A03 全物件＋待机人物阴影深度", "A04 地表阴影接收 PCF"]
        for (index, label) in labels.enumerated() {
            progress(Double(index) / Double(labels.count), label)
            diagnostics.beginStage(label, kind: "native Metal; no SpriteKit rendering", size: index == 2 ? CGSize(width: shadowSize, height: shadowSize) : pixels)
            let command = try MeadowGPUDiagnostics.command(queue: queue, label: label)
            let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = target
            if index == 0 {
                pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
                guard let clear = command.makeRenderCommandEncoder(descriptor: pass) else { throw ShadowLabError.setup("清屏诊断编码失败") }
                clear.label = label; clear.endEncoding()
            } else if index == 2 {
                try encodeShadowDepth(command: command, draws: shadowDraws(heroes: heroes), camera: camera, time: 1, sunCast: MeadowSun.cast)
            } else {
                try encodeGround(command: command, target: pass, camera: camera, time: 1, sunCast: MeadowSun.cast, shadows: index == 3)
            }
            command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw diagnostics.failed(error, stage: label, command: command) }
            guard command.status == .completed else { throw diagnostics.failed(ShadowLabError.setup("诊断命令未完成"), stage: label, command: command) }
            diagnostics.passed(label, command: command)
        }
        progress(1, "原生 Metal 分通道检查完成")
    }

    func groundSnapshot(world: LivingWorld, width: Int = 768, height: Int = 432, roads: Bool = true, shadows: Bool = true, camera: MeadowViewport? = nil, alignment: Bool = false, heroes: [MeadowHeroCaster] = []) throws -> (image: UIImage, bgra: [UInt8]) {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.storageMode = .shared; d.usage = .renderTarget
        guard let target = device.makeTexture(descriptor: d), let command = queue.makeCommandBuffer() else { throw ShadowLabError.setup("地面检查缓冲区失败") }
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = target
        try encode(command: command, target: pass, camera: camera ?? MeadowViewport(size: CGSize(width: width, height: height), center: CGPoint(x: 640, y: 360), scale: CGFloat(width) / 1280), time: 1, sunCast: world.effects.currentCast, heroes: heroes, shadows: shadows, roads: roads, alignment: alignment)
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw ShadowLabError.setup("地面检查图像失败") }
        return (UIImage(cgImage: image), bytes)
    }

    /// Native pipeline execution check: no image readback or effect inspection.
    func validateSubmission(world: LivingWorld, heroes: [MeadowHeroCaster]) throws {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 128, height: 72, mipmapped: false)
        d.storageMode = .private; d.usage = .renderTarget
        guard let texture = device.makeTexture(descriptor: d), let command = queue.makeCommandBuffer() else { throw ShadowLabError.setup("地图运行检查分配失败") }
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = texture
        try encode(command: command, target: pass, camera: MeadowViewport(size: CGSize(width: 128, height: 72), center: CGPoint(x: 640, y: 360), scale: 0.1), time: 1, sunCast: world.effects.currentCast, heroes: heroes)
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        guard command.status == .completed else { throw ShadowLabError.setup("地图 Metal 检查未完成") }
    }
}

struct MeadowHeroCaster {
    let index: Int
    let foot: CGPoint
    let facing: Int
    let frame: Int
    var phase: CGFloat = 0
    var appearanceIndex: Int = 0
    var weaponID:String?="trainingSword"
    var armorID:String?
}

struct MeadowFrameState {
    let world: LivingWorld
    let camera: MeadowViewport
    let time: TimeInterval
    let heroes: [MeadowHeroCaster]
    var includeEnvironment: Bool = true
}
