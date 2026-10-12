import XCTest
@testable import ClassroomProbeCore

final class ProbeCoreTests: XCTestCase {
    func testPauseReasonsRemainIndependentAndTimeFreezes() {
        var state = ProbeState()
        state.setPause(.notes, enabled: true)
        state.setPause(.notes, enabled: false)
        XCTAssertEqual(state.pauseReasons, [.manual])
        state.advanceClock(by: 13)
        XCTAssertEqual(state.remainingSeconds, 30)
        state.toggleManualPause()
        state.advanceClock(by: 13)
        XCTAssertEqual(state.remainingSeconds, 17)
        state.setPause(.notes, enabled: true)
        state.advanceClock(by: 100)
        state.setPause(.notes, enabled: false)
        XCTAssertEqual(state.remainingSeconds, 17)
    }

    func testBackupRoundTripIncludesAssetsButRestoresPaused() throws {
        var state = ProbeState()
        state.pageCount = 3
        state.pageIndex = 2
        state.selectedPlayerID = 7
        state.awardCoins()
        state.toggleManualPause()
        state.advanceClock(by: 13)
        let backup = ProbeBackup(state: state, pptxData: Data([1, 2, 3]), sourceName: "fixture.pptx",
                                 editedNotes: [2: "PRIVATE-NOTES"])
        let restored = try ProbeBackup.decoded(backup.encoded())
        XCTAssertEqual(restored.state.players[6].coins, 10)
        XCTAssertEqual(restored.state.pageIndex, 2)
        XCTAssertEqual(restored.state.remainingSeconds, 17)
        XCTAssertEqual(restored.state.pauseReasons, [.manual])
        XCTAssertEqual(restored.editedNotes[2], "PRIVATE-NOTES")
        XCTAssertEqual(restored.pptxData, Data([1, 2, 3]))
        let publicJSON = try JSONEncoder().encode(restored.state.publicSnapshot)
        XCTAssertFalse(String(decoding: publicJSON, as: UTF8.self).contains("PRIVATE-NOTES"))
    }

    func testInvalidBackupIsRejectedBeforeUse() throws {
        var state = ProbeState()
        state.players[0].coins = -1
        let backup = ProbeBackup(state: state, pptxData: nil, sourceName: nil, editedNotes: [:])
        XCTAssertThrowsError(try ProbeBackup.decoded(backup.encoded()))
        state.players[0].coins = 0
        state.players[0].score = Int.min
        XCTAssertThrowsError(try ProbeBackup.decoded(ProbeBackup(state: state, pptxData: nil, sourceName: nil, editedNotes: [:]).encoded()))
    }

    func testActualPPTXOrderImagesEmptyAndLongNotes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "pptx", subdirectory: "Fixtures"))
        let deck = try PPTXReader.read(Data(contentsOf: url))
        XCTAssertEqual(deck.slides.count, 3)
        XCTAssertTrue(deck.slides[0].plainText.hasPrefix("图文测试页"))
        XCTAssertTrue(deck.slides[1].plainText.hasPrefix("空备注测试页"))
        XCTAssertTrue(deck.slides[2].plainText.hasPrefix("长备注测试页"))
        XCTAssertTrue(deck.slides[0].notes.contains("PRIVATE-FIXTURE-8642"))
        XCTAssertEqual(deck.slides[1].notes, "")
        XCTAssertEqual(deck.slides[2].notes, String(repeating: "教师测试长备注。", count: 400))
        XCTAssertEqual(deck.slides[0].elements.filter { if case .image = $0 { return true }; return false }.count, 1)
    }

    func testUnsafePathBadZipAndDTDRejected() throws {
        XCTAssertThrowsError(try PPTXReader.resolve(owner: "ppt/slides/slide1.xml", target: "../../../outside.xml"))
        XCTAssertThrowsError(try PPTXReader.read(Data("not a zip".utf8)))
        XCTAssertThrowsError(try XMLTree.read(Data("<!DOCTYPE a><a/>".utf8), part: "test.xml"))
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "pptx", subdirectory: "Fixtures"))
        var damaged = Array(try Data(contentsOf: fixture))
        var changed = false
        for offset in 0..<(damaged.count - 46) {
            guard Array(damaged[offset..<(offset + 4)]) == [0x50, 0x4b, 0x01, 0x02] else { continue }
            let length = Int(damaged[offset + 28]) + Int(damaged[offset + 29]) * 256
            guard offset + 46 + length <= damaged.count else { continue }
            let name = String(decoding: damaged[(offset + 46)..<(offset + 46 + length)], as: UTF8.self)
            if name == "ppt/presentation.xml" {
                damaged[offset + 16] ^= 1 // Corrupt only the central-directory CRC.
                changed = true
                break
            }
        }
        XCTAssertTrue(changed)
        XCTAssertThrowsError(try PPTXReader.read(Data(damaged)))
    }

    func testNotesExcludeSlideNumberAndFooter() throws {
        let xml = """
        <p:notes xmlns:p="urn:p" xmlns:a="urn:a"><p:sp><p:ph type="body"/><a:p><a:r><a:t>Teacher note</a:t></a:r></a:p></p:sp><p:sp><p:ph type="sldNum"/><a:p><a:r><a:t>999</a:t></a:r></a:p></p:sp></p:notes>
        """
        XCTAssertEqual(PPTXReader.extractNotes(try XMLTree.read(Data(xml.utf8), part: "notes.xml")), "Teacher note")
    }
}
