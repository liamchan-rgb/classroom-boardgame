import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport

final class CampInventoryTests:XCTestCase {
    private func location()->URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("camp.json") }
    private func cleanup(_ url:URL) { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
    func testColdRestoreKeepsAllSlotsClothesCountsAndResourcesWithoutRegrantingLoans() throws {
        let u=location();defer { cleanup(u) };let a=try CampInventorySession(store:CampSaveStore(url:u))
        try a.equip(slot:.weapon,item:"huntingBow");try a.equip(slot:.armor,item:"leatherArmor");try a.equip(slot:.accessory,item:"actionRing");try a.setAppearance("wayfarer")
        try a.use(item:"smallPotion",target:"p1")
        let original=a.loadout.engine.archive;let restored=try CampInventorySession(store:CampSaveStore(url:u))
        XCTAssertEqual(restored.appearanceID,"wayfarer");XCTAssertEqual(restored.loadout.engine.archive,original)
        XCTAssertEqual(restored.loadout.units["p1"]?.inventory["smallPotion"],1)
        XCTAssertNil(restored.loadout.units["p1"]?.inventory["huntingBow"]);XCTAssertEqual(restored.loadout.units["p1"]?.inventory["trainingSword"],1)
        XCTAssertEqual(restored.loadout.units["p1"]?.ap,2);XCTAssertEqual(restored.loadout.units["p1"]?.health,16)
    }
    func testEquipComparisonUsesOriginalRulesWithoutMutatingOrSaving() throws {
        let u=location();defer { cleanup(u) };let a=try CampInventorySession(store:CampSaveStore(url:u)),before=a.loadout.engine.archive,data=try Data(contentsOf:u)
        let d=try CampInventoryProjection.detail("runeArmor",session:a);XCTAssertTrue(d.enabled)
        XCTAssertTrue(d.comparison.contains("生命：12/12 → 12/20"));XCTAssertEqual(before,a.loadout.engine.archive);XCTAssertEqual(data,try Data(contentsOf:u))
        try a.equip(slot:.armor,item:"runeArmor");XCTAssertEqual(a.loadout.units["p1"]?.health,12)
        try a.loadout.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:20)))
        try a.equip(slot:.armor,item:nil);XCTAssertEqual(a.loadout.units["p1"]?.health,12)
    }
    func testStorageFailureRollsBackEquipmentAndAppearance() throws {
        let u=location();defer { cleanup(u) };let a=try CampInventorySession(store:CampSaveStore(url:u)),before=a.loadout.engine.archive
        try FileManager.default.removeItem(at:u);try FileManager.default.removeItem(at:u.deletingLastPathComponent());try Data("file blocks directory".utf8).write(to:u.deletingLastPathComponent())
        XCTAssertThrowsError(try a.equip(slot:.weapon,item:"greatSword"));XCTAssertEqual(a.loadout.engine.archive,before)
        XCTAssertThrowsError(try a.setAppearance("wayfarer"));XCTAssertEqual(a.appearanceID,"forester")
    }
    func testUnreadableSaveIsNotOverwrittenUntilPreservedExplicitly() throws {
        let u=location();defer { cleanup(u) };try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true)
        let broken=Data("not valid JSON".utf8);try broken.write(to:u)
        let a=try CampInventorySession(store:CampSaveStore(url:u));XCTAssertTrue(a.savingBlocked)
        try a.equip(slot:.weapon,item:"greatSword");XCTAssertEqual(try Data(contentsOf:u),broken);XCTAssertThrowsError(try a.saveNow())
        try a.preserveOldAndEnableSaving();XCTAssertFalse(a.savingBlocked)
        let files=try FileManager.default.contentsOfDirectory(at:u.deletingLastPathComponent(),includingPropertiesForKeys:nil)
        let old=try XCTUnwrap(files.first{$0.lastPathComponent.contains("preserved-")});XCTAssertEqual(try Data(contentsOf:old),broken)
        let b=try CampInventorySession(store:CampSaveStore(url:u));XCTAssertEqual(b.loadout.units["p1"]?.equipment.weapon,"greatSword")
    }
    func testImportValidatesBeforeReplacingAndKeepsPreviousFile() throws {
        let u=location();defer { cleanup(u) };let a=try CampInventorySession(store:CampSaveStore(url:u));try a.equip(slot:.accessory,item:"powerBadge")
        let old=try Data(contentsOf:u),b=try CampInventorySession(store:nil);try b.equip(slot:.weapon,item:nil);try b.equip(slot:.armor,item:"runeArmor");try b.setAppearance("wayfarer")
        try a.importData(b.exportData());XCTAssertEqual(a.appearanceID,"wayfarer");XCTAssertNil(a.loadout.units["p1"]?.equipment.weapon);XCTAssertEqual(a.loadout.units["p1"]?.equipment.armor,"runeArmor")
        let files=try FileManager.default.contentsOfDirectory(at:u.deletingLastPathComponent(),includingPropertiesForKeys:nil);let backup=try XCTUnwrap(files.first{$0.lastPathComponent.contains("preserved-")});XCTAssertEqual(try Data(contentsOf:backup),old)
        let stable=a.loadout.engine.archive,bytes=try Data(contentsOf:u)
        var invalid=try JSONSerialization.jsonObject(with:b.exportData()) as! [String:Any];invalid["formatVersion"]=99
        XCTAssertThrowsError(try a.importData(JSONSerialization.data(withJSONObject:invalid)));XCTAssertEqual(a.loadout.engine.archive,stable);XCTAssertEqual(try Data(contentsOf:u),bytes)
    }
    func testRejectsBattleArchiveUnknownClothesAndUnsupportedEquippedArt() throws {
        let a=try CampInventorySession(store:nil),p=try PartyEncounter(seed:47),before=a.loadout.engine.archive
        for data in [try CampSave(appearanceID:"forester",archive:p.engine.archive).encoded(),try CampSave(appearanceID:"missing",archive:before).encoded()] { XCTAssertThrowsError(try a.importData(data)) }
        var state=before.state;state.units["p1"]?.equipment.weapon="starlightBlade"
        XCTAssertThrowsError(try a.importData(CampSave(appearanceID:"forester",archive:GameArchive(catalog:before.catalog,state:state,history:[])).encoded()))
        var p2=before.state;p2.units["p2"]?.equipment.armor="leatherArmor"
        XCTAssertThrowsError(try a.importData(CampSave(appearanceID:"forester",archive:GameArchive(catalog:before.catalog,state:p2,history:[])).encoded()))
        XCTAssertEqual(a.loadout.engine.archive,before)
    }
    func testFiltersIncludeEquippedItemsAndDepletedRowsDisappear() throws {
        let a=try CampInventorySession(store:nil);try a.equip(slot:.accessory,item:"powerBadge")
        let before=a.loadout.units["p1"]!,catalog=a.loadout.engine.catalog
        let accessories=CampInventoryProjection.entries(before,catalog:catalog,filter:"accessory")
        XCTAssertEqual(Set(accessories.map(\.id)),Set(["powerBadge","actionRing"]))
        let badge=try XCTUnwrap(accessories.first{$0.id=="powerBadge"});XCTAssertEqual(badge.quantity,0);XCTAssertTrue(badge.equipped)
        try a.use(item:"shieldPotion",target:"p1")
        XCTAssertFalse(CampInventoryProjection.entries(a.loadout.units["p1"]!,catalog:catalog,filter:"supplies").contains{$0.id=="shieldPotion"})
        let full=try CampInventoryProjection.detail("smallPotion",session:a);XCTAssertFalse(full.enabled);XCTAssertEqual(full.reason,"目标生命已满，无需使用。")
    }
    func testSuppliesPayOriginalAPAndInvalidUseDoesNotPersist() throws {
        let u=location();defer { cleanup(u) };let a=try CampInventorySession(store:CampSaveStore(url:u));try a.equip(slot:.armor,item:"leatherArmor")
        try a.use(item:"smallPotion",target:"p1");XCTAssertEqual(a.loadout.units["p1"]?.health,16);XCTAssertEqual(a.loadout.units["p1"]?.ap,2)
        let before=a.loadout.engine.archive,bytes=try Data(contentsOf:u)
        XCTAssertThrowsError(try a.use(item:"revivalStone",target:"p2"));XCTAssertEqual(a.loadout.engine.archive,before);XCTAssertEqual(try Data(contentsOf:u),bytes)
    }
    func testInventoryConservationThroughAllSlotsAndEmptyColdRestore() throws {
        let u=location();defer { cleanup(u) };let a=try CampInventorySession(store:CampSaveStore(url:u));let initial=a.loadout.units["p1"]!
        for (slot,ids) in [(ItemSlot.weapon,["huntingBow","greatSword","legendaryStaff","trainingSword"]),(.armor,["leatherArmor","runeArmor"]),(.accessory,["powerBadge","actionRing"])] {
            for id in ids { try a.equip(slot:slot,item:id) };try a.equip(slot:slot,item:nil)
        }
        let b=try CampInventorySession(store:CampSaveStore(url:u));let last=b.loadout.units["p1"]!;XCTAssertTrue(last.equipment.itemIDs.isEmpty)
        for item in initial.inventory.keys.map({$0})+["trainingSword"] { XCTAssertEqual((initial.inventory[item] ?? 0)+(initial.equipment.itemIDs.contains(item) ? 1:0),last.inventory[item]) }
    }
    func testLayoutKeepsAllColumnsInsideSafeAreaOnPhoneAndPad() {
        for (w,h,l,r,b) in [(667.0,375.0,0.0,0.0,0.0),(844,390,47,47,21),(1194,834,0,0,20),(1366,1024,0,0,20)] {
            let a=CampInventoryLayout(width:w,height:h,left:l,right:r,bottom:b)
            XCTAssertGreaterThanOrEqual(a.equipment.x,l);XCTAssertLessThanOrEqual(a.detail.x+a.detail.width,w-r)
            XCTAssertLessThan(a.equipment.x+a.equipment.width,a.bag.x);XCTAssertLessThan(a.bag.x+a.bag.width,a.detail.x)
            XCTAssertGreaterThan(a.detail.width,150);XCTAssertGreaterThan(a.bag.width,150);XCTAssertGreaterThan(a.detail.height,100)
            XCTAssertLessThan(a.detail.y+a.detail.height,a.footer.y)
        }
    }
}
