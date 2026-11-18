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
        let styled = """
        <p:notes xmlns:p="urn:p" xmlns:a="urn:a"><p:sp><p:ph type="body"/><a:p><a:r><a:t>先读</a:t></a:r><a:r><a:rPr b="1"/><a:t>重点</a:t></a:r><a:r><a:rPr b="1"/><a:t>词</a:t></a:r><a:r><a:t>，再</a:t></a:r><a:r><a:rPr u="sng"/><a:t>划线</a:t></a:r><a:r><a:rPr u="none"/><a:t>结束</a:t></a:r></a:p></p:sp></p:notes>
        """
        XCTAssertEqual(PPTXReader.extractNotes(try XMLTree.read(Data(styled.utf8), part: "notes.xml")), "先读**重点词**，再__划线__结束")
    }

    func testAnimationBuildClicksEntryParagraphsAndTransition() throws {
        // Shape 3 fades in by itself, then click 1 flies shape 4 in from the left with its 2nd bullet zooming
        // in 0.5 s after it, click 2 wipes bullets 0–1 in from the bottom; shape 5 spins (emphasis) on click 2 too.
        let xml = """
        <p:sld xmlns:p="urn:p" xmlns:a="urn:a"><p:cSld><p:spTree/></p:cSld>
        <mc:AlternateContent xmlns:mc="urn:mc"><mc:Choice><p:transition spd="slow" p14:dur="1200" xmlns:p14="urn:p14"><p:push dir="u"/></p:transition></mc:Choice>
        <mc:Fallback><p:transition spd="slow"><p:push dir="u"/></p:transition></mc:Fallback></mc:AlternateContent>
        <p:timing><p:tnLst><p:par><p:cTn id="1" dur="indefinite" nodeType="tmRoot"><p:childTnLst>
        <p:seq concurrent="1" nextAc="seek"><p:cTn id="2" dur="indefinite" nodeType="mainSeq"><p:childTnLst>
          <p:par><p:cTn id="3" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>
            <p:par><p:cTn id="4" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>
              <p:par><p:cTn id="5" presetID="10" presetClass="entr" presetSubtype="0" fill="hold" nodeType="afterEffect"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>
                <p:set><p:cBhvr><p:cTn id="6" dur="1"/><p:tgtEl><p:spTgt spid="3"/></p:tgtEl></p:cBhvr></p:set>
                <p:animEffect transition="in" filter="fade"><p:cBhvr><p:cTn id="7" dur="750"/><p:tgtEl><p:spTgt spid="3"/></p:tgtEl></p:cBhvr></p:animEffect>
              </p:childTnLst></p:cTn></p:par>
            </p:childTnLst></p:cTn></p:par>
          </p:childTnLst></p:cTn></p:par>
          <p:par><p:cTn id="8" fill="hold"><p:stCondLst><p:cond delay="indefinite"/></p:stCondLst><p:childTnLst>
            <p:par><p:cTn id="9" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>
              <p:par><p:cTn id="10" presetID="2" presetClass="entr" presetSubtype="8" fill="hold" nodeType="clickEffect"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>
                <p:anim><p:cBhvr><p:cTn id="11" dur="500"/><p:tgtEl><p:spTgt spid="4"/></p:tgtEl></p:cBhvr></p:anim>
              </p:childTnLst></p:cTn></p:par>
            </p:childTnLst></p:cTn></p:par>
            <p:par><p:cTn id="12" fill="hold"><p:stCondLst><p:cond delay="500"/></p:stCondLst><p:childTnLst>
              <p:par><p:cTn id="13" presetID="53" presetClass="entr" presetSubtype="16" fill="hold" nodeType="afterEffect"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>
                <p:anim><p:cBhvr><p:cTn id="14" dur="400"/><p:tgtEl><p:spTgt spid="6"><p:txEl><p:pRg st="1" end="1"/></p:txEl></p:spTgt></p:tgtEl></p:cBhvr></p:anim>
              </p:childTnLst></p:cTn></p:par>
            </p:childTnLst></p:cTn></p:par>
          </p:childTnLst></p:cTn></p:par>
          <p:par><p:cTn id="15" fill="hold"><p:stCondLst><p:cond delay="indefinite"/></p:stCondLst><p:childTnLst>
            <p:par><p:cTn id="16" fill="hold"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>
              <p:par><p:cTn id="17" presetID="22" presetClass="entr" presetSubtype="4" fill="hold" nodeType="clickEffect"><p:stCondLst><p:cond delay="0"/></p:stCondLst><p:childTnLst>
                <p:animEffect transition="in" filter="wipe(up)"><p:cBhvr><p:cTn id="18" dur="500"/><p:tgtEl><p:spTgt spid="6"><p:txEl><p:pRg st="0" end="1"/></p:txEl></p:spTgt></p:tgtEl></p:cBhvr></p:animEffect>
              </p:childTnLst></p:cTn></p:par>
              <p:par><p:cTn id="19" presetID="8" presetClass="emph" presetSubtype="0" fill="hold" nodeType="withEffect"><p:stCondLst><p:cond delay="250"/></p:stCondLst><p:childTnLst>
                <p:animRot by="21600000"><p:cBhvr><p:cTn id="20" dur="2000"/><p:tgtEl><p:spTgt spid="5"/></p:tgtEl></p:cBhvr></p:animRot>
              </p:childTnLst></p:cTn></p:par>
            </p:childTnLst></p:cTn></p:par>
          </p:childTnLst></p:cTn></p:par>
        </p:childTnLst></p:cTn></p:seq></p:childTnLst></p:cTn></p:par></p:tnLst></p:timing></p:sld>
        """
        let root = try XMLTree.read(Data(xml.utf8), part: "slide.xml")
        var warnings: [String] = []
        let build = PPTXAnimations.build(root, warnings: &warnings)
        XCTAssertEqual(build.entry.count, 1)
        XCTAssertEqual(build.entry[0].target, SlideAnimationTarget(shapeID: 3))
        XCTAssertEqual(build.entry[0].style, "fade"); XCTAssertEqual(build.entry[0].duration, 0.75, accuracy: 1e-9)
        XCTAssertEqual(build.clicks.count, 2)
        XCTAssertEqual(build.clicks[0].map(\.style), ["fly", "zoom"])
        XCTAssertEqual(build.clicks[0][0].direction, "left")
        XCTAssertEqual(build.clicks[0][1].target, SlideAnimationTarget(shapeID: 6, paragraphs: 1...1))
        XCTAssertEqual(build.clicks[0][1].delay, 0.5, accuracy: 1e-9)
        XCTAssertEqual(build.clicks[1][0].style, "wipe"); XCTAssertEqual(build.clicks[1][0].direction, "bottom")
        XCTAssertEqual(build.clicks[1][0].target.paragraphs, 0...1)
        XCTAssertEqual(build.clicks[1][1].kind, .emphasis); XCTAssertEqual(build.clicks[1][1].style, "spin")
        XCTAssertEqual(build.clicks[1][1].delay, 0.25, accuracy: 1e-9); XCTAssertEqual(build.clicks[1][1].duration, 2, accuracy: 1e-9)
        XCTAssertTrue(warnings.isEmpty)
        let transition = try XCTUnwrap(PPTXAnimations.transition(root))
        XCTAssertEqual(transition.style, "push"); XCTAssertEqual(transition.direction, "top")
        XCTAssertEqual(transition.duration, 1.2, accuracy: 1e-9)
        let still = try XMLTree.read(Data("<p:sld xmlns:p=\"urn:p\"><p:cSld/></p:sld>".utf8), part: "s.xml")
        XCTAssertTrue(PPTXAnimations.build(still, warnings: &warnings).isEmpty); XCTAssertNil(PPTXAnimations.transition(still))
    }
}
