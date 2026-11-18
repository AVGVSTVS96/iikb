import XCTest

final class MicSessionCheck: XCTestCase {
    func testMicOnOffOnAndBehind() throws {
        let iikb = XCUIApplication()
        iikb.launch()
        let mic = iikb.switches["home-mic"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 20))
        func set(_ on: Bool) {
            if (mic.value as? String == "1") != on { mic.switches.firstMatch.tap() }
            let want = on ? "1" : "0"
            let deadline = Date().addingTimeInterval(15)
            while mic.value as? String != want, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
            XCTAssertEqual(mic.value as? String, want)
        }
        set(true)
        set(false)
        set(true)
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        iikb.activate()
        XCTAssertTrue(mic.waitForExistence(timeout: 10))
        XCTAssertEqual(mic.value as? String, "1", "the microphone went off behind")
        set(false)
    }
}
