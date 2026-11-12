import UIKit
import Metal
import QuartzCore
import simd

/// GPU drawing of the procedural skill primitives (`MeadowSkillProcedural.Prim`).
///
/// The primitives are still computed on the CPU (a few hundred closed-form shapes per frame - cheap), but they are no longer rasterised
/// with CoreGraphics: every shape becomes a few triangles and the whole frame is drawn in one Metal pass. Glows, streaks, rings, arcs and
/// ribbons are shaded analytically in the fragment shader (soft edges for free), light is additive, solid shapes use normal blending.
/// The shader is compiled from source at run time, so no `.metal` file has to be in the project; if Metal or the shader is unavailable
/// `MeadowSkillGPUView.init` returns nil and the stage keeps the CoreGraphics path.
enum MeadowSkillGPUGeometry {
    /// Must match `struct V` in the shader (64 bytes).
    struct Vertex {
        var pos: SIMD2<Float>
        var loc: SIMD2<Float>
        var col: SIMD4<Float>
        var p: SIMD4<Float>
        var q: SIMD2<Float>
    }
    struct Run { let additive: Bool; var start: Int; var count: Int }
    struct Frame { var vertices: [Vertex] = []; var runs: [Run] = []; var flash: (color: MeadowSkillProcedural.RGB, alpha: Double)? = nil }

    private static func rgba(_ c: MeadowSkillProcedural.RGB, _ a: Double) -> SIMD4<Float> {
        SIMD4<Float>(Float(c.r / 255), Float(c.g / 255), Float(c.b / 255), Float(min(1, max(0, a))))
    }

    private static func push(_ frame: inout Frame, _ v: [Vertex], additive: Bool) {
        let start = frame.vertices.count
        frame.vertices += v
        if var last = frame.runs.last, last.additive == additive, last.start + last.count == start {
            last.count += v.count; frame.runs[frame.runs.count - 1] = last
        } else { frame.runs.append(Run(additive: additive, start: start, count: v.count)) }
    }

    /// Two triangles from four corners given as (world position, local coordinates) in the order (-,-) (+,-) (-,+) (+,+).
    private static func quad(_ c: [(SIMD2<Float>, SIMD2<Float>)], _ col: SIMD4<Float>, _ p: SIMD4<Float>, _ q: SIMD2<Float>) -> [Vertex] {
        func v(_ i: Int) -> Vertex { Vertex(pos: c[i].0, loc: c[i].1, col: col, p: p, q: q) }
        return [v(0), v(1), v(2), v(2), v(1), v(3)]
    }

    private static func rotated(_ x: Double, _ y: Double, _ a: Double) -> (Double, Double) {
        let c = cos(a), s = sin(a); return (x * c - y * s, x * s + y * c)
    }

    /// Corners of the box [-hx, hx] x [-hy, hy] around (cx, cy), rotated by `rot`; the local coordinates are either normalised (glow) or in world units.
    private static func box(_ cx: Double, _ cy: Double, _ hx: Double, _ hy: Double, _ rot: Double, normalised: Bool) -> [(SIMD2<Float>, SIMD2<Float>)] {
        var out: [(SIMD2<Float>, SIMD2<Float>)] = []
        for (sy, sx) in [(-1.0, -1.0), (-1.0, 1.0), (1.0, -1.0), (1.0, 1.0)] {
            let (rx, ry) = rotated(sx * hx, sy * hy, rot)
            let loc = normalised ? SIMD2<Float>(Float(sx), Float(sy)) : SIMD2<Float>(Float(sx * hx), Float(sy * hy))
            out.append((SIMD2<Float>(Float(cx + rx), Float(cy + ry)), loc))
        }
        return out
    }

    private static func ribbon(_ frame: inout Frame, _ pts: [MeadowSkillProcedural.Pt], _ ws: [Double], _ c: MeadowSkillProcedural.RGB, _ a: Double, additive: Bool, grow: Double) {
        guard pts.count >= 2, pts.count == ws.count else { return }
        var left: [SIMD2<Float>] = [], right: [SIMD2<Float>] = [], hard: Float = 0.8
        for i in 0..<pts.count {
            let p0 = pts[max(0, i - 1)], p1 = pts[min(pts.count - 1, i + 1)]
            var dx = p1.x - p0.x, dy = p1.y - p0.y
            let len = hypot(dx, dy)
            if len < 1e-9 { dx = 1; dy = 0 } else { dx /= len; dy /= len }
            let half = max(0.25, ws[i] / 2 + grow), outer = half + 1.0
            hard = Float(half / outer)
            left.append(SIMD2<Float>(Float(pts[i].x - dy * outer), Float(pts[i].y + dx * outer)))
            right.append(SIMD2<Float>(Float(pts[i].x + dy * outer), Float(pts[i].y - dx * outer)))
        }
        let col = rgba(c, a), p = SIMD4<Float>(hard, 0, 0, 2)
        var v: [Vertex] = []
        for i in 0..<(pts.count - 1) {
            let l0 = Vertex(pos: left[i], loc: SIMD2<Float>(-1, 0), col: col, p: p, q: .zero), r0 = Vertex(pos: right[i], loc: SIMD2<Float>(1, 0), col: col, p: p, q: .zero)
            let l1 = Vertex(pos: left[i + 1], loc: SIMD2<Float>(-1, 0), col: col, p: p, q: .zero), r1 = Vertex(pos: right[i + 1], loc: SIMD2<Float>(1, 0), col: col, p: p, q: .zero)
            v += [l0, r0, l1, l1, r0, r1]
        }
        push(&frame, v, additive: additive)
    }

