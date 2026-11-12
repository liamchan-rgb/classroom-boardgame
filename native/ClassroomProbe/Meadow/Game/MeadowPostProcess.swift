import MetalKit
import SpriteKit
import simd

/// World-layer HD-2D look: tilt-shift, bloom, warm haze, drifting shafts,
/// grade and vignette. It only changes presentation. Input, routes, camera,
/// projection and hit-testing are untouched; on-map UI is drawn afterwards.
final class MeadowPostProcess {
    struct Settings: Equatable {
        // Tilt-shift as fractions of the view height around the focus line.
        var focus: Float = 0.5
        var clearHalfBand: Float = 0.22
        var smallReached: Float = 0.38
        var largeReached: Float = 0.60
        var tiltSmallSigma: Float = 0.0025   // fraction of view height
        var tiltLargeSigma: Float = 0.0065
        // Bloom.
        var bloomThreshold: Float = 0.58
        var bloomKnee: Float = 0.22
        var bloomSmallSigma: Float = 0.020
        var bloomLargeSigma: Float = 0.050
        var bloomSmall: Float = 0.40
        var bloomLarge: Float = 0.28
        // Grade.
        var sCurve: Float = 0.40
        var saturation: Float = 1.10
        var warmHighlights: Float = 0.030
        var coolShadows: Float = 0.022
        var vignette: Float = 0.34
        var vignetteInner: Float = 0.45
        var vignetteOuter: Float = 1.05
        var haze = SIMD4<Float>(214 / 255, 198 / 255, 170 / 255, 0.10)
        // Shafts (world points per band; drift in radians per second).
        var shaftIntensity: Float = 0.085
        var shaftPeriod: Float = 260
        var shaftDrift: Float = 0.16
        var shaftColor = SIMD3<Float>(255 / 255, 225 / 255, 170 / 255)

        static let hd2d = Settings()
    }

    private struct Uniforms {
        var view: SIMD4<Float>
        var tilt: SIMD4<Float>
        var bloom: SIMD4<Float>
        var grade: SIMD4<Float>
        var vignette: SIMD4<Float>
        var haze: SIMD4<Float>
        var shafts: SIMD4<Float>
        var shaftColor: SIMD4<Float>
        var worldInverse: SIMD4<Float>
        var worldOrigin: SIMD4<Float>
    }

    /// Matches MeadowPostBlur in the shader: axis + 12 paired taps.
    struct BlurKernel: Equatable {
        static let maxTaps = 12
        var centre: Float
        var taps: [SIMD2<Float>]   // (offset in texels, combined weight)

        /// Discrete Gaussian, normalised, folded into bilinear pairs so each
        /// pair costs one fetch per side. Sigma is clamped to what 12 pairs cover.
        static func gaussian(sigma: Float) -> BlurKernel {
            let s = min(max(sigma, 0.01), Float(maxTaps * 2) / 3)
            let radius = max(1, Int((s * 3).rounded(.up)))
            var weights = (0...radius).map { k -> Float in exp(-Float(k * k) / (2 * s * s)) }
            let total = weights[0] + 2 * weights.dropFirst().reduce(0, +)
            weights = weights.map { $0 / total }
            var taps: [SIMD2<Float>] = []
            var k = 1
            while k <= radius {
                let w1 = weights[k], w2 = k + 1 <= radius ? weights[k + 1] : 0
                let w = w1 + w2
                let offset = w > 0 ? (Float(k) * w1 + Float(k + 1) * w2) / w : Float(k)
                taps.append(SIMD2(offset, w))
                k += 2
            }
            return BlurKernel(centre: weights[0], taps: Array(taps.prefix(maxTaps)))
        }
    }

    /// On-map UI lives in the world node (it follows the camera) but must not
    /// be blurred or graded: node badges, "P1" plates, completion sparks.
    static let overlayDepth: CGFloat = 22000

    var settings = Settings.hd2d
    var isEnabled: Bool
    private let device: MTLDevice
    private let downsample: MTLRenderPipelineState
    private let bright: MTLRenderPipelineState
    private let blur: MTLRenderPipelineState
    private let composite: MTLRenderPipelineState
    private var sceneTexture: MTLTexture?
    private var levels: [String: MTLTexture] = [:]
    private(set) var textureBytes = 0

