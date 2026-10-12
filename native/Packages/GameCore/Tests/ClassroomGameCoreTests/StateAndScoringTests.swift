import XCTest
@testable import ClassroomGameCore

final class StateAndScoringTests: XCTestCase {
    func testSevenPlayersIncludingHostHaveIndependentResourcesAndRankingTies() throws {
        let (catalog,initial)=try fixture(classes:["adventurer","ranger","spellblade","dragonKnight","adventurer","ranger","spellblade"],monsters:[],kind:nil)
        var state=initial; state.units["p7"]?.host=true
        state.units["p2"]?.teamID="orange"; state.units["p3"]?.teamID="green"
        let engine=try GameEngine(catalog:catalog,state:state)
        XCTAssertEqual(engine.state.players.count,7)
        XCTAssertEqual(engine.state.players.map(\.health),[12,18,24,32,12,18,24])
        try engine.apply(.reward(actors:["p1","p7"],value:ResourceReward(score:5)))
        try engine.apply(.reward(actors:["p2"],value:ResourceReward(score:10)))
        try engine.apply(.reward(actors:["p3"],value:ResourceReward(score:2)))
        XCTAssertEqual(try GameRules.teamRankings(engine.state).map(\.rank),[1,1,3])
        XCTAssertEqual(try GameRules.teamRankings(engine.state).map(\.score),[10,10,2])
        try engine.apply(.changeTeam(unit:"p7",team:"orange"))
        XCTAssertEqual(engine.state.units["p7"]?.score,5)
        XCTAssertEqual(try GameRules.teamRankings(engine.state).map(\.score),[15,5,2])
    }
    func testMultipleRewardsRespectCapWithoutChangingCurrentActor() throws {
        let (catalog,initial)=try fixture(classes:["adventurer","adventurer","adventurer"])
        var state=initial; state.units["p2"]?.ap=8; state.units["p3"]?.ap=1
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.reward(actors:["p2","p3"],value:ResourceReward(coins:10,ap:1,score:2)))
        XCTAssertEqual(engine.state.battle?.current,"p1")
        XCTAssertEqual(engine.state.units["p2"]?.ap,8); XCTAssertEqual(engine.state.units["p3"]?.ap,2)
        XCTAssertEqual(engine.state.units["p2"]?.coins,10); XCTAssertEqual(engine.state.units["p3"]?.coins,10)
        XCTAssertEqual(engine.state.units["p1"]?.coins,0)
        let before=engine.state
        XCTAssertThrowsError(try engine.apply(.reward(actors:["p2","p1"],value:ResourceReward(coins:-5))))
        XCTAssertEqual(engine.state,before)
    }
    func testGroupMoveFailureAndEncounterStopAreAtomic() throws {
        let (catalog,initial)=try fixture(classes:["adventurer","adventurer","adventurer"],monsters:[],kind:nil)
        var insufficient=initial; insufficient.units["p2"]?.ap=1
        let invalid=try GameEngine(catalog:catalog,state:insufficient)
        XCTAssertThrowsError(try invalid.apply(.move(actors:["p1","p2"],path:[1,2,3])))
        XCTAssertEqual(invalid.state,insufficient)
        var encounter=initial
        encounter.units["p1"]?.ap=6; encounter.units["p2"]?.ap=6
        encounter.units["m1"]=try GameFactory.monster(id:"m1",templateID:"slime",nodeID:2,catalog:catalog)
        encounter.random=RandomState(scripted:[20,19,18,1])
        let engine=try GameEngine(catalog:catalog,state:encounter)
        let receipt=try engine.apply(.move(actors:["p1","p2"],path:[1,2,3]))
        XCTAssertEqual(engine.state.units["p1"]?.nodeID,2); XCTAssertEqual(engine.state.units["p2"]?.nodeID,2)
        XCTAssertEqual(engine.state.units["p3"]?.nodeID,1)
        XCTAssertEqual(engine.state.units["p1"]?.ap,5); XCTAssertEqual(engine.state.phase,.pve)
        XCTAssertEqual(Set(engine.state.battle?.queue ?? []),Set(["p1","p2","p3","m1"]))
        XCTAssertEqual(receipt.dice.count,4); XCTAssertTrue(receipt.dice.allSatisfy { !$0.naturalTwenty })
        XCTAssertEqual(engine.state.units["m1"]?.health,8)
    }
    func testSharedNodeRewardIsClaimedOnceAndUndoRestoresAllArrivalEffects() throws {
        let (catalog,state)=try fixture(classes:["adventurer","adventurer","adventurer"],monsters:[],kind:nil)
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.move(actors:["p1","p2"],path:[1,2,3]))
        XCTAssertEqual(engine.state.units["p1"]?.coins,10); XCTAssertEqual(engine.state.units["p2"]?.coins,10)
        XCTAssertEqual(engine.state.units["p1"]?.score,2); XCTAssertEqual(engine.state.units["p2"]?.score,2)
        XCTAssertTrue(engine.state.map.nodes.first { $0.id==3 }!.rewardCompleted)
        try engine.apply(.move(actors:["p3"],path:[1,2,3]))
        XCTAssertEqual(engine.state.units["p3"]?.coins,0); XCTAssertEqual(engine.state.units["p3"]?.score,0)
        try engine.undo(); try engine.undo()
        XCTAssertEqual(engine.state,state)
    }
    func testBothSetThresholdsAccumulateWithoutHealingOrRefilling() throws {
        let (catalog,state)=try fixture(monsters:[],kind:nil)
        let engine=try GameEngine(catalog:catalog,state:state)
        let allParts=Dictionary(uniqueKeysWithValues:catalog.sets.flatMap(\.items).map { ($0,1) })
        try engine.apply(.reward(actors:["p1"],value:ResourceReward(items:allParts)))
        try engine.apply(.equip(unit:"p1",slot:.weapon,item:"starlightBlade"))
        try engine.apply(.equip(unit:"p1",slot:.armor,item:"starlightArmor"))
        var stats=try GameRules.attributes(engine.state.units["p1"]!,catalog:catalog)
        XCTAssertEqual(stats.maximumHealth,24); XCTAssertEqual(stats.damage,1)
        try engine.apply(.equip(unit:"p1",slot:.accessory,item:"starlightCharm"))
        stats=try GameRules.attributes(engine.state.units["p1"]!,catalog:catalog)
        XCTAssertEqual(stats.maximumHealth,24); XCTAssertEqual(stats.damage,3); XCTAssertEqual(stats.baseAP,4)
        XCTAssertEqual(engine.state.units["p1"]?.health,12); XCTAssertEqual(engine.state.units["p1"]?.ap,3)
        XCTAssertTrue(try GameRules.skills(engine.state.units["p1"]!,catalog:catalog).contains("starlightPulse"))
        try engine.apply(.equip(unit:"p1",slot:.weapon,item:"dragonFangSword"))
        try engine.apply(.equip(unit:"p1",slot:.armor,item:"dragonArmor"))
        try engine.apply(.equip(unit:"p1",slot:.accessory,item:"dragonCharm"))
        stats=try GameRules.attributes(engine.state.units["p1"]!,catalog:catalog)
        XCTAssertEqual(stats.maximumHealth,30); XCTAssertEqual(stats.damage,3)
        XCTAssertEqual(stats.baseAP,4); XCTAssertEqual(stats.maximumAP,10)
        XCTAssertEqual(engine.state.units["p1"]?.health,12)
        try engine.apply(.setHealth(unit:"p1",value:30,killer:nil))
        try engine.apply(.reward(actors:["p1"],value:ResourceReward(ap:6)))
        try engine.apply(.equip(unit:"p1",slot:.armor,item:nil))
        try engine.apply(.equip(unit:"p1",slot:.accessory,item:nil))
        XCTAssertEqual(engine.state.units["p1"]?.health,12); XCTAssertEqual(engine.state.units["p1"]?.ap,8)
    }
    func testSetSkillUsageDoesNotResetWhenUnequippingAndReequipping() throws {
        let (catalog,initial)=try fixture(classes:["adventurer"],monsters:[],kind:nil)
        var state=initial; state.units["p1"]?.equipment=Equipment(weapon:"starlightBlade",armor:"starlightArmor",accessory:"starlightCharm")
        state.units["p1"]?.skillUses["starlightPulse"]=1
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.equip(unit:"p1",slot:.accessory,item:nil))
        try engine.apply(.equip(unit:"p1",slot:.accessory,item:"starlightCharm"))
        XCTAssertEqual(engine.state.units["p1"]?.skillUses["starlightPulse"],1)
    }
    func testPvPKnockoutCanScoreAgainAfterReviveWithoutDroppingAssets() throws {
        let (catalog,initial)=try fixture(classes:["adventurer","adventurer","adventurer"],monsters:[],kind:.freeForAll,scripted:[20,20])
        var state=initial; state.units["p1"]?.equipment.weapon="legendaryStaff"
        state.units["p2"]?.coins=17; state.units["p2"]?.inventory["smallPotion"]=2
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.attack(actor:"p1",target:"p2")); XCTAssertEqual(engine.state.units["p1"]?.score,2)
        try engine.apply(.revive("p2")); try engine.apply(.attack(actor:"p1",target:"p2"))
        XCTAssertEqual(engine.state.units["p1"]?.score,4)
        XCTAssertEqual(engine.state.units["p2"]?.coins,17); XCTAssertEqual(engine.state.units["p2"]?.inventory["smallPotion"],2)
        let before=engine.state
        XCTAssertThrowsError(try engine.apply(.finishBattle(winner:nil,byScore:false)))
        XCTAssertEqual(engine.state,before)
        try engine.apply(.finishBattle(winner:"p3",byScore:false))
        XCTAssertEqual(engine.state.phase,.settlement); XCTAssertEqual(engine.state.lastOutcome?.winners,["p3"])
        XCTAssertEqual(engine.state.lastOutcome?.personalRanking.first?.id,"p1")
    }
    func testTeamSupportAndRescueUseCurrentBattleFaction() throws {
        let (catalog,initial)=try fixture(classes:["dragonKnight","adventurer","adventurer"],monsters:[],kind:.teamPvp)
        var state=initial; state.units["p2"]?.health=0; state.units["p2"]?.baseAttributes.maximumHealth=13
        state.units["p3"]?.teamID="orange"; state.units["p3"]?.health=2
        state.units["p1"]?.ap=8; state.units["p1"]?.inventory["revivalStone"]=1
        let team=try GameEngine(catalog:catalog,state:state)
        try team.apply(.cast(actor:"p1",skill:"dragonScaleWard",target:.node(2)))
        XCTAssertEqual(team.state.units["p3"]?.health,2); XCTAssertEqual(team.state.units["p3"]?.shield,0)
        XCTAssertEqual(team.state.units["p2"]?.health,0)
        try team.apply(.rescue(actor:"p1",target:"p2")); XCTAssertEqual(team.state.units["p2"]?.health,7)
        state.battle?.kind = .freeForAll; state.phase = .freeForAll
        let free=try GameEngine(catalog:catalog,state:state)
        XCTAssertThrowsError(try free.apply(.rescue(actor:"p1",target:"p2")))
        XCTAssertEqual(free.state,state)
    }
    func testNoSurvivingPvPFactionWaitsForTeacherAndScoreTiesArePreserved() throws {
        let (catalog,initial)=try fixture(classes:["adventurer","adventurer"],monsters:[],kind:.freeForAll)
        var state=initial; state.units["p1"]?.health=0; state.units["p2"]?.health=0
        state.battle?.current=nil; state.pauseReasons=[.noSurvivors]
        let waiting=try GameEngine(catalog:catalog,state:state)
        try waiting.apply(.reward(actors:["p1","p2"],value:ResourceReward(score:2)))
        XCTAssertEqual(waiting.state.phase,.freeForAll); XCTAssertNil(waiting.state.lastOutcome)
        try waiting.apply(.finishBattle(winner:nil,byScore:true))
        XCTAssertEqual(Set(waiting.state.lastOutcome?.winners ?? []),Set(["p1","p2"]))
        XCTAssertEqual(waiting.state.lastOutcome?.personalRanking.map(\.rank),[1,1])
    }
    func testTeacherKillWithoutOwnerDoesNotAutoPayButExplicitAttributionCan() throws {
        let (catalog,state)=try fixture(classes:["adventurer"],monsters:["slime"],scripted:Array(repeating:100,count:10))
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.setHealth(unit:"m1",value:0,killer:nil))
        XCTAssertEqual(engine.state.units["p1"]?.coins,0); XCTAssertEqual(engine.state.units["p1"]?.score,0)
        try engine.apply(.setHealth(unit:"m1",value:0,killer:"p1"))
        XCTAssertEqual(engine.state.units["p1"]?.score,1)
        try engine.apply(.setHealth(unit:"m1",value:0,killer:"p1"))
        XCTAssertEqual(engine.state.units["p1"]?.score,1)
    }
    func testArchiveAndAtomicStoreRestoreCompleteStatePausedAndDoNotMutateTemplates() throws {
        let (catalog,initial)=try fixture(monsters:["slime"],scripted:[1])
        var state=initial; state.units["m1"]?.baseAttributes.maximumHealth=30; state.units["m1"]?.health=30
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store=AtomicGameStore(url:directory.appendingPathComponent("game.json"))
        let engine=try GameEngine(catalog:catalog,state:state,persist:store.save)
        try engine.advanceClock(by:13); try engine.apply(.attack(actor:"p1",target:"m1"),id:"saved-attack")
        let restored=try store.load()
        XCTAssertTrue(restored.state.pauseReasons.contains(.manual))
        XCTAssertEqual(restored.state.units,engine.state.units); XCTAssertEqual(restored.state.random,engine.state.random)
        XCTAssertEqual(restored.history,engine.history); XCTAssertEqual(restored.catalog,catalog)
        XCTAssertEqual(try GameFactory.monster(id:"new",templateID:"slime",nodeID:2,catalog:catalog).health,8)
        let fileBefore=try Data(contentsOf:store.url)
        XCTAssertThrowsError(try engine.apply(.move(actors:["p2"],path:[2,4])))
        XCTAssertEqual(try Data(contentsOf:store.url),fileBefore)
        XCTAssertThrowsError(try GameArchive.decoded(Data("bad data".utf8)))
    }
    func testRollbackDropsFutureBranchAndRestoresRandomAndWholeOperations() throws {
        let (catalog,state)=try fixture(monsters:["ruinDragon"],scripted:[1,2,3])
        let engine=try GameEngine(catalog:catalog,state:state)
        let first=try engine.apply(.attack(actor:"p1",target:"m1"),id:"first")
        try engine.apply(.attack(actor:"p1",target:"m1"),id:"old-future")
        try engine.rollback(after:"first")
        XCTAssertEqual(engine.state,first.after); XCTAssertEqual(engine.history.count,1)
        let branch=try engine.apply(.attack(actor:"p1",target:"m1"),id:"new-future")
        XCTAssertEqual(branch.dice.first?.values,[2]); XCTAssertThrowsError(try engine.replay("old-future"))
        XCTAssertEqual(engine.history.map(\.id),["first","new-future"])
    }
    func testPublicProjectionOmitsUnrevealedContentsAndPrivateSimulationState() throws {
        let (catalog,initial)=try fixture(monsters:[],kind:nil)
        var state=initial
        state.units["hidden"]=try GameFactory.monster(id:"hidden",templateID:"ruinDragon",nodeID:4,catalog:catalog)
        state.units["hidden"]?.name="PRIVATE-MONSTER-8642"; state.map.nodes[3].name="PRIVATE-NODE-8642"
        let snapshot=try state.publicSnapshot(catalog:catalog)
        let json=String(decoding:try JSONEncoder().encode(snapshot),as:UTF8.self)
        XCTAssertFalse(json.contains("PRIVATE")); XCTAssertFalse(json.contains("scripted")); XCTAssertFalse(json.contains("inventory"))
        XCTAssertEqual(snapshot.nodes.map(\.id),[1,2]); XCTAssertNil(snapshot.nodes[1].kind)
        XCTAssertEqual(snapshot.units.count,2)
    }
}
