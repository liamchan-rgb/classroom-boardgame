import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport
final class PartyTests:XCTestCase {
    func testSupportAtomicAndReplay() throws {
        let p=try PartyEncounter(seed:17,sessionID:"support-test")
        let before=p.state
        for _ in 0..<40 { XCTAssertTrue(p.preview(.support,target:"p1").allowed) }
        XCTAssertEqual(before,p.state)
        let intent=try XCTUnwrap(p.prepare(.support,target:"p1"));XCTAssertEqual(p.state,before)
        let r=try XCTUnwrap(p.commit(intent.id));XCTAssertEqual(r.after.units["p1"]?.health,12);XCTAssertEqual(r.after.units["p1"]?.shield,4)
        XCTAssertEqual(r.after.units["p2"]?.ap,2);XCTAssertNil(try p.commit(intent.id));XCTAssertEqual(p.engine.history.count,1)
        XCTAssertEqual(try p.engine.apply(intent.command,id:intent.id),r)
    }
    func testGroupBuffAndMaxShieldAndCancellation() throws {
        let p=try PartyEncounter(seed:18)
        let start=p.state;_ = p.prepare(.support,target:"p1");p.cancel();XCTAssertEqual(start,p.state)
        let a=try XCTUnwrap(p.prepare(.support,target:"p1"));_ = try p.commit(a.id)
        let b=try XCTUnwrap(p.prepare(.support,target:"p1"));_ = try p.commit(b.id)
        XCTAssertEqual(p.state.units["p1"]?.shield,4)
        let c=try XCTUnwrap(p.prepare(.rally,target:"p1"));let r=try XCTUnwrap(p.commit(c.id))
        XCTAssertEqual(c.targets,["p1","p2"])
        for id in ["p1","p2"] { XCTAssertEqual(r.after.units[id]?.damageBuff?.amount,2);XCTAssertEqual(r.after.units[id]?.damageBuff?.roundsLeft,1) }
        XCTAssertFalse(p.preview(.rally,target:"m1").allowed)
    }
    func testSourceDefinitionsAndItems() throws {
        let p=try PartyEncounter(seed:19),source=try GameCatalog.initial()
        XCTAssertEqual(p.engine.catalog.skills,source.skills);XCTAssertEqual(p.engine.catalog.items,source.items)
        XCTAssertFalse(p.preview(.smallPotion,target:"m1").allowed)
        let i=try XCTUnwrap(p.prepare(.largePotion,target:"p1"));let r=try XCTUnwrap(p.commit(i.id))
        XCTAssertEqual(r.after.units["p1"]?.health,12);XCTAssertEqual(r.after.units["p2"]?.inventory["largePotion"],nil)
        let small=try XCTUnwrap(p.prepare(.smallPotion,target:"p2"));let healed=try XCTUnwrap(p.commit(small.id))
        XCTAssertEqual(healed.after.units["p2"]?.health,18);XCTAssertEqual(healed.after.units["p2"]?.inventory["smallPotion"],1)
    }
    func testRevivalConsumesOnceAndRetainsDownedPlayer() throws {
        let p=try PartyEncounter(seed:21)
        try p.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:0)))
        let down=p.state.units["p1"]!;XCTAssertFalse(down.isAlive)
        XCTAssertEqual(PartyVisual.pose(unit:down,intent:nil,age:0,time:0,downAge:0).progress,0)
        let falling=PartyVisual.pose(unit:down,intent:nil,age:0.3,time:0.3,downAge:0.3)
        XCTAssertGreaterThan(falling.progress,0);XCTAssertLessThan(falling.progress,1)
        XCTAssertFalse(p.preview(.smallPotion,target:"p1").allowed)
        let intent=try XCTUnwrap(p.prepare(.revivalStone,target:"p1"))
        let before=PartyVisual.pose(unit:down,intent:intent,age:0.71,time:0.71)
        XCTAssertEqual(before.clip,"defeat");XCTAssertEqual(before.progress,1)
        let receipt=try XCTUnwrap(p.commit(intent.id))
        let risen=try XCTUnwrap(receipt.after.units["p1"])
        XCTAssertEqual(risen.health,6);XCTAssertEqual(risen.canActFromRound,2)
        XCTAssertEqual(receipt.after.units["p2"]?.ap,1)
        XCTAssertNil(receipt.after.units["p2"]?.inventory["revivalStone"])
        XCTAssertNil(try p.commit(intent.id))
        let mid=PartyVisual.pose(unit:risen,intent:intent,age:1.02,time:1.02)
        XCTAssertGreaterThan(mid.progress,0);XCTAssertLessThan(mid.progress,1)
    }
    func testBuffDamageAndActualRoundExpiry() throws {
        let p=try PartyEncounter(seed:22)
        let rally=try XCTUnwrap(p.prepare(.rally,target:"p1"));_ = try p.commit(rally.id)
        try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
        let strike=try XCTUnwrap(p.prepare(.attack,target:"m1"));let hit=try XCTUnwrap(p.commit(strike.id))
        XCTAssertEqual(18-(hit.after.units["m1"]?.health ?? 0),hit.dice.first!.total+2)
        for targetRound in [2,3] {
            var guardCount=0
            while p.round<targetRound {
                guardCount += 1;XCTAssertLessThan(guardCount,20)
                try p.engine.apply(.endTurn(actor:p.current!,timedOut:false))
            }
            for id in ["p1","p2"] { XCTAssertEqual(p.state.units[id]?.damageBuff == nil,targetRound==3) }
        }
    }
    func testImpactCadencesAndStaleCancellation() throws {
        for fps in [15,30,60,120] {
            let p=try PartyEncounter(seed:23)
            let intent=try XCTUnwrap(p.prepare(.support,target:"p1"));let before=p.state
            var elapsed=0.0,commits=0
            while elapsed<1.8 {
                elapsed += 1/Double(fps)
                if elapsed>=intent.action.impact,let _=try p.commit(intent.id) { commits += 1;XCTAssertLessThanOrEqual(elapsed-intent.action.impact,1/Double(fps)+1e-8) }
                if elapsed<intent.action.impact { XCTAssertEqual(p.state,before) }
            }
            XCTAssertEqual(commits,1);XCTAssertEqual(p.state.units["p1"]?.health,12)
            let other=try XCTUnwrap(p.prepare(.support,target:"p1"));let snapshot=p.state;p.cancel()
            XCTAssertNil(try p.commit(other.id));XCTAssertEqual(p.state,snapshot)
        }
    }

    func testEnemyStopsAtActualCircleSurface() throws {
        let p=try PartyEncounter(seed:24)
        try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
        let guardIntent=try XCTUnwrap(p.prepare(.simpleGuard,target:"p1"));_ = try p.commit(guardIntent.id)
        try p.engine.apply(.endTurn(actor:"p1",timedOut:false))
        let enemy=try XCTUnwrap(p.prepare(.attack,target:"p1"));XCTAssertTrue(enemy.enemy)
        let motion=PartyVisual.travel(enemy,age:0.46,shielded:true)
        let leading=PartyVisual.feet[enemy.actor]!.x+motion.x-(178.5-42)*PartyVisual.enemyScale
        let barrier=PartyVisual.feet[enemy.target]!.x+(5+240*0.41)*PartyVisual.heroScale
        XCTAssertEqual(leading,barrier,accuracy:1e-8)
        XCTAssertLessThan(PartyVisual.travel(enemy,age:0.46).x,motion.x)
    }

}

