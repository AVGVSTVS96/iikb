import XCTest

final class SettingsAppTests: XCTestCase {
    func testSettingsAppSharesSwitchesWithApp() throws {
        let iikb = XCUIApplication()
        iikb.launchArguments = ["-iikbResetSettings", "YES", "-iikbSettings", "appearance"]
        iikb.launch()
        let inApp = iikb.switches["Emoji Key"]
        XCTAssertTrue(inApp.waitForExistence(timeout: 5))
        XCTAssertEqual(inApp.value as? String, "1")
        iikb.terminate()

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let back = settings.buttons.matching(identifier: "BackButton").firstMatch
        while back.waitForExistence(timeout: 2) { back.tap() }
        let apps = settings.buttons["Apps"].firstMatch
        while !apps.isHittable { settings.swipeUp() }
        apps.tap()
        let entry = settings.buttons["iikb"].firstMatch
        while !entry.isHittable { settings.swipeUp() }
        entry.tap()
        open("Layout", in: settings)
        let inSettings = settings.switches["Emoji Key"]
        XCTAssertTrue(inSettings.waitForExistence(timeout: 5))
        if let path = ProcessInfo.processInfo.environment["IIKB_SETTINGS_SHOT"] {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
        inSettings.switches.firstMatch.tap()
        XCTAssertEqual(inSettings.value as? String, "0")
        settings.terminate()

        iikb.launchArguments = ["-iikbSettings", "appearance"]
        iikb.launch()
        XCTAssertTrue(inApp.waitForExistence(timeout: 5))
        XCTAssertEqual(inApp.value as? String, "0")
    }

    func testKeepMicOnIsPickedInAppAndShownInSettings() throws {
        let iikb = XCUIApplication()
        iikb.launchArguments = ["-iikbResetSettings", "YES", "-iikbSettings", "voice"]
        iikb.launch()
        let picked = iikb.buttons["5 Minutes"]
        XCTAssertTrue(picked.waitForExistence(timeout: 5))
        reveal(picked, in: iikb)
        XCTAssertTrue(picked.isSelected)
        try shot(iikb, "keep-mic-on-choices")
        let minute = iikb.buttons["1 Minute"]
        reveal(minute, in: iikb)
        minute.tap()
        XCTAssertTrue(minute.isSelected)
        XCTAssertFalse(picked.isSelected)
        iikb.terminate()

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let back = settings.buttons.matching(identifier: "BackButton").firstMatch
        while back.waitForExistence(timeout: 2) { back.tap() }
        let apps = settings.buttons["Apps"].firstMatch
        while !apps.isHittable { settings.swipeUp() }
        apps.tap()
        let entry = settings.buttons["iikb"].firstMatch
        while !entry.isHittable { settings.swipeUp() }
        entry.tap()
        open("Voice Typing", in: settings)
        XCTAssertTrue(settings.staticTexts["Keep Mic On"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            settings.descendants(matching: .any).matching(
                NSPredicate(format: "label == '1 Minute' OR value == '1 Minute'")
            ).firstMatch.exists)
        try shot(settings, "keep-mic-on-settings")
        settings.terminate()
    }

    /// Scrolls a short way at a time until the row sits clear of the page's title, where a tap reaches it: a swipe can
    /// fling it up under the title, which takes the tap.
    private func reveal(_ row: XCUIElement, in app: XCUIApplication) {
        let middle = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let title = app.navigationBars.firstMatch.frame.maxY
        for _ in 0..<10 where !row.isHittable || row.frame.minY < title {
            let up = row.frame.minY >= title
            middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: up ? -150 : 150)))
        }
    }

    /// Opens one of iikb's pages in Settings › Apps › iikb.
    private func open(_ page: String, in settings: XCUIApplication) {
        let row = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", page)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        while !row.isHittable { settings.swipeUp() }
        row.tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["IIKB_SHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }
}
