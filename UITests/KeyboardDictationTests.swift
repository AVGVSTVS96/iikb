import XCTest

final class KeyboardDictationTests: XCTestCase {
    @MainActor func testTheKeyboardHearsWithTheMicOff() throws {
        guard let shots = ProcessInfo.processInfo.environment["IIKB_SHOTS"] else {
            throw XCTSkip("Run through scripts/keyboardvoicetest")
        }
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments = [
            "-iikbFocus", "YES", "-iikbOrientation", "portrait", "-iikbOneHanded", "off", "-iikbMicKey", "NO",
        ]
        app.launchWithIikb()
        let mic = app.buttons["iikb.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5), "the mic is beside the suggestions")
        XCTAssertTrue(
            wait { mic.label == "Dictate" && (mic.value as? String ?? "").isEmpty },
            "the app's microphone is off, so the keyboard dictates by itself")

        mic.tap()
        try shot("\(shots)-starting")
        XCTAssertTrue(
            wait { mic.label == "Stop Dictating" },
            "the keyboard's own capture hears sound: \(mic.label) \(mic.value as? String ?? "")")
        let time = app.staticTexts["iikb.time"]
        XCTAssertTrue(
            wait { ["0:03", "0:04", "0:05", "0:06"].contains(time.label) },
            "the bar counts what it heard, \(time.label)")
        try shot("\(shots)-recording")

        mic.tap()
        XCTAssertTrue(wait { mic.label == "Dictate" }, "a tap stops it")
    }

    @MainActor private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    @MainActor private func shot(_ path: String) throws {
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path + ".png"))
    }
}
