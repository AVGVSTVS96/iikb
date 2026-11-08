import UniformTypeIdentifiers
import XCTest

/// The menu, its edits and shelves, and the GIF, clipboard and Transcripts panels through the real keyboard, with Full Access on (scripts/paneltest turns it on). With
/// IIKB_SHOTS set, screenshots each step.
final class ToolPanelTests: XCTestCase {
    private var shots: String?

    override func setUpWithError() throws {
        shots = ProcessInfo.processInfo.environment["IIKB_SHOTS"]
        continueAfterFailure = false
    }

    func testTheGifPanelSearchesKlipyAndCopiesWhatYouTap() throws {
        let app = launch()
        open(.gif, in: app)
        let gifs = app.scrollViews["iikb.gifs"]
        XCTAssertTrue(gifs.waitForExistence(timeout: 3), "the menu's GIFs shelf opens the GIF panel")
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'iikb.gif.'"))
        XCTAssertTrue(tile.firstMatch.waitForExistence(timeout: 15), "an empty search shows KLIPY's trending GIFs")
        XCTAssertFalse(key("space", in: app).isHittable, "the panel opens in the keys' place")
        try shot("gif")

        let search = raiseKeys(in: app)
        for letter in "cat" { key(String(letter), in: app).tap() }
        XCTAssertTrue(wait { (search.value as? String) == "cat" }, "the keys type into the search")
        XCTAssertTrue(wait(15) { tile.count > 4 }, "searching finds GIFs")
        try shot("gif-search")
        if compact { assertOneRowScrollsSideways(tile, in: gifs, app: app) }
        key("return", in: app).tap()
        XCTAssertTrue(wait { !self.key("space", in: app).isHittable }, "return puts the keys back down")
        XCTAssertEqual(search.value as? String, "cat", "and keeps the search")

        let picked = tile.element(boundBy: 0)
        let id = picked.identifier.components(separatedBy: "--")[0]
        picked.tap()
        XCTAssertTrue(wait(15) { (search.value as? String)?.hasPrefix("Copied") == true }, "a tap says it was copied")
        XCTAssertTrue(
            UIPasteboard.general.contains(pasteboardTypes: [UTType.gif.identifier]), "the GIF is on the clipboard")
        try shot("gif-copied")

        app.buttons["iikb.gifs.recents"].tap()
        XCTAssertTrue(wait(15) { tile.firstMatch.identifier == id }, "the clock shows the GIF you sent first")
        try shot("gif-recents")
        tile.firstMatch.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1.5)
        try shot("gif-preview")
    }

    func testAHeldGifDragsIntoTheMessage() throws {
        guard
            FileManager.default.fileExists(
                atPath: (ProcessInfo.processInfo.environment["SIMULATOR_ROOT"] ?? "") + "/Applications/MobileSMS.app")
        else {
            throw XCTSkip("this simulator has no Messages: iOS 27.1, the only one with the iPhone Duo, leaves it out")
        }
        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        messages.launch()
        let thread = messages.cells.firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Messages shows a conversation")
        thread.tap()
        let field = messages.textFields["messageBodyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the conversation has a message field")
        field.tap()
        XCTAssertTrue(key("space", in: messages).waitForExistence(timeout: 20), "iikb is not the active keyboard")
        open(.gif, in: messages)
        let tile = messages.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'iikb.gif.'"))
        XCTAssertTrue(tile.firstMatch.waitForExistence(timeout: 15), "an empty search shows KLIPY's trending GIFs")
        try shot("gif-drag")

        let picked = tile.firstMatch
        let id = picked.identifier.components(separatedBy: "--")[0]
        picked.press(forDuration: 1, thenDragTo: field, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(wait(15) { (field.value as? String)?.contains("\u{FFFC}") == true }, "the GIF is in the message")
        let search = messages.descendants(matching: .any).matching(identifier: "iikb.panel.search").firstMatch
        XCTAssertFalse((search.value as? String)?.hasPrefix("Copied") == true, "a drag doesn't also copy")
        try shot("gif-dropped")
        messages.buttons["iikb.gifs.recents"].tap()
        XCTAssertTrue(wait(15) { tile.firstMatch.identifier == id }, "the clock shows the GIF you dropped first")
        messages.terminate()
    }

    func testTheClipboardPanelKeepsWhatYouCopyAndTypesWhatYouPick() throws {
        UIPasteboard.general.string = "Meet at Sightglass on 7th, 4pm?"
        var app = launch()
        open(.clipboard, in: app)
        let message = app.buttons["iikb.clipboard.message"]
        if message.waitForExistence(timeout: 2), message.label.contains("Paste from Other Apps") {
            try shot("clipboard-refused")
            message.tap()
            sleep(2)
            try shot("clipboard-settings")
            try allowPasteFromOtherApps()
            app = launch()
            open(.clipboard, in: app)
        }
        let row = app.descendants(matching: .any).matching(identifier: "iikb.clip.Meet at Sightglass on 7th, 4pm?")
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "what you copied in another app is kept")
        XCTAssertTrue(
            row.staticTexts["iikb.clip.detail"].label.hasPrefix("31 chars · "),
            "a row says how long its text is, then how long ago")
        try shot("clipboard")

        raiseKeys(in: app)
        for letter in "sight" { key(String(letter), in: app).tap() }
        XCTAssertTrue(row.exists, "the search finds it by its text")
        row.tap()
        let field = app.textViews.firstMatch
        XCTAssertTrue(
            wait { (field.value as? String)?.contains("Meet at Sightglass on 7th, 4pm?") == true },
            "a tap types it into the app")
        app.buttons["iikb.panel.clear"].tap()

        row.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3), "holding a row shows it with Pin and Delete")
        let pin = app.buttons["Pin"].exists ? app.buttons["Pin"] : app.buttons["Unpin"]
        try shot("clipboard-hold")
        let pinned = pin.label == "Pin"
        pin.tap()
        XCTAssertTrue(wait { !app.buttons["Delete"].exists }, "Pin closes the menu")
        row.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons[pinned ? "Unpin" : "Pin"].waitForExistence(timeout: 3), "Pin and Unpin take turns")
        app.buttons[pinned ? "Unpin" : "Pin"].tap()
        XCTAssertTrue(wait { !app.buttons["Delete"].exists })
        try shot("clipboard-pinned")
    }

    func testThePreviewOfAHeldClipShowsAllOfIt() throws {
        UIPasteboard.general.string =
            "Meet at Sightglass on 7th, 4pm? Bring the deck and both printouts, and ask Sam about Thursday."
        let app = launch()
        open(.clipboard, in: app)
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'iikb.clip.Meet'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1)
        try shot("clipboard-preview")
    }

    func testHoldingAShelfItemShowsAllOfIt() throws {
        UIPasteboard.general.string =
            "Meet at Sightglass on 7th, 4pm? Bring the deck and both printouts, and ask Sam about Thursday."
        let app = launch()
        let more = app.buttons["iikb.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "the bar's More button shows")
        more.tap()
        let item = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'iikb.clip.Meet'")
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the clipboard's shelf shows what you copied")
        item.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3), "holding it shows all of it with its menu")
        try shot("menu-preview")
    }

    /// Made-up and public items of every kind, oldest first.
    private static let kinds = [
        "Meet at Sightglass on 7th, 4pm?", "https://en.wikipedia.org/wiki/International_Typographic_Style", "#FF6B00",
        "https://www.youtube.com/watch?v=aircAruvnKk", "https://github.com/swiftlang/swift/pull/80000",
        "(415) 555-0132",
        "hello@example.com", "https://x.com/vercel/status/1985000000000000001?s=46",
    ]

    func testCopiedItemsShowByKind() throws {
        UIPasteboard.general.string = Self.kinds[0]
        var app = launch()
        open(.clipboard, in: app)
        let message = app.buttons["iikb.clipboard.message"]
        if message.waitForExistence(timeout: 2), message.label.contains("Paste from Other Apps") {
            message.tap()
            try allowPasteFromOtherApps()
            app = launch()
            open(.clipboard, in: app)
        }
        app.buttons["iikb.panel.back"].tap()
        XCTAssertTrue(app.buttons["iikb.shelf.clipboard"].waitForExistence(timeout: 3), "back steps out to the menu")
        let more = app.buttons["iikb.more"]
        more.tap()
        XCTAssertTrue(wait { self.key("space", in: app).isHittable }, "and More gives the keys back")
        for item in Self.kinds.dropFirst() {
            UIPasteboard.general.string = item
            more.tap()
            XCTAssertTrue(app.buttons["iikb.shelf.clipboard"].waitForExistence(timeout: 3))
            more.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        more.tap()
        let link = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'iikb.clip.https://x.com/vercel'")
        ).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "the shelf shows the link")
        Thread.sleep(forTimeInterval: 3)
        try shot("menu-kinds")
        app.buttons["iikb.shelf.clipboard"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5), "the panel shows the link")
        XCTAssertLessThan(link.frame.height, 40, "a link is a one-line badge")
        Thread.sleep(forTimeInterval: 2)
        try shot("clipboard-kinds")
        let list = app.collectionViews["iikb.clipboard"]
        list.swipeUp()
        _ = app.descendants(matching: .any)["iikb.clip.#FF6B00"].waitForExistence(timeout: 3)
        try shot("clipboard-kinds-more")
        list.swipeDown()
        list.swipeDown()
        app.buttons["iikb.clipboard.links"].tap()
        XCTAssertTrue(
            wait { !app.descendants(matching: .any)["iikb.clip.Meet at Sightglass on 7th, 4pm?"].exists },
            "the link button shows only links")
        XCTAssertTrue(link.waitForExistence(timeout: 3))
        try shot("clipboard-links")
        link.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        try shot("clipboard-link-preview")
        app.terminate()

        let page = XCUIApplication()
        page.launchArguments = ["-iikbTab", "clipboard", "-iikbOrientation", orientation]
        page.launch()
        XCTAssertTrue(
            page.staticTexts["x.com"].waitForExistence(timeout: 10),
            "the app's Clipboard writes a link by its site's name")
        Thread.sleep(forTimeInterval: 2)
        try shot("app-clipboard-kinds")
        page.buttons["Links"].firstMatch.tap()
        XCTAssertTrue(wait { !page.staticTexts["hello@example.com"].exists }, "Links shows only links")
        try shot("app-clipboard-links")
    }

    func testTheMenuTakesTheKeysPlaceWithEditsAndShelves() throws {
        UIPasteboard.general.string = "Meet at Sightglass on 7th, 4pm?"
        let app = launch()
        let more = app.buttons["iikb.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 3), "the bar's More button shows")
        more.tap()
        XCTAssertTrue(
            app.buttons["iikb.shelf.clipboard"].waitForExistence(timeout: 3), "the menu has the clipboard's shelf")
        XCTAssertTrue(app.buttons["iikb.shelf.transcripts"].exists, "and Transcripts'")
        XCTAssertFalse(key("space", in: app).isHittable, "the menu is in the keys' place")
        XCTAssertTrue(
            wait { more.frame.minY < 200 }, "the menu grows the keyboard to all of the screen but 140 pt for the app")
        let footer = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'iikb.menu.' AND identifier != 'iikb.menu.settings'"))
        XCTAssertEqual(footer.count, 0, "the menu has no layout or Next Keyboard buttons")
        Thread.sleep(forTimeInterval: ProcessInfo.processInfo.environment["IIKB_SETTLE"].flatMap(Double.init) ?? 3)
        try shot("menu")
        more.tap()
        XCTAssertTrue(wait { self.key("space", in: app).isHittable }, "More again gives the keys back")
    }

    func testAPanelFromTheMenuTakesTheKeysPlaceUntilItsSearchIsTapped() throws {
        let app = launch()
        open(.transcripts, in: app)
        XCTAssertTrue(
            app.collectionViews["iikb.transcripts"].waitForExistence(timeout: 3), "the shelf's name opens its panel")
        XCTAssertFalse(key("space", in: app).isHittable, "in the keys' place")
        XCTAssertTrue(app.buttons["iikb.more"].isHittable, "with the bar and More above it")
        try shot("panel-in-place")

        raiseKeys(in: app)
        XCTAssertTrue(app.collectionViews["iikb.transcripts"].exists, "the panel sits above the keys")
        try shot("panel-keys")
        let back = app.buttons["iikb.panel.back"]
        back.tap()
        XCTAssertTrue(wait { !self.key("space", in: app).isHittable }, "back puts the keys down first")
        XCTAssertTrue(app.collectionViews["iikb.transcripts"].exists, "and keeps the panel")
        back.tap()
        XCTAssertTrue(
            app.buttons["iikb.shelf.transcripts"].waitForExistence(timeout: 3), "back again returns to the menu")

        app.buttons["iikb.shelf.transcripts"].tap()
        XCTAssertTrue(app.collectionViews["iikb.transcripts"].waitForExistence(timeout: 3))
        app.buttons["iikb.more"].tap()
        XCTAssertTrue(wait { self.key("space", in: app).isHittable }, "More gives the keys back from a panel")
        XCTAssertFalse(app.collectionViews["iikb.transcripts"].exists, "and closes it")
    }

    func testTheMenuLetsOutCutCopyAndPasteAndGivesTheKeysBackOnceUsed() throws {
        UIPasteboard.general.string = "Sightglass"
        let app = launch()
        let field = app.textViews.firstMatch
        let tool = app.buttons["iikb.more"]
        XCTAssertTrue(tool.waitForExistence(timeout: 10))
        for letter in "hi" { key(String(letter), in: app).tap() }
        key("space", in: app).tap()
        let paste = app.buttons["iikb.edit.paste"]
        let cut = app.buttons["iikb.edit.cut"]
        XCTAssertFalse(paste.isHittable, "the edits are tucked into the More button")
        tool.tap()
        XCTAssertTrue(wait { paste.isHittable }, "the More button lets them out")
        XCTAssertFalse(cut.isEnabled, "nothing selected, nothing to cut")
        try shot("edits")
        paste.tap()
        let notice = app.staticTexts["iikb.notice"]
        if notice.waitForExistence(timeout: 2), notice.label.contains("Paste from Other Apps") {
            try shot("edits-refused")
            throw XCTSkip(
                "iOS refused the paste and the bar said why: Paste from Other Apps is still Ask (the clipboard panel's test turns it on)"
            )
        }
        XCTAssertTrue(
            wait { (field.value as? String)?.lowercased().hasSuffix("hi sightglass") == true },
            "Paste types what's on the clipboard")
        XCTAssertTrue(wait { !paste.isHittable }, "and they tuck back in")

        tool.tap()
        XCTAssertTrue(wait { paste.isHittable })
        tool.tap()
        XCTAssertTrue(wait { !paste.isHittable }, "More again tucks them back in")

        field.doubleTap()
        tool.tap()
        XCTAssertTrue(wait { cut.isHittable && cut.isEnabled }, "with a selection, Cut and Copy can")
        try shot("edits-selected")
        cut.tap()
        XCTAssertTrue(wait { (field.value as? String)?.contains("Sightglass") == false }, "Cut takes the selection out")
        tool.tap()
        XCTAssertTrue(wait { paste.isHittable && paste.isEnabled })
        paste.tap()
        XCTAssertTrue(
            wait { (field.value as? String)?.contains("Sightglass") == true }, "and Paste puts back what Cut copied")
    }

    func testTranscriptsOpenFromTheirShelfAndTypeWhatYouPick() throws {
        let app = launch()
        open(.transcripts, in: app)
        XCTAssertTrue(
            app.collectionViews["iikb.transcripts"].waitForExistence(timeout: 3),
            "the menu's Transcripts shelf opens them")
        let row = app.descendants(matching: .any).matching(identifier: "iikb.transcript.0").firstMatch
        guard row.waitForExistence(timeout: 5) else {
            XCTAssertTrue(app.buttons["iikb.transcripts.message"].exists, "with nothing dictated, the drawer says so")
            return try shot("transcripts-empty")
        }
        XCTAssertTrue(
            row.staticTexts["iikb.clip.detail"].label.contains(" words · ")
                || row.staticTexts["iikb.clip.detail"].label.contains(" word · "),
            "a row says its words, then how long ago")
        try shot("transcripts")
        let text = row.staticTexts["iikb.clip.text"].label
        row.tap()
        let field = app.textViews.firstMatch
        XCTAssertTrue(
            wait { (field.value as? String)?.contains(text.prefix(20)) == true }, "a tap types it into the app")
        row.press(forDuration: 1.2)
        XCTAssertTrue(
            app.buttons["Copy"].waitForExistence(timeout: 3), "holding a transcript shows it with Paste and Copy")
        try shot("transcripts-preview")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-iikbFocus", "YES", "-iikbOrientation", orientation, "-iikbOneHanded", "off", "-iikbCompactPanels",
            compactSetting ? "YES" : "NO",
        ]
        app.launch()
        if !key("space", in: app).waitForExistence(timeout: 20) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 30), "iikb is not the active keyboard")
        return app
    }

    private enum Shelf: String { case gif, clipboard, transcripts }

    /// Opens a panel the way you do: the More button, then the shelf's name. It opens in the keys' place.
    private func open(_ shelf: Shelf, in app: XCUIApplication) {
        let more = app.buttons["iikb.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "the bar's More button shows")
        more.tap()
        let head = app.buttons["iikb.shelf.\(shelf.rawValue)"]
        XCTAssertTrue(head.waitForExistence(timeout: 3), "the menu has the \(shelf.rawValue) shelf")
        head.tap()
    }

    /// A tap on a panel's search brings the keys up to type into it.
    @discardableResult
    private func raiseKeys(in app: XCUIApplication) -> XCUIElement {
        let search = app.descendants(matching: .any).matching(identifier: "iikb.panel.search").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3), "the panel has its search")
        search.tap()
        XCTAssertTrue(wait(5) { self.key("space", in: app).isHittable }, "tapping the search brings the keys up")
        return search
    }

    private func wait(_ timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private var orientation: String { ProcessInfo.processInfo.environment["IIKB_ORIENTATION"] ?? "portrait" }
    /// `IIKB_OPEN=1`: the iPhone Duo is unfolded, so shots come from its inner screen, not the cover screen it leaves dark.
    private var unfolded: Bool { ProcessInfo.processInfo.environment["IIKB_OPEN"] == "1" }
    /// `IIKB_COMPACT=1` turns on Compact Emoji & GIFs.
    private var compactSetting: Bool { ProcessInfo.processInfo.environment["IIKB_COMPACT"] == "1" }
    /// Landscape, or the setting, shows the panels as one row.
    private var compact: Bool { compactSetting || orientation == "landscape" }

    /// The results sit in one row, and a swipe moves them sideways.
    private func assertOneRowScrollsSideways(_ tiles: XCUIElementQuery, in scroller: XCUIElement, app: XCUIApplication)
    {
        let row = (0..<min(tiles.count, 8)).map { tiles.element(boundBy: $0).frame }
        XCTAssertEqual(Set(row.map(\.minY)).count, 1, "the GIFs are one row")
        let first = tiles.element(boundBy: 0)
        let start = first.frame.minX
        scroller.swipeLeft()
        XCTAssertTrue(wait(5) { first.frame.minX < start - 40 }, "a swipe scrolls the row sideways")
        scroller.swipeRight()
        _ = wait(5) { first.frame.minX == start }
    }

    private func shot(_ name: String) throws {
        guard let shots else { return }
        Thread.sleep(forTimeInterval: 1.5)
        let inner = XCUIScreen.screens.map { $0.screenshot() }.max {
            $0.image.size.width * $0.image.size.height < $1.image.size.width * $1.image.size.height
        }
        let screen = unfolded ? inner : nil
        try (screen ?? XCUIScreen.main.screenshot()).pngRepresentation.write(
            to: URL(fileURLWithPath: "\(shots)-\(name).png"))
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let iikb = app.keys.matching(identifier: "iikb.\(name)").firstMatch
        return iikb.exists ? iikb : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
