import XCTest
@testable import ClassroomGameCore

final class CombatTests: XCTestCase {
    func testAPRefillPreservesStoredPointsAndSkillUses() throws {
        let (catalog, initial) = try fixture()
        var state = initial; state.units["p1"]?.ap = 2; state.units["p2"]?.ap = 6; state.units["p2"]?.skillUses["breather"] = 1
        let engine = try GameEngine(catalog:catalog,state:state)
        try finishRound(engine)
        XCTAssertEqual(engine.state.battle?.round,2)
        XCTAssertEqual(engine.state.units["p1"]?.ap,3); XCTAssertEqual(engine.state.units["p2"]?.ap,6)
        XCTAssertEqual(engine.state.units["p2"]?.skillUses["breather"],1)
    }
    func testManualEndKeepsAPButTimeoutClearsItAndAdvances() throws {
        let (catalog, initial) = try fixture()
        var state = initial; state.units["p1"]?.ap = 2; state.remainingSeconds = 17
        let manual = try GameEngine(catalog:catalog,state:state)
        try manual.apply(.endTurn(actor:"p1",timedOut:false))
        XCTAssertEqual(manual.state.units["p1"]?.ap,2); XCTAssertEqual(manual.state.battle?.current,"p2")
        let timeout = try GameEngine(catalog:catalog,state:state)
        try timeout.advanceClock(by:17)
        XCTAssertEqual(timeout.state.units["p1"]?.ap,0); XCTAssertEqual(timeout.state.battle?.current,"p2")
        XCTAssertEqual(timeout.state.remainingSeconds,30); XCTAssertEqual(timeout.history.count,1)
    }
    func testPauseReasonsStackAndRemainingTimeIsExact() throws {
        let (catalog,state) = try fixture(); let engine = try GameEngine(catalog:catalog,state:state)
        try engine.advanceClock(by:13); XCTAssertEqual(engine.state.remainingSeconds,17)
        try engine.setPause(.manual,enabled:true); try engine.setPause(.editor,enabled:true); try engine.setPause(.book,enabled:true)
        try engine.advanceClock(by:100); try engine.setPause(.editor,enabled:false); try engine.setPause(.book,enabled:false)
        try engine.advanceClock(by:100); XCTAssertEqual(engine.state.remainingSeconds,17)
        XCTAssertEqual(engine.state.pauseReasons,[.manual]); XCTAssertTrue(engine.history.isEmpty)
        try engine.setPause(.manual,enabled:false); try engine.advanceClock(by:2)
        XCTAssertEqual(engine.state.remainingSeconds,15)
    }
    func testMovementAttackMovementConsumesActualAPAndResetsDecisionClock() throws {
        let (catalog,initial) = try fixture(monsters:["ruinDragon"],scripted:[1])
        var state=initial; state.units["p1"]?.equipment.weapon="huntingBow"; state.units["p1"]?.ap=6
        state.units["m1"]?.nodeID=3; state.remainingSeconds=17
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.move(actors:["p1"],path:[2,1]))
        XCTAssertEqual(engine.state.remainingSeconds,30)
        let before=engine.state
        XCTAssertThrowsError(try engine.apply(.attack(actor:"p1",target:"m1"))) // 1→2→3 exceeds bow range.
        XCTAssertEqual(engine.state,before)
        try engine.apply(.move(actors:["p1"],path:[1,2]))
        try engine.apply(.attack(actor:"p1",target:"m1"))
        try engine.apply(.move(actors:["p1"],path:[2,4]))
        XCTAssertEqual(engine.state.units["p1"]?.ap,2); XCTAssertEqual(engine.state.units["p1"]?.nodeID,4)
        XCTAssertEqual(engine.state.remainingSeconds,30)
    }
    func testMinimumDamageStillHitsAndShieldAbsorbsFirst() throws {
        let (catalog,initial)=try fixture(monsters:["stoneGuardian"],scripted:[1])
        let engine=try GameEngine(catalog:catalog,state:initial)
        let receipt=try engine.apply(.attack(actor:"p1",target:"m1"))
        XCTAssertEqual(engine.state.units["m1"]?.health,24); XCTAssertEqual(engine.state.units["m1"]?.shield,5)
        XCTAssertEqual(receipt.dice.count,1); XCTAssertEqual(receipt.dice[0].values,[1])
    }
    func testNaturalTwentyKillsBossButEighteenPlusTwoDoesNot() throws {
        let (catalog,initial)=try fixture(monsters:["ruinDragon"],scripted:[20]+Array(repeating:100,count:12))
        var state=initial; state.units["p1"]?.equipment.weapon="legendaryStaff"; state.units["m1"]?.shield=100
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.attack(actor:"p1",target:"m1"))
        XCTAssertEqual(engine.state.units["m1"]?.health,0); XCTAssertEqual(engine.state.units["m1"]?.shield,0)
        XCTAssertEqual(engine.state.units["p1"]?.score,5); XCTAssertEqual(engine.state.phase,.exploration)
        state.random=RandomState(scripted:[18]); state.units["p1"]?.baseAttributes.damage=2
        let ordinary=try GameEngine(catalog:catalog,state:state)
        let receipt=try ordinary.apply(.attack(actor:"p1",target:"m1"))
        XCTAssertEqual(ordinary.state.units["m1"]?.health,72); XCTAssertEqual(ordinary.state.units["m1"]?.shield,80)
        XCTAssertFalse(receipt.dice[0].naturalTwenty)
    }
    func testGroupTwentyAllRewardsSelfEffectsAndUndoAreOneTransaction() throws {
        let (catalog,initial)=try fixture(classes:["dragonKnight"],monsters:["slime","wolf","ruinDragon"],scripted:[20]+Array(repeating:1,count:40))
        var state=initial; state.units["p1"]?.health=5
        var saves=0
        let engine=try GameEngine(catalog:catalog,state:state,persist:{ _ in saves += 1 })
        let command=GameCommand.cast(actor:"p1",skill:"dragonFlame",target:.node(2))
        let receipt=try engine.apply(command,id:"one-group-attack")
        XCTAssertEqual(receipt.dice.filter { $0.source=="damage" }.count,1)
        XCTAssertTrue(engine.state.units.values.filter { $0.kind == .monster }.allSatisfy { !$0.isAlive && $0.shield == 0 })
        let player=try XCTUnwrap(engine.state.units["p1"])
        XCTAssertEqual(player.ap,1); XCTAssertEqual(player.health,11); XCTAssertEqual(player.shield,6)
        XCTAssertEqual(player.coins,40); XCTAssertEqual(player.score,7)
        XCTAssertEqual(player.inventory["starlightBlade"],3); XCTAssertEqual(player.inventory["dragonCharm"],3)
        XCTAssertEqual(player.inventory["smallPotion"],2)
        XCTAssertNil(player.damageBuff); XCTAssertEqual(engine.state.phase,.exploration); XCTAssertNil(engine.state.battle)
        XCTAssertEqual(saves,1); XCTAssertEqual(engine.history.count,1)
        let committed=engine.state
        XCTAssertEqual(try engine.apply(command,id:"one-group-attack"),receipt)
        XCTAssertEqual(try engine.replay("one-group-attack"),receipt)
        XCTAssertEqual(engine.state,committed); XCTAssertEqual(saves,1)
        try engine.undo(); XCTAssertEqual(engine.state,state); XCTAssertTrue(engine.history.isEmpty); XCTAssertEqual(saves,2)
    }
    func testInvalidActionAndPersistenceFailureNeverConsumeResourcesOrRandom() throws {
        let (catalog,initial)=try fixture(classes:["dragonKnight"],monsters:["ruinDragon"],scripted:[20]+Array(repeating:1,count:20))
        var distant=initial; distant.units["p1"]?.nodeID=1; distant.units["m1"]?.nodeID=4
        let invalid=try GameEngine(catalog:catalog,state:distant)
        XCTAssertThrowsError(try invalid.apply(.cast(actor:"p1",skill:"dragonFlame",target:.node(4))))
        XCTAssertEqual(invalid.state,distant); XCTAssertTrue(invalid.history.isEmpty)
        var attempted=0
        let failing=try GameEngine(catalog:catalog,state:initial,persist:{ _ in attempted += 1; throw GameError("模拟保存失败") })
        XCTAssertThrowsError(try failing.apply(.cast(actor:"p1",skill:"dragonFlame",target:.node(2))))
        XCTAssertEqual(failing.state,initial); XCTAssertTrue(failing.history.isEmpty); XCTAssertEqual(attempted,1)
    }
    func testRescueHalfHealthAndEligibilityStartsNextRound() throws {
        let (catalog,initial)=try fixture(monsters:["wolf"])
        var state=initial; state.units["p2"]?.baseAttributes.maximumHealth=13; state.units["p2"]?.health=0
        state.units["p1"]?.inventory["revivalStone"]=1
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.rescue(actor:"p1",target:"p2"))
        XCTAssertEqual(engine.state.units["p2"]?.health,7); XCTAssertEqual(engine.state.units["p2"]?.canActFromRound,2)
        XCTAssertEqual(engine.state.units["p1"]?.ap,1); XCTAssertNil(engine.state.units["p1"]?.inventory["revivalStone"])
        XCTAssertEqual(engine.state.units["p1"]?.score,2)
        try engine.apply(.endTurn(actor:"p1",timedOut:false)); XCTAssertEqual(engine.state.battle?.current,"m1")
        try engine.apply(.endTurn(actor:"m1",timedOut:false)); XCTAssertEqual(engine.state.battle?.round,2)
        try engine.apply(.endTurn(actor:"p1",timedOut:false)); XCTAssertEqual(engine.state.battle?.current,"p2")
    }
    func testInvalidRescueCasesAreAtomic() throws {
        let (catalog,initial)=try fixture()
        for variant in 0..<3 {
            var state=initial; state.units["p2"]?.health=0; state.units["p1"]?.inventory["revivalStone"]=1
            if variant==0 { state.units["p1"]?.nodeID=1 }
            if variant==1 { state.units["p1"]?.ap=1 }
            if variant==2 { state.units["p1"]?.inventory.removeAll() }
            let engine=try GameEngine(catalog:catalog,state:state)
            XCTAssertThrowsError(try engine.apply(.rescue(actor:"p1",target:"p2")))
            XCTAssertEqual(engine.state,state); XCTAssertTrue(engine.history.isEmpty)
        }
    }
    func testLateMonsterIsImmediatelyAttackableButWaitsForNextRound() throws {
        // Joining consumes an initiative roll and one tie-position draw before damage.
        let (catalog,initial)=try fixture(monsters:["wolf"],scripted:[20,1,1])
        var state=initial; state.units["m2"]=try GameFactory.monster(id:"m2",templateID:"ruinDragon",nodeID:2,catalog:catalog)
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.joinMonster("m2"))
        XCTAssertEqual(engine.state.battle?.queue.first,"m2"); XCTAssertEqual(engine.state.battle?.current,"p1")
        XCTAssertEqual(engine.state.units["m2"]?.canActFromRound,2); XCTAssertEqual(engine.state.units["m2"]?.health,72)
        try engine.apply(.attack(actor:"p1",target:"m2")); XCTAssertEqual(engine.state.units["m2"]?.shield,9)
        try finishRound(engine)
        XCTAssertEqual(engine.state.battle?.current,"m2"); XCTAssertEqual(engine.state.battle?.round,2)
    }
    func testAllPlayersDownPausesWithoutPenaltiesAndTeacherCanRevive() throws {
        let (catalog,initial)=try fixture(classes:["adventurer"],monsters:["ruinDragon"],scripted:[12])
        var state=initial; state.battle?.current="m1"; state.units["p1"]?.coins=31; state.units["p1"]?.score=7; state.units["p1"]?.ap=6
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.attack(actor:"m1",target:"p1"))
        XCTAssertEqual(engine.state.phase,.pve); XCTAssertTrue(engine.state.pauseReasons.contains(.allPlayersDown))
        XCTAssertEqual(engine.state.units["p1"]?.coins,31); XCTAssertEqual(engine.state.units["p1"]?.score,7); XCTAssertEqual(engine.state.units["p1"]?.ap,6)
        try engine.apply(.revive("p1")); XCTAssertEqual(engine.state.units["p1"]?.health,6)
        XCTAssertFalse(engine.state.pauseReasons.contains(.allPlayersDown)); XCTAssertEqual(engine.state.units["p1"]?.canActFromRound,2)
    }
    func testBuffLifetimeRefreshAndNewBattleSkillReset() throws {
        let (catalog,state)=try fixture(classes:["ranger","adventurer"],monsters:["ruinDragon"])
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.cast(actor:"p1",skill:"rally",target:.node(2)))
        try finishRound(engine); XCTAssertEqual(engine.state.units["p2"]?.damageBuff?.amount,2)
        try engine.apply(.cast(actor:"p1",skill:"rally",target:.node(2)))
        try finishRound(engine); XCTAssertNotNil(engine.state.units["p2"]?.damageBuff)
        try finishRound(engine); XCTAssertNil(engine.state.units["p2"]?.damageBuff)
        XCTAssertThrowsError(try engine.apply(.cast(actor:"p1",skill:"rally",target:.node(2))))
        try engine.apply(.finishBattle(winner:nil,byScore:false))
        try engine.apply(.startBattle(kind:.pve,monsters:["m1"]))
        XCTAssertEqual(engine.state.units["p1"]?.skillUses["rally"] ?? 0,0)
    }
    func testMonsterRecoveryCanOnlyBeUsedOncePerTurn() throws {
        let (catalog,initial)=try fixture(monsters:["caveTroll"],scripted:[12])
        var state=initial; state.battle?.current="m1"; state.units["m1"]?.health=16
        let engine=try GameEngine(catalog:catalog,state:state)
        try engine.apply(.cast(actor:"m1",skill:"regeneration",target:nil))
        XCTAssertEqual(engine.state.units["m1"]?.health,24)
        let before=engine.state
        XCTAssertThrowsError(try engine.apply(.cast(actor:"m1",skill:"regeneration",target:nil)))
        XCTAssertEqual(engine.state,before)
        try engine.apply(.cast(actor:"m1",skill:"sweep",target:.node(2)))
        XCTAssertTrue(engine.state.pauseReasons.contains(.allPlayersDown))
    }
}
