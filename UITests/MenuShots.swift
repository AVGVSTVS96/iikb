import XCTest

/// The menu opening on whatever screen the simulator shows, with Chats from `IIKB_EXTENSION` (scripts/chats.ts), for
/// scripts/menushots: the keys, then the menu, each left as `<prefix>-<name>.hold` for the script to shoot from
/// outside, since `XCUIScreen` shoots the Duo's open screen black. Opening it moves nothing: the bar, More on it, stays
/// where it was, and Paste comes up in it.
final class MenuShots: XCTestCase {
    func testMenuOpensInPlace() throws {
        let environment = ProcessInfo.processInfo.environment
        let prefix = try XCTUnwrap(environment["IIKB_SHOTS"])
        continueAfterFailure = false
        if let url = environment["IIKB_EXTENSION"] {
            let linked = XCUIApplication()
            var link = URLComponents(string: "iikb://extension")!
            link.queryItems = [URLQueryItem(name: "name", value: "Notes"), URLQueryItem(name: "url", value: url)]
            linked.open(link.url!)
            let add = linked.alerts.buttons["Add"]
            if add.waitForExistence(timeout: 10) { add.tap() }
            linked.terminate()
        }
        UIPasteboard.general.string = "Meet at Sightglass on 7th, 4pm?"
        let app = XCUIApplication()
        app.launchArguments = [
            "-iikbFocus", "YES", "-iikbOrientation", environment["IIKB_ORIENTATION"] ?? "portrait", "-iikbText",
            "Coffee at ",
        ]
        app.launchWithIikb()
        let more = app.buttons["iikb.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "the bar's More button shows")
        Thread.sleep(forTimeInterval: 2)
        let keyboard = app.keyboards.firstMatch
        let (moreBefore, keyboardBefore) = (more.frame, keyboard.exists ? keyboard.frame : nil)
        shoot("\(prefix)-keys")
        more.tap()
        let paste = app.buttons["iikb.edit.paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "Paste shows in the bar")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(more.frame, moreBefore, "More stays where it was as the menu opens")
        if let keyboardBefore { XCTAssertEqual(keyboard.frame, keyboardBefore, "the keyboard keeps its size") }
        XCTAssertEqual(paste.frame.midY, moreBefore.midY, accuracy: 1, "Paste sits in the bar, beside More")
        shoot("\(prefix)-menu")
    }

    private func shoot(_ name: String) {
        FileManager.default.createFile(atPath: "\(name).hold", contents: Data("0".utf8))
        let gone = Date().addingTimeInterval(10)
        while FileManager.default.fileExists(atPath: "\(name).hold"), Date() < gone { Thread.sleep(forTimeInterval: 0.1) }
    }
}
