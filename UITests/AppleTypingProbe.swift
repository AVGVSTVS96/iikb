import XCTest

/// Measures Apple's keyboard where iikb's typing follows it, writing what the field holds after each step to
/// IIKB_PROBE_OUT and screenshots beside it: a space after a word picked from the bar, a swipe after deleting its word,
/// and the bar on an empty field after a copy. The trackpad's speed isn't measured: the simulator's synthesized touches
/// don't carry the speed they're given, so a drag read the same at every speed.
final class AppleTypingProbe: XCTestCase {
    private var app: XCUIApplication!
    private var field: XCUIElement!
    private var out = ""
    private var path = ""

    override func setUpWithError() throws {
        guard let output = ProcessInfo.processInfo.environment["IIKB_PROBE_OUT"] else {
            throw XCTSkip("Run through scripts/appleprobe")
        }
        path = output
        app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbOrientation", "portrait"]
        app.launch()
        field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(key("a").waitForExistence(timeout: 10))
    }

    func testAPickThenSpace() throws {
        for (typed, step) in [("hel", "pick"), ("goo", "pick2")] {
            clear()
            typed.forEach { key(String($0)).tap() }
            let picked = try XCTUnwrap(settledBar().first { !$0.label.hasPrefix("“") }, "no word in the bar")
            note("\(step) bar", barLabels().joined(separator: ","))
            picked.tap()
            note("\(step) after pick", value())
            for space in 1...3 {
                key("space").tap()
                note("\(step) after space \(space)", value())
            }
            shot("\(step)")
        }
        clear()
        "hel".forEach { key(String($0)).tap() }
        try XCTUnwrap(settledBar().first { !$0.label.hasPrefix("“") }).tap()
        (key("more").exists ? key("more") : key("numbers")).tap()
        key(".").tap()
        note("pick then period", value())
    }

    func testASwipeAfterDeletingItsWord() throws {
        for (before, word) in [("", "hello"), ("", "good"), ("so ", "good")] {
            clear()
            if !before.isEmpty { field.typeText(before) }
            for attempt in 1...4 {
                try swipe(word)
                note("swipe \(before)\(word) \(attempt)", value())
                note("swipe \(before)\(word) \(attempt) bar", barLabels().joined(separator: ","))
                key("delete").tap()
                note("swipe \(before)\(word) \(attempt) deleted", value())
            }
        }
    }

    func testTheBarAfterACopy() throws {
        clear()
        shot("empty-before-copy")
        UIPasteboard.general.string = "Copied by the probe"
        app.terminate()
        app.launch()
        XCTAssertTrue(key("a").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        note("bar after copy, empty field", barLabels().joined(separator: ","))
        shot("empty-after-copy")
        key("h").tap()
        Thread.sleep(forTimeInterval: 1)
        note("bar after copy, h", barLabels().joined(separator: ","))
        shot("h-after-copy")
    }

    private func key(_ label: String) -> XCUIElement {
        app.keys.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    private func value() -> String { field.value as? String ?? "" }

    private func clear() {
        let text = value()
        if !text.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count + 2)) }
    }

    private var bar: XCUIElement { app.otherElements["Typing Predictions"] }

    private func barLabels() -> [String] { bar.buttons.allElementsBoundByIndex.map(\.label) }

    private func settledBar() -> [XCUIElement] {
        let start = Date()
        while Date().timeIntervalSince(start) < 3 {
            let buttons = bar.buttons.allElementsBoundByIndex
            if buttons.contains(where: { !$0.label.hasPrefix("“") }) { return buttons }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return bar.buttons.allElementsBoundByIndex
    }

    private func swipe(_ word: String) throws {
        let centers = word.map { key(String($0)).frame }.map { CGPoint(x: $0.midX, y: $0.midY) }
        let finger = XCPointerEventPath(forTouchAt: centers[0], offset: 0.05)
        var time = 0.05
        for (from, to) in zip(centers, centers.dropFirst()) {
            let steps = max(Int(hypot(to.x - from.x, to.y - from.y) / 6), 1)
            if steps == 1 && from == to { time += 0.12 }
            for step in 1...steps {
                time += 0.01
                let share = Double(step) / Double(steps)
                finger.move(
                    to: CGPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share),
                    atOffset: time)
            }
        }
        finger.liftUp(atOffset: time + 0.02)
        let record = XCSynthesizedEventRecord(name: word, interfaceOrientation: .portrait)
        record.add(finger)
        try record.synthesize()
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func note(_ step: String, _ result: String) {
        out += "\(name)|\(step)|\(result.debugDescription)\n"
        try? out.write(toFile: path + "-\(name.filter(\.isLetter)).txt", atomically: true, encoding: .utf8)
    }

    private func shot(_ step: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path + "-\(step).png"))
    }
}
