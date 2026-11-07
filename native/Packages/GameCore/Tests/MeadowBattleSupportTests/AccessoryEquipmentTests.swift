import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport
final class AccessoryEquipmentTests:XCTestCase {
    func testSingleAccessorySlotConservesBothItemsWithoutChangingWeaponOrArmor() throws {
        let g=try TrainingLoadout();try g.equip("huntingBow");try g.equipArmor("runeArmor")
        for id in ["powerBadge","actionRing","powerBadge",nil,"actionRing",nil] {
            try g.equipAccessory(id);let u=g.units["p1"]!
            XCTAssertEqual(u.equipment.accessory,id);XCTAssertEqual(u.equipment.weapon,"huntingBow");XCTAssertEqual(u.equipment.armor,"runeArmor")
            for item in ["powerBadge","actionRing"] { XCTAssertEqual((u.inventory[item] ?? 0)+(u.equipment.accessory==item ? 1:0),1) }
        }
    }
    func testEquipDoesNotRefillAPOrHealthAndRingDoesNotRaiseCap() throws {
        let g=try TrainingLoadout();try g.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:5,ap:1)))
        let before=g.units["p1"]!;try g.equipAccessory("actionRing");let u=g.units["p1"]!,stats=try GameRules.attributes(u,catalog:g.engine.catalog)
        XCTAssertEqual(u.ap,1);XCTAssertEqual(u.health,5);XCTAssertEqual(stats.baseAP,before.baseAttributes.baseAP+1);XCTAssertEqual(stats.maximumAP,before.baseAttributes.maximumAP)
        try g.equipAccessory("powerBadge");XCTAssertEqual(g.units["p1"]?.ap,1);XCTAssertEqual(g.units["p1"]?.health,5)
    }
    func testWrongSlotAndCombatEquipAreRejectedAtomically() throws {
        let g=try TrainingLoadout();let before=g.engine.state
        XCTAssertThrowsError(try g.equipAccessory("leatherArmor"));XCTAssertEqual(g.engine.state,before)
        try g.equipAccessory("powerBadge");let p=try PartyEncounter(seed:47,loadouts:g.units);let state=p.state
        XCTAssertThrowsError(try p.engine.apply(.equip(unit:"p1",slot:.accessory,item:"actionRing")));XCTAssertEqual(p.state,state)
    }
    func testBadgePreviewAndContactReceiptAgreeWithoutTemporaryBuff() throws {
        let g=try TrainingLoadout();try g.equipAccessory("powerBadge");let p=try PartyEncounter(seed:47,loadouts:g.units)
        try p.engine.apply(.endTurn(actor:"p2",timedOut:false));let before=p.state
        let intent=try XCTUnwrap(p.prepare(.attack,target:"m1")),staged=try XCTUnwrap(p.confirmedReceipt)
        XCTAssertEqual(p.state,before);XCTAssertNil(before.units["p1"]?.damageBuff)
        let dice=BattleDice.channels(.attack,actor:before.units["p1"]!,target:before.units["m1"]!,catalog:p.engine.catalog,receipt:staged)
        XCTAssertEqual(dice.filter{$0.color=="yellow"}.compactMap(\.value),[2])
        let result=try XCTUnwrap(p.commit(intent.id));let roll=try XCTUnwrap(result.dice.first{$0.source=="damage"})
        XCTAssertEqual(result.before.units["m1"]!.health-result.after.units["m1"]!.health,roll.total+2)
        XCTAssertNil(p.state.units["p1"]?.damageBuff);XCTAssertNil(try p.commit(intent.id))
    }
    func testBadgeAddsToSkillAndStacksWithOriginalRallySeparately() throws {
        let g=try TrainingLoadout();try g.equipAccessory("powerBadge");let p=try PartyEncounter(seed:47,loadouts:g.units)
        let rally=try XCTUnwrap(p.prepare(.rally,target:"p1"));_=try p.commit(rally.id)
        try p.engine.apply(.endTurn(actor:"p2",timedOut:false));let actor=p.state.units["p1"]!
        let intent=try XCTUnwrap(p.prepare(.heavyStrike,target:"m1"));let r=try XCTUnwrap(p.confirmedReceipt)
        let dice=BattleDice.channels(.heavyStrike,actor:actor,target:p.state.units["m1"]!,catalog:p.engine.catalog,receipt:r)
        XCTAssertEqual(dice.filter{$0.color=="yellow"}.compactMap(\.value),[2,2,2])
        let receipt=try XCTUnwrap(p.commit(intent.id)),roll=try XCTUnwrap(receipt.dice.first{$0.source=="damage"})
        XCTAssertEqual(receipt.before.units["m1"]!.health-receipt.after.units["m1"]!.health,min(18,roll.total+4))
        XCTAssertEqual(p.state.units["p1"]?.damageBuff?.amount,2)
    }
    func testRingStartsAtFourAndRefillsThroughOriginalRoundRules() throws {
        let g=try TrainingLoadout();try g.equipAccessory("actionRing");let p=try PartyEncounter(seed:47,loadouts:g.units)
        XCTAssertEqual(p.state.units["p1"]?.ap,4)
        try p.engine.apply(.endTurn(actor:"p2",timedOut:false));XCTAssertEqual(p.current,"p1")
        for action in [PartyAction.smallPotion,.smallPotion,.simpleGuard,.attack] {
            let i=try XCTUnwrap(p.prepare(action,target:action == .attack ? "m1":"p1"));_=try p.commit(i.id)
        }
        XCTAssertEqual(p.state.units["p1"]?.ap,0);XCTAssertEqual(p.current,"m1")
    }
    func testRingRoundRefillAndRemovalPreserveBankedAP() throws {
        let g=try TrainingLoadout();try g.equipAccessory("actionRing");let p=try PartyEncounter(seed:47,loadouts:g.units)
        for id in ["p2","p1","m1","m2"] { XCTAssertEqual(p.current,id);try p.engine.apply(.endTurn(actor:id,timedOut:false)) }
        XCTAssertEqual(p.round,2);XCTAssertEqual(p.state.units["p1"]?.ap,4)
        try g.engine.apply(.editResources(unit:"p1",value:ResourcePatch(ap:6)))
        try g.equipAccessory(nil);XCTAssertEqual(g.units["p1"]?.ap,6)
        let stats=try GameRules.attributes(g.units["p1"]!,catalog:g.engine.catalog);XCTAssertEqual(stats.baseAP,3);XCTAssertEqual(stats.maximumAP,8)
        let banked=try PartyEncounter(seed:47,loadouts:g.units);XCTAssertEqual(banked.state.units["p1"]?.ap,6)
    }
    func testAccessoryReadoutReportsPersistentAttributesAndNoFakeBuff() throws {
        let g=try TrainingLoadout();XCTAssertNil(try AccessoryReadout.make(g.units["p1"]!,catalog:g.engine.catalog))
        for (id,damage,ap) in [("powerBadge",2,0),("actionRing",0,1)] {
            try g.equipAccessory(id);let r=try XCTUnwrap(AccessoryReadout.make(g.units["p1"]!,catalog:g.engine.catalog))
            XCTAssertEqual(r.damageBonus,damage);XCTAssertEqual(r.baseAPBonus,ap);XCTAssertNil(g.units["p1"]?.damageBuff)
        }
    }
}
