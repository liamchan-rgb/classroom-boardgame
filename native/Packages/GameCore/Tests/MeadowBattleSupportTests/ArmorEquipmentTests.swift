import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport
final class ArmorEquipmentTests:XCTestCase {
    func testArmorTransfersConserveInventoryAndDoNotChangeWeapon() throws {
        let g=try TrainingLoadout();try g.equip("huntingBow")
        for item in ["leatherArmor","runeArmor","leatherArmor",nil,"runeArmor",nil] {
            try g.equipArmor(item)
            let u=try XCTUnwrap(g.units["p1"])
            XCTAssertEqual(u.equipment.weapon,"huntingBow")
            for id in ["leatherArmor","runeArmor"] { XCTAssertEqual((u.inventory[id] ?? 0)+(u.equipment.armor==id ? 1:0),1) }
        }
    }
    func testArmorRaisesOnlyMaximumHealthAndUnequipClampsWithoutHealing() throws {
        let g=try TrainingLoadout();let original=try XCTUnwrap(g.units["p1"])
        let base=try GameRules.attributes(original,catalog:g.engine.catalog)
        for (id,bonus) in [("leatherArmor",4),("runeArmor",8)] {
            try g.equipArmor(id);let u=g.units["p1"]!,stats=try GameRules.attributes(u,catalog:g.engine.catalog)
            XCTAssertEqual(stats.maximumHealth,base.maximumHealth+bonus);XCTAssertEqual(u.health,original.health)
            XCTAssertEqual(stats.damage,base.damage);XCTAssertEqual(stats.maximumAP,base.maximumAP)
        }
        try g.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:base.maximumHealth+8)))
        try g.equipArmor(nil);XCTAssertEqual(g.units["p1"]?.health,base.maximumHealth)
    }
    func testInvalidArmorSlotIsAtomic() throws {
        let g=try TrainingLoadout(),before=g.engine.state
        XCTAssertThrowsError(try g.equipArmor("huntingBow"));XCTAssertEqual(g.engine.state,before)
    }
    func testPartyCopiesArmorAndUsesOriginalHealingLimit() throws {
        let g=try TrainingLoadout();try g.equipArmor("runeArmor")
        let p=try PartyEncounter(seed:47,loadouts:g.units);let unit=p.state.units["p1"]!
        XCTAssertEqual(unit.equipment.armor,"runeArmor")
        let maxHP=try GameRules.attributes(unit,catalog:p.engine.catalog).maximumHealth
        XCTAssertEqual(maxHP,unit.baseAttributes.maximumHealth+8)
        XCTAssertEqual(BattleDice.channels(.revivalStone,actor:p.state.units["p2"]!,target:unit,catalog:p.engine.catalog).first?.value,(maxHP+1)/2)
        try p.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:maxHP-2)))
        _=try XCTUnwrap(p.prepare(.largePotion,target:"p1"));let receipt=try XCTUnwrap(p.confirmedReceipt)
        XCTAssertEqual(receipt.after.units["p1"]?.health,maxHP)
        XCTAssertEqual(receipt.before.units["p1"]?.health,maxHP-2)
        XCTAssertThrowsError(try p.engine.apply(.equip(unit:"p1",slot:.armor,item:nil)))
    }
}
