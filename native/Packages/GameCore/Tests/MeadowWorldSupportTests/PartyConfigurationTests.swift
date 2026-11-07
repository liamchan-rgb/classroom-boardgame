import XCTest
import ClassroomGameCore
import MeadowBattleSupport
import MeadowCampaignAuditSupport
@testable import MeadowWorldSupport

final class PartyConfigurationTests:XCTestCase {
    private func layout()throws->GeneratedMeadowMap {try MeadowMapGenerator.generate(.suggested(total:4,seed:31827))}
    private func battle(_ p1:String,_ p2:String,current:String)throws->MeadowCampaignSession {
        let s=try MeadowCampaignSession.new(layout:layout(),playerClassID:p1,companionClassID:p2)
        let node=s.engine.state.map.nodes.first{$0.kind == .combat}!.id
        try s.beginTravel(to:node)
        while s.travel != nil {
            if !s.isMoving{try s.refillMovement(usingCoins:false);try s.setPaused(false)}
            try s.advanceTravel(distance:100000)
        }
        try s.interactCurrentNode()
        // Controlled turn fixture; full journeys below retain actual initiative.
        var save=s.snapshot;save.archive.state.battle?.current=current
        save.archive.state.battle?.acted=[]
        return try MeadowCampaignSession(save:save)
    }
    func testAllSixteenPairsUseSelectedStatsSkillsAndIndependentOpeningAP()throws {
        let map=try layout(),catalog=try MeadowCampaignSession.catalog()
        let baseline=try MeadowCampaignSession.new(layout:map).snapshot
        for p1 in MeadowPartyConfiguration.classIDs {for p2 in MeadowPartyConfiguration.classIDs {
            let s=try MeadowCampaignSession.new(layout:map,playerClassID:p1,companionClassID:p2)
            XCTAssertEqual(s.partyConfiguration,.init(playerClassID:p1,companionClassID:p2))
            XCTAssertEqual(s.snapshot.layout,baseline.layout)
            XCTAssertEqual(s.engine.state.map,baseline.archive.state.map)
            XCTAssertEqual(s.engine.state.units.filter{$0.value.kind == .monster},baseline.archive.state.units.filter{$0.value.kind == .monster})
            for (id,role) in [("p1",p1),("p2",p2)] {
                let u=s.engine.state.units[id]!,definition=try catalog.playerClass(role)
                XCTAssertEqual(u.baseAttributes,definition.attributes)
                XCTAssertEqual(u.templateID,role);XCTAssertEqual(u.health,definition.attributes.maximumHealth)
                XCTAssertEqual(u.ap,3);XCTAssertTrue(u.name.contains(definition.name))
                XCTAssertEqual(try GameRules.skills(u,catalog:catalog),definition.skills)
                let before=s.snapshot,summary=try MeadowPartyConfiguration.summary(for:role,catalog:catalog)
                for skill in definition.skills{XCTAssertTrue(summary.contains(try catalog.skill(skill).name))}
                XCTAssertEqual(s.snapshot,before)
            }
            XCTAssertEqual(s.movementCapacity,400);XCTAssertEqual(s.movementRemaining,400)
        }}
    }
    func testDefaultsAndInvalidEitherClassNeverPersist()throws {
        XCTAssertEqual(try MeadowCampaignSession.new(layout:layout()).partyConfiguration,MeadowPartyConfiguration())
        var writes=0
        for (p1,p2) in [("bad","ranger"),("spellblade","bad"),("wolf","ranger")] {
            XCTAssertThrowsError(try MeadowCampaignSession.new(layout:layout(),playerClassID:p1,companionClassID:p2,persist:{_ in writes+=1}))
        }
        XCTAssertEqual(writes,0)
    }
    func testCampEquipmentPersistsButOldClassAndSpentResourcesDoNotLeakIntoNewParty()throws {
        let catalog=try MeadowCampaignSession.catalog()
        var old=try GameFactory.player(id:"p2",name:"old",classID:"ranger",teamID:"party",nodeID:1,catalog:catalog)
        old.equipment = .init(weapon:"legendaryStaff",armor:"runeArmor",accessory:"actionRing")
        old.health=1;old.ap=0;old.skillUses=["support":3];old.inventory=["smallPotion":5]
        let s=try MeadowCampaignSession.new(layout:layout(),playerClassID:"ranger",companionClassID:"dragonKnight",loadouts:["p2":old])
        let p1=s.engine.state.units["p1"]!,p2=s.engine.state.units["p2"]!
        XCTAssertEqual(p2.equipment,old.equipment);XCTAssertEqual(p2.inventory,old.inventory)
        XCTAssertEqual(p2.health,try GameRules.attributes(p2,catalog:catalog).maximumHealth)
        XCTAssertEqual(p2.baseAttributes,try catalog.playerClass("dragonKnight").attributes)
        XCTAssertEqual(p2.ap,4);XCTAssertEqual(p1.ap,3);XCTAssertEqual(p1.health,18)
        XCTAssertEqual(p2.skillUses,[:]);XCTAssertEqual(s.movementCapacity,400)
        XCTAssertEqual(try GameRules.skills(p2,catalog:catalog),try catalog.playerClass("dragonKnight").skills)
    }
    func testResumeKeepsBothClassesCursorResourcesAndSelection()throws {
        let s=try MeadowCampaignSession.new(layout:layout(),playerClassID:"ranger",companionClassID:"spellblade")
        try s.selectPlayer("p2")
        let start=s.engine.state.units["p1"]!.nodeID
        try s.beginTravel(to:s.engine.state.map.neighbors(start)[0]);try s.advanceTravel(distance:17.25)
        try s.setPaused(true)
        let before=s.snapshot,resumed=try MeadowCampaignSession(save:.decoded(before.encoded()))
        XCTAssertEqual(resumed.snapshot,before);XCTAssertEqual(resumed.selectedPlayerID,"p2")
        XCTAssertEqual(resumed.partyConfiguration,.init(playerClassID:"ranger",companionClassID:"spellblade"))
        XCTAssertEqual(resumed.position(of:"p2"),s.position(of:"p2"));XCTAssertEqual(resumed.movementRemaining,s.movementRemaining)
        _=MeadowPartyConfiguration(playerClassID:"dragonKnight",companionClassID:"adventurer")
        XCTAssertEqual(resumed.snapshot,before);XCTAssertEqual(resumed.snapshot.formatVersion,1)
    }
    func testSupportDefaultsToOtherPlayerAndSelfSkillsToActualCasterWithoutMutation()throws {
        let s=try battle("ranger","adventurer",current:"p1"),b=try PartyEncounter(engine:s.engine),before=s.snapshot
        XCTAssertEqual(b.preferredTarget(for:.support,ally:"p1",enemy:b.monsterIDs[0]),"p2")
        XCTAssertTrue(b.preview(.support,target:b.preferredTarget(for:.support,ally:"p1",enemy:b.monsterIDs[0])).allowed)
        XCTAssertEqual(b.preferredTarget(for:.attack,ally:"p1",enemy:b.monsterIDs[0]),b.monsterIDs[0])
        XCTAssertEqual(b.preferredTarget(for:.support,ally:"p2",enemy:b.monsterIDs[0]),"p2")
        XCTAssertEqual(s.snapshot,before)
        let other=try battle("ranger","adventurer",current:"p2"),c=try PartyEncounter(engine:other.engine),old=other.snapshot
        XCTAssertEqual(c.preferredTarget(for:.breather,ally:"p1",enemy:c.monsterIDs[0]),"p2")
        XCTAssertEqual(other.snapshot,old)
    }
    func testRepeatedClassSkillCommitAndResumeDoNotShareAPOrUses()throws {
        let s=try battle("ranger","ranger",current:"p1"),b=try PartyEncounter(engine:s.engine)
        let before=s.engine.archive,other=before.state.units["p2"]!
        let intent=try XCTUnwrap(b.prepare(.support,target:"p2"))
        XCTAssertEqual(s.engine.archive,before)
        let restored=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded())),replay=try PartyEncounter(engine:restored.engine)
        let again=try XCTUnwrap(replay.prepare(.support,target:"p2"))
        try b.commit(intent.id);try replay.commit(again.id)
        XCTAssertEqual(s.engine.state,restored.engine.state)
        XCTAssertEqual(s.engine.state.units["p1"]!.skillUses["support"],1)
        XCTAssertEqual(s.engine.state.units["p1"]!.ap,2)
        XCTAssertEqual(s.engine.state.units["p2"]!.ap,other.ap)
        XCTAssertEqual(s.engine.state.units["p2"]!.skillUses,other.skillUses)
        XCTAssertNil(try b.commit(intent.id))
        let done=try MeadowCampaignSession(save:.decoded(s.snapshot.encoded()))
        XCTAssertEqual(done.engine.archive,s.engine.archive)
    }
    func testShieldDisplayReferenceIncludesDragonWardWithoutChangingMechanics()throws {
        let c=try MeadowCampaignSession.catalog()
        var u=try GameFactory.player(id:"p1",name:"p1",classID:"dragonKnight",teamID:"party",nodeID:1,catalog:c)
        for value in [10,9,6]{u.shield=value;XCTAssertEqual(PartyVisual.shieldDisplayMaximum(unit:u,catalog:c),10);XCTAssertEqual(u.shield,value)}
        u.shield=14;XCTAssertEqual(PartyVisual.shieldDisplayMaximum(unit:u,catalog:c),14)
        let monster=try GameFactory.monster(id:"m",templateID:"stoneGuardian",nodeID:1,catalog:c)
        XCTAssertEqual(PartyVisual.shieldDisplayMaximum(unit:monster,catalog:c),6)
    }
    func testNewCompanionJourneyReplaysActualDiceAndResources()throws {
        let a=try MeadowJourneyAudit.run(size:4,seed:0,role:"ranger",companionRole:"spellblade")
        let b=try MeadowJourneyAudit.run(size:4,seed:0,role:"ranger",companionRole:"spellblade")
        XCTAssertEqual(a,b);XCTAssertTrue(["victory","defeat"].contains(a.outcome))
        XCTAssertGreaterThan(a.resumes,0);XCTAssertGreaterThan(a.stagedRestarts,0)
        XCTAssertEqual(a.startingCoins+a.nodeCoins+a.dropCoins-a.movementSpent,a.finalCoins)
    }
}
