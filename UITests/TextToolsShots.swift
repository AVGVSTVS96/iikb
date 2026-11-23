import XCTest

/// The text tools through the real keyboard, for scripts/texttoolshots: a calculation's answer in the bar typed in its
/// place, then Text Styles and Change Case from the menu, on the selection and then on the whole message. Each step is
/// left as `<prefix>-<name>.hold` for the script to shoot from outside, since `XCUIScreen` shoots the Duo's open screen
/// black. Each launch is a test of its own: together they ran past the 5 minutes a test gets on GitHub's Macs.
final class TextToolsShots: XCTestCase {
    private var prefix = ""
    private var app = XCUIApplication()
    private var field: XCUIElement { app.textViews.firstMatch }

    private var cases: XCUIElement { app.buttons["iikb.shelf.changeCase"] }

    override func setUp() {
        prefix = ProcessInfo.processInfo.environment["IIKB_SHOTS"] ?? NSTemporaryDirectory() + "texttools"
        continueAfterFailure = false
    }

    func testTheBarsCalculatorAndTheTextTools() throws {
        let environment = ProcessInfo.processInfo.environment
        app.launchArguments = [
            "-iikbFocus", "YES", "-iikbOrientation", environment["IIKB_ORIENTATION"] ?? "portrait", "-iikbText",
            "Dinner for four was 84 ",
        ]
        app.launchWithIikb()
        key("numbers").tap()
        key("/").tap()
        key("space").tap()
        if !key("4").exists { key("numbers").tap() }
        key("4").tap()
        let answer = app.descendants(matching: .any).matching(identifier: "iikb.suggestion.0").firstMatch
        XCTAssertTrue(wait { answer.label == "21" }, "the bar answers the calculation")
        shoot("calculator")
        answer.tap()
        XCTAssertTrue(wait { self.value == "Dinner for four was 21 " }, "a tap types the answer in its place")

        let more = app.buttons["iikb.more"]
        more.tap()
        let styles = app.buttons["iikb.shelf.textStyles"]
        XCTAssertTrue(styles.waitForExistence(timeout: 5), "the menu has a Text Styles shelf")
        open(styles)
        shoot("styles")
        pick("Bold Serif", in: "textStyles")
        XCTAssertTrue(wait { self.value == "𝐃𝐢𝐧𝐧𝐞𝐫 𝐟𝐨𝐫 𝐟𝐨𝐮𝐫 𝐰𝐚𝐬 𝟐𝟏 " }, "a style rewrites the whole message")
        shoot("styled")
        pick("Italic Serif", in: "textStyles")
        XCTAssertTrue(wait { self.value == "𝐷𝑖𝑛𝑛𝑒𝑟 𝑓𝑜𝑟 𝑓𝑜𝑢𝑟 𝑤𝑎𝑠 21 " }, "the next style replaces it")

        app.buttons["iikb.panel.back"].tap()
        scroll(to: cases)
        shoot("menu")
        open(cases)
        pick("lowercase", in: "changeCase")
        pick("Title Case", in: "changeCase")
        XCTAssertTrue(wait { self.value == "𝐷𝑖𝑛𝑛𝑒𝑟 𝑓𝑜𝑟 𝐹𝑜𝑢𝑟 𝑊𝑎𝑠 21 " }, "cases keep the style")
        shoot("cased")
    }

