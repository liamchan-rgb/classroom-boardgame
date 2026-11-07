import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class ProvisionsPreviewTests:XCTestCase {
    func testCoinBudgetUsesPhysicalRoadsAndPerRecipientPayoutWithoutDoubling()throws {
        for n in [4,10,30] {for seed:UInt64 in [0,31827,UInt64.max] {
            let layout=try MeadowMapGenerator.generate(.suggested(total:n,seed:seed)),s=try MeadowCampaignSession.new(layout:layout)
            let plan=try MeadowProvisioning.plan(layout:layout,players:s.engine.state.players,catalog:s.engine.catalog)
            let issued=plan.startingCoins.values.reduce(0,+)+plan.rewards.values.map(\.coins).reduce(0,+)*s.playerIDs.count
            XCTAssertGreaterThanOrEqual(issued,plan.movementCoinBudget)
            XCTAssertLessThan(issued,plan.movementCoinBudget+s.playerIDs.count)
            XCTAssertGreaterThan(plan.treeTourDistance,0)
            XCTAssertEqual(Set(plan.rewards.keys),Set(layout.map.nodes.filter{$0.kind == .reward}.map(\.id)))
            for node in s.engine.state.map.nodes where node.kind == .reward{XCTAssertEqual(node.reward,plan.rewards[node.id])}
            XCTAssertEqual(s.partyCoins,plan.startingCoins.values.reduce(0,+))
            XCTAssertEqual(s.engine.state.random,RandomState(seed:seed ^ 0x43414d504149474e))
        }}
    }
    func testFirstSupplyReachableWithPaidRefillsAndRewardIsIssuedExactlyOnce()throws {
        let layout=try MeadowMapGenerator.generate(.suggested(total:30,seed:UInt64.max)),s=try MeadowCampaignSession.new(layout:layout)
        let start=s.engine.state.units["p1"]!.nodeID
        let target=try XCTUnwrap(s.engine.state.map.nodes.filter{$0.kind == .reward}.min {
            let a=s.routeDistance(s.engine.state.map.shortestPath(from:start,to:$0.id)!),b=s.routeDistance(s.engine.state.map.shortestPath(from:start,to:$1.id)!)
            return a==b ? $0.id<$1.id:a<b
        })
        let expected=target.reward!,inventory=s.engine.state.units["p1"]!.inventory
        try s.beginTravel(to:target.id);try finishPaid(s)
        XCTAssertEqual(s.snapshot.movement?.manualRefills,0)
        let oldCoins=s.partyCoins;try s.interactCurrentNode()
        XCTAssertEqual(s.partyCoins,oldCoins+expected.coins*2)
        for (id,count) in expected.items{XCTAssertEqual(s.engine.state.units["p1"]!.inventory[id,default:0],inventory[id,default:0]+count)}
        let save=s.snapshot;XCTAssertThrowsError(try s.interactCurrentNode());XCTAssertEqual(s.snapshot,save)
        let restored=try MeadowCampaignSession(save:.decoded(save.encoded()));XCTAssertEqual(restored.snapshot,save)
    }
    func testNoSupplyMapHasRoadMoneyForClosedTreeTourWithoutDrops()throws {
        var c=MeadowMapConfiguration.suggested(total:10,seed:27);c.combat=9;c.boss=0;c.reward=0;c.empty=0
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c)),start=s.engine.state.units["p1"]!.nodeID
        var visited:Set<Int>=[start],walk=[start]
        func visit(_ n:Int){for next in s.engine.state.map.neighbors(n) where visited.insert(next).inserted{walk.append(next);visit(next);walk.append(n)}}
        visit(start)
        let before=s.engine.state.players.map(\.ap)
        for id in walk.dropFirst(){try s.beginTravel(to:id);try finishPaid(s)}
        XCTAssertEqual(s.engine.state.units["p1"]!.nodeID,start)
        XCTAssertEqual(s.snapshot.movement?.manualRefills,0);XCTAssertGreaterThan(s.snapshot.movement?.purchasedRefills ?? 0,0)
        XCTAssertEqual(s.engine.state.players.map(\.ap),before);XCTAssertNil(s.engine.state.battle)
    }
    func testQuietMapHasNoCombatMedicineAndOldEditedSaveIsNotReprovisioned()throws {
        var c=MeadowMapConfiguration.suggested(total:4);c.combat=0;c.boss=0;c.reward=3;c.empty=0
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c))
        XCTAssertTrue(s.engine.state.map.nodes.compactMap(\.reward).allSatisfy{$0.items.isEmpty})
        var save=s.snapshot;save.archive.state.units["p1"]!.coins=1;save.archive.state.units["p2"]!.coins=0
        let i=save.archive.state.map.nodes.firstIndex{$0.kind == .reward}!
        save.archive.state.map.nodes[i].reward=NodeReward(coins:3,score:9,items:["shieldPotion":7])
        let resumed=try MeadowCampaignSession(save:.decoded(save.encoded()))
        XCTAssertEqual(resumed.engine.archive,save.archive);XCTAssertEqual(resumed.partyCoins,1)
        XCTAssertEqual(resumed.snapshot.formatVersion,1)
    }
    func testSupplyPressureAndFinalBossCacheScaleWithoutChangingCatalog()throws {
        var c=MeadowMapConfiguration.suggested(total:10);c.combat=7;c.boss=1;c.reward=1;c.empty=0
        let layout=try MeadowMapGenerator.generate(c),s=try MeadowCampaignSession.new(layout:layout)
        let plan=try MeadowProvisioning.plan(layout:layout,players:s.engine.state.players,catalog:s.engine.catalog)
        let reward=try XCTUnwrap(plan.rewards.values.first)
        XCTAssertGreaterThanOrEqual(plan.healingPressure,2)
        XCTAssertEqual(reward.items["largePotion"],plan.healingPressure)
        XCTAssertEqual(reward.items["shieldPotion"],1);XCTAssertEqual(reward.items["revivalStone"],1)
        XCTAssertEqual(try GameCatalog.initial().monsters,Array(s.engine.catalog.monsters.prefix(6)))
    }
    func testPreviewIsReadOnlyAndReflectsManualMixedDamagedAndClearedMonsters()throws {
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:10)))
        let node=s.engine.state.map.nodes.first{$0.kind == .combat}!.id
        try s.configureEncounter(node:node,templates:["stoneGuardian","goblinArcher","meadowStag"])
        try s.engine.apply(.setHealth(unit:"m-\(node)-1",value:17,killer:nil))
        try s.engine.apply(.setHealth(unit:"m-\(node)-2",value:0,killer:nil))
        let before=s.snapshot,readout=try XCTUnwrap(s.encounterPreview(node:node))
        XCTAssertEqual(readout.monsters.map(\.templateID),["stoneGuardian","goblinArcher","meadowStag"])
        XCTAssertEqual(readout.monsters[0].health,17);XCTAssertEqual(readout.monsters[0].shield,6)
        XCTAssertEqual(readout.monsters[0].skills,["石肤"]);XCTAssertEqual(readout.monsters[0].attack,"1D8")
        XCTAssertEqual(readout.monsters[1].health,0);XCTAssertEqual(readout.monsters[2].name,"林地鹿灵")
        XCTAssertFalse(readout.cleared);XCTAssertFalse(readout.canInteract);XCTAssertEqual(s.snapshot,before)
        for m in readout.monsters where m.health>0{try s.engine.apply(.setHealth(unit:m.id,value:0,killer:nil))}
        XCTAssertTrue(try XCTUnwrap(s.encounterPreview(node:node)).cleared)
        XCTAssertNil(try s.encounterPreview(node:9999))
    }
    func testPreviewCanStartOnlyAfterArrivalAndCannotStartAgainDuringBattle()throws {
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:10)))
        let node=s.engine.state.map.nodes.first{$0.kind == .combat}!.id
        XCTAssertFalse(try XCTUnwrap(s.encounterPreview(node:node)).canInteract)
        try s.beginTravel(to:node);try s.advanceTravel(distance:10)
        XCTAssertFalse(try XCTUnwrap(s.encounterPreview(node:node)).canInteract)
        while s.travel != nil{if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)};try s.advanceTravel(distance:100000)}
        XCTAssertTrue(try XCTUnwrap(s.encounterPreview(node:node)).canInteract)
        try s.interactCurrentNode();XCTAssertFalse(try XCTUnwrap(s.encounterPreview(node:node)).canInteract)
    }
    private func finishPaid(_ s:MeadowCampaignSession)throws {
        for _ in 0..<300 where s.travel != nil {
            if !s.isMoving{try s.refillMovement(usingCoins:true);try s.setPaused(false)}
            try s.advanceTravel(distance:100000)
        }
        XCTAssertNil(s.travel)
    }
}
