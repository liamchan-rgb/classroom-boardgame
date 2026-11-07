import XCTest
import ClassroomGameCore
import MeadowBattleSupport
import MeadowCampaignAuditSupport
@testable import MeadowWorldSupport

final class EquipmentJourneyTests:XCTestCase {
    private func session(_ kit:String="trainingSword-plain",role:String="spellblade",persist:((Data)throws->Void)?=nil)throws->MeadowCampaignSession {
        let loadout=try XCTUnwrap(MeadowAuditLoadout.all.first{$0.id==kit})
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:10,seed:31827)),playerClassID:role,loadouts:loadout.units(role:role))
        var save=s.snapshot
        for id in ["trainingSword","huntingBow","greatSword","legendaryStaff","leatherArmor","runeArmor","powerBadge","actionRing","starlightBlade","starlightArmor","starlightCharm","dragonFangSword","dragonArmor","dragonCharm"] {save.archive.state.units["p1"]!.inventory[id]=1}
        return try MeadowCampaignSession(save:save,persist:persist)
    }
    func testAllSupportedWeaponPreviewsMatchActualEquipmentAndNeverRefillVitalsOrMovement()throws {
        for role in ["adventurer","spellblade","dragonKnight"] {for kit in MeadowAuditLoadout.supported {
            let s=try session(kit.id,role:role)
            for id in ["trainingSword","huntingBow","greatSword","legendaryStaff"] {
                let before=s.snapshot,preview=try s.equipmentComparison(actor:"p1",slot:.weapon,item:id)
                XCTAssertEqual(s.snapshot,before)
                try s.equipInventory(actor:"p1",slot:.weapon,item:id)
                XCTAssertEqual(s.engine.state.units["p1"],preview.after)
                XCTAssertEqual(s.movementRemaining,before.movement!.remaining,accuracy:1e-8)
                XCTAssertEqual(s.engine.state.units["p1"]!.ap,preview.before.ap)
                XCTAssertEqual(try MeadowCampaignSession(save:.decoded(s.snapshot.encoded())).engine.archive,s.engine.archive)
            }
        }}
    }
    func testActionRingChangesIndividualOpeningAPWithoutIncreasingMovementMaximum()throws {
        let s=try session(),before=s.movementRemaining
        let preview=try s.equipmentComparison(actor:"p1",slot:.accessory,item:"actionRing")
        XCTAssertEqual(preview.beforeStats.baseAP,3);XCTAssertEqual(preview.afterStats.baseAP,4)
        XCTAssertEqual(preview.beforeStats.maximumAP,8);XCTAssertEqual(preview.afterStats.maximumAP,8)
        XCTAssertEqual(preview.movementBefore,400);XCTAssertEqual(preview.movementAfter,400)
        try s.equipInventory(actor:"p1",slot:.accessory,item:"actionRing")
        XCTAssertEqual(s.engine.state.units["p1"]!.ap,3);XCTAssertEqual(s.movementRemaining,before)
        let target=s.engine.state.map.nodes.first{$0.kind == .combat}!.id
        try s.beginTravel(to:target)
        while s.travel != nil {
            if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)}
            try s.advanceTravel(distance:100000)
        }
        try s.interactCurrentNode()
        XCTAssertEqual(s.engine.state.units["p1"]!.ap,4);XCTAssertEqual(s.engine.state.units["p2"]!.ap,3)
        let resumed=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(resumed.engine.state.units["p1"]!.ap,4);XCTAssertEqual(resumed.engine.state.units["p2"]!.ap,3)
    }
    func testDroppingMaximumPermanentlyClipsStoredMovementAndReequippingNeverRefillsIt()throws {
        let s=try session("dragon-two")
        XCTAssertEqual(s.movementCapacity,450);XCTAssertEqual(s.movementRemaining,450)
        let preview=try s.equipmentComparison(actor:"p1",slot:.armor,item:"runeArmor")
        XCTAssertEqual(preview.movementAfter,400)
        var unnormalized=s.snapshot;unnormalized.archive.state.units["p1"]=preview.after
        XCTAssertThrowsError(try unnormalized.encoded())
        try s.equipInventory(actor:"p1",slot:.armor,item:"runeArmor")
        XCTAssertEqual(s.snapshot.movement?.remaining,400)
        try s.equipInventory(actor:"p1",slot:.armor,item:"dragonArmor")
        XCTAssertEqual(s.movementCapacity,450);XCTAssertEqual(s.movementRemaining,400)
        XCTAssertEqual(try MeadowCampaignSession(save:.decoded(s.snapshot.encoded())).movementRemaining,400)
    }
    func testInvalidOverCapacitySaveIsRejectedAndWriteFailureRollsBackEquipmentAndMeter()throws {
        let old=try session();var save=old.snapshot;save.movement?.remaining=450
        XCTAssertThrowsError(try MeadowCampaignSession(save:save))
        var fail=false
        let s=try session("dragon-two",persist:{_ in if fail{throw GameError("disk")}})
        let before=s.snapshot;fail=true
        XCTAssertThrowsError(try s.equipInventory(actor:"p1",slot:.armor,item:"runeArmor"))
        XCTAssertEqual(s.snapshot,before);XCTAssertEqual(s.movementRemaining,450)
    }
    func testSetThresholdsKeepOriginalRulesAndRemoveUnlockedSkillOnUnequip()throws {
        for (kit,skill) in [("starlight-three","starlightPulse"),("dragon-three","dragonSoulWard")] {
            let s=try session(kit),original=try GameCatalog.initial()
            XCTAssertEqual(Array(s.engine.catalog.items),original.items)
            XCTAssertTrue(try GameRules.skills(s.engine.state.units["p1"]!,catalog:s.engine.catalog).contains(skill))
            let preview=try s.equipmentComparison(actor:"p1",slot:.weapon,item:"trainingSword")
            XCTAssertTrue(preview.skillsBefore.contains(try s.engine.catalog.skill(skill).name))
            XCTAssertFalse(preview.skillsAfter.contains(try s.engine.catalog.skill(skill).name))
            try s.equipInventory(actor:"p1",slot:.weapon,item:"trainingSword")
            XCTAssertFalse(try GameRules.skills(s.engine.state.units["p1"]!,catalog:s.engine.catalog).contains(skill))
        }
    }
    func testFullJourneyUsesRealLoadoutAndDeterministicOriginalDice()throws {
        let kit=MeadowAuditLoadout.supported.first{$0.id=="huntingBow-rune-ring"}!
        let a=try MeadowJourneyAudit.run(size:4,seed:31827,role:"spellblade",loadout:kit)
        let b=try MeadowJourneyAudit.run(size:4,seed:31827,role:"spellblade",loadout:kit)
        XCTAssertEqual(a,b);XCTAssertTrue(["victory","defeat"].contains(a.outcome))
        XCTAssertGreaterThan(a.resumes,0);XCTAssertGreaterThan(a.stagedRestarts,0)
    }
}
