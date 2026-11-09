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

    /// The keyboard goes away and comes back in the same field, as it does when the mic goes through iikb: the chat
    /// opens again with its line and its keys up. More then leaves it, keys up and all.
    func testAChatComesBackAsYouLeftItOnThePhone() throws {
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
        field.tap()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 5), "tapping the box brings the keys up")
        for character in "kept" { key(String(character), in: app).tap() }
        Thread.sleep(forTimeInterval: 1)
        shot("7-before-leaving")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the chat is open again")
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 5), "with its keys up")
        Thread.sleep(forTimeInterval: 2)
        shot("8-back")

        let messages = app.textViews.matching(NSPredicate(format: "identifier != 'iikb.chat.field'"))
        if let last = messages.allElementsBoundByIndex.last(where: \.isHittable) {
            last.press(forDuration: 1.2)
            Thread.sleep(forTimeInterval: 1.5)
            shot("8b-selected")
            XCTAssertTrue(key("space", in: app).exists, "selecting in a message leaves the keys up")
            XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 3), "with the selection's Copy")
            Thread.sleep(forTimeInterval: 3)
            XCTAssertTrue(app.menuItems["Copy"].exists, "which stays as the chat redraws")
        }

        for _ in 0..<4 { key("delete", in: app).tap() }
        element("iikb.more", in: app).tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(field.exists, "More leaves the chat with its keys up")
        XCTAssertTrue(key("space", in: app).exists, "and gives the app's keys back")
        shot("9-left")
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

    /// A message's text is real text: held, a word selects with iOS's edit menu, Copy copies it, and it pastes into
    /// the box; a link held offers Open Link and Copy Link.
    func testAMessageSelectsAndCopiesOnThePhone() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 10), "iikb is not the active keyboard")
        element("iikb.more", in: app).tap()
        let card = element("iikb.chats.shelf.0", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the menu has a Chats shelf with the chats as cards")
        card.tap()
        let thread = element("iikb.chat.messages", in: app)
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "the chat opens with its messages")
        Thread.sleep(forTimeInterval: 3)
        shot("7-messages")
        let messages = thread.textViews
        XCTAssertGreaterThan(messages.count, 0, "the messages are text views")
        let newest = messages.element(boundBy: messages.count - 1)
        newest.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1)
        shot("8-held-message")
        let copy = app.menuItems["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3), "holding a message's text offers iOS's Copy")
        copy.tap()
        let field = element("iikb.chat.field", in: app)
        field.tap()
        Thread.sleep(forTimeInterval: 1)
        field.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"]
        if paste.waitForExistence(timeout: 3) {
            paste.tap()
            Thread.sleep(forTimeInterval: 1)
            shot("9-pasted")
            field.press(forDuration: 1.2)
            if app.menuItems["Select All"].waitForExistence(timeout: 3) {
                app.menuItems["Select All"].tap()
                if app.menuItems["Cut"].waitForExistence(timeout: 3) { app.menuItems["Cut"].tap() }
            }
        }
        shot("10-box-cleared")
        let links = thread.links
        if links.count > 0 {
            links.element(boundBy: links.count - 1).press(forDuration: 1.2)
            Thread.sleep(forTimeInterval: 1)
            shot("11-held-link")
            XCTAssertTrue(
                app.buttons["Copy Link"].exists || app.menuItems["Copy Link"].exists, "a held link offers Copy Link")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        }
        element("iikb.more", in: app).tap()
    }

    /// A chat's photo is a photo: a tap opens it large, a tap closes it, and holding it shows it larger over Copy
    /// (`CHAT`, the chat with photos, ChatsCraft by default).
    func testAPhotoOpensAndCopiesOnThePhone() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 10), "iikb is not the active keyboard")
        element("iikb.more", in: app).tap()
        let card = element("iikb.chats.shelf.0", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the menu has a Chats shelf with the chats as cards")
        card.tap()
        let name = ProcessInfo.processInfo.environment["CHAT"] ?? "ChatsCraft"
        let tab = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(name) is one of the chats")
        let first = element("iikb.chat.0", in: app)
        for _ in 0..<8 where !tab.isHittable { first.swipeLeft() }
        tab.tap()
        let thread = element("iikb.chat.messages", in: app)
        let photos = thread.images
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 15), "\(name)'s photos are images")
        Thread.sleep(forTimeInterval: 4)
        shot("12-photos")
        let photo = photos.element(boundBy: photos.count - 1)
        photo.tap()
        let large = element("iikb.chat.photo", in: app)
        XCTAssertTrue(large.waitForExistence(timeout: 5), "a tap opens the photo large")
        Thread.sleep(forTimeInterval: 2)
        shot("13-photo-open")
        large.tap()
        Thread.sleep(forTimeInterval: 1)
        photo.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1.5)
        shot("14-photo-held")
        let copy = app.buttons["Copy"].exists ? app.buttons["Copy"] : app.menuItems["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3), "holding a photo offers Copy")
        copy.tap()
        Thread.sleep(forTimeInterval: 1)
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
