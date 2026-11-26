import XCTest
import ClassroomGameCore
import MeadowBattleSupport
@testable import MeadowWorldSupport

final class ExpansionContentTests: XCTestCase {
    func testAllExpansionSkillsAndConsumablesAreMappedInPartyAction() throws {
        let catalog = try GameCatalog.initial()
        XCTAssertEqual(catalog.classes.count, 14)
        XCTAssertEqual(catalog.skills.count, 81)
        XCTAssertEqual(catalog.items.count, 71)
        XCTAssertEqual(catalog.sets.count, 8)
        XCTAssertEqual(catalog.monsters.count, 22)
        XCTAssertEqual(CampaignLottery.tiers.count, 4)

        let monsterAliases: Set<String> = ["stoneSkin", "monsterDragonScale", "monsterDragonFlame"]
        for skill in catalog.skills where !monsterAliases.contains(skill.id) {
            let action = PartyAction(rawValue: skill.id)
            XCTAssertNotNil(action, "Missing PartyAction for skill \(skill.id)")
            XCTAssertEqual(action?.title, skill.name, "Title mismatch for \(skill.id)")
        }
        let consumables = catalog.items.filter { $0.kind == .consumable || $0.kind == .revivalStone }
        XCTAssertEqual(consumables.count, 12)
        for item in consumables {
            let action = PartyAction(rawValue: item.id)
            XCTAssertNotNil(action, "Missing PartyAction for consumable \(item.id)")
            XCTAssertTrue(PartyAction.allConsumables.contains(action!), "Consumable \(item.id) missing from allConsumables")
        }
    }

    func testAllEightSetsUnlockTwoPieceThreePieceAndSetSkills() throws {
        let catalog = try GameCatalog.initial()
        for set in catalog.sets {
            var unit = try GameFactory.player(id: "p1", name: "P1", classID: "adventurer", teamID: "party", nodeID: 0, catalog: catalog)
            let baseStats = try GameRules.attributes(unit, catalog: catalog)
            let weapon = try catalog.item(set.items[0])
            let armor = try catalog.item(set.items[1])
            let accessory = try catalog.item(set.items[2])
            unit.equipment = Equipment(weapon: weapon.id, armor: armor.id, accessory: accessory.id)
            let fullStats = try GameRules.attributes(unit, catalog: catalog)
            let skills = try GameRules.skills(unit, catalog: catalog)
            XCTAssertTrue(skills.contains(set.skill), "Set \(set.id) did not unlock \(set.skill)")
            let expectedHP = baseStats.maximumHealth + weapon.attributes.maximumHealth + armor.attributes.maximumHealth + accessory.attributes.maximumHealth + set.twoPieces.maximumHealth + set.threePieces.maximumHealth
            XCTAssertEqual(fullStats.maximumHealth, expectedHP, set.id)
        }
    }

    func testPreExpansionLegacySavesStillValidateAndLoad() throws {
        let layout = try MeadowMapGenerator.generate(.suggested(total: 10, seed: 31827))
        for version in 0...3 {
            let legacy = try MeadowCampaignSession.journeyCatalog(version: version, expanded: false)
            XCTAssertEqual(legacy.classes.count, 4)
            XCTAssertEqual(legacy.skills.count, 19)
            XCTAssertEqual(legacy.items.count, 18)
            XCTAssertEqual(legacy.sets.count, 2)
            XCTAssertEqual(legacy.monsters.count, 8) // 6 classic + 2 legacy deer skins
            XCTAssertTrue(MeadowCampaignSession.isKnownCatalog(legacy))

            let p1 = try GameFactory.player(id: "p1", name: "P1", classID: "spellblade", teamID: "party", nodeID: layout.map.nodes.first { $0.kind == .start }!.id, catalog: legacy)
            let state = GameState(units: ["p1": p1], teams: [GameTeam(id: "party", name: "林间小队")], map: layout.map, random: RandomState(seed: 1))
            let save = MeadowCampaignSave(layout: layout, archive: GameArchive(catalog: legacy, state: state, history: []), appearanceID: "forester")
            let data = try save.encoded()
            let restored = try MeadowCampaignSession(save: .decoded(data))
            XCTAssertEqual(restored.engine.catalog.classes.count, 4)
        }
    }

    func testGoblinShamanHealsInjuredAllyAndSkipsFullHealthAlly() throws {
        let catalog = try GameCatalog.initial()
        let p1 = try GameFactory.player(id: "p1", name: "P1", classID: "adventurer", teamID: "party", nodeID: 1, catalog: catalog)
        var shaman = try GameFactory.monster(id: "m1", templateID: "goblinShaman", nodeID: 1, catalog: catalog)
        var wolf = try GameFactory.monster(id: "m2", templateID: "wolf", nodeID: 1, catalog: catalog)
        shaman.active = true; wolf.active = true
        let map = GameMap(nodes: [MapNode(id: 0, name: "营地", kind: .start), MapNode(id: 1, name: "林地", kind: .combat)], roads: [MapRoad(0, 1)], revealed: [0, 1])

        // Injured ally: shaman should prioritize shamanMend (priority 1) and heal m2 by 6.
        wolf.health = 4
        var injuredState = GameState(units: ["p1": p1, "m1": shaman, "m2": wolf], teams: [GameTeam(id: "party", name: "小队")], map: map, random: RandomState(seed: 7))
        injuredState.pauseReasons = []; injuredState.phase = .pve
        injuredState.battle = BattleState(kind: .pve, queue: ["m1", "m2", "p1"], current: "m1")
        let engine1 = try GameEngine(catalog: catalog, state: injuredState)
        let receipt1 = try engine1.apply(.monsterStep)
        XCTAssertEqual(receipt1.events.first { $0.kind == "aiAction" }?.detail, "部落愈合")
        XCTAssertEqual(receipt1.after.units["m2"]?.health, 10)

        // Full-health ally: shaman should NOT waste shamanMend; it casts shamanChant instead.
        wolf.health = wolf.baseAttributes.maximumHealth
        var healthyState = GameState(units: ["p1": p1, "m1": shaman, "m2": wolf], teams: [GameTeam(id: "party", name: "小队")], map: map, random: RandomState(seed: 7))
        healthyState.pauseReasons = []; healthyState.phase = .pve
        healthyState.battle = BattleState(kind: .pve, queue: ["m1", "m2", "p1"], current: "m1")
        let engine2 = try GameEngine(catalog: catalog, state: healthyState)
        let receipt2 = try engine2.apply(.monsterStep)
        XCTAssertNotEqual(receipt2.events.first { $0.kind == "aiAction" }?.detail, "部落愈合")
        XCTAssertEqual(receipt2.events.first { $0.kind == "aiAction" }?.detail, "战鼓呐喊")
    }

    func testAllFourteenClassesWorkInTrainingEncounter() throws {
        let catalog = try GameCatalog.initial()
        for cls in catalog.classes {
            let encounter = try PartyEncounter(seed: 101, playerClassID: cls.id)
            XCTAssertEqual(encounter.state.units["p1"]?.templateID, cls.id)
            let actions = encounter.actions(for: "p1")
            XCTAssertEqual(actions.count, 4, "Expected attack + 3 skills for \(cls.id)")
        }
    }
}
