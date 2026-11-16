import XCTest

final class ProxyProbe: XCTestCase {
    private func words(_ tag: String, _ count: Int) -> String {
        (0..<count).map { "\(tag)\($0)" }.joined(separator: " ")
    }

    private func run(_ name: String, text: String) {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbText", text]
        app.launchWithIikb()
        print("PROBE \(name) total=\(text.count) nl=\(text.filter { $0 == "\n" }.count)")
        let label = app.descendants(matching: .any).matching(identifier: "iikb.probe").firstMatch
        func read() -> String { label.exists ? label.label : "missing" }
        app.buttons["iikb.probe.read"].tap()
        print("PROBE \(name) start \(read())")
        for (button, times) in [("iikb.probe.back", 8), ("iikb.probe.fwd", 10)] {
            for i in 0..<times {
                let before = read()
                app.buttons[button].tap()
                print("PROBE \(name) \(button) \(i) sync \(read())")
                var now = read()
                for _ in 0..<15 where now == before || now.hasPrefix("sync") {
                    Thread.sleep(forTimeInterval: 0.2)
                    now = read()
                }
                Thread.sleep(forTimeInterval: 0.5)
                app.buttons["iikb.probe.read"].tap()
                print("PROBE \(name) \(button) \(i) settled \(read())")
            }
        }
        let value = app.textViews.firstMatch.value as? String ?? ""
        print("PROBE \(name) field=\(value.count)")
    }

    func testParagraphs() {
        run("paras", text: words("a", 200) + "\n" + words("b", 60) + "\n" + words("c", 150))
    }

    func testOneLongLine() {
        run("line", text: words("w", 700))
    }

    func testShort() {
        run("short", text: "Hello there, how are you doing today?\nSecond line here.")
    }
}
