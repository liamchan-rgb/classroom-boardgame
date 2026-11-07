import XCTest
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import ClassroomGameCore
import MeadowWorldSupport
@testable import MeadowClassroomSupport

final class ClassroomGMTests:XCTestCase {
    func fixture(persist:((Data)throws->Void)?=nil)throws->ClassroomGameBackend {
        let b=ClassroomGameBackend(),layout=try b.generate(.suggested(total:10,seed:31827),role:.teacher)
        try b.install(.new(layout:layout,studentClasses:Array(repeating:"ranger",count:6),persist:persist),role:.teacher)
        return b
    }
    func testBookStripUsesLessThanTenPercentForAllSupportedPlayerCounts(){
        for host in [CGSize(width:1280,height:720),CGSize(width:1024,height:768),CGSize(width:1920,height:1080),CGSize(width:3840,height:2160),CGSize(width:768,height:1024),CGSize(width:640,height:360)] {
            for count in 1...7 {
                let h=ClassroomBookStatusLayout.height(in:host,players:count)
                XCTAssertGreaterThan(h,0);XCTAssertLessThanOrEqual(h*host.width/(host.width*host.height),0.1)
                XCTAssertEqual(h/host.height,0.09,accuracy:0.000001)
            }
        }
        XCTAssertEqual(ClassroomBookStatusLayout.height(in:.zero,players:7),0)
        XCTAssertEqual(ClassroomBookStatusLayout.height(in:CGSize(width:1280,height:Double.nan),players:7),0)
        XCTAssertEqual(ClassroomBookStatusLayout.height(in:CGSize(width:1280,height:720),players:0),0)
    }
    func testBookProjectionIncludesSevenPlayersAndOnlyPublicFields()throws {
        let b=try fixture(),c=b.campaign!;try b.joinTeacher(name:"老师",classID:"adventurer",team:"party",role:.teacher)
        let before=c.snapshot,rows=b.bookPlayers
        XCTAssertEqual(rows.count,7)
        let data=try JSONEncoder().encode(rows),json=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [[String:Any]])
        for row in json {XCTAssertEqual(Set(row.keys),Set(["id","name","health","maximumHealth","ap","maximumAP","coins"]))}
        XCTAssertEqual(c.snapshot,before)
    }
    func testBookGrantUpdatesSelectedPlayersWithIndividualCapsAndNoMovementDebit()throws {
        let b=try fixture(),c=b.campaign!
        try c.engine.apply(.editResources(unit:"p1",value:.init(ap:1,coins:2)))
        try c.engine.apply(.editResources(unit:"p2",value:.init(ap:7,coins:4)))
        try c.engine.setPause(.book,enabled:true);try b.project(.book,role:.teacher)
        let before=c.snapshot
        try b.grantPlayers(["p1","p2"],ap:3,coins:10,role:.teacher)
        XCTAssertEqual(c.engine.state.units["p1"]?.ap,4);XCTAssertEqual(c.engine.state.units["p2"]?.ap,8)
        XCTAssertEqual(c.engine.state.units["p1"]?.coins,12);XCTAssertEqual(c.engine.state.units["p2"]?.coins,14)
        XCTAssertEqual(c.engine.state.units["p3"],before.archive.state.units["p3"])
        XCTAssertEqual(c.movementRemaining,before.movement?.remaining);XCTAssertEqual(c.engine.state.random,before.archive.state.random)
        XCTAssertEqual(b.surface,.book);XCTAssertTrue(c.engine.state.pauseReasons.contains(.book))
    }
    func testGrantInvalidRecipientsAmountsAndOverflowRollBackEveryone()throws {
        let b=try fixture(),c=b.campaign!
        try c.engine.apply(.editResources(unit:"p2",value:.init(coins:Int.max)))
        let before=c.snapshot
        for ids in [["p1","p2"],["p1","missing"],["p1","p1"],[]] {
            XCTAssertThrowsError(try b.grantPlayers(ids,ap:1,coins:1,role:.teacher));XCTAssertEqual(c.snapshot,before)
        }
        XCTAssertThrowsError(try b.grantPlayers(["p1"],ap:-1,coins:1,role:.teacher));XCTAssertEqual(c.snapshot,before)
    }
    func testDisplayCannotGrantOrEditAnyPlayer()throws {
        let b=try fixture(),c=b.campaign!,before=c.snapshot,value=TeacherPlayerEdit(unit:c.engine.state.units["p6"]!)
        XCTAssertThrowsError(try b.editPlayer("p6",value:value,role:.publicDisplay))
        XCTAssertThrowsError(try b.grantPlayers(["p6"],ap:1,coins:1,role:.publicDisplay))
        XCTAssertThrowsError(try b.apply(.editPlayer(unit:"p6",value:value),role:.publicDisplay))
        XCTAssertEqual(c.snapshot,before)
    }
    func testGMCanEditAnyPlayerResourcesAttributesAndBagWithoutChangingIdentityOrOthers()throws {
        let b=try fixture(),c=b.campaign!,before=c.snapshot
        var value=TeacherPlayerEdit(unit:c.engine.state.units["p6"]!)
        value.name="第六名同学";value.attributes.maximumHealth=40;value.attributes.maximumAP=12;value.attributes.baseAP=4;value.attributes.damage=7;value.attributes.range=3
        value.health=35;value.shield=8;value.ap=10;value.coins=99;value.score = -2;value.inventory=["largePotion":8]
        try b.editPlayer("p6",value:value,role:.teacher)
        let actual=c.engine.state.units["p6"]!
        XCTAssertEqual(actual.name,value.name);XCTAssertEqual(actual.baseAttributes,value.attributes);XCTAssertEqual(actual.health,35);XCTAssertEqual(actual.ap,10)
        XCTAssertEqual(actual.inventory,["largePotion":8]);XCTAssertEqual(actual.equipment,before.archive.state.units["p6"]?.equipment)
        XCTAssertEqual(actual.nodeID,before.archive.state.units["p6"]?.nodeID);XCTAssertEqual(actual.teamID,before.archive.state.units["p6"]?.teamID)
        XCTAssertEqual(c.engine.state.units["p1"],before.archive.state.units["p1"]);XCTAssertEqual(c.engine.state.teams,before.archive.state.teams)
        XCTAssertEqual(c.engine.state.random,before.archive.state.random);XCTAssertEqual(c.engine.catalog,before.archive.catalog)
    }
    func testGMRejectsIllegalCapsInventoryAndSkillUsesAtomically()throws {
        let b=try fixture(),c=b.campaign!,before=c.snapshot,base=TeacherPlayerEdit(unit:c.engine.state.units["p1"]!)
        var values=[TeacherPlayerEdit]()
        var x=base;x.health=999;values.append(x)
        x=base;x.ap=999;values.append(x)
        x=base;x.attributes.maximumAP=0;values.append(x)
        x=base;x.inventory=["smallPotion":-1];values.append(x)
        x=base;x.inventory=["unknown":1];values.append(x)
        x=base;x.skillUses=["ambush":999];values.append(x)
        for value in values {XCTAssertThrowsError(try b.editPlayer("p1",value:value,role:.teacher));XCTAssertEqual(c.snapshot,before)}
    }
    func testGMZeroQuantityRemovesOnlyBackpackCopy()throws {
        let b=try fixture(),c=b.campaign!,equipment=c.engine.state.units["p1"]!.equipment
        var value=TeacherPlayerEdit(unit:c.engine.state.units["p1"]!);value.inventory["smallPotion"]=0;value.inventory["trainingSword"]=4
        try b.editPlayer("p1",value:value,role:.teacher)
        XCTAssertNil(c.engine.state.units["p1"]?.inventory["smallPotion"]);XCTAssertEqual(c.engine.state.units["p1"]?.inventory["trainingSword"],4)
        XCTAssertEqual(c.engine.state.units["p1"]?.equipment,equipment)
    }
    func testGMBuffsAndExplicitSkillResetPersistWithoutResettingAP()throws {
        let b=try fixture(),c=b.campaign!;var value=TeacherPlayerEdit(unit:c.engine.state.units["p1"]!)
        value.skillUses=["ambush":1];value.damageBuff = .init(amount:3,roundsLeft:2,appliedRound:0)
        try b.editPlayer("p1",value:value,role:.teacher)
        XCTAssertEqual(c.engine.state.units["p1"]?.damageBuff?.amount,3)
        let ap=c.engine.state.units["p1"]!.ap
        value.skillUses=["ambush":0];value.damageBuff=nil;try b.editPlayer("p1",value:value,role:.teacher)
        XCTAssertEqual(c.engine.state.units["p1"]?.skillUses["ambush"],0);XCTAssertNil(c.engine.state.units["p1"]?.damageBuff);XCTAssertEqual(c.engine.state.units["p1"]?.ap,ap)
    }
    func testGMDeathAndReviveKeepNormalNextRoundEligibility()throws {
        let b=try fixture(),c=b.campaign!,monster=c.engine.state.units.values.first{$0.kind == .monster}!
        try c.engine.apply(.startBattle(kind:.pve,monsters:[monster.id]));try c.engine.setPause(.book,enabled:true);try b.project(.book,role:.teacher)
        var value=TeacherPlayerEdit(unit:c.engine.state.units["p1"]!);value.health=0;value.shield=5;value.damageBuff = .init(amount:2,roundsLeft:1,appliedRound:0)
        try b.editPlayer("p1",value:value,role:.teacher)
        XCTAssertEqual(c.engine.state.units["p1"]?.shield,0);XCTAssertNil(c.engine.state.units["p1"]?.damageBuff)
        value=TeacherPlayerEdit(unit:c.engine.state.units["p1"]!);value.health=8
        try b.editPlayer("p1",value:value,role:.teacher)
        XCTAssertEqual(c.engine.state.units["p1"]?.canActFromRound,(c.engine.state.battle?.round ?? 0)+1);XCTAssertEqual(b.surface,.book)
    }
    func testGMSaveAndUndoRestoreCompletePlayerAndBookProjection()throws {
        let b=try fixture(),c=b.campaign!,before=c.snapshot
        var value=TeacherPlayerEdit(unit:c.engine.state.units["p6"]!);value.coins=57;value.inventory=["revivalStone":9]
        try b.editPlayer("p6",value:value,role:.teacher)
        let restored=try MeadowCampaignSession(save:.decoded(c.snapshot.encoded()))
        XCTAssertEqual(restored.engine.state.units["p6"],c.engine.state.units["p6"])
        XCTAssertEqual(b.bookPlayers.first{$0.id=="p6"}?.coins,57)
        try c.engine.undo();XCTAssertEqual(c.snapshot,before)
    }
    func testGMFailedDiskSaveKeepsStateProjectionAndRandomUnchanged()throws {
        var fail=false
        let b=try fixture(persist:{_ in if fail{throw GameError("disk full")}}),c=b.campaign!,before=c.snapshot,projection=b.bookPlayers
        var value=TeacherPlayerEdit(unit:c.engine.state.units["p1"]!);value.coins=123;fail=true
        XCTAssertThrowsError(try b.editPlayer("p1",value:value,role:.teacher));XCTAssertEqual(c.snapshot,before);XCTAssertEqual(b.bookPlayers,projection)
        XCTAssertThrowsError(try b.grantPlayers(["p1","p2"],ap:1,coins:3,role:.teacher));XCTAssertEqual(c.snapshot,before)
    }
    func testGMRejectsDefeatingActiveRoadTravelerWithoutCorruptingCursor()throws {
        let b=try fixture(),c=b.campaign!,start=c.engine.state.units["p1"]!.nodeID
        try c.beginTravel(to:c.engine.state.map.neighbors(start)[0]);try c.advanceTravel(distance:25)
        let before=c.snapshot;var value=TeacherPlayerEdit(unit:c.engine.state.units["p1"]!);value.health=0
        XCTAssertThrowsError(try b.editPlayer("p1",value:value,role:.teacher));XCTAssertEqual(c.snapshot,before)
    }
    func testTeacherUndoIsPrivateAndCannotUndoUnrelatedLaterActions()throws {
        let b=try fixture(),c=b.campaign!,before=c.snapshot
        try b.grantPlayers(["p1","p2"],ap:1,coins:10,role:.teacher)
        XCTAssertTrue(b.canUndoTeacherAction)
        XCTAssertThrowsError(try b.undoTeacherAction(role:.publicDisplay))
        try b.undoTeacherAction(role:.teacher);XCTAssertEqual(c.snapshot,before)
        try b.grantPlayers(["p1"],ap:1,coins:10,role:.teacher)
        try c.engine.apply(.reward(actors:["p2"],value:.init(coins:1)))
        XCTAssertFalse(b.canUndoTeacherAction)
        XCTAssertThrowsError(try b.undoTeacherAction(role:.teacher))
    }

}
