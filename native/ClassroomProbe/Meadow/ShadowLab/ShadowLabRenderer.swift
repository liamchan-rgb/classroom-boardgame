import MetalKit
import UIKit

enum ShadowLabError: LocalizedError {
    case setup(String)
    var errorDescription: String? { switch self { case let .setup(message): return message } }
}

struct ShadowLabSnapshot {
    let image: UIImage
    let bgra: [UInt8]
    let width: Int
    let height: Int
    let depthTexels: Int
    let minimumDepth: Float
}

/// Three passes on one command buffer: real 3D depth, ground receiver, original RGBA art.
/// Normal display never reads pixels back to the CPU or transfers between views.
final class ShadowLabRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let shadowSize = 1024
    var paused = false
    var automaticSun = true
    var manualSun: Float = -0.65
    var shadowsEnabled = true
    var modelsVisible = false
    var zoom: Float = 1
    var seed: UInt64 = 1
    var onStatus: ((String) -> Void)?
    private(set) var elapsed: Float = 0
    var currentSunAngle: Float { automaticSun ? -0.65 + sin(elapsed * 0.19) * 0.60 : manualSun }
    private let queue: MTLCommandQueue
    private let shadowMap: MTLTexture
    private let cutoutShadowPipeline: MTLRenderPipelineState
    private let groundPipeline: MTLRenderPipelineState
    private let artworkPipeline: MTLRenderPipelineState
    private let cutoutModelPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let groundBuffer: MTLBuffer
    private var textures: [String: MTLTexture] = [:]
    private var lastTime = CACurrentMediaTime()
    private var reportTime = CACurrentMediaTime()
    private var reportFrames = 0
    private var frameCount = 0
    private var samples: [[String: Any]] = []
    private let inFlight = DispatchSemaphore(value: 2)

    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue(), let library = device.makeDefaultLibrary() else {
            throw ShadowLabError.setup("无法建立 Metal 渲染队列或加载着色器")
        }
        self.queue = queue
        let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: shadowSize, height: shadowSize, mipmapped: false)
        depth.storageMode = .private
        depth.usage = [.renderTarget, .shaderRead]
        guard let shadowMap = device.makeTexture(descriptor: depth) else { throw ShadowLabError.setup("无法分配深度阴影贴图") }
        self.shadowMap = shadowMap
        shadowMap.label = "ShadowLab 1024x1024 real 3D depth"
        let cutout = MTLRenderPipelineDescriptor()
        cutout.label = "Image-alpha clipped 3D relief casters"
        cutout.vertexFunction = library.makeFunction(name: "labCutoutShadowVertex")
        cutout.fragmentFunction = library.makeFunction(name: "labCutoutShadowFragment")
        cutout.depthAttachmentPixelFormat = .depth32Float
        cutoutShadowPipeline = try device.makeRenderPipelineState(descriptor: cutout)

        func colorPipeline(_ fragment: String, blend: Bool) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = fragment
            descriptor.vertexFunction = library.makeFunction(name: "labColorVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            if blend {
                let attachment = descriptor.colorAttachments[0]!
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        groundPipeline = try colorPipeline("labGroundFragment", blend: false)
        artworkPipeline = try colorPipeline("labArtworkFragment", blend: true)
        cutoutModelPipeline = try colorPipeline("labCutoutModelFragment", blend: true)
        let state = MTLDepthStencilDescriptor()
        state.depthCompareFunction = .lessEqual
        state.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: state) else { throw ShadowLabError.setup("无法建立阴影深度状态") }
        self.depthState = depthState
        var ground = ShadowLabMesh()
        ground.triangle(SIMD3(-30, -30, 0), SIMD3(30, -30, 0), SIMD3(30, 30, 0))
        ground.triangle(SIMD3(-30, -30, 0), SIMD3(30, 30, 0), SIMD3(-30, 30, 0))
        guard let groundBuffer = device.makeBuffer(bytes: ground.vertices, length: ground.vertices.count * MemoryLayout<ShadowLabVertex>.stride) else {
            throw ShadowLabError.setup("无法建立地面网格")
        }
        self.groundBuffer = groundBuffer
        super.init()
        for name in ["MeadowGround", "OakA", "WatchTower", "Banner"] {
            guard let image = UIImage(named: name)?.cgImage else { throw ShadowLabError.setup("缺少素材 \(name)") }
            textures[name] = try upload(image)
        }
        guard let atlas = UIImage(named: "Hero1Directions")?.cgImage else { throw ShadowLabError.setup("缺少人物素材") }
        let cell = atlas.height / HeroFrames.atlasRows
        for frame in 0..<HeroFrames.columns {
            let column = HeroFrames.sourceColumn(frame: frame)
            guard let image = atlas.cropping(to: CGRect(x: column * cell, y: cell, width: cell, height: cell)) else { throw ShadowLabError.setup("人物切片失败") }
            textures["hero\(frame)"] = try upload(image)
        }
    }

    private func upload(_ image: CGImage) throws -> MTLTexture {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw ShadowLabError.setup("素材解码失败") }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw ShadowLabError.setup("素材上传失败") }
        rgba.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        if !paused { elapsed += Float(min(0.1, now - lastTime)) }
        lastTime = now
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer() else { inFlight.signal(); return }
        command.label = "ShadowLab depth + receiver + artwork"
        let sun = currentSunAngle
        let frame = ShadowLabFrame(time: elapsed, sunAngle: sun, shadows: shadowsEnabled, models: modelsVisible, zoom: zoom, seed: seed)
        do {
            let count = try encode(command: command, color: descriptor, size: view.drawableSize, frame: frame)
            let semaphore = inFlight
            command.addCompletedHandler { buffer in
                semaphore.signal()
                if let error = buffer.error { DispatchQueue.main.async { [weak self] in self?.onStatus?("Metal 渲染失败：\(error.localizedDescription)") } }
            }
            command.present(drawable)
            command.commit()
            frameCount += 1; reportFrames += 1
            if now - reportTime >= 1 {
                let fps = Double(reportFrames) / (now - reportTime)
                let status = String(format: "%.0f FPS · %@ %@ · 光向 %.0f°", fps, "轮廓投影", shadowsEnabled ? "开" : "关", sun * 180 / .pi)
                onStatus?(status)
                samples.append(["time": elapsed, "fps": fps, "proxyTriangles": count / 3, "shadowMapSize": shadowSize,
                                "sunAngle": sun, "shadowsEnabled": shadowsEnabled, "seed": seed, "zoom": zoom,
                                "objects": 3, "depthPasses": frameCount])
                if samples.count > 180 { samples.removeFirst() }
                if let data = try? JSONSerialization.data(withJSONObject: samples, options: .prettyPrinted),
                   let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("ShadowLabMetrics.json") {
                    try? data.write(to: url, options: .atomic)
                }
                reportTime = now; reportFrames = 0
            }
        } catch { inFlight.signal(); onStatus?(error.localizedDescription) }
    }

    private func buffer(_ vertices: [ShadowLabVertex]) throws -> MTLBuffer {
        guard let result = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<ShadowLabVertex>.stride) else { throw ShadowLabError.setup("网格上传失败") }
        return result
    }

    @discardableResult
    private func encode(command: MTLCommandBuffer, color: MTLRenderPassDescriptor, size: CGSize, frame: ShadowLabFrame) throws -> Int {
        let sun = ShadowLabMath.sun(angle: frame.sunAngle)
        var uniforms = ShadowLabUniforms(camera: ShadowLabMath.camera(aspect: Float(size.width / max(size.height, 1)), zoom: frame.zoom),
                                         light: ShadowLabMath.light(sun: sun), sunTime: SIMD4(sun, frame.time),
                                         options: SIMD4(frame.shadows ? 1 : 0, 1 / Float(shadowSize), frame.wind ? 1 : 0, 0))
        let instances = ShadowLabMath.instances(seed: frame.seed, time: frame.time)
        let heroFrame = frame.heroFrame ?? ShadowLabMath.heroFrame(time: frame.time)
        var cutouts: [(buffer: MTLBuffer, count: Int, texture: MTLTexture, kind: Float)] = []
        for instance in instances {
            var mesh = ShadowLabMesh()
            mesh.imageCaster(instance, mirrored: instance.asset == .hero && ShadowLabMath.heroMovingRight(time: frame.time))
            let key = instance.asset == .hero ? "hero\(heroFrame)" : instance.asset.rawValue
            guard let texture = textures[key] else { throw ShadowLabError.setup("投影素材缺失：\(key)") }
            cutouts.append((try buffer(mesh.vertices), mesh.vertices.count, texture, instance.asset.casterKind))
        }
        let shadowPass = MTLRenderPassDescriptor()
        shadowPass.depthAttachment.texture = shadowMap
        shadowPass.depthAttachment.loadAction = .clear
        shadowPass.depthAttachment.storeAction = .store
        shadowPass.depthAttachment.clearDepth = 1
        guard let depth = command.makeRenderCommandEncoder(descriptor: shadowPass) else { throw ShadowLabError.setup("阴影通道建立失败") }
        depth.label = "Alpha-clipped image relief into real 3D depth"
        depth.setDepthStencilState(depthState)
        depth.setCullMode(.none)
        depth.setVertexBytes(&uniforms, length: MemoryLayout<ShadowLabUniforms>.stride, index: 1)
        depth.setRenderPipelineState(cutoutShadowPipeline)
        for caster in cutouts {
            var settings = SIMD4<Float>(caster.kind, 0.32, 0, 0)
            depth.setVertexBuffer(caster.buffer, offset: 0, index: 0)
            depth.setFragmentTexture(caster.texture, index: 0)
            depth.setFragmentBytes(&settings, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            depth.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: caster.count)
        }
        depth.endEncoding()

        color.colorAttachments[0].loadAction = .clear
        color.colorAttachments[0].storeAction = .store
        color.colorAttachments[0].clearColor = MTLClearColor(red: 0.28, green: 0.36, blue: 0.15, alpha: 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: color) else { throw ShadowLabError.setup("颜色通道建立失败") }
        encoder.label = "Ground PCF receiver + premultiplied artwork"
        encoder.setCullMode(.none)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShadowLabUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShadowLabUniforms>.stride, index: 1)
        encoder.setRenderPipelineState(groundPipeline)
        encoder.setVertexBuffer(groundBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(textures["MeadowGround"], index: 0)
        encoder.setFragmentTexture(shadowMap, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        if frame.artwork {
            encoder.setRenderPipelineState(artworkPipeline)
            for instance in instances.sorted(by: { $0.root.y > $1.root.y }) {
                if instance.asset == .tower {
                    // Draw the flag BEFORE the tower: the roof occludes the lower pole.
                    let flag = ShadowLabInstance(asset: .tower, root: instance.imagePoint(0.5, 0.10), width: 1.4,
                                                 aspect: 258.0 / 400, anchor: SIMD2(0.065, 0.035))
                    var mesh = ShadowLabMesh(); mesh.card(flag, rows: 8)
                    for index in mesh.vertices.indices { mesh.vertices[index].uvWind.z = mesh.vertices[index].uvWind.x * 0.7; mesh.vertices[index].uvWind.w = 1.2 }
                    encoder.setVertexBuffer(try buffer(mesh.vertices), offset: 0, index: 0)
                    encoder.setFragmentTexture(textures["Banner"], index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertices.count)
                }
                var mesh = ShadowLabMesh()
                mesh.card(instance, rows: instance.asset == .tree ? 32 : 1, windPhase: 0.4)
                if instance.asset == .hero && ShadowLabMath.heroMovingRight(time: frame.time) {
                    for index in mesh.vertices.indices { mesh.vertices[index].uvWind.x = 1 - mesh.vertices[index].uvWind.x }
                }
                encoder.setVertexBuffer(try buffer(mesh.vertices), offset: 0, index: 0)
                encoder.setFragmentTexture(textures[instance.asset == .hero ? "hero\(heroFrame)" : instance.asset.rawValue], index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertices.count)
            }
        }
        if frame.models {
            encoder.setRenderPipelineState(cutoutModelPipeline)
            for caster in cutouts {
                var settings = SIMD4<Float>(caster.kind, 0.32, 0, 0)
                encoder.setVertexBuffer(caster.buffer, offset: 0, index: 0)
                encoder.setFragmentTexture(caster.texture, index: 0)
                encoder.setFragmentBytes(&settings, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: caster.count)
            }
        }
        encoder.endEncoding()
        return cutouts.reduce(0) { $0 + $1.count }
    }

    /// Submission/error check only: no image readback, screenshot or visual assertion.
    func validateFrameSubmission(frame: ShadowLabFrame) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.usage = .renderTarget; descriptor.storageMode = .private
        guard let target = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else {
            throw ShadowLabError.setup("基础运行缓冲区分配失败")
        }
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = target
        try encode(command: command, color: pass, size: CGSize(width: 64, height: 64), frame: frame)
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        guard command.status == .completed else { throw ShadowLabError.setup("Metal 命令未正常完成") }
    }

    /// Explicit review path only: waits for the GPU and reads actual rendered colors AND depth.
    func snapshot(frame: ShadowLabFrame, width: Int = 900, height: Int = 600) throws -> ShadowLabSnapshot {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget; descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer(),
              let depthCopy = device.makeBuffer(length: shadowSize * shadowSize * 4, options: .storageModeShared) else { throw ShadowLabError.setup("验收缓冲区分配失败") }
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = target
        try encode(command: command, color: pass, size: CGSize(width: width, height: height), frame: frame)
        guard let blit = command.makeBlitCommandEncoder() else { throw ShadowLabError.setup("深度回读通道失败") }
        blit.copy(from: shadowMap, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: shadowSize, height: shadowSize, depth: 1), to: depthCopy, destinationOffset: 0,
                  destinationBytesPerRow: shadowSize * 4, destinationBytesPerImage: shadowSize * shadowSize * 4)
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        let depths = UnsafeBufferPointer(start: depthCopy.contents().assumingMemoryBound(to: Float.self), count: shadowSize * shadowSize)
        let covered = depths.filter { $0 < 0.9999 && $0.isFinite }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw ShadowLabError.setup("验收截图生成失败") }
        return ShadowLabSnapshot(image: UIImage(cgImage: image), bgra: bytes, width: width, height: height,
                                 depthTexels: covered.count, minimumDepth: covered.min() ?? 1)
    }
}
