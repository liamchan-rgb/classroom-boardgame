import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class SaveTransferTests:XCTestCase {
    func store()throws->MeadowSlotStore {let p=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);addTeardownBlock{try? FileManager.default.removeItem(at:p)};return .init(directory:p)}
    func profile(_ name:String="林")->MeadowPlayerProfile {.init(name:name,appearance:.init(body:"wayfarer",outfit:"runeArmor"))}
    func save()throws->MeadowCampaignSave {try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4,seed:913)),studentClasses:Array(repeating:"ranger",count:6)).snapshot}
    func transfer()throws->MeadowSaveTransfer {var t=MeadowSaveTransfer();t.profiles=[.init(slot:3,entry:.init(title:"第三位",value:profile()))];return t}
    func testProfileExportExcludesCampaignAndPersonalStats()throws {
        let s=try store();try s.saveProfile(profile(),slot:3,title:"人物");try s.saveCampaign(save(),slot:3,title:"行程")
        let t=try s.exportTransfer([.init(.profile,3)]);XCTAssertEqual(t.profiles.count,1);XCTAssertTrue(t.campaigns.isEmpty)
        let bytes=try t.encoded(),copy=try MeadowSaveTransfer.decoded(bytes);XCTAssertEqual(copy,t)
        let value=(try JSONSerialization.jsonObject(with:bytes) as! [String:Any])["profiles"] as! [[String:Any]]
        let entry=value[0]["entry"] as! [String:Any],p=entry["value"] as! [String:Any];XCTAssertEqual(Set(p.keys),["formatVersion","name","appearance"])
    }
    func testMixedBatchPreservesWholeCampaignAndMetadata()throws {
        let s=try store(),c=try save();try s.saveProfile(profile(),slot:12,title:"人物");try s.saveCampaign(c,slot:8,title:"最后一课")
        let t=try s.exportTransfer([.init(.profile,12),.init(.campaign,8)]),copy=try MeadowSaveTransfer.decoded(t.encoded())
        XCTAssertEqual(t,copy);XCTAssertEqual(copy.campaigns[0].entry.value,c)
    }
    func testImportRemapsBothKindsWithoutColliding()throws {
        let s=try store();var t=try transfer();t.campaigns=[.init(slot:1,entry:.init(title:"课",value:try save()))]
        _=try s.importTransfer(t,destinations:[.init(.profile,3):2,.init(.campaign,1):2])
        XCTAssertEqual(try s.profile(2)?.value,profile());XCTAssertEqual(try s.campaign(2)?.value,t.campaigns[0].entry.value)
        XCTAssertNil(try s.profile(3));XCTAssertNil(try s.campaign(1))
    }
    func testImportKeepsOriginalSavedAt()throws {
        let s=try store(),t=try transfer();_=try s.importTransfer(t,destinations:[.init(.profile,3):1]);XCTAssertEqual(try s.profile(1),t.profiles[0].entry)
    }
    func testMissingDestinationRejectedBeforeWriting()throws {let s=try store();XCTAssertThrowsError(try s.importTransfer(transfer(),destinations:[:]));XCTAssertNil(try s.profile(3))}
    func testOutOfRangeDestinationRejected()throws {let s=try store();XCTAssertThrowsError(try s.importTransfer(transfer(),destinations:[.init(.profile,3):51]));XCTAssertNil(try s.profile(3))}
    func testDuplicateTargetRejectedBeforeOverwriting()throws {
        let s=try store();try s.saveProfile(profile("原"),slot:1,title:"原");var t=try transfer();t.profiles.append(.init(slot:4,entry:.init(title:"另一个",value:profile("新"))))
        XCTAssertThrowsError(try s.importTransfer(t,destinations:[.init(.profile,3):1,.init(.profile,4):1]));XCTAssertEqual(try s.profile(1)?.value.name,"原")
    }
    func testDuplicateSourceAndUnknownVersionRejected()throws {
        var t=try transfer();t.profiles.append(t.profiles[0]);XCTAssertThrowsError(try t.encoded());t=try transfer();t.version=999
        XCTAssertThrowsError(try MeadowSaveTransfer.decoded(JSONEncoder().encode(t)))
    }
    func testWrongFileAndEmptyFileRejected()throws {XCTAssertThrowsError(try MeadowSaveTransfer.decoded(Data()));XCTAssertThrowsError(try MeadowSaveTransfer.decoded(Data("[]".utf8)));XCTAssertThrowsError(try MeadowSaveTransfer.decoded(Data("{\"name\":\"wrong\"}".utf8)))}
    func testInvalidAppearanceDoesNotChangeExistingSlots()throws {
        let s=try store();try s.saveProfile(profile("原"),slot:1,title:"原");var t=try transfer();t.profiles=[.init(slot:3,entry:.init(title:"坏",value:.init(name:"坏",appearance:.init(body:"missing"))))]
        XCTAssertThrowsError(try s.importTransfer(t,destinations:[.init(.profile,3):1]));XCTAssertEqual(try s.profile(1)?.value.name,"原")
    }
    func testOverwriteHasReadableBackupAndKeepsOtherSlot()throws {
        let s=try store();try s.saveProfile(profile("原"),slot:1,title:"原");try s.saveProfile(profile("不变"),slot:2,title:"不变")
        let id=try s.importTransfer(transfer(),destinations:[.init(.profile,3):1]);XCTAssertEqual(try s.profile(1)?.value.name,"林");XCTAssertEqual(try s.profile(2)?.value.name,"不变")
        XCTAssertEqual(try s.importBackups().first?.id,id);XCTAssertEqual(try s.transferBeforeImport(id).profiles[0].entry.value.name,"原")
    }
    func testCorruptOriginalBytesRetainedExactly()throws {
        let s=try store();try FileManager.default.createDirectory(at:s.directory,withIntermediateDirectories:true);let bad=Data("broken original".utf8)
        try bad.write(to:s.directory.appendingPathComponent("profile-1.json"))
        let id=try s.importTransfer(transfer(),destinations:[.init(.profile,3):1])
        let j=try JSONDecoder().decode(MeadowSlotImportJournal.self,from:Data(contentsOf:s.directory.appendingPathComponent("ImportBackups/"+id+".json")))
        XCTAssertEqual(j.rows[0].before,bad);XCTAssertEqual(try s.profile(1)?.value.name,"林")
    }
    func testInterruptedBatchRollsBackBeforeFirstRead()throws {
        let s=try store();try s.saveProfile(profile("原"),slot:1,title:"原")
        let original=try Data(contentsOf:s.directory.appendingPathComponent("profile-1.json")),new=try JSONEncoder().encode(MeadowSaveSlot(title:"新",value:profile("新"))),id=UUID().uuidString
        let j=MeadowSlotImportJournal(version:1,id:id,createdAt:Date(),rows:[.init(address:.init(.profile,1),before:original,after:new),.init(address:.init(.profile,2),before:nil,after:new)])
        let folder=s.directory.appendingPathComponent("ImportBackups");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try JSONEncoder().encode(j).write(to:folder.appendingPathComponent(id+".json"));try JSONEncoder().encode(id).write(to:s.directory.appendingPathComponent("pending-import.json"))
        try new.write(to:s.directory.appendingPathComponent("profile-1.json"));try new.write(to:s.directory.appendingPathComponent("profile-2.json"))
        XCTAssertEqual(try s.profile(1)?.value.name,"原");XCTAssertNil(try s.profile(2));XCTAssertFalse(FileManager.default.fileExists(atPath:s.directory.appendingPathComponent("pending-import.json").path))
    }
    func testBrokenPendingJournalBlocksReadAndPreservesSlot()throws {
        let s=try store();try s.saveProfile(profile("原"),slot:1,title:"原");let path=s.directory.appendingPathComponent("profile-1.json"),bytes=try Data(contentsOf:path)
        try Data("bad marker".utf8).write(to:s.directory.appendingPathComponent("pending-import.json"));XCTAssertThrowsError(try s.profile(1));XCTAssertEqual(try Data(contentsOf:path),bytes)
    }
    func testOldProfileSlotAndRawProfileAccepted()throws {
        let p=profile(),slot=MeadowSaveSlot(title:"旧档",value:p)
        XCTAssertEqual(try MeadowSaveTransfer.decoded(JSONEncoder().encode(slot)).profiles[0].entry,slot)
        XCTAssertEqual(try MeadowSaveTransfer.decoded(JSONEncoder().encode(p)).profiles[0].entry.value,p)
    }
    func testOldCampaignSlotAndWorkingSaveAccepted()throws {
        let c=try save(),slot=MeadowSaveSlot(title:"旧地图",value:c)
        XCTAssertEqual(try MeadowSaveTransfer.decoded(JSONEncoder().encode(slot)).campaigns[0].entry,slot)
        XCTAssertEqual(try MeadowSaveTransfer.decoded(c.encoded()).campaigns[0].entry.value,c)
    }
    func testSelectionRejectsForeignEntriesAndEmptySelection()throws {
        let t=try transfer();XCTAssertThrowsError(try t.selecting([]));XCTAssertThrowsError(try t.selecting([.init(.profile,4)]));XCTAssertEqual(try t.selecting([.init(.profile,3)]),t)
    }
    func testUnreadableOrEmptyExportCannotSilentlySkip()throws {
        let s=try store();XCTAssertThrowsError(try s.exportTransfer([]));XCTAssertThrowsError(try s.exportTransfer([.init(.profile,1)]))
        try s.saveProfile(profile(),slot:2,title:"人物");try Data("bad".utf8).write(to:s.directory.appendingPathComponent("profile-1.json"))
        XCTAssertThrowsError(try s.exportTransfer([.init(.profile,1),.init(.profile,2)]));XCTAssertEqual(try s.exportTransfer([.init(.profile,2)]).profiles.count,1)
    }
    func testBoundedReaderRejectsOversizedFileBeforeAllocation()throws {
        let s=try store();try FileManager.default.createDirectory(at:s.directory,withIntermediateDirectories:true);let path=s.directory.appendingPathComponent("large.json")
        FileManager.default.createFile(atPath:path.path,contents:Data());let file=try FileHandle(forWritingTo:path);try file.truncate(atOffset:UInt64(MeadowSaveTransfer.maximumBytes+1));try file.close()
        XCTAssertThrowsError(try MeadowSaveTransfer.read(from:path))
    }
    func testFileReaderAndMalformedBackupIsolation()throws {
        let s=try store(),t=try transfer();try FileManager.default.createDirectory(at:s.directory,withIntermediateDirectories:true)
        let file=s.directory.appendingPathComponent("import.json");try t.encoded().write(to:file);XCTAssertEqual(try MeadowSaveTransfer.read(from:file),t)
        let folder=s.directory.appendingPathComponent("ImportBackups");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try Data("bad".utf8).write(to:folder.appendingPathComponent("broken.json"))
        XCTAssertEqual(try s.importBackups().count,1);XCTAssertNotNil(try s.importBackups()[0].error)
        try s.saveProfile(profile(),slot:1,title:"可读");XCTAssertEqual(try s.profile(1)?.value,profile())
    }
    func testImportDoesNotTouchWorkingCampaignFile()throws {
        let s=try store(),working=s.directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString+"-campaign-v1.json"),bytes=try save().encoded()
        addTeardownBlock{try? FileManager.default.removeItem(at:working)};try bytes.write(to:working)
        _=try s.importTransfer(transfer(),destinations:[.init(.profile,3):1]);XCTAssertEqual(try Data(contentsOf:working),bytes)
    }

}
