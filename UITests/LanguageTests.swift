import XCTest

/// A language downloaded on Settings › Languages, its layout picked there, typed with the keyboard, then removed, which
/// leaves English.
final class LanguageTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    func testDownloadsPicksAndRemovesALanguage() throws {
        app.launchArguments = ["-iikbResetSettings", "YES", "-iikbSettings", "languages"]
        app.launch()
        let german = row("Deutsch")
        XCTAssertTrue(german.waitForExistence(timeout: 10))
        if app.buttons["Remove Deutsch"].exists { app.buttons["Remove Deutsch"].tap() }
        XCTAssertTrue(app.buttons["Download Deutsch"].waitForExistence(timeout: 5))
        XCTAssertTrue(row("English").isSelected)
        top()
        try shot("languages")

        reveal(german)
        app.buttons["Download Deutsch"].tap()
        XCTAssertTrue(app.buttons["Cancel Deutsch"].waitForExistence(timeout: 5))
        let start = Date.now
        while app.buttons["Cancel Deutsch"].exists, Date.now.timeIntervalSince(start) < 20 {
            let label = german.label
            if label.contains("%"), !label.contains(" 0%"), !label.hasPrefix("0%") {
                try shot("downloading")
                break
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(german.label.contains("%") || !app.buttons["Cancel Deutsch"].exists, "row: \(german.label)")
        XCTAssertFalse(german.isSelected, "Download alone doesn't pick it")
        XCTAssertTrue(app.buttons["Cancel Deutsch"].waitForNonExistence(timeout: 120), "Deutsch didn't finish")

        german.tap()
        XCTAssertTrue(becomes(german, selected: true, within: 5))
        XCTAssertTrue(layoutRow.label.contains("German"))
        top()
        try shot("downloaded")

        layoutRow.tap()
        app.buttons["QWERTY"].firstMatch.tap()
        XCTAssertTrue(layoutRow.label.contains("QWERTY"))
        top()
        try shot("qwerty")
        layoutRow.tap()
        app.buttons["German"].firstMatch.tap()

        row("English").tap()
        XCTAssertTrue(becomes(row("English"), selected: true, within: 5))
        XCTAssertTrue(app.buttons["Remove Deutsch"].waitForExistence(timeout: 5))
        reveal(german)
        try shot("remove")
        app.buttons["Remove Deutsch"].tap()
        XCTAssertTrue(app.buttons["Download Deutsch"].waitForExistence(timeout: 5))
        XCTAssertTrue(row("English").isSelected)
        for _ in 0..<4 { app.windows.firstMatch.swipeUp(velocity: .fast) }
        try shot("end")
    }

    func testTypesTheLanguagePicked() throws {
        app.launchArguments = ["-iikbResetSettings", "YES", "-iikbSettings", "languages"]
        app.launch()
        let german = row("Deutsch")
        XCTAssertTrue(german.waitForExistence(timeout: 10))
        german.tap()
        XCTAssertTrue(becomes(german, selected: true, within: 120), "Deutsch wasn't picked once it downloaded")
        app.terminate()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbAutoCorrection", "YES"]
        app.launchWithIikb()
        XCTAssertLessThan(key("z").frame.midY, key("a").frame.midY, "German's z isn't in the top row")
        type("nicjt ")
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "Nicht ")
        try shot("typed")
    }

    private var layoutRow: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Keyboard Layout'")).firstMatch
    }

    private func row(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    private func becomes(_ element: XCUIElement, selected: Bool, within seconds: TimeInterval) -> Bool {
        let wanted = NSPredicate(format: "isSelected == %@", NSNumber(value: selected))
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: wanted, object: element)], timeout: seconds) == .completed
    }

    private func key(_ name: String) -> XCUIElement {
        app.keys.matching(identifier: "iikb.\(name)").firstMatch
    }

    private func type(_ text: String) {
        for character in text { key(character == " " ? "space" : String(character)).tap() }
    }

    /// Drags the page up slowly, so it stops where it's let go, until the row is in view above the tab bar.
    private func reveal(_ row: XCUIElement) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        for _ in 0..<6 where row.frame.maxY > window.frame.maxY * 0.8 {
            start.press(
                forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)), withVelocity: .slow,
                thenHoldForDuration: 0.3)
        }
    }

    /// Back to the top of the page, where the preview is.
    private func top() {
        let window = app.windows.firstMatch
        for _ in 0..<3 { window.swipeDown(velocity: .fast) }
    }

    private func shot(_ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["IIKB_SHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(
            to: URL(fileURLWithPath: "\(folder)/language-\(name).png"))
    }
}
