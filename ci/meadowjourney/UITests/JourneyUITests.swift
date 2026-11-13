import XCTest

final class JourneyUITests: XCTestCase {
    func testPlaybackResetZoomAndCapture() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-visualReview"]
        app.launch()
        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        capture("01-reference-layout")
        XCTAssertEqual(play.label, "开始行旅")
        play.tap()
        XCTAssertEqual(play.label, "暂停行旅")
        // Give the characters enough time to travel a visible distance.
        let traveled = expectation(description: "Visible route movement")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { traveled.fulfill() }
        waitForExpectations(timeout: 3)
        capture("02-traveling")
        play.tap()
        XCTAssertEqual(play.label, "开始行旅")
        let zoom = app.buttons["zoomButton"]
        zoom.tap()
        XCTAssertEqual(zoom.value as? String, "125%")
        capture("03-zoomed")
        app.buttons["resetButton"].tap()
        XCTAssertEqual(zoom.value as? String, "100%")
        XCTAssertEqual(play.label, "开始行旅")
        capture("04-reset")
        let metrics = diagnostics(app)
        XCTAssertGreaterThan(metrics["independentProps"] as? Int ?? 0, 140)
        XCTAssertEqual(metrics["roads"] as? Int, 4)
        print("SCENE_METRICS", app.otherElements["meadowMap"].value ?? "missing")

        let heroes = metrics["heroTargets"] as! [[String: Double]]
        tap(app, at: heroes[0])
        tap(app, at: diagnostics(app)["orderPoint"] as! [String: Double])
        XCTAssertEqual(play.label, "暂停行旅")
        XCTAssertEqual(diagnostics(app)["mode"] as? String, "destination")
        let destination = diagnostics(app)["goal"] as! [String: Double]
        play.tap()
        XCTAssertEqual(play.label, "开始行旅")
        play.tap()
        let resumed = diagnostics(app)
        XCTAssertEqual(resumed["mode"] as? String, "destination")
        XCTAssertEqual(resumed["goal"] as! [String: Double], destination)
        capture("05-ordered-journey")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func diagnostics(_ app: XCUIApplication) -> [String: Any] {
        let text = app.otherElements["meadowMap"].value as! String
        return try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    private func tap(_ app: XCUIApplication, at point: [String: Double]) {
        app.otherElements["meadowMap"].coordinate(withNormalizedOffset:
            CGVector(dx: point["x"]!, dy: point["y"]!)).tap()
    }
}
