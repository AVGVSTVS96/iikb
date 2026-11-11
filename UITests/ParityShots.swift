import XCTest

/// Every screen of the keyboard on one phone, light or dark, for the parity page beside the Android port
/// (scripts/parity): the layers, typing with its bar, held keys, swipe, the menu and each of its shelves, and every
/// panel opened, searched and held, and Chats from `IIKB_EXTENSION` (scripts/chats.ts). `IIKB_SHOTS` is the file
/// prefix; `IIKB_STATES` names the sections to shoot (`layers typing held swipe menu emoji gif clipboard transcripts
/// chats`), and any other name shoots the keyboard as it opens under that name, as for dictation's states, which
/// scripts/voiceapp.py holds.
/// A held key's pop-up lasts only as long as the hold, so for those the test leaves `<prefix>-<name>.hold`, holding
/// how many seconds into the hold to shoot, and scripts/parity takes the screenshot.
final class ParityShots: XCTestCase {
    private var prefix = ""

    func testEveryScreen() throws {
        let environment = ProcessInfo.processInfo.environment
        prefix = try XCTUnwrap(environment["IIKB_SHOTS"])
        continueAfterFailure = false
        for section in (environment["IIKB_STATES"] ?? "").split(separator: " ") {
            switch section {
            case "layers": try layers()
            case "typing": try typing()
            case "held": try held()
            case "swipe": try swipe()
            case "menu": try menu()
            case "emoji": try panel("emoji", search: "pizza")
            case "gif": try panel("gif", search: "cat")
            case "clipboard": try panel("clipboard", search: "sight")
            case "transcripts": try panel("transcripts", search: "the")
            case "chats": try chats(at: try XCTUnwrap(environment["IIKB_EXTENSION"]))
            default:
                _ = launch()
                try shot(String(section), settle: 3)
            }
        }
    }

    private func layers() throws {
        let app = launch(text: "Coffee at ")
        try shot("keyboard-letters", settle: 4)
        key("shift", in: app).tap()
        try shot("keyboard-shift")
        key("shift", in: app).doubleTap()
        try shot("keyboard-caps")
        key("shift", in: app).tap()
        key("numbers", in: app).tap()
        try shot("keyboard-numbers")
        key("symbols", in: app).tap()
        try shot("keyboard-symbols")
    }

    private func typing() throws {
        let app = launch(autoCorrection: true)
        type("Coffee at th", in: app)
        try shot("keyboard-typing")
        key("delete", in: app).tap()
        key("delete", in: app).tap()
        type("teh", in: app)
        try shot("keyboard-autocorrect")
        key("space", in: app).tap()
        try shot("keyboard-autocorrected")
    }

