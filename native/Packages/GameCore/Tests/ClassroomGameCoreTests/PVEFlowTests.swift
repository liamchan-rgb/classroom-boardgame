import XCTest
@testable import ClassroomGameCore

final class PVEFlowTests: XCTestCase {
    func testSetupSixStudentsAndHostAndRejectsInvalidParticipation() throws {
        let catalog = try GameCatalog.initial()
        var players = (1...6).map { PlayerSetup(id:"p\($0)",name:"学生\($0)",classID:catalog.classes[($0-1)%4].id) }
        players.append(PlayerSetup(id:"p7",name:"主持人",classID:"dragonKnight",host:true))
        let state = try PVEGameFactory.make(players:players,seed:1,catalog:catalog)
        let session = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        XCTAssertEqual(state.players.count,7)
        for player in players {
            session.selectPlayer(player.id); session.selectReward(player.id)
            try session.reward(ResourceReward(coins:10,score:2))
            XCTAssertEqual(session.engine.state.units[player.id]?.score,2)
            XCTAssertEqual(session.actor?.id,player.id)
        }
        XCTAssertEqual(try GameRules.teamRankings(session.engine.state).first?.score,14)
        players[6].host = false
        XCTAssertThrowsError(try PVEGameFactory.make(players:players,seed:1,catalog:catalog))
    }
    func testPreviewSelectionsAndInvalidCommandsNeverRollSaveOrResetClock() throws {
        let (catalog, initial) = try fixture(monsters:["stoneGuardian"],scripted:[2])
        var state = initial; state.remainingSeconds = 17; state.units["m1"]?.nodeID = 3
        var saves = 0
        let session = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state,persist:{ _ in saves += 1 }))
        session.choose(.attack); session.selectTarget(.unit("m1"))
        for _ in 0..<10 { XCTAssertFalse(session.preview.allowed) }
        XCTAssertThrowsError(try session.perform())
        XCTAssertEqual(session.engine.state,state); XCTAssertEqual(saves,0)
        session.choose(.move); try session.tapNode(3)
        XCTAssertTrue(session.preview.allowed)
        XCTAssertEqual(session.engine.state.random,state.random)
        XCTAssertEqual(session.engine.state.remainingSeconds,17)
    }
    func testContinuousPathStopsAtFirstEnemyAndAllPlayersJoinAtOriginalPositions() throws {
        let catalog = try GameCatalog.initial()
        let players = [PlayerSetup(id:"p1",name:"甲",classID:"adventurer"),PlayerSetup(id:"p2",name:"乙",classID:"spellblade")]
        var state = try PVEGameFactory.make(players:players,seed:1,catalog:catalog)
        state.random.scripted = [20,19,10]
        let session = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        session.choose(.move); try session.tapNode(2); try session.tapNode(3); try session.tapNode(5)
        XCTAssertEqual(session.preview.cost,1); XCTAssertEqual(session.preview.path,[1,2])
        try session.perform()
        XCTAssertEqual(session.engine.state.units["p1"]?.nodeID,2)
        XCTAssertEqual(session.engine.state.units["p2"]?.nodeID,1)
        XCTAssertEqual(session.engine.state.phase,.pve)
        XCTAssertEqual(session.engine.state.battle?.queue,["p1","p2","m1"])
        XCTAssertEqual(session.action,.attack)
    }
    func testMovingAttackMovingUsesActualActorAndDoesNotChangeRewardSelection() throws {
        let (catalog, initial) = try fixture(monsters:["stoneGuardian"],scripted:[1])
        var state = initial; state.units["p1"]?.ap = 6; state.units["p1"]?.equipment.weapon = "huntingBow"
        let session = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        session.selectReward("p2")
        session.choose(.move); try session.tapNode(1); try session.perform()
        session.choose(.attack); session.selectTarget(.unit("m1")); XCTAssertTrue(session.preview.allowed); try session.perform()
        session.choose(.move); try session.tapNode(2); try session.tapNode(3); try session.perform()
        XCTAssertEqual(session.engine.state.units["p1"]?.ap,2)
        XCTAssertEqual(session.rewardIDs,["p2"])
        try session.reward(ResourceReward(coins:10))
        XCTAssertEqual(session.engine.state.units["p2"]?.coins,10)
        XCTAssertEqual(session.engine.state.battle?.current,"p1")
    }
    func testGroupMovementCannotPartlySpendAndRewardTargetsAreSeparate() throws {
        let (catalog, initial) = try fixture(monsters:[],kind:nil)
        var state = initial; state.units["p2"]?.ap = 0
        let session = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        session.toggleTravel("p2"); session.choose(.move); try session.tapNode(2)
        XCTAssertFalse(session.preview.allowed)
        XCTAssertThrowsError(try session.perform()); XCTAssertEqual(session.engine.state,state)
        try session.apply(.editResources(unit:"p2",value:ResourcePatch(ap:3)))
        try session.perform()
        XCTAssertEqual(session.engine.state.units["p1"]?.ap,2); XCTAssertEqual(session.engine.state.units["p2"]?.ap,2)
        XCTAssertEqual(session.rewardIDs,["p1"])
    }
    func testTimeoutClearsPendingTargetsInsteadOfAttackingAsNextPlayer() throws {
        let (catalog, state) = try fixture()
        let session = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        session.choose(.attack); session.selectTarget(.unit("m1"))
        _ = try session.engine.advanceClock(by:30); session.synchronize()
        XCTAssertEqual(session.actor?.id,"p2"); XCTAssertNil(session.target)
        XCTAssertNil(session.command); XCTAssertThrowsError(try session.perform())
    }
    func testAllCompleteEffectsAndVictoryViaPlayerInteractionInTwentyScenario() throws {
        let catalog = try GameCatalog.initial()
        let players = [PlayerSetup(id:"p1",name:"龙骑士",classID:"adventurer"),PlayerSetup(id:"p2",name:"冒险者",classID:"adventurer")]
        let state = try PVEGameFactory.make(players:players,scenario:.playerTwenty,seed:2,catalog:catalog)
        let session = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        session.choose(.move); try session.tapNode(2); try session.perform()
        XCTAssertEqual(session.actor?.id,"p1")
        session.choose(.skill("dragonFlame")); session.selectTarget(.node(2)); XCTAssertTrue(session.preview.allowed)
        let before = session.engine.state
        let receipt = try session.perform()
        XCTAssertEqual(receipt.dice.first?.values,[20])
        XCTAssertEqual(session.engine.state.phase,.exploration)
        XCTAssertEqual(session.engine.state.units["p1"]?.health,11)
        XCTAssertEqual(session.engine.state.units["p1"]?.shield,6)
        XCTAssertEqual(session.engine.state.units["p1"]?.score,7)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(session.engine.state.units["p1"]?.coins),30)
        XCTAssertTrue(session.engine.state.units.values.filter { $0.kind == .monster }.allSatisfy { !$0.isAlive })
        let result = session.engine.state
        _ = try session.engine.replay(receipt.id); XCTAssertEqual(session.engine.state,result)
        try session.engine.undo(); XCTAssertEqual(session.engine.state,before)
    }
    func testRescueAndPersonalPotionThroughInteractionController() throws {
        let (catalog, initial) = try fixture()
        var state = initial; state.units["p2"]?.health = 0; state.units["p2"]?.baseAttributes.maximumHealth = 13
        state.units["p1"]?.inventory = ["revivalStone":1,"smallPotion":1]; state.units["p1"]?.ap = 5
        let session = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        session.choose(.rescue); session.selectTarget(.unit("p2")); try session.perform()
        XCTAssertEqual(session.engine.state.units["p2"]?.health,7)
        XCTAssertEqual(session.engine.state.units["p2"]?.canActFromRound,2)
        session.choose(.item("smallPotion")); session.selectTarget(.unit("p2")); try session.perform()
        XCTAssertEqual(session.engine.state.units["p2"]?.health,13)
        XCTAssertEqual(session.engine.state.units["p1"]?.ap,2)
    }
    func testResourceEditingIsOneAtomicOperationAndDoesNotAwardTeacherMonsterKills() throws {
        let (catalog, state) = try fixture(monsters:["stoneGuardian"])
        let engine = try GameEngine(catalog:catalog,state:state)
        XCTAssertThrowsError(try engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:3,coins:-1))))
        XCTAssertEqual(engine.state,state)
        try engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:3,shield:9,ap:7,coins:20,score:-2)))
        XCTAssertEqual(engine.history.count,1); XCTAssertEqual(engine.state.units["p1"]?.shield,9)
        try engine.apply(.editResources(unit:"m1",value:ResourcePatch(health:0)))
        XCTAssertEqual(engine.state.units["p1"]?.score,-2); XCTAssertEqual(engine.state.units["p1"]?.coins,20)
        XCTAssertEqual(engine.state.phase,.exploration)
    }
    func testPublicPlayProjectionAndLogHideUndiscoveredMonsterNamesAndDropChecks() throws {
        let catalog = try GameCatalog.initial()
        let players = [PlayerSetup(id:"p1",name:"甲",classID:"adventurer")]
        let state = try PVEGameFactory.make(players:players,seed:1,catalog:catalog)
        let session = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        let bytes = try JSONEncoder().encode(session.publicFrame())
        let text = try XCTUnwrap(String(data:bytes,encoding:.utf8))
        XCTAssertFalse(text.contains("洞穴巨魔")); XCTAssertFalse(text.contains("哥布林弓手"))
        XCTAssertFalse(text.contains("damageD20Override")); XCTAssertFalse(text.contains("scripted"))
        XCTAssertFalse(text.contains("inventory")); XCTAssertFalse(text.contains("dropCheck"))
    }
}