extension PartyTests {
    func testDicePreviewDoesNotRollAndCommitShowsReceiptPlusBuff() throws {
        let p=try PartyEncounter(seed:47)
        let rally=try XCTUnwrap(p.prepare(.rally,target:"p1"));_ = try p.commit(rally.id)
        try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
        let before=p.state,actor=before.units["p1"]!,target=before.units["m1"]!
        for _ in 0..<120 {
            let dice=BattleDice.channels(.attack,actor:actor,target:target,catalog:p.engine.catalog)
            XCTAssertEqual(dice.map(\.color),["red","yellow"]);XCTAssertNil(dice.first?.value);XCTAssertEqual(dice.last?.value,2)
        }
        XCTAssertEqual(p.state,before)
        let intent=try XCTUnwrap(p.prepare(.attack,target:"m1"));let r=try XCTUnwrap(p.commit(intent.id))
        let result=BattleDice.channels(.attack,actor:actor,target:target,catalog:p.engine.catalog,receipt:r)
        XCTAssertEqual(result.first?.value,r.dice.first?.values.first);XCTAssertEqual(result.last?.value,2)
        XCTAssertEqual(result.first!.value!+result.last!.value!,r.events.first(where: { $0.kind=="damage" })?.amount)
    }
    func testFixedDiceSupportAndItemsKeepOriginalValues() throws {
        let p=try PartyEncounter(seed:48),before=p.state
        let i=try XCTUnwrap(p.prepare(.support,target:"p1"));let r=try XCTUnwrap(p.commit(i.id))
        let channels=BattleDice.channels(.support,actor:before.units["p2"]!,target:before.units["p1"]!,catalog:p.engine.catalog,receipt:r)
        XCTAssertEqual(channels.map(\.color),["green","blue"]);XCTAssertEqual(channels.compactMap(\.value),[6,4]);XCTAssertTrue(channels.allSatisfy { $0.sides==0 })
        let shield=BattleDice.channels(.shieldPotion,actor:before.units["p2"]!,target:before.units["p1"]!,catalog:p.engine.catalog,receipt:r)
        XCTAssertEqual(shield.map(\.color),["blue"]);XCTAssertEqual(shield.first?.value,8)
        let large=BattleDice.channels(.largePotion,actor:before.units["p2"]!,target:before.units["p1"]!,catalog:p.engine.catalog,receipt:r)
        XCTAssertEqual(large.first?.value,12)
        XCTAssertEqual(BattleDice.channels(.revivalStone,actor:before.units["p2"]!,target:before.units["p1"]!,catalog:p.engine.catalog,receipt:r).first?.value,6)
    }
    func testDiceShakeSettlesContinuouslyWithoutChangingValues() {
        let a=BattleDice.pose(time:0.5,index:0,resolvedAge:nil,visibleAge:0.5)
        let b=BattleDice.pose(time:0.501,index:0,resolvedAge:0,visibleAge:0.501)
        XCTAssertEqual(a.angle,b.angle,accuracy:0.01);XCTAssertEqual(b.resultMix,0)
        let mid=BattleDice.pose(time:0.68,index:0,resolvedAge:0.325,visibleAge:0.68)
        XCTAssertEqual(mid.resultMix,0.5,accuracy:1e-8)
        let settled=BattleDice.pose(time:0.9,index:0,resolvedAge:0.7,visibleAge:0.9)
        XCTAssertEqual(settled.angle,0);XCTAssertEqual(settled.offsetY,0);XCTAssertEqual(settled.resultMix,1)
        XCTAssertNotEqual(a.angle,BattleDice.pose(time:6.8,index:0,resolvedAge:nil,visibleAge:6.8).angle)
        XCTAssertEqual(BattleDice.pose(time:3,index:0,resolvedAge:2,visibleAge:3).alpha,0)
        XCTAssertGreaterThan(BattleDice.darkness(.heavyStrike),BattleDice.darkness(.attack))
    }
    func testMonsterIdleHitPreparationAndRecovery() {
        let idle=PartyVisual.monster(time:0,attackAge:nil),breath=PartyVisual.monster(time:0.4,attackAge:nil)
        XCTAssertNotEqual(idle.scaleY,breath.scaleY)
        let hit=PartyVisual.monster(time:0.4,attackAge:nil,hurtAge:0.055)
        XCTAssertEqual(hit.recoil,14,accuracy:1e-8);XCTAssertGreaterThan(hit.flash,0.6)
        let recovered=PartyVisual.monster(time:1,attackAge:nil,hurtAge:0.6)
        XCTAssertEqual(recovered.recoil,0);XCTAssertEqual(recovered.flash,0)
        XCTAssertEqual(PartyVisual.monster(time:1,attackAge:0.96).progress,1)
    }
}
extension PartyTests {
    func testPersistentMonsterDiceUseReviewedSlots() {
        for node in [0,2,17,29] {
            for index in 1...2 {
                let id="m-\(node)-\(index)",slot="m\(index)"
                for age in [0.0,0.16,0.46,0.96,1.10] {
                    let dynamic=PartyVisual.diceAnchor(actor:id,intent:nil,age:age,diceCount:3)
                    let reviewed=PartyVisual.diceAnchor(actor:slot,intent:nil,age:age,diceCount:3)
                    XCTAssertEqual(dynamic.x,reviewed.x);XCTAssertEqual(dynamic.y,reviewed.y)
                }
            }
        }
    }
    func testPlayerDiceAvoidPersistentEnemyHeaderLikeTrainingHeader() {
        for actor in ["p1","p2"] {
            for index in 1...2 {
                for action in [PartyAction.attack,.ambush,.runeSlash] {
                    func intent(_ target:String)->PartyIntent {
                        PartyIntent(id:"anchor",action:action,actor:actor,target:target,targets:[target],command:.attack(actor:actor,target:target),enemy:false,weaponID:"trainingSword")
                    }
                    for age in [0.0,0.3,0.72,1.048,1.5] {
                        for count in [1,2,5] {
                            let real=PartyVisual.diceAnchor(actor:actor,intent:intent("m-17-\(index)"),age:age,diceCount:count)
                            let demo=PartyVisual.diceAnchor(actor:actor,intent:intent("m\(index)"),age:age,diceCount:count)
                            XCTAssertEqual(real.x,demo.x,accuracy:1e-9);XCTAssertEqual(real.y,demo.y,accuracy:1e-9)
                        }
                    }
                }
            }
        }
    }
    func testHeadDiceClearEnemyBarDuringForwardStrike() throws {
        let p=try PartyEncounter(seed:49)
        try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
        let i=try XCTUnwrap(p.prepare(.attack,target:"m1"))
        let anchor=PartyVisual.diceAnchor(actor:i.actor,intent:i,age:1.048)
        let rightFace=anchor.x+PolyhedralDice.spacing(count:2)/2+PolyhedralDice.radius(count:2)*1.3
        XCTAssertLessThan(rightFace,PartyVisual.feet[i.target]!.x-84-10)
        let idle=PartyVisual.diceAnchor(actor:i.actor,intent:nil,age:0)
        XCTAssertEqual(idle.x,PartyVisual.feet[i.actor]!.x)
    }
}
