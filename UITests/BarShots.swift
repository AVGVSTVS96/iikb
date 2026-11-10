import XCTest

/// The bar with Predictive Text off, upright and sideways, on a simulator or an iPhone (`TEST=BarShots
/// scripts/chatdevice`): screenshots of GIFs, Transcripts and Clipboard after More, and where the top row's keys sit
/// against the screen's width. Predictive Text is turned back on at the end.
final class BarShots: XCTestCase {
    override func tearDown() {
        let app = XCUIApplication()
        app.launchArguments = ["-iikbPredictiveText", "YES"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testSuggestionsOff() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbPredictiveText", "NO"]
        XCUIDevice.shared.orientation = .portrait
        app.launchWithIikb()
        for name in ["t", "h", "e"] { key(name, in: app).tap() }
        XCTAssertTrue(element("iikb.tool.clipboard", in: app).waitForExistence(timeout: 5), "the panels are in the bar")
        XCTAssertFalse(element("iikb.suggestion.1", in: app).isHittable, "no suggestions show")
        Thread.sleep(forTimeInterval: 1)
        shot("portrait", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        shot("landscape", app: app)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.keys.matching(identifier: "iikb.\(name)").firstMatch
    }

    /// The screenshot, and beside it the screen's width and where the top row's first and last keys sit on it.
    private func shot(_ name: String, app: XCUIApplication) {
        let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        picture.name = name
        picture.lifetime = .keepAlways
        add(picture)
        let screen = app.windows.firstMatch.frame
        let q = key("q", in: app).frame
        let p = key("p", in: app).frame
        let numbers = XCTAttachment(
            string: "screen \(screen.width) × \(screen.height); q from \(q.minX), p to \(p.maxX); "
                + "left of q \(q.minX), right of p \(screen.width - p.maxX)")
        numbers.name = "\(name)-geometry"
        numbers.lifetime = .keepAlways
        add(numbers)
    }
}
