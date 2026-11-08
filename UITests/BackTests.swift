import XCTest

/// A page opened from another in its tab has one Back, in the Duo's side bar with the tabs, upright and sideways, and
/// both it and a swipe from the leading edge go back.
final class BackTests: XCTestCase {
    func testBackSitsWithTheTabsAndGoesBack() throws {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for page in [["-iikbSettings", "appearance"], ["-iikbTab", "transcripts", "-iikbTranscript", "YES"]] {
                let app = XCUIApplication()
                app.launchArguments = page
                app.launch()
                let backs = app.buttons.matching(NSPredicate(format: "label == 'Back'"))
                let back = backs.firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 15), "\(page): no Back")
                XCTAssertEqual(backs.count, 1, "\(page): more than one Back")
                let tab = app.buttons["Stats"].firstMatch
                XCTAssertTrue(
                    tab.exists, "\(page): no Stats tab among \(app.buttons.allElementsBoundByIndex.map(\.label))")
                XCTAssertLessThan(
                    abs(back.frame.midX - tab.frame.midX), 12,
                    "\(page) \(orientation.rawValue): Back at \(back.frame), tabs at \(tab.frame)")
                back.tap()
                XCTAssertTrue(back.waitForNonExistence(timeout: 5), "\(page): Back didn't go back")
                app.terminate()

                app.launch()
                XCTAssertTrue(back.waitForExistence(timeout: 15))
                let window = app.windows.firstMatch
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
                    .press(
                        forDuration: 0.05,
                        thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
                XCTAssertTrue(back.waitForNonExistence(timeout: 5), "\(page): a swipe from the edge didn't go back")
                app.terminate()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
