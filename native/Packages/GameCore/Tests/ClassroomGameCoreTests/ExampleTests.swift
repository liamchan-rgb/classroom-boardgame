import XCTest
@testable import ClassroomGameCore

final class ExampleTests: XCTestCase {
    func testAllTeacherExamplesRunTheRealEngineAndMeetTheirChecks() throws {
        let catalog = try GameCatalog.initial()
        for example in RuleExample.allCases {
            let first = try example.run(catalog: catalog)
            XCTAssertFalse(first.checks.isEmpty)
            for check in first.checks { XCTAssertTrue(check.passed, "\(example.title)：\(check.title)") }
            let repeated = try example.run(catalog: catalog)
            XCTAssertEqual(first.before, repeated.before)
            XCTAssertEqual(first.after, repeated.after)
            XCTAssertEqual(first.undone, repeated.undone)
            if example == .groupUndo { XCTAssertEqual(first.before, first.undone) }
        }
    }
}
