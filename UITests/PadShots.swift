import XCTest

/// Every state of the keyboard on one screen, through the real extension, for checking a layout on iPad (scripts/padshots):
/// typing with suggestions, the number and symbol layers, the menu, the emoji, GIF, clipboard and
/// Transcripts panels, and the keyboard pinched to float. Screenshots go to `IIKB_SHOTS-<state>.png`; a state the screen
/// doesn't have is left out.
final class PadShots: XCTestCase {
    func testEveryState() throws {
        let prefix = try XCTUnwrap(ProcessInfo.processInfo.environment["IIKB_SHOTS"])
        let only = ProcessInfo.processInfo.environment["IIKB_STATES"].flatMap {
            $0.isEmpty ? nil : Set($0.split(separator: " ").map(String.init))
        }
        func wanted(_ state: String) -> Bool { only?.contains(state) ?? true }
        func shot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 0.8)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "-iikbFocus", "YES", "-iikbOrientation",
            ProcessInfo.processInfo.environment["IIKB_ORIENTATION"] ?? "portrait", "-iikbOneHanded", "off",
        ]
        app.launch()
        XCUIDevice.shared.orientation =
            ProcessInfo.processInfo.environment["IIKB_ORIENTATION"] == "landscape" ? .landscapeLeft : .portrait
        let space = key("space", in: app)
        XCTAssertTrue(space.waitForExistence(timeout: 30), "iikb is not the active keyboard")
        try shot("empty")
        try app.debugDescription.write(toFile: "\(prefix)-empty.txt", atomically: true, encoding: .utf8)
        for letter in "coffee at" { key(letter == " " ? "space" : String(letter), in: app).tap() }
        try shot("main")

        if wanted("layers"), key("numbers", in: app).exists {
            key("numbers", in: app).tap()
            try shot("numbers")
            if key("symbols", in: app).exists {
                key("symbols", in: app).tap()
                try shot("symbols")
            }
            if key("letters", in: app).exists { key("letters", in: app).tap() }
        }
        if wanted("more"), app.buttons["iikb.more"].exists {
            app.buttons["iikb.more"].tap()
            Thread.sleep(forTimeInterval: 2)
            try shot("more")
            app.buttons["iikb.more"].tap()
        }
        for (panel, tool) in [("emoji", "iikb.tool.emoji"), ("gif", "iikb.shelf.gif")] where wanted(panel) {
            if panel == "gif", app.buttons["iikb.more"].exists { app.buttons["iikb.more"].tap() }
            let button = app.buttons[tool].waitForExistence(timeout: 2) ? app.buttons[tool] : key("emoji", in: app)
            guard button.exists else { continue }
            button.tap()
            Thread.sleep(forTimeInterval: panel == "gif" ? 4 : 1)
            try shot(panel)
            app.buttons["iikb.panel.back"].tap()
        }
        if wanted("clipboard"), app.buttons["iikb.more"].exists {
            app.buttons["iikb.more"].tap()
            app.buttons["iikb.shelf.clipboard"].tap()
            try shot("clipboard")
            app.buttons["iikb.panel.back"].tap()
        }
        if wanted("window"), let size = ProcessInfo.processInfo.environment["IIKB_WINDOW"].flatMap(Self.size) {
            resize(app.windows.firstMatch, to: size)
            let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
            if field.exists { field.tap() }
            Thread.sleep(forTimeInterval: 2)
            try shot("window")
            print(
                "WINDOW \(app.windows.firstMatch.frame.debugDescription) space \(space.exists ? space.frame.debugDescription : "gone") keyboard \(app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.debugDescription : "none")"
            )
        }
        if wanted("floating"), key("g", in: app).exists {
            let keyboard = app.keyboards.firstMatch
            (keyboard.exists ? keyboard : key("g", in: app)).pinch(withScale: 0.3, velocity: -0.6)
            Thread.sleep(forTimeInterval: 2)
            try shot("floating")
            print("FLOATING space \(space.exists ? space.frame.debugDescription : "gone")")
        }
    }

    private static func size(_ spec: String) -> CGSize? {
        let parts = spec.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
    }

    /// Drags the window's bottom right corner toward `size`, as AppShots does, the way a person makes a Split View or
    /// Stage Manager window: by half the gap each time, since iPadOS resizes by about twice a drag.
    private func resize(_ window: XCUIElement, to size: CGSize) {
        let screen = XCUIApplication(bundleIdentifier: "com.apple.springboard").coordinate(withNormalizedOffset: .zero)
        for _ in 0..<10 {
            let frame = window.frame
            let change = CGVector(dx: (size.width - frame.width) / 2, dy: (size.height - frame.height) / 2)
            guard abs(change.dx) > 3 || abs(change.dy) > 3 else { return }
            let corner = screen.withOffset(CGVector(dx: frame.maxX - 6, dy: frame.maxY - 6))
            corner.press(
                forDuration: 0.5, thenDragTo: corner.withOffset(change), withVelocity: .slow, thenHoldForDuration: 0.5)
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.keys.matching(NSPredicate(format: "identifier == %@ OR label ==[c] %@", "iikb.\(name)", name)).firstMatch
    }
}
