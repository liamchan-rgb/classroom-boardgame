import XCTest
@testable import ClassroomGameCore

final class PresentationTests: XCTestCase {
    func testSevenPlayersMixedQueueAndLiveSkillDefinitions() throws {
        var (catalog,state) = try fixture(classes:["adventurer","ranger","spellblade","dragonKnight","adventurer","ranger","dragonKnight"],monsters:["slime","goblinArcher","caveTroll"])
        state.units["p1"]?.name = "晨曦森林守护者小队长安然"
        state.units["p2"]?.name = "AlexandriaWinterbrookJoy"
        state.units["p7"]?.host = true
        state.units["p5"]?.health = 0
        state.units["p6"]?.canActFromRound = 2
        let skillID = catalog.classes[0].skills[0]
        let index = try XCTUnwrap(catalog.skills.firstIndex { $0.id == skillID })
        catalog.skills[index].name = "本局修改的技能"
        catalog.skills[index].effects[0].amount = 9
        let play = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        let archive = play.engine.archive
        let frame = try play.publicFrame()
        XCTAssertEqual(frame.snapshot.units.count,10)
        XCTAssertEqual(frame.snapshot.queueIDs,state.battle?.queue)
        XCTAssertEqual(frame.snapshot.currentName,state.units["p1"]?.name)
        XCTAssertEqual(frame.currentDetails?.skills.first?.name,"本局修改的技能")
        XCTAssertTrue(frame.currentDetails!.skills.first!.detail.contains("9"))
        XCTAssertEqual(frame.snapshot.units.first { $0.id == "p6" }?.canActFromRound,2)
        play.toggleReward("p2"); play.choose(.skill(skillID)); play.selectTarget(.unit("m1"))
        XCTAssertEqual(try play.publicFrame(),frame) // no private selection crosses the boundary
        XCTAssertEqual(play.engine.archive,archive)
    }
    func testUnknownBossAndRewardProduceIdenticalPublicProjection() throws {
        let (catalog,initial) = try fixture(kind:nil)
        var boss = initial
        boss.map.nodes[1].kind = .boss
        boss.units["hidden"] = try GameFactory.monster(id:"hidden",templateID:"ruinDragon",nodeID:4,catalog:catalog)
        var reward = boss
        reward.map.nodes[1].kind = .reward; reward.map.nodes[1].name = "隐藏奖励"
        reward.map.nodes[1].rewardCompleted = true; reward.units["hidden"]?.templateID = "caveTroll"
        XCTAssertEqual(try boss.publicSnapshot(catalog:catalog),try reward.publicSnapshot(catalog:catalog))
        let frame = try PVEPlaySession(engine:GameEngine(catalog:catalog,state:boss)).publicFrame()
        let text = String(decoding:try JSONEncoder().encode(frame),as:UTF8.self)
        XCTAssertFalse(text.contains("ruinDragon")); XCTAssertFalse(text.contains("hidden")); XCTAssertFalse(text.contains("probability"))
        XCTAssertEqual(frame.snapshot.roads,[MapRoad(1,2)])
        XCTAssertTrue(frame.snapshot.nodes.filter { !$0.revealed }.allSatisfy { $0.kind == nil && !$0.claimed })
    }
    func testNaturalTwentyPresentationNeverReexecutesAndRestoresSuppressed() throws {
        let catalog = try GameCatalog.initial()
        let state = try PVEGameFactory.make(players:[PlayerSetup(id:"p1",name:"学生",classID:"dragonKnight")],scenario:.playerTwenty,seed:21,catalog:catalog)
        let engine = try GameEngine(catalog:catalog,state:state)
        try engine.apply(.move(actors:["p1"],path:[1,2]))
        let skill = try catalog.playerClass("dragonKnight").skills[0]
        let receipt = try engine.apply(.cast(actor:"p1",skill:skill,target:.node(2)))
        let after = engine.archive
        var ledger = PresentationLedger()
        let now = Date(timeIntervalSince1970:1000)
        let event = try XCTUnwrap(ledger.submit(receipt,catalog:catalog,now:now))
        XCTAssertTrue(event.text.contains("自然20")); XCTAssertTrue(event.text.contains("积分"))
        XCTAssertEqual(event.units.filter { $0.effects.contains("natural20") }.count,3)
        XCTAssertTrue(event.units.first { $0.id == "p1" }!.effects.contains("heal"))
        XCTAssertTrue(event.units.first { $0.id == "p1" }!.effects.contains("shield"))
        for i in 0..<20 { XCTAssertNil(try ledger.submit(receipt,catalog:catalog,now:now.addingTimeInterval(Double(i)))) }
        XCTAssertFalse(event.isVisible(at:now.addingTimeInterval(10)))
        XCTAssertEqual(engine.archive,after)
        var recovered = PresentationLedger(); recovered.suppressHistory(engine.history)
        XCTAssertNil(try recovered.submit(receipt,catalog:catalog,now:now.addingTimeInterval(100)))
        XCTAssertTrue(recovered.pending.isEmpty)
        XCTAssertEqual(ledger.elapsedDecisionTime(from:now,to:now.addingTimeInterval(2)),0.7,accuracy:0.001)
    }
    func testActualRewardDeltasNoAPAndNoTurnChange() throws {
        let (catalog,state) = try fixture()
        let play = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        play.toggleReward("p2")
        let current = play.actor?.id
        let receipt = try play.reward(ResourceReward(coins:10,ap:1,score:2))
        var ledger = PresentationLedger()
        let event = try XCTUnwrap(ledger.submit(receipt,catalog:catalog,now:Date()))
        XCTAssertTrue(event.text.contains("玩家1：金币+10、积分+2"))
        XCTAssertTrue(event.text.contains("玩家2：金币+10、积分+2"))
        XCTAssertFalse(event.text.contains("AP")); XCTAssertFalse(event.text.contains("行动点"))
        XCTAssertEqual(play.actor?.id,current)
        XCTAssertEqual(play.rewardIDs,["p1","p2"])
    }
    func testPausePanelsAndReadOnlyLegalityPreserveRemainingAndRandom() throws {
        let (catalog,state) = try fixture()
        let play = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        try play.engine.advanceClock(by:13)
        try play.engine.setPause(.manual,enabled:true)
        for reason in [GamePause.book,.editor,.history] {
            try play.engine.setPause(reason,enabled:true)
            let before = play.engine.archive
            play.choose(.attack)
            _ = play.previewForTarget(.unit("m1")); _ = play.legalTargetNodes; _ = try play.publicFrame()
            XCTAssertEqual(play.engine.archive,before)
            XCTAssertNil(try play.engine.advanceClock(by:100))
            try play.engine.setPause(reason,enabled:false)
            XCTAssertEqual(play.engine.state.pauseReasons,[.manual])
            XCTAssertEqual(play.engine.state.remainingSeconds,17)
        }
    }
    func testRescueProjectionKeepsNextRoundAndOneResultGroup() throws {
        let (catalog, initial) = try fixture()
        var state = initial
        state.units["p2"]?.health = 0; state.units["p2"]?.baseAttributes.maximumHealth = 13
        state.units["p1"]?.ap = 5; state.units["p1"]?.inventory = ["revivalStone":1]
        let play = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        play.choose(.rescue); play.selectTarget(.unit("p2"))
        let receipt = try play.perform()
        let frame = try play.publicFrame()
        let rescued = try XCTUnwrap(frame.snapshot.units.first { $0.id == "p2" })
        XCTAssertEqual(rescued.health,7); XCTAssertEqual(rescued.canActFromRound,2)
        XCTAssertEqual(frame.snapshot.queueIDs,state.battle?.queue)
        var ledger = PresentationLedger()
        let event = try XCTUnwrap(ledger.submit(receipt,catalog:catalog,now:Date()))
        XCTAssertEqual(event.units.first { $0.id == "p2" }?.motion,"revive")
        XCTAssertEqual(event.units.first { $0.id == "p2" }?.effects,["revive"])
        XCTAssertTrue(event.text.contains("生命+7")); XCTAssertTrue(event.text.contains("积分+2"))
        let archive = play.engine.archive
        ledger.suppressHistory(play.engine.history)
        XCTAssertNil(try ledger.submit(receipt,catalog:catalog,now:Date()))
        XCTAssertEqual(play.engine.archive,archive)
    }

    func testExplorationDoesNotPublishUncommittedActorOrSkillSelection() throws {
        let (catalog,state) = try fixture(classes:["adventurer","dragonKnight"],kind:nil)
        let play = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        let before = try play.publicFrame()
        XCTAssertNil(before.currentDetails)
        play.selectPlayer("p2"); play.toggleReward("p2"); play.choose(.skill("dragonFlame")); play.selectTarget(.node(2))
        XCTAssertEqual(try play.publicFrame(),before)
        XCTAssertEqual(play.engine.state,state)
    }

}
