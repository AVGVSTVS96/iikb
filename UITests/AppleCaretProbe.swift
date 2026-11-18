import XCTest

final class AppleCaretProbe: XCTestCase {
    func testCarets() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["IIKB_PROBE_OUT"] else { throw XCTSkip("probe") }
        let cases: [(String, Int)] = [
            ("Coffee at ge", 12), ("Coffee at ge", 0), ("Coffee at ge", 3), ("Coffee at ge", 6),
            ("Coffee at ge", 7), ("Coffee at ge", 8), ("Coffee at ge", 9), ("Coffee at ge", 10),
            ("I like coffee. See you", 15), ("I like coffee. See you", 14), ("I like coffee. See you", 17),
            ("hello world", 6), ("hello world", 0), ("hello world", 2), ("Thx", 0), ("teh cat", 3), ("teh cat", 1),
            ("I went home", 2), ("I went home", 4), ("Good morning", 5), ("Good morning", 12),
        ]
        var out = ""
        for (text, caret) in cases {
            let app = XCUIApplication()
            app.launchArguments = [
                "-iikbFocus", "YES", "-iikbOrientation", "portrait", "-iikbText", text, "-iikbCaret", "\(caret)",
            ]
            app.launch()
            XCTAssertTrue(
                app.keys.matching(NSPredicate(format: "label ==[c] 'a'")).firstMatch.waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 2.5)
            let labels = read(app)
            Thread.sleep(forTimeInterval: 1.5)
            let later = read(app)
            let shift = app.keys.allElementsBoundByIndex.first { $0.label.lowercased() == "shift" }
            let shiftValue = (shift?.value as? String) ?? "?"
            out += "\(text.replacingOccurrences(of: " ", with: "_"))@\(caret) | \(labels.joined(separator: ", ")) | later: \(later.joined(separator: ", ")) | shift=\(shiftValue)\n"
            let shot = XCUIScreen.main.screenshot()
            try shot.pngRepresentation.write(
                to: URL(fileURLWithPath: "\(output)-\(text.replacingOccurrences(of: " ", with: "_"))-\(caret).png"))
            try out.write(toFile: output + ".txt", atomically: true, encoding: .utf8)
            app.terminate()
        }
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbOrientation", "portrait", "-iikbText", "Coffee at ge"]
        app.launch()
        XCTAssertTrue(
            app.keys.matching(NSPredicate(format: "label ==[c] 'a'")).firstMatch.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)
        out += "trackpad before | \(read(app).joined(separator: ", "))\n"
        let space = app.keys.allElementsBoundByIndex.first { $0.label.lowercased() == "space" }!
        space.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 1.2, thenDragTo: space.coordinate(withNormalizedOffset: CGVector(dx: -1.5, dy: 0.5)),
            withVelocity: .slow, thenHoldForDuration: 1)
        Thread.sleep(forTimeInterval: 2.5)
        out += "trackpad after release | \(read(app).joined(separator: ", ")) | value=\(app.textViews.firstMatch.value ?? "")\n"
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(output)-trackpad.png"))
        try out.write(toFile: output + ".txt", atomically: true, encoding: .utf8)
    }

    private func read(_ app: XCUIApplication) -> [String] {
        guard let snapshot = try? app.otherElements["Typing Predictions"].snapshot() else { return ["<no bar>"] }
        var labels: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .button { labels.append(node.label) }
            node.children.forEach(walk)
        }
        walk(snapshot)
        return labels
    }
}
