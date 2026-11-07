import XCTest
import ClassroomGameCore
import MeadowBattleSupport
@testable import MeadowWorldSupport

final class JourneyReadoutTests:XCTestCase {
    func testActualActorSupportTargetAndIndependentResourcesAreReadOnly()throws {
        let b=try PartyEncounter(seed:31827),before=b.engine.archive
        let r=b.actionReadout(.support,ally:"p2",enemy:"m1")
        XCTAssertTrue(r.actor.contains("P2"));XCTAssertTrue(r.target.contains("P1"))
        XCTAssertTrue(r.resources.contains("剩余"));XCTAssertTrue(r.allowed)
        XCTAssertTrue(b.partyResourceSummary.contains("个人行动"));XCTAssertEqual(b.engine.archive,before)
    }
    func testItemShortageExplainsActualPersonalInventory()throws {
        let b=try PartyEncounter(seed:31827)
        var state=b.state;state.units["p2"]!.ap=0;state.units["p2"]!.inventory.removeValue(forKey:"smallPotion")
        let current=try PartyEncounter(engine:GameEngine(catalog:b.engine.catalog,state:state))
        let before=current.engine.archive,r=current.actionReadout(.smallPotion,ally:"p1",enemy:"m1")
        XCTAssertFalse(r.allowed);XCTAssertTrue(r.resources.contains("个人行动 0"))
        XCTAssertTrue(r.resources.contains("个人库存"));XCTAssertFalse(r.availability.isEmpty)
        XCTAssertEqual(current.engine.archive,before)
    }
    func testGroupSkillsDescribeGroupInsteadOfClickedSingleUnit()throws {
        let b=try PartyEncounter(seed:31827)
        XCTAssertEqual(b.actionReadout(.rally,ally:"p1",enemy:"m1").target,"同地点存活队员")
        XCTAssertEqual(b.actionReadout(.dragonFlame,ally:"p1",enemy:"m1").target,"目标地点敌人")
    }
    func testClosingExplanationPreservesOldSaveAndResourcesOnResume()throws {
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4,seed:0)))
        let before=s.snapshot,text=s.closingReadout
        XCTAssertTrue(text.contains("补给"));XCTAssertTrue(text.contains("不额外发奖"));XCTAssertEqual(s.snapshot,before)
        let resumed=try MeadowCampaignSession(save:.decoded(before.encoded()))
        XCTAssertEqual(resumed.closingReadout,text);XCTAssertEqual(resumed.snapshot,before)
    }
    func testGoalReachedAwayFromCampExplainsCoinShortageAndManualRefill()throws {
        var config=MeadowMapConfiguration.suggested(total:4,seed:317)
        config.combat=3;config.boss=0;config.reward=0;config.empty=0;config.extraRoads=0
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(config))
        let start=s.engine.state.units["p1"]!.nodeID
        try s.beginTravel(to:s.engine.state.map.neighbors(start)[0])
        while s.travel != nil {
            if !s.isMoving {try s.refillMovement(usingCoins:false);try s.setPaused(false)}
            try s.advanceTravel(distance:100000)
        }
        // Goal-state fixture only; the full audit retains real battle outcomes.
        for id in s.engine.state.units.values.filter({$0.kind == .monster && $0.isAlive}).map(\.id){try s.engine.apply(.setHealth(unit:id,value:0,killer:"p1"))}
        var save=s.snapshot;save.movement?.remaining=0
        for id in ["p1","p2"]{save.archive.state.units[id]!.coins=0}
        let restored=try MeadowCampaignSession(save:save),before=restored.snapshot
        XCTAssertTrue(restored.closingReadout.contains("金币缺口"));XCTAssertTrue(restored.closingReadout.contains("手动补满"))
        XCTAssertFalse(restored.canComplete);XCTAssertEqual(restored.snapshot,before)
        var survivor=save;survivor.archive.state.units["p1"]!.health=0;survivor.selectedPlayerID="p1"
        let onlyP2=try MeadowCampaignSession(save:survivor),frozen=onlyP2.snapshot
        XCTAssertTrue(onlyP2.closingReadout.contains("金币缺口"));XCTAssertTrue(onlyP2.closingReadout.contains("手动补满"))
        XCTAssertEqual(onlyP2.snapshot,frozen)
    }
    func testPausedRoadExplanationSurvivesCheckpointWithoutGrantingAnything()throws {
        let s=try MeadowCampaignSession.new(layout:MeadowMapGenerator.generate(.suggested(total:4,seed:0)))
        let start=s.engine.state.units["p1"]!.nodeID
        try s.beginTravel(to:s.engine.state.map.neighbors(start)[0]);try s.advanceTravel(distance:10);try s.setPaused(true)
        let before=s.snapshot,resumed=try MeadowCampaignSession(save:.decoded(before.encoded()))
        XCTAssertTrue(resumed.closingReadout.contains("暂停恢复"));XCTAssertEqual(resumed.closingReadout,s.closingReadout)
        XCTAssertEqual(resumed.snapshot,before)
    }
}
