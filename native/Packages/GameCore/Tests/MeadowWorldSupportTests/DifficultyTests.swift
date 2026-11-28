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
        // Points too, in the same one operation: undone together with the steps and coins.
        let score=s.engine.state.units["p1"]!.score
        try s.grantSupplies(actors:["p1"],movementSteps:1,coins:5,score:3)
        XCTAssertEqual(s.engine.state.units["p1"]!.score,score+3);XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins+5)
        try s.undoSuppliesGrant()
        XCTAssertEqual(s.engine.state.units["p1"]!.score,score);XCTAssertEqual(s.movementRemaining,0,accuracy:1e-9)
        try s.grantSupplies(actors:["p1"],movementSteps:0,coins:0,score:2)
        XCTAssertEqual(s.engine.state.units["p1"]!.score,score+2)
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
        // Saved on every step, as in the app: the duel must be a valid save (and read back mid-fight).
        var written:Data?
        let s=try MeadowCampaignSession(save:save,persist:{written=$0})
        XCTAssertEqual(s.duelOpponent(actor:"p1"),b.teamID)
        let packA=s.engine.state.units["p1"]!.inventory.values.reduce(0,+),packB=s.engine.state.units["p2"]!.inventory.values.reduce(0,+)
        try s.startDuel(actor:"p1")
        XCTAssertEqual(s.engine.state.battle?.duel,true);XCTAssertEqual(Set(s.engine.state.battle?.queue ?? []),["p1","p2"])
        let midFight=try MeadowCampaignSave.decoded(XCTUnwrap(written))
        XCTAssertEqual(midFight.archive.state.battle?.duel,true);XCTAssertEqual(midFight.archive.state.phase,.teamPvp)
        MeadowCampaignSession.persistInBackground=true;defer{MeadowCampaignSession.persistInBackground=false}
        let background=try MeadowCampaignSession(save:save,persist:{_ in})
        XCTAssertNoThrow(try background.startDuel(actor:"p1"));XCTAssertEqual(background.engine.state.battle?.duel,true)
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
    /// Mid-trip team changes: a player joins another team where it stands, and a player can be removed; both are saved,
    /// read back and can be undone. The operator moves off a player who changes team or leaves.
    func testMidTripChangeTeamAndRemovePlayer()throws {
        var c=MeadowMapConfiguration.suggested(total:8,seed:9);c.starts=2
        let fresh=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),studentClasses:["spellblade","ranger","adventurer"],studentTeams:[0,1,1])
        var written:Data?
        let s=try MeadowCampaignSession(save:fresh.snapshot,persist:{written=$0})
        let red=s.engine.state.units["p1"]!.teamID!,blue=s.engine.state.units["p2"]!.teamID!,blueNode=s.engine.state.units["p2"]!.nodeID
        XCTAssertNotEqual(s.engine.state.units["p1"]!.nodeID,blueNode)
        XCTAssertEqual(s.selectedPlayerID,"p1")
        let moved=try s.movePlayer("p1",toTeam:blue)
        XCTAssertEqual(s.engine.state.units["p1"]!.teamID,blue);XCTAssertEqual(s.engine.state.units["p1"]!.nodeID,blueNode)
        XCTAssertNotEqual(s.selectedPlayerID,"p1")
        XCTAssertThrowsError(try s.movePlayer("p1",toTeam:blue))
        XCTAssertEqual(try MeadowCampaignSave.decoded(XCTUnwrap(written)).archive.state.units["p1"]?.teamID,blue)
        _=moved;try s.engine.undo()
        XCTAssertEqual(s.engine.state.units["p1"]!.teamID,red);XCTAssertNotEqual(s.engine.state.units["p1"]!.nodeID,blueNode)
        try s.selectPlayer("p3")
        let removed=try s.removePlayer("p3")
        XCTAssertNil(s.engine.state.units["p3"]);XCTAssertEqual(s.playerIDs,["p1","p2"]);XCTAssertNotEqual(s.selectedPlayerID,"p3")
        let back=try MeadowCampaignSave.decoded(XCTUnwrap(written))
        XCTAssertNil(back.archive.state.units["p3"]);XCTAssertNoThrow(try MeadowCampaignSession(save:back))
        _=removed;try s.engine.undo();XCTAssertNotNil(s.engine.state.units["p3"])
        try s.removePlayer("p2");try s.removePlayer("p3")
        XCTAssertThrowsError(try s.removePlayer("p1"))
    }
    /// A road never blocks a team switch: a player joins a team that is stopped out on a road (walking on with it),
    /// and a player on that road can switch away (standing with the new team). The result saves and reloads.
    func testTeamSwitchWorksWhileATeamIsOutOnARoad()throws {
        var c=MeadowMapConfiguration.suggested(total:8,seed:9);c.starts=2
        let fresh=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),studentClasses:["spellblade","ranger","adventurer"],studentTeams:[0,1,1])
        // A persist hook makes every write run the full save check, as in the app.
        var written:Data?
        let s=try MeadowCampaignSession(save:fresh.snapshot,persist:{written=$0})
        let red=s.engine.state.units["p1"]!.teamID!,blue=s.engine.state.units["p2"]!.teamID!
        let start=s.engine.state.units["p1"]!.nodeID,next=s.engine.state.map.neighbors(start)[0]
        try s.beginTravel(to:next);try s.advanceTravel(distance:5);try s.setPaused(true)
        let road=try XCTUnwrap(s.travel(holding:"p1"))
        try s.movePlayer("p3",toTeam:red)
        XCTAssertEqual(s.travel(holding:"p3")?.id,road.id);XCTAssertEqual(s.position(of:"p3"),s.position(of:"p1"))
        try s.movePlayer("p1",toTeam:blue)
        XCTAssertNil(s.travel(holding:"p1"));XCTAssertEqual(s.engine.state.units["p1"]!.nodeID,s.engine.state.units["p2"]!.nodeID)
        XCTAssertEqual(s.travel(holding:"p3")?.actors,["p3"])
        let back=try MeadowCampaignSession(save:.decoded(XCTUnwrap(written)))
        XCTAssertEqual(back.travel(holding:"p3")?.id,road.id);XCTAssertNil(back.travel(holding:"p1"))
    }
    /// The teacher (or a student) can leave while their team is stopped out on a road, also when that road is parked
    /// because another team is being operated. The save is checked on every write here, as in the app.
    func testLeavingWorksWhileOnARoad()throws {
        var c=MeadowMapConfiguration.suggested(total:8,seed:9);c.starts=2
        let fresh=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),studentClasses:["spellblade","ranger"],studentTeams:[0,1])
        var written:Data?
        let s=try MeadowCampaignSession(save:fresh.snapshot,persist:{written=$0})
        let blue=s.engine.state.units["p2"]!.teamID!
        _=try s.enter(host:true,name:"林老师",classID:"adventurer",team:blue,appearance:nil)
        try s.selectPlayer("p2")
        let start=s.engine.state.units["p2"]!.nodeID,next=s.engine.state.map.neighbors(start)[0]
        try s.beginTravel(to:next,actor:"p2");try s.advanceTravel(distance:5);try s.setPaused(true)
        XCTAssertEqual(Set(s.travel(holding:"p7")?.actors ?? []),["p2","p7"])
        try s.selectPlayer("p1")  // the blue road is now parked
        XCTAssertNotNil(s.parkedTravels[blue])
        try s.leave("p7")
        XCTAssertNil(s.engine.state.units["p7"]);XCTAssertEqual(s.parkedTravels[blue]?.actors,["p2"])
        XCTAssertNoThrow(try MeadowCampaignSession(save:.decoded(XCTUnwrap(written))))
        try s.engine.undo();XCTAssertNotNil(s.engine.state.units["p7"])
    }
    /// Raid-style personal loot: everyone in the fight gets the kill score (3, as much as a near cache), coins are shared
    /// out, and each fighter rolls the item drops on their own. Kill score lines up with supply caches.
    func testPersonalLootGivesEveryFighterTheKillScoreAndASplitPurse()throws {
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:10)),studentClasses:["spellblade","ranger","adventurer"])
        XCTAssertEqual(s.engine.catalog.rules.personalLoot,true)
        let monster=try XCTUnwrap(s.engine.state.units.values.filter{$0.kind == .monster}.sorted{$0.id<$1.id}.first)
        let definition=try s.engine.catalog.monster(monster.templateID)
        XCTAssertEqual(definition.score,definition.boss ? 10:3)
        let purse=definition.drops.filter{$0.itemID==nil}.map(\.coins).reduce(0,+)
        let before=s.engine.state.players.map{($0.id,$0.coins,$0.score)}
        try s.engine.apply(.startBattle(kind:.pve,monsters:[monster.id]))
        let fighters=s.engine.state.battle!.queue.filter{s.engine.state.units[$0]?.kind == .player}
        XCTAssertEqual(fighters.count,3)
        try s.engine.apply(.setHealth(unit:monster.id,value:0,killer:"p1"))
        var gained=0
        for (id,coins,score) in before {
            let u=s.engine.state.units[id]!
            XCTAssertEqual(u.score-score,definition.score,"\(id) gets the kill score")
            gained+=u.coins-coins
            XCTAssertLessThanOrEqual(abs((u.coins-coins)-purse/3),1)
        }
        XCTAssertEqual(gained,purse)
        let caches=try MeadowProvisioning.plan(layout:s.snapshot.layout,players:s.engine.state.players,catalog:s.engine.catalog).rewards.values.map(\.score)
        XCTAssertEqual(caches.min(),2)
    }
    /// Two team camps: each camp's nearest fight is an opening one and each camp's caches start from the same small
    /// treasure, so neither camp starts next to the stronger, richer spots.
    func testEveryCampGetsItsOwnEasyToHardRing()throws {
        var checked=0
        for seed in [UInt64(9),21,77,1234,98765] {
            var c=MeadowMapConfiguration.suggested(total:14,seed:seed);c.starts=2
            guard let layout=try? MeadowMapGenerator.generate(c) else{continue}
            let near=MeadowEncounterPlanner.campDistances(layout)
            let plan=MeadowEncounterPlanner.plan(layout)
            let camps=Set(plan.filter{$0.band != "boss"}.compactMap{near[$0.nodeID]?.camp})
            guard camps.count==2 else{continue}
            for camp in camps {
                let mine=plan.filter{$0.band != "boss" && near[$0.nodeID]?.camp==camp}.sorted{$0.distance<$1.distance}
                XCTAssertEqual(mine.first?.band,"opening","seed \(seed) camp \(camp)")
            }
            let s=try MeadowCampaignSession.new(layout:layout,studentClasses:["spellblade","ranger"],studentTeams:[0,1])
            let rewards=try MeadowProvisioning.plan(layout:layout,players:s.engine.state.players,catalog:s.engine.catalog).rewards
            let byCamp=Dictionary(grouping:rewards,by:{near[$0.key]?.camp ?? -1})
            if byCamp.count==2 {for (_,list) in byCamp {XCTAssertEqual(list.map(\.value.score).min(),2,"seed \(seed)")}}
            checked+=1
        }
        XCTAssertGreaterThan(checked,0)
    }
    /// Two teams on the same monster spot: the team that takes it on fights; the other one is not pulled in.
    func testOnlyTheArrivingTeamFightsWhenAnotherTeamIsThere()throws {
        var c=MeadowMapConfiguration.suggested(total:8,seed:9);c.starts=2
        let fresh=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c),studentClasses:["spellblade","ranger"],studentTeams:[0,1])
        let monster=try XCTUnwrap(fresh.engine.state.units.values.filter{$0.kind == .monster}.sorted{$0.id<$1.id}.first)
        var save=fresh.snapshot
        save.archive.state.units["p1"]!.nodeID=monster.nodeID;save.archive.state.units["p2"]!.nodeID=monster.nodeID
        let s=try MeadowCampaignSession(save:save)
        XCTAssertNotEqual(s.engine.state.units["p1"]!.teamID,s.engine.state.units["p2"]!.teamID)
        try s.interactCurrentNode(actor:"p2")
        let queue=s.engine.state.battle?.queue ?? []
        XCTAssertTrue(queue.contains("p2"));XCTAssertFalse(queue.contains("p1"))
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
