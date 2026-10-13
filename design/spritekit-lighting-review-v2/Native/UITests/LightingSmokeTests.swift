import XCTest

final class LightingSmokeTests: XCTestCase {
    private func capture(_ ratio: String) {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--reduce-motion", "--lighting=flat"]
        app.launchEnvironment["PROTOTYPE_RATIO"] = ratio; app.launch()
        let play = app.buttons["play-demo"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        attach(app, "original-\(ratio)")
        let mode = app.buttons["lighting-mode"]; mode.tap()
        XCTAssertEqual(mode.value as? String, "太阳光影")
        attach(app, "sunlight-\(ratio)")
        play.tap()
        let arrived = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'node-2'"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 10), .completed)
        attach(app, "arrival-reduced-motion-\(ratio)")
        mode.tap(); XCTAssertEqual(mode.value as? String, "局部光照")
        attach(app, "local-light-\(ratio)")
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testWideSceneModes() { capture("16x9") }
    func testStandardSceneModes() { capture("4x3") }
}