    init(device: MTLDevice, library: MTLLibrary, enabled: Bool = true) throws {
        self.device = device
        isEnabled = enabled
        func pipeline(_ fragment: String) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            guard let vertex = library.makeFunction(name: "meadowPostVertex"),
                  let shader = library.makeFunction(name: fragment) else {
                throw ShadowLabError.setup("后处理着色器缺失：\(fragment)")
            }
            descriptor.label = fragment
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = shader
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        downsample = try pipeline("meadowPostDownsample")
        bright = try pipeline("meadowPostBright")
        blur = try pipeline("meadowPostBlur")
        composite = try pipeline("meadowPostComposite")
    }

    /// Full-resolution offscreen target that receives the world before grading.
    func worldTarget(width: Int, height: Int) throws -> MTLTexture {
        if let texture = sceneTexture, texture.width == width, texture.height == height { return texture }
        sceneTexture = try makeTexture("Meadow post world", width, height)
        let quarter = (max(1, width / 4), max(1, height / 4))
        let eighth = (max(1, width / 8), max(1, height / 8))
        let sixteenth = (max(1, width / 16), max(1, height / 16))
        levels = [:]
        for (name, size) in [("q", quarter), ("qTmp", quarter), ("qTiltSmall", quarter),
                             ("e", eighth), ("eTmp", eighth), ("eTiltLarge", eighth),
                             ("eBright", eighth), ("eBloomSmall", eighth),
                             ("s", sixteenth), ("sTmp", sixteenth), ("sBloomLarge", sixteenth)] {
            levels[name] = try makeTexture("Meadow post \(name)", size.0, size.1)
        }
        textureBytes = ([sceneTexture!] + Array(levels.values)).reduce(0) { $0 + $1.width * $1.height * 4 }
        return sceneTexture!
    }

    /// Release the offscreen chain, e.g. when the effect is switched off.
    func releaseTargets() { sceneTexture = nil; levels = [:]; textureBytes = 0 }

