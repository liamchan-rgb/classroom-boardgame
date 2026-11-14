import XCTest
@testable import ClassroomGameCore

final class DisplayNameTests:XCTestCase {
    func testShortNameUsesGivenNameElseSeat()throws {
        let catalog=try GameCatalog.initial()
        var u=try GameFactory.player(id:"p2",name:"P2 · 游侠",classID:"ranger",teamID:"party",nodeID:0,catalog:catalog)
        XCTAssertEqual(u.shortName,"P2")
        u.name="小明";XCTAssertEqual(u.shortName,"小明")
        u.name="P2";XCTAssertEqual(u.shortName,"P2")
        let m=try GameFactory.monster(id:"m1",templateID:"wolf",nodeID:0,catalog:catalog)
        XCTAssertEqual(m.shortName,m.name)
    }
}
