import XCTest
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport
@testable import MeadowClassroomSupport

final class ClassroomArchiveTests:XCTestCase {
    func setup()throws->ClassroomGameBackend {
        let b=ClassroomGameBackend(),c=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4,seed:819)),studentClasses:Array(repeating:"ranger",count:6))
        try b.install(c,role:.teacher);return b
    }
    func testTeacherProfileAndSevenPlayerSaveUseSameEngine()throws {
        let b=try setup(),c=b.campaign!,engine=c.engine,a=PlayerAppearance(body:"wayfarer",outfit:"runeArmor")
        try b.joinTeacher(name:"老师",classID:"dragonKnight",team:"party",appearance:a,role:.teacher)
        XCTAssertTrue(c.engine === engine);XCTAssertEqual(c.engine.state.players.count,7);XCTAssertEqual(c.engine.state.units["p7"]?.appearance,a)
        let copy=try MeadowCampaignSession(save:MeadowCampaignSave.decoded(c.snapshot.encoded()))
        XCTAssertEqual(copy.engine.state.players,c.engine.state.players);XCTAssertEqual(copy.engine.state.random,c.engine.state.random)
        XCTAssertEqual(b.bookPlayers.count,7)
    }
    func testPublicDisplayCannotChangeProfile()throws {
        let b=try setup(),before=b.campaign!.snapshot
        XCTAssertThrowsError(try b.apply(.applyPlayerProfile(unit:"p1",name:"伪造",appearance:.init()),role:.publicDisplay))
        XCTAssertEqual(b.campaign!.snapshot,before)
    }
    func testBadTeacherAppearanceDoesNotPartiallyJoin()throws {
        let b=try setup(),before=b.campaign!.snapshot
        XCTAssertThrowsError(try b.joinTeacher(name:"老师",classID:"ranger",team:"party",appearance:.init(outfit:"missing"),role:.teacher))
        XCTAssertEqual(b.campaign!.snapshot,before)
    }
    func testOldHostCommandDecodesWithoutAppearance()throws {
        let bytes=Data(#"{"addHost":{"id":"p7","name":"老师","classID":"ranger","team":"party","node":0}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(GameCommand.self,from:bytes),.addHost(id:"p7",name:"老师",classID:"ranger",team:"party",node:0))
    }
    func testTeacherCanUndoJoinUsingSelectedHistory()throws {
        let b=try setup(),c=b.campaign!,first=try c.engine.apply(.grantPlayerResources(actors:["p1"],ap:0,coins:1))
        try b.joinTeacher(name:"老师",classID:"ranger",team:"party",role:.teacher)
        let result=try c.snapshot.rollingBack(after:first.id);XCTAssertEqual(result.archive.state.players.count,6);XCTAssertNil(result.archive.state.units["p7"])
        XCTAssertEqual(c.engine.state.players.count,7)
    }
    func testSevenPlayerBattleUsesIndividualAPAndQueue()throws {
        let b=try setup(),c=b.campaign!
        try b.joinTeacher(name:"老师",classID:"ranger",team:"party",role:.teacher)
        let target=c.engine.state.map.nodes.first{$0.kind == .combat || $0.kind == .boss}!.id
        for _ in 0..<50 where c.engine.state.units["p1"]?.nodeID != target {
            try c.refillMovement(usingCoins:false)
            if c.travel==nil{try c.beginTravel(to:target)}else{try c.setPaused(false)}
            try c.advanceTravel(distance:100000)
        }
        try c.interactCurrentNode();let model=try b.battleModel(role:.teacher)
        XCTAssertTrue(model.engine === c.engine)
        XCTAssertTrue(Set(c.playerIDs).isSubset(of:Set(c.engine.state.battle!.queue)))
        let before=c.engine.state.units["p2"]!.ap
        try c.engine.apply(.grantPlayerResources(actors:["p1"],ap:0,coins:1));XCTAssertEqual(c.engine.state.units["p2"]?.ap,before)
    }
}
