import XCTest
@testable import ClassroomGameCore

final class MeadowBridgeTests:XCTestCase {
    let now=Date(timeIntervalSince1970:1000)
    func testImpactUsesBeforeValuesAndNeverExecutesAgain() throws {
        let (catalog,state)=try fixture(scripted:[3])
        let engine=try GameEngine(catalog:catalog,state:state)
        let receipt=try engine.apply(.attack(actor:"p1",target:"m1"))
        var ledger=PresentationLedger()
        let event=try XCTUnwrap(ledger.submit(receipt,catalog:catalog,now:now))
        var frame=try PVEPlaySession(engine:engine).publicFrame();frame.presentations=ledger.pending
        let archive=engine.archive
        XCTAssertEqual(MeadowPublicProjection.units(frame,at:now.addingTimeInterval(0.3)).first { $0.id == "m1" }?.health,state.units["m1"]?.health)
        XCTAssertEqual(MeadowPublicProjection.units(frame,at:now.addingTimeInterval(0.5)).first { $0.id == "m1" }?.health,receipt.after.units["m1"]?.health)
        for i in 0..<200 { _=MeadowPublicProjection.participants(frame,at:now.addingTimeInterval(Double(i)/60)) }
        XCTAssertEqual(archive,engine.archive)
        ledger.suppressHistory(engine.history)
        XCTAssertNil(try ledger.submit(receipt,catalog:catalog,now:event.end))
    }
    func testQueuedReceiptsDoNotJumpToFutureResult() throws {
        let (catalog,state)=try fixture(scripted:[2,2])
        let engine=try GameEngine(catalog:catalog,state:state)
        var ledger=PresentationLedger()
        let first=try engine.apply(.attack(actor:"p1",target:"m1"))
        try ledger.submit(first,catalog:catalog,now:now)
        let second=try engine.apply(.attack(actor:"p1",target:"m1"))
        try ledger.submit(second,catalog:catalog,now:now)
        var frame=try PVEPlaySession(engine:engine).publicFrame();frame.presentations=ledger.pending
        XCTAssertEqual(MeadowPublicProjection.units(frame,at:now.addingTimeInterval(0.6)).first { $0.id == "m1" }?.health,first.after.units["m1"]?.health)
        XCTAssertEqual(MeadowPublicProjection.units(frame,at:now.addingTimeInterval(1.5)).first { $0.id == "m1" }?.health,second.before.units["m1"]?.health)
    }
    func testBattleStageExcludesVisibleNonParticipantsAndHiddenEnemies() throws {
        let (catalog,initial)=try fixture()
        var state=initial
        state.units["nearby"]=try GameFactory.monster(id:"nearby",templateID:"wolf",nodeID:1,catalog:catalog)
        state.units["hidden"]=try GameFactory.monster(id:"hidden",templateID:"ruinDragon",nodeID:4,catalog:catalog)
        let frame=try PVEPlaySession(engine:GameEngine(catalog:catalog,state:state)).publicFrame()
        XCTAssertTrue(frame.snapshot.units.contains { $0.id == "nearby" })
        XCTAssertEqual(Set(MeadowPublicProjection.participants(frame,at:now).map(\.id)),Set(["p1","p2","m1"]))
        XCTAssertFalse(String(decoding:try JSONEncoder().encode(frame),as:UTF8.self).contains("hidden"))
    }
    func testArrivalKeepsMapUntilActualCommittedMoveEnds() throws {
        let catalog=try GameCatalog.initial()
        let state=try PVEGameFactory.make(players:[PlayerSetup(id:"custom-id",name:"学生",classID:"adventurer")],scenario:.playerTwenty,seed:21,catalog:catalog)
        let engine=try GameEngine(catalog:catalog,state:state)
        let receipt=try engine.apply(.move(actors:["custom-id"],path:[1,2]))
        var ledger=PresentationLedger();let event=try XCTUnwrap(ledger.submit(receipt,catalog:catalog,now:now))
        var frame=try PVEPlaySession(engine:engine).publicFrame();frame.presentations=ledger.pending
        XCTAssertTrue(event.opensBattleAfterArrival)
        XCTAssertFalse(MeadowPublicProjection.battle(frame,at:now.addingTimeInterval(0.7)))
        XCTAssertTrue(MeadowPublicProjection.battle(frame,at:event.end))
        let unit=try XCTUnwrap(frame.snapshot.units.first { $0.id == "custom-id" })
        XCTAssertEqual(MeadowPublicProjection.point(unit,frame:frame,at:now.addingTimeInterval(-1)),event.mapMoves.first?.points.first)
        XCTAssertEqual(MeadowPublicProjection.point(unit,frame:frame,at:event.end),event.mapMoves.first?.points.last)
    }
    func testUnknownSpeciesRemainExplicitFallback() {
        XCTAssertNil(MeadowPublicProjection.recognizedMonster("custom-boss"))
        XCTAssertEqual(MeadowPublicProjection.recognizedMonster("wolf"),"wolf")
    }
}
