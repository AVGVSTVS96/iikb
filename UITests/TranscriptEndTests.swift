import XCTest

/// A transcript's page scrolls far enough upright that its last card, Delete Transcript, sits whole on screen and
/// opens its confirmation, on whatever screen the simulator shows (the folded Duo by default); with `IIKB_SHOTS` set,
/// the screen scrolled to the end goes to `IIKB_SHOTS-end.png`.
final class TranscriptEndTests: XCTestCase {
    func testDeleteTranscriptCanBeReached() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-iikbTab", "transcripts", "-iikbTranscript", "YES"]
        app.launch()
        let delete = app.buttons["Delete Transcript"]
        let window = app.windows.firstMatch
        XCTAssertTrue(
            app.buttons["Back"].firstMatch.waitForExistence(timeout: 15),
            "no transcript opened; the simulator needs one (scripts/sim fill)")
        for _ in 0..<6 { window.swipeUp(velocity: .fast) }
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no Delete Transcript")
        if let prefix = ProcessInfo.processInfo.environment["IIKB_SHOTS"] {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-end.png"))
        }
        XCTAssertTrue(
            delete.isHittable, "Delete Transcript at \(delete.frame) can't be tapped in a window of \(window.frame)")
        XCTAssertLessThanOrEqual(
            delete.frame.maxY, window.frame.maxY,
            "Delete Transcript at \(delete.frame) runs past the window's \(window.frame)")
        let tab = app.buttons["Stats"].firstMatch
        XCTAssertFalse(
            delete.frame.intersects(tab.frame),
            "Delete Transcript at \(delete.frame) sits under the tabs at \(tab.frame)")
        delete.tap()
        XCTAssertTrue(
            app.staticTexts["Delete this transcript?"].waitForExistence(timeout: 5), "Delete Transcript didn't ask")
    }
}
