import XCTest

/// The emoji keyboard through the real keyboard: the emoji key puts it in the keys' place, a category's tap shows its
/// page, a tap types an emoji into the app and delete deletes there, its search field brings the keys up to type into
/// it, the emoji key goes back to the pages and ABC to the letters. With IIKB_SHOTS set, screenshots each step.
final class PanelTests: XCTestCase {
    func testTheEmojiKeyboardPagesSearchesAndTypesWhatYouPick() throws {
        let shots = ProcessInfo.processInfo.environment["IIKB_SHOTS"]
        let app = launchAndType("coffee at")
        try shot(shots, "main")

        let emojiKey = key("emoji", in: app)
        openEmoji(in: app)
        let grid = app.collectionViews["iikb.emoji"]
        let letters = app.descendants(matching: .any).matching(identifier: "iikb.emoji.abc").firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 3), "the emoji key opens the emoji keyboard")
        XCTAssertTrue(letters.exists, "with ABC")
        XCTAssertFalse(key("q", in: app).isHittable, "in the keys' place")
        try shot(shots, "emoji")

        app.descendants(matching: .any).matching(identifier: "iikb.emoji.category.food").firstMatch.tap()
        let grapes = app.descendants(matching: .any).matching(identifier: "iikb.emoji.🍇").firstMatch
        XCTAssertTrue(wait { grapes.exists && grapes.isHittable }, "a category's tap shows its page from its start")
        try shot(shots, "food")
        grapes.tap()
        let field = app.textViews.firstMatch
        XCTAssertTrue(wait { (field.value as? String) == "Coffee at🍇" }, "a tap types the emoji into the app")
        app.descendants(matching: .any).matching(identifier: "iikb.emoji.delete").firstMatch.tap()
        XCTAssertTrue(wait { (field.value as? String) == "Coffee at" }, "delete deletes in the app")

        let search = searchEmoji("pizza", in: app, opening: false)
        let pizza = app.descendants(matching: .any).matching(identifier: "iikb.emoji.🍕").firstMatch
        XCTAssertEqual(field.value as? String, "Coffee at", "the keys type into the search, not the app")
        XCTAssertTrue(pizza.waitForExistence(timeout: 3), "searching finds the emoji by name")
        assertOneRow(grid.cells)
        try shot(shots, "search")
        pizza.tap()
        XCTAssertTrue(wait { (field.value as? String) == "Coffee at🍕" }, "a found emoji types into the app")

        key("emoji", in: app).tap()
        XCTAssertTrue(
            wait { letters.exists && (search.value as? String) == "" }, "the emoji key goes back to the pages")
        letters.tap()
        XCTAssertTrue(wait { emojiKey.isHittable && !grid.exists }, "ABC brings the letters back")
        try shot(shots, "after")
    }

    func testHoldingDeleteToEmptyTheSearchLeavesTheMessageAlone() throws {
        let app = launchAndType("coffee at")
        let search = searchEmoji("pizza", in: app)
        key("delete", in: app).press(forDuration: 3)
        XCTAssertTrue(wait { (search.value as? String) == "" }, "holding delete empties the search")
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "Coffee at", "and stops there, before the message")
    }

    func testHoldingAnEmojiAtTheRightEdgeWithoutSlidingPicksIt() throws {
        let app = launchAndType("hi ")
        _ = searchEmoji("hand", in: app)
        let cells = app.collectionViews["iikb.emoji"].cells
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 3))
        let window = app.windows.firstMatch.frame
        let row = (0..<min(cells.count, 20)).map { cells.element(boundBy: $0) }.filter {
            $0.frame.maxX <= window.maxX
        }
        let edge = try XCTUnwrap(row.max { $0.frame.maxX < $1.frame.maxX })
        let emoji = edge.label
        edge.press(forDuration: 1)
        let field = app.textViews.firstMatch
        XCTAssertTrue(wait { (field.value as? String) != "Hi " })
        XCTAssertEqual(field.value as? String, "Hi " + emoji, "letting go where the hold began picks the emoji held")
    }

    private var orientation: String { ProcessInfo.processInfo.environment["IIKB_ORIENTATION"] ?? "portrait" }

    /// The menu's Theme and Stop Animation shelves pick the keyboard's look in place, a tap each, and the app's
    /// Appearance page shows what they picked. With IIKB_SHOTS set, screenshots the menu before and after, and the page.
    func testTheMenuPicksTheThemeAndStopAnimation() throws {
        let shots = ProcessInfo.processInfo.environment["IIKB_SHOTS"]
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-iikbFocus", "YES", "-iikbOrientation", "portrait", "-iikbOneHanded", "off", "-iikbTheme", "standard",
            "-iikbStopAnimation", "squeeze",
        ]
        app.launchWithIikb()
        app.buttons["iikb.more"].tap()
        let mechanical = app.buttons["iikb.look.theme.mechanical"]
        let drain = app.buttons["iikb.look.stop.drain"]
        let clipboard = app.buttons["iikb.shelf.clipboard"]
        XCTAssertTrue(clipboard.waitForExistence(timeout: 3), "the menu opens on the histories")
        try shot(shots, "menu-top")
        let stop = app.buttons["iikb.shelf.stop"]
        let window = app.windows.firstMatch
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: window.frame.width * 0.8, dy: clipboard.frame.midY))
        for _ in 0..<3 where !(stop.exists && stop.frame.maxY < window.frame.maxY) {
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -300)))
        }
        try shot(shots, "menu-scrolled")
        XCTAssertTrue(
            wait { stop.exists && stop.frame.maxY < window.frame.maxY },
            "the themes and stop animations are a scroll below the histories")
        XCTAssertTrue(app.buttons["iikb.look.theme.standard"].isSelected, "with the one in use picked")
        XCTAssertTrue(app.buttons["iikb.look.stop.squeeze"].isSelected)
        try shot(shots, "menu-look")

        mechanical.tap()
        XCTAssertTrue(wait { mechanical.isSelected }, "a tap picks a theme")
        drain.tap()
        XCTAssertTrue(wait { drain.isSelected }, "and a stop animation")
        try shot(shots, "menu-look-picked")
        app.buttons["iikb.more"].tap()
        try shot(shots, "menu-look-keys")

        app.terminate()
        app.launchArguments = ["-iikbSettings", "appearance"]
        app.launch()
        Thread.sleep(forTimeInterval: 2)
        try shot(shots, "menu-look-app")
        app.terminate()
        app.launchArguments = [
            "-iikbFocus", "YES", "-iikbOrientation", "portrait", "-iikbTheme", "standard", "-iikbStopAnimation",
            "squeeze",
        ]
        app.launch()
    }

    private func launchAndType(_ text: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-iikbFocus", "YES", "-iikbOrientation", orientation, "-iikbOneHanded", "off", "-iikbAutoCapitalization",
            "YES",
        ]
        app.launchWithIikb()
        for letter in text { key(letter == " " ? "space" : String(letter), in: app).tap() }
        return app
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    private func shot(_ prefix: String?, _ name: String) throws {
        guard let prefix else { return }
        Thread.sleep(forTimeInterval: 0.8)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
        for (index, screen) in XCUIScreen.screens.enumerated() where index > 0 {
            try screen.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-\(name)-\(index).png"))
        }
    }

    /// The key on screen by that name: while the panel opens, iOS can still hold a copy of the letters off screen.
    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let keys = app.keys.matching(NSPredicate(format: "identifier == %@ OR label ==[c] %@", "iikb.\(name)", name))
        return keys.allElementsBoundByIndex.first(where: \.isHittable) ?? keys.firstMatch
    }

    /// The results sit in one row, as Apple's search shows them.
    private func assertOneRow(_ cells: XCUIElementQuery) {
        let row = (0..<min(cells.count, 12)).map { cells.element(boundBy: $0).frame }
        XCTAssertFalse(row.isEmpty)
        XCTAssertEqual(Set(row.map(\.minY)).count, 1, "the results are one row")
    }

    /// The emoji keyboard's search, `query` typed into it by the keys its field brings up.
    private func searchEmoji(_ query: String, in app: XCUIApplication, opening: Bool = true) -> XCUIElement {
        if opening { openEmoji(in: app) }
        let letters = app.descendants(matching: .any).matching(identifier: "iikb.emoji.abc").firstMatch
        XCTAssertTrue(wait { letters.isHittable }, "the emoji keyboard is up")
        let search = app.descendants(matching: .any).matching(identifier: "iikb.panel.search").firstMatch
        XCTAssertTrue(search.isHittable, "its search sits over it")
        search.tap()
        XCTAssertTrue(wait { self.key("space", in: app).isHittable }, "the field brings the keys up")
        for letter in query { key(String(letter), in: app).tap() }
        XCTAssertTrue(wait { (search.value as? String) == query }, "the keys type into the search")
        return search
    }

    private func openEmoji(in app: XCUIApplication) {
        let emoji = key("emoji", in: app)
        XCTAssertTrue(emoji.waitForExistence(timeout: 5), "the emoji key sits beside the space bar")
        emoji.tap()
    }
}
