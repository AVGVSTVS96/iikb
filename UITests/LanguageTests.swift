import XCTest

/// A language downloaded on Settings › Languages and typed and swiped along with English, on a layout picked there,
/// then let go and removed, which leaves English.
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
        // A fast network can finish it before Cancel is looked for.
        XCTAssertTrue(
            app.buttons["Cancel Deutsch"].waitForExistence(timeout: 5) || app.buttons["Remove Deutsch"].exists,
            "row: \(german.label), Try Again: \(app.buttons["Try Again Deutsch"].exists)")
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
        XCTAssertTrue(row("English").isSelected, "English is typed along with it")
        XCTAssertTrue(layoutRow.label.contains("QWERTY"), "the layout that was up stays")
        try shot("downloaded")

        reveal(layoutRow)
        layoutRow.tap()
        app.buttons["German"].firstMatch.tap()
        XCTAssertTrue(layoutRow.label.contains("German"))
        top()
        try shot("german")

        german.tap()
        XCTAssertTrue(becomes(german, selected: false, within: 5))
        XCTAssertTrue(layoutRow.label.contains("QWERTY"), "German's layout goes with it")
        row("English").tap()
        XCTAssertTrue(row("English").isSelected, "one language always stays")
        XCTAssertTrue(app.buttons["Remove Deutsch"].waitForExistence(timeout: 5))
        reveal(german)
        try shot("remove")
        app.buttons["Remove Deutsch"].tap()
        XCTAssertTrue(app.buttons["Download Deutsch"].waitForExistence(timeout: 5))
        XCTAssertTrue(row("English").isSelected)
        for _ in 0..<4 { app.windows.firstMatch.swipeUp(velocity: .fast) }
        try shot("end")
    }

    /// English and German typed and swiped on German's keys with no switching. The keyboard types both from one file
    /// of their words, which the app puts together after the pick, or as it opens again if it was closed before that
    /// was done: until then a German slip is read as English, so each is typed once, since one kept twice is a word
    /// of yours.
    func testTypesTheLanguagesPickedAtOnce() throws {
        app.launchArguments = ["-iikbResetSettings", "YES", "-iikbSettings", "languages"]
        app.launch()
        let german = row("Deutsch")
        XCTAssertTrue(german.waitForExistence(timeout: 10))
        german.tap()
        XCTAssertTrue(becomes(german, selected: true, within: 120), "Deutsch wasn't picked once it downloaded")
        reveal(layoutRow)
        layoutRow.tap()
        app.buttons["German"].firstMatch.tap()
        XCTAssertTrue(layoutRow.label.contains("German"))
        app.terminate()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbAutoCorrection", "YES"]
        app.launchWithIikb()
        XCTAssertLessThan(key("z").frame.midY, key("a").frame.midY, "German's z isn't in the top row")
        let field = app.textViews.firstMatch
        type("teh ")
        XCTAssertEqual(text(field), "The ")
        for slip in ["nicjt", "nivht", "nixht", "nicgt", "nichr", "nocht"] where !text(field).hasSuffix(" nicht ") {
            type("\(slip) ")
            if !text(field).hasSuffix(" nicht ") { Thread.sleep(forTimeInterval: 10) }
        }
        XCTAssertTrue(text(field).hasSuffix(" nicht "), "typed: \(text(field))")
        try swipe(through: ["ü", "b", "e", "r"])
        let swiped = NSPredicate(format: "value ENDSWITH ' nicht über'")
        XCTAssertTrue(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: swiped, object: field)], timeout: 5)
                == .completed,
            "swiped on German's ü key: \(text(field))")
        try shot("typed")
    }

    private func text(_ field: XCUIElement) -> String {
        field.value as? String ?? ""
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

    /// A finger sliding from key to key, 6 points every 10 ms.
    private func swipe(through keys: [String]) throws {
        let centers = keys.map { key($0).frame }.map { CGPoint(x: $0.midX, y: $0.midY) }
        let finger = XCPointerEventPath(forTouchAt: centers[0], offset: 0.05)
        var time = 0.05
        for (from, to) in zip(centers, centers.dropFirst()) {
            let steps = max(Int(hypot(to.x - from.x, to.y - from.y) / 6), 1)
            for step in 1...steps {
                time += 0.01
                let share = Double(step) / Double(steps)
                finger.move(
                    to: CGPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share),
                    atOffset: time)
            }
        }
        finger.liftUp(atOffset: time + 0.02)
        let record = XCSynthesizedEventRecord(name: keys.joined(), interfaceOrientation: .portrait)
        record.add(finger)
        try record.synthesize()
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
