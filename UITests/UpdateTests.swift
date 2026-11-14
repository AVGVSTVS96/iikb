import XCTest

/// A newer build on the install link, `scripts/updatetest`'s stand-in for it: the app shows its toast and the
/// keyboard's bar its button, and the button opens the link.
final class UpdateTests: XCTestCase {
    func testANewerBuildOnTheLinkIsOfferedAndTheBarOpensIt() throws {
        guard let shots = ProcessInfo.processInfo.environment["IIKB_SHOTS"] else {
            throw XCTSkip("Run through scripts/updatetest")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbOrientation", "portrait", "-iikbOneHanded", "off"]
        app.launchWithIikb()
        let toast = app.descendants(matching: .any).matching(identifier: "iikb.update.toast").firstMatch
        let button = app.descendants(matching: .any).matching(identifier: "iikb.update").firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 15), "the app shows the toast")
        XCTAssertTrue(button.waitForExistence(timeout: 15), "the bar shows the update's button")
        try shot("\(shots)-offered")

        app.buttons["iikb.update.toast.close"].tap()
        XCTAssertTrue(toast.waitForNonExistence(timeout: 5), "the toast's close button puts it away")
        XCTAssertTrue(button.isHittable, "the bar keeps its button")
        try shot("\(shots)-bar")

        button.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20), "the button opens the link in Safari")
        try shot("\(shots)-link")
    }

    private func shot(_ path: String) throws {
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path + ".png"))
    }
}
