import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport
final class GreatSwordTests:XCTestCase {
    func testEquipSwitchesTransferExactlyOneItemWithoutDuplicatingAnyWeapon() throws {
        let gear=try TrainingLoadout()
        for id in ["greatSword","huntingBow","trainingSword","greatSword"] {
            try gear.equip(id)
            let u=gear.units["p1"]!
            XCTAssertEqual(u.equipment.weapon,id)
            for item in ["greatSword","huntingBow","trainingSword"] { XCTAssertEqual((u.inventory[item] ?? 0)+(u.equipment.weapon==item ? 1:0),1) }
        }
        try gear.equip(nil)
        XCTAssertNil(gear.units["p1"]!.equipment.weapon)
        XCTAssertEqual(gear.units["p1"]!.inventory["greatSword"],1)
    }
    func testD12AttackIsLockedOnceAndCommitsAtTheExistingSingleHit() throws {
        let gear=try TrainingLoadout();try gear.equip("greatSword")
        let p=try PartyEncounter(seed:58,loadouts:gear.units);try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
        let before=p.state,intent=try XCTUnwrap(p.prepare(.attack,target:"m1"))
        XCTAssertEqual(intent.weaponID,"greatSword");XCTAssertFalse(intent.ranged)
        XCTAssertEqual(p.state,before)
        let die=try XCTUnwrap(p.confirmedReceipt?.dice.first)
        XCTAssertEqual(die.formula.sides,12);XCTAssertEqual(die.formula.count,1)
        let result=try XCTUnwrap(p.commit(intent.id));XCTAssertNil(try p.commit(intent.id))
        XCTAssertEqual(before.units["m1"]!.health-result.after.units["m1"]!.health,die.total)
        XCTAssertEqual(before.units["p1"]!.ap-result.after.units["p1"]!.ap,1)
        XCTAssertEqual(intent.action.impact,1.048)
    }
    func testHeavyStrikeKeepsItsSkillD6PlusTwoRatherThanUsingWeaponD12() throws {
        let gear=try TrainingLoadout();try gear.equip("greatSword")
        let p=try PartyEncounter(seed:58,loadouts:gear.units);try p.engine.apply(.endTurn(actor:"p2",timedOut:false))
        _=try XCTUnwrap(p.prepare(.heavyStrike,target:"m1"))
        let die=try XCTUnwrap(p.confirmedReceipt?.dice.first)
        XCTAssertEqual(die.formula.sides,6);XCTAssertEqual(die.formula.flat,2)
    }
    func testContactTravelActuallyPutsTheBladeOnTheSameDamagePoint() {
        for target in ["m1","m2"] {
            let from=PartyVisual.feet["p1"]!,to=PartyVisual.hitPoint(target:target,weaponID:"greatSword")
            let travel=GreatSwordRig.travel(age:1.048,from:from,to:to,scale:PartyVisual.heroScale)
            let tip=GreatSwordRig.tip(progress:GreatSwordRig.progress(age:1.048))
            XCTAssertEqual(from.x+travel.x+(tip.x-123)*PartyVisual.heroScale,to.x,accuracy:1e-8)
            XCTAssertEqual(from.y+travel.y+(tip.y-214)*PartyVisual.heroScale,to.y,accuracy:1e-8)
            for age in [0.0,1.7,2.0] {
                let q=GreatSwordRig.travel(age:age,from:from,to:to,scale:PartyVisual.heroScale)
                XCTAssertEqual(q.x,0,accuracy:1e-8);XCTAssertEqual(q.y,0,accuracy:1e-8)
            }
        }
    }
    func testContinuousProfileKeepsGripFaceAndGroundingRegistered() {
        for i in 0...600 {
            let q=GreatSwordRig.pose(progress:Double(i)/600)
            let a=q.layers["MeadowBattleHeroWeapon"]!,b=q.layers["MeadowBattleHeroNearHand"]!
            XCTAssertEqual(a.offset.x,b.offset.x);XCTAssertEqual(a.offset.y,b.offset.y);XCTAssertEqual(a.rotation,b.rotation)
            let head=q.layers["MeadowBattleHeroHair"]!,face=q.layers["MeadowBattleHeroFace"]!,torso=q.layers["MeadowBattleHeroBodyCore"]!
            XCTAssertEqual(head.rotation,face.rotation);XCTAssertEqual(face.rotation,torso.rotation)
            XCTAssertTrue(q.rootOffset.x.isFinite && q.rootOffset.y.isFinite)
            XCTAssertFalse(q.contacts.isEmpty)
            XCTAssertTrue(q.contacts.allSatisfy { abs($0.y-q.footAnchorPx.y)<=1.01 })
        }
    }
    func testMotionClockKeepsTheHitHoldAndReturnsToItsRestPose() {
        XCTAssertEqual(GreatSwordRig.progress(age:0),0)
        XCTAssertEqual(GreatSwordRig.progress(age:1.048),0.55,accuracy:1e-8)
        XCTAssertEqual(GreatSwordRig.progress(age:1.048),GreatSwordRig.progress(age:1.148),accuracy:1e-8)
        XCTAssertEqual(GreatSwordRig.progress(age:1.7),1)
        var previous=0.0
        for i in 0...200 { let p=GreatSwordRig.progress(age:Double(i)/100);XCTAssertGreaterThanOrEqual(p+1e-8,previous);previous=p }
        for key in GreatSwordRig.pose(progress:0).layers.keys {
            let a=GreatSwordRig.pose(progress:0).layers[key]!,b=GreatSwordRig.pose(progress:1).layers[key]!
            XCTAssertEqual(a.offset.x,b.offset.x,accuracy:1e-8);XCTAssertEqual(a.offset.y,b.offset.y,accuracy:1e-8);XCTAssertEqual(a.rotation,b.rotation,accuracy:1e-8)
        }
    }
}
