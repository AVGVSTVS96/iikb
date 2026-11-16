import XCTest

/// Snippets and quicklinks through the real keyboard: the snippet key and a keyword expanding, the bar's keywords after
/// the prefix, an argument asked for in the form, and the Snippets panel from the menu. With IIKB_SHOTS set,
/// screenshots each step.
final class SnippetTypingTests: XCTestCase {
    private var app: XCUIApplication!
    private var shots: String?
    private let kept =
        #"{"snippets":[{"id":"t-addr","name":"Address","text":"1 Infinite Loop","keyword":"!addr","tag":""},"#
        + #"{"id":"t-hi","name":"Greeting","text":"Hi {argument name=\"Name\"}, see you in {argument name=\"City\" default=\"Paris\"}.","keyword":"!hi","tag":"work"}],"#
        + #""quicklinks":[{"id":"t-search","name":"Search","link":"https://duckduckgo.com/?q={argument name=\"Query\"}"}]}"#

    override func setUp() {
        continueAfterFailure = false
        shots = ProcessInfo.processInfo.environment["IIKB_SHOTS"]
        app = XCUIApplication()
        app.launchArguments = [
            "-iikbSnippets", kept, "-iikbFocus", "YES", "-iikbAutoCapitalization", "NO", "-iikbAutoCorrection", "NO",
            "-iikbSnippetKey", "YES", "-iikbOneHanded", "off",
        ]
        app.launchWithIikb()
    }

    private var field: XCUIElement { app.textViews.firstMatch }

    func testAKeywordFromTheSnippetKeyExpandsAndAnArgumentIsAskedFor() throws {
        let snippetKey = key("snippet")
        XCTAssertTrue(snippetKey.waitForExistence(timeout: 5), "the bottom row has the snippet key")
        snippetKey.tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'iikb.suggestion.' AND label == '!addr'")
            ).firstMatch.waitForExistence(timeout: 5),
            "after the prefix the bar offers the keywords")
        try shot("snippet-bar")
        type("addr")
        XCTAssertTrue(wait { (self.field.value as? String) == "1 Infinite Loop" }, "the keyword becomes its snippet")

        type(" ")
        snippetKey.tap()
        type("hi")
        let value = app.textFields["iikb.form.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5), "an argument is asked for before the snippet goes in")
        XCTAssertEqual(field.value as? String, "1 Infinite Loop !hi", "the keyword waits")
        type("ana")
        try shot("snippet-form")
        app.buttons["iikb.form.done"].tap()
        try shot("snippet-form-last")
        key("return").tap()
        XCTAssertTrue(
            wait { (self.field.value as? String) == "1 Infinite Loop Hi ana, see you in Paris." },
            "the snippet goes in with the argument, the empty one its default: \(field.value ?? "")")
        XCTAssertFalse(value.exists, "the form closes")
    }

    func testTheSnippetsPanelTypesAPickAndHoldingOneOffersEdit() throws {
        let more = app.buttons["iikb.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        let head = app.buttons["iikb.shelf.snippets"]
        XCTAssertTrue(head.waitForExistence(timeout: 3), "the menu has a Snippets shelf")
        try shot("snippet-menu")
        head.tap()
        let row = app.descendants(matching: .any).matching(identifier: "iikb.snippets.0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the panel lists the snippets")
        try shot("snippet-panel")
        row.tap()
        XCTAssertTrue(wait { (self.field.value as? String) == "1 Infinite Loop" }, "a tap types the snippet")
        row.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5), "holding one offers Edit")
        try shot("snippet-hold")
    }

    private func type(_ text: String) {
        for character in text { key(character == " " ? "space" : String(character)).tap() }
    }

    private func key(_ name: String) -> XCUIElement {
        app.keys.matching(identifier: "iikb.\(name)").firstMatch
    }

    private func wait(_ timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func shot(_ name: String) throws {
        guard let shots else { return }
        Thread.sleep(forTimeInterval: 1.5)
        let inner = XCUIScreen.screens.map { $0.screenshot() }.max {
            $0.image.size.width * $0.image.size.height < $1.image.size.width * $1.image.size.height
        }
        let screen = ProcessInfo.processInfo.environment["IIKB_OPEN"] == "1" ? inner : nil
        try (screen ?? XCUIScreen.main.screenshot()).pngRepresentation.write(
            to: URL(fileURLWithPath: "\(shots)-\(name).png"))
    }
}
