import XCTest

/// The app's Snippets and Quicklinks: the keyboard's Edit link opens one's editor, an argument goes in and is saved, a
/// snippet is deleted, and a new one can't be saved without text.
final class SnippetPagesTests: XCTestCase {
    private let kept = #"""
        {"snippets": [{"id": "t-meet", "name": "Meeting", "text": "Meet at {argument name=\"Place\"}", "keyword": "!meet", "tag": ""}],
         "quicklinks": [{"id": "t-search", "name": "Search", "link": "https://duckduckgo.com/?q={argument name=\"Query\"}"}]}
        """#

    func testEditLinksOpenEditorsAndASnippetSavesAndDeletes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-iikbSnippets", kept, "-iikbLink", "iikb://snippets/t-meet"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Edit Snippet"].waitForExistence(timeout: 15), "the link opens its editor")
        XCTAssertEqual(app.textFields["Name"].value as? String, "Meeting")
        let text = app.textViews["Text"]
        XCTAssertEqual(text.value as? String, #"Meet at {argument name="Place"}"#)

        app.buttons["Argument"].tap()
        let add = app.alerts.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Argument asks for its name")
        add.tap()
        XCTAssertEqual(text.value as? String, #"Meet at {argument name="Place"}{argument}"#, "it goes in at the end")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit Snippet"].waitForNonExistence(timeout: 5), "Save closes the editor")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Meeting'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit Snippet"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.textViews["Text"].value as? String, #"Meet at {argument name="Place"}{argument}"#, "the argument was kept")
        app.buttons["Delete Snippet"].tap()
        XCTAssertTrue(
            app.staticTexts["Keep text you type often, and type it again by its keyword or from the keyboard’s Snippets."]
                .waitForExistence(timeout: 5), "deleting the only snippet empties the list")

        app.buttons["Add Snippet"].tap()
        XCTAssertTrue(app.navigationBars["New Snippet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled, "a snippet needs text")
        app.buttons["Cursor"].tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled, "the cursor is text enough")
        app.buttons["Cancel"].tap()
        app.terminate()

        app.launchArguments = ["-iikbSnippets", kept, "-iikbLink", "iikb://quicklinks/t-search"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Edit Quicklink"].waitForExistence(timeout: 15), "the link opens its editor")
        XCTAssertEqual(app.textViews["Link"].value as? String, #"https://duckduckgo.com/?q={argument name="Query"}"#)
    }
}
