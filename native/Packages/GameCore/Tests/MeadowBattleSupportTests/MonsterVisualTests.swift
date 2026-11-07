import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport
final class MonsterVisualTests:XCTestCase {
    func testSpeciesRegistryIsSeparateFromPersistentIDsAndLegacyDeer() throws {
        let catalog=try GameCatalog.initial()
        XCTAssertEqual(Set(MonsterVisualSpec.ids),Set(catalog.monsters.map(\.id)))
        XCTAssertEqual(Set(MonsterVisualSpec.ids.compactMap{MonsterVisualSpec.find($0)?.asset}).count,6)
        XCTAssertEqual(MonsterVisualSpec.find("stoneGuardian")!.shieldCapacity(catalog:catalog),6);XCTAssertEqual(MonsterVisualSpec.find("ruinDragon")!.shieldCapacity(catalog:catalog),10)
        XCTAssertNil(MonsterVisualSpec.find("meadowStag"));XCTAssertNil(MonsterVisualSpec.find("m-7-2"))
        XCTAssertGreaterThan(MonsterVisualSpec.find("caveTroll")!.scale,MonsterVisualSpec.find("wolf")!.scale)
        for id in MonsterVisualSpec.ids {
            let target="m-9-1",old=PartyVisual.hitPoint(target:target),new=PartyVisual.hitPoint(target:target,templateID:id)
            let base=PartyIntent(id:"old",action:.attack,actor:"p1",target:target,targets:[target],command:.attack(actor:"p1",target:target),enemy:false,weaponID:"trainingSword")
            let fixed=PartyIntent(id:"registered",action:.attack,actor:"p1",target:target,targets:[target],command:base.command,enemy:false,weaponID:"trainingSword",targetTemplateID:id)
            let a=PartyVisual.travel(base,age:1.048),b=PartyVisual.travel(fixed,age:1.048)
            XCTAssertEqual(PartyVisual.foot("p1")!.y+b.y,PartyVisual.foot(target)!.y-12,accuracy:1)
            XCTAssertEqual(b.x-a.x,new.x-old.x,accuracy:0.001);XCTAssertEqual(b.y-a.y,new.y-old.y,accuracy:0.001)
            let anchor=PartyVisual.diceAnchor(actor:"p1",intent:fixed,age:1.048,diceCount:2)
            XCTAssertLessThan(anchor.x+70,PartyVisual.foot(target)!.x-84)
        }
    }
    func testHurtInterruptsAttackAndAllSpeciesReturnToIdle() throws {
        for id in MonsterVisualSpec.ids {
            let spec=try XCTUnwrap(MonsterVisualSpec.find(id))
            for age in stride(from:0.0,through:3,by:1.0/60) {
                let frame=spec.frame(time:age,attackAge:age,castAge:nil,hurtAge:nil)
                XCTAssertTrue((0..<56).contains(frame))
                let hurt=spec.frame(time:age,attackAge:0.4,castAge:nil,hurtAge:0.1)
                XCTAssertTrue((48..<56).contains(hurt))
            }
            XCTAssertLessThan(spec.frame(time:2.4,attackAge:1.1,castAge:2,hurtAge:1),12)
            XCTAssertEqual(MonsterVisualSpec.deathFrame(-1),0);XCTAssertEqual(MonsterVisualSpec.deathFrame(20),39)
        }
    }
    func testRangedSpeciesStayInPlaceAndMissileTerminatesAtContact() throws {
        let from=PartyVisual.foot("m-7-1")!,target=PartyVisual.hitPoint(target:"p1")
        for id in ["goblinArcher","ruinDragon"] {
            let spec=try XCTUnwrap(MonsterVisualSpec.find(id))
            let intent=PartyIntent(id:"missile",action:.attack,actor:"m-7-1",target:"p1",targets:["p1"],command:.monsterStep,enemy:true,weaponID:nil,monsterTemplateID:id,enemyRanged:true)
            XCTAssertTrue(intent.ranged);XCTAssertEqual(PartyVisual.travel(intent,age:0.46).x,0)
            XCTAssertNil(spec.projectile(age:0.23,foot:from,target:target));XCTAssertNil(spec.projectile(age:0.46,foot:from,target:target))
            let first=try XCTUnwrap(spec.projectile(age:0.24,foot:from,target:target)),last=try XCTUnwrap(spec.projectile(age:0.45999,foot:from,target:target))
            XCTAssertGreaterThan(first.tip.x,last.tip.x);XCTAssertEqual(last.tip.x,target.x,accuracy:0.05)
            XCTAssertEqual(intent.impactAge,0.46)
        }
        for id in ["slime","wolf","stoneGuardian","caveTroll"] {
            let spec=try XCTUnwrap(MonsterVisualSpec.find(id)),intent=PartyIntent(id:"contact",action:.attack,actor:"m-7-1",target:"p1",targets:["p1"],command:.monsterStep,enemy:true,weaponID:nil,monsterTemplateID:id)
            let foot=PartyVisual.foot(intent.actor)!,offset=PartyVisual.travel(intent,age:0.46)
            XCTAssertEqual(foot.x+offset.x+(spec.contactX-178.5)*spec.scale,PartyVisual.foot("p1")!.x,accuracy:0.001)
        }
    }
    func testThreePersistentSlotsAndBossDiceAvoidTheirHeaders() throws {
        let slots=["m-10-1","m-10-2","m-10-3"]
        XCTAssertEqual(Set(slots.map(PartyVisual.slot)).count,3)
        let points=slots.compactMap(PartyVisual.foot);XCTAssertEqual(points.count,3)
        XCTAssertNotEqual(points[0].x,points[2].x)
        for id in MonsterVisualSpec.ids {
            let spec=try XCTUnwrap(MonsterVisualSpec.find(id)),foot=PartyVisual.foot(slots[0])!
            let anchor=PartyVisual.diceAnchor(actor:slots[0],intent:nil,age:0,monsterTemplateID:id)
            let header=foot.y-224*spec.scale-46
            XCTAssertLessThanOrEqual(anchor.y+100,header-9)
        }
    }
}
