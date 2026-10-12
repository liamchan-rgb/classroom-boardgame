import XCTest
@testable import ClassroomGameCore

final class IntegrationBoundaryTests: XCTestCase {
    func testThreeClassesCompleteMixedBattleUsingInteractionAndAutomaticSteps() throws {
        let catalog = try GameCatalog.initial()
        let players = [PlayerSetup(id:"p1",name:"冒险者",classID:"adventurer"),PlayerSetup(id:"p2",name:"魔剑士",classID:"spellblade"),PlayerSetup(id:"p3",name:"龙骑士",classID:"dragonKnight")]
        var state = try PVEGameFactory.make(players:players,seed:1,catalog:catalog)
        for id in state.units.keys { state.units[id]?.nodeID = 2 }
        state.random.scripted = [20,19,18,10,9,8] + Array(repeating:1,count:1000)
        let play = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        try play.apply(.startBattle(kind:.pve,monsters:["m1","m2","m3"]))
        var steps = 0
        while play.engine.state.battle != nil && !play.engine.state.pauseReasons.contains(.allPlayersDown) {
            steps += 1; XCTAssertLessThan(steps,200); if steps >= 200 { break }
            let actor = try XCTUnwrap(play.actor)
            if actor.kind == .monster { try play.apply(.monsterStep); continue }
            let target = try XCTUnwrap(play.engine.state.units.values.filter { $0.kind == .monster && $0.isAlive }.sorted { $0.id > $1.id }.first)
            let skills = try GameRules.skills(actor,catalog:catalog).filter { id in (try? catalog.skill(id).effects.contains { $0.kind == .damage }) == true }
            var performed = false
            for id in skills {
                let skill = try catalog.skill(id)
                play.choose(.skill(id)); play.selectTarget(skill.target == .enemiesAtNode ? .node(2) : .unit(target.id))
                if play.preview.allowed { try play.perform(); performed = true; break }
            }
            if !performed { play.choose(.attack); play.selectTarget(.unit(target.id)); try play.perform() }
        }
        XCTAssertEqual(play.engine.state.phase,.exploration)
        XCTAssertTrue(play.engine.state.units.values.filter { $0.kind == .monster }.allSatisfy { !$0.isAlive })
        XCTAssertEqual(play.engine.state.players.reduce(0) { $0 + $1.score },7)
        XCTAssertGreaterThan(play.engine.history.filter { $0.command == .monsterStep }.count,0)
        XCTAssertEqual(play.engine.history.count,steps+1)
    }
    func testMovementActivatesMonsterImmediatelyButItsAutomaticTurnWaitsNextRound() throws {
        let (catalog, initial) = try fixture(monsters:["stoneGuardian"],scripted:[20,1,1])
        var state = initial; state.units["p1"]?.ap = 6; state.units["p1"]?.equipment.weapon = "huntingBow"
        state.units["m2"] = try GameFactory.monster(id:"m2",templateID:"goblinArcher",nodeID:3,catalog:catalog)
        let play = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:state))
        play.choose(.move); try play.tapNode(3); try play.perform()
        XCTAssertEqual(play.engine.state.battle?.queue.first,"m2")
        XCTAssertEqual(play.engine.state.battle?.current,"p1")
        XCTAssertEqual(play.engine.state.units["m2"]?.canActFromRound,2)
        XCTAssertEqual(play.path,[3])
        play.choose(.attack); play.selectTarget(.unit("m2")); try play.perform()
        XCTAssertEqual(play.engine.state.units["m2"]?.health,11)
    }
    func testFailedUnpauseKeepsClockFrozenAndShortcutSevenAlwaysMeansHost() throws {
        let (catalog, initial) = try fixture()
        var state = initial; state.pauseReasons = [.manual]
        let failed = try GameEngine(catalog:catalog,state:state,persist:{ _ in throw GameError("写入失败") })
        XCTAssertThrowsError(try failed.setPause(.manual,enabled:false))
        XCTAssertEqual(failed.state,state)
        _ = try failed.advanceClock(by:100); XCTAssertEqual(failed.state.remainingSeconds,30)
        let players = [PlayerSetup(id:"p1",name:"学生",classID:"adventurer"),PlayerSetup(id:"p7",name:"教师",classID:"dragonKnight",host:true)]
        let game = try PVEGameFactory.make(players:players,seed:1,catalog:catalog)
        let play = PVEPlaySession(engine:try GameEngine(catalog:catalog,state:game))
        XCTAssertEqual(play.shortcutPlayer(7)?.id,"p7")
        XCTAssertNil(play.shortcutPlayer(2)); XCTAssertNil(play.shortcutPlayer(8))
    }
}
