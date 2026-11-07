import XCTest
import ClassroomGameCore
@testable import MeadowBattleSupport

final class PolyDiceTests:XCTestCase {
    func testClosedConvexPolyhedraHaveCorrectFacesAndNumbers() throws {
        for sides in PolyhedralDice.supported {
            let mesh=try XCTUnwrap(PolyhedralDice.mesh(sides))
            XCTAssertEqual(mesh.faces.count,sides);XCTAssertEqual(Set(mesh.faces.map(\.value)),Set(1...sides))
            var edges:[String:Int]=[:]
            for f in mesh.faces {
                XCTAssertGreaterThan(f.normal.dot(f.center),0)
                for i in f.indices.indices {
                    let a=f.indices[i],b=f.indices[(i+1)%f.indices.count]
                    let key="\(min(a,b))/\(max(a,b))";edges[key,default:0] += 1
                }
                for i in f.indices { XCTAssertEqual((mesh.vertices[i]-f.center).dot(f.normal),0,accuracy:1e-6) }
            }
            XCTAssertTrue(edges.values.allSatisfy { $0==2 });XCTAssertEqual(mesh.vertices.count-edges.count+mesh.faces.count,2)
        }
    }
    func testEveryResultLandsOnItsOwnFaceAndNumbersStayAttached() throws {
        for sides in PolyhedralDice.supported {
            let mesh=try XCTUnwrap(PolyhedralDice.mesh(sides))
            for value in 1...sides {
                let die=BattleDie("red",sides:sides,value:value,label:"D\(sides)")
                let settled=PolyhedralDice.sample(die:die,time:3,index:0,count:1,resolvedAge:0.8,visibleAge:3)
                XCTAssertEqual(settled.faces.max(by: { $0.depth<$1.depth })?.value,value)
                XCTAssertTrue(settled.faces.allSatisfy { face in mesh.faces.contains(where: { $0.value==face.value }) })
                XCTAssertTrue(settled.faces.flatMap(\.points).allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x)<1.5 && abs($0.y)<1.5 })
            }
        }
    }
    func testRotationFlipsFacesAndContinuesThroughReceiptWithoutJump() {
        let die=BattleDie("red",sides:20,value:17,label:"D20")
        let a=PolyhedralDice.sample(die:die,time:1,index:0,count:1,resolvedAge:nil,visibleAge:1)
        let b=PolyhedralDice.sample(die:die,time:1.000001,index:0,count:1,resolvedAge:0,visibleAge:1)
        XCTAssertEqual(a.orientation.w,b.orientation.w,accuracy:1e-5)
        XCTAssertEqual(a.orientation.x,b.orientation.x,accuracy:1e-5)
        let c=PolyhedralDice.sample(die:die,time:1.3,index:0,count:1,resolvedAge:nil,visibleAge:1)
        XCTAssertNotEqual(a.faces.map(\.value),c.faces.map(\.value))
        let p=a.faces[0].points[0],q=c.faces[0].points[0]
        XCTAssertGreaterThan(abs(p.x-q.x)+abs(p.y-q.y),0.05)
        let stop=PolyhedralDice.sample(die:die,time:2,index:0,count:1,resolvedAge:1,visibleAge:2)
        let held=PolyhedralDice.sample(die:die,time:2.001,index:0,count:1,resolvedAge:1.001,visibleAge:2)
        XCTAssertEqual(stop.orientation.w,held.orientation.w,accuracy:1e-10)
    }
    func testPreviewUsesActualWeaponDiceAndAllSkillDiceRatherThanD6Fallback() throws {
        let p=try PartyEncounter(seed:48),catalog=p.engine.catalog;var actor=p.state.units["p1"]!;let target=p.state.units["m1"]!
        for (item,sides) in [("trainingSword",6),("huntingBow",8),("greatSword",12),("legendaryStaff",20)] {
            actor.equipment.weapon=item
            let dice=BattleDice.channels(.attack,actor:actor,target:target,catalog:catalog)
            XCTAssertEqual(dice.first?.sides,sides);XCTAssertNil(dice.first?.value)
        }
        let ambush=BattleDice.skillChannels("ambush",actor:actor,catalog:catalog)
        XCTAssertEqual(ambush.filter { $0.sides>0 }.map(\.sides),[8,8])
        XCTAssertEqual(ambush.first(where: { $0.label=="固定加值" })?.sides,0)
        let rune=BattleDice.skillChannels("runeSlash",actor:actor,catalog:catalog)
        XCTAssertEqual(rune.filter { $0.sides>0 }.map(\.sides),[12,12])
    }
    func testWeaponReceiptValuesAndFixedBuffRemainSeparate() throws {
        let p=try PartyEncounter(seed:48)
        let buff=p.prepare(.rally,target:"p1")!;_ = try p.commit(buff.id)
        var state=p.state;state.units["p1"]?.equipment.weapon="huntingBow";state.battle?.queue=["p1","p2","m1","m2"];state.battle?.current="p1"
        let engine=try GameEngine(catalog:p.engine.catalog,state:state)
        let receipt=try engine.apply(.attack(actor:"p1",target:"m1"))
        let dice=BattleDice.channels(.attack,actor:state.units["p1"]!,target:state.units["m1"]!,catalog:p.engine.catalog,receipt:receipt)
        XCTAssertEqual(dice.map(\.sides),[8,0]);XCTAssertEqual(dice.first?.value,receipt.dice.first?.values.first);XCTAssertEqual(dice.last?.value,2)
        XCTAssertEqual(dice.last?.color,"yellow");XCTAssertEqual(dice.last?.label,"固定增伤")
    }
}

extension PolyDiceTests {
    func testRolledHealingUsesItsOwnD4FormulaWithoutInventingD6() throws {
        let p=try PartyEncounter(seed:51);var catalog=p.engine.catalog,state=p.state
        let index=try XCTUnwrap(catalog.skills.firstIndex { $0.id=="breather" })
        catalog.skills[index].effects[0].dice=DiceFormula(sides:4)
        state.battle?.queue=["p1","p2","m1","m2"];state.battle?.current="p1"
        let engine=try GameEngine(catalog:catalog,state:state)
        let receipt=try engine.apply(.cast(actor:"p1",skill:"breather",target:.unit("p1")))
        let dice=BattleDice.channels(.breather,actor:state.units["p1"]!,target:state.units["p1"]!,catalog:catalog,receipt:receipt)
        XCTAssertEqual(dice.first?.color,"green");XCTAssertEqual(dice.first?.sides,4)
        XCTAssertEqual(dice.first?.value,receipt.dice.first?.values.first)
        XCTAssertEqual(dice.last?.sides,0);XCTAssertEqual(dice.last?.value,4)
        XCTAssertEqual(try GameCatalog.initial().skill("breather").effects[0].dice,nil)
    }
}
