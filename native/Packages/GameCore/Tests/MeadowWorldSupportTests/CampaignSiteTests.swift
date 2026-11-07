import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class CampaignSiteTests:XCTestCase {
    private func session(persist:((Data)throws->Void)?=nil)throws->MeadowCampaignSession {
        var c=MeadowMapConfiguration.suggested(total:10,seed:31827)
        c.combat=0;c.boss=0;c.reward=0;c.empty=9;c.extraRoads=0
        var save=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c)).snapshot
        for id in ["p1","p2"]{save.archive.state.units[id]!.coins=1000}
        return try MeadowCampaignSession(save:save,persist:persist)
    }
    private func move(_ s:MeadowCampaignSession,to kind:CampaignSiteKind)throws {
        let target=try XCTUnwrap(s.engine.state.map.nodes.first{$0.kind == .empty && s.siteKind(node:$0.id)==kind})
        try s.beginTravel(to:target.id)
        while s.travel != nil {
            if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)}
            try s.advanceTravel(distance:100000)
        }
    }
    func testAllCatalogPurchasableItemsChargeOnlyBuyerAndNeverEquip()throws {
        let s=try session(),beforeOther=s.engine.state.units["p2"]!,ap=s.engine.state.units["p1"]!.ap,movement=s.snapshot.movement
        for item in s.engine.catalog.items where item.purchasePrice != nil && item.setID==nil {
            let old=s.engine.state.units["p1"]!
            try s.tradeAtSite(actor:"p1",item:item.id,buy:true)
            let new=s.engine.state.units["p1"]!
            XCTAssertEqual(new.coins,old.coins-item.purchasePrice!)
            XCTAssertEqual(new.inventory[item.id],(old.inventory[item.id] ?? 0)+1)
            XCTAssertEqual(new.equipment,old.equipment)
        }
        XCTAssertEqual(s.engine.state.units["p2"],beforeOther);XCTAssertEqual(s.engine.state.units["p1"]!.ap,ap)
        XCTAssertEqual(s.snapshot.movement,movement)
        let p1=s.engine.state.units["p1"]!,p2=s.engine.state.units["p2"]!
        try s.tradeAtSite(actor:"p2",item:"actionRing",buy:true)
        try s.equipInventory(actor:"p2",slot:.accessory,item:"actionRing")
        XCTAssertEqual(s.engine.state.units["p1"],p1)
        XCTAssertEqual(s.engine.state.units["p2"]!.coins,p2.coins-(try s.engine.catalog.item("actionRing").purchasePrice!))
        XCTAssertEqual(s.engine.state.units["p2"]!.ap,p2.ap)
        XCTAssertEqual(try GameRules.attributes(s.engine.state.units["p2"]!,catalog:s.engine.catalog).baseAP,4)
        XCTAssertEqual(s.snapshot.movement,movement)
    }
    func testSaleOnlyConsumesInventoryAndTransactionIDIsIdempotent()throws {
        let s=try session(),old=s.engine.state.units["p1"]!
        try s.tradeAtSite(actor:"p1",item:"smallPotion",buy:false,id:"sale")
        let saved=s.snapshot
        try s.tradeAtSite(actor:"p1",item:"smallPotion",buy:false,id:"sale")
        XCTAssertEqual(s.snapshot,saved)
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,old.coins+(try s.engine.catalog.item("smallPotion").sellPrice))
        XCTAssertThrowsError(try s.tradeAtSite(actor:"p1",item:"trainingSword",buy:false))
        XCTAssertThrowsError(try s.tradeAtSite(actor:"p1",item:"smallPotion",buy:true,id:"sale"))
        XCTAssertEqual(s.snapshot,saved)
    }
    func testTradeSaveFailureRollsBackAndRetryWritesOnce()throws {
        var fail=false,bytes=Data()
        let s=try session(persist:{if fail{throw GameError("disk")};bytes=$0});try s.checkpoint()
        let before=s.snapshot,old=bytes;fail=true
        XCTAssertThrowsError(try s.tradeAtSite(actor:"p1",item:"smallPotion",buy:true,id:"buy"))
        XCTAssertEqual(s.snapshot,before);XCTAssertEqual(bytes,old)
        fail=false;try s.tradeAtSite(actor:"p1",item:"smallPotion",buy:true,id:"buy")
        let saved=bytes;try s.tradeAtSite(actor:"p1",item:"smallPotion",buy:true,id:"buy")
        XCTAssertEqual(bytes,saved);XCTAssertEqual(try MeadowCampaignSession(save:.decoded(bytes)).snapshot,s.snapshot)
    }
    func testNoMoneyRareSetAndTravelAreRejectedWithoutChanges()throws {
        let s=try session();var save=s.snapshot;save.archive.state.units["p1"]!.coins=0
        let poor=try MeadowCampaignSession(save:save),before=poor.snapshot
        XCTAssertThrowsError(try poor.tradeAtSite(actor:"p1",item:"smallPotion",buy:true))
        XCTAssertThrowsError(try poor.tradeAtSite(actor:"p1",item:"starlightBlade",buy:true))
        XCTAssertEqual(poor.snapshot,before)
        let start=s.engine.state.units["p1"]!.nodeID
        try s.beginTravel(to:s.engine.state.map.neighbors(start)[0]);try s.setPaused(true)
        let paused=s.snapshot
        XCTAssertThrowsError(try s.tradeAtSite(actor:"p1",item:"smallPotion",buy:true));XCTAssertEqual(s.snapshot,paused)
    }
    func testSeededSitesDoNotAdvanceRNGAndOldOmittedFlagLoads()throws {
        let s=try session(),before=s.snapshot
        for _ in 0..<20 {for node in s.engine.state.map.nodes {
            XCTAssertEqual(s.siteKind(node:node.id),CampaignSiteRules.kind(node:node,seed:s.engine.state.map.seed))
        }}
        XCTAssertEqual(s.snapshot,before)
        XCTAssertEqual(CampaignSiteRules.kind(node:MapNode(id:3,name:"empty",kind:.empty),seed:31827),.spring)
        let expected=s.engine.state.map.nodes.map{s.siteKind(node:$0.id)}
        var shifted=before;_ = try shifted.archive.state.random.next(upperBound:20)
        let resumed=try MeadowCampaignSession(save:shifted)
        XCTAssertEqual(resumed.engine.state.map.nodes.map{resumed.siteKind(node:$0.id)},expected)
        let bytes=try before.encoded();XCTAssertFalse(String(decoding:bytes,as:UTF8.self).contains("siteResolved"))
        XCTAssertEqual(try MeadowCampaignSession(save:.decoded(bytes)).snapshot,before)
    }
    func testSatchelIsOncePerSiteAcrossPlayersAndResume()throws {
        let s=try session();try move(s,to:.satchel)
        let old=s.engine.state.units["p1"]!,rng=s.engine.state.random
        try s.resolveSite(actor:"p1",accept:true,id:"event")
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,old.coins+5);XCTAssertEqual(s.engine.state.units["p1"]!.ap,old.ap)
        let resumed=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded())),before=resumed.snapshot
        XCTAssertThrowsError(try resumed.resolveSite(actor:"p2",accept:true));XCTAssertEqual(resumed.snapshot,before)
        try resumed.resolveSite(actor:"p1",accept:true,id:"event");XCTAssertEqual(resumed.snapshot,before)
        XCTAssertEqual(resumed.engine.state.random,rng)
    }
    func testSpringFullHealthDoesNotConsumeAndHealingClampsToActualMaximum()throws {
        let s=try session();try move(s,to:.spring);let before=s.snapshot
        XCTAssertThrowsError(try s.resolveSite(actor:"p1",accept:true));XCTAssertEqual(s.snapshot,before)
        let max=try GameRules.attributes(s.engine.state.units["p1"]!,catalog:s.engine.catalog).maximumHealth
        try s.engine.apply(.setHealth(unit:"p1",value:max-2,killer:nil))
        try s.resolveSite(actor:"p1",accept:true)
        XCTAssertEqual(s.engine.state.units["p1"]!.health,max)
        XCTAssertFalse(s.siteAvailable(actor:"p2"))
    }
    func testEventFailureRetriesAndExplicitLeaveIsPermanentWithoutReward()throws {
        var fail=false,bytes=Data()
        let s=try session(persist:{if fail{throw GameError("disk")};bytes=$0});try move(s,to:.satchel)
        let before=s.snapshot,old=bytes;fail=true
        XCTAssertThrowsError(try s.resolveSite(actor:"p1",accept:true))
        XCTAssertEqual(s.snapshot,before);XCTAssertEqual(bytes,old)
        fail=false;try s.resolveSite(actor:"p2",accept:false)
        XCTAssertEqual(s.engine.state.players,before.archive.state.players)
        let restored=try MeadowCampaignSession(save:.decoded(bytes)),saved=restored.snapshot
        XCTAssertThrowsError(try restored.resolveSite(actor:"p1",accept:true));XCTAssertEqual(restored.snapshot,saved)
    }
    func testServicesSurviveFullExplorationAndFrozenCompletion()throws {
        let s=try session(),start=s.engine.state.units["p1"]!.nodeID
        try s.tradeAtSite(actor:"p1",item:"smallPotion",buy:true)
        try move(s,to:.satchel);try s.resolveSite(actor:"p1",accept:true)
        for target in s.engine.state.map.nodes.map(\.id)+[start] {
            if s.engine.state.units["p1"]!.nodeID==target{continue}
            try s.beginTravel(to:target)
            while s.travel != nil {
                if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)}
                try s.advanceTravel(distance:100000)
            }
        }
        XCTAssertTrue(s.canComplete)
        let expected=s.engine.state.players,result=try s.completeCampaign(),before=s.snapshot
        XCTAssertEqual(result.players,expected);XCTAssertEqual(result.players.first{$0.id=="p1"}!.coins,995)
        XCTAssertEqual(result.collectedRewards,0)
        let resumed=try MeadowCampaignSession(save:.decoded(before.encoded()))
        XCTAssertEqual(try resumed.completeCampaign(),result)
        XCTAssertThrowsError(try resumed.tradeAtSite(actor:"p1",item:"smallPotion",buy:true))
        XCTAssertThrowsError(try resumed.resolveSite(actor:"p1",accept:false))
        XCTAssertEqual(resumed.snapshot,before)
    }
}
