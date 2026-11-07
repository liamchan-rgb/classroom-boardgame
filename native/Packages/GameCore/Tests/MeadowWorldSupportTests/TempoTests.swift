import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class TempoTests:XCTestCase {
    func testSingleBossReadinessRequiresBothCombatAndSupplyRatherThanMapSize()throws {
        var dragonSeen=false
        for seed:UInt64 in 0..<16 {
            for mode in 0..<4 {
                var c=MeadowMapConfiguration.suggested(total:mode==0 ? 4:30,seed:seed)
                if mode==1{c.combat=1;c.boss=1;c.reward=27;c.empty=0}
                if mode==2{c.combat=20;c.boss=1;c.reward=1;c.empty=7}
                if mode==3{c.combat=4;c.boss=1;c.reward=2;c.empty=22}
                let boss=try XCTUnwrap(MeadowEncounterPlanner.plan(MeadowMapGenerator.generate(c)).first{$0.band=="boss"})
                if mode<3{XCTAssertEqual(boss.templates,["caveTroll"])}
                else{dragonSeen = dragonSeen || boss.templates==["ruinDragon"]}
            }
        }
        XCTAssertTrue(dragonSeen)
    }
    func testExplicitBossRushRetainsFinalDragonAndOriginalRules()throws {
        var c=MeadowMapConfiguration.suggested(total:4);c.combat=0;c.boss=3;c.reward=0;c.empty=0
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c))
        let templates=s.engine.state.units.values.filter{$0.kind == .monster}.map(\.templateID)
        XCTAssertEqual(templates.filter{$0=="ruinDragon"}.count,1);XCTAssertEqual(templates.filter{$0=="caveTroll"}.count,2)
        XCTAssertEqual(try GameCatalog.initial().monsters,Array(s.engine.catalog.monsters.prefix(6)))
        let plan=try MeadowProvisioning.plan(layout:s.snapshot.layout,players:s.engine.state.players,catalog:s.engine.catalog)
        XCTAssertTrue(plan.bossSupplyNodes.isEmpty);XCTAssertTrue(plan.rewards.isEmpty)
    }
    func testBossSupplyIsEarlierAndNearBossWhileShieldArrivesAtFirstCache()throws {
        var nonFarthestSeen=false
        for seed:UInt64 in 0..<16 {
            let layout=try MeadowMapGenerator.generate(.suggested(total:10,seed:seed)),s=try MeadowCampaignSession.new(layout:layout)
            let plan=try MeadowProvisioning.plan(layout:layout,players:s.engine.state.players,catalog:s.engine.catalog)
            let start=s.engine.state.players[0].nodeID,boss=layout.map.nodes.first{$0.kind == .boss}!.id
            func distance(_ a:Int,_ b:Int)->Double{s.routeDistance(layout.map.shortestPath(from:a,to:b)!)}
            let caches=layout.map.nodes.filter{$0.kind == .reward}.sorted{let a=distance(start,$0.id),b=distance(start,$1.id);return a==b ? $0.id<$1.id:a<b}
            let chosen=try XCTUnwrap(plan.bossSupplyNodes[boss])
            let earlier=caches.filter{distance(start,$0.id)<=distance(start,boss)+0.000001}
            if !earlier.isEmpty{XCTAssertTrue(earlier.contains{$0.id==chosen})}
            for candidate in earlier.isEmpty ? caches:earlier{XCTAssertLessThanOrEqual(distance(chosen,boss),distance(candidate.id,boss)+0.000001)}
            XCTAssertEqual(plan.rewards[caches.first!.id]?.items["shieldPotion"],1)
            XCTAssertEqual(plan.rewards[chosen]?.items["largePotion"],plan.healingPressure)
            XCTAssertEqual(plan.rewards[chosen]?.items["revivalStone"],1)
            XCTAssertEqual(plan.rewards.values.reduce(0){$0+($1.items["smallPotion"] ?? 0)+($1.items["largePotion"] ?? 0)},caches.count*plan.healingPressure)
            XCTAssertEqual(plan.rewards.values.reduce(0){$0+($1.items["shieldPotion"] ?? 0)},1)
            nonFarthestSeen = nonFarthestSeen || chosen != caches.last!.id
        }
        XCTAssertTrue(nonFarthestSeen)
    }
    func testSingleCacheIsUpgradedAndMultiBossRevivalStockMatchesBossCount()throws {
        let small=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4)))
        let one=try MeadowProvisioning.plan(layout:small.snapshot.layout,players:small.engine.state.players,catalog:small.engine.catalog)
        let reward=try XCTUnwrap(one.rewards.values.first)
        XCTAssertEqual(reward.items["largePotion"],1);XCTAssertNil(reward.items["smallPotion"])
        XCTAssertEqual(reward.items["shieldPotion"],1);XCTAssertEqual(reward.items["revivalStone"],1)
        var c=MeadowMapConfiguration.suggested(total:10);c.combat=3;c.boss=3;c.reward=2;c.empty=1
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c))
        let many=try MeadowProvisioning.plan(layout:s.snapshot.layout,players:s.engine.state.players,catalog:s.engine.catalog)
        XCTAssertEqual(many.bossSupplyNodes.count,3)
        XCTAssertEqual(many.rewards.values.reduce(0){$0+($1.items["revivalStone"] ?? 0)},3)
        for id in Set(many.bossSupplyNodes.values){XCTAssertEqual(many.rewards[id]?.items["largePotion"],many.healingPressure)}
    }
    func testOldDragonAndEditedRewardsAreNotRetimedOnResume()throws {
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4)))
        let boss=s.engine.state.map.nodes.first{$0.kind == .boss}!.id,cache=s.engine.state.map.nodes.first{$0.kind == .reward}!.id
        try s.configureEncounter(node:boss,templates:["ruinDragon"])
        try s.configureReward(node:cache,reward:NodeReward(coins:77,score:5,items:["smallPotion":9,"revivalStone":2,"shieldPotion":3]))
        let saved=s.snapshot,resumed=try MeadowCampaignSession(save:.decoded(saved.encoded()))
        XCTAssertEqual(resumed.engine.archive,saved.archive)
        XCTAssertEqual(resumed.engine.state.units["m-\(boss)-1"]?.templateID,"ruinDragon")
        XCTAssertEqual(resumed.snapshot.formatVersion,1)
    }
    func testRewardSummaryReadsActualEditedContentsWithoutChangingArchive()throws {
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4)))
        let cache=s.engine.state.map.nodes.first{$0.kind == .reward}!.id
        try s.configureReward(node:cache,reward:NodeReward(coins:11,score:3,items:["largePotion":2,"revivalStone":1,"trainingSword":1]))
        let before=s.snapshot,text=try XCTUnwrap(s.rewardSummary(node:cache))
        XCTAssertTrue(text.contains("每位存活领取者"));XCTAssertTrue(text.contains("金币 11 · 积分 3"))
        for (id,count) in [("largePotion",2),("revivalStone",1),("trainingSword",1)]{XCTAssertTrue(text.contains((try s.engine.catalog.item(id).name)+" ×\(count)"))}
        XCTAssertEqual(s.snapshot,before);XCTAssertNil(try s.rewardSummary(node:9999))
    }
}