    /// The pop-ups that last only while a finger is down, each shot by scripts/parity mid-hold.
    private func held() throws {
        let app = launch(text: "Coffee at ")
        hold("keyboard-callout", at: 3) { self.key("g", in: app).press(forDuration: 10) }
        hold("keyboard-accents", at: 4) { self.key("e", in: app).press(forDuration: 10) }
        let space = key("space", in: app)
        hold("keyboard-trackpad", at: 5) {
            space.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
                forDuration: 1.2, thenDragTo: space.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)),
                withVelocity: .slow, thenHoldForDuration: 10)
        }
        let numbers = key("numbers", in: app)
        hold("keyboard-numbers-menu", at: 5) {
            numbers.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
                forDuration: 1.5,
                thenDragTo: numbers.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(
                    CGVector(dx: 0, dy: -85)),
                withVelocity: .slow, thenHoldForDuration: 10)
        }
    }

    /// A word swiped slowly from key to key, shot mid-swipe with its trail, then the word it typed.
    private func swipe() throws {
        let app = launch(text: "Coffee at ")
        let field = app.textViews.firstMatch
        let middle = CGVector(dx: 0.5, dy: 0.5)
        let from = key("t", in: app).coordinate(withNormalizedOffset: middle)
        let to = key("o", in: app).coordinate(withNormalizedOffset: middle)
        hold("keyboard-swipe", at: 3) {
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 30, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(wait(15) { (field.value as? String)?.lowercased().hasSuffix("to") == true }, "the swipe types")
        try shot("keyboard-swiped")
    }

    /// The menu, its edits on top, from its shelves down to Theme and Stop Animation, a screenful at a time.
    private func menu() throws {
        UIPasteboard.general.string = "Meet at Sightglass on 7th, 4pm?"
        let app = launch(text: "Coffee at ")
        let more = app.buttons["iikb.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "the bar's More button shows")
        more.tap()
        XCTAssertTrue(app.buttons["iikb.shelf.clipboard"].waitForExistence(timeout: 3))
        try shot("menu", settle: 3)
        let stop = app.buttons["iikb.shelf.stop"]
        let window = app.windows.firstMatch
        let origin = window.coordinate(withNormalizedOffset: .zero)
        for page in 2...6 {
            let look = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'iikb.look.stop.'")).firstMatch
            if look.exists, look.frame.maxY < window.frame.maxY, stop.frame.minY > more.frame.maxY { break }
            let x = window.frame.width * 0.8
            let y = window.frame.maxY - 60
            origin.withOffset(CGVector(dx: x, dy: y)).press(
                forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: x, dy: y - window.frame.height * 0.35)))
            try shot("menu-\(page)", settle: 1.5)
        }
        app.terminate()
    }

    /// A panel opened from the menu (emoji, which has no shelf, from its key), with the keys up, with a search, and
    /// with an item held, in a launch of its own, since a held item leaves its preview open.
    private func panel(_ panel: String, search: String) throws {
        UIPasteboard.general.string = "Meet at Sightglass on 7th, 4pm?"
        var app = open(panel)
        try shot(panel, settle: panel == "gif" ? 5 : 2)
        if !key("space", in: app).isHittable {
            app.descendants(matching: .any).matching(identifier: "iikb.panel.search").firstMatch.tap()
            XCTAssertTrue(wait(5) { self.key("space", in: app).isHittable }, "\(panel)'s search raises the keys")
            try shot("\(panel)-keys")
        }
        type(search, in: app)
        try shot("\(panel)-search", settle: panel == "gif" ? 5 : 2)
        app.terminate()

        app = open(panel)
        if panel == "emoji" {
            let thumbs = app.descendants(matching: .any)["iikb.emoji.👍"]
            XCTAssertTrue(thumbs.waitForExistence(timeout: 5))
            hold("emoji-hold", at: 3) { thumbs.press(forDuration: 10) }
        } else {
            let start = ["gif": "iikb.gif.", "clipboard": "iikb.clip.", "transcripts": "iikb.transcript."][panel]!
            let item = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", start)
            ).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 15), "\(panel) has an item to hold")
            item.press(forDuration: 1.2)
            try shot("\(panel)-hold", settle: 1.5)
        }
        app.terminate()
    }

    /// The extension added through its link, then its chats, named as the Android port's shots are: the menu's Chats
    /// shelf, Notes open with the keys down, the keys up under its box, "ok" typed, sent and answered with the keys
    /// down, Trip's file and photo, every chat in the tabs' hold menu, the photo opened large and held for Copy, and a
    /// message's text selected.
    private func chats(at url: String) throws {
        let linked = XCUIApplication()
        var link = URLComponents(string: "iikb://extension")!
        link.queryItems = [URLQueryItem(name: "name", value: "Notes"), URLQueryItem(name: "url", value: url)]
        linked.open(link.url!)
        let add = linked.alerts.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the link asks before adding the extension")
        add.tap()
        linked.terminate()

        var app = launch()
        let more = element("iikb.more", in: app)
        let field = element("iikb.chat.field", in: app)
        if field.exists {
            more.tap()
            XCTAssertTrue(wait(5) { !field.exists }, "More leaves the chat the keyboard came back with")
        }
        more.tap()
        let card = element("iikb.chats.shelf.0", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the menu has a Chats shelf with the chats as cards")
        try shot("panel-chat-shelf", settle: 2)
        card.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the chat opens with its message box")
        XCTAssertTrue(element("iikb.chat.0", in: app).waitForExistence(timeout: 20), "the chats are tabs")
        try shot("panel-chat", settle: 2)
        for _ in 0..<3 where !key("space", in: app).isHittable {
            field.tap()
            _ = wait(10) { self.key("space", in: app).isHittable }
        }
        XCTAssertTrue(key("space", in: app).isHittable, "tapping the box brings the keys up")
        try shot("panel-chat-keys")
        type("ok", in: app)
        try shot("panel-chat-typing")
        element("iikb.chat.send", in: app).tap()
        let reply = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Got it'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 20), "the reply shows")
        keysAway(in: app)
        XCTAssertTrue(wait(5) { !self.key("space", in: app).isHittable }, "tapping the messages puts the keys away")
        try shot("panel-chat-answered", settle: 1.5)
        let trip = tab("Trip", in: app)
        trip.tap()
        let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "Trip has its photo")
        try shot("panel-chat-photo", settle: 3)
        trip.press(forDuration: 1.2)
        try shot("panel-chat-tabs-menu", settle: 1.5)
        app.terminate()

        app = openChat("Trip")
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()
        XCTAssertTrue(element("iikb.chat.photo", in: app).waitForExistence(timeout: 5), "a tap opens the photo large")
        try shot("panel-chat-photo-open", settle: 1.5)
        app.terminate()

        app = openChat("Trip")
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.press(forDuration: 1.2)
        try shot("panel-chat-photo-hold", settle: 1.5)
        app.terminate()

        app = openChat("Notes")
        let message = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Booked for 11'"))
            .firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10), "Notes has its messages")
        message.press(forDuration: 1.2)
        try shot("panel-chat-select", settle: 1.5)
        app.terminate()
    }

    /// A tap on the messages beside the last one, not on a bubble's text, which keeps the keys up to select, once the
    /// chat has scrolled to it.
    private func keysAway(in app: XCUIApplication) {
        let space = key("space", in: app)
        for _ in 0..<3 where space.isHittable {
            Thread.sleep(forTimeInterval: 1.5)
            element("iikb.chat.messages", in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.97)).tap()
            _ = wait(3) { !space.isHittable }
        }
    }

    private func tab(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'iikb.chat.' AND label == %@", name)).firstMatch
    }

    /// The chat named, open with its keys down, whether the keyboard comes back with a chat open or not.
    private func openChat(_ name: String) -> XCUIApplication {
        let app = launch()
        let field = element("iikb.chat.field", in: app)
        if !field.exists {
            element("iikb.more", in: app).tap()
            element("iikb.chats.shelf.0", in: app).tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "a chat opens")
        if key("space", in: app).isHittable { keysAway(in: app) }
        tab(name, in: app).tap()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The menu's shelf for `panel`, or the emoji key for emoji.
    private func open(_ panel: String) -> XCUIApplication {
        let app = launch(text: "Coffee at ")
        if panel == "emoji" {
            key("emoji", in: app).tap()
        } else {
            let more = app.buttons["iikb.more"]
            XCTAssertTrue(more.waitForExistence(timeout: 10))
            more.tap()
            let shelf = app.buttons["iikb.shelf.\(panel)"]
            XCTAssertTrue(shelf.waitForExistence(timeout: 5), "the menu has the \(panel) shelf")
            shelf.tap()
        }
        let list = [
            "emoji": "iikb.emoji", "gif": "iikb.gifs", "clipboard": "iikb.clipboard", "transcripts": "iikb.transcripts",
        ][panel]!
        XCTAssertTrue(app.descendants(matching: .any)[list].waitForExistence(timeout: 5), "\(panel) opens")
        return app
    }

    /// The app with its field focused on iikb, set as it first comes, auto-correction off unless asked for.
    private func launch(text: String? = nil, autoCorrection: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-iikbFocus", "YES", "-iikbOrientation", "portrait", "-iikbOneHanded", "off", "-iikbCompactPanels",
                "NO",
                "-iikbAutoCorrection", autoCorrection ? "YES" : "NO",
            ] + (text.map { ["-iikbText", $0] } ?? [])
        let up = { app.keys["iikb.space"].exists || app.descendants(matching: .any)["iikb.chat.field"].exists }
        for _ in 0..<4 {
            app.launch()
            if wait(30, up) { break }
            app.terminate()
        }
        XCTAssertTrue(up(), "iikb is not the active keyboard")
        return app
    }

    private func type(_ text: String, in app: XCUIApplication) {
        for character in text {
            switch character {
            case " ": key("space", in: app).tap()
            case let letter where letter.isUppercase:
                key("shift", in: app).tap()
                key(letter.lowercased(), in: app).tap()
            default: key(String(character), in: app).tap()
            }
        }
    }

    /// Leaves `<prefix>-<name>.hold` for scripts/parity, which shoots the screen `seconds` into the hold.
    private func hold(_ name: String, at seconds: Double, _ press: () throws -> Void) rethrows {
        FileManager.default.createFile(atPath: "\(prefix)-\(name).hold", contents: Data("\(seconds)".utf8))
        try press()
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func shot(_ name: String, settle: TimeInterval = 1.2) throws {
        Thread.sleep(forTimeInterval: settle)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
        try? outline().write(to: URL(fileURLWithPath: "\(prefix)-\(name).json"))
    }

    /// What XCUITest sees on the screen as it's shot, for scripts/screens: each element's identifier, label, frame in
    /// points, and whether it takes text (where a caret blinks).
    private func outline() throws -> Data {
        var elements: [[String: Any]] = []
        let inputs: Set<XCUIElement.ElementType> = [.textField, .textView, .searchField, .secureTextField]
        func add(_ element: XCUIElementSnapshot) {
            let frame = element.frame
            guard !frame.isNull, !frame.isInfinite else { return element.children.forEach(add) }
            elements.append([
                "id": element.identifier, "label": element.label, "input": inputs.contains(element.elementType),
                "frame": [frame.minX, frame.minY, frame.width, frame.height].map { ($0 * 2).rounded() / 2 },
            ])
            element.children.forEach(add)
        }
        add(try XCUIApplication().snapshot())
        return try JSONSerialization.data(withJSONObject: elements, options: [.sortedKeys])
    }

    private func wait(_ timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let iikb = app.keys.matching(identifier: "iikb.\(name)").firstMatch
        return iikb.exists ? iikb : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