    private func makeTexture(_ label: String, _ width: Int, _ height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw ShadowLabError.setup("后处理目标分配失败") }
        texture.label = label
        return texture
    }

    /// Grade `worldTarget` into `target` (which is cleared and fully covered).
    func encode(command: MTLCommandBuffer, target: MTLRenderPassDescriptor, camera: MeadowViewport, time: TimeInterval) throws {
        guard let scene = sceneTexture, let q = levels["q"], let qTmp = levels["qTmp"], let qTiltSmall = levels["qTiltSmall"],
              let e = levels["e"], let eTmp = levels["eTmp"], let eTiltLarge = levels["eTiltLarge"],
              let eBright = levels["eBright"], let eBloomSmall = levels["eBloomSmall"],
              let s = levels["s"], let sTmp = levels["sTmp"], let sBloomLarge = levels["sBloomLarge"] else {
            throw ShadowLabError.setup("后处理目标未准备")
        }
        let h = Float(scene.height)
        pass(command, downsample, from: scene, to: q)
        gaussian(command, from: q, via: qTmp, to: qTiltSmall, sigma: settings.tiltSmallSigma * h / 4)
        pass(command, downsample, from: q, to: e)
        gaussian(command, from: e, via: eTmp, to: eTiltLarge, sigma: settings.tiltLargeSigma * h / 8)
        var threshold = SIMD2<Float>(settings.bloomThreshold, settings.bloomKnee)
        pass(command, bright, from: e, to: eBright) { $0.setFragmentBytes(&threshold, length: MemoryLayout<SIMD2<Float>>.stride, index: 0) }
        gaussian(command, from: eBright, via: eTmp, to: eBloomSmall, sigma: settings.bloomSmallSigma * h / 8)
        pass(command, downsample, from: eBright, to: s)
        gaussian(command, from: s, via: sTmp, to: sBloomLarge, sigma: settings.bloomLargeSigma * h / 16)

        var u = uniforms(camera: camera, time: time)
        target.colorAttachments[0].loadAction = .dontCare
        target.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: target) else { throw ShadowLabError.setup("后处理合成编码失败") }
        encoder.label = "HD-2D world grade"
        encoder.setRenderPipelineState(composite)
        for (index, texture) in [scene, qTiltSmall, eTiltLarge, eBloomSmall, sBloomLarge].enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func pass(_ command: MTLCommandBuffer, _ state: MTLRenderPipelineState, from source: MTLTexture, to destination: MTLTexture,
                      configure: ((MTLRenderCommandEncoder) -> Void)? = nil) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = destination
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = destination.label
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        configure?(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func gaussian(_ command: MTLCommandBuffer, from source: MTLTexture, via temporary: MTLTexture, to destination: MTLTexture, sigma: Float) {
        let kernel = BlurKernel.gaussian(sigma: sigma)
        for (input, output, horizontal) in [(source, temporary, true), (temporary, destination, false)] {
            var data = [SIMD4<Float>](repeating: .zero, count: 1 + BlurKernel.maxTaps)
            data[0] = SIMD4(horizontal ? 1 / Float(output.width) : 0, horizontal ? 0 : 1 / Float(output.height),
                            kernel.centre, Float(kernel.taps.count))
            for (index, tap) in kernel.taps.enumerated() { data[index + 1] = SIMD4(tap.x, tap.y, 0, 0) }
            pass(command, blur, from: input, to: output) {
                $0.setFragmentBytes(&data, length: MemoryLayout<SIMD4<Float>>.stride * data.count, index: 0)
            }
        }
    }

    private func uniforms(camera: MeadowViewport, time: TimeInterval) -> Uniforms {
        let c = settings
        // View point = origin + x * xAxis + y * yAxis; invert the 2x2 for shafts.
        let a = Float(camera.xAxis.dx), b = Float(camera.xAxis.dy), cc = Float(camera.yAxis.dx), d = Float(camera.yAxis.dy)
        let det = a * d - b * cc
        let inverse = abs(det) > 1e-6 ? SIMD4(d / det, -b / det, -cc / det, a / det) : SIMD4<Float>(1, 0, 0, 1)
        return Uniforms(
            view: SIMD4(Float(camera.size.width), Float(camera.size.height), 0, 0),
            tilt: SIMD4(c.focus, c.clearHalfBand, c.smallReached, c.largeReached),
            bloom: SIMD4(c.bloomSmall, c.bloomLarge, 0, 0),
            grade: SIMD4(c.sCurve, c.saturation, c.warmHighlights, c.coolShadows),
            vignette: SIMD4(c.vignette, c.vignetteInner, c.vignetteOuter, 0),
            haze: c.haze,
            shafts: SIMD4(c.shaftIntensity, Float(time.truncatingRemainder(dividingBy: 3600)), c.shaftPeriod, c.shaftDrift),
            shaftColor: SIMD4(c.shaftColor, 0),
            worldInverse: inverse,
            worldOrigin: SIMD4(Float(camera.origin.x), Float(camera.origin.y), 0, 0))
    }

    /// Visible on-map UI nodes, in the world but above everything else.
    static func overlayNodes(in world: SKNode) -> [SKNode] {
        world.children.filter { !$0.isHidden && $0.zPosition >= overlayDepth }
    }

    /// Hide `nodes`; returns a closure that restores exactly what it changed.
    static func hide(_ nodes: [SKNode]) -> () -> Void {
        let changed = nodes.filter { !$0.isHidden }
        changed.forEach { $0.isHidden = true }
        return { changed.forEach { $0.isHidden = false } }
    }

    /// Hide everything in the scene except the overlay nodes (and their parent chain).
    static func isolate(_ overlays: [SKNode], world: SKNode, scene: SKScene) -> () -> Void {
        let keep = Set(overlays.map { ObjectIdentifier($0) })
        let others = world.children.filter { !keep.contains(ObjectIdentifier($0)) }
            + scene.children.filter { $0 !== world }
        return hide(others)
    }
}
