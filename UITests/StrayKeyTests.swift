import UIKit
import XCTest

/// A key by the space bar hit where a space belonged, through the real keyboard in a field with Instagram's keys.
final class StrayKeyTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = [
            "-iikbFocus", "YES", "-iikbResetSettings", "YES", "-iikbAutoCorrection", "YES", "-iikbAutoCapitalization",
            "NO", "-FullKeyboardType", "\(UIKeyboardType.twitter.rawValue)",
        ]
        app.launchWithIikb()
    }

    /// The words before it are how a new keyboard learns how seldom you type one it doesn't know. A test's taps land
    /// dead center, which teaches it a typist steady enough that an @ hit dead center is meant, so the @ is hit at its
    /// edge by the space bar, where a thumb that misses the bar lands.
    func testAnAtHitForTheSpaceBecomesTheSpace() {
        let known = String(repeating: "the ", count: 12)
        for character in known + "great@day " {
            let key = app.keys.matching(identifier: "iikb.\(character == " " ? "space" : String(character))").firstMatch
            key.coordinate(withNormalizedOffset: CGVector(dx: character == "@" ? 0.1 : 0.5, dy: 0.5)).tap()
        }
        XCTAssertEqual(app.textViews.firstMatch.value as? String, known + "great day ")
    }
}
