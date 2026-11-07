import XCTest
import ClassroomGameCore
import MeadowBattleSupport
@testable import MeadowWorldSupport

final class CampaignTests:XCTestCase {
    func layout(combat:Bool=false)throws->GeneratedMeadowMap {
        var c=MeadowMapConfiguration.suggested(total:4,seed:317)
        c.combat=combat ? 3:0;c.boss=0;c.reward=combat ? 0:3;c.empty=0;c.extraRoads=0
        return try MeadowMapGenerator.generate(c)
    }
    func testPreviewAndPartialTravelHaveNoEarlySettlement()throws {
        let s=try MeadowCampaignSession.new(layout:layout()),before=s.engine.archive,start=s.engine.state.units["p1"]!.nodeID,target=s.engine.state.map.neighbors(s.engine.state.units["p1"]!.nodeID)[0]
        let preview=s.preview(to:target),capacity=s.movementRemaining,length=s.routeDistance([start,target])
        XCTAssertTrue(preview.allowed);XCTAssertEqual(preview.cost,Int(ceil(length)));XCTAssertEqual(s.engine.archive,before)
        try s.beginTravel(to:target);try s.advanceTravel(distance:min(20,length*0.25))
        XCTAssertEqual(s.engine.archive,before);XCTAssertEqual(s.movementRemaining,capacity-min(20,length*0.25),accuracy:0.000001)
        try finishTravel(s);XCTAssertNil(s.travel)
        XCTAssertNil(s.engine.state.battle);XCTAssertFalse(s.engine.state.map.nodes.first{$0.id==target}!.rewardCompleted)
        for id in ["p1","p2"]{XCTAssertEqual(s.engine.state.units[id]!.ap,before.state.units[id]!.ap);XCTAssertEqual(s.engine.state.units[id]!.coins,before.state.units[id]!.coins)}
        try s.interactCurrentNode();XCTAssertTrue(s.engine.state.map.nodes.first{$0.id==target}!.rewardCompleted)
        XCTAssertEqual(s.engine.state.units["p1"]!.coins,before.state.units["p1"]!.coins+before.state.map.nodes.first{$0.id==target}!.reward!.coins)
    }
    func testEachActualEdgeArrivesAndChargesOnce()throws {
        let s=try MeadowCampaignSession.new(layout:layout()),start=s.engine.state.units["p1"]!.nodeID
        let target=s.engine.state.map.nodes.max{s.engine.state.map.distance(from:start,to:$0.id)!<s.engine.state.map.distance(from:start,to:$1.id)!}!.id
        let plan=try s.beginTravel(to:target),distance=s.routeDistance(plan.path),ap=s.engine.state.units["p1"]!.ap,initialCoins=s.partyCoins
        try finishTravel(s)
        XCTAssertEqual(s.snapshot.movement!.totalDistance,distance,accuracy:0.000001)
        XCTAssertEqual(s.engine.history.flatMap(\.events).filter{$0.kind=="campaignArrival"}.count,plan.path.count-1)
        XCTAssertEqual(s.engine.state.units["p1"]!.ap,ap);XCTAssertEqual(s.partyCoins,initialCoins)
        XCTAssertFalse(s.engine.state.map.nodes.contains{$0.rewardCompleted})
        try s.interactCurrentNode();let coins=s.engine.state.units["p1"]!.coins
        XCTAssertThrowsError(try s.interactCurrentNode());XCTAssertEqual(s.engine.state.units["p1"]!.coins,coins)
    }
    func testMidRoadSaveRestoresExactCursorPausedWithoutReroll()throws {
        let s=try MeadowCampaignSession.new(layout:layout()),start=s.engine.state.units["p1"]!.nodeID,target=s.engine.state.map.neighbors(start)[0]
        try s.beginTravel(to:target);try s.advanceTravel(distance:28)
        let p=s.position(of:"p1"),bytes=try s.snapshot.encoded()
        let restored=try MeadowCampaignSession(save:MeadowCampaignSave.decoded(bytes))
        XCTAssertEqual(restored.position(of:"p1"),p);XCTAssertFalse(restored.isMoving)
        let before=restored.engine.archive
        XCTAssertTrue(try restored.advanceTravel(distance:100000).isEmpty);XCTAssertEqual(restored.engine.archive,before)
        try restored.setPaused(false);try finishTravel(restored)
        XCTAssertEqual(restored.engine.state.units["p1"]?.coins,before.state.units["p1"]?.coins)
        try restored.interactCurrentNode();XCTAssertEqual(restored.engine.state.units["p1"]!.coins,before.state.units["p1"]!.coins+before.state.map.nodes.first{$0.id==target}!.reward!.coins)
        XCTAssertEqual(restored.engine.state.random,before.state.random)
    }
    func testArrivalSaveFailureDoesNotSpendAPRevealOrReward()throws {
        var fail=false,stored=Data()
        let s=try MeadowCampaignSession.new(layout:layout(),persist:{data in if fail {throw GameError("disk full")};stored=data})
        let start=s.engine.state.units["p1"]!.nodeID,target=s.engine.state.map.neighbors(start)[0]
        try s.beginTravel(to:target);let before=s.engine.archive,old=stored
        fail=true;XCTAssertThrowsError(try finishTravel(s))
        XCTAssertEqual(s.engine.archive,before);XCTAssertEqual(stored,old);XCTAssertFalse(s.isMoving)
        fail=false;try s.setPaused(false);try finishTravel(s)
        XCTAssertEqual(s.engine.history.flatMap(\.events).filter{$0.kind=="campaignArrival"}.count,1);XCTAssertEqual(s.engine.state.units["p1"]?.coins,before.state.units["p1"]?.coins)
        try s.interactCurrentNode();XCTAssertEqual(s.engine.state.units["p1"]!.coins,before.state.units["p1"]!.coins+before.state.map.nodes.first{$0.id==target}!.reward!.coins)
    }
    func testEncounterStopsAtFirstEnemyAndPreservesOneEngine()throws {
        var stored=Data();let s=try MeadowCampaignSession.new(layout:layout(combat:true),persist:{stored=$0})
        let start=s.engine.state.units["p1"]!.nodeID,target=s.engine.state.map.neighbors(start)[0]
        let plan=try s.beginTravel(to:target);XCTAssertGreaterThan(plan.cost,0)
        XCTAssertNil(s.engine.state.battle);try finishTravel(s)
        XCTAssertNil(s.engine.state.battle);XCTAssertNil(s.travel)
        try s.interactCurrentNode();XCTAssertNotNil(s.engine.state.battle)
        let battle=try PartyEncounter(engine:s.engine,sessionID:"real-battle")
        XCTAssertTrue(battle.engine === s.engine)
        for _ in 0..<160 {
            if battle.terminal {break}
            guard let actor=battle.current else {XCTFail("missing actor");break}
            let intent:PartyIntent?
            if s.engine.state.units[actor]?.kind == .monster {intent=battle.prepareMonsterStep()}
            else {
                let foe=battle.monsterIDs.first{s.engine.state.units[$0]?.isAlive==true}!
                intent=battle.prepare(.attack,target:foe) ?? battle.prepare(.endTurn,target:actor)
            }
            let action=try XCTUnwrap(intent),before=s.engine.archive
            XCTAssertEqual(try MeadowCampaignSave.decoded(stored).archive,before)
            let receipt=try XCTUnwrap(battle.commit(action.id))
            XCTAssertTrue(battle.engine === s.engine);XCTAssertEqual(receipt.after,s.engine.state)
            XCTAssertNil(try battle.commit(action.id))
            XCTAssertEqual(try MeadowCampaignSave.decoded(stored).archive,s.engine.archive)
        }
        XCTAssertTrue(battle.terminal)
        let restored=try MeadowCampaignSession(save:.decoded(stored))
        XCTAssertEqual(restored.engine.archive,s.engine.archive)
        XCTAssertEqual(restored.snapshot.layout,s.snapshot.layout)
    }
    func testConfirmedBattleSaveFailureLeavesLiveDiceAndResourcesUnchanged()throws {
        var fail=false
        let s=try MeadowCampaignSession.new(layout:layout(combat:true),persist:{_ in if fail {throw GameError("disk")}})
        let start=s.engine.state.units["p1"]!.nodeID;try s.beginTravel(to:s.engine.state.map.neighbors(start)[0]);try finishTravel(s)
        try s.interactCurrentNode()
        let b=try PartyEncounter(engine:s.engine)
        let intent=try XCTUnwrap(s.engine.state.units[b.current!]?.kind == .monster ? b.prepareMonsterStep():b.prepare(.attack,target:b.monsterIDs[0]))
        let before=s.engine.archive;fail=true
        XCTAssertThrowsError(try b.commit(intent.id));XCTAssertEqual(s.engine.archive,before)
        XCTAssertNil(b.pending)
    }
    func testStoreDoesNotReplaceCorruptFilesAndRejectsBadCursor()throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let store=MeadowCampaignStore(url:folder.appendingPathComponent("campaign-v1.json"))
        try store.write(Data("invalid".utf8));XCTAssertThrowsError(try store.read())
        XCTAssertEqual(try Data(contentsOf:store.url),Data("invalid".utf8))
        let s=try MeadowCampaignSession.new(layout:layout());var snapshot=s.snapshot;snapshot.formatVersion=999
        XCTAssertThrowsError(try MeadowCampaignSession(save:snapshot))
        let start=s.engine.state.units["p1"]!.nodeID;try s.beginTravel(to:s.engine.state.map.neighbors(start)[0])
        snapshot=s.snapshot;snapshot.travel?.distance = .nan;XCTAssertThrowsError(try snapshot.encoded())
        snapshot=s.snapshot;snapshot.travel?.leg=999;XCTAssertThrowsError(try snapshot.encoded())
    }
    func testBossKeepsOriginalStatsAndChoosesRealRegenerationAI()throws {
        var c=MeadowMapConfiguration.suggested(total:4,seed:317);c.combat=0;c.boss=3;c.reward=0;c.empty=0
        let session=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(c))
        let source=try GameCatalog.initial(),boss=try session.engine.catalog.monster("meadowElderStag")
        XCTAssertEqual(boss.attributes,try source.monster("caveTroll").attributes)
        XCTAssertEqual(boss.skills,try source.monster("caveTroll").skills)
        let start=session.engine.state.units["p1"]!.nodeID
        let target=session.engine.state.map.neighbors(start)[0]
        try session.configureEncounter(node:target,templates:["caveTroll"])
        try session.beginTravel(to:target);try finishTravel(session)
        try session.interactCurrentNode()
        let encounter=try PartyEncounter(engine:session.engine),id=encounter.monsterIDs[0]
        try session.engine.apply(.editResources(unit:id,value:ResourcePatch(health:12)))
        for _ in 0..<3 where session.engine.state.units[encounter.current ?? ""]?.kind == .player {
            try session.engine.apply(.endTurn(actor:encounter.current!,timedOut:false))
        }
        let before=session.engine.archive,intent=try XCTUnwrap(encounter.prepareMonsterStep())
        XCTAssertEqual(intent.action,.regeneration);XCTAssertEqual(intent.target,id)
        XCTAssertEqual(session.engine.archive,before)
        XCTAssertEqual(PartyVisual.foot(id)?.x,PartyVisual.feet["m1"]?.x)
        XCTAssertEqual(PartyVisual.hitPoint(target:id).x,PartyVisual.hitPoint(target:"m1").x)
        let dice=BattleDice.channels(intent.action,actor:before.state.units[id]!,target:before.state.units[id]!,catalog:session.engine.catalog,receipt:encounter.confirmedReceipt)
        XCTAssertFalse(dice.isEmpty)
        for age in stride(from:0.0,through:1.1,by:1.0/60) {
            let anchor=PartyVisual.diceAnchor(actor:id,intent:intent,age:age,diceCount:dice.count)
            XCTAssertTrue(anchor.x.isFinite && anchor.y.isFinite)
        }
        let receipt=try XCTUnwrap(encounter.commit(intent.id))
        XCTAssertGreaterThan(receipt.after.units[id]!.health,12)
    }

    func testCampaignDiceThroughTwoRoundsAndResumedMonsterTurn()throws {
        for seed:UInt64 in [317,318,319] {
            var config=MeadowMapConfiguration.suggested(total:4,seed:seed)
            config.combat=3;config.boss=0;config.reward=0;config.empty=0
            var session=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(config))
            let start=session.engine.state.units["p1"]!.nodeID
            try session.beginTravel(to:session.engine.state.map.neighbors(start)[0]);try finishTravel(session)
            try session.interactCurrentNode()
            var encounter=try PartyEncounter(engine:session.engine),monsterTurns=0,resumed=false
            for _ in 0..<30 {
                if encounter.round>=3 {break}
                let actor=try XCTUnwrap(encounter.current)
                if session.engine.state.units[actor]?.kind == .player {
                    let intent=try XCTUnwrap(encounter.prepare(.endTurn,target:actor));_ = try encounter.commit(intent.id)
                } else {
                    // Preserve both players for two full rounds; no player
                    // attacks, so every persistent monster reaches its turn.
                    for id in session.playerIDs {
                        let maximum=try GameRules.attributes(session.engine.state.units[id]!,catalog:session.engine.catalog).maximumHealth
                        try session.engine.apply(.editResources(unit:id,value:ResourcePatch(health:maximum,shield:8)))
                    }
                    if !resumed {
                        let archive=session.engine.archive
                        session=try MeadowCampaignSession(save:.decoded(session.snapshot.encoded()))
                        XCTAssertEqual(session.engine.archive,archive)
                        encounter=try PartyEncounter(engine:session.engine);resumed=true
                    }
                    let intent=try XCTUnwrap(encounter.prepareMonsterStep()),before=session.engine.archive
                    let dice=BattleDice.channels(intent.action,actor:before.state.units[intent.actor]!,target:before.state.units[intent.target]!,catalog:session.engine.catalog,receipt:encounter.confirmedReceipt)
                    XCTAssertFalse(dice.isEmpty);XCTAssertTrue(intent.actor.hasPrefix("m-"))
                    for age in stride(from:0.0,through:1.1,by:1.0/60) {
                        let anchor=PartyVisual.diceAnchor(actor:intent.actor,intent:intent,age:age,shielded:true,diceCount:dice.count)
                        XCTAssertTrue(anchor.x.isFinite && anchor.y.isFinite)
                    }
                    XCTAssertEqual(session.engine.archive,before)
                    _ = try encounter.commit(intent.id);XCTAssertNil(try encounter.commit(intent.id));monsterTurns+=1
                }
            }
            XCTAssertTrue(resumed);XCTAssertGreaterThanOrEqual(encounter.round,3)
            XCTAssertGreaterThanOrEqual(monsterTurns,encounter.monsterIDs.count*2)
        }
    }
    func testVictoryAndNextEncounterDoNotResetHealthOrInventory()throws {
        let session=try MeadowCampaignSession.new(layout:layout(combat:true)),start=session.engine.state.units["p1"]!.nodeID
        try session.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:11)))
        let target=session.engine.state.map.neighbors(start)[0]
        try session.beginTravel(to:target);try finishTravel(session)
        try session.interactCurrentNode()
        let before=session.engine.archive,_=try PartyEncounter(engine:session.engine)
        XCTAssertEqual(session.engine.archive,before)
        for monster in session.engine.state.units.values.filter({$0.kind == .monster && $0.active && $0.isAlive}) {
            try session.engine.apply(.setHealth(unit:monster.id,value:0,killer:"p1"))
        }
        XCTAssertNil(session.engine.state.battle);XCTAssertEqual(session.engine.state.units["p1"]!.health,11)
        let inventory=session.engine.state.units["p1"]!.inventory,coins=session.engine.state.units["p1"]!.coins
        let resumed=try MeadowCampaignSession(save:.decoded(session.snapshot.encoded()))
        XCTAssertEqual(resumed.engine.state.units["p1"]!.health,11)
        XCTAssertEqual(resumed.engine.state.units["p1"]!.inventory,inventory);XCTAssertEqual(resumed.engine.state.units["p1"]!.coins,coins)
        try resumed.refillExploration()
        let next=resumed.engine.state.map.nodes.first{ node in node.kind == .combat && resumed.engine.state.units.values.contains{$0.nodeID==node.id && $0.kind == .monster && $0.isAlive}}!.id
        try resumed.beginTravel(to:next);try finishTravel(resumed);try resumed.interactCurrentNode()
        XCTAssertNotNil(resumed.engine.state.battle);XCTAssertEqual(resumed.engine.state.units["p1"]!.health,11)
        XCTAssertEqual(resumed.engine.state.units["p1"]!.inventory,inventory)
    }

    func testEncounterEditingIsValidatedLoggedAndPersisted()throws {
        var config=MeadowMapConfiguration.suggested(total:4,seed:731)
        config.combat=3;config.boss=0;config.reward=0;config.empty=0;config.extraRoads=0
        let layout=try MeadowMapGenerator.generate(config)
        var stored=Data()
        let session=try MeadowCampaignSession.new(layout:layout,persist:{stored=$0})
        let node=try XCTUnwrap(session.engine.state.map.nodes.first{$0.kind == .combat})
        let receipt=try session.configureEncounter(node:node.id,templates:["meadowElderStag","meadowStag"])
        XCTAssertEqual(receipt.command,.configureNodeEncounter(node:node.id,monsterTemplates:["meadowElderStag","meadowStag"]))
        XCTAssertTrue(receipt.events.contains{$0.kind=="nodeEncounterConfigured"})
        let monsters=session.engine.state.units.values.filter{$0.kind == .monster && $0.nodeID==node.id}
        XCTAssertEqual(monsters.count,2)
        XCTAssertEqual(Set(monsters.map(\.templateID)),Set(["meadowElderStag","meadowStag"]))
        let restored=try MeadowCampaignSession(save:MeadowCampaignSave.decoded(stored))
        XCTAssertEqual(restored.engine.state.units.values.filter{$0.kind == .monster && $0.nodeID==node.id}.count,2)
        XCTAssertEqual(restored.engine.history.last?.events.first{$0.kind=="nodeEncounterConfigured"}?.detail,
                       "node=\(node.id);templates=meadowElderStag,meadowStag")
        let before=restored.engine.archive
        XCTAssertThrowsError(try restored.configureEncounter(node:node.id,templates:[]))
        XCTAssertThrowsError(try restored.configureEncounter(node:node.id,templates:["unknownMonster"]))
        XCTAssertThrowsError(try restored.configureEncounter(node:9999,templates:["meadowStag"]))
        XCTAssertEqual(restored.engine.archive,before)
    }

    func testClaimedRewardEditingRequiresExplicitResetAndPaysUpdatedValueOnce()throws {
        let session=try MeadowCampaignSession.new(layout:layout()),start=session.engine.state.units["p1"]!.nodeID,node=session.engine.state.map.neighbors(session.engine.state.units["p1"]!.nodeID)[0]
        try session.beginTravel(to:node);try finishTravel(session);try session.interactCurrentNode()
        let before=session.engine.state.units["p1"]!.coins,updated=NodeReward(coins:37,score:8,items:["smallPotion":2])
        try session.configureReward(node:node,reward:updated)
        XCTAssertTrue(session.engine.state.map.nodes.first{$0.id==node}!.rewardCompleted)
        XCTAssertEqual(session.engine.state.units["p1"]!.coins,before)
        XCTAssertThrowsError(try session.interactCurrentNode())
        try session.resetReward(node:node);XCTAssertEqual(session.engine.state.units["p1"]!.coins,before)
        try session.refillExploration();try session.beginTravel(to:start);try finishTravel(session)
        try session.refillExploration();try session.beginTravel(to:node);try finishTravel(session)
        XCTAssertEqual(session.engine.state.units["p1"]!.coins,before)
        try session.interactCurrentNode();XCTAssertEqual(session.engine.state.units["p1"]!.coins,before+37)
        XCTAssertThrowsError(try session.interactCurrentNode())
        let restored=try MeadowCampaignSession(save:.decoded(session.snapshot.encoded()))
        XCTAssertEqual(restored.engine.archive,session.engine.archive)
        XCTAssertTrue(restored.engine.state.map.nodes.first{$0.id==node}!.rewardCompleted)
    }
    func testNewCampaignCopiesSpareInventoryWithoutDuplicatingWornItems()throws {
        let original=try MeadowCampaignSession.new(layout:layout())
        var p1=original.engine.state.units["p1"]!
        p1.inventory=["huntingBow":2,"leatherArmor":1,"smallPotion":3]
        let session=try MeadowCampaignSession.new(layout:layout(),loadouts:["p1":p1])
        XCTAssertEqual(session.engine.state.units["p1"]!.inventory,p1.inventory)
        XCTAssertEqual(session.engine.state.units["p1"]!.equipment,p1.equipment)
        XCTAssertNil(session.engine.state.units["p1"]!.inventory[p1.equipment.weapon!])
        XCTAssertEqual(p1.inventory["huntingBow"],2)
        let restored=try MeadowCampaignSession(save:.decoded(session.snapshot.encoded()))
        XCTAssertEqual(restored.engine.archive,session.engine.archive)
    }
    func testCampaignInventorySaveFailureIsAtomicAndMembersConsumeOwnSupplies()throws {
        let original=try MeadowCampaignSession.new(layout:layout())
        var p1=original.engine.state.units["p1"]!;p1.inventory=["leatherArmor":1,"smallPotion":3]
        var fail=false,stored=Data()
        let session=try MeadowCampaignSession.new(layout:layout(),loadouts:["p1":p1],persist:{data in if fail{throw GameError("disk")};stored=data})
        try session.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:5,ap:2)))
        let before=session.engine.archive,old=stored
        let candidate=try session.candidateEquipment(actor:"p1",slot:.armor,item:"leatherArmor")
        XCTAssertEqual(candidate.health,5);XCTAssertEqual(candidate.ap,2);XCTAssertEqual(session.engine.archive,before)
        fail=true
        XCTAssertThrowsError(try session.equipInventory(actor:"p1",slot:.armor,item:"leatherArmor"))
        XCTAssertEqual(session.engine.archive,before);XCTAssertEqual(stored,old)
        fail=false;try session.equipInventory(actor:"p1",slot:.armor,item:"leatherArmor")
        XCTAssertNil(session.engine.state.units["p1"]!.inventory["leatherArmor"])
        XCTAssertEqual(session.engine.state.units["p1"]!.equipment.armor,"leatherArmor")
        XCTAssertEqual(session.engine.state.units["p1"]!.health,5);XCTAssertEqual(session.engine.state.units["p1"]!.ap,2)
        let p1Count=session.engine.state.units["p1"]!.inventory["smallPotion"],p2Before=session.engine.state.units["p2"]!
        let beforeUse=session.engine.archive,saved=stored
        fail=true;XCTAssertThrowsError(try session.useInventory(actor:"p2",item:"smallPotion",target:"p1"))
        XCTAssertEqual(session.engine.archive,beforeUse);XCTAssertEqual(stored,saved)
        fail=false;try session.useInventory(actor:"p2",item:"smallPotion",target:"p1")
        XCTAssertEqual(session.engine.state.units["p1"]!.inventory["smallPotion"],p1Count)
        XCTAssertEqual(session.engine.state.units["p2"]!.inventory["smallPotion"],(p2Before.inventory["smallPotion"] ?? 0)-1)
        XCTAssertEqual(session.engine.state.units["p2"]!.ap,p2Before.ap-1)
        XCTAssertGreaterThan(session.engine.state.units["p1"]!.health,5)
        let restored=try MeadowCampaignSession(save:.decoded(stored))
        XCTAssertEqual(restored.engine.archive,session.engine.archive)
    }
    func testCampaignInventoryBlockedDuringTravelAndBattle()throws {
        let session=try MeadowCampaignSession.new(layout:layout(combat:true))
        let start=session.engine.state.units["p1"]!.nodeID,target=session.engine.state.map.neighbors(start)[0]
        try session.beginTravel(to:target);let before=session.engine.archive
        XCTAssertFalse(session.canManageInventory)
        XCTAssertThrowsError(try session.candidateEquipment(actor:"p1",slot:.weapon,item:nil))
        XCTAssertThrowsError(try session.useInventory(actor:"p1",item:"shieldPotion",target:"p1"))
        XCTAssertEqual(session.engine.archive,before)
        try finishTravel(session);XCTAssertNil(session.engine.state.battle);try session.interactCurrentNode();XCTAssertNotNil(session.engine.state.battle)
        let battle=session.engine.archive
        XCTAssertThrowsError(try session.equipInventory(actor:"p1",slot:.weapon,item:nil))
        XCTAssertThrowsError(try session.useInventory(actor:"p1",item:"shieldPotion",target:"p1"))
        XCTAssertEqual(session.engine.archive,battle)
    }

    func finishTravel(_ session:MeadowCampaignSession)throws {
        for _ in 0..<30 where session.travel != nil {
            if !session.isMoving {try session.refillMovement(usingCoins:false);try session.setPaused(false)}
            try session.advanceTravel(distance:100000)
        }
        XCTAssertNil(session.travel)
    }
    func testMovementUsesAverageMaximumAPAndIgnoresCurrentAP()throws {
        let initial=try MeadowCampaignSession.new(layout:layout())
        var save=initial.snapshot
        save.archive.state.units["p1"]!.baseAttributes.maximumAP=10;save.archive.state.units["p2"]!.baseAttributes.maximumAP=6
        save.archive.state.units["p1"]!.ap=0;save.archive.state.units["p2"]!.ap=1
        save.movement=nil
        let session=try MeadowCampaignSession(save:save),start=session.engine.state.units["p1"]!.nodeID
        XCTAssertEqual(session.movementCapacity,400,accuracy:0.000001)
        try session.beginTravel(to:session.engine.state.map.neighbors(start)[0]);try session.advanceTravel(distance:37.5)
        XCTAssertEqual(session.movementRemaining,362.5,accuracy:0.000001)
        XCTAssertEqual(session.engine.state.units["p1"]!.ap,0);XCTAssertEqual(session.engine.state.units["p2"]!.ap,1)
        let restored=try MeadowCampaignSession(save:.decoded(session.snapshot.encoded()))
        XCTAssertEqual(restored.position(of:"p1"),session.position(of:"p1"));XCTAssertEqual(restored.movementRemaining,session.movementRemaining)
    }
    func testMovementExhaustionStopsMidRoadAndResumesWithoutTeleport()throws {
        let initial=try MeadowCampaignSession.new(layout:layout());var save=initial.snapshot;save.movement?.remaining=20
        save.archive.state.units["p1"]?.coins=0;save.archive.state.units["p2"]?.coins=0
        let session=try MeadowCampaignSession(save:save),start=session.engine.state.units["p1"]!.nodeID
        try session.beginTravel(to:session.engine.state.map.neighbors(start)[0]);try session.advanceTravel(distance:40)
        XCTAssertEqual(session.travel!.distance,20,accuracy:0.000001);XCTAssertEqual(session.movementRemaining,0)
        XCTAssertFalse(session.isMoving);XCTAssertEqual(session.engine.state.units["p1"]!.nodeID,start)
        let position=session.position(of:"p1"),before=session.snapshot
        XCTAssertThrowsError(try session.refillMovement(usingCoins:true));XCTAssertEqual(session.snapshot,before)
        try session.refillMovement(usingCoins:false);XCTAssertEqual(session.position(of:"p1"),position);XCTAssertFalse(session.isMoving)
        try session.setPaused(false);try finishTravel(session)
        XCTAssertNotEqual(session.engine.state.units["p1"]!.nodeID,start);XCTAssertFalse(session.engine.state.map.nodes.contains{$0.rewardCompleted})
    }
    func testMovementPurchaseUsesPartyCoinsAndFailedSaveRollsBackBarAndCoins()throws {
        let initial=try MeadowCampaignSession.new(layout:layout());var save=initial.snapshot
        save.movement?.remaining=initial.movementCapacity-225
        save.archive.state.units["p1"]!.coins=1;save.archive.state.units["p2"]!.coins=5
        var fail=false,stored=Data()
        let session=try MeadowCampaignSession(save:save,persist:{data in if fail{throw GameError("disk")};stored=data})
        try session.checkpoint();let before=session.snapshot,old=stored
        XCTAssertEqual(session.movementRefillCost,5)
        fail=true;XCTAssertThrowsError(try session.refillMovement(usingCoins:true));XCTAssertEqual(session.snapshot,before);XCTAssertEqual(stored,old)
        fail=false;try session.refillMovement(usingCoins:true)
        XCTAssertEqual(session.movementRemaining,session.movementCapacity)
        XCTAssertEqual(session.engine.state.units["p1"]!.coins,0);XCTAssertEqual(session.engine.state.units["p2"]!.coins,1)
        XCTAssertEqual(session.engine.state.units["p1"]!.ap,before.archive.state.units["p1"]!.ap)
        let restored=try MeadowCampaignSession(save:.decoded(stored));XCTAssertEqual(restored.snapshot,session.snapshot)
    }
    func testEveryExplicitBattleStartsPlayersAtOwnBaseAPWithoutRefillingMovement()throws {
        let session=try MeadowCampaignSession.new(layout:layout(combat:true)),start=session.engine.state.units["p1"]!.nodeID
        for id in session.playerIDs{try session.engine.apply(.editResources(unit:id,value:ResourcePatch(ap:0)))}
        try session.beginTravel(to:session.engine.state.map.neighbors(start)[0]);try finishTravel(session)
        XCTAssertNil(session.engine.state.battle);let remaining=session.movementRemaining
        try session.interactCurrentNode()
        for id in session.playerIDs{XCTAssertEqual(session.engine.state.units[id]!.ap,try GameRules.attributes(session.engine.state.units[id]!,catalog:session.engine.catalog).baseAP)}
        XCTAssertEqual(session.movementRemaining,remaining)
        for id in session.engine.state.units.values.filter({$0.kind == .monster && $0.active}).map(\.id){try session.engine.apply(.setHealth(unit:id,value:0,killer:"p1"))}
        for id in session.playerIDs{try session.engine.apply(.editResources(unit:id,value:ResourcePatch(ap:0)))}
        let next=session.engine.state.units.values.first{$0.kind == .monster && $0.isAlive}!.nodeID
        try session.refillMovement(usingCoins:false);try session.beginTravel(to:next);try finishTravel(session)
        XCTAssertNil(session.engine.state.battle);let before=session.movementRemaining
        try session.interactCurrentNode();XCTAssertEqual(session.movementRemaining,before)
        for id in session.playerIDs{XCTAssertEqual(session.engine.state.units[id]!.ap,try GameRules.attributes(session.engine.state.units[id]!,catalog:session.engine.catalog).baseAP)}
    }
    func testLegacyMidRoadSaveGetsIndependentMovementWithoutChangingArchive()throws {
        let session=try MeadowCampaignSession.new(layout:layout()),start=session.engine.state.units["p1"]!.nodeID
        try session.beginTravel(to:session.engine.state.map.neighbors(start)[0]);try session.advanceTravel(distance:17)
        var legacy=session.snapshot;legacy.movement=nil
        let restored=try MeadowCampaignSession(save:.decoded(legacy.encoded()))
        XCTAssertEqual(restored.position(of:"p1"),session.position(of:"p1"));XCTAssertEqual(restored.engine.archive,session.engine.archive)
        XCTAssertEqual(restored.movementRemaining,restored.movementCapacity);XCTAssertFalse(restored.isMoving)
        var invalid=restored.snapshot;invalid.movement?.remaining = .nan;XCTAssertThrowsError(try invalid.encoded())
    }

    func roadPoint(_ s:MeadowCampaignSession,_ fraction:Double)->MeadowWorldPoint {
        let start=s.engine.state.units["p1"]!.nodeID,end=s.engine.state.map.neighbors(start)[0]
        let points=MeadowCampaignSave.road(s.snapshot.layout,from:start,to:end)!
        var distance=MeadowCampaignSave.length(points)*fraction
        for(a,b) in zip(points,points.dropFirst()){let length=hypot(b.x-a.x,b.y-a.y);if distance<=length{return .init(a.x+(b.x-a.x)*distance/length,a.y+(b.y-a.y)*distance/length)};distance-=length}
        return points.last!
    }
    func testArbitraryRoadPointStopsExactlyWithoutNodeEvents()throws {
        let session=try MeadowCampaignSession.new(layout:layout()),point=roadPoint(try MeadowCampaignSession.new(layout:layout()),0.1)
        let ap=session.engine.state.units["p1"]!.ap,before=session.movementRemaining
        let plan=try session.beginTravel(toRoadPoint:point);try session.advanceTravel(distance:100000)
        XCTAssertFalse(session.isMoving);XCTAssertFalse(session.hasPendingTravel);XCTAssertNotNil(session.travel)
        XCTAssertEqual(session.position(of:"p1").x,point.x,accuracy:0.000001);XCTAssertEqual(session.position(of:"p1").y,point.y,accuracy:0.000001)
        XCTAssertEqual(session.engine.state.units["p1"]!.ap,ap);XCTAssertFalse(session.engine.state.map.nodes.contains{$0.rewardCompleted})
        XCTAssertEqual(before-session.movementRemaining,session.travel!.distance,accuracy:0.000001);XCTAssertGreaterThan(plan.cost,0)
        let restored=try MeadowCampaignSession(save:.decoded(session.snapshot.encoded()));XCTAssertEqual(restored.position(of:"p1"),session.position(of:"p1"))
    }
    func testImmediateRoadRetargetCanReverseWithoutTeleportOrAPCost()throws {
        let session=try MeadowCampaignSession.new(layout:layout()),point=roadPoint(try MeadowCampaignSession.new(layout:layout()),0.2)
        try session.beginTravel(toRoadPoint:point);try session.advanceTravel(distance:15)
        let before=session.position(of:"p1"),start=session.engine.state.units["p1"]!.nodeID
        try session.beginTravel(to:start);XCTAssertEqual(session.position(of:"p1").x,before.x,accuracy:0.000001);XCTAssertEqual(session.position(of:"p1").y,before.y,accuracy:0.000001)
        try session.advanceTravel(distance:100000);XCTAssertNil(session.travel)
        XCTAssertEqual(session.engine.state.units["p1"]!.nodeID,start)
        XCTAssertEqual(session.snapshot.movement!.totalDistance,30,accuracy:0.000001)
    }
    func testMovementScaleMigrationPreservesFractionAndPartyMean()throws {
        let initial=try MeadowCampaignSession.new(layout:layout());var old=initial.snapshot
        old.movement?.scale=nil;old.movement?.remaining=600
        let session=try MeadowCampaignSession(save:.decoded(old.encoded()))
        XCTAssertEqual(session.movementCapacity,400);XCTAssertEqual(session.movementRemaining,200)
        XCTAssertEqual(session.snapshot.movement?.scale,50)
    }
    func testNewCampaignClassAndSelectedMemberPersist()throws {
        for role in ["adventurer","spellblade","dragonKnight"]{
            let s=try MeadowCampaignSession.new(layout:layout(),playerClassID:role)
            XCTAssertEqual(s.engine.state.units["p1"]!.templateID,role);XCTAssertEqual(s.engine.state.units["p2"]!.templateID,"ranger")
            try s.selectPlayer("p2");let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
            XCTAssertEqual(restored.selectedPlayerID,"p2");XCTAssertThrowsError(try s.selectPlayer("unknown"))
        }
    }
    func testBattleAPConsumptionRemainsPerActor()throws {
        let session=try MeadowCampaignSession.new(layout:layout(combat:true)),start=session.engine.state.units["p1"]!.nodeID
        try session.beginTravel(to:session.engine.state.map.neighbors(start)[0]);try finishTravel(session);try session.interactCurrentNode()
        for _ in 0..<8 where session.engine.state.units[session.engine.state.battle?.current ?? ""]?.kind == .monster{try session.engine.apply(.endTurn(actor:session.engine.state.battle!.current!,timedOut:false))}
        let actor=try XCTUnwrap(session.engine.state.battle?.current);XCTAssertEqual(session.engine.state.units[actor]?.kind,.player)
        let other=actor=="p1" ? "p2":"p1",before=session.engine.state.units[other]!.ap,own=session.engine.state.units[actor]!.ap
        let enemy=try XCTUnwrap(session.engine.state.units.values.first{$0.kind == .monster && $0.active && $0.isAlive})
        try session.engine.apply(.attack(actor:actor,target:enemy.id))
        XCTAssertEqual(session.engine.state.units[actor]!.ap,own-1);XCTAssertEqual(session.engine.state.units[other]!.ap,before)
    }

    func clearEnemies(_ session:MeadowCampaignSession)throws {
        for id in session.engine.state.units.values.filter({$0.kind == .monster && $0.isAlive}).map(\.id){try session.engine.apply(.setHealth(unit:id,value:0,killer:"p1"))}
    }
    func testCompletionRequiresAllEncountersAndReturnToCamp()throws {
        let s=try MeadowCampaignSession.new(layout:layout(combat:true)),start=s.engine.state.units["p1"]!.nodeID
        XCTAssertFalse(s.canComplete);XCTAssertThrowsError(try s.completeCampaign())
        let target=s.engine.state.map.neighbors(start)[0];try s.beginTravel(to:target);try finishTravel(s)
        try clearEnemies(s);XCTAssertTrue(s.completionGoalMet);XCTAssertFalse(s.canComplete)
        XCTAssertThrowsError(try s.completeCampaign());XCTAssertNil(s.completion)
        try s.refillMovement(usingCoins:false);try s.beginTravel(to:start);try finishTravel(s)
        XCTAssertTrue(s.canComplete);let result=try s.completeCampaign()
        XCTAssertEqual(result.outcome,"victory");XCTAssertEqual(result.clearedEncounters,result.totalEncounters)
    }
    func testNoEnemyMapNeedsExplorationAndRewardsRemainOptional()throws {
        let s=try MeadowCampaignSession.new(layout:layout()),start=s.engine.state.units["p1"]!.nodeID
        let initial=s.engine.state.players.map(\.coins)
        XCTAssertFalse(s.canComplete)
        for node in s.engine.state.map.nodes where node.id != start {
            try s.refillMovement(usingCoins:false);try s.beginTravel(to:node.id);try finishTravel(s)
        }
        XCTAssertTrue(s.completionGoalMet);XCTAssertFalse(s.canComplete)
        try s.refillMovement(usingCoins:false);try s.beginTravel(to:start);try finishTravel(s)
        let result=try s.completeCampaign();XCTAssertEqual(result.collectedRewards,0);XCTAssertEqual(result.exploredNodes,result.totalNodes)
        XCTAssertEqual(result.players.map(\.coins),initial)
    }
    func testCompletionIsIdempotentAndClosesResourceOperations()throws {
        let s=try MeadowCampaignSession.new(layout:layout(combat:true));try clearEnemies(s)
        let archive=s.engine.archive,result=try s.completeCampaign(),saved=s.snapshot
        XCTAssertEqual(s.engine.archive,archive);XCTAssertEqual(try s.completeCampaign(),result);XCTAssertEqual(s.snapshot,saved)
        let target=s.engine.state.map.neighbors(s.engine.state.units["p1"]!.nodeID)[0]
        XCTAssertThrowsError(try s.beginTravel(to:target));XCTAssertThrowsError(try s.refillMovement(usingCoins:false))
        XCTAssertThrowsError(try s.configureEncounter(node:target,templates:["meadowStag"]))
        XCTAssertThrowsError(try s.equipInventory(actor:"p1",slot:.weapon,item:nil))
        XCTAssertThrowsError(try s.engine.apply(.editResources(unit:"p1",value:ResourcePatch(coins:999))))
        XCTAssertEqual(s.engine.archive,archive);XCTAssertEqual(s.completion,result)
        try s.selectPlayer("p2");try s.checkpoint()
        XCTAssertEqual(s.completion,result)
    }
    func testCompletionSaveFailureLeavesSessionOpenAndCanRetry()throws {
        var fail=false,stored=Data()
        let s=try MeadowCampaignSession.new(layout:layout(combat:true),persist:{data in if fail{throw GameError("disk")};stored=data})
        try clearEnemies(s);let before=s.snapshot,old=stored
        fail=true;XCTAssertThrowsError(try s.completeCampaign());XCTAssertEqual(s.snapshot,before);XCTAssertEqual(stored,old);XCTAssertTrue(s.canComplete)
        fail=false;let result=try s.completeCampaign(),bytes=stored
        XCTAssertEqual(try s.completeCampaign(),result);XCTAssertEqual(stored,bytes)
        let restored=try MeadowCampaignSession(save:.decoded(stored));XCTAssertEqual(restored.completion,result);XCTAssertTrue(restored.isCompleted)
        XCTAssertThrowsError(try restored.refillMovement(usingCoins:false))
    }
    func testCompletedHistoryIsPreservedBeforeNewCampaignAndDeduplicated()throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let store=MeadowCampaignStore(url:folder.appendingPathComponent("campaign-v1.json"))
        let s=try MeadowCampaignSession.new(layout:layout(combat:true),persist:store.write);try clearEnemies(s);let result=try s.completeCampaign()
        let file=try XCTUnwrap(store.preserveCompletedCampaign());XCTAssertEqual(try store.preserveCompletedCampaign(),file)
        XCTAssertEqual(try store.completedCampaigns().count,1)
        _=try MeadowCampaignSession.new(layout:layout(),persist:store.write)
        XCTAssertEqual(try store.completedCampaigns().first?.completion,result)
        XCTAssertNil(try store.read()?.completion)
        let archived=try MeadowCampaignSave.decoded(Data(contentsOf:file));var corrupted=archived
        let other=try MeadowCampaignSession.new(layout:layout(combat:true));try clearEnemies(other);corrupted.completion=try other.completeCampaign()
        XCTAssertThrowsError(try corrupted.encoded())
    }
    func testDefeatCompletionIsAtomicAndDoesNotPayAdditionalRewards()throws {
        var fail=false,stored=Data()
        let s=try MeadowCampaignSession.new(layout:layout(combat:true),persist:{data in if fail{throw GameError("disk")};stored=data})
        let start=s.engine.state.units["p1"]!.nodeID;try s.beginTravel(to:s.engine.state.map.neighbors(start)[0]);try finishTravel(s);try s.interactCurrentNode()
        for id in s.playerIDs{try s.engine.apply(.setHealth(unit:id,value:0,killer:nil))}
        XCTAssertTrue(s.canCompleteDefeat);let before=s.engine.archive,old=stored
        fail=true;XCTAssertThrowsError(try s.completeCampaign());XCTAssertEqual(s.engine.archive,before);XCTAssertEqual(stored,old)
        fail=false;let result=try s.completeCampaign()
        XCTAssertEqual(result.outcome,"defeat");XCTAssertNil(s.engine.state.battle);XCTAssertTrue(result.players.allSatisfy{!$0.isAlive})
        XCTAssertEqual(result.players.map(\.coins),before.state.players.map(\.coins));XCTAssertEqual(try s.completeCampaign(),result)
        XCTAssertEqual(try MeadowCampaignSave.decoded(stored).completion,result)
    }

    func testThreeDistinctMonstersResumeAndTakeRealAITurns()throws {
        var s=try MeadowCampaignSession.new(layout:layout(combat:true));let start=s.engine.state.units["p1"]!.nodeID,target=s.engine.state.map.neighbors(start)[0]
        try s.configureEncounter(node:target,templates:["slime","wolf","goblinArcher"])
        try s.beginTravel(to:target);try finishTravel(s);try s.interactCurrentNode()
        s=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()));let encounter=try PartyEncounter(engine:s.engine)
        XCTAssertEqual(encounter.monsterIDs.count,3);XCTAssertEqual(Set(encounter.monsterIDs.map(PartyVisual.slot)).count,3)
        var seen=Set<String>()
        for _ in 0..<40 {
            if encounter.round>=3{break}
            let actor=try XCTUnwrap(encounter.current)
            if s.engine.state.units[actor]?.kind == .player {
                let preview=try XCTUnwrap(encounter.prepare(.attack,target:encounter.monsterIDs[0]));XCTAssertEqual(preview.targetTemplateID,s.engine.state.units[preview.target]?.templateID);encounter.cancel()
                try s.engine.apply(.endTurn(actor:actor,timedOut:false))
            }
            else {
                for id in s.playerIDs {let hp=try GameRules.attributes(s.engine.state.units[id]!,catalog:s.engine.catalog).maximumHealth;try s.engine.apply(.editResources(unit:id,value:ResourcePatch(health:hp,shield:8)))}
                let before=s.engine.archive,intent=try XCTUnwrap(encounter.prepareMonsterStep())
                XCTAssertEqual(s.engine.archive,before);seen.insert(intent.actor)
                XCTAssertEqual(intent.monsterTemplateID,before.state.units[actor]?.templateID)
                XCTAssertEqual(intent.ranged,intent.monsterTemplateID=="goblinArcher")
                let dice=BattleDice.channels(intent.action,actor:before.state.units[actor]!,target:before.state.units[intent.target]!,catalog:s.engine.catalog,receipt:encounter.confirmedReceipt)
                for age in stride(from:0.0,through:1.1,by:0.02){let p=PartyVisual.diceAnchor(actor:actor,intent:intent,age:age,diceCount:dice.count,monsterTemplateID:intent.monsterTemplateID);XCTAssertTrue(p.x.isFinite && p.y.isFinite)}
                _=try encounter.commit(intent.id);XCTAssertNil(try encounter.commit(intent.id))
            }
        }
        XCTAssertEqual(seen,Set(encounter.monsterIDs));XCTAssertGreaterThanOrEqual(encounter.round,3)
    }
    func testRealMonsterSkillPresentationAliasesAndDelayedFeedback()throws {
        for template in ["stoneGuardian","caveTroll","ruinDragon"] {
            var config=MeadowMapConfiguration.suggested(total:4,seed:317)
            let boss=try GameCatalog.initial().monster(template).boss;config.combat=boss ? 0:3;config.boss=boss ? 3:0;config.reward=0;config.empty=0
            let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(config)),start=s.engine.state.units["p1"]!.nodeID,target=s.engine.state.map.neighbors(start)[0]
            try s.configureEncounter(node:target,templates:[template]);try s.beginTravel(to:target);try finishTravel(s);try s.interactCurrentNode()
            let e=try PartyEncounter(engine:s.engine),id=e.monsterIDs[0]
            if template=="caveTroll"{try s.engine.apply(.editResources(unit:id,value:ResourcePatch(health:12)))}else{try s.engine.apply(.editResources(unit:id,value:ResourcePatch(shield:0)))}
            for _ in 0..<8 where s.engine.state.units[e.current ?? ""]?.kind == .player {try s.engine.apply(.endTurn(actor:e.current!,timedOut:false))}
            let before=s.engine.archive,intent=try XCTUnwrap(e.prepareMonsterStep())
            XCTAssertEqual(s.engine.archive,before)
            XCTAssertEqual(intent.action,template=="stoneGuardian" ? .simpleGuard:template=="caveTroll" ? .regeneration:.dragonScaleWard)
            XCTAssertGreaterThan(intent.visualDuration,1.1)
            let source=template=="stoneGuardian" ? "stoneSkin":template=="caveTroll" ? "regeneration":"monsterDragonScale"
            XCTAssertEqual(intent.sourceSkillID,source)
            let channels=BattleDice.channels(intent.action,actor:before.state.units[id]!,target:before.state.units[id]!,catalog:s.engine.catalog,receipt:e.confirmedReceipt,sourceSkillID:intent.sourceSkillID)
            XCTAssertEqual(channels.first?.value,try s.engine.catalog.skill(source).effects.first?.amount)
            _=try e.commit(intent.id)
            if template=="ruinDragon" {
                let flame=try XCTUnwrap(e.prepareMonsterStep());XCTAssertEqual(flame.action,.dragonFlame);XCTAssertEqual(flame.targets.count,2)
                XCTAssertEqual(flame.sourceSkillID,"monsterDragonFlame")
                let dice=BattleDice.channels(flame.action,actor:s.engine.state.units[id]!,target:s.engine.state.units[flame.target]!,catalog:s.engine.catalog,receipt:e.confirmedReceipt,sourceSkillID:flame.sourceSkillID)
                XCTAssertEqual(dice.first?.sides,20);XCTAssertFalse(dice.contains{$0.color=="blue"})
                XCTAssertEqual(flame.visualDuration,2.75);XCTAssertEqual(PartyVisual.travel(flame,age:0.46).x,0)
            }
        }
    }

}
