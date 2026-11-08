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
        let tool = element("iikb.tool.chats", in: app)
        XCTAssertTrue(tool.waitForExistence(timeout: 10), "the bar has the Chats tool")
        tool.tap()
        try shot("\(shots)-panel")
        let listed = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["iikb.chat.0", "iikb.chat.picker"])
        ).firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 20), "the chats are listed, as chips or, in one row, a picker")
        if let name = environment["IIKB_CHAT"] {
            if listed.identifier == "iikb.chat.picker" { listed.tap() }
            app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch.tap()
        }
        try shot("\(shots)-open")

        type(message, in: app)
        try shot("\(shots)-typed")
        element("iikb.chat.send", in: app).tap()
        let answer = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", reply))
            .firstMatch
        XCTAssertTrue(
            answer.waitForExistence(timeout: Double(environment["IIKB_WAIT"] ?? "20") ?? 20),
            "the reply shows in the panel")
        try shot("\(shots)-reply")

        element("iikb.panel.back", in: app).tap()
        XCTAssertTrue(wait { !self.element("iikb.chat.send", in: app).exists }, "back closes the chats")
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
