import XCTest

/// Home's switch brings up iikb's tab (`MicTab`), which stays over the Home Screen once iikb leaves, and the switch
/// takes it down. `IIKB_SHOTS` keeps a screenshot of each step.
final class MicTabTests: XCTestCase {
    func testSwitchBringsUpTheTab() throws {
        let iikb = XCUIApplication()
        iikb.launch()
        let mic = iikb.switches["home-mic"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 15))
        if mic.value as? String == "1" { mic.switches.firstMatch.tap() }
        XCTAssertTrue(wait { mic.value as? String == "0" })
        mic.switches.firstMatch.tap()
        XCTAssertTrue(wait { mic.value as? String == "1" }, "the switch didn't stay on")
        try shot("on")
        XCUIDevice.shared.press(.home)
        sleep(2)
        try shot("home")

        iikb.activate()
        XCTAssertTrue(wait { mic.value as? String == "1" }, "the tab went down as iikb came back")
        mic.switches.firstMatch.tap()
        XCTAssertTrue(wait { mic.value as? String == "0" }, "the switch didn't take the tab down")
        try shot("off")
    }

    private func wait(_ condition: () -> Bool) -> Bool {
        for _ in 0..<20 {
            if condition() { return true }
            usleep(250_000)
        }
        return false
    }

    private func shot(_ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["IIKB_SHOTS"] else { return }
        let url = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: url.appending(path: "tab-\(name).png"))
    }
}
