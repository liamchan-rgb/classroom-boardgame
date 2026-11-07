import XCTest
import ClassroomGameCore
import MeadowCampaignAuditSupport
@testable import MeadowWorldSupport

final class JourneyAuditTests:XCTestCase {
    func testThreeClassesFinishDefaultJourneyWithRealDiceAndPaidMovement()throws {
        var victories=0
        for role in ["adventurer","spellblade","dragonKnight"] {
            let r=try MeadowJourneyAudit.run(size:10,seed:31827,role:role)
            XCTAssertTrue(["victory","defeat"].contains(r.outcome))
            if r.outcome=="victory"{victories+=1;XCTAssertEqual(r.cleared,5)}
            XCTAssertGreaterThan(r.resumes,0);XCTAssertGreaterThan(r.stagedRestarts,0)
            XCTAssertGreaterThan(r.monsterActions,0)
            XCTAssertEqual(r.startingCoins+r.nodeCoins+r.dropCoins-r.movementSpent,r.finalCoins)
        }
        XCTAssertGreaterThan(victories,0)
    }
    func testWholeJourneyReplayIsDeterministicIncludingLootAndResumes()throws {
        let a=try MeadowJourneyAudit.run(size:4,seed:0,role:"dragonKnight")
        let b=try MeadowJourneyAudit.run(size:4,seed:0,role:"dragonKnight")
        XCTAssertEqual(a,b)
    }
    private func depletedSave()throws->MeadowCampaignSave {
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4)))
        var save=s.snapshot
        save.archive.state.units["p1"]!.equipment.accessory="actionRing"
        save.archive.state.units["p1"]!.ap=0;save.archive.state.units["p2"]!.ap=0
        save.archive.state.units["p2"]!.health=0
        save.movement?.remaining=123.5
        return save
    }
    func testManualRestUsesEachBaseAPAndEnablesRealRescueWithoutFreeVitalsOrMovement()throws {
        let s=try MeadowCampaignSession(save:depletedSave()),before=s.snapshot
        let command=try s.inventoryItemCommand(actor:"p1",item:"revivalStone",target:"p2")
        XCTAssertFalse(s.engine.preview(command).allowed)
        XCTAssertTrue(s.inventoryActionRefillNeeded)
        let receipt=try XCTUnwrap(s.refillInventoryActions());XCTAssertEqual(receipt.command,.refillExploration)
        for u in s.engine.state.players {
            XCTAssertEqual(u.ap,try GameRules.attributes(u,catalog:s.engine.catalog).baseAP)
            let old=before.archive.state.units[u.id]!
            XCTAssertEqual(u.health,old.health);XCTAssertEqual(u.shield,old.shield);XCTAssertEqual(u.inventory,old.inventory)
            XCTAssertEqual(u.coins,old.coins);XCTAssertEqual(u.skillUses,old.skillUses)
        }
        XCTAssertEqual(s.engine.state.units["p1"]!.ap,4);XCTAssertEqual(s.engine.state.units["p2"]!.ap,3)
        XCTAssertEqual(s.snapshot.movement,before.movement);XCTAssertEqual(s.engine.state.random,before.archive.state.random)
        XCTAssertFalse(s.inventoryActionRefillNeeded);let count=s.engine.history.count
        XCTAssertNil(try s.refillInventoryActions());XCTAssertEqual(s.engine.history.count,count)
        try s.useInventory(actor:"p1",item:"revivalStone",target:"p2")
        XCTAssertEqual(s.engine.state.units["p2"]!.health,9)
        XCTAssertEqual(s.engine.state.units["p1"]!.ap,2);XCTAssertNil(s.engine.state.units["p1"]!.inventory["revivalStone"])
        try s.useInventory(actor:"p1",item:"smallPotion",target:"p2")
        XCTAssertEqual(s.engine.state.units["p2"]!.health,15);XCTAssertEqual(s.engine.state.units["p1"]!.ap,1)
        XCTAssertEqual(s.snapshot.movement,before.movement)
    }
    func testManualRestKeepsSurplusAPAndSaveFailureRollsBack()throws {
        var save=try depletedSave();save.archive.state.units["p2"]!.ap=5
        var fail=false,bytes=Data()
        let s=try MeadowCampaignSession(save:save,persist:{if fail{throw GameError("disk full")};bytes=$0})
        try s.checkpoint();let before=s.snapshot,oldBytes=bytes
        fail=true;XCTAssertThrowsError(try s.refillInventoryActions());XCTAssertEqual(s.snapshot,before);XCTAssertEqual(bytes,oldBytes)
        fail=false;try s.refillInventoryActions()
        XCTAssertEqual(s.engine.state.units["p1"]!.ap,4);XCTAssertEqual(s.engine.state.units["p2"]!.ap,5)
        let restored=try MeadowCampaignSession(save:.decoded(bytes));XCTAssertEqual(restored.snapshot,s.snapshot)
    }
    func testManualRestIsBlockedOnRoadInBattleAndAfterCompletion()throws {
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4)))
        let target=s.engine.state.map.nodes.first{$0.kind == .combat}!.id
        try s.beginTravel(to:target)
        XCTAssertFalse(s.inventoryActionRefillNeeded);XCTAssertThrowsError(try s.refillInventoryActions())
        while s.travel != nil {
            if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)}
            try s.advanceTravel(distance:100000)
        }
        try s.interactCurrentNode();let before=s.engine.archive
        XCTAssertThrowsError(try s.refillInventoryActions());XCTAssertEqual(s.engine.archive,before)
        for id in s.playerIDs{try s.engine.apply(.setHealth(unit:id,value:0,killer:nil))}
        try s.completeCampaign();let completed=s.snapshot
        XCTAssertThrowsError(try s.refillInventoryActions());XCTAssertEqual(s.snapshot,completed)
    }
    func testPartialMovementPurchaseUsesAffordableCoinsWithoutTouchingAP()throws {
        let initial=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4)))
        var save=initial.snapshot;save.movement?.remaining=0
        save.archive.state.units["p1"]!.coins=2;save.archive.state.units["p2"]!.coins=3
        save.archive.state.units["p1"]!.ap=0;save.archive.state.units["p2"]!.ap=1
        let s=try MeadowCampaignSession(save:save),ap=s.engine.state.players.map(\.ap),hp=s.engine.state.players.map(\.health)
        XCTAssertEqual(s.movementRefillCost,8);XCTAssertEqual(s.movementPurchaseCoins,5);XCTAssertEqual(s.movementPurchaseDistance,250)
        try s.refillMovement(usingCoins:true)
        XCTAssertEqual(s.movementRemaining,250);XCTAssertEqual(s.partyCoins,0)
        XCTAssertEqual(s.engine.state.players.map(\.ap),ap);XCTAssertEqual(s.engine.state.players.map(\.health),hp)
        XCTAssertEqual(s.engine.state.random,save.archive.state.random)
        let before=s.snapshot;XCTAssertThrowsError(try s.refillMovement(usingCoins:true));XCTAssertEqual(s.snapshot,before)
        XCTAssertEqual(s.snapshot.movement?.purchasedRefills,1);XCTAssertEqual(s.snapshot.movement?.manualRefills,0)
    }
    func testPartialPurchaseRollsBackAndFinalFractionNeverOverfills()throws {
        let initial=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4)))
        var save=initial.snapshot;save.movement?.remaining=100
        save.archive.state.units["p1"]!.coins=1;save.archive.state.units["p2"]!.coins=1
        var fail=false,data=Data()
        let s=try MeadowCampaignSession(save:save,persist:{if fail{throw GameError("disk")};data=$0})
        try s.checkpoint();let before=s.snapshot,old=data
        fail=true;XCTAssertThrowsError(try s.refillMovement(usingCoins:true));XCTAssertEqual(s.snapshot,before);XCTAssertEqual(data,old)
        fail=false;try s.refillMovement(usingCoins:true);XCTAssertEqual(s.movementRemaining,200)
        XCTAssertEqual(try MeadowCampaignSession(save:.decoded(data)).snapshot,s.snapshot)
        save.movement?.remaining=399.75
        let fraction=try MeadowCampaignSession(save:save)
        XCTAssertEqual(fraction.movementPurchaseCoins,1);XCTAssertEqual(fraction.movementPurchaseDistance,0.25)
        try fraction.refillMovement(usingCoins:true)
        XCTAssertEqual(fraction.movementRemaining,400);XCTAssertEqual(fraction.partyCoins,1)
        XCTAssertNil(try fraction.refillMovement(usingCoins:true))
    }
}
