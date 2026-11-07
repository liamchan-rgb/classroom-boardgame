import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport

final class SkillVFXTests:XCTestCase {
    func testFiveDeliverySpecsRetainTheirAuthoredCanvasAndExistingMotionRole() {
        XCTAssertEqual(PartySkillVFXSpec.all.map(\.id),["starlightPulse","rally","sweep","dragonSoulWard","dragonScaleWard"])
        XCTAssertEqual(PartySkillVFXSpec.all.map(\.frameCount),[20,20,20,20,20])
        XCTAssertEqual(PartySkillVFXSpec.all.map(\.framesPerSecond),[16,12,20,12,20])
        XCTAssertEqual(PartySkillVFXSpec.all.map { [$0.frameWidth,$0.frameHeight] },[[344,344],[256,256],[339,287],[256,256],[256,256]])
        XCTAssertEqual(PartySkillVFXSpec.all.map { [$0.anchorX,$0.anchorY] },[[172,172],[128,128],[169.5,143.5],[133,154],[128,128]])
        XCTAssertEqual(PartySkillVFXSpec.all.map(\.peakFrame),[12,14,9,12,12])
        XCTAssertEqual(PartySkillVFXSpec.all.map(\.motion),[.ranged,.support,.melee,.support,.support])
        XCTAssertEqual(PartySkillVFXSpec.all.map(\.target),[.enemyNode,.allyNode,.allyNode,.allyNode,.allyNode])
    }

    func testSkillVFXReusesAttackAndGuardActionsInsteadOfIntroducingNewClips() {
        XCTAssertEqual(PartyAction.starlightPulse.visual,"attack")
        XCTAssertTrue(PartyAction.starlightPulse.usesRangedMotion)
        XCTAssertTrue(PartyAction.starlightPulse.isOffensive)
        XCTAssertEqual(PartyAction.sweep.visual,"attack")
        XCTAssertFalse(PartyAction.sweep.usesRangedMotion)
        XCTAssertTrue(PartyAction.sweep.isOffensive)
        for action in [PartyAction.rally,.dragonSoulWard,.dragonScaleWard] {
            XCTAssertEqual(action.visual,"support")
            XCTAssertFalse(action.isOffensive)
        }
    }

    func testOffensiveFramesPeakOnTheExistingHitTime() throws {
        let star=try XCTUnwrap(PartySkillVFXSpec.find("starlightPulse"))
        XCTAssertEqual(star.startTime(actionStart:0,impactAge:1.048)+star.peakTime,1.048,accuracy:1e-9)
        let sweep=try XCTUnwrap(PartySkillVFXSpec.find("sweep"))
        XCTAssertEqual(sweep.startTime(actionStart:2,impactAge:0.46)+sweep.peakTime,2.46,accuracy:1e-9)
        let ward=try XCTUnwrap(PartySkillVFXSpec.find("dragonScaleWard"))
        XCTAssertEqual(ward.startTime(actionStart:2,impactAge:0.56),2.56,accuracy:1e-9)
        let rally=try XCTUnwrap(PartySkillVFXSpec.find("rally"))
        XCTAssertEqual(rally.startTime(actionStart:2,impactAge:0.56),2.56,accuracy:1e-9)
    }

    func testSkillEffectsUseOneNodeAnchorForAllTargets() {
        let allies=PartyVisual.skillEffectCenter(targets:["p1","p2"],actor:"p1")
        XCTAssertEqual(allies.x,244.15,accuracy:1e-9)
        XCTAssertEqual(allies.y,391.12,accuracy:1e-9)
        let enemies=PartyVisual.skillEffectCenter(targets:["m1","m2"],actor:"p1")
        XCTAssertEqual(enemies.x,753.57,accuracy:1e-9)
        XCTAssertEqual(enemies.y,360.66,accuracy:1e-9)
        let monsterTargets=PartyVisual.skillEffectCenter(targets:["p1","p2"],actor:"m1")
        XCTAssertEqual(monsterTargets.x,244.15,accuracy:1e-9)
        XCTAssertEqual(monsterTargets.y,391.12,accuracy:1e-9)
    }

    func testClassAndSetSkillsExposeTheirNewVFXActions() throws {
        let dragon=try PartyEncounter(playerClassID:"dragonKnight")
        XCTAssertEqual(dragon.actions(for:"p1"),[.attack,.dragonFlame,.dragonScaleWard,.dragonOrder])

        let catalog=try GameCatalog.initial()
        var starlight=try GameFactory.player(id:"p2",name:"P2",classID:"ranger",teamID:"party",nodeID:1,catalog:catalog)
        starlight.equipment=Equipment(weapon:"starlightBlade",armor:"starlightArmor",accessory:"starlightCharm")
        let starParty=try PartyEncounter(loadouts:["p2":starlight])
        XCTAssertEqual(Array(starParty.actions(for:"p2").suffix(1)),[.starlightPulse])
        let starIntent=try XCTUnwrap(starParty.prepare(.starlightPulse,target:"m1"))
        XCTAssertEqual(starIntent.targets,["m1","m2"])

        var dragonMark=try GameFactory.player(id:"p2",name:"P2",classID:"ranger",teamID:"party",nodeID:1,catalog:catalog)
        dragonMark.equipment=Equipment(weapon:"dragonFangSword",armor:"dragonArmor",accessory:"dragonCharm")
        let wardParty=try PartyEncounter(loadouts:["p2":dragonMark])
        XCTAssertTrue(wardParty.actions(for:"p2").contains(.dragonSoulWard))
        let wardIntent=try XCTUnwrap(wardParty.prepare(.dragonSoulWard,target:"p1"))
        XCTAssertEqual(wardIntent.targets,["p1","p2"])
    }
}
