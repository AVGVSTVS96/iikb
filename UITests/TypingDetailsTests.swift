import XCTest

/// Raycast's typing details through the real extension: a number hint's hold, the period's web endings, sliding from
/// delete and the emoji key's emoji.
final class TypingDetailsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testHoldingAHintedLetterTypesItsDigit() {
        let app = launchDetails(["-iikbNumberHints", "YES"])
        key("w", in: app).press(forDuration: 1)
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "2")
    }

    @MainActor func testHoldingTheAddressPeriodTypesDotCom() {
        let app = launchDetails(["-FullKeyboardType", "7", "-iikbText", "me@mail"])
        key(".", in: app).press(forDuration: 1)
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "me@mail.com")
    }

    /// The slide's first word is the 4 delete took as it went down, a step that changes nothing; holding on after the
    /// second word, delete's repeat must stay stopped.
    @MainActor func testSlidingFromDeleteTakesWholeWords() {
        let app = launchDetails(["-iikbText", "one two three 4"])
        let delete = key("delete", in: app)
        let start = delete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: -delete.frame.width * 1.8, dy: 0)),
            withVelocity: 200, thenHoldForDuration: 2)
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "one two ")
    }

    @MainActor func testHoldingEmojiOffersEmojiAboveTheMenu() {
        let app = launchDetails()
        let emoji = key("emoji", in: app)
        let start = emoji.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -emoji.frame.height * 2.4)),
            withVelocity: 150, thenHoldForDuration: 0.3)
        let typed = app.textViews.firstMatch.value as? String ?? ""
        XCTAssertTrue(typed.unicodeScalars.contains { $0.properties.isEmojiPresentation }, "typed \(typed)")
        XCTAssertTrue(key("space", in: app).exists, "the keys stay up")
    }

    /// With emoji above it, the menu row still ends in the gear, which opens iikb's keyboard settings and so takes the
    /// keys down.
    @MainActor func testTheEmojiHoldStillReachesSettings() {
        let app = launchDetails()
        let emoji = key("emoji", in: app)
        let start = emoji.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: 200, dy: -emoji.frame.height * 0.5)),
            withVelocity: 300, thenHoldForDuration: 0.3)
        let gone = NSPredicate(format: "exists == false")
        let wait = expectation(for: gone, evaluatedWith: key("space", in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 5), .completed, "the gear left the field")
    }
}

/// The same details held while scripts/menushots (CLASS=TypingDetailsShots) shoots each screen of the Duo: each pose
/// is left as `<prefix>-<name>.hold`, holding the seconds to wait before the shot.
final class TypingDetailsShots: XCTestCase {
    @MainActor func testHeldDetails() throws {
        let environment = ProcessInfo.processInfo.environment
        let prefix = try XCTUnwrap(environment["IIKB_SHOTS"])
        try XCTSkipUnless(prefix.contains("/details/"), "only scripts/menushots shoots these")
        continueAfterFailure = false
        let orientation = environment["IIKB_ORIENTATION"] ?? "portrait"
        let launch = { (more: [String]) in launchDetails(["-iikbOrientation", orientation] + more) }

        var app = launch(["-iikbNumberHints", "YES", "-iikbText", "Coffee at noon with the team "])
        shoot("\(prefix)-hints")
        let w = key("w", in: app)
        shoot("\(prefix)-hint-hold", after: 1.5) { w.press(forDuration: 3) }
        let emoji = key("emoji", in: app)
        shoot("\(prefix)-emoji-hold", after: 1.5) { emoji.press(forDuration: 3) }
        let delete = key("delete", in: app)
        let start = delete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        shoot("\(prefix)-delete-slide", after: 3) {
            start.press(
                forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: -delete.frame.width * 1.8, dy: 0)),
                withVelocity: 200, thenHoldForDuration: 5)
        }
        app.terminate()

        app = launch(["-FullKeyboardType", "7", "-iikbText", "me@mail"])
        let period = key(".", in: app)
        shoot("\(prefix)-endings", after: 1.5) { period.press(forDuration: 3) }
        app.terminate()

        app = launch(["-iikbCurrency", "euro"])
        key("numbers", in: app).tap()
        shoot("\(prefix)-currency")
        app.terminate()

        for layout in ["dvorak", "colemak", "workman"] {
            app = launch(["-iikbLayout", layout])
            shoot("\(prefix)-\(layout)")
            app.terminate()
        }
        _ = launch(["-iikbLayout", "", "-iikbCurrency", "automatic"])
    }

    /// Leaves `<name>.hold` for the script, then holds while it waits `after` seconds and shoots, and waits for it.
    private func shoot(_ name: String, after seconds: Double = 1, _ hold: () -> Void = {}) {
        FileManager.default.createFile(atPath: "\(name).hold", contents: Data("\(seconds)".utf8))
        hold()
        let gone = Date().addingTimeInterval(10)
        while FileManager.default.fileExists(atPath: "\(name).hold"), Date() < gone {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}

@MainActor private func launchDetails(_ arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
        ["-iikbFocus", "YES", "-iikbResetSettings", "YES", "-iikbAutoCorrection", "NO"] + arguments
    app.launchWithIikb()
    return app
}

private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
    app.keys.matching(identifier: "iikb.\(name)").firstMatch
}
