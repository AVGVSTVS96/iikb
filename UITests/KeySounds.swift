import XCTest

/// Scratch: presses each kind of key on the keyboard in use, logging SNDMARK lines for scratch/keysounds.sh.
final class KeySounds: XCTestCase {
    private var app: XCUIApplication!

    private func mark(_ what: String) {
        NSLog("SNDMARK %@ t=%.3f", what, Date().timeIntervalSince1970)
        let line = String(format: "%.6f AppUITests-Runner SNDMARK %@\n", Date().timeIntervalSince1970, what)
        if let handle = FileHandle(forWritingAtPath: "/tmp/sndtrace.log") {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        }
    }

    private func keys() -> [String: CGRect] {
        var keys: [String: CGRect] = [:]
        guard let root = try? app.snapshot() else { return keys }
        func walk(_ node: XCUIElementSnapshot) {
            let frame = node.frame
            if frame.width > 0, node.elementType == .key || node.elementType == .button || node.elementType == .cell {
                func put(_ name: String) { if keys[name].map({ $0.midY < frame.midY }) ?? true { keys[name] = frame } }
                if !node.identifier.isEmpty { put(node.identifier) }
                if !node.label.isEmpty { put(node.label) }
                if node.elementType == .button, !node.label.isEmpty { put("button:" + node.label) }
            }
            node.children.forEach(walk)
        }
        walk(root)
        return keys
    }

    private func press(_ point: CGPoint, hold: Double = 0.06, moveBy: CGVector? = nil) throws {
        let record = XCSynthesizedEventRecord(name: "press", interfaceOrientation: .portrait)
        let path = XCPointerEventPath(forTouchAt: point, offset: 0)
        if let moveBy {
            path.move(to: point, atOffset: hold * 0.8)
            path.move(to: CGPoint(x: point.x + moveBy.dx, y: point.y + moveBy.dy), atOffset: hold)
            path.liftUp(atOffset: hold + 0.3)
        } else {
            path.liftUp(atOffset: hold)
        }
        record.add(path)
        try record.synthesize()
    }

    private func step(_ name: String, _ label: [String], hold: Double = 0.06, moveBy: CGVector? = nil) throws {
        let all = keys()
        guard let key = label.lazy.compactMap({ all[$0] }).first else {
            mark("missing \(name) wanted=\(label) have=\(all.keys.sorted())")
            return
        }
        let point = CGPoint(x: key.midX, y: key.midY)
        mark("begin \(name) hold=\(hold)")
        try press(point, hold: hold, moveBy: moveBy.map { CGVector(dx: $0.dx * key.width, dy: $0.dy * key.height) })
        mark("lifted \(name)")
        Thread.sleep(forTimeInterval: 0.8)
        mark("end \(name) text=\(value.suffix(24))")
    }

    private var value: String { app.textViews.firstMatch.value as? String ?? "" }

