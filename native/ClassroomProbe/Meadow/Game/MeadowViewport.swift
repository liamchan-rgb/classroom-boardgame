import SpriteKit
import simd

/// Capture the foreground's actual projection, including SKScene's view mapping.
/// The receiver never reconstructs a second camera from a separate zoom value.
struct MeadowViewport: Equatable {
    let size: CGSize
    let origin: CGPoint
    let xAxis: CGVector
    let yAxis: CGVector

    init(world: SKNode, scene: SKScene, view: SKView) {
        func project(_ p: CGPoint) -> CGPoint {
            scene.convertPoint(toView: world.convert(CGPoint(x: p.x, y: -p.y), to: scene))
        }
        size = view.bounds.size
        origin = project(.zero)
        let x = project(CGPoint(x: 32, y: 0)), y = project(CGPoint(x: 0, y: 32))
        xAxis = CGVector(dx: (x.x - origin.x) / 32, dy: (x.y - origin.y) / 32)
        yAxis = CGVector(dx: (y.x - origin.x) / 32, dy: (y.y - origin.y) / 32)
    }

    /// SKRenderer uses a resizeFill scene whose point size matches the view.
    /// Capture its actual node transform without requiring a second SKView.
    init(world: SKNode, scene: SKScene, viewSize: CGSize) {
        func project(_ p: CGPoint) -> CGPoint {
            let point = world.convert(CGPoint(x: p.x, y: -p.y), to: scene)
            return CGPoint(x: point.x, y: viewSize.height - point.y)
        }
        size = viewSize
        origin = project(.zero)
        let x = project(CGPoint(x: 32, y: 0)), y = project(CGPoint(x: 0, y: 32))
        xAxis = CGVector(dx: (x.x - origin.x) / 32, dy: (x.y - origin.y) / 32)
        yAxis = CGVector(dx: (y.x - origin.x) / 32, dy: (y.y - origin.y) / 32)
    }

    init(size: CGSize, center: CGPoint, scale: CGFloat) {
        self.size = size
        origin = CGPoint(x: size.width / 2 - center.x * scale, y: size.height / 2 - center.y * scale)
        xAxis = CGVector(dx: scale, dy: 0); yAxis = CGVector(dx: 0, dy: scale)
    }

    func project(_ point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x * xAxis.dx + point.y * yAxis.dx,
                y: origin.y + point.x * xAxis.dy + point.y * yAxis.dy)
    }

    var matrix: simd_float4x4 {
        let up = ShadowLabMath.cameraUp
        let sx = Float(2 / max(1, size.width)), sy = Float(-2 / max(1, size.height))
        func column(_ axis: CGVector, _ factor: Float) -> SIMD4<Float> {
            SIMD4(Float(axis.dx) * factor * sx, Float(axis.dy) * factor * sy, 0, 0)
        }
        let reference = project(CGPoint(x: 640, y: 360))
        return simd_float4x4(columns: (column(xAxis, 32), column(yAxis, -32 * up.y), column(yAxis, -32 * up.z),
            SIMD4(Float(reference.x) * sx - 1, Float(reference.y) * sy + 1, 0.5, 1)))
    }
}
