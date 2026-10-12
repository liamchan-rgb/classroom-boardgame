import XCTest
@testable import ClassroomGameCore

final class EdgeRuleTests: XCTestCase {
    func testSpendingLastActionPointAdvancesOnlyAfterDamageResolves() throws {
        let (catalog, initial) = try fixture(monsters: ["stoneGuardian"], scripted: [1])
        var state = initial; state.units["p1"]?.ap = 1; state.remainingSeconds = 4
        let engine = try GameEngine(catalog: catalog, state: state)
        let receipt = try engine.apply(.attack(actor: "p1", target: "m1"))
        XCTAssertEqual(engine.state.units["m1"]?.shield, 5)
        XCTAssertEqual(engine.state.units["p1"]?.ap, 0)
        XCTAssertEqual(engine.state.battle?.current, "p2")
        XCTAssertEqual(engine.state.remainingSeconds, 30)
        XCTAssertEqual(receipt.after, engine.state)
        try engine.undo(); XCTAssertEqual(engine.state, state)
    }
    func testShieldTakesMaximumPersistsAfterBattleAndClearsOnDown() throws {
        let (catalog, initial) = try fixture(monsters: ["stoneGuardian"])
        var state = initial
        state.units["p1"]?.shield = 5; state.units["p1"]?.ap = 6
        state.units["p1"]?.inventory["shieldPotion"] = 1
        let engine = try GameEngine(catalog: catalog, state: state)
        try engine.apply(.useItem(actor: "p1", item: "shieldPotion", target: "p1"))
        XCTAssertEqual(engine.state.units["p1"]?.shield, 8)
        try engine.apply(.cast(actor: "p1", skill: "simpleGuard", target: nil))
        XCTAssertEqual(engine.state.units["p1"]?.shield, 8)
        try engine.apply(.setHealth(unit: "m1", value: 0, killer: nil))
        XCTAssertEqual(engine.state.phase, .exploration)
        XCTAssertEqual(engine.state.units["p1"]?.shield, 8)
        try engine.apply(.setHealth(unit: "p1", value: 0, killer: nil))
        XCTAssertEqual(engine.state.units["p1"]?.shield, 0)
    }
    func testWeakerBuffDoesNotReplaceOrRefreshStrongerBuff() throws {
        let (catalog, initial) = try fixture(classes: ["ranger", "adventurer"])
        var state = initial
        let stronger = DamageBuff(amount: 5, roundsLeft: 1, appliedRound: 0)
        state.units["p2"]?.damageBuff = stronger
        let engine = try GameEngine(catalog: catalog, state: state)
        try engine.apply(.cast(actor: "p1", skill: "rally", target: .node(2)))
        XCTAssertEqual(engine.state.units["p2"]?.damageBuff, stronger)
        XCTAssertEqual(engine.state.units["p1"]?.damageBuff?.amount, 2)
    }
    func testLastLivingPvPFactionWinsAfterKnockoutPointsAreIncluded() throws {
        let (catalog, initial) = try fixture(monsters: [], kind: .teamPvp, scripted: [6])
        var state = initial; state.units["p2"]?.teamID = "orange"; state.units["p2"]?.health = 1
        state.units["p1"]?.shield = 7; state.units["p2"]?.coins = 25
        let engine = try GameEngine(catalog: catalog, state: state)
        try engine.apply(.attack(actor: "p1", target: "p2"))
        XCTAssertEqual(engine.state.phase, .settlement)
        XCTAssertEqual(engine.state.lastOutcome?.winners, ["blue"])
        XCTAssertEqual(engine.state.lastOutcome?.personalRanking.first?.score, 2)
        XCTAssertEqual(engine.state.units["p2"]?.coins, 25)
        XCTAssertEqual(engine.state.units["p1"]?.shield, 7)
        XCTAssertNil(engine.state.battle)
    }
    func testNaturalTwentyAlsoDefeatsShieldedPvPPlayer() throws {
        let (catalog, initial) = try fixture(monsters: [], kind: .freeForAll, scripted: [20])
        var state = initial
        state.units["p1"]?.equipment.weapon = "legendaryStaff"
        state.units["p2"]?.shield = 100
        let engine = try GameEngine(catalog: catalog, state: state)
        try engine.apply(.attack(actor: "p1", target: "p2"))
        XCTAssertEqual(engine.state.units["p2"]?.health, 0)
        XCTAssertEqual(engine.state.units["p2"]?.shield, 0)
        XCTAssertEqual(engine.state.units["p1"]?.score, 2)
        XCTAssertEqual(engine.state.lastOutcome?.winners, ["p1"])
    }
    func testAnyDamageD20CanTriggerInstantKillButHealingTwentyCannot() throws {
        var (catalog, state) = try fixture(monsters: ["stoneGuardian"], scripted: [1,20])
        let weaponIndex = try XCTUnwrap(catalog.items.firstIndex { $0.id == "trainingSword" })
        catalog.items[weaponIndex].attack?.dice = DiceFormula(sides: 20, count: 2)
        let engine = try GameEngine(catalog: catalog, state: state)
        let result = try engine.apply(.attack(actor: "p1", target: "m1"))
        XCTAssertTrue(try XCTUnwrap(result.dice.first).naturalTwenty)
        XCTAssertEqual(engine.state.units["m1"]?.health, 0)
        let healIndex = try XCTUnwrap(catalog.skills.firstIndex { $0.id == "breather" })
        catalog.skills[healIndex].effects[0].dice = DiceFormula(sides: 20)
        catalog.skills[healIndex].effects[0].amount = 0
        state.units["p1"]?.health = 1; state.units["p1"]?.baseAttributes.maximumHealth = 32
        state.random = RandomState(seed: 1, scripted: [20])
        let healing = try GameEngine(catalog: catalog, state: state)
        let receipt = try healing.apply(.cast(actor: "p1", skill: "breather", target: nil))
        XCTAssertFalse(try XCTUnwrap(receipt.dice.first).naturalTwenty)
        XCTAssertEqual(healing.state.units["p1"]?.health, 21)
        XCTAssertEqual(healing.state.units["m1"]?.health, 24)
    }
}
