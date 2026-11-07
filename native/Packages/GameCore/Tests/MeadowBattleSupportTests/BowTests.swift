import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport
final class BowTests:XCTestCase {
    func testBowInventoryTransferAndRealD8SingleAtomicHit() throws {
        let gear=try TrainingLoadout();try gear.equip("huntingBow")
        XCTAssertEqual(gear.units["p1"]?.inventory["trainingSword"],1);XCTAssertNil(gear.units["p1"]?.inventory["huntingBow"])
        let party=try PartyEncounter(seed:47,loadouts:gear.units);try party.engine.apply(.endTurn(actor:"p2",timedOut:false))
        let before=party.state,intent=try XCTUnwrap(party.prepare(.attack,target:"m1"))
        XCTAssertTrue(intent.ranged);XCTAssertEqual(before,party.state)
        let die=try XCTUnwrap(party.confirmedReceipt?.dice.first);XCTAssertEqual(die.formula.sides,8)
        for age in stride(from:0.0,through:1.7,by:0.01) { let p=PartyVisual.travel(intent,age:age);XCTAssertEqual(p.x,0);XCTAssertEqual(p.y,0) }
        let result=try XCTUnwrap(party.commit(intent.id));XCTAssertNil(try party.commit(intent.id));XCTAssertEqual(before.units["m1"]!.health-result.after.units["m1"]!.health,die.total)
        try gear.equip("trainingSword");XCTAssertEqual(gear.units["p1"]?.inventory["huntingBow"],1);XCTAssertNil(gear.units["p1"]?.inventory["trainingSword"])
    }
    func testProjectileVisibleOnlyAfterReleaseAndArrivesAtAtomicHitPoint() {
        let from=PartyPoint(212.31,362.73),to=PartyVisual.hitPoint(target:"m1")
        XCTAssertNil(BowRig.projectile(age:0.859,from:from,to:to,impact:1.048))
        let first=BowRig.projectile(age:0.86,from:from,to:to,impact:1.048)!
        XCTAssertEqual(first.tip.x,from.x,accuracy:1e-9);XCTAssertEqual(first.tip.y,from.y,accuracy:1e-9)
        let last=BowRig.projectile(age:1.048-1e-9,from:from,to:to,impact:1.048)!
        XCTAssertEqual(last.tip.x,to.x,accuracy:0.00001);XCTAssertEqual(last.tip.y,to.y,accuracy:0.00001)
        XCTAssertNil(BowRig.projectile(age:1.048,from:from,to:to,impact:1.048))
    }
    private func position(_ p:BowPartPose)->PartyPoint { PartyPoint(p.pivot.x+p.offset.x,p.pivot.y+p.offset.y) }
    func testReviewedFullDrawAndRelaxedShoulderReachRuntimeWithoutLegacyGeometry() {
        let held=BowRig.sample(clip:"attack",progress:BowRig.releaseProgress-0.001)
        XCTAssertEqual(position(held.parts["nearUpper"]!).x,117)
        XCTAssertEqual(position(held.parts["nearUpper"]!).y,141)
        XCTAssertEqual(position(held.parts["nearFore"]!).x,104)
        XCTAssertEqual(position(held.parts["nearFore"]!).y,136)
        XCTAssertEqual(position(held.parts["nearHand"]!).x,141)
        XCTAssertEqual(position(held.parts["nearHand"]!).y,139)
        XCTAssertEqual(position(held.parts["farHand"]!).x,184)
        XCTAssertTrue(held.arrowVisible)
        let idle=BowRig.sample(clip:"idle",progress:0),returned=BowRig.sample(clip:"attack",progress:1)
        let elbow=position(idle.parts["nearFore"]!)
        XCTAssertEqual(elbow.x,112);XCTAssertEqual(elbow.y,159,"The approved upper arm unfolds down from the shoulder")
        for key in ["nearUpper","nearFore","nearHand","farHand","bow"] {
            XCTAssertEqual(position(idle.parts[key]!).x,position(returned.parts[key]!).x,accuracy:1e-8)
            XCTAssertEqual(position(idle.parts[key]!).y,position(returned.parts[key]!).y,accuracy:1e-8)
        }
        XCTAssertFalse(idle.arrowVisible);XCTAssertFalse(returned.arrowVisible)
    }
    func testNativePartsKeepTheirRegistrationsAndDrawingContactThroughAllSamples() {
        var last:[String:PartyPoint]=[:]
        for i in 0...600 {
            let p=BowRig.sample(clip:"attack",progress:Double(i)/600)
            XCTAssertEqual(Set(p.nativeTiles!.keys),Set(["nearUpperArm","nearSleeveConnected","farArm","nearHand","farHand"]))
            for group in p.nativeTiles!.keys { let tile=BowRig.nativeTile(p,group:group);XCTAssertGreaterThan(tile.width,0);XCTAssertGreaterThan(tile.height,0) }
            for key in ["nearUpper","nearFore","nearHand","farUpper","farFore","farHand"] {
                let at=position(p.parts[key]!);XCTAssertTrue(at.x.isFinite && at.y.isFinite)
                if let before=last[key] { XCTAssertLessThan(hypot(at.x-before.x,at.y-before.y),6,"No branch flip or frame reset") }
                last[key]=at
            }
            let hand=position(p.parts["nearHand"]!),grip=position(p.parts["farHand"]!),bow=position(p.parts["bow"]!)
            XCTAssertEqual(grip.x,bow.x,accuracy:1e-9);XCTAssertEqual(grip.y,bow.y,accuracy:1e-9)
            if p.arrowVisible {
                XCTAssertEqual(p.arrowTail.x,hand.x,accuracy:1e-8);XCTAssertEqual(p.arrowTail.y,hand.y,accuracy:1e-8)
                if p.nativeFrame!>=33 {
                    XCTAssertEqual(p.stringHand.x,hand.x,accuracy:1e-8);XCTAssertEqual(p.stringHand.y,hand.y,accuracy:1e-8)
                }
            }
        }
    }
    func testReleaseClockAndRecoveryKeepTheReviewedPace() {
        XCTAssertEqual(BowRig.releaseAge,0.86)
        XCTAssertEqual(BowRig.artTime(progress:BowRig.releaseProgress),1.34,accuracy:1e-9)
        let first=BowRig.sample(clip:"attack",progress:BowRig.releaseProgress)
        XCTAssertFalse(first.arrowVisible)
        let initial=position(first.parts["nearHand"]!),grip=position(first.parts["farHand"]!)
        var y=initial.y
        for i in 1...120 {
            let q=BowRig.sample(clip:"attack",progress:BowRig.releaseProgress+0.34/1.2*Double(i)/120)
            let hand=position(q.parts["nearHand"]!),holding=position(q.parts["farHand"]!)
            XCTAssertGreaterThanOrEqual(hand.y+1e-8,y);y=hand.y
            XCTAssertEqual(holding.x,grip.x,accuracy:1e-8);XCTAssertEqual(holding.y,grip.y,accuracy:1e-8)
        }
        XCTAssertGreaterThan(y-initial.y,20)
        XCTAssertEqual(BowRig.releaseArrowTip.x,214);XCTAssertEqual(BowRig.releaseArrowTip.y,139)
        XCTAssertEqual(BowRig.releaseArrowLength,73)
    }
    func testPreparationBeginsAtConfirmationWithoutMovingReleaseOrImpactHold() {
        XCTAssertGreaterThan(BowRig.sample(clip:"attack",progress:BowRig.progress(age:0.3)).nativeFrame!,14)
        XCTAssertEqual(BowRig.progress(age:0.86),BowRig.releaseProgress,accuracy:1e-9)
        XCTAssertEqual(BowRig.progress(age:1.048),BowRig.progress(age:1.148),accuracy:1e-9)
        XCTAssertEqual(BowRig.progress(age:1.8),1)
    }
    func testProjectileDoesNotShrinkAtReleaseOrOvershootTheHit() {
        let scale=PartyVisual.heroScale,from=PartyPoint(200,300),to=PartyPoint(450,310)
        for age in [0.86,0.90,1.047] {
            let arrow=BowRig.projectile(age:age,from:from,to:to,impact:1.048,scale:scale)!
            XCTAssertEqual(hypot(arrow.tip.x-arrow.tail.x,arrow.tip.y-arrow.tail.y),73*scale,accuracy:1e-8)
        }
        XCTAssertNil(BowRig.projectile(age:0.86,from:from,to:to,impact:0.86))
    }
    func testDedicatedStatesKeepGripAndCanvasRegistrationWithoutDoubleRecoil() {
        for clip in ["guard","hit","victory","defeat"] {
            let source=BowRig.sample(clip:clip,progress:0.5)
            let moved=BowRig.sample(clip:clip,progress:0.5,lean:0.1,crouch:4)
            XCTAssertTrue(source.canvasBaked == true)
            XCTAssertGreaterThan(source.nativeFrame!,142)
            XCTAssertEqual(source.nativeFrame,moved.nativeFrame)
            XCTAssertEqual(source.nativeTiles,moved.nativeTiles)
            XCTAssertEqual(position(source.parts["farHand"]!).x,position(moved.parts["farHand"]!).x)
            XCTAssertFalse(source.arrowVisible)
            for i in 0...600 {
                let q=BowRig.sample(clip:clip,progress:Double(i)/600)
                let grip=position(q.parts["farHand"]!),bow=position(q.parts["bow"]!)
                XCTAssertEqual(grip.x,bow.x,accuracy:1e-9);XCTAssertEqual(grip.y,bow.y,accuracy:1e-9)
                XCTAssertFalse(q.arrowVisible)
                XCTAssertEqual(q.groundY!+q.rootOffset!.y,214,accuracy:1e-9)
                XCTAssertFalse(q.contacts!.isEmpty)
                for c in q.contacts! { XCTAssertEqual(c.y,q.groundY!,accuracy:1e-9) }
                for group in q.nativeTiles!.keys { let tile=BowRig.nativeTile(q,group:group);XCTAssertGreaterThan(tile.width,0);XCTAssertGreaterThan(tile.height,0) }
            }
        }
    }
    func testGuardAndRecoilReturnToApprovedIdleWithoutArmReset() {
        let idle=BowRig.sample(clip:"idle",progress:0)
        XCTAssertEqual(idle.nativeFrame,142)
        for clip in ["guard","hit"] {
            for p in [0.0,1.0] {
                let q=BowRig.sample(clip:clip,progress:p)
                for key in ["nearUpper","nearFore","nearHand","farUpper","farFore","farHand","bow"] {
                    XCTAssertEqual(position(q.parts[key]!).x,position(idle.parts[key]!).x,accuracy:1e-8)
                    XCTAssertEqual(position(q.parts[key]!).y,position(idle.parts[key]!).y,accuracy:1e-8)
                }
                for key in idle.nativeTiles!.keys { XCTAssertEqual(q.nativeTiles![key],idle.nativeTiles![key]) }
            }
            let peak=BowRig.sample(clip:clip,progress:0.3)
            XCTAssertNotEqual(peak.nativeTiles!["nearSleeveConnected"],idle.nativeTiles!["nearSleeveConnected"])
        }
    }
    func testCollapsedPoseSupportsHandAndReversesThroughSameRevivalFrames() {
        let rest=BowRig.sample(clip:"defeat",progress:0),down=BowRig.sample(clip:"defeat",progress:1)
        XCTAssertGreaterThan(position(down.parts["nearUpper"]!).y-position(rest.parts["nearUpper"]!).y,15)
        XCTAssertGreaterThan(position(down.parts["nearHand"]!).y,205)
        XCTAssertEqual(down.parts["bow"]!.rotation,1.25,accuracy:1e-8)
        XCTAssertEqual(down.nativeTiles,BowRig.sample(clip:"defeat",progress:1.1).nativeTiles)
        var previous:[String:PartyPoint]=[:]
        for i in 0...600 {
            let q=BowRig.sample(clip:"defeat",progress:1-Double(i)/600)
            for key in ["nearUpper","nearFore","nearHand","farHand"] {
                let at=position(q.parts[key]!)
                if let before=previous[key] { XCTAssertLessThan(hypot(at.x-before.x,at.y-before.y),4) }
                previous[key]=at
            }
        }
        let raised=BowRig.sample(clip:"victory",progress:1)
        XCTAssertLessThan(position(raised.parts["farHand"]!).y,position(rest.parts["farHand"]!).y-15)
    }
    func testVictoryWaitsForRecoveryAndLeavesFallenPlayersDown() throws {
        let p=try PartyEncounter(seed:47),alive=p.state.units["p1"]!
        XCTAssertEqual(PartyVisual.pose(unit:alive,intent:nil,age:0,time:0,victoryAge:0.54).clip,"victory")
        XCTAssertEqual(PartyVisual.pose(unit:alive,intent:nil,age:0,time:0,victoryAge:0.54).progress,0.5,accuracy:1e-8)
        XCTAssertEqual(PartyVisual.pose(unit:alive,intent:nil,age:0,time:0,hurtAge:0.1,victoryAge:0.54).clip,"hit")
        try p.engine.apply(.editResources(unit:"p1",value:ResourcePatch(health:0)))
        XCTAssertEqual(PartyVisual.pose(unit:p.state.units["p1"]!,intent:nil,age:0,time:0,downAge:1,victoryAge:1).clip,"defeat")
    }

}
