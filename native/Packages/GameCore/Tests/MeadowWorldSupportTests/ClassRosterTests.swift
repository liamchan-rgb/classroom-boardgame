import XCTest
import ClassroomGameCore
@testable import MeadowWorldSupport

final class ClassRosterTests:XCTestCase {
    private func store()->ClassRosterStore {
        ClassRosterStore(url:FileManager.default.temporaryDirectory.appendingPathComponent("rosters-\(UUID().uuidString)/classes.json"))
    }
    private let look=PlayerAppearance(body:"wayfarer",hair:PlayerAppearance.hairOptions[2],face:PlayerAppearance.faceOptions[1])

    func testSaveReadReplaceAndDelete()throws {
        let s=store()
        XCTAssertEqual(try s.all(),[])
        try s.save(ClassRoster(name:" 三年级二班 ",students:[.init(name:"Amy",appearance:look,classID:"ranger",team:1),.init(name:"Ben",classID:"spellblade")]))
        try s.save(ClassRoster(name:"一班",students:[.init(name:"Cat",classID:"adventurer")]))
        var all=try s.all()
        XCTAssertEqual(Set(all.map(\.name)),["一班","三年级二班"])
        let second=try XCTUnwrap(all.first{$0.name=="三年级二班"})
        XCTAssertEqual(second.students[0].appearance,look)
        XCTAssertEqual(second.students[0].team,1)
        XCTAssertEqual(second.teamCount,2)
        // Same name replaces.
        try s.save(ClassRoster(name:"一班",students:[.init(name:"Dan",classID:"dragonKnight"),.init(name:"Eve",classID:"ranger")]))
        all=try s.all()
        XCTAssertEqual(all.count,2)
        XCTAssertEqual(all.first{$0.name=="一班"}?.students.map(\.name),["Dan","Eve"])
        try s.delete("一班")
        XCTAssertEqual(try s.all().map(\.name),["三年级二班"])
    }

    func testValidationFixesOrRejects()throws {
        XCTAssertThrowsError(try ClassRoster(name:"  ",students:[.init(name:"A",classID:"ranger")]).validated()){XCTAssertEqual($0 as? ClassRosterError,.emptyName)}
        XCTAssertThrowsError(try ClassRoster(name:"x",students:[]).validated()){XCTAssertEqual($0 as? ClassRosterError,.noStudents)}
        let seven=(0..<7).map{ClassRoster.Student(name:"S\($0)",classID:"ranger")}
        XCTAssertThrowsError(try ClassRoster(name:"x",students:seven).validated()){XCTAssertEqual($0 as? ClassRosterError,.tooManyStudents)}
        let fixed=try ClassRoster(name:"x",students:[.init(name:"A",appearance:PlayerAppearance(body:"robot"),classID:"wizard",team:7)]).validated()
        XCTAssertNil(fixed.students[0].appearance)
        XCTAssertEqual(fixed.students[0].classID,"ranger")
        XCTAssertEqual(fixed.students[0].team,2)
        XCTAssertEqual(fixed.teamCount,3)
    }
}
