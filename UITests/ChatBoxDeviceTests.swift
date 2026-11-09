import XCTest

/// The chat box on a real iPhone, with whatever chats its extension has: a chat opens from the menu, a tap on its box
/// brings the keys up and focuses it, the keys type into it, and iOS's own loupe, selection and edit menu work on it.
/// Nothing is sent: what it typed is deleted before the chat closes (scripts/chatdevice).
final class ChatBoxDeviceTests: XCTestCase {
    func testTheChatBoxIsARealTextViewOnThePhone() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 10), "iikb is not the active keyboard")
        element("iikb.more", in: app).tap()
        let card = element("iikb.chats.shelf.0", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the menu has a Chats shelf with the chats as cards")
        card.tap()
        let field = element("iikb.chat.field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the chat opens with its message box")
        Thread.sleep(forTimeInterval: 2)
        shot("1-open")

        field.tap()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 5), "tapping the box brings the keys up")
        let words = "testing the real box"
        for character in words {
            key(character == " " ? "space" : String(character), in: app).tap()
        }
        Thread.sleep(forTimeInterval: 1)
        shot("2-typed")

        let middle = field.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        middle.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1)
        shot("3-held")
        field.doubleTap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("4-selected")

        field.tap()
        Thread.sleep(forTimeInterval: 1)
        shot("4b-tapped")
        let delete = key("delete", in: app)
        for _ in 0..<8 { delete.tap() }
        shot("4c-deleting")
        for _ in 0..<(words.count - 4) { delete.tap() }
        Thread.sleep(forTimeInterval: 0.5)
        shot("5-cleared")
        element("iikb.more", in: app).tap()
    }

    func testThePanelSearchIsARealFieldOnThePhone() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 10), "iikb is not the active keyboard")
        element("iikb.more", in: app).tap()
        let shelf = element("iikb.shelf.clipboard", in: app)
        XCTAssertTrue(shelf.waitForExistence(timeout: 10), "the menu has a Clipboard shelf")
        shelf.tap()
        let search = element("iikb.panel.search", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Clipboard opens with its search field")
        search.tap()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 5), "tapping search brings the keys up")
        for character in "http" { key(String(character), in: app).tap() }
        Thread.sleep(forTimeInterval: 1.5)
        for blink in 0..<4 {
            shot("6-search-\(blink)")
            Thread.sleep(forTimeInterval: 0.3)
        }
        for _ in 0..<4 { key("delete", in: app).tap() }
        element("iikb.panel.back", in: app).tap()
        element("iikb.panel.back", in: app).tap()
        element("iikb.more", in: app).tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let iikb = app.keys.matching(identifier: "iikb.\(name)").firstMatch
        return iikb.exists ? iikb : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
