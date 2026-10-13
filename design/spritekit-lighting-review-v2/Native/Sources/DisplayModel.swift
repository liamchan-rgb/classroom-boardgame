import Foundation
import CoreGraphics

enum LightingMode: String, CaseIterable {
    case flat, sunlight, normal
    var title: String {
        switch self { case .flat: return "原始素材"; case .sunlight: return "太阳光影"; case .normal: return "局部光照" }
    }
    var next: Self { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
}

struct DisplayNode {
    let id: Int
    let point: CGPoint
    let revealed: Bool
    let visual: String?
}
struct DisplayEdge: Hashable { let a: Int; let b: Int }
struct DisplayGraph {
    let nodes: [DisplayNode]
    let edges: [DisplayEdge]
    // This is a display fixture; never an engine random seed.
    let decorationSeed: UInt64
    var publicEdges: [DisplayEdge] {
        let known = Set(nodes.filter(\.revealed).map(\.id))
        return edges.filter { known.contains($0.a) && known.contains($0.b) }
    }
    static func sample(seed: UInt64 = 17) -> Self {
        Self(nodes: [
            DisplayNode(id: 1, point: CGPoint(x: 0.10, y: 0.55), revealed: true, visual: "camp_a"),
            DisplayNode(id: 2, point: CGPoint(x: 0.36, y: 0.55), revealed: true, visual: "tower_a"),
            DisplayNode(id: 3, point: CGPoint(x: 0.62, y: 0.26), revealed: true, visual: "tower_b"),
            DisplayNode(id: 4, point: CGPoint(x: 0.62, y: 0.78), revealed: false, visual: nil),
            DisplayNode(id: 5, point: CGPoint(x: 0.90, y: 0.55), revealed: false, visual: nil)
        ], edges: [DisplayEdge(a: 1, b: 2), DisplayEdge(a: 2, b: 3), DisplayEdge(a: 2, b: 4), DisplayEdge(a: 3, b: 5)], decorationSeed: seed)
    }
}

struct WorldGeometry {
    let size = CGSize(width: 1600, height: 1600)
    func point(_ normalized: CGPoint) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: (1 - normalized.y) * size.height)
    }
    func fitScale(view: CGSize) -> CGFloat {
        max((size.width + 180) / max(1, view.width), (1100 + 180) / max(1, view.height))
    }
}

struct RoadCurve {
    let a: CGPoint; let c1: CGPoint; let c2: CGPoint; let b: CGPoint
    init(a: CGPoint, b: CGPoint, bend: CGFloat = 28) {
        self.a = a; self.b = b
        let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
        let nx = length > 0 ? -dy / length : 0, ny = length > 0 ? dx / length : 0
        let offset = min(abs(bend), length * 0.10) * (bend < 0 ? -1 : 1)
        c1 = CGPoint(x: a.x + dx / 3 + nx * offset, y: a.y + dy / 3 + ny * offset)
        c2 = CGPoint(x: a.x + dx * 2 / 3 - nx * offset * 0.45, y: a.y + dy * 2 / 3 - ny * offset * 0.45)
    }
    func point(_ raw: Double) -> CGPoint {
        let t = CGFloat(min(1, max(0, raw))), s = 1 - t
        return CGPoint(x: s*s*s*a.x + 3*s*s*t*c1.x + 3*s*t*t*c2.x + t*t*t*b.x,
                       y: s*s*s*a.y + 3*s*s*t*c1.y + 3*s*t*t*c2.y + t*t*t*b.y)
    }
    func tangent(_ t: Double) -> CGPoint {
        let p = point(t - 0.002), q = point(t + 0.002), length = hypot(q.x-p.x, q.y-p.y)
        return length > 0 ? CGPoint(x: (q.x-p.x)/length, y: (q.y-p.y)/length) : CGPoint(x: 1, y: 0)
    }
    func distance(to point: CGPoint) -> CGFloat {
        (0...60).map { t in let p = self.point(Double(t)/60); return hypot(p.x-point.x, p.y-point.y) }.min() ?? .infinity
    }
}

struct DemoPresentation {
    let id: String
    let start: Date
    let duration: TimeInterval
    let curve: RoadCurve
    var end: Date { start.addingTimeInterval(duration) }
}
struct PresentationGate {
    private var consumed: Set<String> = []
    mutating func accept(_ event: DemoPresentation, now: Date) -> Bool {
        guard consumed.insert(event.id).inserted else { return false }
        return event.duration > 0 && event.end > now
    }
    mutating func suppress(_ ids: [String]) { consumed.formUnion(ids) }
}

struct DisplayRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 32) / CGFloat(UInt32.max)
    }
}

// A 2D projection of the opaque silhouette onto the ground. It is not a physics shadow.
struct SunProjection {
    let dx: CGFloat = 0.85
    let dy: CGFloat = 0.40 // UIKit image space: positive down.
    func transform(anchorTop: CGPoint) -> CGAffineTransform {
        CGAffineTransform(a: 1, b: 0, c: -dx, d: -dy, tx: dx * anchorTop.y, ty: dy * anchorTop.y)
    }
    func projectedFoot(anchorTop: CGPoint) -> CGPoint { anchorTop.applying(transform(anchorTop: anchorTop)) }
}
