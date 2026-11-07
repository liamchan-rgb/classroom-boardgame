import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport
final class EquipmentTests:XCTestCase {
    func testEquipUnequipUsesOriginalInventoryTransferWithoutRefreshingResources() throws {
        let gear=try TrainingLoadout(),before=gear.engine.state
        XCTAssertEqual(gear.units["p1"]?.equipment.weapon,"trainingSword")
        let off=try gear.equip(nil);XCTAssertNil(off.after.units["p1"]?.equipment.weapon);XCTAssertEqual(off.after.units["p1"]?.inventory["trainingSword"],1)
        let on=try gear.equip("trainingSword");XCTAssertEqual(on.after.units["p1"]?.equipment.weapon,"trainingSword");XCTAssertNil(on.after.units["p1"]?.inventory["trainingSword"])
        XCTAssertEqual(before.units,on.after.units);XCTAssertEqual(before.random,on.after.random)
        let same=gear.engine.state;XCTAssertThrowsError(try gear.equip("legendaryScepter"));XCTAssertEqual(same,gear.engine.state)
    }
    func testBattleCopiesEquipmentAndRespectsUnarmedAttackAndBattleEquipRestrictions() throws {
        let gear=try TrainingLoadout();try gear.equip(nil)
        let party=try PartyEncounter(seed:52,loadouts:gear.units)
        XCTAssertNil(party.state.units["p1"]?.equipment.weapon);XCTAssertEqual(party.state.units["p1"]?.inventory["trainingSword"],1)
        try party.engine.apply(.endTurn(actor:"p2",timedOut:false))
        XCTAssertFalse(party.preview(.attack,target:"m1").allowed)
        XCTAssertTrue(party.preview(.breather,target:"p1").allowed)
        let before=party.state;XCTAssertThrowsError(try party.engine.apply(.equip(unit:"p1",slot:.weapon,item:"trainingSword")));XCTAssertEqual(before,party.state)
        try gear.equip("trainingSword");XCTAssertNil(party.state.units["p1"]?.equipment.weapon)
        let next=try PartyEncounter(seed:52,loadouts:gear.units);try next.engine.apply(.endTurn(actor:"p2",timedOut:false))
        let intent=try XCTUnwrap(next.prepare(.attack,target:"m1"));let result=try XCTUnwrap(next.commit(intent.id));XCTAssertEqual(result.dice.first?.formula.sides,6)
    }
    func testVisualMappingIsAnActualCatalogItemAndBothAppearancesSupplyArmedAndEmptyAtlases() throws {
        var root=URL(fileURLWithPath:#filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath:root.appendingPathComponent("native/ClassroomProbe/Resources/hero-gait.json").path) && root.path != "/" { root.deleteLastPathComponent() }
        let data=try Data(contentsOf:root.appendingPathComponent("native/ClassroomProbe/Resources/hero-gait.json"))
        struct Spec:Decodable { let equipmentVisuals:[String:EquipmentVisualBinding] }
        let spec=try JSONDecoder().decode(Spec.self,from:data),catalog=try GameCatalog.initial()
        for (id,b) in spec.equipmentVisuals { XCTAssertEqual(id,b.itemID);XCTAssertEqual(try catalog.item(id).slot,.weapon) }
        let json=try JSONSerialization.jsonObject(with:data) as! [String:Any],modular=json["modularP1"] as! [String:Any]
        for preset in modular["loadouts"] as! [[String:Any]] {
            let names=preset["weaponAtlasNames"] as! [String:[String]]
            for state in ["trainingSword","huntingBow","none"] {
                XCTAssertEqual(names[state]?.count,2)
                for name in names[state] ?? [] { XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("native/ClassroomProbe/Resources/Assets.xcassets/\(name).imageset/Contents.json").path)) }
            }
        }
    }
}