    func testChangeCaseChangesOnlyTheSelection() {
        let original = "say hello to everyone"
        app.launchArguments = ["-iikbFocus", "YES", "-iikbText", original]
        app.launchWithIikb()
        field.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 60, dy: 20)).doubleTap()
        Thread.sleep(forTimeInterval: 1)
        app.buttons["iikb.more"].tap()
        open(cases)
        pick("UPPERCASE", in: "changeCase")
        XCTAssertTrue(wait { self.value != original }, "Uppercase changes the selection")
        XCTAssertNotEqual(value, original.uppercased(), "only the selection")
        XCTAssertEqual(value?.lowercased(), original, "and nothing else")
        shoot("selection")
    }

    func testChangeCaseCountsEmojiAndStyledLettersWhole() {
        let wide = "😀 hi 𝐛𝐨𝐥𝐝 end"
        app.launchArguments = ["-iikbFocus", "YES", "-iikbText", wide]
        app.launchWithIikb()
        field.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 20)).tap()
        Thread.sleep(forTimeInterval: 1)
        app.buttons["iikb.more"].tap()
        open(cases)
        pick("UPPERCASE", in: "changeCase")
        XCTAssertTrue(wait { self.value != wide }, "Uppercase changes the whole field from its start")
        XCTAssertEqual(value, "😀 HI 𝐁𝐎𝐋𝐃 END", "over emoji and styled letters, two units each")
        app.buttons["iikb.more"].tap()
        key("x").tap()
        XCTAssertEqual(value.map { String($0.dropLast()) }, "😀 HI 𝐁𝐎𝐋𝐃 END", "the caret ends after it")
        XCTAssertEqual(value?.last?.lowercased(), "x", "where the key types")
    }

    func testChangeCaseChangesEveryLine() throws {
        app.launchArguments = ["-iikbFocus", "YES", "-iikbText", "one"]
        app.launchWithIikb()
        Thread.sleep(forTimeInterval: 1)
        key("return").tap()
        key("return").tap()
        for letter in "two" { key(String(letter)).tap() }
        let lines = try XCTUnwrap(value)
        XCTAssertEqual(lines.lowercased(), "one\n\ntwo", "return breaks the line")
        app.buttons["iikb.more"].tap()
        open(cases)
        pick("UPPERCASE", in: "changeCase")
        XCTAssertTrue(wait { self.value != lines }, "Uppercase changes a field of several lines")
        XCTAssertEqual(value, "ONE\n\nTWO", "every line of it")
    }

    private var value: String? { field.value as? String }

    private func key(_ name: String) -> XCUIElement {
        let iikb = app.keys.matching(identifier: "iikb.\(name)").firstMatch
        return iikb.exists ? iikb : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }

    /// Drags the menu slowly, holding at the end so it doesn't glide past, until `element` is wholly between the bar
    /// and the screen's bottom.
    private func scroll(to element: XCUIElement) {
        let window = app.windows.firstMatch
        let top = app.buttons["iikb.more"].frame.maxY
        let start = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.frame.width * 0.8, dy: top + 60))
        for _ in 0..<14 {
            guard element.waitForExistence(timeout: 2) else { return }
            let frame = element.frame
            if frame.minY < top {
                start.press(
                    forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 60)), withVelocity: .slow,
                    thenHoldForDuration: 0.3)
            } else if frame.maxY > window.frame.maxY {
                start.press(
                    forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -60)), withVelocity: .slow,
                    thenHoldForDuration: 0.3)
            } else {
                return
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// Opens the panel a shelf's name opens, scrolling the menu to it.
    private func open(_ shelf: XCUIElement) {
        scroll(to: shelf)
        shelf.tap()
        XCTAssertTrue(app.buttons["iikb.panel.back"].waitForExistence(timeout: 5), "\(shelf.label) opens its panel")
    }

    /// Taps the row named `name` in the open panel, dragging its list up until the row is wholly in it.
    private func pick(_ name: String, in panel: String) {
        let list = app.descendants(matching: .any).matching(identifier: "iikb.\(panel)").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "the \(panel) panel's list")
        let row = list.cells["iikb.rewrite.\(name)"]
        let sideways = list.frame.height < 120
        for _ in 0..<8 where !(row.exists && list.frame.contains(row.frame)) {
            let start = list.coordinate(
                withNormalizedOffset: CGVector(dx: sideways ? 0.8 : 0.5, dy: sideways ? 0.5 : 0.8))
            start.press(
                forDuration: 0.1,
                thenDragTo: start.withOffset(CGVector(dx: sideways ? -120 : 0, dy: sideways ? 0 : -80)))
        }
        row.tap()
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(5)
        while Date() < until {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    private func shoot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let hold = "\(prefix)-\(name).hold"
        FileManager.default.createFile(atPath: hold, contents: Data("0".utf8))
        let gone = Date().addingTimeInterval(10)
        while FileManager.default.fileExists(atPath: hold), Date() < gone {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}
