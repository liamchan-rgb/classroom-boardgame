import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport
final class LegendaryStaffTests:XCTestCase {
    func testInventoryAndSwitchingConserveFourWeapons() throws {
        let gear=try TrainingLoadout()
        for id in ["legendaryStaff","greatSword","huntingBow","trainingSword","legendaryStaff"] {
            try gear.equip(id)
            for item in ["legendaryStaff","greatSword","huntingBow","trainingSword"] {
                let u=gear.units["p1"]!;XCTAssertEqual((u.inventory[item] ?? 0)+(u.equipment.weapon==item ? 1:0),1)
            }
        }
    }
    func testD20LockedOnceWithNoPrematureDamage() throws {
        let g=try TrainingLoadout();try g.equip("legendaryStaff")
        let p=try PartyEncounter(seed:47,loadouts:g.units);try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
        let before=p.state,i=try XCTUnwrap(p.prepare(.attack,target:"m1")),r=try XCTUnwrap(p.confirmedReceipt)
        XCTAssertEqual(r.dice.first?.formula.sides,20);XCTAssertEqual(p.state,before)
        XCTAssertTrue(i.magical);XCTAssertFalse(i.ranged);XCTAssertEqual(i.action.impact,1.048)
        let travel=PartyVisual.travel(i,age:0.8);XCTAssertEqual(travel.x,0);XCTAssertEqual(travel.y,0)
        XCTAssertEqual(try p.commit(i.id),r);XCTAssertNil(try p.commit(i.id))
    }
    func testHeavyStrikeRetainsSkillFormula() throws {
        let g=try TrainingLoadout();try g.equip("legendaryStaff")
        let p=try PartyEncounter(seed:47,loadouts:g.units);try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
        _=try XCTUnwrap(p.prepare(.heavyStrike,target:"m1"));let d=try XCTUnwrap(p.confirmedReceipt?.dice.first)
        XCTAssertEqual(d.formula.sides,6);XCTAssertEqual(d.formula.flat,2)
    }
    func testNaturalTwentyComesFromOriginalRuleAndClearsHealthThroughShield() throws {
        let g=try TrainingLoadout();try g.equip("legendaryStaff");var checked=false
        for seed in UInt64(1)...100 {
            let p=try PartyEncounter(seed:seed,loadouts:g.units);try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
            try p.engine.apply(.editResources(unit:"m1",value:ResourcePatch(shield:100)))
            let i=try XCTUnwrap(p.prepare(.attack,target:"m1"))
            if p.confirmedReceipt?.dice.first?.naturalTwenty==true {
                let r=try XCTUnwrap(p.commit(i.id));XCTAssertEqual(r.after.units["m1"]?.health,0)
                XCTAssertTrue(r.events.contains { $0.kind=="naturalTwenty" });checked=true;break
            }
        }
        XCTAssertTrue(checked)
    }
    func testProjectileStartsAtRealGemAndEndsAtDamagePointWithoutTeleporting() {
        for id in ["m1","m2"] {
            let f=PartyVisual.feet["p1"]!,to=PartyVisual.hitPoint(target:id,weaponID:"legendaryStaff"),s=PartyVisual.heroScale
            let a=LegendaryStaffRig.effect(age:LegendaryStaffRig.releaseAge,foot:f,target:to,groundY:PartyVisual.feet[id]!.y,scale:s)
            let g=LegendaryStaffRig.gem(progress:LegendaryStaffRig.progress(age:LegendaryStaffRig.releaseAge))
            XCTAssertEqual(a.head!.x,f.x+(g.x-123)*s,accuracy:1e-8);XCTAssertEqual(a.head!.y,f.y+(g.y-214)*s,accuracy:1e-8)
            let b=LegendaryStaffRig.effect(age:1.048,foot:f,target:to,groundY:PartyVisual.feet[id]!.y,scale:s)
            XCTAssertEqual(b.head!.x,to.x,accuracy:1e-8);XCTAssertEqual(b.head!.y,to.y,accuracy:1e-8)
            XCTAssertNil(LegendaryStaffRig.effect(age:0,foot:f,target:to,groundY:400,scale:s).head)
        }
    }
    func testClockGripAndRestContinuity() {
        var last=0.0
        for i in 0...600 {
            let p=LegendaryStaffRig.progress(age:Double(i)/300);XCTAssertGreaterThanOrEqual(p+1e-10,last);last=p
            let q=LegendaryStaffRig.pose(progress:Double(i)/600)
            let a=q.layers["MeadowBattleHeroWeapon"]!,b=q.layers["MeadowBattleHeroNearHand"]!
            XCTAssertEqual(a.rotation,b.rotation);XCTAssertEqual(a.offset.x,b.offset.x);XCTAssertEqual(a.offset.y,b.offset.y)
            XCTAssertFalse(q.contacts.isEmpty)
        }
        XCTAssertEqual(LegendaryStaffRig.progress(age:1.048),LegendaryStaffRig.progress(age:1.148),accuracy:1e-9)
        XCTAssertEqual(LegendaryStaffRig.progress(age:1.7),1)
    }
    func testParticleGroundContactsAreFiniteAndDoNotFallThroughFloor() {
        for i in 0...200 {
            let q=LegendaryStaffRig.effect(age:Double(i)/100,foot:PartyVisual.feet["p1"]!,target:PartyPoint(580,320),groundY:395,scale:0.83)
            for p in q.motes where p.id>=10 { XCTAssertTrue(p.x.isFinite && p.y.isFinite);XCTAssertLessThanOrEqual(p.y,395);XCTAssertTrue((0...1).contains(p.alpha)) }
        }
    }
    func testDebrisLandsThenFadesBeforeActionCloses() {
        var landed=false
        for i in 0...65 {
            let q=LegendaryStaffRig.effect(age:1.048+Double(i)/100,foot:PartyVisual.feet["p1"]!,target:PartyPoint(580,320),groundY:395,scale:0.83)
            if q.motes.contains(where: { $0.id>=10 && abs($0.y-395)<5 && $0.alpha>0.1 }) { landed=true }
        }
        XCTAssertTrue(landed)
        let end=LegendaryStaffRig.effect(age:1.7,foot:PartyVisual.feet["p1"]!,target:PartyPoint(580,320),groundY:395,scale:0.83)
        XCTAssertTrue(end.motes.allSatisfy { $0.alpha<1e-8 })
    }

}
