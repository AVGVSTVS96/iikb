import XCTest

/// Apple's emoji keyboard, the reference iikb's is matched against: opened from Apple's emoji key, then a category
/// picked, an emoji with skin tones held, and its search. IIKB_EMOJI_SHOTS names the files; the simulator types with
/// Apple's English and emoji keyboards.
final class AppleEmojiShots: XCTestCase {
    func testApplesEmojiKeyboard() throws {
        guard let prefix = ProcessInfo.processInfo.environment["IIKB_EMOJI_SHOTS"] else {
            throw XCTSkip("Run with IIKB_EMOJI_SHOTS")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES"]
        app.launch()
        let q = app.keys.matching(NSPredicate(format: "label ==[c] 'q'")).firstMatch
        XCTAssertTrue(q.waitForExistence(timeout: 15), "Apple's keyboard is up")
        func shot(_ name: String) throws {
            try app.debugDescription.write(toFile: "\(prefix)-\(name).txt", atomically: true, encoding: .utf8)
            for (index, screen) in XCUIScreen.screens.enumerated() {
                try screen.screenshot().pngRepresentation.write(
                    to: URL(fileURLWithPath: "\(prefix)-\(name)-\(index).png"))
            }
        }
        let emojiKey = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] 'emoji' OR label ==[c] 'next keyboard'")
        ).firstMatch
        XCTAssertTrue(emojiKey.waitForExistence(timeout: 5), "Apple's keyboard has an emoji key")
        try shot("letters")
        emojiKey.tap()
        let abc = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ==[c] 'ABC' OR label ==[c] 'letters'")).firstMatch
        XCTAssertTrue(abc.waitForExistence(timeout: 5), "the emoji keyboard is up")
        try shot("emoji")
        let food = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'food'")).firstMatch
        if food.exists {
            food.tap()
            try shot("food")
        }
        let people = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'smileys'"))
            .firstMatch
        if people.exists { people.tap() }
        let thumbs = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'thumbs up'"))
            .firstMatch
        if thumbs.exists {
            thumbs.press(forDuration: 1.2)
            try shot("tones")
        }
        let search = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'search'"))
            .firstMatch
        if search.exists {
            search.tap()
            try shot("search")
            for letter in "pizza" {
                app.keys.matching(NSPredicate(format: "label ==[c] %@", String(letter))).firstMatch.tap()
            }
            try shot("search-pizza")
        }
    }
}
