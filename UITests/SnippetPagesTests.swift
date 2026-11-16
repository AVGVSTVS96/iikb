import XCTest

/// The app's Snippets and Quicklinks: the keyboard's Edit link opens one's editor, an argument goes in and is saved, a
/// snippet is deleted, and a new one can't be saved without text.
final class SnippetPagesTests: XCTestCase {
    private let kept =
        #"{"snippets":[{"id":"t-meet","name":"Meeting","text":"Meet at {argument name=\"Place\"}","keyword":"!meet","tag":""}],"#
        + #""quicklinks":[{"id":"t-search","name":"Search","link":"https://duckduckgo.com/?q={argument name=\"Query\"}"}]}"#

    func testEditLinksOpenEditorsAndASnippetSavesAndDeletes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-iikbSnippets", kept, "-iikbSettings", "snippets"]
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Meeting'")).firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "the snippet is kept, but the app shows \(app.debugDescription.split(separator: "\n").joined(separator: " | "))"
        )
        app.terminate()

        app.launchArguments = ["-iikbLink", "iikb://snippets/t-meet"]
        app.launch()
        let text = app.textViews["Text"]
        XCTAssertTrue(text.waitForExistence(timeout: 15), "the link opens its editor")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == 'Meeting'")).firstMatch.exists, "its name")
        XCTAssertEqual(text.value as? String, #"Meet at {argument name="Place"}"#)

        app.buttons["Argument"].tap()
        let alert = app.alerts["Add Argument"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Argument asks for its name")
        settled(alert)
        alert.buttons["Add"].tap()
        XCTAssertEqual(text.value as? String, #"Meet at {argument name="Place"}{argument}"#, "it goes in at the end")
        app.buttons["Save"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 5), "Save closes the editor")

        row.tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.value as? String, #"Meet at {argument name="Place"}{argument}"#, "the argument was kept")
        app.buttons["Delete Snippet"].tap()
        XCTAssertTrue(
            app.staticTexts[
                "Keep text you type often, and type it again by its keyword or from the keyboard’s Snippets."
            ]
            .waitForExistence(timeout: 5), "deleting the only snippet empties the list")

        app.buttons["Add Snippet"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled, "a snippet needs text")
        app.buttons["Cursor"].tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled, "the cursor is text enough")
        app.buttons["Cancel"].tap()
        app.terminate()

        app.launchArguments = ["-iikbLink", "iikb://quicklinks/t-search"]
        app.launch()
        let link = app.textViews["Link"]
        XCTAssertTrue(link.waitForExistence(timeout: 15), "the link opens its editor")
        XCTAssertEqual(link.value as? String, #"https://duckduckgo.com/?q={argument name="Query"}"#)
    }

    /// Waits for `element` to stop moving, as the alert does while the keys rise under its focused field: a tap
    /// mid-slide finds no alert.
    private func settled(_ element: XCUIElement) {
        var last = element.frame
        for _ in 0..<12 {
            Thread.sleep(forTimeInterval: 0.25)
            let now = element.frame
            if now == last { return }
            last = now
        }
    }
}
