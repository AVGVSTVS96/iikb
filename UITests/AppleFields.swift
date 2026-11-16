import XCTest

/// Measures where Apple's own apps lay out the text of their multi-line fields (scripts/applefields, t707): for each
/// app named in `IIKB_FIELDS_APPS`, the window, the keyboard and the field as accessibility reports them, and each step
/// left as `<prefix>-<name>.hold` for the script to shoot from outside, since `XCUIScreen` shoots the Duo's open screen
/// black.
final class AppleFields: XCTestCase {
    private var prefix = ""

    static let apps: [String: String] = [
        "messages": "com.apple.MobileSMS", "notes": "com.apple.mobilenotes", "mail": "com.apple.mobilemail",
        "reminders": "com.apple.reminders", "calendar": "com.apple.mobilecal", "contacts": "com.apple.MobileAddressBook",
    ]

    func testExplore() throws {
        let environment = ProcessInfo.processInfo.environment
        prefix = try XCTUnwrap(environment["IIKB_SHOTS"])
        continueAfterFailure = true
        let names = (environment["IIKB_FIELDS_APPS"] ?? "messages,notes,mail").split(separator: ",").map(String.init)
        for name in names {
            let app = XCUIApplication(bundleIdentifier: Self.apps[name]!)
            if let installed = try? String(contentsOfFile: ((prefix as NSString).deletingLastPathComponent + "/installed-apps.txt"), encoding: .utf8),
                !installed.contains(Self.apps[name]!) { continue }
            app.terminate()
            app.launch()
            Thread.sleep(forTimeInterval: 4)
            dump(app, "\(name)-launch")
            shoot("\(name)-launch")
            if name == "messages", app.cells.firstMatch.exists {
                app.cells.firstMatch.tap()
                Thread.sleep(forTimeInterval: 2)
                dump(app, "\(name)-conversation")
                shoot("\(name)-conversation")
            }
            let field = app.textViews.firstMatch
            if field.waitForExistence(timeout: 3) {
                field.tap()
            } else if app.textFields.firstMatch.exists {
                app.textFields.firstMatch.tap()
            }
            Thread.sleep(forTimeInterval: 3)
            dump(app, "\(name)-tap")
            shoot("\(name)-tap")
        }
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        try? app.debugDescription.write(toFile: "\(prefix)-\(name).txt", atomically: true, encoding: .utf8)
    }

    private func shoot(_ name: String) {
        let path = "\(prefix)-\(name)"
        FileManager.default.createFile(atPath: "\(path).hold", contents: Data("0".utf8))
        let gone = Date().addingTimeInterval(20)
        while FileManager.default.fileExists(atPath: "\(path).hold"), Date() < gone {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}
