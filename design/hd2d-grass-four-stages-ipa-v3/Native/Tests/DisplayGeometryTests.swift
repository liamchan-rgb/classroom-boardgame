import XCTest
import CoreGraphics
@testable import GrassLightingPrototype

final class DisplayGeometryTests: XCTestCase {
    func testCurveUsesExactLogicalEndpoints() {
        let a = CGPoint(x: 160, y: 450), b = CGPoint(x: 576, y: 450)
        let curve = RoadCurve(a: a, b: b, bend: 28)
        XCTAssertEqual(curve.point(-1), a); XCTAssertEqual(curve.point(2), b)
        XCTAssertTrue(curve.point(0.5).x.isFinite); XCTAssertLessThan(curve.distance(to: curve.point(0.5)), 0.001)
    }
    func testWorldCoordinateIndependentOfViewportAspect() {
        let geometry = WorldGeometry(), p = CGPoint(x: 0.36, y: 0.55)
        XCTAssertEqual(geometry.point(p).x, 576, accuracy: 0.001)
        XCTAssertEqual(geometry.point(p).y, 720, accuracy: 0.001)
        XCTAssertNotEqual(geometry.fitScale(view: CGSize(width: 1920, height: 1080)), geometry.fitScale(view: CGSize(width: 1440, height: 1080)))
    }
    func testProjectedShadowKeepsFootAndExtendsRightDown() {
        let sun = SunProjection(), anchor = CGPoint(x: 200, y: 450)
        let foot = sun.projectedFoot(anchorTop: anchor)
        XCTAssertEqual(foot.x, anchor.x, accuracy: 0.001); XCTAssertEqual(foot.y, 0, accuracy: 0.001)
        let crown = CGPoint(x: 200, y: 100).applying(sun.transform(anchorTop: anchor))
        XCTAssertGreaterThan(crown.x, foot.x); XCTAssertGreaterThan(crown.y, foot.y)
    }
    func testHiddenRoadsNeverReachRendererInput() {
        let graph = DisplayGraph.sample()
        XCTAssertEqual(graph.publicEdges, [DisplayEdge(a: 1, b: 2), DisplayEdge(a: 2, b: 3)])
        XCTAssertTrue(graph.nodes.filter { !$0.revealed }.allSatisfy { $0.visual == nil })
    }
    func testCommittedPresentationCannotReplay() {
        let now = Date(), curve = RoadCurve(a: .zero, b: CGPoint(x: 100, y: 0))
        let event = DemoPresentation(id: "one", start: now, duration: 2, curve: curve)
        var gate = PresentationGate()
        XCTAssertTrue(gate.accept(event, now: now)); XCTAssertFalse(gate.accept(event, now: now))
        gate.suppress(["restored"])
        XCTAssertFalse(gate.accept(DemoPresentation(id: "restored", start: now, duration: 2, curve: curve), now: now))
        XCTAssertFalse(gate.accept(DemoPresentation(id: "expired", start: now.addingTimeInterval(-10), duration: 2, curve: curve), now: now))
    }
}
