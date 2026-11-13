import XCTest
import UIKit
@testable import MeadowJourney

final class TrailTests: XCTestCase {
    private let trail = Trail(points: [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0), CGPoint(x: 30, y: 40)])

    func testArcLengthInterpolationAndClamping() {
        XCTAssertEqual(trail.length, 70, accuracy: 0.001)
        XCTAssertEqual(trail.point(at: -10), CGPoint(x: 0, y: 0))
        XCTAssertEqual(trail.point(at: 50), CGPoint(x: 30, y: 20))
        XCTAssertEqual(trail.point(at: 100), CGPoint(x: 30, y: 40))
    }

    func testTapProjectsOntoNearestRoadSegment() {
        XCTAssertEqual(trail.distance(nearestTo: CGPoint(x: 12, y: -8)), 12, accuracy: 0.001)
        XCTAssertEqual(trail.distance(nearestTo: CGPoint(x: 38, y: 25)), 55, accuracy: 0.001)
    }

    func testRepeatedPointsDoNotProduceNaN() {
        let repeated = Trail(points: [.zero, .zero, CGPoint(x: 10, y: 0)])
        XCTAssertEqual(repeated.point(at: 5), CGPoint(x: 5, y: 0))
        XCTAssertEqual(repeated.distance(nearestTo: CGPoint(x: 5, y: 9)), 5, accuracy: 0.001)
    }

    func testMovementUsesDistanceAndReflectsAtEndpoint() {
        var hero = Traveler(distance: 65, direction: 1, speed: 10)
        hero.advance(by: 1, on: trail)
        XCTAssertEqual(hero.distance, 65, accuracy: 0.001)
        XCTAssertEqual(hero.direction, -1)
        hero.advance(by: 30, on: trail)
        XCTAssertEqual(hero.distance, 45, accuracy: 0.001)
        XCTAssertEqual(hero.direction, -1)
    }

    func testDestinationStopsWithoutOvershootingOrResuming() {
        var hero = Traveler(distance: 50, direction: 1, destination: 22, speed: 40)
        hero.advance(by: 1, on: trail)
        XCTAssertEqual(hero.distance, 22, accuracy: 0.001)
        XCTAssertTrue(hero.isWaiting)
        hero.advance(by: 1, on: trail)
        XCTAssertEqual(hero.distance, 22, accuracy: 0.001)
    }

    func testReferencePositionsAreOnTheRoad() {
        for point in [CGPoint(x: 440, y: 444), CGPoint(x: 555, y: 441), CGPoint(x: 744, y: 209)] {
            let projected = Trail.meadow.point(at: Trail.meadow.distance(nearestTo: point))
            XCTAssertEqual(projected.x, point.x, accuracy: 0.001)
            XCTAssertEqual(projected.y, point.y, accuracy: 0.001)
        }
    }

    func testBranchToBranchRoutePassesThroughSharedJunction() {
        let network = TrailNetwork(roads: SceneDefinition.load().roads)
        let route = network.route(from: CGPoint(x: 982, y: 430), to: CGPoint(x: 735, y: 578))
        XCTAssertEqual(route.points.first!, CGPoint(x: 982, y: 430))
        XCTAssertEqual(route.points.last!, CGPoint(x: 735, y: 578))
        XCTAssertTrue(route.points.contains(CGPoint(x: 555, y: 441)))
        for point in route.points { XCTAssertLessThan(network.project(point).error, 0.01) }
    }

    func testSameRoadDestinationDoesNotDetourToAnEndpoint() {
        let network = TrailNetwork(roads: SceneDefinition.load().roads)
        let start = CGPoint(x: 383, y: 448)
        let end = CGPoint(x: 503, y: 445)
        let edge = network.edges[0].trail
        let expected = abs(edge.distance(nearestTo: end) - edge.distance(nearestTo: start))
        XCTAssertEqual(network.route(from: start, to: end).length, expected, accuracy: 0.01)
    }

    func testPauseResumePreservesOrderedDestinationAndOtherTravelers() {
        var simulation = JourneySimulation(network: TrailNetwork(roads: SceneDefinition.load().roads))
        simulation.orderSelected(to: CGPoint(x: 982, y: 430))
        simulation.advance(1)
        let destination = simulation.travelers[0].destination
        let point = simulation.point(for: 0)
        simulation.togglePlayback()
        simulation.advance(5)
        XCTAssertEqual(simulation.point(for: 0), point)
        simulation.togglePlayback()
        XCTAssertEqual(simulation.travelers[0].destination, destination)
        XCTAssertTrue(simulation.travelers[1].isWaiting)
        XCTAssertTrue(simulation.travelers[2].isWaiting)
        simulation.advance(1)
        XCTAssertNotEqual(simulation.point(for: 0), point)
    }

    func testNewOrderWhileExplicitlyPausedWaitsForResume() {
        var simulation = JourneySimulation(network: TrailNetwork(roads: SceneDefinition.load().roads))
        simulation.togglePlayback()
        simulation.togglePlayback()
        simulation.orderSelected(to: CGPoint(x: 735, y: 578))
        XCTAssertFalse(simulation.isPlaying)
        XCTAssertNotNil(simulation.travelers[0].destination)
        simulation.togglePlayback()
        XCTAssertTrue(simulation.isPlaying)
        XCTAssertEqual(simulation.mode, .destination)
    }

    func testDiscoveryRouteStopsExactlyAtTheDestination() {
        var simulation = JourneySimulation(network: TrailNetwork(roads: SceneDefinition.load().roads))
        simulation.selected = 2
        simulation.orderSelected(to: CGPoint(x: 735, y: 578))
        simulation.advance(100)
        XCTAssertEqual(simulation.point(for: 2), CGPoint(x: 735, y: 578))
        XCTAssertFalse(simulation.isPlaying)
    }

    func testIndependentRetinaAssetsAreBundledWithoutFlattenedMap() {
        XCTAssertNil(UIImage(named: "MapBackground"))
        for name in ["Hero1Directions", "Hero2Directions", "Hero3Directions"] {
            XCTAssertEqual(UIImage(named: name)?.cgImage?.width, 1536)
            XCTAssertEqual(UIImage(named: name)?.cgImage?.height, 1536)
        }
        for name in ["OakA", "OakB", "WatchTower", "CampTent", "MeadowGround", "Banner"] {
            XCTAssertNotNil(UIImage(named: name))
        }
    }
}
