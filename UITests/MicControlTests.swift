import XCTest

/// Control Center's iikb Mic, end to end: the app's microphone on, the control added and shown on, a tap on it, and the
/// app's switch off without iikb coming forward. `IIKB_SHOTS` keeps a screenshot of each step.
final class MicControlTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testMicControlTurnsTheMicrophoneOff() throws {
        let iikb = XCUIApplication()
        iikb.launch()
        let mic = iikb.switches["home-mic"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 15))
        if mic.value as? String != "1" { mic.switches.firstMatch.tap() }
        XCTAssertTrue(wait { mic.value as? String == "1" }, "the app's microphone didn't turn on")
        XCUIDevice.shared.press(.home)

        openControlCenter()
        let control = springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'iikb Mic'")
        ).firstMatch
        if !control.waitForExistence(timeout: 3) { addControl() }
        XCTAssertTrue(control.waitForExistence(timeout: 10), springboard.debugDescription)
        try shot("on")
        control.tap()
        try shot("tapped")

        iikb.activate()
        XCTAssertTrue(
            wait { mic.value as? String == "0" }, "the app's microphone stayed on after the control was tapped")
        XCUIDevice.shared.press(.home)
        openControlCenter()
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        try shot("off")
    }

    private func openControlCenter() {
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.005))
        top.press(
            forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.7)))
        sleep(2)
    }

    /// Edit mode's "+" and Add a Control's gallery, searched for iikb.
    private func addControl() {
        let any = springboard.descendants(matching: .any)
        let plus = any.matching(NSPredicate(format: "label IN {'Add', 'Edit', 'Edit Controls', 'Add Controls'}"))
            .firstMatch
        if plus.waitForExistence(timeout: 3) {
            plus.tap()
        } else {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).press(forDuration: 1.5)
        }
        let add = any.matching(NSPredicate(format: "label CONTAINS[c] 'Add a Control'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), springboard.debugDescription)
        add.tap()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), springboard.debugDescription)
        search.tap()
        search.typeText("iikb")
        let entry = any.matching(NSPredicate(format: "label CONTAINS[c] 'iikb Mic'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10), springboard.debugDescription)
        entry.tap()
        sleep(2)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()
        sleep(1)
    }

    private func wait(_ done: () -> Bool) -> Bool {
        for _ in 0..<20 {
            if done() { return true }
            sleep(1)
        }
        return false
    }

    private func shot(_ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["IIKB_SHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }
}
