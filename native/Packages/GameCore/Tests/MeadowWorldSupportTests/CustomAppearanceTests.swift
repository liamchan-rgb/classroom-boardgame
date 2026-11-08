import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class CustomAppearanceTests:XCTestCase {
    private var look:PlayerAppearance { .init(body:"wayfarer",outfit:"dragonArmor",hair:PlayerAppearance.hairOptions[3],face:PlayerAppearance.faceOptions[2]) }
    func testLegacyAppearanceWithoutHeadFieldsDecodes()throws {
        let a=try JSONDecoder().decode(PlayerAppearance.self,from:Data(#"{"body":"wayfarer","outfit":"runeArmor"}"#.utf8))
        XCTAssertEqual(a,.init(body:"wayfarer",outfit:"runeArmor"));XCTAssertNil(a.hair);XCTAssertNil(a.face)
    }
    func testCompleteChoiceRoundTripsWithStableIDs()throws {
        let a=try JSONDecoder().decode(PlayerAppearance.self,from:JSONEncoder().encode(look));XCTAssertEqual(a,look);try a.validate()
    }
    func testHairAndFaceAreIndependentAndGenderDoesNotRestrictChoice()throws {
        for hair in PlayerAppearance.hairOptions { for face in PlayerAppearance.faceOptions {
            XCTAssertNoThrow(try PlayerAppearance(outfit:"starlightArmor",hair:hair,face:face).validate())
        }}
    }
    func testUnknownHeadIDsRejected()throws {
        XCTAssertThrowsError(try PlayerAppearance(hair:"missing").validate());XCTAssertThrowsError(try PlayerAppearance(face:"missing").validate())
        XCTAssertNoThrow(try PlayerAppearance(hair:PlayerAppearance.hairOptions[0]).validate());XCTAssertNoThrow(try PlayerAppearance(face:PlayerAppearance.faceOptions[0]).validate())
    }
    func testChangingOneOfSevenPlayersKeepsOtherPlayersAndRules()throws {
        let layout=try MeadowMapGenerator.generate(.suggested(total:4,seed:731))
        let s=try MeadowCampaignSession.new(layout:layout,studentClasses:Array(repeating:"ranger",count:6))
        var expected=s.engine.state.units["p4"]!;let before=s.engine.state
        _ = try s.engine.apply(.applyPlayerProfile(unit:"p4",name:"新人物",appearance:look))
        expected.name="新人物";expected.appearance=look;XCTAssertEqual(s.engine.state.units["p4"],expected)
        for id in before.units.keys where id != "p4" {XCTAssertEqual(s.engine.state.units[id],before.units[id])}
        XCTAssertEqual(s.engine.state.map,before.map)
    }
    func testInvalidHeadDoesNotPartiallyApplyProfile()throws {
        let layout=try MeadowMapGenerator.generate(.suggested(total:4,seed:731))
        let s=try MeadowCampaignSession.new(layout:layout),before=s.engine.archive
        XCTAssertThrowsError(try s.engine.apply(.applyPlayerProfile(unit:"p1",name:"坏",appearance:.init(outfit:"dragonArmor",hair:"bad"))))
        XCTAssertEqual(s.engine.archive,before)
    }
    func testNewJourneyAndWholeCampaignKeepHeadAndOutfit()throws {
        let layout=try MeadowMapGenerator.generate(.suggested(total:4,seed:731))
        let s=try MeadowCampaignSession.new(layout:layout,playerAppearances:["p2":look])
        let loaded=try MeadowCampaignSession(save:MeadowCampaignSave.decoded(s.snapshot.encoded()))
        XCTAssertEqual(loaded.engine.state.units["p2"]?.appearance,look)
        XCTAssertNil(loaded.engine.state.units["p1"]?.appearance)
    }
    func testProfileSlotsPersistHeadWithoutEquipmentStats()throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let p=MeadowPlayerProfile(name:"紫发",appearance:look),store=MeadowSlotStore(directory:folder)
        try store.saveProfile(p,slot:12,title:"紫发")
        XCTAssertEqual(try store.profile(12)?.value,p)
    }
    func testNewOutfitsAreCosmeticAndDoNotBecomeWornItems()throws {
        XCTAssertEqual(look.armor(worn:"runeArmor"),"dragonArmor")
        XCTAssertEqual(PlayerAppearance(outfit:"starlightArmor").armor(worn:nil),"starlightArmor")
        XCTAssertEqual(PlayerAppearance(hair:look.hair).armor(worn:"leatherArmor"),"leatherArmor")
    }
    func testCacheIdentityIncludesIndependentHeadSelections()throws {
        let a=look,b=PlayerAppearance(body:a.body,outfit:a.outfit,hair:PlayerAppearance.hairOptions[0],face:a.face)
        let c=PlayerAppearance(body:a.body,outfit:a.outfit,hair:a.hair,face:PlayerAppearance.faceOptions[0])
        XCTAssertNotEqual(a.visualKey,b.visualKey);XCTAssertNotEqual(a.visualKey,c.visualKey)
    }
}
