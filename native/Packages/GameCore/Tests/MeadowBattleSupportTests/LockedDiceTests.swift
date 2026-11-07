import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport
final class LockedDiceTests:XCTestCase {
    func testConfirmationResolvesOnceWithoutApplyingDamageUntilImpact() throws {
        let p=try PartyEncounter(seed:50),before=p.state,history=p.engine.history.count
        let i=try XCTUnwrap(p.prepare(.ambush,target:"m1")),r=try XCTUnwrap(p.confirmedReceipt)
        XCTAssertEqual(r.dice.first?.values.count,2);XCTAssertEqual(p.state,before);XCTAssertEqual(p.engine.history.count,history)
        let d=BattleDice.channels(.ambush,actor:before.units["p2"]!,target:before.units["m1"]!,catalog:p.engine.catalog,receipt:r)
        XCTAssertEqual(d.filter { $0.sides>0 }.compactMap(\.value),r.dice.first?.values)
        let committed=try XCTUnwrap(p.commit(i.id));XCTAssertEqual(committed.after,r.after);XCTAssertEqual(p.state,r.after)
        XCTAssertEqual(p.engine.history.count,history+1);XCTAssertNil(try p.commit(i.id));XCTAssertNil(p.confirmedReceipt)
    }
    func testCancelAndStaleReservationDoNotConsumeOrOverwriteState() throws {
        let p=try PartyEncounter(seed:50),before=p.state
        let first=try XCTUnwrap(p.prepare(.ambush,target:"m1")),values=p.confirmedReceipt?.dice.first?.values
        p.cancel();XCTAssertEqual(p.state,before);XCTAssertNil(try p.commit(first.id))
        let second=try XCTUnwrap(p.prepare(.ambush,target:"m1"));XCTAssertEqual(p.confirmedReceipt?.dice.first?.values,values)
        try p.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:7)))
        let changed=p.state;XCTAssertThrowsError(try p.commit(second.id));XCTAssertEqual(p.state,changed);XCTAssertNil(p.pending)
    }
    func testLockedDiceAreImmediatelyStationaryAndDamageIsCenteredOnContact() {
        let die=BattleDie("red",sides:8,value:7)
        let a=PolyhedralDice.sample(die:die,time:1,index:0,count:4,resolvedAge:nil,visibleAge:1,locked:true)
        let b=PolyhedralDice.sample(die:die,time:2,index:0,count:4,resolvedAge:nil,visibleAge:2,locked:true)
        XCTAssertEqual(a.resultMix,1);XCTAssertEqual(a.offsetY,0);XCTAssertEqual(a.orientation.w,b.orientation.w);XCTAssertEqual(a.orientation.x,b.orientation.x)
        XCTAssertEqual(a.faces.max { $0.depth<$1.depth }?.value,7)
        for id in ["p1","m1"] {
            let hit=PartyVisual.hitPoint(target:id),origin=PartyVisual.damageLabelOrigin(at:hit,width:40,height:30,age:0)
            XCTAssertEqual(origin.x+20,hit.x);XCTAssertEqual(origin.y+15,hit.y)
            XCTAssertLessThan(PartyVisual.damageLabelOrigin(at:hit,width:40,height:30,age:0.5).y,origin.y)
        }
    }
    func testEveryResolvedFaceAndNumeralAreUprightWithoutTimeDependentSkew() throws {
        for sides in PolyhedralDice.supported {
            let mesh=try XCTUnwrap(PolyhedralDice.mesh(sides))
            for value in 1...sides {
                let die=BattleDie("red",sides:sides,value:value)
                let sample=PolyhedralDice.sample(die:die,time:1,index:2,count:3,resolvedAge:nil,visibleAge:1,locked:true)
                let face=try XCTUnwrap(mesh.faces.first { $0.value==value })
                let normal=sample.orientation.rotate(face.normal),up=sample.orientation.rotate(face.up)
                XCTAssertEqual(normal.z,1,accuracy:1e-9);XCTAssertEqual(up.y,1,accuracy:1e-9)
                let front=try XCTUnwrap(sample.faces.first { $0.value==value })
                XCTAssertEqual(front.up.x,front.center.x,accuracy:1e-9)
                XCTAssertLessThan(front.up.y,front.center.y)
                XCTAssertEqual(front.right.y,front.center.y,accuracy:1e-9)
                XCTAssertGreaterThan(front.right.x,front.center.x)
                let later=PolyhedralDice.sample(die:die,time:3,index:2,count:3,resolvedAge:0.2,visibleAge:3,locked:true)
                XCTAssertEqual(sample.faces.map(\.value),later.faces.map(\.value))
                for (a,b) in zip(sample.faces,later.faces) {
                    XCTAssertEqual(a.center.x,b.center.x,accuracy:1e-9)
                    XCTAssertEqual(a.center.y,b.center.y,accuracy:1e-9)
                    XCTAssertEqual(a.depth,b.depth,accuracy:1e-9)
                }
            }
        }
    }
}

extension LockedDiceTests {
    func testConfirmationLandingStartsAtExactHoverPoseAndFinishesUprightBeforeImpact() throws {
        for sides in PolyhedralDice.supported { for value in 1...sides {
            let die=BattleDie("red",sides:sides,value:value),t=7.31
            let hover=PolyhedralDice.sample(die:die,time:t,index:1,count:2,resolvedAge:nil,visibleAge:1)
            let first=PolyhedralDice.sample(die:die,time:t,index:1,count:2,resolvedAge:nil,visibleAge:1,locked:true,confirmationAge:0)
            XCTAssertEqual(hover.orientation.w,first.orientation.w,accuracy:1e-10);XCTAssertEqual(hover.offsetY,first.offsetY,accuracy:1e-10)
            let finished=PolyhedralDice.sample(die:die,time:t+0.32,index:1,count:2,resolvedAge:nil,visibleAge:2,locked:true,confirmationAge:0.32)
            let held=PolyhedralDice.sample(die:die,time:t+0.6,index:1,count:2,resolvedAge:nil,visibleAge:2,locked:true,confirmationAge:0.6)
            let face=try XCTUnwrap(PolyhedralDice.mesh(sides)?.faces.first { $0.value==value })
            XCTAssertEqual(finished.orientation.rotate(face.normal).z,1,accuracy:1e-9);XCTAssertEqual(finished.orientation.rotate(face.up).y,1,accuracy:1e-9)
            XCTAssertEqual(finished.orientation.w,held.orientation.w,accuracy:1e-9);XCTAssertEqual(finished.offsetY,0);XCTAssertEqual(held.alpha,1)
        } }
    }
    func testConfirmationLandingHasContinuousRotationWithNoFinalJump() {
        func distance(_ a:DieQuaternion,_ b:DieQuaternion)->Double { 2*acos(min(1,abs(a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z))) }
        for sides in PolyhedralDice.supported {
            let die=BattleDie("red",sides:sides,value:sides)
            var prior=PolyhedralDice.sample(die:die,time:4,index:0,count:1,resolvedAge:nil,visibleAge:1,locked:true,confirmationAge:0).orientation
            var moved=0.0
            for frame in 1...40 {
                let age=Double(frame)*0.01,q=PolyhedralDice.sample(die:die,time:4+age,index:0,count:1,resolvedAge:nil,visibleAge:1+age,locked:true,confirmationAge:age).orientation
                let delta=distance(prior,q);XCTAssertLessThan(delta,0.22);moved+=delta;prior=q
            }
            XCTAssertGreaterThan(moved,0.05)
        }
    }
}
