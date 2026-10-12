import XCTest
@testable import ClassroomGameCore

final class MonsterAITests: XCTestCase {
    func testRecoveryPriorityOnceThenAttackAndRoundRefill() throws {
        let (catalog, initial) = try fixture(monsters:["caveTroll"],scripted:[1,1,1,1])
        var state = initial; state.units["m1"]?.health = 16; state.battle?.current = "m1"; state.battle?.acted = ["p1","p2"]
        let engine = try GameEngine(catalog:catalog,state:state)
        let heal = try engine.apply(.monsterStep)
        XCTAssertEqual(engine.state.units["m1"]?.health,24)
        XCTAssertEqual(engine.state.units["m1"]?.skillUses["regeneration"],1)
        XCTAssertTrue(heal.events.contains { $0.kind == "heal" })
        try engine.apply(.monsterStep) // AP2: sweep before ordinary attacks, no second regeneration.
        XCTAssertEqual(engine.state.units["m1"]?.skillUses["regeneration"],1)
        XCTAssertEqual(engine.state.units["m1"]?.skillUses["sweep"],1)
        XCTAssertEqual(engine.state.battle?.round,2)
        XCTAssertEqual(engine.state.battle?.current,"p1")
        XCTAssertEqual(engine.history.count,2)
    }
    func testNearestEnemyMovesThenAttacksWithoutDecisionClock() throws {
        let (catalog, initial) = try fixture(monsters:["wolf"],scripted:[2,1])
        var state = initial; state.battle?.current = "m1"; state.units["m1"]?.nodeID = 1
        state.units["p1"]?.nodeID = 2; state.units["p2"]?.nodeID = 3
        let engine = try GameEngine(catalog:catalog,state:state)
        XCTAssertNil(try engine.advanceClock(by:100))
        XCTAssertEqual(engine.state.remainingSeconds,30)
        // Wolf prefers lowest HP ratio; make p1 the unique priority.
        try engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:6)))
        try engine.apply(.monsterStep)
        XCTAssertEqual(engine.state.units["m1"]?.nodeID,2)
        try engine.apply(.monsterStep)
        XCTAssertEqual(engine.state.units["p1"]?.health,4)
        XCTAssertEqual(engine.state.battle?.current,"p1")
    }
    func testRandomTargetIsSavedAcrossMovementAndRestoreAndRetargetsOnlyWhenInvalid() throws {
        var (catalog, state) = try fixture(monsters:["wolf"],scripted:[2,1,1])
        let index = try XCTUnwrap(catalog.monsters.firstIndex { $0.id == "wolf" })
        catalog.monsters[index].strategy = .random
        state.units["m1"]?.nodeID = 1; state.units["m1"]?.ap = 5; state.units["p1"]?.nodeID = 3; state.units["p2"]?.nodeID = 3
        state.battle?.current = "m1"
        let engine = try GameEngine(catalog:catalog,state:state)
        try engine.apply(.monsterStep)
        XCTAssertEqual(engine.state.battle?.monsterTargets?["m1"],"p2")
        XCTAssertEqual(engine.state.random.cursor,1)
        let restored = try GameArchive.decoded(engine.archive.encoded(),pauseOnRestore:false)
        let continued = try GameEngine(catalog:restored.catalog,state:restored.state,history:restored.history)
        try continued.apply(.monsterStep) // No new target draw on second movement.
        XCTAssertEqual(continued.state.units["m1"]?.nodeID,3)
        XCTAssertEqual(continued.state.random.cursor,1)
        try continued.apply(.editResources(unit:"p2",value:ResourcePatch(health:0)))
        try continued.apply(.monsterStep)
        XCTAssertEqual(continued.state.battle?.monsterTargets?["m1"],"p1")
        XCTAssertEqual(continued.state.units["p1"]?.health,11)
    }
    func testNearestTieDrawRecordedAndEntireAIStepUndoRestoresRandom() throws {
        let (catalog, initial) = try fixture(monsters:["goblinArcher"],scripted:[2,1])
        var state = initial; state.battle?.current = "m1"
        let engine = try GameEngine(catalog:catalog,state:state)
        let receipt = try engine.apply(.monsterStep)
        XCTAssertEqual(engine.state.units["p2"]?.health,11)
        XCTAssertTrue(receipt.events.contains { $0.kind == "aiRandomChoice" && $0.amount == 1 })
        XCTAssertEqual(engine.state.random.cursor,2)
        try engine.undo(); XCTAssertEqual(engine.state,state)
    }
    func testPausedAIAndFailedSaveDoNotSelectTargetsOrSpendPoints() throws {
        let (catalog, initial) = try fixture(monsters:["goblinArcher"],scripted:[2,1])
        var state = initial; state.battle?.current = "m1"; state.pauseReasons = [.book]
        let paused = try GameEngine(catalog:catalog,state:state)
        XCTAssertThrowsError(try paused.apply(.monsterStep)); XCTAssertEqual(paused.state,state)
        state.pauseReasons = []
        let failed = try GameEngine(catalog:catalog,state:state,persist:{ _ in throw GameError("磁盘失败") })
        XCTAssertThrowsError(try failed.apply(.monsterStep)); XCTAssertEqual(failed.state,state); XCTAssertTrue(failed.history.isEmpty)
    }
    func testAIContinuesOrdinaryAttacksAndEndsWhenAPIsExhausted() throws {
        let (catalog, initial) = try fixture(monsters:["goblinArcher"],scripted:[1,2,1,3])
        var state = initial; state.battle?.current = "m1"; state.battle?.acted = ["p1","p2"]
        let engine = try GameEngine(catalog:catalog,state:state)
        try engine.apply(.monsterStep); XCTAssertEqual(engine.state.units["m1"]?.ap,1)
        try engine.apply(.monsterStep)
        XCTAssertEqual(engine.state.units["p1"]?.health,7)
        XCTAssertEqual(engine.state.battle?.round,2); XCTAssertEqual(engine.state.battle?.current,"p1")
        XCTAssertEqual(engine.history.filter { $0.command == .monsterStep }.count,2)
    }
    func testMonsterNaturalTwentyPausesAllDownAndNoMoreAutoStepsRun() throws {
        let catalog = try GameCatalog.initial()
        let players = [PlayerSetup(id:"p1",name:"甲",classID:"adventurer"),PlayerSetup(id:"p2",name:"乙",classID:"spellblade")]
        let state = try PVEGameFactory.make(players:players,scenario:.monsterTwenty,seed:1,catalog:catalog)
        let engine = try GameEngine(catalog:catalog,state:state)
        try engine.apply(.startBattle(kind:.pve,monsters:["m1"]))
        XCTAssertEqual(engine.state.battle?.current,"m1")
        let receipt = try engine.apply(.monsterStep)
        XCTAssertEqual(receipt.dice.count,1); XCTAssertTrue(receipt.dice[0].naturalTwenty)
        XCTAssertTrue(engine.state.players.allSatisfy { !$0.isAlive })
        XCTAssertTrue(engine.state.pauseReasons.contains(.allPlayersDown))
        XCTAssertThrowsError(try engine.apply(.monsterStep))
        try engine.setPause(.manual,enabled:true)
        try engine.apply(.revive("p1"))
        XCTAssertEqual(engine.state.units["p1"]?.health,6)
        XCTAssertEqual(engine.state.units["p1"]?.canActFromRound,2)
        XCTAssertTrue(engine.state.pauseReasons.contains(.manual))
    }
}
