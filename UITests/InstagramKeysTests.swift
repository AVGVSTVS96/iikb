import UIKit
import XCTest

/// The full keyboard in a field with Instagram's keys, through the real keyboard: its @ and # aren't on the letters'
/// bottom row, so a tap at the space bar's right end, where they were, is a space.
final class InstagramKeysTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = [
            "-iikbFocus", "YES", "-iikbResetSettings", "YES", "-iikbAutoCapitalization", "NO", "-FullKeyboardType",
            "\(UIKeyboardType.twitter.rawValue)",
        ]
        app.launchWithIikb()
    }

    func testTheSpaceBarsEndIsASpace() {
        XCTAssertFalse(app.keys.matching(identifier: "iikb.@").firstMatch.exists)
        XCTAssertFalse(app.keys.matching(identifier: "iikb.#").firstMatch.exists)
        for character in "great day " {
            let key = app.keys.matching(identifier: "iikb.\(character == " " ? "space" : String(character))").firstMatch
            key.coordinate(withNormalizedOffset: CGVector(dx: character == " " ? 0.95 : 0.5, dy: 0.5)).tap()
        }
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "great day ")
    }
}
