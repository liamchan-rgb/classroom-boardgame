import XCTest
import ClassroomGameCore
import MeadowWorldSupport
import MeadowBattleSupport
@testable import MeadowClassroomSupport

final class ClassroomTeamTests:XCTestCase {
    func campaign(_ count:Int=6,persist:((Data)throws->Void)?=nil)throws->MeadowCampaignSession {
        try .new(layout:MeadowMapGenerator.generate(.suggested(total:10,seed:31827)),studentClasses:Array(repeating:"ranger",count:count),persist:persist)
    }
    func testOneThroughSixStudentsRoundTripAndUseAverageCapacity()throws {
        for count in 1...6 {
            let c=try campaign(count)
            XCTAssertEqual(c.playerIDs.count,count);XCTAssertEqual(c.movementCapacity,400)
            let restored=try MeadowCampaignSession(save:.decoded(c.snapshot.encoded()))
            XCTAssertEqual(restored.playerIDs,c.playerIDs);XCTAssertEqual(restored.engine.state.random,c.engine.state.random)
            XCTAssertTrue(c.playerIDs.allSatisfy{PartyVisual.foot($0) != nil})
        }
    }
    func testRejectZeroOrSevenStudentsAndUnknownClass()throws {
        XCTAssertThrowsError(try campaign(0));XCTAssertThrowsError(try campaign(7))
        XCTAssertThrowsError(try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4)),studentClasses:["unknown"]))
    }
    func testHostHasOneSeparateSeatAndPublicCannotJoin()throws {
        let b=ClassroomGameBackend(),c=try campaign();try b.install(c,role:.teacher)
        let before=c.snapshot
        XCTAssertThrowsError(try b.joinTeacher(name:"老师",classID:"adventurer",team:"party",role:.publicDisplay));XCTAssertEqual(c.snapshot,before)
        try b.joinTeacher(name:"老师",classID:"adventurer",team:"party",role:.teacher)
        XCTAssertEqual(c.engine.state.players.filter{!$0.host}.count,6);XCTAssertEqual(c.engine.state.players.filter{$0.host}.map(\.id),["p7"])
        XCTAssertThrowsError(try b.joinTeacher(name:"第二位",classID:"ranger",team:"party",role:.teacher))
        XCTAssertEqual(try MeadowCampaignSave.decoded(c.snapshot.encoded()).archive.state.players.count,7)
        XCTAssertNotNil(PartyVisual.foot("p7"))
    }
    func testGroupingPreservesEveryPersonalFieldAndRandom()throws {
        let c=try campaign();try c.engine.apply(.editResources(unit:"p1",value:.init(health:9,shield:3,ap:1,coins:19,score:7)))
        let before=c.engine.state
        try c.engine.apply(.configureTeams(names:["red":"红队"],members:["p1":"red","p2":"red"]))
        for u in before.players {var expected=u;if ["p1","p2"].contains(u.id){expected.teamID="red"};XCTAssertEqual(c.engine.state.units[u.id],expected)}
        XCTAssertEqual(c.engine.state.random,before.random)
        XCTAssertEqual(try GameRules.teamRankings(c.engine.state).first{$0.id=="red"}?.score,7)
    }
    func testWarehouseTransferAndMergeConserveCoinsAndItemsAndUndo()throws {
        let c=try campaign();try c.engine.apply(.reward(actors:["p1"],value:.init(coins:100,items:["smallPotion":4])))
        let before=c.engine.state
        try c.engine.apply(.transferTeamResource(from:.player("p1"),to:.warehouse("party"),coins:17,item:"smallPotion",count:2))
        XCTAssertEqual(c.engine.state.teams[0].coins,17)
        try c.engine.apply(.configureTeams(names:["red":"红队"],members:["p2":"red"]))
        try c.engine.apply(.mergeTeams(source:"party",destination:"red"))
        XCTAssertTrue(c.engine.state.players.allSatisfy{$0.teamID=="red"})
        XCTAssertEqual(c.engine.state.teams.first{$0.id=="red"}?.coins,17)
        XCTAssertEqual(c.engine.state.teams.first{$0.id=="red"}?.inventory["smallPotion"],2)
        XCTAssertEqual(c.engine.state.players.reduce(0){$0+$1.coins}+c.engine.state.teams.reduce(0){$0+$1.coins},before.players.reduce(0){$0+$1.coins})
        try c.engine.undo();XCTAssertEqual(c.engine.state.teams.first{$0.id=="party"}?.coins,17)
    }
    func testCrossTeamAndOverdrawAreAtomicAndDoNotConsumeRandom()throws {
        let c=try campaign();try c.engine.apply(.configureTeams(names:["red":"红队"],members:["p2":"red"]))
        let before=c.snapshot
        XCTAssertThrowsError(try c.engine.apply(.transferTeamResource(from:.player("p1"),to:.player("p2"),coins:1,item:nil,count:0)))
        XCTAssertThrowsError(try c.engine.apply(.transferTeamResource(from:.warehouse("party"),to:.player("p1"),coins:1,item:nil,count:0)))
        XCTAssertThrowsError(try c.engine.apply(.transferTeamResource(from:.player("p1"),to:.warehouse("party"),coins:0,item:"smallPotion",count:999)))
        XCTAssertEqual(c.snapshot,before)
    }
    func testOldWarehouseStaysWithOldTeamOnSplit()throws {
        let c=try campaign();try c.engine.apply(.reward(actors:["p1"],value:.init(coins:20)))
        try c.engine.apply(.transferTeamResource(from:.player("p1"),to:.warehouse("party"),coins:10,item:nil,count:0))
        try c.engine.apply(.configureTeams(names:["solo":"独行队"],members:["p1":"solo"]))
        XCTAssertEqual(c.engine.state.teams.first{$0.id=="party"}?.coins,10);XCTAssertEqual(c.engine.state.teams.first{$0.id=="solo"}?.coins,0)
    }
    func testSixPlayerBattleQueueAndWarehouseLockout()throws {
        let c=try campaign();let monster=try XCTUnwrap(c.engine.state.units.values.first{$0.kind == .monster})
        try c.engine.apply(.startBattle(kind:.pve,monsters:[monster.id]))
        XCTAssertTrue(Set(c.playerIDs).isSubset(of:Set(c.engine.state.battle!.queue)))
        let before=c.snapshot
        XCTAssertThrowsError(try c.engine.apply(.transferTeamResource(from:.player("p1"),to:.warehouse("party"),coins:0,item:"smallPotion",count:1)))
        XCTAssertEqual(c.snapshot,before)
    }
    func testFailedPersistenceCannotPartiallyGroupOrTransfer()throws {
        var fail=false
        let c=try campaign(persist:{_ in if fail{throw GameError("disk full")}});let before=c.snapshot;fail=true
        XCTAssertThrowsError(try c.engine.apply(.configureTeams(names:["red":"红队"],members:["p1":"red"])))
        XCTAssertThrowsError(try c.engine.apply(.transferTeamResource(from:.player("p1"),to:.warehouse("party"),coins:0,item:"smallPotion",count:1)))
        XCTAssertEqual(c.snapshot,before)
    }
    func testDifferentTeamDoesNotFollowSelectedParty()throws {
        let c=try campaign();try c.engine.apply(.configureTeams(names:["red":"红队"],members:["p3":"red","p4":"red","p5":"red","p6":"red"]))
        let start=c.engine.state.units["p1"]!.nodeID,goal=c.engine.state.map.neighbors(start)[0]
        try c.beginTravel(to:goal,actor:"p1")
        XCTAssertEqual(Set(c.travel!.actors),Set(["p1","p2"]))
        try c.advanceTravel(distance:25)
        XCTAssertEqual(c.engine.state.units["p3"]?.nodeID,start)
        XCTAssertEqual(c.movementRemaining,c.movementCapacity-25,accuracy:0.001)
        XCTAssertEqual(c.snapshot.movementBalances?["red"],400)
        let restored=try MeadowCampaignSession(save:.decoded(c.snapshot.encoded()))
        XCTAssertEqual(restored.movementRemaining,c.movementRemaining)
    }
    func testSeparateTeamsParkTheirRoadsAndWalkIndependently()throws {
        let c=try campaign();try c.engine.apply(.configureTeams(names:["red":"红队"],members:["p4":"red","p5":"red","p6":"red"]))
        let start=c.engine.state.units["p1"]!.nodeID,roads=c.engine.state.map.neighbors(start)
        try c.beginTravel(to:roads[0],actor:"p1");try c.advanceTravel(distance:10)
        XCTAssertThrowsError(try c.selectPlayer("p4"))
        try c.setPaused(true);let partyPoint=c.position(of:"p1")
        try c.selectPlayer("p4")
        XCTAssertNil(c.travel);XCTAssertEqual(Set(c.parkedTravels["party"]!.actors),Set(["p1","p2","p3"]))
        XCTAssertEqual(c.position(of:"p2"),partyPoint)
        try c.beginTravel(to:roads[roads.count>1 ? 1:0],actor:"p4");try c.advanceTravel(distance:5)
        XCTAssertEqual(Set(c.travel!.actors),Set(["p4","p5","p6"]))
        XCTAssertEqual(c.position(of:"p1"),partyPoint)
        XCTAssertFalse(c.canComplete)
        let restored=try MeadowCampaignSession(save:.decoded(c.snapshot.encoded()))
        XCTAssertEqual(restored.parkedTravels,c.parkedTravels);XCTAssertEqual(restored.position(of:"p1"),partyPoint)
        try c.setPaused(true);try c.selectPlayer("p2")
        XCTAssertEqual(Set(c.travel!.actors),Set(["p1","p2","p3"]));XCTAssertEqual(Set(c.parkedTravels["red"]!.actors),Set(["p4","p5","p6"]))
        try c.setPaused(false);try c.advanceTravel(distance:100000)
        while c.travel != nil {if !c.isMoving{try c.refillMovement(usingCoins:false);try c.setPaused(false)};try c.advanceTravel(distance:100000)}
        XCTAssertEqual(c.engine.state.units["p1"]?.nodeID,roads[0]);XCTAssertEqual(c.engine.state.units["p4"]?.nodeID,start)
        var broken=c.snapshot;broken.parkedTravels?["red"]?.paused=false
        XCTAssertThrowsError(try broken.validate())
    }
    func testTeamMovementBalancesRemainIndependentAndDoNotTouchAP()throws {
        let c=try campaign();try c.engine.apply(.configureTeams(names:["red":"红队"],members:["p3":"red"]))
        var save=c.snapshot;save.movementBalances=["party":120,"red":75];save.movement?.remaining=120
        let restored=try MeadowCampaignSession(save:save),before=restored.engine.state.players.map(\.ap)
        try restored.selectPlayer("p3");XCTAssertEqual(restored.movementRemaining,75)
        try restored.refillMovement(usingCoins:false);XCTAssertEqual(restored.movementRemaining,400)
        try restored.selectPlayer("p1");XCTAssertEqual(restored.movementRemaining,120)
        XCTAssertEqual(restored.engine.state.players.map(\.ap),before)
        let copy=try MeadowCampaignSession(save:.decoded(restored.snapshot.encoded()))
        try copy.selectPlayer("p3");XCTAssertEqual(copy.movementRemaining,400)
    }

    func testExplicitTeacherTransferCrossesTeamsButDisplayCannotInvokeIt()throws {
        let c=try campaign(),b=ClassroomGameBackend();try b.install(c,role:.teacher)
        try c.engine.apply(.configureTeams(names:["red":"红队"],members:["p2":"red"]))
        let command=GameCommand.teacherTransferTeamResource(from:.player("p1"),to:.player("p2"),coins:0,item:"smallPotion",count:1),before=c.snapshot
        XCTAssertThrowsError(try b.apply(command,role:.publicDisplay));XCTAssertEqual(c.snapshot,before)
        try b.apply(command,role:.teacher)
        XCTAssertEqual(c.engine.state.units["p1"]?.inventory["smallPotion"],1)
        XCTAssertEqual(c.engine.state.units["p2"]?.inventory["smallPotion"],3)
        XCTAssertEqual(c.engine.state.random,before.archive.state.random)
        XCTAssertEqual(c.engine.state.players.map(\.ap),before.archive.state.players.map(\.ap))
    }

}
