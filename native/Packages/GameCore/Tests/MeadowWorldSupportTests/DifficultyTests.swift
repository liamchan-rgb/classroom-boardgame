import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class DifficultyTests:XCTestCase {
    private func layout()throws->GeneratedMeadowMap {
        var c=MeadowMapConfiguration.suggested(total:4,seed:317)
        c.combat=3;c.boss=0;c.reward=0;c.empty=0;c.extraRoads=0
        return try MeadowMapGenerator.generate(c)
    }
    private func monsters(_ s:MeadowCampaignSession)->[GameUnit] {s.engine.state.units.values.filter{$0.kind == .monster}.sorted{$0.id<$1.id}}
    private func stats(_ s:MeadowCampaignSession,_ u:GameUnit)throws->Attributes {try GameRules.attributes(u,catalog:s.engine.catalog)}

    func testLevelsScaleMonsterHealthAndDamageOnly()throws {
        let normal=try MeadowCampaignSession.new(layout:layout())
        let hard=try MeadowCampaignSession.new(layout:layout(),difficulty:.hard)
        XCTAssertNil(normal.engine.state.difficulty);XCTAssertEqual(hard.engine.state.difficulty,.hard)
        for (a,b) in zip(monsters(normal),monsters(hard)) {
            let base=try stats(normal,a),scaled=try stats(hard,b)
            XCTAssertEqual(scaled.maximumHealth,(base.maximumHealth*150+50)/100);XCTAssertEqual(b.health,scaled.maximumHealth)
            XCTAssertEqual(scaled.damage,base.damage+2);XCTAssertEqual(scaled.baseAP,base.baseAP)
        }
        XCTAssertEqual(normal.engine.state.players,hard.engine.state.players)
    }
    func testSwitchKeepsWoundShareAndRoundTripsAndRestores()throws {
        let s=try MeadowCampaignSession.new(layout:layout())
        let first=monsters(s)[0],max=try stats(s,first).maximumHealth
        try s.engine.apply(.setHealth(unit:first.id,value:max/2,killer:nil))
        let random=s.engine.state.random
        try s.setDifficulty(.nightmare)
        let wounded=s.engine.state.units[first.id]!,newMax=try stats(s,wounded).maximumHealth
        XCTAssertEqual(newMax,max*2);XCTAssertEqual(wounded.health,(max/2*newMax+max/2)/max)
        XCTAssertEqual(try stats(s,wounded).damage,try s.engine.catalog.monster(wounded.templateID).attributes.damage+4)
        XCTAssertEqual(s.engine.state.random,random)
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(restored.difficulty,.nightmare);XCTAssertEqual(restored.engine.state.units,s.engine.state.units)
        try s.setDifficulty(.normal)
        XCTAssertNil(s.engine.state.difficulty)
        for u in monsters(s) {XCTAssertEqual(u.baseAttributes,try s.engine.catalog.monster(u.templateID).attributes)}
    }
    func testNewEncountersFollowLevelAndBattleRefusesSwitch()throws {
        let s=try MeadowCampaignSession.new(layout:layout(),difficulty:.easy)
        let node=monsters(s)[0].nodeID,template=monsters(s)[0].templateID
        try s.configureEncounter(node:node,templates:[template])
        let placed=s.engine.state.units["m-\(node)-1"]!,base=try s.engine.catalog.monster(template).attributes
        XCTAssertEqual(placed.baseAttributes.maximumHealth,(base.maximumHealth*75+50)/100);XCTAssertEqual(placed.health,placed.baseAttributes.maximumHealth)
        try s.engine.apply(.startBattle(kind:.pve,monsters:[placed.id]))
        let before=s.snapshot
        XCTAssertThrowsError(try s.setDifficulty(.hard));XCTAssertEqual(s.snapshot,before)
    }
    func testOldSavesWithoutLevelLoadAsNormal()throws {
        let s=try MeadowCampaignSession.new(layout:layout())
        let bytes=try s.snapshot.encoded()
        XCTAssertFalse(String(decoding:bytes,as:UTF8.self).contains("difficulty"))
        XCTAssertEqual(try MeadowCampaignSession(save:.decoded(bytes)).difficulty,.normal)
    }
    func testLeavingBattleKeepsHealthAndMonstersForLater()throws {
        let s=try MeadowCampaignSession.new(layout:layout())
        let monster=monsters(s)[0]
        XCTAssertFalse(s.canLeaveBattle);XCTAssertThrowsError(try s.leaveBattle())
        try s.engine.apply(.startBattle(kind:.pve,monsters:[monster.id]))
        try s.engine.apply(.setHealth(unit:monster.id,value:1,killer:nil))
        let coins=s.engine.state.players.map(\.coins),health=s.engine.state.players.map(\.health)
        XCTAssertTrue(s.canLeaveBattle)
        try s.leaveBattle()
        XCTAssertNil(s.engine.state.battle);XCTAssertEqual(s.engine.state.phase,.exploration)
        XCTAssertEqual(s.engine.state.lastOutcome?.winners,[])
        XCTAssertEqual(s.engine.state.players.map(\.coins),coins);XCTAssertEqual(s.engine.state.players.map(\.health),health)
        let left=s.engine.state.units[monster.id]!
        XCTAssertEqual(left.health,1);XCTAssertFalse(left.active);XCTAssertEqual(left.nodeID,monster.nodeID)
    }
    func testSuppliesGrantAddsCoinsAndMovementStepsAndUndoesBoth()throws {
        let initial=try MeadowCampaignSession.new(layout:layout());var save=initial.snapshot
        save.movement?.remaining=0
        let s=try MeadowCampaignSession(save:save),coins=s.engine.state.units["p1"]!.coins
        try s.grantSupplies(actors:["p1"],movementSteps:2,coins:15)
        XCTAssertEqual(s.movementRemaining,2*MeadowMovementRules.distancePerStep,accuracy:1e-9)
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins+15)
        try s.undoSuppliesGrant()
        XCTAssertEqual(s.movementRemaining,0,accuracy:1e-9);XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins)
        try s.grantSupplies(actors:["p1","p2"],movementSteps:99,coins:0)
        XCTAssertEqual(s.movementRemaining,s.movementCapacity,accuracy:1e-9)
        XCTAssertThrowsError(try s.grantSupplies(actors:["p1"],movementSteps:0,coins:0))
    }
    func testTeammatesGiveItemsAndCoinsInsideThePack()throws {
        let s=try MeadowCampaignSession.new(layout:layout())
        try s.engine.apply(.reward(actors:["p1"],value:ResourceReward(coins:30,items:["smallPotion":2])))
        let p1=s.engine.state.units["p1"]!,p2=s.engine.state.units["p2"]!
        XCTAssertEqual(s.teammates(of:"p1").map(\.id),["p2"])
        try s.give(from:"p1",to:"p2",item:"smallPotion",count:1)
        try s.give(from:"p1",to:"p2",coins:10)
        XCTAssertEqual(s.engine.state.units["p1"]!.inventory["smallPotion"] ?? 0,(p1.inventory["smallPotion"] ?? 0)-1)
        XCTAssertEqual(s.engine.state.units["p2"]!.inventory["smallPotion"] ?? 0,(p2.inventory["smallPotion"] ?? 0)+1)
        XCTAssertEqual(s.engine.state.units["p2"]!.coins,p2.coins+10);XCTAssertEqual(s.engine.state.units["p1"]!.coins,p1.coins-10)
        XCTAssertThrowsError(try s.give(from:"p1",to:"p1",coins:1))
        XCTAssertThrowsError(try s.give(from:"p2",to:"p1",item:"largePotion",count:99))
    }
    func testTeamCampsDuelOnceWithSpoilsAndGMReset()throws {
        var c=MeadowMapConfiguration.suggested(total:8,seed:9);c.starts=2
        let layout=try MeadowMapGenerator.generate(c)
        XCTAssertEqual(layout.map.nodes.filter{$0.kind == .start}.count,2)
        let fresh=try MeadowCampaignSession.new(layout:layout,studentClasses:["spellblade","ranger"],studentTeams:[0,1])
        let a=fresh.engine.state.units["p1"]!,b=fresh.engine.state.units["p2"]!
        XCTAssertNotEqual(a.teamID,b.teamID);XCTAssertNotEqual(a.nodeID,b.nodeID)
        XCTAssertNil(fresh.duelOpponent(actor:"p1"))
        var save=fresh.snapshot
        save.archive.state.units["p2"]!.nodeID=a.nodeID
        save.archive.state.units["p1"]!.coins=0;save.archive.state.units["p1"]!.score=0
        save.archive.state.units["p2"]!.coins=100;save.archive.state.units["p2"]!.score=10
        let s=try MeadowCampaignSession(save:save)
        XCTAssertEqual(s.duelOpponent(actor:"p1"),b.teamID)
        let packA=s.engine.state.units["p1"]!.inventory.values.reduce(0,+),packB=s.engine.state.units["p2"]!.inventory.values.reduce(0,+)
        try s.startDuel(actor:"p1")
        XCTAssertEqual(s.engine.state.battle?.duel,true);XCTAssertEqual(Set(s.engine.state.battle?.queue ?? []),["p1","p2"])
        try s.engine.apply(.setHealth(unit:"p2",value:0,killer:nil))
        XCTAssertNil(s.engine.state.battle);XCTAssertEqual(s.engine.state.phase,.exploration)
        XCTAssertEqual(s.engine.state.lastOutcome?.winners,[a.teamID!])
        XCTAssertEqual(s.engine.state.units["p2"]!.health,1)
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,30);XCTAssertEqual(s.engine.state.units["p2"]!.coins,70)
        XCTAssertEqual(s.engine.state.units["p1"]!.score,3);XCTAssertEqual(s.engine.state.units["p2"]!.score,7)
        XCTAssertEqual(s.engine.state.units["p1"]!.inventory.values.reduce(0,+),packA+(packB>0 ? 1:0))
        XCTAssertNil(s.duelOpponent(actor:"p1"));XCTAssertThrowsError(try s.startDuel(actor:"p1"))
        try s.resetDuelLimits();XCTAssertEqual(s.duelOpponent(actor:"p1"),b.teamID)
    }
    func testSplitTeamsFightTheirOwnEncounters()throws {
        var c=MeadowMapConfiguration.suggested(total:8,seed:9);c.starts=2
        let fresh=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),studentClasses:["spellblade","ranger"],studentTeams:[0,1])
        let monster=try XCTUnwrap(fresh.engine.state.units.values.filter{$0.kind == .monster}.sorted{$0.id<$1.id}.first)
        var save=fresh.snapshot;save.archive.state.units["p1"]!.nodeID=monster.nodeID
        let s=try MeadowCampaignSession(save:save)
        let others=s.engine.state.units.values.filter{$0.kind == .monster && $0.nodeID==monster.nodeID}.map(\.id).sorted()
        try s.engine.apply(.startBattle(kind:.pve,monsters:others))
        let queue=s.engine.state.battle?.queue ?? []
        XCTAssertTrue(queue.contains("p1"));XCTAssertFalse(queue.contains("p2"))
        try s.engine.apply(.setHealth(unit:"p1",value:0,killer:nil))
        XCTAssertTrue(s.mustRetreat)
        try s.retreatAfterWipe()
        XCTAssertEqual(s.engine.state.units["p1"]!.health,1);XCTAssertEqual(s.engine.state.units["p2"]!.health,fresh.engine.state.units["p2"]!.health)
    }
}
