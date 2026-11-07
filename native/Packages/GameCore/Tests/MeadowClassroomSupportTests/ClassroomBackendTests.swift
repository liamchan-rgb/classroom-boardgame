import XCTest
import ClassroomGameCore
import MeadowWorldSupport
@testable import MeadowClassroomSupport

final class ClassroomBackendTests:XCTestCase {
    func fixture()throws->ClassroomGameBackend {
        let backend=ClassroomGameBackend()
        let layout=try backend.generate(.suggested(total:10,seed:31827),role:.teacher)
        try backend.install(MeadowCampaignSession.new(layout:layout),role:.teacher)
        return backend
    }
    func testDisplayCannotGenerateMapsOrInstallGame()throws {
        let backend=ClassroomGameBackend()
        XCTAssertThrowsError(try backend.generate(.suggested(total:10),role:.publicDisplay))
        XCTAssertNil(backend.campaign);XCTAssertEqual(backend.surface,.waiting)
        let layout=try backend.generate(.suggested(total:10),role:.teacher)
        let c=try MeadowCampaignSession.new(layout:layout)
        XCTAssertThrowsError(try backend.install(c,role:.publicDisplay))
        XCTAssertNil(backend.campaign)
    }
    func testDisplayCannotEditRefillRewardMoveOrSelect()throws {
        let b=try fixture(),c=try XCTUnwrap(b.campaign),before=c.snapshot
        let node=try XCTUnwrap(c.engine.state.map.nodes.first{$0.kind == .combat})
        XCTAssertThrowsError(try b.configureEncounter(node:node.id,templates:["ruinDragon"],role:.publicDisplay))
        XCTAssertThrowsError(try b.refill(usingCoins:false,role:.publicDisplay))
        XCTAssertThrowsError(try b.apply(.reward(actors:["p1"],value:ResourceReward(coins:10)),role:.publicDisplay))
        XCTAssertThrowsError(try b.travel(to:c.point(at:node.id),role:.publicDisplay))
        XCTAssertThrowsError(try b.selectPlayer("p2",role:.publicDisplay))
        XCTAssertEqual(c.snapshot,before)
    }
    func testTeacherCanGenerateExactConfiguredNodeCounts()throws {
        let b=ClassroomGameBackend()
        for total in [4,10,30]{
            let config=MeadowMapConfiguration.suggested(total:total,seed:44)
            let map=try b.generate(config,role:.teacher)
            XCTAssertEqual(map.map.nodes.count,total)
            XCTAssertEqual(map.map.nodes.filter{$0.kind == .combat}.count,config.combat)
            XCTAssertEqual(map,try b.generate(config,role:.teacher))
        }
    }
    func testAdminEditsDoNotOpenAPublicEditorOrChangeRandom()throws {
        let b=try fixture(),c=try XCTUnwrap(b.campaign)
        let node=try XCTUnwrap(c.engine.state.map.nodes.first{$0.kind == .combat}),random=c.engine.state.random
        try b.configureEncounter(node:node.id,templates:["wolf"],role:.teacher)
        XCTAssertEqual(b.surface,.exploration);XCTAssertEqual(c.engine.state.random,random)
        XCTAssertEqual(c.engine.state.units.values.filter{$0.kind == .monster && $0.nodeID==node.id}.map(\.templateID),["wolf"])
    }
    func testOnlyExplicitPlayerPanelsCanBeProjected()throws {
        let b=try fixture(),c=try XCTUnwrap(b.campaign)
        try b.project(.inventory("p2"),role:.teacher);XCTAssertEqual(b.surface,.inventory("p2"))
        XCTAssertThrowsError(try b.project(.inventory("teacher-note"),role:.teacher))
        let node=try XCTUnwrap(c.engine.state.map.nodes.first{$0.kind == .combat})
        try b.project(.encounter(node.id),role:.teacher);XCTAssertEqual(b.surface,.encounter(node.id))
        let before=c.snapshot
        XCTAssertThrowsError(try b.project(.book,role:.publicDisplay))
        XCTAssertEqual(b.surface,.encounter(node.id));XCTAssertEqual(c.snapshot,before)
    }
    func testTeacherBackendAndRendererUseTheSameEngine()throws {
        let b=try fixture(),c=try XCTUnwrap(b.campaign),before=c.engine.state.units["p2"]!.coins
        try b.selectPlayer("p2",role:.teacher)
        try b.apply(.reward(actors:["p2"],value:ResourceReward(coins:10)),role:.teacher)
        XCTAssertTrue(b.campaign === c);XCTAssertEqual(c.engine.state.units["p2"]?.coins,before+10)
        XCTAssertEqual(c.engine.history.filter{if case .reward=$0.command{return true};return false}.count,1)
    }
    func testBattleBindingUsesOneExistingEngineAndDoesNotRoll()throws {
        let b=try fixture(),c=try XCTUnwrap(b.campaign)
        let node=try XCTUnwrap(c.engine.state.map.nodes.first{$0.kind == .combat})
        try c.beginTravel(to:node.id)
        var count=0
        while c.travel != nil {
            count += 1;XCTAssertLessThan(count,100);if count>=100{return}
            if c.movementRemaining<0.000001{try b.refill(usingCoins:false,role:.teacher)}
            if !c.isMoving{try c.setPaused(false)}
            _=try b.advanceTravel(distance:10000,role:.teacher)
        }
        _=try c.interactCurrentNode()
        let before=c.snapshot
        let one=try b.battleModel(role:.teacher),two=try b.battleModel(role:.teacher)
        XCTAssertTrue(one === two);XCTAssertTrue(one.engine === c.engine);XCTAssertEqual(c.snapshot,before)
        XCTAssertEqual(b.surface,.battle)
        XCTAssertThrowsError(try b.battleModel(role:.publicDisplay))
        XCTAssertEqual(c.snapshot,before)
    }
    func testDisplayCannotAdvanceTravelOrClockThroughBackend()throws {
        let b=try fixture(),c=try XCTUnwrap(b.campaign),before=c.snapshot
        XCTAssertThrowsError(try b.advanceTravel(distance:10000,role:.publicDisplay))
        XCTAssertThrowsError(try b.battleModel(role:.publicDisplay))
        XCTAssertEqual(c.snapshot,before)
    }
}
