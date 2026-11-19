import XCTest
@testable import MeadowWorldSupport

final class DictionaryTests: XCTestCase {
    /// The dictionary bundled with the app (trimmed ECDICT).
    static let shared: ClassroomDictionary = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../ClassroomProbe/Resources/ecdict-classroom.tsv").standardized
        return try! ClassroomDictionary(contentsOf: url)
    }()
    func testWordsFormsAndSenses() throws {
        let d = Self.shared
        XCTAssertEqual(d.base(of: "went"), "go")
        XCTAssertEqual(d.base(of: "apples"), "apple")
        XCTAssertNil(d.base(of: "go"))
        let book = try XCTUnwrap(d.entry("book"))
        XCTAssertEqual(book.senses.first?.pos, "n.")
        // "She can book a room": a verb, so the verb senses come first.
        let ranked = ClassroomDictionary.ranked(book.senses, preferring: "Verb")
        XCTAssertEqual(ranked.first?.pos, "v."); XCTAssertTrue(ranked.first?.meanings.contains("预订") ?? false)
        XCTAssertEqual(d.entry("Went")?.word, "go")  // looked up by base form
    }
    func testUnfitMeaningsAreNeverOffered() throws {
        let d = Self.shared
        // Only the clean meaning is left: "Silly Willy" must not show the slang one.
        let willy = try XCTUnwrap(d.entry("willy")).senses.flatMap(\.meanings)
        XCTAssertFalse(willy.contains { ClassroomDictionary.isUnfit($0) })
        XCTAssertTrue(willy.contains { $0.contains("柳树") })
        XCTAssertTrue(try XCTUnwrap(d.entry("seed")).senses.flatMap(\.meanings).contains("种子"))
        XCTAssertFalse(try XCTUnwrap(d.entry("seed")).senses.flatMap(\.meanings).contains { ClassroomDictionary.isUnfit($0) })
        XCTAssertTrue(d.entry("penis")?.senses.isEmpty ?? true)
        // A phrase with only unfit meanings is not suggested.
        XCTAssertFalse(d.phrases(in: ["a", "blow", "job"], at: 2).contains { $0.phrase == "blow job" })
    }
    func testPhrasesAroundAWord() {
        let d = Self.shared
        let s1 = ["She", "looked", "after", "her", "little", "brother"]
        XCTAssertEqual(d.phrases(in: s1, at: 2).first?.phrase, "look after")
        XCTAssertEqual(d.phrases(in: s1, at: 2).first?.tokens, [1, 2])
        let s2 = ["Please", "pick", "it", "up", "now"]
        XCTAssertTrue(d.phrases(in: s2, at: 3).contains { $0.phrase == "pick up" && $0.tokens == [1, 3] })
        let s3 = ["They", "took", "part", "in", "the", "race"]
        XCTAssertEqual(d.phrases(in: s3, at: 2).first?.phrase, "take part in")
        XCTAssertTrue(d.phrases(in: ["a", "red", "apple"], at: 2).isEmpty)
    }
    func testParsesSensesFromALine() {
        let d = ClassroomDictionary(tsv: "book\tn. 书, 书籍 | v. 登记；预订\ts:books/d:booked\nlook after\t照顾, 关心\t\n")
        XCTAssertEqual(d.entry("booked")?.senses, [.init(pos: "n.", meanings: ["书", "书籍"]), .init(pos: "v.", meanings: ["登记", "预订"])])
        XCTAssertEqual(d.phrases(in: ["look", "after", "it"], at: 0).first?.phrase, "look after")
    }
}
