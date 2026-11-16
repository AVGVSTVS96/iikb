import XCTest

/// Photos in Chats through the real keyboard, every way you'd send them: several with a caption and one taken off, ten
/// at most, pasted, with no access to the library until Allow Photos asks, a send that fails and goes again, and a whole
/// library scrolled through (scripts/phototest, scripts/chats.ts standing in for the extension).
final class ChatPhotoTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment.filter { !$0.value.isEmpty } }
    private var shots = ""
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        guard let shots = environment["IIKB_SHOTS"], environment["IIKB_EXTENSION"] != nil else {
            throw XCTSkip("Run through scripts/phototest")
        }
        self.shots = shots
        continueAfterFailure = false
    }

    /// Each failure leaves the screen as it was, and what XCUITest saw on it in the log.
    override func record(_ issue: XCTIssue) {
        try? shot("failed-\(name.split(separator: " ").last?.dropLast() ?? "")")
        print(app.debugDescription)
        super.record(issue)
    }

    func testSeveralPhotosGoWithACaptionAfterOneIsTakenOff() throws {
        try openChat()
        let grid = try openPhotos()
        checkChatOverKeys("with your photos up")
        try shot("grid")
        for index in 0..<3 { cell(index).tap() }
        XCTAssertTrue(element("iikb.chat.photo.2").waitForExistence(timeout: 15), "three photos sit in the box")
        XCTAssertTrue(cell(2).isSelected, "a picked photo is marked in the grid")
        checkChatOverKeys("with three photos picked")
        try shot("three")
        element("iikb.chat.photo.1.remove").tap()
        XCTAssertTrue(wait { !self.element("iikb.chat.photo.2").exists }, "the ✕ takes a photo off the box")
        XCTAssertFalse(cell(1).isSelected, "and unmarks it in the grid")
        try shot("removed")
        tapBox()
        XCTAssertTrue(key("space").waitForExistence(timeout: 5), "tapping the box over its photos brings the keys up")
        XCTAssertFalse(grid.isHittable, "and puts the photos away")
        checkChatOverKeys("typing under two photos")
        type("the view")
        try shot("caption")
        element("iikb.chat.send").tap()
        XCTAssertTrue(label("Got it: 2 photos and “the view”").waitForExistence(timeout: 20), "both go with the words")
        XCTAssertFalse(element("iikb.chat.photo.0").exists, "the box is empty once they're sent")
        Thread.sleep(forTimeInterval: 2)
        try shot("sent")
    }

    func testTenIsTheMost() throws {
        try openChat()
        let grid = try openPhotos()
        for index in 0..<11 {
            let photo = cell(index)
            for _ in 0..<6 where !(photo.exists && photo.isHittable) { scrollARow(grid) }
            photo.tap()
        }
        XCTAssertTrue(element("iikb.chat.photo.9").waitForExistence(timeout: 30), "ten photos sit in the box")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(element("iikb.chat.photo.10").exists, "an eleventh isn't attached")
        try shot("ten")
        element("iikb.chat.send").tap()
        XCTAssertTrue(label("Got it: 10 photos").waitForExistence(timeout: 30), "all ten go")
        Thread.sleep(forTimeInterval: 2)
        try shot("ten-sent")
    }

    func testAPastedPhotoIsAttached() throws {
        try openChat()
        UIPasteboard.general.image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).image {
            UIColor.systemTeal.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
            UIColor.systemOrange.setFill()
            $0.fill(CGRect(x: 150, y: 100, width: 300, height: 200))
        }
        let field = element("iikb.chat.field")
        field.tap()
        XCTAssertTrue(key("space").waitForExistence(timeout: 5), "tapping the box brings the keys up")
        checkChatOverKeys("with the keys up")
        field.press(forDuration: 1)
        let paste = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Paste'")).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "the box's menu offers Paste with a photo copied")
        paste.tap()
        XCTAssertTrue(element("iikb.chat.photo.0").waitForExistence(timeout: 15), "the pasted photo sits in the box")
        checkChatOverKeys("with a photo pasted")
        try shot("pasted")
        element("iikb.chat.send").tap()
        XCTAssertTrue(label("Got it: 1 photo").waitForExistence(timeout: 20), "and goes")
    }

    func testASendThatFailsIsKeptAndGoesAgain() throws {
        try openChat()
        try stand("fail")
        _ = try openPhotos()
        cell(0).tap()
        XCTAssertTrue(element("iikb.chat.photo.0").waitForExistence(timeout: 15), "the photo sits in the box")
        element("iikb.chat.send").tap()
        XCTAssertTrue(label("What you sent is kept").waitForExistence(timeout: 20), "a failed send says it's kept")
        XCTAssertTrue(label("Not sent").waitForExistence(timeout: 5), "and the message is marked as not sent")
        Thread.sleep(forTimeInterval: 1)
        try shot("failed")
        try stand("ok")
        element("iikb.chat.field").tap()
        type("and this")
        element("iikb.chat.send").tap()
        XCTAssertTrue(label("Got it: 1 photo").waitForExistence(timeout: 30), "the kept photo goes with the next send")
        XCTAssertTrue(label("Got it: “and this”").waitForExistence(timeout: 20), "and so do the words after it")
        XCTAssertFalse(label("Not sent").exists, "the mark goes once it's sent")
        Thread.sleep(forTimeInterval: 2)
        try shot("resent")
    }

    func testTheWholeLibraryScrollsAndAPhotoFromItsEndGoes() throws {
        let count = Int(environment["IIKB_LIBRARY"] ?? "") ?? 0
        guard count > 100 else { throw XCTSkip("Run with LIBRARY=<more than 100>") }
        try openChat()
        let grid = try openPhotos()
        for _ in 0..<(count / 12) { grid.swipeUp(velocity: .fast) }
        Thread.sleep(forTimeInterval: 2)
        try shot("library-end")
        let last = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'iikb.chat.photos.'"))
            .allElementsBoundByIndex
            .filter(\.isHittable).last
        XCTAssertNotNil(last, "the grid's end shows photos")
        last?.tap()
        XCTAssertTrue(element("iikb.chat.photo.0").waitForExistence(timeout: 15), "a photo from the end attaches")
        try shot("library-attached")
        element("iikb.chat.send").tap()
        XCTAssertTrue(label("Got it: 1 photo").waitForExistence(timeout: 30), "and goes")
    }

    /// Run with the library's access reset, as before you've given it. The chat is in another app's field, as it is in
    /// Telegram: a page's box in Safari. Allow Photos opens iikb, iOS asks there, and iikb goes back to Safari, where the
    /// chat shows the photos.
    func testAllowPhotosAsksAndThePhotosShowBackInTheApp() throws {
        guard environment["IIKB_NO_ACCESS"] != nil else { throw XCTSkip("Run with the library's access reset") }
        try openChat(inSafari: true)
        element("iikb.chat.attach").tap()
        let notice = label("Photos need their own permission")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "without access the grid says so")
        try shot("no-access")
        // XCUITest takes iOS's question for an interruption as the test taps its answer, and its own handler would
        // answer Don't Allow first, as it does on the iPad.
        let monitor = addUIInterruptionMonitor(withDescription: "iOS asks for the photos") { question in
            let allow = question.buttons["Allow Full Access"].firstMatch
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        defer { removeUIInterruptionMonitor(monitor) }
        notice.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow Full Access"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 30), "Allow Photos opens iikb, and iOS asks")
        try shot("asked")
        allow.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "iikb goes back to the app you were in")
        if !cell(0).waitForExistence(timeout: 15) {
            // The simulator now and then hands XCUITest a stale picture of a keyboard that came back with its app, the
            // grid's photos on screen but not in it; the keys going down and up again show it as it is.
            try shot("stale")
            let done = app.buttons["Done"].firstMatch
            if done.exists { done.tap() } else { app.keyboards.buttons["Hide keyboard"].firstMatch.tap() }
            let box = app.webViews.textViews.firstMatch
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: box.frame.midX, dy: box.frame.midY))
                .tap()
        }
        XCTAssertTrue(cell(0).waitForExistence(timeout: 15), "once allowed, the photos show in the chat")
        try shot("allowed")
        cell(0).tap()
        XCTAssertTrue(element("iikb.chat.photo.0").waitForExistence(timeout: 15), "and one picked sits in the box")
        element("iikb.chat.send").tap()
        XCTAssertTrue(label("Got it: 1 photo").waitForExistence(timeout: 30), "and goes")
    }

    /// Opens the stand-in's first chat from the menu, in iikb's own field or a page's box in Safari.
    private func openChat(inSafari: Bool = false) throws {
        var link = URLComponents(string: "iikb://extension")!
        link.queryItems = [
            URLQueryItem(name: "name", value: "hex"), URLQueryItem(name: "url", value: environment["IIKB_EXTENSION"]),
        ]
        let linked = XCUIApplication()
        linked.open(link.url!)
        let add = linked.alerts.buttons["Add"]
        if add.waitForExistence(timeout: 10) { add.tap() }
        linked.terminate()
        let landscape = environment["IIKB_ORIENTATION"] == "landscape"
        if inSafari {
            app = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
            app.launch()
            app.open(URL(string: environment["IIKB_EXTENSION"]! + "/field")!)
            let box = app.webViews.textViews.firstMatch
            XCTAssertTrue(box.waitForExistence(timeout: 30), "Safari shows the page's box")
            guard app.frame.size == XCUIScreen.main.screenshot().image.size else {
                throw XCTSkip(
                    "Safari opened on the open Duo's other display, where the simulator brings up no keyboard for it")
            }
            // A tap on the box's place, again until a keyboard comes up: while the page's process isn't answering
            // XCUITest yet (kAXErrorServerNotFound), tapping the element itself fails and a tap can land before the
            // box is ready. A Safari that keeps Apple's keyboard (`showsIikb`) starts over once.
            let place = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: box.frame.midX, dy: box.frame.midY))
            var shown = false
            for attempt in 0..<2 where !shown {
                if attempt > 0 {
                    app.launch()
                    app.open(URL(string: environment["IIKB_EXTENSION"]! + "/field")!)
                    _ = box.waitForExistence(timeout: 30)
                }
                for _ in 0..<3 where !app.keyboards.firstMatch.exists {
                    place.tap()
                    _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
                }
                shown = app.showsIikb(relaunching: false)
            }
            XCTAssertTrue(shown, "iikb is not the active keyboard")
        } else {
            app = XCUIApplication()
            app.launchArguments = [
                "-iikbFocus", "YES", "-iikbOrientation",
                landscape ? "landscape" : environment["IIKB_LAUNCH"] ?? "portrait",
            ]
            app.launchWithIikb()
        }
        if landscape { XCUIDevice.shared.orientation = .landscapeLeft }
        XCTAssertTrue(element("iikb.more").waitForExistence(timeout: 20), "iikb's menu button shows")
        element("iikb.more").tap()
        let card = element("iikb.chats.shelf.0")
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the menu has a Chats shelf with the chats as cards")
        card.tap()
        XCTAssertTrue(element("iikb.chat.attach").waitForExistence(timeout: 10), "the box has a paperclip beside it")
    }

    /// A tap on the box's middle, where your thumb goes, over its photos when it has some.
    private func tapBox() {
        element("iikb.chat.field").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The chat over the keys or your photos: More and the tabs over the box, and the box whole, its photos inside it
    /// over a line's room for its words, as the box has with nothing attached.
    private func checkChatOverKeys(_ moment: String, file: StaticString = #filePath, line: UInt = #line) {
        let box = element("iikb.chat.field").frame
        XCTAssertTrue(
            element("iikb.chat.more").isHittable, "\(moment): More sits atop the chat", file: file, line: line)
        XCTAssertLessThanOrEqual(
            element("iikb.chats").frame.maxY, box.minY, "\(moment): the tabs sit over the box", file: file, line: line)
        let photos = (0..<10).map { element("iikb.chat.photo.\($0)") }.prefix { $0.exists }.map(\.frame)
        for photo in photos {
            XCTAssertTrue(box.contains(photo), "\(moment): the box holds its photos", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(
            box.maxY - (photos.map(\.maxY).max() ?? box.minY), 39.5,
            "\(moment): the box keeps a line for its words under its photos", file: file, line: line)
    }

    private func openPhotos() throws -> XCUIElement {
        element("iikb.chat.attach").tap()
        XCTAssertTrue(cell(0).waitForExistence(timeout: 10), "the paperclip brings your newest photos up")
        return element("iikb.chat.photos")
    }

    /// Turns the stand-in's sends off ("fail") or on ("ok").
    private func stand(_ turn: String) throws {
        let url = URL(string: environment["IIKB_EXTENSION"]! + "/stand-in/" + turn)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let done = expectation(description: turn)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
    }

    private func cell(_ index: Int) -> XCUIElement { element("iikb.chat.photos.\(index)") }

    /// Drags the grid up by about a row.
    private func scrollARow(_ grid: XCUIElement) {
        let middle = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -110)))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func label(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func key(_ name: String) -> XCUIElement {
        let iikb = app.keys.matching(identifier: "iikb.\(name)").firstMatch
        return iikb.exists ? iikb : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }

    private func type(_ text: String) {
        for character in text { key(character == " " ? "space" : String(character)).tap() }
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    /// The screen in use, which scripts/phototest shoots from the Mac once the request's file is there, and then
    /// takes the file away.
    private func shot(_ name: String) throws {
        let want = URL(fileURLWithPath: "\(shots)-\(name).want")
        try Data().write(to: want)
        _ = wait { !FileManager.default.fileExists(atPath: want.path) }
    }
}
