import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class SiteConfigurationTests:XCTestCase {
    private func session(persist:((Data)throws->Void)?=nil)throws->MeadowCampaignSession {
        var c=MeadowMapConfiguration.suggested(total:4,seed:31827);c.combat=0;c.boss=0;c.reward=0;c.empty=3
        var save=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c)).snapshot
        save.archive.state.units["p1"]!.coins=1000
        return try MeadowCampaignSession(save:save,persist:persist)
    }
    private func travel(_ s:MeadowCampaignSession,_ node:Int)throws {
        try s.beginTravel(to:node)
        while s.travel != nil {if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)};try s.advanceTravel(distance:100000)}
    }
    func testShopEditAndReloadUseSameActualPricesWithoutResourceGrant()throws {
        let s=try session(),node=s.engine.state.units["p1"]!.nodeID,before=s.snapshot
        try s.configureSite(node:node,configuration:.init(kind:.shop,buyPercent:200,sellPercent:100))
        XCTAssertEqual(s.engine.state.players,before.archive.state.players);XCTAssertEqual(s.snapshot.movement,before.movement)
        XCTAssertEqual(s.engine.state.random,before.archive.state.random)
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        let n=restored.engine.state.map.nodes.first{$0.id==node}!,item=try s.engine.catalog.item("smallPotion")
        XCTAssertEqual(try CampaignSiteRules.price(item:item,buy:true,node:n,seed:31827),20)
        try restored.tradeAtSite(actor:"p1",item:item.id,buy:true)
        XCTAssertEqual(restored.engine.state.units["p1"]!.coins,980)
        try restored.tradeAtSite(actor:"p1",item:item.id,buy:false)
        XCTAssertEqual(restored.engine.state.units["p1"]!.coins,980+item.sellPrice)
    }
    func testEditingTypeAndEventGoldIsPersistentAndDoesNotReopenAfterResolution()throws {
        let s=try session(),node=s.engine.state.map.nodes.first{$0.kind == .empty}!.id
        try s.configureSite(node:node,configuration:.init(kind:.satchel,gold:42))
        XCTAssertEqual(s.siteKind(node:node),.satchel)
        try travel(s,node);let old=s.engine.state.units["p1"]!.coins
        try s.resolveSite(actor:"p1",accept:true)
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,old+42)
        let resumed=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded())),before=resumed.snapshot
        XCTAssertThrowsError(try resumed.configureSite(node:node,configuration:.init(kind:.shop)))
        XCTAssertThrowsError(try resumed.configureSite(node:node,configuration:.init(kind:.satchel,gold:999)))
        XCTAssertEqual(resumed.snapshot,before)
    }
    func testEditedSpringUsesConfiguredAmountAndStillClamps()throws {
        let s=try session(),node=s.engine.state.map.nodes.first{$0.kind == .empty}!.id
        try s.configureSite(node:node,configuration:.init(kind:.spring,healing:9));try travel(s,node)
        let max=try GameRules.attributes(s.engine.state.units["p1"]!,catalog:s.engine.catalog).maximumHealth
        try s.engine.apply(.setHealth(unit:"p1",value:max-7,killer:nil))
        try s.resolveSite(actor:"p1",accept:true);XCTAssertEqual(s.engine.state.units["p1"]!.health,max)
    }
    func testMalformedArbitrageAndCampTypeAreRejectedIncludingImportedSave()throws {
        let s=try session(),node=s.engine.state.units["p1"]!.nodeID,before=s.snapshot
        for config in [CampaignSiteConfiguration(kind:.shop,buyPercent:0),.init(kind:.shop,sellPercent:501),.init(kind:.satchel,gold:0),.init(kind:.spring,healing:101),.init(kind:.shop,buyPercent:10,sellPercent:500),.init(kind:.spring)] {
            XCTAssertThrowsError(try s.configureSite(node:node,configuration:config));XCTAssertEqual(s.snapshot,before)
        }
        var forged=before;let index=forged.archive.state.map.nodes.firstIndex{$0.id==node}!
        forged.archive.state.map.nodes[index].siteConfiguration = .init(kind:.shop,buyPercent:10,sellPercent:500)
        XCTAssertThrowsError(try MeadowCampaignSession(save:forged))
    }
    func testFailureKeepsEntireSaveAndDraftCanRetry()throws {
        var fail=false,bytes=Data();let s=try session(persist:{if fail{throw GameError("disk")};bytes=$0})
        try s.checkpoint();let before=s.snapshot,old=bytes,node=s.engine.state.units["p1"]!.nodeID
        let draft=CampaignSiteConfiguration(kind:.shop,buyPercent:150,sellPercent:100)
        fail=true;XCTAssertThrowsError(try s.configureSite(node:node,configuration:draft));XCTAssertEqual(s.snapshot,before);XCTAssertEqual(bytes,old)
        fail=false;try s.configureSite(node:node,configuration:draft)
        XCTAssertEqual(try MeadowCampaignSession(save:.decoded(bytes)).snapshot,s.snapshot)
    }
    func testOldDefaultOmittedConfigurationAndTravelEditGuard()throws {
        let s=try session(),before=s.snapshot
        let bytes=try before.encoded();XCTAssertFalse(String(decoding:bytes,as:UTF8.self).contains("siteConfiguration"))
        XCTAssertEqual(try MeadowCampaignSession(save:.decoded(bytes)).snapshot,before)
        let start=s.engine.state.units["p1"]!.nodeID,target=s.engine.state.map.neighbors(start)[0]
        try s.beginTravel(to:target);try s.setPaused(true);let paused=s.snapshot
        XCTAssertThrowsError(try s.configureSite(node:start,configuration:.init(kind:.shop)));XCTAssertEqual(s.snapshot,paused)
    }
}
