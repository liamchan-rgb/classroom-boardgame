import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class PlayerSlotTests:XCTestCase {
    func session(count:Int=2,persist:((Data)throws->Void)?=nil)throws->MeadowCampaignSession {
        let layout=try MeadowMapGenerator.generate(.suggested(total:4,seed:731))
        return try .new(layout:layout,studentClasses:Array(repeating:"ranger",count:count),persist:persist)
    }
    func temporary()throws->MeadowSlotStore {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock{try? FileManager.default.removeItem(at:folder)};return .init(directory:folder)
    }
    func testProfileRoundTripWithoutGameResources()throws {
        let store=try temporary(),p=MeadowPlayerProfile(name:" 林 ",appearance:.init(body:"wayfarer",outfit:"runeArmor"))
        try store.saveProfile(p,slot:12,title:"学生林")
        XCTAssertEqual(try store.profile(12)?.value,p)
        let data=try Data(contentsOf:store.directory.appendingPathComponent("profile-12.json")),object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        XCTAssertEqual(Set((object["value"] as! [String:Any]).keys),["formatVersion","name","appearance"])
    }
    func testInvalidProfileDoesNotReplaceExisting()throws {
        let store=try temporary(),old=MeadowPlayerProfile(name:"甲",appearance:.init())
        try store.saveProfile(old,slot:1,title:"甲")
        XCTAssertThrowsError(try store.saveProfile(.init(name:"",appearance:.init()),slot:1,title:"坏"))
        XCTAssertEqual(try store.profile(1)?.value,old)
    }
    func testInvalidAppearanceRejected()throws {
        XCTAssertThrowsError(try PlayerAppearance(body:"missing").validate())
        XCTAssertThrowsError(try PlayerAppearance(outfit:"missing").validate())
        XCTAssertNoThrow(try PlayerAppearance(outfit:"runeArmor").validate())
    }
    func testSlotBoundsAndNamespaces()throws {
        let store=try temporary();XCTAssertThrowsError(try store.profile(0));XCTAssertThrowsError(try store.profile(51));XCTAssertThrowsError(try store.campaign(51));XCTAssertEqual(MeadowSlotStore.profileCount,50);XCTAssertEqual(MeadowSlotStore.campaignCount,50)
        try store.saveProfile(.init(name:"甲",appearance:.init()),slot:1,title:"人物")
        XCTAssertNil(try store.campaign(1));XCTAssertNil(try store.profile(2))
    }
    func testDamagedSlotDoesNotHideHealthySlot()throws {
        let store=try temporary();try store.saveProfile(.init(name:"甲",appearance:.init()),slot:2,title:"甲")
        let path=store.directory.appendingPathComponent("profile-1.json");try Data("broken".utf8).write(to:path)
        XCTAssertThrowsError(try store.profile(1));XCTAssertEqual(try store.profile(2)?.value.name,"甲");XCTAssertEqual(try Data(contentsOf:path),Data("broken".utf8))
    }
    func testCampaignSlotPreservesWholeSave()throws {
        let store=try temporary(),s=try session();_ = try s.engine.apply(.grantPlayerResources(actors:["p1"],ap:0,coins:13))
        try store.saveCampaign(s.snapshot,slot:8,title:"第1课")
        XCTAssertEqual(try store.campaign(8)?.value,s.snapshot)
    }
    func testBackupHasUniqueRecoverableFiles()throws {
        let store=try temporary(),s=try session(),first=try store.backup(s.snapshot),second=try store.backup(s.snapshot)
        XCTAssertNotEqual(first,second);XCTAssertEqual(try store.recoveries().count,2)
        XCTAssertEqual(try MeadowCampaignSave.decoded(Data(contentsOf:first)),s.snapshot)
    }
    func testApplyProfileKeepsResourcesAndEquipment()throws {
        let s=try session();var expected=s.engine.state.units["p1"]!
        let a=PlayerAppearance(body:"wayfarer",outfit:"leatherArmor")
        _ = try s.engine.apply(.applyPlayerProfile(unit:"p1",name:" 新名字 ",appearance:a))
        expected.name="新名字";expected.appearance=a;XCTAssertEqual(s.engine.state.units["p1"],expected)
    }
    func testBadProfileTransactionIsAtomic()throws {
        let s=try session(),before=s.engine.archive
        XCTAssertThrowsError(try s.engine.apply(.applyPlayerProfile(unit:"p1",name:"",appearance:.init())))
        XCTAssertEqual(s.engine.archive,before)
    }
    func testNewJourneyUsesProfileOnly()throws {
        let s=try session(),a=PlayerAppearance(body:"wayfarer",outfit:"blue")
        let fresh=try MeadowCampaignSession.new(layout:s.snapshot.layout,studentNames:["甲","乙"],playerAppearances:["p2":a])
        XCTAssertEqual(fresh.engine.state.units["p2"]?.appearance,a);XCTAssertEqual(fresh.engine.state.units["p2"]?.name,"乙")
        XCTAssertNil(fresh.engine.state.units["p1"]?.appearance)
    }
    func testLegacySaveWithoutAppearanceAndCheckpointsLoads()throws {
        let s=try session();var object=try JSONSerialization.jsonObject(with:s.snapshot.encoded()) as! [String:Any]
        object.removeValue(forKey:"checkpoints")
        let loaded=try MeadowCampaignSave.decoded(JSONSerialization.data(withJSONObject:object));XCTAssertNil(loaded.checkpoints);XCTAssertNil(loaded.archive.state.units["p1"]?.appearance)
    }
    func testRollbackRestoresRulesRNGAndTruncatesHistory()throws {
        let s=try session();let first=try s.engine.apply(.grantPlayerResources(actors:["p1"],ap:0,coins:10))
        _ = try s.engine.apply(.grantPlayerResources(actors:["p2"],ap:0,coins:20))
        let saved=s.snapshot,result=try saved.rollingBack(after:first.id)
        var expected=first.after;expected.pauseReasons.insert(.manual)
        XCTAssertEqual(result.archive.state,expected);XCTAssertEqual(result.archive.history.map(\.id),[first.id]);XCTAssertEqual(s.snapshot,saved)
    }
    func testRollbackRestoresMovementCheckpoint()throws {
        let s=try session();_ = try s.refillMovement(usingCoins:false)
        let first=try s.engine.apply(.grantPlayerResources(actors:["p1"],ap:0,coins:1)),saved=s.snapshot
        let result=try saved.rollingBack(after:first.id)
        XCTAssertEqual(result.movement,saved.movement);XCTAssertEqual(result.movementBalances,saved.movementBalances)
    }
    func testUnknownHistoryIDCannotRollback()throws {XCTAssertThrowsError(try session().snapshot.rollingBack(after:"missing"))}
    func testLegacyRollbackStopsTravelWithoutRefill()throws {
        let s=try session();let first=try s.engine.apply(.grantPlayerResources(actors:["p1"],ap:0,coins:1));var save=s.snapshot;save.checkpoints=nil
        let result=try save.rollingBack(after:first.id);XCTAssertNil(result.travel);XCTAssertLessThanOrEqual(result.movement?.remaining ?? 0,save.movement?.remaining ?? 0)
    }
    func testRollbackKeepsBookPauseWhenRequested()throws {
        let s=try session(),first=try s.engine.apply(.grantPlayerResources(actors:["p1"],ap:0,coins:1))
        XCTAssertTrue(try s.snapshot.rollingBack(after:first.id,book:true).archive.state.pauseReasons.isSuperset(of:[.manual,.book]))
    }
    func testProfilePersistsAcrossCampaignLoad()throws {
        let s=try session();_ = try s.engine.apply(.applyPlayerProfile(unit:"p2",name:"乙",appearance:.init(outfit:"runeArmor")))
        let loaded=try MeadowCampaignSession(save:MeadowCampaignSave.decoded(s.snapshot.encoded()))
        XCTAssertEqual(loaded.engine.state.units["p2"]?.appearance?.outfit,"runeArmor")
    }
    func testExplicitBlueDoesNotShowActualArmor()throws {
        XCTAssertNil(PlayerAppearance(outfit:"blue").armor(worn:"runeArmor"))
        XCTAssertEqual(PlayerAppearance().armor(worn:"runeArmor"),"runeArmor")
    }
}
