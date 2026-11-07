import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport

final class SpellbladeTests:XCTestCase {
    private func ready(_ gear:TrainingLoadout?=nil) throws -> PartyEncounter {
        let p=try PartyEncounter(seed:47,sessionID:"spellblade-test",loadouts:gear?.units,playerClassID:"spellblade")
        try p.engine.apply(.endTurn(actor:"p2",timedOut:false));return p
    }
    @discardableResult private func cast(_ p:PartyEncounter,_ a:PartyAction,_ target:String="p1") throws -> OperationReceipt {
        let i=try XCTUnwrap(p.prepare(a,target:target));return try XCTUnwrap(p.commit(i.id))
    }
    func testClassActionsAndOriginalCostsWithoutEditingCatalog() throws {
        let p=try ready();XCTAssertEqual(p.state.units["p1"]?.baseAttributes.maximumHealth,24)
        XCTAssertEqual(p.playerActions(),[.attack,.runeSlash,.runeWard,.battleRune])
        XCTAssertEqual([p.cost(.runeSlash),p.cost(.runeWard),p.cost(.battleRune)],[2,2,1])
        let old=try PartyEncounter(seed:47);try old.engine.apply(.endTurn(actor:"p2",timedOut:false))
        XCTAssertFalse(old.preview(.runeSlash,target:"m1").allowed);XCTAssertEqual(old.playerActions(),[.attack,.heavyStrike,.breather,.simpleGuard])
        let dragon=try PartyEncounter(playerClassID:"dragonKnight")
        try dragon.engine.apply(.endTurn(actor:"p2",timedOut:false))
        XCTAssertEqual(dragon.state.units["p1"]?.baseAttributes.maximumHealth,32)
        XCTAssertEqual(dragon.playerActions(),[.attack,.dragonFlame,.dragonScaleWard,.dragonOrder])
        let base=try GameCatalog.initial();XCTAssertEqual(try p.engine.catalog.skill("runeWard"),try base.skill("runeWard"))
    }
    func testSlashStagesOneReceiptAndUsesD12EvenWithStaffAndPermanentDamage() throws {
        let g=try TrainingLoadout();try g.equip("legendaryStaff");try g.equipAccessory("powerBadge")
        let p=try ready(g),before=p.state;let i=try XCTUnwrap(p.prepare(.runeSlash,target:"m1")),staged=try XCTUnwrap(p.confirmedReceipt)
        XCTAssertEqual(before,p.state);XCTAssertEqual(p.state.random,before.random)
        let roll=try XCTUnwrap(staged.dice.first{$0.source=="damage"});XCTAssertEqual(roll.formula,DiceFormula(sides:12,count:2,flat:2));XCTAssertEqual(roll.values.count,2)
        let channels=BattleDice.channels(.runeSlash,actor:before.units["p1"]!,target:before.units["m1"]!,catalog:p.engine.catalog,receipt:staged)
        XCTAssertEqual(channels.filter{$0.color=="red"}.map(\.sides),[12,12]);XCTAssertEqual(channels.filter{$0.color=="red"}.compactMap(\.value),roll.values)
        XCTAssertEqual(channels.filter{$0.color=="yellow"}.compactMap(\.value),[2,2]);XCTAssertEqual(channels.filter{$0.color=="green"}.compactMap(\.value),[4]);XCTAssertEqual(channels.filter{$0.color=="blue"}.compactMap(\.value),[4])
        let r=try XCTUnwrap(p.commit(i.id));XCTAssertEqual(r,staged)
        XCTAssertEqual(p.state.units["p1"]?.health,16);XCTAssertEqual(p.state.units["p1"]?.shield,4);XCTAssertEqual(p.state.units["p1"]?.ap,1)
        XCTAssertEqual(18-p.state.units["m1"]!.health,min(18,roll.total+2));XCTAssertNil(try p.commit(i.id))
    }
    func testSlashSelfChannelsNeverHealOrShieldTheEnemyAndPreserveStrongerShield() throws {
        let p=try ready();try p.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:23,shield:8)))
        let i=try XCTUnwrap(p.prepare(.runeSlash,target:"m1"));let cues=SpellbladeEffects.recipients(i,catalog:p.engine.catalog)
        XCTAssertEqual(cues.map(\.unitID),["p1"]);XCTAssertEqual(cues.first?.heal,4);XCTAssertEqual(cues.first?.shield,4)
        _=try p.commit(i.id);XCTAssertEqual(p.state.units["p1"]?.health,24);XCTAssertEqual(p.state.units["p1"]?.shield,8)
        XCTAssertEqual(p.state.units["m1"]?.shield,0)
    }
    func testWardHealsAndShieldsEveryLiveAllyAtSelectedNodeWithFixedDice() throws {
        let p=try ready(),before=p.state;let i=try XCTUnwrap(p.prepare(.runeWard,target:"p2"))
        XCTAssertEqual(Set(i.targets),Set(["p1","p2"]));XCTAssertEqual(p.state,before)
        let dice=BattleDice.channels(.runeWard,actor:before.units["p1"]!,target:before.units["p2"]!,catalog:p.engine.catalog)
        XCTAssertEqual(dice.map(\.color),["green","blue"]);XCTAssertEqual(dice.compactMap(\.value),[8,6]);XCTAssertTrue(dice.allSatisfy{$0.sides==0})
        XCTAssertTrue(p.confirmedReceipt!.dice.isEmpty)
        let r=try XCTUnwrap(p.commit(i.id));XCTAssertEqual(r.after.units["p1"]?.health,20);XCTAssertEqual(r.after.units["p2"]?.health,18)
        for id in ["p1","p2"] { XCTAssertEqual(r.after.units[id]?.shield,6) }
        XCTAssertEqual(r.after.units["p1"]?.ap,1);XCTAssertEqual(r.after.units["p1"]?.skillUses["runeWard"],1)
    }
    func testWardRemoteNodeScopeDoesNotIncludeCasterElsewhere() throws {
        let p=try PartyEncounter(seed:47,playerClassID:"spellblade")
        try p.engine.apply(.move(actors:["p2"],path:[1,0]));try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
        let i=try XCTUnwrap(p.prepare(.runeWard,target:"p2"));XCTAssertEqual(i.targets,["p2"])
        XCTAssertEqual(SpellbladeEffects.recipients(i,catalog:p.engine.catalog).map(\.unitID),["p2"])
        _=try p.commit(i.id);XCTAssertEqual(p.state.units["p1"]?.health,12);XCTAssertEqual(p.state.units["p1"]?.shield,0);XCTAssertEqual(p.state.units["p2"]?.shield,6)
    }
    func testWardSkipsDownedAllyAndNeverReducesExistingShield() throws {
        let p=try ready();try p.engine.apply(.editResources(unit:"p2",value:ResourcePatch(health:0)))
        try p.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:24,shield:8)))
        let i=try XCTUnwrap(p.prepare(.runeWard,target:"p1"));XCTAssertEqual(i.targets,["p1"])
        let r=try XCTUnwrap(p.commit(i.id));XCTAssertEqual(r.after.units["p1"]?.shield,8);XCTAssertEqual(r.after.units["p1"]?.health,24);XCTAssertEqual(r.after.units["p2"]?.health,0)
    }
    func testBattleRuneGrantsBothAlliesShieldAndIndependentTwoRoundDamageBuff() throws {
        let p=try ready();let r=try cast(p,.battleRune)
        XCTAssertTrue(r.dice.isEmpty)
        for id in ["p1","p2"] { XCTAssertEqual(r.after.units[id]?.shield,4);XCTAssertEqual(r.after.units[id]?.damageBuff?.amount,3);XCTAssertEqual(r.after.units[id]?.damageBuff?.roundsLeft,2) }
        XCTAssertEqual(p.state.units["p1"]?.ap,2)
        let i=try XCTUnwrap(p.prepare(.runeSlash,target:"m1")),receipt=try XCTUnwrap(p.confirmedReceipt),roll=try XCTUnwrap(receipt.dice.first{$0.source=="damage"})
        let dice=BattleDice.channels(.runeSlash,actor:p.state.units["p1"]!,target:p.state.units["m1"]!,catalog:p.engine.catalog,receipt:receipt)
        XCTAssertEqual(dice.filter{$0.color=="yellow"}.compactMap(\.value),[2,3])
        _=try p.commit(i.id);XCTAssertEqual(18-p.state.units["m1"]!.health,min(18,roll.total+3));XCTAssertNil(try p.commit(i.id))
    }
    func testBattleRuneDurationAndUseLimitStayWithOriginalRoundEngine() throws {
        let p=try ready();_=try cast(p,.battleRune)
        for id in ["p1","m1","m2"] { XCTAssertEqual(p.current,id);try p.engine.apply(.endTurn(actor:id,timedOut:false)) }
        XCTAssertEqual(p.round,2);XCTAssertEqual(p.state.units["p1"]?.damageBuff?.roundsLeft,2)
        for id in ["p2","p1","m1","m2"] { XCTAssertEqual(p.current,id);try p.engine.apply(.endTurn(actor:id,timedOut:false)) }
        XCTAssertEqual(p.round,3);XCTAssertEqual(p.state.units["p1"]?.damageBuff?.roundsLeft,1)
        for id in ["p2","p1","m1","m2"] { XCTAssertEqual(p.current,id);try p.engine.apply(.endTurn(actor:id,timedOut:false)) }
        XCTAssertEqual(p.round,4);XCTAssertNil(p.state.units["p1"]?.damageBuff)
        try p.engine.apply(.endTurn(actor:"p2",timedOut:false));_=try cast(p,.battleRune)
        XCTAssertFalse(p.preview(.battleRune,target:"p1").allowed)
    }
    func testCancelAndStaleConfirmationNeverPayOrApplySupport() throws {
        let p=try ready(),before=p.state;let i=try XCTUnwrap(p.prepare(.runeWard,target:"p1"));p.cancel()
        XCTAssertNil(try p.commit(i.id));XCTAssertEqual(p.state,before)
        let j=try XCTUnwrap(p.prepare(.battleRune,target:"p1"));try p.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:10)))
        XCTAssertThrowsError(try p.commit(j.id));XCTAssertNil(p.state.units["p1"]?.damageBuff);XCTAssertEqual(p.state.units["p1"]?.ap,3)
    }
    func testTrainingClassAndCastsNeverMutateTheSavedCampProfile() throws {
        let camp=try CampInventorySession(store:nil);try camp.equip(slot:.armor,item:"runeArmor")
        let saved=try camp.exportData(),p=try ready(camp.loadout)
        XCTAssertEqual(try GameRules.attributes(p.state.units["p1"]!,catalog:p.engine.catalog).maximumHealth,32)
        _=try cast(p,.runeWard)
        XCTAssertEqual(try camp.exportData(),saved);XCTAssertEqual(camp.loadout.units["p1"]?.templateID,"adventurer")
        XCTAssertEqual(try GameRules.attributes(camp.loadout.units["p1"]!,catalog:camp.loadout.engine.catalog).maximumHealth,20)
    }
    func testSupportNumbersStayBelowHeadersAndBesideTheCorrectActor() {
        for id in ["p1","p2"] { for width in [36.0,90.0,110.0] { for line in [0,1] { for age in [0.0,0.5,1.0] {
            let foot=PartyVisual.feet[id]!,p=PartyVisual.supportLabelOrigin(at:foot,width:width,line:line,age:age)
            XCTAssertGreaterThanOrEqual(p.x,4);XCTAssertLessThanOrEqual(p.x+width,foot.x-14)
            XCTAssertGreaterThan(p.y,foot.y-170+44+2)
            if id=="p1" { XCTAssertLessThan(p.x+width,PartyVisual.feet["p2"]!.x-88) }
        } } } }
    }
    func testRuneSpriteSequencesHitAtReceiptAreNodeScopedAndParticlesStrikeTheGround() throws {
        let p=try ready();let unit=p.state.units["p1"]!
        let slash=try XCTUnwrap(p.prepare(.runeSlash,target:"m1")),cues=SpellbladeEffects.recipients(slash,catalog:p.engine.catalog)
        let before=SpellbladeEffects.sample(action:.runeSlash,age:0.642,actor:"p1",target:"m1",recipients:cues)
        XCTAssertTrue(before.spriteLayers.isEmpty)
        let onset=SpellbladeEffects.sample(action:.runeSlash,age:0.643,actor:"p1",target:"m1",recipients:cues)
        XCTAssertEqual(onset.spriteLayers.first?.asset,"MeadowRuneSlashAttack01")
        let hit=SpellbladeEffects.sample(action:.runeSlash,age:PartyAction.runeSlash.impact,actor:"p1",target:"m1",recipients:cues)
        XCTAssertEqual(hit.spriteLayers.map(\.asset),["MeadowRuneSlashAttack11"])
        let hitPoint=PartyVisual.hitPoint(target:"m1",weaponID:slash.weaponID)
        XCTAssertEqual(hit.spriteLayers[0].center.x,hitPoint.x-52);XCTAssertEqual(hit.spriteLayers[0].center.y,hitPoint.y-20)
        XCTAssertEqual(hit.spriteLayers[0].size,256);XCTAssertEqual(hit.spriteLayers[0].alpha,1)
        XCTAssertGreaterThan(hit.motes.count,0);XCTAssertTrue(hit.motes.contains{$0.color=="gold" || $0.color=="cyan"})
        let debris=SpellbladeEffects.sample(action:.runeSlash,age:PartyAction.runeSlash.impact+0.5,actor:"p1",target:"m1",recipients:cues)
        XCTAssertTrue(debris.motes.contains{$0.groundAge != nil})
        XCTAssertTrue(debris.motes.allSatisfy{(0...1).contains($0.alpha) && $0.point.x.isFinite && $0.point.y.isFinite})
        XCTAssertTrue(SpellbladeEffects.sample(action:.runeSlash,age:1.598,actor:"p1",target:"m1",recipients:cues).spriteLayers.isEmpty)
        XCTAssertEqual(PartyVisual.travel(slash,age:0).x,0)
        XCTAssertGreaterThan(PartyVisual.travel(slash,age:0.9).x,0)
        XCTAssertEqual(PartyVisual.travel(slash,age:PartyAction.runeSlash.duration).x,0)
        XCTAssertEqual(PartyVisual.pose(unit:unit,intent:slash,age:0,time:0).clip,"attack")
        p.cancel()

        let wardIntent=try XCTUnwrap(p.prepare(.runeWard,target:"p1")),wardRecipients=SpellbladeEffects.recipients(wardIntent,catalog:p.engine.catalog)
        let wardStart=SpellbladeEffects.sample(action:.runeWard,age:0.001,actor:"p1",target:"p1",recipients:wardRecipients)
        XCTAssertEqual(wardStart.spriteLayers.first?.asset,"MeadowRuneWardCast01")
        XCTAssertTrue(wardStart.strokes.isEmpty && wardStart.motes.isEmpty)
        let wardPeak=SpellbladeEffects.sample(action:.runeWard,age:0.831,actor:"p1",target:"p1",recipients:wardRecipients)
        XCTAssertEqual(wardPeak.spriteLayers.first?.asset,"MeadowRuneWardCast13")
        XCTAssertTrue(wardPeak.spriteLayers.count<=2);XCTAssertEqual(Set(wardPeak.spriteLayers.map(\.center).map { "\($0.x),\($0.y)" }).count,1)
        XCTAssertTrue(SpellbladeEffects.sample(action:.runeWard,age:1.44,actor:"p1",target:"p1",recipients:wardRecipients).spriteLayers.isEmpty)
        p.cancel()

        for action in [PartyAction.runeWard,.battleRune] {
            let target=action.isOffensive ? "m1":"p1";let i=try XCTUnwrap(p.prepare(action,target:target)),recipients=SpellbladeEffects.recipients(i,catalog:p.engine.catalog)
            XCTAssertTrue(SpellbladeEffects.sample(action:action,age:-0.1,actor:"p1",target:target,recipients:recipients).strokes.isEmpty)
            for n in 0...Int(action.duration*120) {
                let age=Double(n)/120,q=SpellbladeEffects.sample(action:action,age:age,actor:"p1",target:target,recipients:recipients)
                for s in q.strokes { XCTAssertTrue((0...1).contains(s.alpha));XCTAssertTrue(s.points.allSatisfy{$0.x.isFinite && $0.y.isFinite}) }
                for m in q.motes { XCTAssertTrue((0...1).contains(m.alpha));XCTAssertTrue(m.point.x.isFinite && m.point.y.isFinite);if m.groundAge != nil { XCTAssertLessThanOrEqual(m.point.y,m.ground.y+0.001) } }
            }
            let final=SpellbladeEffects.sample(action:action,age:action.duration,actor:"p1",target:target,recipients:recipients);XCTAssertTrue(final.strokes.isEmpty && final.glows.isEmpty && final.motes.isEmpty && final.spriteLayers.isEmpty)
            XCTAssertEqual(SpellbladeEffects.darkness(action,age:action.duration,from:0),0,accuracy:0.00001)
            XCTAssertEqual(PartyVisual.travel(i,age:0.9).x,0)
            let start=PartyVisual.pose(unit:unit,intent:i,age:0,time:0),end=PartyVisual.pose(unit:unit,intent:i,age:action.duration,time:action.duration)
            XCTAssertEqual(start.clip,"guard");XCTAssertEqual(start.progress,0);XCTAssertEqual(end.progress,1)
            p.cancel()
        }
        XCTAssertEqual(SpellbladeEffects.healingStrength(4),1);XCTAssertGreaterThan(SpellbladeEffects.healingStrength(8),SpellbladeEffects.healingStrength(6));XCTAssertGreaterThan(SpellbladeEffects.healingStrength(12),SpellbladeEffects.healingStrength(8))
    }

    func testPositiveHealthAndShieldFeedbackWaitsUntilEffectSecondHalf() {
        let expected:[(PartyAction,Double)]=[
            (.runeSlash,1.1979),(.runeWard,0.8352),(.dragonSoulWard,1.5266),
            (.dragonScaleWard,1.14),(.starlightPulse,PartyAction.starlightPulse.impact),
            (.dragonFlame,1.2333),(.battleRune,1.334)
        ]
        for (action,age) in expected {
            let cue=SpellbladeEffects.statusVFXCueAge(for:action)!
            XCTAssertEqual(cue,age,accuracy:0.002,"\(action)")
            XCTAssertGreaterThanOrEqual(cue,action.impact)
        }
    }
}
