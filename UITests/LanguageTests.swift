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
        reveal(german)
        try shot("languages")

        german.tap()
        if app.buttons["Cancel Deutsch"].waitForExistence(timeout: 2) { try shot("downloading") }
        XCTAssertTrue(becomes(german, selected: true, within: 120), "Deutsch wasn't picked once it downloaded")
        XCTAssertTrue(layoutRow.label.contains("German"))
        try shot("downloaded")

        layoutRow.tap()
        app.buttons["QWERTY"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["QWERTY"].waitForExistence(timeout: 5))
        try shot("qwerty")
        layoutRow.tap()
        app.buttons["German"].firstMatch.tap()

        row("English").tap()
        XCTAssertTrue(becomes(row("English"), selected: true, within: 5))
        XCTAssertTrue(app.buttons["Remove Deutsch"].waitForExistence(timeout: 5))
        try shot("remove")
        app.buttons["Remove Deutsch"].tap()
        XCTAssertTrue(app.buttons["Download Deutsch"].waitForExistence(timeout: 5))
        XCTAssertTrue(row("English").isSelected)
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

    /// Scrolls until the row sits in the window's lower half, with the rows above it in view.
    private func reveal(_ row: XCUIElement) {
        let window = app.windows.firstMatch.frame
        let middle = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        for _ in 0..<8 where row.frame.maxY > window.maxY - 120 {
            middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -120)))
        }
    }

    private func shot(_ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["IIKB_SHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(
            to: URL(fileURLWithPath: "\(folder)/language-\(name).png"))
    }
}
