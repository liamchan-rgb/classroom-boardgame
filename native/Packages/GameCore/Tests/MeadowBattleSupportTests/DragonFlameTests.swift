import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport

final class DragonFlameTests:XCTestCase {
    func testDragonKnightFlameCommitsOneNodeWideReceiptAndCasterChannels() throws {
        let model=try PartyEncounter(seed:47,sessionID:"dragon-flame-node",playerClassID:"dragonKnight")
        XCTAssertEqual(model.state.units["p1"]?.baseAttributes.maximumHealth,32)
        XCTAssertEqual(model.state.units["p1"]?.health,20)
        XCTAssertEqual(model.actions(for:"p1"),[.attack,.dragonFlame,.dragonScaleWard,.dragonOrder])
        XCTAssertEqual(model.cost(.dragonFlame),2)
        try model.engine.apply(.endTurn(actor:"p2",timedOut:false))

        let before=model.state
        let intent=try XCTUnwrap(model.prepare(.dragonFlame,target:"m1"))
        XCTAssertEqual(intent.command,.cast(actor:"p1",skill:"dragonFlame",target:.node(1)))
        XCTAssertEqual(Set(intent.targets),Set(["m1","m2"]))
        XCTAssertEqual(model.state,before,"the pending visual must not mutate combat state")
        let staged=try XCTUnwrap(model.confirmedReceipt)
        let roll=try XCTUnwrap(staged.dice.first{$0.source=="damage"})
        XCTAssertEqual(roll.formula,DiceFormula(sides:20,count:1,flat:6))
        XCTAssertEqual(roll.values.count,1)
        let dice=BattleDice.channels(.dragonFlame,actor:before.units["p1"]!,target:before.units["m1"]!,catalog:model.engine.catalog,receipt:staged)
        XCTAssertEqual(dice.map(\.color),["red","yellow","green","blue","yellow"])
        XCTAssertEqual(dice.map(\.sides),[20,0,0,0,0])
        XCTAssertEqual(dice.compactMap(\.value),[roll.values[0],6,6,6,2])

        let receipt=try XCTUnwrap(model.commit(intent.id))
        XCTAssertEqual(receipt,staged)
        XCTAssertEqual(receipt.after.units["p1"]?.health,26)
        XCTAssertEqual(receipt.after.units["p1"]?.shield,6)
        XCTAssertEqual(receipt.after.units["p1"]?.damageBuff?.amount,2)
        XCTAssertEqual(receipt.after.units["p1"]?.damageBuff?.roundsLeft,2)
        XCTAssertEqual(receipt.after.units["p1"]?.ap,1)
        XCTAssertEqual(receipt.after.units["p1"]?.skillUses["dragonFlame"],1)
        for id in ["m1","m2"] {
            // The staged roll total already includes the skill's +6 flat bonus.
            XCTAssertEqual(before.units[id]!.health-receipt.after.units[id]!.health,min(18,roll.total))
            XCTAssertEqual(receipt.after.units[id]?.shield,0)
        }
        XCTAssertNil(try model.commit(intent.id),"one confirmed action must never commit twice")
    }

    func testDragonFlameSpriteSequenceStartsAtImpactAndKeepsOneAnchor() throws {
        let model=try PartyEncounter(seed:9,sessionID:"dragon-flame-sprite",playerClassID:"dragonKnight")
        try model.engine.apply(.endTurn(actor:"p2",timedOut:false))
        let intent=try XCTUnwrap(model.prepare(.dragonFlame,target:"m1"))
        let cues=SpellbladeEffects.recipients(intent,catalog:model.engine.catalog)
        XCTAssertEqual(cues.map(\.unitID),["p1"])
        let before=SpellbladeEffects.sample(action:.dragonFlame,age:PartyAction.dragonFlame.impact-0.001,actor:"p1",target:"m1",recipients:cues,targets:intent.targets)
        XCTAssertTrue(before.spriteLayers.isEmpty && before.glows.isEmpty && before.motes.isEmpty)

        let hit=SpellbladeEffects.sample(action:.dragonFlame,age:PartyAction.dragonFlame.impact,actor:"p1",target:"m1",recipients:cues,targets:intent.targets)
        XCTAssertEqual(hit.spriteLayers.count,2)
        XCTAssertEqual(Set(hit.spriteLayers.map(\.asset)),Set(["MeadowDragonFlame01"]))
        XCTAssertTrue(hit.spriteLayers.allSatisfy{$0.size==280 && $0.alpha==1})
        for (layer,id) in zip(hit.spriteLayers,["m1","m2"]) {
            let expected=PartyVisual.hitPoint(target:id)
            XCTAssertEqual(layer.center.x,expected.x)
            XCTAssertEqual(layer.center.y,expected.y)
        }
        XCTAssertTrue(hit.glows.isEmpty,"light should fade in smoothly from the exact hit frame")
        let lit=SpellbladeEffects.sample(action:.dragonFlame,age:PartyAction.dragonFlame.impact+0.06,actor:"p1",target:"m1",recipients:cues,targets:intent.targets)
        XCTAssertEqual(lit.glows.count,8)
        XCTAssertTrue(lit.glows.allSatisfy{$0.color.hasPrefix("fire") && $0.alpha.isFinite && $0.alpha>0})

        let burst=SpellbladeEffects.sample(action:.dragonFlame,age:PartyAction.dragonFlame.impact+0.74,actor:"p1",target:"m1",recipients:cues,targets:intent.targets)
        XCTAssertTrue(burst.spriteLayers.contains{$0.asset=="MeadowDragonFlame12" || $0.asset=="MeadowDragonFlame13"})
        XCTAssertTrue(burst.motes.contains{$0.color=="fireRed" || $0.color=="fireOrange" || $0.color=="fireGold"})
        XCTAssertTrue(burst.glows.contains{$0.rx>=120 && $0.ry>=100},"warm light must reach beyond the impact pixel")

        var groundContacts=0
        for n in 0...118 {
            let age=PartyAction.dragonFlame.impact+Double(n)/60
            let sample=SpellbladeEffects.sample(action:.dragonFlame,age:age,actor:"p1",target:"m1",recipients:cues,targets:intent.targets)
            for mote in sample.motes {
                XCTAssertTrue(mote.alpha.isFinite && (0...1).contains(mote.alpha))
                XCTAssertTrue(mote.point.x.isFinite && mote.point.y.isFinite)
                if let contact=mote.groundAge { XCTAssertTrue((0...0.23).contains(contact));groundContacts+=1 }
            }
        }
        XCTAssertGreaterThan(groundContacts,0,"embers should visibly hit the floor")
        let finished=SpellbladeEffects.sample(action:.dragonFlame,age:PartyAction.dragonFlame.impact+1.95,actor:"p1",target:"m1",recipients:cues,targets:intent.targets)
        XCTAssertTrue(finished.spriteLayers.isEmpty && finished.glows.isEmpty && finished.motes.isEmpty)
        XCTAssertEqual(PartyVisual.travel(intent,age:1).x,0)
        XCTAssertEqual(PartyVisual.pose(unit:model.state.units["p1"]!,intent:intent,age:0.4,time:0).clip,"guard")
    }
}
