import XCTest
@testable import ClassroomGameCore

final class MapPresentationTests:XCTestCase {
    func testCameraKeepsFocusAndClampsOnlyDisplayCoordinates() {
        let camera = MapCamera(x:0.25,y:0.7,zoom:2)
        XCTAssertEqual(camera.screen(MapPoint(x:0.25,y:0.7),width:800,height:500),MapPoint(x:400,y:250))
        XCTAssertEqual(camera.panned(x:-10,y:10).center,MapPoint(x:0,y:1))
        XCTAssertEqual(camera.scaled(by:100).zoom,3)
        XCTAssertEqual(MapCamera(x:.nan,y:.infinity,zoom:.nan),MapCamera())
    }
    func testCoincidentOffscreenPlayersStaySeparateAndPointTowardTheirPosition() {
        let points = (1...7).map { ("p\($0)",MapPoint(x:2000,y:200)) }
        let markers = MapDisplayGeometry.edgeMarkers(points:points,width:800,height:500,size:44)
        XCTAssertEqual(markers.count,7)
        XCTAssertTrue(markers.allSatisfy { $0.edge == .right && abs($0.directionDegrees) < 10 })
        let positions = markers.map(\.point.y).sorted()
        for i in 1..<positions.count { XCTAssertGreaterThanOrEqual(positions[i]-positions[i-1],44) }
        XCTAssertTrue(markers.allSatisfy { $0.point.x > 700 && $0.point.x < 800 && $0.point.y >= 52 && $0.point.y <= 448 })
    }
    func testSmallTeacherViewportGroupsCrowdedMarkersWithoutLosingPlayers() {
        let points = (1...7).map { ("p\($0)",MapPoint(x:-1000,y:140)) }
        let markers = MapDisplayGeometry.edgeMarkers(points:points,width:500,height:320,size:44)
        XCTAssertLessThan(markers.count,7)
        XCTAssertEqual(Set(markers.flatMap(\.unitIDs)),Set(points.map(\.0)))
        let positions = markers.map(\.point.y).sorted()
        for i in 1..<positions.count { XCTAssertGreaterThanOrEqual(positions[i]-positions[i-1],44) }
        XCTAssertTrue(markers.allSatisfy { $0.point.y > 80 && $0.point.y < 240 })
    }
    func testCommittedGroupMoveUsesActualEncounterStopsAndNeverReplays() throws {
        let catalog = try GameCatalog.initial()
        let state = try PVEGameFactory.make(players:[PlayerSetup(id:"p1",name:"甲",classID:"adventurer"),PlayerSetup(id:"p2",name:"乙",classID:"ranger")],seed:19,catalog:catalog)
        let engine = try GameEngine(catalog:catalog,state:state)
        let receipt = try engine.apply(.move(actors:["p1","p2"],path:[1,2,4]))
        let archive = engine.archive
        var ledger = PresentationLedger()
        let now = Date(timeIntervalSince1970:100)
        let event = try XCTUnwrap(ledger.submit(receipt,catalog:catalog,now:now))
        XCTAssertTrue(event.opensBattleAfterArrival)
        XCTAssertEqual(event.mapMoves.map(\.unitID),["p1","p2"])
        for move in event.mapMoves {
            XCTAssertEqual(move.points,[MapPoint(x:0.1,y:0.55),MapPoint(x:0.36,y:0.55)])
            XCTAssertEqual(move.position(progress:0),move.points.first)
            XCTAssertEqual(move.position(progress:1),move.points.last)
            XCTAssertEqual(move.position(progress:10),move.points.last)
            XCTAssertEqual(move.position(progress:0.5)?.x ?? 0,0.23,accuracy:0.0001)
        }
        for _ in 0..<20 { XCTAssertNil(try ledger.submit(receipt,catalog:catalog,now:now)) }
        ledger.suppressHistory(engine.history)
        XCTAssertTrue(ledger.pending.isEmpty)
        XCTAssertNil(try ledger.submit(receipt,catalog:catalog,now:now))
        XCTAssertEqual(engine.archive,archive)
    }
    func testCommittedRoundTripStillAnimatesEveryActualStop() throws {
        let (catalog,initial) = try fixture()
        var state = initial
        state.map.nodes[0].x = 0.1; state.map.nodes[0].y = 0.5
        state.map.nodes[1].x = 0.5; state.map.nodes[1].y = 0.5
        let engine = try GameEngine(catalog:catalog,state:state)
        let receipt = try engine.apply(.move(actors:["p1"],path:[2,1,2]))
        var ledger = PresentationLedger()
        let event = try XCTUnwrap(ledger.submit(receipt,catalog:catalog,now:Date()))
        let move = try XCTUnwrap(event.mapMoves.first)
        XCTAssertEqual(move.points.count,3)
        XCTAssertEqual(move.points.first,move.points.last)
        XCTAssertEqual(move.position(progress:0.5)?.x ?? 0,0.1,accuracy:0.0001)
        XCTAssertFalse(event.opensBattleAfterArrival)
        XCTAssertEqual(engine.state.units["p1"]?.ap,1)
    }
    func testAvailabilityAndInventoryReadActualStateWithoutPrivateSelectionOrDice() throws {
        let (catalog,initial) = try fixture()
        var state = initial
        let gear = try XCTUnwrap(catalog.items.first { $0.kind == .equipment })
        state.units["p1"]?.inventory = ["smallPotion":2,"revivalStone":1,gear.id:1]
        let play = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        let archive = play.engine.archive
        let details = try XCTUnwrap(play.publicFrame().currentDetails)
        XCTAssertEqual(details.items.first { $0.id == "smallPotion" }?.quantity,2)
        XCTAssertEqual(details.items.first { $0.id == "smallPotion" }?.available,true)
        XCTAssertEqual(details.items.first { $0.id == gear.id }?.unavailableReason,"战斗中不可换装")
        XCTAssertEqual(details.items.first { $0.id == "revivalStone" }?.available,false)
        play.choose(.skill(details.skills[0].id)); play.selectTarget(.unit("m1")); play.toggleReward("p2")
        XCTAssertEqual(try play.publicFrame().currentDetails,details)
        XCTAssertEqual(play.engine.archive,archive)
        state.units["p1"]?.ap = 0
        let unavailable = try PVEPlaySession(engine:GameEngine(catalog:catalog,state:state)).publicFrame().currentDetails!
        XCTAssertTrue(unavailable.skills.allSatisfy { $0.available == false && $0.unavailableReason == "行动点不足" })
        XCTAssertEqual(unavailable.items.first { $0.id == "smallPotion" }?.unavailableReason,"行动点不足")
    }
    func testCameraDoesNotRevealHiddenNodesOrChangeSaveData() throws {
        let (catalog,state) = try fixture(kind:nil)
        let play = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        let before = play.engine.archive
        var frame = try play.publicFrame()
        frame.camera = MapCamera(x:1,y:1,zoom:3); frame.cameraFocusID = "p2"; frame.itemPage = 3
        XCTAssertFalse(frame.snapshot.units.contains { $0.id == "m1" })
        XCTAssertTrue(frame.snapshot.nodes.filter { !$0.revealed }.allSatisfy { $0.kind == nil })
        XCTAssertFalse(frame.snapshot.nodes.contains { $0.id == 4 })
        XCTAssertEqual(play.engine.archive,before)
    }
}