    func testKeySounds() throws {
        app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbOrientation", "portrait"]
        let iikb = ProcessInfo.processInfo.environment["SNDTRACE_IIKB"] == "1"
        if let dylib = ProcessInfo.processInfo.environment["SNDTRACE_DYLIB"], !dylib.isEmpty {
            app.launchEnvironment["DYLD_INSERT_LIBRARIES"] = dylib
        }
        if iikb { app.launchWithIikb() } else { app.launch() }
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10))
        let letter = { (c: String) in iikb ? ["iikb.\(c)", c] : [c, c.uppercased()] }
        if !iikb { XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 15)) }
        Thread.sleep(forTimeInterval: 2)
        mark("labels \(keys().keys.sorted())")
        for c in ["h", "e", "l", "l", "o", "w", "o", "r", "l", "d"] { try step("letter-\(c)", letter(c)) }
        try step("space", iikb ? ["iikb.space", "space"] : ["space"])
        try step("letter-hold-q", letter("q"), hold: 1.2)
        try step("delete-tap", iikb ? ["iikb.delete", "delete"] : ["delete", "Delete"])
        try step("return", iikb ? ["iikb.return", "return", "Return"] : ["return", "Return", "new line"])
        try step("shift", iikb ? ["iikb.shift", "shift"] : ["shift", "Shift"])
        try step("letter-after-shift-t", letter("t"))
        try step("shift-hold", iikb ? ["iikb.shift", "shift"] : ["shift", "Shift"], hold: 1.0)
        try step("more-123", iikb ? ["iikb.more", "more", "123"] : ["more", "numbers", "Numbers", "123", "more, numbers"])
        mark("labels-123 \(keys().keys.sorted())")
        try step("digit-1", iikb ? ["iikb.1", "1"] : ["1"])
        try step("symbol-dash", iikb ? ["iikb.-", "-"] : ["-", "hyphen", "Hyphen"])
        try step("symbols-#+=", iikb ? ["iikb.symbols", "#+="] : ["more, symbols", "symbols", "#+=", "Symbols"])
        mark("labels-sym \(keys().keys.sorted())")
        try step("symbol-bracket", iikb ? ["iikb.[", "["] : ["[", "left bracket", "Left bracket"])
        try step("abc", iikb ? ["iikb.more", "more", "ABC"] : ["more, letters", "letters", "Letters", "ABC", "more"])
        mark("labels-abc \(keys().keys.sorted())")
        for c in ["t", "h", "e", " ", "q", "u", "i", "c", "k", " ", "b", "r", "o", "w", "n", " ", "f", "o", "x", " ", "j", "u", "m", "p", "s", " "] {
            if c == " " { try step("space", iikb ? ["iikb.space", "space"] : ["space"]) } else { try step("letter-\(c)", letter(c)) }
        }
        try step("delete-hold-short", iikb ? ["iikb.delete", "delete"] : ["delete", "Delete"], hold: 1.5)
        try step("delete-hold-long", iikb ? ["iikb.delete", "delete"] : ["delete", "Delete"], hold: 4.5)
        for c in ["h", "e", "l", "o"] { try step("letter-\(c)", letter(c)) }
        let bar = app.otherElements["Typing Predictions"]
        if !iikb, bar.exists {
            var buttons: [(label: String, frame: CGRect)] = []
            if let root = try? bar.snapshot() {
                func walk(_ node: XCUIElementSnapshot) {
                    if node.elementType == .button, node.frame.width > 0 { buttons.append((node.label, node.frame)) }
                    node.children.forEach(walk)
                }
                walk(root)
            }
            mark("bar \(buttons.map(\.label))")
            if let pick = buttons.dropFirst().first ?? buttons.first {
                mark("begin suggestion label=\(pick.label)")
                try press(CGPoint(x: pick.frame.midX, y: pick.frame.midY))
                mark("lifted suggestion")
                Thread.sleep(forTimeInterval: 0.8)
                mark("end suggestion text=\(value.suffix(24))")
            }
        }
        try step("accent-e", letter("e"), hold: 1.0, moveBy: CGVector(dx: 1, dy: -0.2))
        try step("globe", iikb ? ["iikb.globe", "Next keyboard"] : ["Next keyboard", "next keyboard", "globe", "button:Next keyboard"])
        mark("labels-after-globe \(keys().keys.sorted())")
        try step("globe-back", ["Next keyboard", "next keyboard", "globe", "button:Next keyboard"])
        try step("emoji", iikb ? ["iikb.emoji", "Emoji"] : ["Emoji", "emoji", "button:Emoji"])
        mark("labels-emoji \(keys().keys.sorted())")
        var cells: [(label: String, frame: CGRect)] = []
        if let root = try? app.snapshot() {
            func walk(_ node: XCUIElementSnapshot) {
                if node.elementType == .cell, node.frame.width > 0 { cells.append((node.label, node.frame)) }
                node.children.forEach(walk)
            }
            walk(root)
        }
        mark("emoji-cells \(cells.prefix(5).map(\.label))")
        if let cell = cells.first {
            mark("begin emoji-cell label=\(cell.label)")
            try press(CGPoint(x: cell.frame.midX, y: cell.frame.midY))
            mark("lifted emoji-cell")
            Thread.sleep(forTimeInterval: 0.8)
            mark("end emoji-cell text=\(value.suffix(24))")
        }
        try step("emoji-delete", ["delete", "Delete", "button:delete", "button:Delete"])
        try step("emoji-abc", ["ABC", "button:ABC", "Next keyboard", "letters"])
        mark("done")
    }
}
