import XCTest
@testable import ClassroomGameCore

final class CatalogTests: XCTestCase {
    func testConfirmedInitialCountsAndClassProfiles() throws {
        let catalog = try GameCatalog.initial()
        XCTAssertEqual(catalog.classes.count, 4); XCTAssertEqual(catalog.skills.count, 19)
        XCTAssertEqual(catalog.items.count, 18); XCTAssertEqual(catalog.monsters.count, 6); XCTAssertEqual(catalog.sets.count, 2)
        XCTAssertEqual(catalog.classes.map { $0.attributes.maximumHealth }, [12, 18, 24, 32])
        for value in catalog.classes {
            XCTAssertEqual(value.attributes.baseAP, 3); XCTAssertEqual(value.attributes.maximumAP, 8); XCTAssertEqual(value.skills.count, 3)
        }
        XCTAssertEqual(catalog.rules.mapDistribution.values.reduce(0, +), 10)
    }
    func testAllTwelveClassSkillsAndBothSetSkillsMatchTheSpecification() throws {
        let catalog = try GameCatalog.initial()
        let expected: [(String, Int, Int, Int)] = [
            ("heavyStrike",1,0,2),("breather",1,0,2),("simpleGuard",1,0,2),
            ("ambush",2,1,2),("support",1,1,2),("rally",1,0,2),
            ("runeSlash",2,1,2),("runeWard",2,1,2),("battleRune",1,1,2),
            ("dragonFlame",2,1,1),("dragonScaleWard",2,1,2),("dragonOrder",2,1,1),
            ("starlightPulse",2,1,1),("dragonSoulWard",2,1,1)]
        for (id,cost,range,uses) in expected {
            let value = try catalog.skill(id)
            XCTAssertEqual(value.cost,cost,id); XCTAssertEqual(value.range,range,id); XCTAssertEqual(value.uses,uses,id)
        }
        let damage: [(String, Int, Int, Int)] = [("heavyStrike",6,1,2),("ambush",8,2,2),("runeSlash",12,2,2),("dragonFlame",20,1,6),("starlightPulse",12,1,4)]
        for (id,sides,count,flat) in damage {
            XCTAssertEqual(try catalog.skill(id).effects.first?.dice, DiceFormula(sides:sides,count:count,flat:flat))
        }
        let dragon = try catalog.skill("dragonFlame")
        XCTAssertEqual(dragon.effects.map(\.amount), [0,6,6,2]); XCTAssertEqual(dragon.effects.map(\.scope), [.targets,.caster,.caster,.caster])
        XCTAssertEqual(try catalog.skill("dragonOrder").effects.map(\.amount), [6,8,4])
        XCTAssertEqual(try catalog.skill("dragonScaleWard").effects.map(\.amount), [12,10,2])
        XCTAssertEqual(try catalog.skill("runeWard").effects.map(\.amount), [8,6])
        XCTAssertEqual(try catalog.skill("rally").effects[0].rounds,1)
        XCTAssertEqual(try catalog.skill("battleRune").effects.last?.rounds,2)
    }
    func testAllPricesMonsterStatsAndIndependentRareDrops() throws {
        let catalog = try GameCatalog.initial()
        XCTAssertEqual(catalog.items.compactMap(\.purchasePrice), [10,50,100,200,30,60,50,100,10,20,15,30])
        XCTAssertEqual(catalog.items.map(\.sellPrice), [5,25,50,100,15,30,25,50,5,10,7,15,80,45,45,130,75,75])
        XCTAssertEqual(catalog.monsters.map { $0.attributes.maximumHealth }, [8,12,12,24,48,72])
        XCTAssertEqual(catalog.monsters.map(\.shield), [0,0,0,6,0,10])
        XCTAssertEqual(catalog.monsters.map { $0.attributes.baseAP }, [1,2,2,2,3,3])
        let expected = [[1,1,1,1,1,1],[1,1,1,1,1,1],[1,1,1,1,1,1],[2,2,2,2,2,2],[8,8,8,4,4,4],[4,4,4,8,8,8]]
        for (index, monster) in catalog.monsters.enumerated() {
            XCTAssertEqual(monster.drops.suffix(6).map(\.percent),expected[index])
            XCTAssertEqual(monster.drops.first?.coins,monster.boss ? 30 : 5)
            XCTAssertEqual(monster.drops.first?.percent,monster.boss ? 100 : 50)
            XCTAssertEqual(monster.drops.count,monster.boss ? 11 : 9)
        }
        XCTAssertNotEqual(try catalog.skill("dragonFlame"),try catalog.skill("monsterDragonFlame"))
    }
    func testInvalidReferencesAndProbabilitiesAreRejected() throws {
        var catalog = try GameCatalog.initial()
        catalog.monsters[0].drops[0].percent = 101
        XCTAssertThrowsError(try catalog.validate())
        catalog = try GameCatalog.initial(); catalog.classes[0].skills[0] = "missing"
        XCTAssertThrowsError(try catalog.validate())
        catalog = try GameCatalog.initial(); catalog.items[12].slot = .armor
        XCTAssertThrowsError(try catalog.validate())
    }
}
