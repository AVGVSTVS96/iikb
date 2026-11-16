import UIKit
import XCTest

/// Measures where Apple's own apps lay out the text of their multi-line fields (scripts/applefields, t707): for each
/// app named in `IIKB_FIELDS_APPS`, the window, the keyboard and the field as accessibility reports them and a long
/// known text typed into the field, each step left as `<prefix>-<name>.hold` for the script to shoot from outside,
/// since `XCUIScreen` shoots the Duo's open screen black. `testAnalyze` then reads each shot back against a TextKit
/// layout of the text.
final class AppleFields: XCTestCase {
    private var prefix = ""
    private var notes = ""
    private var keys: [String: CGPoint] = [:]
    private var keyboardFrame: CGRect = .zero

    static let apps: [String: String] = [
        "messages": "com.apple.MobileSMS", "notes": "com.apple.mobilenotes", "mail": "com.apple.mobilemail",
        "reminders": "com.apple.reminders", "calendar": "com.apple.mobilecal", "contacts": "com.apple.MobileAddressBook",
    ]

    static let text =
        "the quick brown fox jumps over the lazy dog while seventeen wizards quietly mix extra jars of purple honey "
        + "for everybody who wanders into the old harbour market before sunrise and asks politely about tomorrow "
        + "weather and whether anyone remembers where the last ferry leaves from on a quiet monday morning"

    func testFields() throws {
        let environment = ProcessInfo.processInfo.environment
        prefix = try XCTUnwrap(environment["IIKB_SHOTS"])
        let typing = environment["IIKB_KEYBOARD"] == "system"
        continueAfterFailure = true
        let names = (environment["IIKB_FIELDS_APPS"] ?? "messages").split(separator: ",").map(String.init)
        let folder = (prefix as NSString).deletingLastPathComponent
        let installed = (try? String(contentsOfFile: folder + "/installed-apps.txt", encoding: .utf8)) ?? ""
        for name in names {
            let id = Self.apps[name]!
            guard installed.isEmpty || installed.contains(id) else {
                note("\(name): not installed")
                continue
            }
            let app = XCUIApplication(bundleIdentifier: id)
            app.terminate()
            app.launch()
            Thread.sleep(forTimeInterval: 4)
            look(app, "\(name)-launch")
            switch name {
            case "messages":
                learnKeys(app)
                if app.cells.firstMatch.exists {
                    app.cells.firstMatch.tap()
                    Thread.sleep(forTimeInterval: 15)
                    look(app, "messages-conversation")
                    typeByCoordinates(app, "messages-conversation", typing: typing)
                }
            case "reminders":
                _ = press(app, ["continue", "get started"])
                _ = press(app, ["not now"])
                Thread.sleep(forTimeInterval: 2)
                look(app, "reminders-start")
                if !press(app, ["new reminder"]) {
                    if app.cells.firstMatch.exists { app.cells.firstMatch.tap() }
                    Thread.sleep(forTimeInterval: 2)
                    _ = press(app, ["new reminder"])
                }
                Thread.sleep(forTimeInterval: 2)
                look(app, "reminders-new")
                capture(app, "reminders-new", typing: typing)
            case "notes":
                _ = press(app, ["continue", "get started"])
                Thread.sleep(forTimeInterval: 1)
                look(app, "notes-start")
                if !press(app, ["new note", "compose"]) {
                    if app.cells.firstMatch.exists {
                        app.cells.firstMatch.tap()
                        Thread.sleep(forTimeInterval: 2)
                        look(app, "notes-folder")
                    }
                    _ = press(app, ["new note", "compose"])
                }
                Thread.sleep(forTimeInterval: 2)
                look(app, "notes-note")
                capture(app, "notes-note", typing: typing)
            case "mail":
                _ = press(app, ["continue", "get started"])
                look(app, "mail-start")
                if press(app, ["compose", "new message"]) {
                    Thread.sleep(forTimeInterval: 2)
                    look(app, "mail-compose")
                    capture(app, "mail-compose", typing: typing)
                }
            default:
                look(app, "\(name)-open")
            }
        }
        try notes.write(toFile: prefix + "-notes.txt", atomically: true, encoding: .utf8)
    }

