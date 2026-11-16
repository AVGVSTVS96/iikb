import Testing

@testable import KeyboardCore

/// The typing details Raycast's keyboard has: more layouts, number hints, a currency of your own, web endings on the
/// period, deleting words by sliding, and emoji on the emoji key's hold.
struct TypingDetailsTests {
    private let phone = Size(width: 402, height: 874)

    private func layout(
        _ layer: KeyboardLayer = .letters, kind: InputKind = .text, device: DeviceClass = .phone,
        region: Region = Region(), _ change: (inout KeyboardSettings) -> Void = { _ in }
    ) -> KeyboardLayout {
        var settings = KeyboardSettings()
        change(&settings)
        return Layouts.layout(
            for: LayoutContext(
                device: device, layer: layer, kind: kind, screen: phone, settings: settings, region: region))
    }

    private func keys(_ layout: KeyboardLayout) -> [Key] {
        layout.rows.flatMap { row in row.compactMap { if case .key(let key) = $0 { key } else { nil } } }
    }

    private func key(_ value: String, in layout: KeyboardLayout) -> Key? {
        keys(layout).first { $0.action == .character(value) }
    }

    private func letters(_ layout: KeyboardLayout) -> [String] {
        layout.rows.dropLast().map { row in
            row.compactMap { item -> String? in
                guard case .key(let key) = item, case .character(let value) = key.action else { return nil }
                return value
            }.joined()
        }
    }

    @Test func englishOffersDvorakColemakAndWorkman() {
        let rows = { (id: String) in letters(layout { $0.layout = id }) }
        #expect(rows("colemak") == ["qwfpgjluy", "arstdhneio", "zxcvbkm"])
        #expect(rows("colemakdh") == ["qwfpbjluy", "arstgmneio", "zxcdvkh"])
        #expect(rows("workman") == ["qdrwbjfup", "ashtgyneoi", "zxmcvkl"])
        for id in ["dvorak", "colemak", "colemakdh", "workman"] {
            var settings = KeyboardSettings()
            settings.layout = id
            let context = LayoutContext(device: .phone, layer: .letters, screen: phone, settings: settings)
            #expect(context.signature == "phone-portrait-letters-\(id)")
            #expect(LayoutContext(signature: context.signature)?.letters.id == id)
        }
    }

    /// Apple's Dvorak on an iPhone: delete ends the top row and shift starts a bottom row of nine letters.
    @Test func dvorakSetsDeleteOnTheTopRowAsApplesDoes() {
        let dvorak = layout { $0.layout = "dvorak" }
        #expect(letters(dvorak) == ["pyfgcrl", "aoeuidhtns", "qjkxbmwvz"])
        let actions = dvorak.rows.prefix(3).map { row in
            row.compactMap { if case .key(let key) = $0 { key.action } else { nil } }
        }
        #expect(actions[0].last == .delete && actions[2].first == .shift && !actions[2].contains(.delete))
        #expect(abs(dvorak.extraColumns - 0.3) < 0.001)
    }

