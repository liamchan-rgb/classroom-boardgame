import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport

final class AmbushTests:XCTestCase {
    func testSelectionExposesFixedAmountsButNeverRollsOrMutates() throws {
        let p=try PartyEncounter(seed:49),before=p.state
        XCTAssertTrue(p.playerActions().contains(.ambush));XCTAssertEqual(p.cost(.ambush),2)
        for _ in 0..<120 {
            XCTAssertTrue(p.preview(.ambush,target:"m1").allowed)
            let d=BattleDice.channels(.ambush,actor:before.units["p2"]!,target:before.units["m1"]!,catalog:p.engine.catalog)
            XCTAssertEqual(d.map(\.sides),[8,8,0,0]);XCTAssertNil(d[0].value);XCTAssertNil(d[1].value)
            XCTAssertEqual(d[2].value,2);XCTAssertEqual(d[3].value,3)
            let support=BattleDice.channels(.support,actor:before.units["p2"]!,target:before.units["p1"]!,catalog:p.engine.catalog)
            XCTAssertEqual(support.compactMap(\.value),[6,4])
        }
        XCTAssertEqual(p.state,before);XCTAssertFalse(p.preview(.ambush,target:"p1").allowed)
    }
    func testAmbushOneReceiptDamagesEnemyHealsCasterAndCostsTwoAP() throws {
        let p=try PartyEncounter(seed:49),before=p.state,i=try XCTUnwrap(p.prepare(.ambush,target:"m1"))
        XCTAssertEqual(p.state,before);let r=try XCTUnwrap(p.commit(i.id))
        let roll=try XCTUnwrap(r.dice.first { $0.source=="damage" })
        XCTAssertEqual(roll.formula.sides,8);XCTAssertEqual(roll.values.count,2)
        XCTAssertEqual(r.before.units["p2"]!.ap-r.after.units["p2"]!.ap,2)
        XCTAssertEqual(r.after.units["p2"]!.health,15);XCTAssertEqual(r.after.units["p1"]!.health,before.units["p1"]!.health)
        XCTAssertEqual(r.after.units["m1"]!.health,max(0,18-roll.values.reduce(0,+)-2))
        XCTAssertEqual(r.after.units["p2"]!.skillUses["ambush"],1)
        let d=BattleDice.channels(.ambush,actor:before.units["p2"]!,target:before.units["m1"]!,catalog:p.engine.catalog,receipt:r)
        XCTAssertEqual(d.filter { $0.sides>0 }.compactMap(\.value),roll.values)
        let after=p.state;XCTAssertNil(try p.commit(i.id));XCTAssertEqual(p.state,after)
    }
    func testFinalEnemyDefeatStillHealsCasterAndFullHealthDoesNotOverheal() throws {
        for health in [12,18] {
            let p=try PartyEncounter(seed:49)
            try p.engine.apply(.editResources(unit:"p2",value:ResourcePatch(health:health)))
            try p.engine.apply(.editResources(unit:"m2",value:ResourcePatch(health:0)))
            try p.engine.apply(.editResources(unit:"m1",value:ResourcePatch(health:1)))
            let i=try XCTUnwrap(p.prepare(.ambush,target:"m1")),r=try XCTUnwrap(p.commit(i.id))
            XCTAssertFalse(r.after.units["m1"]!.isAlive);XCTAssertEqual(r.after.units["p2"]!.health,min(18,health+3))
        }
    }
    func testAmbushMotionContactReturnAndHeadGroupAreContinuous() throws {
        let p=try PartyEncounter(seed:49),i=try XCTUnwrap(p.prepare(.ambush,target:"m1"))
        XCTAssertEqual(PartyVisual.travel(i,age:0).x,0);XCTAssertEqual(PartyVisual.travel(i,age:2.1).x,0)
        XCTAssertEqual(PartyVisual.travel(i,age:i.action.impact).x,510-315,accuracy:1e-8)
        XCTAssertEqual(PartyVisual.ambushProgress(i.action.impact),0.54,accuracy:1e-8)
        for tick in 1...2100 {
            let t=Double(tick)/1000,a=PartyVisual.travel(i,age:t-0.001),b=PartyVisual.travel(i,age:t)
            XCTAssertLessThan(abs(a.x-b.x)+abs(a.y-b.y),1.2)
            XCTAssertLessThan(abs(PartyVisual.ambushProgress(t)-PartyVisual.ambushProgress(t-0.001)),0.005)
        }
        for count in [4,5] {
            let a=PartyVisual.diceAnchor(actor:i.actor,intent:i,age:i.action.impact,diceCount:count)
            let right=a.x+Double(count-1)*PolyhedralDice.spacing(count:count)/2+PolyhedralDice.radius(count:count)*1.3
            XCTAssertLessThan(right,PartyVisual.feet[i.target]!.x-94)
            let idle=PartyVisual.diceAnchor(actor:i.actor,intent:nil,age:0,diceCount:count)
            let half=Double(count-1)*PolyhedralDice.spacing(count:count)/2+PolyhedralDice.radius(count:count)*1.3
            XCTAssertGreaterThanOrEqual(idle.x-half,PartyVisual.feet["p1"]!.x+100-1e-8)
        }
        XCTAssertFalse(PartyVisual.afterimages(i,age:0.5).isEmpty);XCTAssertTrue(PartyVisual.afterimages(i,age:1.1).isEmpty)
        XCTAssertFalse(PartyVisual.ambushSlashes(age:0.8,at:PartyPoint(0,0)).isEmpty)
    }
}