    static func build(_ prims: [MeadowSkillProcedural.Prim]) -> Frame {
        var f = Frame()
        for prim in prims {
            switch prim {
            case let .glow(x, y, rx, ry, c, a):
                guard a > 0.004, rx > 0.3, ry > 0.3 else { continue }
                push(&f, quad(box(x, y, rx, ry, 0, normalised: true), rgba(c, a), SIMD4<Float>(0, 0, 0, 0), .zero), additive: true)
            case let .streak(x, y, rx, ry, ang, c, a):
                guard a > 0.004, rx > 0.3, ry > 0.3 else { continue }
                push(&f, quad(box(x, y, rx, ry, ang, normalised: true), rgba(c, a), SIMD4<Float>(0, 0, 0, 0), .zero), additive: true)
            case let .ring(x, y, rx, ry, w, c, a, rot):
                guard a > 0.004, rx > 0.5, ry > 0.5 else { continue }
                let m = max(1.0, w * 2.6) / 2 + 2
                push(&f, quad(box(x, y, rx + m, ry + m, rot, normalised: false), rgba(c, a), SIMD4<Float>(Float(rx), Float(ry), Float(max(0.6, w) / 2), 1), .zero), additive: true)
            case let .arc(x, y, rx, ry, a0, a1, w, c, a):
                guard a > 0.004, rx > 0.5, ry > 0.5, a1 > a0 else { continue }
                let m = max(1.0, w * 2.6) / 2 + 2
                push(&f, quad(box(x, y, rx + m, ry + m, 0, normalised: false), rgba(c, a), SIMD4<Float>(Float(rx), Float(ry), Float(max(0.6, w) / 2), 1), SIMD2<Float>(Float(a0), Float(a1 - a0))), additive: true)
            case let .ribbon(pts, ws, c, a, add, soft):
                guard a > 0.004 else { continue }
                if soft > 1.4 { ribbon(&f, pts, ws, c, a * 0.32, additive: add, grow: soft * 0.9) }
                ribbon(&f, pts, ws, c, a, additive: add, grow: 0)
            case let .flash(c, a):
                if a > 0.004, a > (f.flash?.alpha ?? 0) { f.flash = (c, a) }
            }
        }
        return f
    }
}

