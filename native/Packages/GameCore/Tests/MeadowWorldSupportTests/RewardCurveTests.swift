import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class RewardCurveTests:XCTestCase {
    func testJourneyDropsAreRicherButStatsUnchanged()throws {
        let journey=try MeadowCampaignSession.catalog(),table=try GameCatalog.initial()
        for monster in table.monsters {
            let rich=try journey.monster(monster.id)
            XCTAssertEqual(rich.attributes,monster.attributes);XCTAssertEqual(rich.attack,monster.attack)
            let coins=try XCTUnwrap(rich.drops.first{$0.itemID==nil})
            XCTAssertEqual(coins.percent,100);XCTAssertGreaterThanOrEqual(coins.coins,monster.attributes.maximumHealth)
            for (a,b) in zip(monster.drops,rich.drops) where a.itemID != nil {XCTAssertGreaterThanOrEqual(b.percent,a.percent)}
        }
    }
    func testSavesFromTheOldCatalogStillLoad()throws {
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:10,seed:31827)))
        var save=s.snapshot;save.archive.catalog=try MeadowCampaignSession.legacyCatalog()
        XCTAssertNoThrow(try MeadowCampaignSave.decoded(save.encoded()))
        var other=save;other.archive.catalog=try GameCatalog.initial()
        XCTAssertThrowsError(try other.validate())
    }
    func testTreasureGrowsWithDistanceFromCamp()throws {
        let layout=try MeadowMapGenerator.generate(.suggested(total:30,seed:7))
        let s=try MeadowCampaignSession.new(layout:layout)
        let plan=try MeadowProvisioning.plan(layout:layout,players:s.engine.state.players,catalog:s.engine.catalog)
        let values=plan.treasure.values.sorted()
        XCTAssertFalse(values.isEmpty);XCTAssertEqual(values.first,25)
        for (a,b) in zip(values,values.dropFirst()){XCTAssertEqual(b-a,20)}
        for (id,bonus) in plan.treasure {XCTAssertGreaterThanOrEqual(plan.rewards[id]!.coins,bonus)}
    }
    func testSpringRestoresEveryTeammateHereToFull()throws {
        var c=MeadowMapConfiguration.suggested(total:10,seed:31827)
        c.combat=0;c.boss=0;c.reward=0;c.empty=9;c.extraRoads=0
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c))
        let target=try XCTUnwrap(s.engine.state.map.nodes.first{$0.kind == .empty && s.siteKind(node:$0.id) == .spring})
        try s.beginTravel(to:target.id)
        while s.travel != nil {if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)};try s.advanceTravel(distance:100000)}
        for id in ["p1","p2"] {try s.engine.apply(.setHealth(unit:id,value:1,killer:nil))}
        try s.resolveSite(actor:"p1",accept:true)
        for id in ["p1","p2"] {
            let u=s.engine.state.units[id]!
            XCTAssertEqual(u.health,try GameRules.attributes(u,catalog:s.engine.catalog).maximumHealth)
        }
    }
}