    /// Dvorak's top row starts two keys in, so the bar is set out by its shift row, which spans the keys as QWERTY's
    /// top row does.
    @Test func dvoraksBarFollowsItsWidestRow() throws {
        var settings = KeyboardSettings()
        settings.layout = "dvorak"
        let context = LayoutContext(device: .phone, layer: .letters, screen: phone, settings: settings)
        let grid = KeyboardGeometry(context, screen: phone, style: .ios27).grid
        let row = grid.barRow
        #expect(row.first?.key.action == .shift)
        let top = try #require(grid.rows.first)
        #expect(
            abs(
                (row.last?.frame.x ?? 0) + (row.last?.frame.width ?? 0)
                    - (top.last.map { $0.frame.x + $0.frame.width } ?? 0)) < 0.5)
    }

    /// The 13-inch iPad's full keys carry each layout's desk punctuation where a desk keyboard has it.
    @Test func theLargePadSetsDvorakAsADesk() {
        let large = layout(device: .largePad) { $0.layout = "dvorak" }
        #expect(key("p", in: large) != nil && key(";", in: large) != nil)
        #expect(key("-", in: large) != nil)
    }

    @Test func numberHintsPutADigitOnEachTopLetter() throws {
        let hinted = layout { $0.numberHints = true }
        let q = try #require(key("q", in: hinted))
        let p = try #require(key("p", in: hinted))
        let e = try #require(key("e", in: hinted))
        #expect(q.secondary == "1" && q.holdPick == "1" && q.alternates == ["1", "q"])
        #expect(p.secondary == "0" && p.alternates.last == "0")
        #expect(e.secondary == "3" && e.alternates.first == "3" && e.alternates.contains("é"))
        #expect(key("a", in: hinted)?.secondary == nil)
        let face = KeyFace(
            q, trailing: false,
            context: KeyFaceContext(
                device: .phone, layer: .letters, kind: .text, shift: .off, returnKind: .default, returnEnabled: true))
        #expect(face.hint == "1" && face.secondary == nil)
    }

    @Test func theNumberRowTakesTheHintsPlace() {
        let hints = { (settings: inout KeyboardSettings) in settings.numberHints = true }
        let withRow = layout {
            hints(&$0)
            $0.numberRow = true
        }
        #expect(key("q", in: withRow)?.secondary == nil)
        #expect(key("q", in: layout(device: .pad, hints))?.holdPick == nil)
        #expect(key("1", in: layout(.numbers, hints))?.secondary == nil)
    }

    @Test func theCurrencyKeyShowsTheRegionsSign() throws {
        let numbers = layout(.numbers, region: Region(code: "GB", currency: "GBP"))
        let pound = try #require(key("£", in: numbers))
        #expect(pound.alternates.contains("$"))
        #expect(key("$", in: numbers) == nil)
        let symbols = layout(.symbols, region: Region(code: "DE", currency: "EUR"))
        #expect(key("€", in: symbols) == nil && key("$", in: symbols) != nil)
        #expect(key("$", in: layout(.numbers)) != nil)
        let hryvnia = try #require(key("₴", in: layout(.numbers) { $0.currency = .hryvnia }))
        #expect(hryvnia.alternates.contains("$"))
    }

    @Test func endingsFollowTheRegionAndLanguage() {
        #expect(Region(code: "GB").endings(typing: .english) == [".com", ".co.uk", ".uk", ".org", ".net", ".edu"])
        #expect(Region(code: "FR").endings(typing: .french) == [".com", ".fr", ".org", ".net", ".edu", ".gov"])
        #expect(Region(code: "CA").endings(typing: .english).prefix(2) == [".com", ".ca"])
        #expect(Region().endings(typing: .english).prefix(2) == [".com", ".us"])
    }

    @Test func theAddressPeriodOffersEndingsAndOpensOnDotCom() throws {
        let email = try #require(key(".", in: layout(kind: .email, region: Region(code: "GB"))))
        #expect(email.holdPick == ".com" && Set(email.alternates).isSuperset(of: [".com", ".co.uk"]))
        #expect(key(".", in: layout(kind: .text))?.holdPick == nil)
        let url = layout(kind: .url)
        #expect(key(".com", in: url)?.holdPick == ".com" && key(".", in: url)?.holdPick == nil)
    }

    @Test func slidingFromDeleteTakesWordsAndGivesThemBack() {
        var engine = TypingEngine()
        let document = TestDocument("one two three")
        engine.documentChanged(document)
        let delete = Key(.delete)
        _ = engine.handle(.down(delete, tapCount: 1), in: document)
        #expect(document.text == "one two thre")
        _ = engine.handle(.deleteSlide(words: 1), in: document)
        #expect(document.text == "one two ")
        _ = engine.handle(.deleteSlide(words: 2), in: document)
        #expect(document.text == "one ")
        _ = engine.handle(.deleteSlide(words: 1), in: document)
        #expect(document.text == "one two ")
        _ = engine.handle(.deleteSlide(words: 0), in: document)
        #expect(document.text == "one two three")
        _ = engine.handle(.up(delete), in: document)
        let after = engine.handle(.deleteSlide(words: 1), in: document)
        #expect(!after)
        #expect(document.text == "one two three")
    }

    /// A host that shows only the last 30 characters before the caret, reporting after every edit, as a long field does:
    /// the slide edits what it wrote, not the window the host slides along.
    @Test func slidingFromDeleteHoldsUpWhenTheHostShowsAWindow() {
        let text = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa"
        let document = WindowDocument(text)
        var engine = TypingEngine()
        engine.documentChanged(document)
        let delete = Key(.delete)
        _ = engine.handle(.down(delete, tapCount: 1), in: document)
        engine.documentChanged(document)
        for words in [1, 2, 3, 2, 1, 0] {
            _ = engine.handle(.deleteSlide(words: words), in: document)
            engine.documentChanged(document)
        }
        #expect(document.text == text)
        _ = engine.handle(.deleteSlide(words: 2), in: document)
        #expect(document.text == text.replacingOccurrences(of: " oscar papa", with: " "))
    }

    /// After delete has repeated, a slide takes words from what's left, never giving back what the repeat took.
    @Test func aSlideAfterTheRepeatCountsFromWhereItBegan() {
        var engine = TypingEngine()
        let document = TestDocument("one two three four")
        engine.documentChanged(document)
        let delete = Key(.delete)
        _ = engine.handle(.down(delete, tapCount: 1), in: document)
        engine.deleteWord(in: document)
        #expect(document.text == "one two three ")
        _ = engine.handle(.deleteSlide(words: 1), in: document)
        #expect(document.text == "one two ")
        _ = engine.handle(.deleteSlide(words: 0), in: document)
        #expect(document.text == "one two three ")
    }

    /// A slide's first word can be the one character delete already took: that step changes nothing, yet the slide
    /// still answers for it, so the keyboard stops delete's repeat instead of letting it eat the field.
    @Test func aSlideStepThatChangesNothingStillHoldsTheRepeat() {
        var engine = TypingEngine()
        let document = TestDocument("Coffee at 2")
        engine.documentChanged(document)
        let delete = Key(.delete)
        _ = engine.handle(.down(delete, tapCount: 1), in: document)
        let first = engine.handle(.deleteSlide(words: 1), in: document)
        #expect(first && document.text == "Coffee at ")
        _ = engine.handle(.deleteSlide(words: 2), in: document)
        #expect(document.text == "Coffee ")
    }

    /// A number hint's digit is no letter's: a 1 typed on 123 never teaches q's aim.
    @Test func aHintsDigitIsNoLettersKey() {
        var settings = KeyboardSettings()
        settings.numberHints = true
        let context = LayoutContext(device: .phone, layer: .letters, screen: phone, settings: settings)
        let grid = KeyboardGeometry(context, screen: phone, style: .ios27).grid
        #expect(grid.key(holding: "1") == nil && grid.key(holding: "é") == "e")
    }

    @Test func theCurrencyStaysOnAnIPadsKeys() {
        let pad = layout(.letters, device: .largePad, region: Region(code: "GB", currency: "GBP"))
        #expect(keys(pad) == keys(layout(.letters, device: .largePad)))
        #expect(Region(code: "419").endings(typing: .english) == [".com", ".org", ".net", ".edu", ".gov"])
    }

    @Test func theEmojiKeysHoldOffersYourEmoji() {
        let search = EmojiSearch(text: "😀\t1\tgrinning\n👍 👍🏻 👍🏼 👍🏽 👍🏾 👍🏿\t2\tthumbs up")
        var history = EmojiHistory()
        history.use("👍🏽", base: "👍")
        let recents = search.held(.recents, custom: ["🍕"], history: history)
        #expect(recents.count == EmojiGrid.most && recents.first == "👍🏽")
        #expect(search.held(.custom, custom: ["🍕", "🌮"], history: history) == ["🍕", "🌮"])
        #expect(search.held(.custom, custom: Array(repeating: "🍕", count: 12), history: history).count == 8)
    }
}

/// A field whose host shows only the last 30 characters before the caret.
private final class WindowDocument: TestDocument {
    override var textBeforeInput: String? { String(text.prefix(cursor).suffix(30)) }
}