final class MeadowSkillGPUView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    /// Developer switch: `defaults write ... MeadowGPUEffects -bool NO` falls back to the CoreGraphics drawing.
    static var enabled: Bool { UserDefaults.standard.object(forKey: "MeadowGPUEffects") as? Bool ?? true }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let additive: MTLRenderPipelineState
    private let mix: MTLRenderPipelineState
    private var rect: CGRect
    private var resolution: CGFloat = 1.5
    private var hadContent = false
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    init?(worldRect: CGRect) {
        guard Self.enabled, let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.source, options: nil),
              let vertex = library.makeFunction(name: "skillVertex"), let fragment = library.makeFunction(name: "skillFragment") else { return nil }
        func pipeline(additive: Bool) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = vertex; d.fragmentFunction = fragment
            let a = d.colorAttachments[0]!
            a.pixelFormat = .bgra8Unorm; a.isBlendingEnabled = true
            a.rgbBlendOperation = .add; a.alphaBlendOperation = .add
            if additive {
                // Light: adds to the picture behind (premultiplied colour with alpha left alone, so the layer adds instead of covering).
                a.sourceRGBBlendFactor = .one; a.destinationRGBBlendFactor = .one
                a.sourceAlphaBlendFactor = .zero; a.destinationAlphaBlendFactor = .one
            } else {
                a.sourceRGBBlendFactor = .one; a.destinationRGBBlendFactor = .oneMinusSourceAlpha
                a.sourceAlphaBlendFactor = .one; a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let add = pipeline(additive: true), let normal = pipeline(additive: false) else { return nil }
        self.device = device; self.queue = queue; self.additive = add; self.mix = normal; self.rect = worldRect
        super.init(frame: worldRect)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false; isHidden = true
        let layer = metalLayer
        layer.device = device; layer.pixelFormat = .bgra8Unorm; layer.framebufferOnly = true; layer.isOpaque = false
        setResolution(1.5)
    }
    required init?(coder: NSCoder) { return nil }

    /// The world rectangle this layer covers (it grows with the battle formation's world zoom).
    func setWorldRect(_ worldRect: CGRect) {
        guard worldRect != rect else { return }
        rect = worldRect; frame = worldRect; setResolution(resolution)
    }

    /// Drawable pixels per world unit.
    func setResolution(_ k: CGFloat) {
        resolution = k
        let size = CGSize(width: (rect.width * k).rounded(), height: (rect.height * k).rounded())
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
    }

    /// Draws one frame of primitives; returns the strongest full-screen flash among them (the stage shows it on a pane-wide overlay).
    @discardableResult
    func draw(_ prims: [MeadowSkillProcedural.Prim]) -> (color: MeadowSkillProcedural.RGB, alpha: Double)? {
        let frame = MeadowSkillGPUGeometry.build(prims)
        if frame.vertices.isEmpty && !hadContent { isHidden = true; return frame.flash }
        isHidden = false
        guard let drawable = metalLayer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return frame.flash }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        if let encoder = commands.makeRenderCommandEncoder(descriptor: pass) {
            if !frame.vertices.isEmpty,
               let buffer = device.makeBuffer(bytes: frame.vertices, length: frame.vertices.count * MemoryLayout<MeadowSkillGPUGeometry.Vertex>.stride, options: .storageModeShared) {
                var r = SIMD4<Float>(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height))
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&r, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
                for run in frame.runs {
                    encoder.setRenderPipelineState(run.additive ? additive : mix)
                    encoder.drawPrimitives(type: .triangle, vertexStart: run.start, vertexCount: run.count)
                }
            }
            encoder.endEncoding()
        }
        commands.present(drawable)
        commands.commit()
        hadContent = !frame.vertices.isEmpty
        return frame.flash
    }

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float2 pos; float2 loc; float4 col; float4 p; float2 q; };
    struct O { float4 position [[position]]; float2 loc; float4 col; float4 p; float2 q; };
    vertex O skillVertex(uint vid [[vertex_id]], const device V *verts [[buffer(0)]], constant float4 &rect [[buffer(1)]]) {
        V v = verts[vid]; O o;
        o.position = float4((v.pos.x - rect.x) / rect.z * 2.0 - 1.0, 1.0 - (v.pos.y - rect.y) / rect.w * 2.0, 0.0, 1.0);
        o.loc = v.loc; o.col = v.col; o.p = v.p; o.q = v.q;
        return o;
    }
    fragment float4 skillFragment(O in [[stage_in]]) {
        int kind = int(in.p.w + 0.5);
        float a = 0.0;
        if (kind == 0) {
            // glow and streak: radial falloff (1 - d)^1.4 over the quad
            a = pow(max(0.0, 1.0 - length(in.loc)), 1.4);
        } else if (kind == 1) {
            // ring and arc on an ellipse: in.p = (rx, ry, half line width), in.q = (start angle, span) for arcs
            float2 n = in.loc / float2(in.p.x, in.p.y);
            float rho = max(length(n), 1e-4);
            float2 g = float2(n.x / in.p.x, n.y / in.p.y) / rho;
            float dist = (rho - 1.0) / max(length(g), 1e-5);
            float ad = fabs(dist);
            float hw = in.p.z, hw2 = max(0.5, hw * 2.6);
            float core = 1.0 - smoothstep(hw - 0.7, hw + 0.7, ad);
            float halo = 0.28 * (1.0 - smoothstep(hw2 - 0.7, hw2 + 0.7, ad));
            a = core + halo;
            if (in.q.y > 0.0) {
                float u = atan2(n.y, n.x) - in.q.x;
                u = u - 6.2831853 * floor(u / 6.2831853);
                float span = in.q.y;
                float m = (span >= 6.28) ? 1.0 : smoothstep(0.0, 0.05, u) * (1.0 - smoothstep(span - 0.05, span, u));
                if (u > span && span < 6.28) { m = 0.0; }
                a *= m;
            }
        } else {
            // ribbon: in.loc.x runs -1...1 across the strip; solid up to in.p.x, then a one pixel feather
            a = 1.0 - smoothstep(in.p.x, 1.0, fabs(in.loc.x));
        }
        float al = in.col.a * a;
        return float4(in.col.rgb * al, al);
    }
    """
}
