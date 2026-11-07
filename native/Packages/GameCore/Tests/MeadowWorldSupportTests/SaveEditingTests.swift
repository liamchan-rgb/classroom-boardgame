import XCTest
import ClassroomGameCore
import MeadowBattleSupport
@testable import MeadowWorldSupport

final class SaveEditingTests:XCTestCase {
    private func make(persist:((Data)throws->Void)?=nil)throws->MeadowCampaignSession {
        try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4,seed:31827)),persist:persist)
    }
    private func move(_ s:MeadowCampaignSession,to:Int)throws {
        try s.beginTravel(to:to)
        while s.travel != nil {
            if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)}
            try s.advanceTravel(distance:100000)
        }
    }
    func testBackgroundCheckpointWritesCursorPauseCameraAndSelectionExactlyOnce()throws {
        var bytes=Data(),writes=0
        let s=try make(persist:{bytes=$0;writes+=1}),start=s.engine.state.players[0].nodeID
        try s.selectPlayer("p2");try s.beginTravel(to:s.engine.state.map.neighbors(start)[0],actor:"p2");try s.advanceTravel(distance:17.25)
        let position=s.position(of:"p2"),archive=s.engine.archive,remaining=s.movementRemaining
        writes=0;let camera=MeadowCampaignCamera(x:350,y:480,zoom:1.75)
        try s.suspendAndCheckpoint(camera:camera)
        XCTAssertEqual(writes,1);XCTAssertFalse(s.isMoving)
        let restored=try MeadowCampaignSession(save:.decoded(bytes))
        XCTAssertEqual(restored.snapshot.camera,camera);XCTAssertEqual(restored.position(of:"p2"),position)
        XCTAssertEqual(restored.selectedPlayerID,"p2");XCTAssertEqual(restored.movementRemaining,remaining)
        XCTAssertEqual(restored.engine.archive,archive)
    }
    func testFailedBackgroundSaveKeepsDurableBytesAndLiveResourcesThenRetriesWithoutDuplicateArrival()throws {
        var bytes=Data(),fail=false
        let s=try make(persist:{if fail{throw GameError("disk")};bytes=$0}),start=s.engine.state.players[0].nodeID,target=s.engine.state.map.neighbors(start)[0]
        try s.beginTravel(to:target);try s.advanceTravel(distance:13)
        let old=bytes,before=s.snapshot,position=s.position(of:"p1"),camera=MeadowCampaignCamera(x:400,y:500,zoom:2)
        fail=true;XCTAssertThrowsError(try s.suspendAndCheckpoint(camera:camera))
        XCTAssertEqual(bytes,old);XCTAssertFalse(s.isMoving)
        XCTAssertEqual(s.position(of:"p1"),position);XCTAssertEqual(s.snapshot.archive,before.archive)
        XCTAssertEqual(s.snapshot.movement,before.movement);XCTAssertEqual(s.snapshot.camera,before.camera)
        fail=false;try s.suspendAndCheckpoint(camera:camera)
        let restored=try MeadowCampaignSession(save:.decoded(bytes));XCTAssertEqual(restored.position(of:"p1"),position)
        try restored.setPaused(false);try moveFromPending(restored)
        XCTAssertEqual(restored.engine.history.flatMap(\.events).filter{$0.kind=="campaignArrival"}.count,1)
    }
    private func moveFromPending(_ s:MeadowCampaignSession)throws {
        while s.travel != nil {
            if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)}
            try s.advanceTravel(distance:100000)
        }
    }
    func testInvalidCameraIsRejectedWithOrWithoutPersistenceWithoutChangingSnapshot()throws {
        for persisted in [false,true] {
            let s=try make(persist:persisted ? {_ in }:nil),before=s.snapshot
            for camera in [MeadowCampaignCamera(x:.nan,y:0),.init(x:0,y:.infinity),.init(x:0,y:0,zoom:0.9),.init(x:0,y:0,zoom:3.1)] {
                XCTAssertThrowsError(try s.checkpoint(camera:camera));XCTAssertEqual(s.snapshot,before)
            }
        }
    }
    func testEditorDraftOffersAllEightRegisteredSpeciesRetainsSlotsAndDoesNotWriteOnCancel()throws {
        let s=try make(),node=s.engine.state.map.nodes.first{$0.kind == .combat}!,before=s.snapshot
        var draft=try MeadowEncounterEditDraft(node:node,templates:["slime","wolf","goblinArcher"],catalog:s.engine.catalog)
        XCTAssertEqual(draft.choices.count,8)
        try draft.setTemplate("stoneGuardian",at:1);try draft.setCount(1);try draft.setCount(3)
        XCTAssertEqual(draft.templates,["slime","stoneGuardian","goblinArcher"])
        let unchanged=draft;XCTAssertThrowsError(try draft.setTemplate("unknown",at:0));XCTAssertEqual(draft,unchanged)
        XCTAssertThrowsError(try draft.setCount(4));XCTAssertEqual(s.snapshot,before)
        let boss=s.engine.state.map.nodes.first{$0.kind == .boss}!
        XCTAssertEqual(try MeadowEncounterEditDraft(node:boss,templates:["caveTroll"],catalog:s.engine.catalog).maximumCount,1)
        let legacy=try MeadowEncounterEditDraft(node:boss,templates:["caveTroll","wolf","slime"],catalog:s.engine.catalog)
        XCTAssertEqual(legacy.templates,["caveTroll","wolf","slime"])
    }
    func testMixedEncounterEditFailureRollsBackAndRetryPersistsExactNewRosterOnly()throws {
        var bytes=Data(),fail=false
        let s=try make(persist:{if fail{throw GameError("disk")};bytes=$0}),node=s.engine.state.map.nodes.first{$0.kind == .combat}!
        let before=s.snapshot,old=bytes
        fail=true;XCTAssertThrowsError(try s.configureEncounter(node:node.id,templates:["wolf","goblinArcher","stoneGuardian"]))
        XCTAssertEqual(s.snapshot,before);XCTAssertEqual(bytes,old)
        fail=false;try s.configureEncounter(node:node.id,templates:["wolf","goblinArcher","stoneGuardian"])
        let restored=try MeadowCampaignSession(save:.decoded(bytes)),preview=try XCTUnwrap(restored.encounterPreview(node:node.id))
        XCTAssertEqual(preview.monsters.map(\.templateID),["wolf","goblinArcher","stoneGuardian"])
        XCTAssertEqual(restored.engine.state.players,before.archive.state.players);XCTAssertEqual(restored.engine.state.random,before.archive.state.random)
        XCTAssertEqual(restored.engine.history.count,before.archive.history.count+1)
    }
    func testRewardEditAndExplicitResetFailAtomicallyAndNeverPayTwice()throws {
        var bytes=Data(),fail=false
        let s=try make(persist:{if fail{throw GameError("disk")};bytes=$0}),target=s.engine.state.map.nodes.first{$0.kind == .reward}!.id
        try move(s,to:target);try s.interactCurrentNode()
        let before=s.snapshot,old=bytes
        fail=true;XCTAssertThrowsError(try s.configureReward(node:target,reward:.init(coins:99,items:["largePotion":3])))
        XCTAssertThrowsError(try s.resetReward(node:target));XCTAssertEqual(s.snapshot,before);XCTAssertEqual(bytes,old)
        fail=false;try s.configureReward(node:target,reward:.init(coins:99,items:["largePotion":3]))
        XCTAssertThrowsError(try s.interactCurrentNode());try s.resetReward(node:target)
        let coins=s.partyCoins;try s.interactCurrentNode();XCTAssertEqual(s.partyCoins,coins+198)
        XCTAssertThrowsError(try s.interactCurrentNode());XCTAssertEqual(try MeadowCampaignSession(save:.decoded(bytes)).engine.archive,s.engine.archive)
    }
    func testCorruptHistoryAndCurrentDoNotHideHealthyHistoryOrRewriteFiles()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=MeadowCampaignStore(url:root.appendingPathComponent("campaign.json")),s=try make()
        for id in s.playerIDs{try s.engine.apply(.setHealth(unit:id,value:0,killer:nil))}
        try s.completeCampaign();try store.write(s.snapshot.encoded());let archived=try XCTUnwrap(store.preserveCompletedCampaign())
        let healthy=try Data(contentsOf:archived),bad=Data("broken".utf8),badURL=archived.deletingLastPathComponent().appendingPathComponent("broken.json")
        try bad.write(to:badURL);try bad.write(to:store.url)
        let history=try store.completedHistory()
        XCTAssertEqual(history.saves.count,1);XCTAssertEqual(history.issues.count,2);XCTAssertTrue(history.notice.contains("2"))
        XCTAssertEqual(try Data(contentsOf:archived),healthy);XCTAssertEqual(try Data(contentsOf:badURL),bad);XCTAssertEqual(try Data(contentsOf:store.url),bad)
        XCTAssertThrowsError(try store.read());XCTAssertThrowsError(try store.preserveCompletedCampaign())
    }
    func testBattleCheckpointDoesNotCommitPendingDiceAndResumeRecreatesSameReceiptOnce()throws {
        var bytes=Data();let s=try make(persist:{bytes=$0}),target=s.engine.state.map.nodes.first{$0.kind == .combat}!.id
        try move(s,to:target);try s.interactCurrentNode();let model=try PartyEncounter(engine:s.engine)
        for _ in 0..<6 where model.current.map({s.engine.state.units[$0]?.kind == .monster})==true {
            let intent=try XCTUnwrap(model.prepareMonsterStep());try model.commit(intent.id)
        }
        let monster=try XCTUnwrap(model.monsterIDs.first),before=s.engine.archive
        _=try XCTUnwrap(model.prepare(.attack,target:monster));let staged=try XCTUnwrap(model.confirmedReceipt)
        try s.suspendAndCheckpoint(camera:.init(x:300,y:400,zoom:1.5));XCTAssertEqual(s.engine.archive,before)
        let restored=try MeadowCampaignSession(save:.decoded(bytes)),next=try PartyEncounter(engine:restored.engine)
        let intent=try XCTUnwrap(next.prepare(.attack,target:monster))
        XCTAssertEqual(next.confirmedReceipt?.dice,staged.dice);XCTAssertEqual(next.confirmedReceipt?.after,staged.after)
        XCTAssertEqual(try next.commit(intent.id)?.after,staged.after);XCTAssertNil(try next.commit(intent.id))
    }
}
