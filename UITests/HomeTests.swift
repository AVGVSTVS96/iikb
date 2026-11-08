import XCTest

/// Typing in Home's field leaves the rest of Home there, and Done or a tap beside the field puts the keys away, upright
/// and sideways.
final class HomeTests: XCTestCase {
    func testTypingLeavesHomeShowingAndDoneOrATapBesideEndsIt() throws {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let app = XCUIApplication()
            app.launchArguments = ["-iikbFocus", "YES"]
            app.launch()
            let space = app.keys.matching(identifier: "iikb.space").firstMatch
            XCTAssertTrue(space.waitForExistence(timeout: 15), "iikb is not the active keyboard")
            let card = app.buttons["home-dictionary"]
            XCTAssertTrue(card.exists, "\(orientation.rawValue): Home's cards went while typing")
            let field = app.textViews["Try iikb"]
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: 6)).tap()
            XCTAssertTrue(
                space.waitForNonExistence(timeout: 5),
                "\(orientation.rawValue): a tap beside the field left the keys up")
            field.tap()
            XCTAssertTrue(
                space.waitForExistence(timeout: 5), "\(orientation.rawValue): the field didn't take the keys back")
            app.buttons["home-done"].tap()
            XCTAssertTrue(space.waitForNonExistence(timeout: 5), "\(orientation.rawValue): Done left the keys up")
            XCTAssertTrue(
                app.buttons["home-done"].waitForNonExistence(timeout: 5),
                "\(orientation.rawValue): Done stayed once the keys went")
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
