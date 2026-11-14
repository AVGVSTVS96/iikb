import XCTest

extension XCUIApplication {
    /// Launches the app and waits for iikb's keys, failing the test if they never come.
    func launchWithIikb(file: StaticString = #filePath, line: UInt = #line) {
        launch()
        XCTAssertTrue(showsIikb(), "iikb is not the active keyboard", file: file, line: line)
    }

    /// Whether iikb's keys are up, bringing them up as you would when they aren't. On the simulator iOS now and then
    /// starts the keyboard's process without handing it to the app (runningboard logs "_EXConfigureLaunchContext is
    /// obsolete") and shows Apple's keyboard or none: Apple's globe, a key in iikb's app and a button in others, brings
    /// iikb, and when there's no keyboard at all, a fresh launch does, unless `relaunching` is off.
    @discardableResult
    func showsIikb(relaunching: Bool = true) -> Bool {
        let space = keys.matching(identifier: "iikb.space").firstMatch
        for _ in 0..<3 {
            if space.waitForExistence(timeout: 15) { return true }
            let globe = descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'Next keyboard'"))
                .firstMatch
            if globe.exists {
                globe.tap()
            } else if relaunching {
                terminate()
                launch()
            } else {
                return false
            }
        }
        return space.waitForExistence(timeout: 15)
    }
}