    /// Messages answers accessibility queries too slowly for `typeText`, so the keys are tapped where the keyboard in
    /// another app (same screen, same keyboard) put them, from the app's own origin.
    private func typeByCoordinates(_ app: XCUIApplication, _ name: String, typing: Bool) {
        let text = String(Self.text.prefix(200))
        var record: [String: Any] = ["name": name, "text": typing ? text : "", "typedByCoordinates": true]
        record["keyboard"] = frameDictionary(keyboardFrame)
        record["window"] = windowFrame
        shoot("\(name)-empty")
        if typing, !keys.isEmpty {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            for character in text {
                guard let point = keys[character == " " ? "space" : String(character)] else { continue }
                origin.withOffset(CGVector(dx: point.x, dy: point.y)).tap()
            }
            Thread.sleep(forTimeInterval: 2)
            shoot("\(name)-typed")
        }
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "\(prefix)-\(name).json"))
        }
    }

    /// Taps the conversation list's Search field, which brings up the same keyboard without the slow conversation, and
    /// keeps where each key is.
    private func learnKeys(_ app: XCUIApplication) {
        let search = app.searchFields.firstMatch
        guard search.waitForExistence(timeout: 10) else { return note("messages: no search field") }
        search.tap()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 10) else { return note("messages: no keyboard") }
        Thread.sleep(forTimeInterval: 1)
        keyboardFrame = keyboard.frame
        windowFrame = frameDictionary(app.windows.firstMatch.frame)
        for key in keyboard.keys.allElementsBoundByIndex where key.frame.width > 0 {
            keys[key.label.lowercased()] = CGPoint(x: key.frame.midX, y: key.frame.midY)
        }
        shoot("messages-search")
        app.terminate()
        app.launch()
        Thread.sleep(forTimeInterval: 4)
    }

    private var windowFrame: [String: Double] = [:]

    private func note(_ line: String) { notes += line + "\n" }

    /// Taps the first button whose label has one of `words` in it.
    private func press(_ app: XCUIApplication, _ words: [String]) -> Bool {
        let predicate = NSPredicate(
            format: words.map { _ in "label CONTAINS[c] %@" }.joined(separator: " OR "), argumentArray: words)
        let button = app.buttons.matching(predicate).firstMatch
        guard button.waitForExistence(timeout: 3) else { return false }
        button.tap()
        return true
    }

    private func look(_ app: XCUIApplication, _ name: String) {
        if ProcessInfo.processInfo.environment["IIKB_DUMP"] != nil || name.hasSuffix("-launch") {
            try? app.debugDescription.write(toFile: "\(prefix)-\(name).txt", atomically: true, encoding: .utf8)
        }
        shoot(name)
    }

    private func frameDictionary(_ frame: CGRect) -> [String: Double] {
        ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
    }

    /// The app's text view, waited for as long as a busy app takes (Messages' main thread can hold an accessibility
    /// query for 30 s at a time); one query each, since every extra one is another chance to hang.
    private func biggestField(_ app: XCUIApplication, patient: Bool = false) -> XCUIElement? {
        let view = app.textViews.firstMatch
        for _ in 0..<(patient ? 4 : 1) where view.waitForExistence(timeout: 45) { return view }
        let field = app.textFields.firstMatch
        return field.exists ? field : nil
    }

    /// Focuses the app's biggest text field, types the long text when `typing`, shoots it and writes what accessibility
    /// says to `<prefix>-<name>.json`.
    private func capture(_ app: XCUIApplication, _ name: String, typing: Bool) {
        guard let field = biggestField(app, patient: true) else {
            note("\(name): no text field")
            return
        }
        field.tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 8)
        Thread.sleep(forTimeInterval: 1)
        var record: [String: Any] = ["name": name, "text": ""]
        record["window"] = frameDictionary(app.windows.firstMatch.frame)
        if app.keyboards.firstMatch.exists {
            keyboardFrame = app.keyboards.firstMatch.frame
            record["keyboard"] = frameDictionary(keyboardFrame)
            for key in app.keyboards.firstMatch.keys.allElementsBoundByIndex where key.frame.width > 0 {
                keys[key.label.lowercased()] = CGPoint(x: key.frame.midX, y: key.frame.midY)
            }
        }
        windowFrame = frameDictionary(app.windows.firstMatch.frame)
        record["fieldEmpty"] = frameDictionary(field.frame)
        record["fieldType"] = field.elementType == .textView ? "textView" : "textField"
        record["fieldIdentifier"] = field.identifier
        record["fieldPlaceholder"] = field.placeholderValue ?? ""
        shoot("\(name)-empty")
        if typing {
            app.typeText(Self.text)
            Thread.sleep(forTimeInterval: 1)
            record["text"] = Self.text
            let after = biggestField(app) ?? field
            record["field"] = frameDictionary(after.frame)
            record["fieldValue"] = (after.value as? String) ?? ""
            shoot("\(name)-typed")
        }
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "\(prefix)-\(name).json"))
        }
    }

    private func shoot(_ name: String) {
        let path = "\(prefix)-\(name)"
        FileManager.default.createFile(atPath: "\(path).hold", contents: Data("0".utf8))
        let gone = Date().addingTimeInterval(20)
        while FileManager.default.fileExists(atPath: "\(path).hold"), Date() < gone {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Reads each `<prefix>-<name>.json` in `IIKB_FIELDS_DIR` with its typed shot: the lines of ink, then every font and
    /// wrap width whose layout of the text puts each line where it was seen.
    func testAnalyze() throws {
        let folder = try XCTUnwrap(ProcessInfo.processInfo.environment["IIKB_FIELDS_DIR"])
        let files = try FileManager.default.contentsOfDirectory(atPath: folder).filter { $0.hasSuffix(".json") }.sorted()
        var report = ""
        for file in files {
            guard let data = FileManager.default.contents(atPath: folder + "/" + file),
                let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let text = record["text"] as? String, !text.isEmpty,
                let window = record["window"] as? [String: Double],
                let field = (record["field"] ?? record["fieldEmpty"]) as? [String: Double]
            else { continue }
            let shot = folder + "/" + String(file.dropLast(5)) + "-typed.png"
            guard let image = UIImage(contentsOfFile: shot)?.cgImage else {
                report += "\(file): no shot\n"
                continue
            }
            let scale = Double(image.width) / window["width"]!
            let frame = CGRect(x: field["x"]!, y: field["y"]!, width: field["width"]!, height: field["height"]!)
            let lines = FieldInk.lines(in: image, frame: frame, scale: scale)
            report += "== \(file) window \(window) field \(field) image \(image.width)x\(image.height) scale \(scale)\n"
            for line in lines {
                report += String(
                    format: "line top %.2f bottom %.2f minX %.2f maxX %.2f\n", line.top, line.bottom, line.minX, line.maxX)
            }
            var fonts: [(String, UIFont)] = [("body", UIFont.preferredFont(forTextStyle: .body))]
            for size in stride(from: 13.0, through: 24.0, by: 0.5) {
                fonts.append(("system \(size)", UIFont.systemFont(ofSize: size)))
            }
            let widest = (lines.map { $0.maxX - $0.minX }.max() ?? 0) - 1
            let fits = FieldInk.fits(
                text, seen: lines, fonts: fonts, widths: stride(from: max(60, widest), through: window["width"]!, by: 0.5))
            for name in Set(fits.map(\.font)).sorted() {
                let mine = fits.filter { $0.font == name }
                report += String(
                    format: "fit %@ width %.1f...%.1f origin %.2f spread %.2f\n", name, mine.map(\.width).min()!,
                    mine.map(\.width).max()!, mine.map(\.origin).reduce(0, +) / Double(mine.count),
                    mine.map(\.spread).min()!)
            }
            if fits.isEmpty { report += "no fit\n" }
        }
        try report.write(toFile: folder + "/analysis.txt", atomically: true, encoding: .utf8)
    }
}
