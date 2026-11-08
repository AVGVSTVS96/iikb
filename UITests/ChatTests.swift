import XCTest

/// An extension's chats through the real keyboard, added through its link the way a real one is: the panel opens from
/// the bar, a message typed with the keys goes to the chat, and the reply shows (scripts/chattest).
final class ChatTests: XCTestCase {
    func testAMessageTypedInAChatIsSentAndItsReplyShows() throws {
        let environment = ProcessInfo.processInfo.environment.filter { !$0.value.isEmpty }
        guard let url = environment["IIKB_EXTENSION"], let shots = environment["IIKB_SHOTS"] else {
            throw XCTSkip("Run through scripts/chattest")
        }
        let message = environment["IIKB_MESSAGE"] ?? "can you check the build"
        let reply = environment["IIKB_REPLY"] ?? "On it"
        continueAfterFailure = false

        let linked = XCUIApplication()
        var link = URLComponents(string: "iikb://extension")!
        link.queryItems = [URLQueryItem(name: "name", value: "hex"), URLQueryItem(name: "url", value: url)]
        linked.open(link.url!)
        let add = linked.alerts.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the link asks before adding the extension")
        try shot("\(shots)-offer")
        add.tap()
        linked.terminate()

        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbOrientation", "portrait"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 10), "iikb is not the active keyboard")
        element("iikb.more", in: app).tap()
        let card = element("iikb.chats.shelf.0", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the menu has a Chats shelf with the chats as cards")
        try shot("\(shots)-menu")
        if let name = environment["IIKB_CHAT"] {
            app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch.tap()
        } else {
            card.tap()
        }
        let field = element("iikb.chat.field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the chat opens with its message box")
        XCTAssertFalse(key("space", in: app).isHittable, "the chat opens with the keys down")
        XCTAssertTrue(element("iikb.chat.0", in: app).waitForExistence(timeout: 20), "the chats are pills in the bar")
        Thread.sleep(forTimeInterval: 1)
        try shot("\(shots)-open")

        field.tap()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 5), "tapping the box brings the keys up")
        type(message, in: app)
        try shot("\(shots)-typed")
        field.doubleTap()
        Thread.sleep(forTimeInterval: 1.5)
        try shot("\(shots)-select")
        field.tap()
        key("return", in: app).tap()
        let answer = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", reply))
            .firstMatch
        XCTAssertTrue(
            answer.waitForExistence(timeout: Double(environment["IIKB_WAIT"] ?? "20") ?? 20),
            "the reply shows in the panel")
        try shot("\(shots)-reply")

        element("iikb.chat.messages", in: app).tap()
        XCTAssertTrue(wait { !self.key("space", in: app).isHittable }, "tapping the messages puts the keys away")
        try shot("\(shots)-read")
        element("iikb.more", in: app).tap()
        XCTAssertTrue(wait { !field.exists }, "More leaves the chat")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func type(_ text: String, in app: XCUIApplication) {
        for character in text { key(character == " " ? "space" : String(character), in: app).tap() }
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    /// The open Duo draws on its inner screen, the larger one.
    private func shot(_ path: String) throws {
        let open = ProcessInfo.processInfo.environment["IIKB_OPEN"].map { !$0.isEmpty } ?? false
        let screen =
            open
            ? XCUIScreen.screens.max { $0.screenshot().image.size.width < $1.screenshot().image.size.width }!
            : XCUIScreen.main
        try screen.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path + ".png"))
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let iikb = app.keys.matching(identifier: "iikb.\(name)").firstMatch
        return iikb.exists ? iikb : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
