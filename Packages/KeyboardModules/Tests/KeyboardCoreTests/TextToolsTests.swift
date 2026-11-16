import Testing

@testable import KeyboardCore

struct CalculatorTests {
    private func answer(_ text: String) -> String? { Calculation(before: text)?.answer }

    @Test(arguments: [
        ("12*4", "48"), ("2 + 3 × 4", "14"), ("(2 + 3) × 4", "20"), ("10 / 4", "2.5"), ("0.1 + 0.2", "0.3"),
        ("2^10", "1024"), ("-2^2", "-4"), ("20% of 80", "16"), ("80 + 20%", "96"), ("1,200 * 3", "3600"),
        ("1/3 + 0", "0.333333333333"), ("3 x 4", "12"), ("10 - 3", "7"), ("7 ÷ 2", "3.5"),
        ("2^100", "1.26765060023e+30"),
    ])
    func calculations(_ typed: String, _ expected: String) {
        #expect(answer(typed) == expected)
    }

    @Test(arguments: [
        ("10 km in mi", "6.21371 mi"), ("10km to miles", "6.21371 miles"), ("100 f in c", "37.7778 °C"),
        ("5 fl oz in ml", "147.868 mL"), ("1 mile in feet", "5280 feet"), ("60 MPH in KPH", "96.5606 KPH"),
        ("12 in in cm", "30.48 cm"), ("2 + 3 kg in lb", "11.0231 lb"), ("0 c in k", "273.15 K"),
        ("1 GiB in MiB", "1024 MiB"), ("10 km in m", "10000 m"),
    ])
    func conversions(_ typed: String, _ expected: String) {
        #expect(answer(typed) == expected)
    }

    @Test(arguments: [
        "5", "50%", "call 555-1234", "on 2026-11-15", "on 11/15", "a 1920x1080 screen", "abc-3+4", "2+2 ",
        "version 1.2.3", "at 10:30", "5 km", "I ran 5 km in an hour", "it's 5 to 6", "1/0 + 1", "(2+3", "12x4", "x-3+4",
        "Meeting 9:30 - 10", "10:45 + 30", "- 5 + 3", "total - 5 + 3", "5 feet 6 inches in cm", "1 000 + 1",
        "I ran 5 km in m", "2019 – 2021",
    ])
    func notCalculations(_ typed: String) {
        #expect(answer(typed) == nil)
    }

    @Test(arguments: [
        ("0.1 + 0.2 - 0.3", "0"), ("999999999999999 * 10", "1e+16"), ("1 / 10^11", "1e-11"),
        ("10^14", "100000000000000"),
        ("-7 / 2", "-3.5"), ("9.9999999999999 + 0", "10"), ("1000000000000 - 999999999999.5", "0.5"),
        ("12345678901.5 + 1", "12345678902.5"), ("50% + 20%", "70%"), ("80 - 20%", "64"),
    ])
    func numbers(_ typed: String, _ expected: String) {
        #expect(answer(typed) == expected)
    }

    @Test func numbersAreReadAsTheLanguageWritesThem() {
        let comma: (String) -> String? = { Calculation(before: $0, mark: ",")?.answer }
        #expect(comma("3,5 + 2") == "5,5")
        #expect(comma("10 / 4") == "2,5")
        #expect(comma("10 km in mi") == "6,21371 mi")
        #expect(comma("1.500 + 500") == nil)
        #expect(comma("0.5 + 1") == nil)
        #expect(comma("1,2,3 + 1") == nil)
        #expect(comma("1,500 + 250") == nil)
        #expect(comma("0,125 + 1") == "1,125")
        #expect(answer("3,5 + 2") == nil)
        #expect(answer("1.500 + 500") == "501.5")
    }

    @Test func theBarAnswersInTheKeyboardsLanguage() {
        var engine = TypingEngine()
        engine.settings.languages = [.german]
        let document = TestDocument()
        engine.type("3,5*2", in: document)
        #expect(engine.suggestions.first?.title == "= 7")
        engine.type("+0,25", in: document)
        engine.accept(engine.suggestions[0], in: document)
        #expect(document.text == "7,25 ")
    }

    @Test func languagesThatWriteNumbersApartGetOnlyWholeNumbers() {
        let mixed: (String) -> String? = { Calculation(before: $0, mark: nil)?.answer }
        #expect(mixed("12 * 4") == "48")
        #expect(mixed("1,5 + 1") == nil)
        #expect(mixed("1.5 + 1") == nil)
        #expect(mixed("10 / 4") == nil)
        var engine = TypingEngine()
        engine.settings.languages = [.english, .german]
        let document = TestDocument()
        engine.type("1,5*2", in: document)
        #expect(!engine.suggestions.contains { $0.title.hasPrefix("=") })
    }

    @Test func aLongSumIsReadWholeOrNotAtAll() {
        let sum = (0..<40).map { "\($0 * 100 + 123)" }.joined(separator: " + ")
        #expect(answer(sum) == nil)
        #expect(answer("Call 555-1234 then 2+3") == "5")
    }

    @Test func aLoneDashOrSlashCountsOnceSpacedOrFollowedByEquals() {
        #expect(answer("10-3=") == "7")
        #expect(answer("3/4 =") == "0.75")
        #expect(answer("3/4 + 1") == "1.75")
    }

    @Test func theAnswerReplacesOnlyTheCalculationAndFollowsAnEquals() {
        #expect(Calculation(before: "I owe you 20+5")?.replacing == "20+5")
        #expect(Calculation(before: "Total: 3 * 4")?.replacing == "3 * 4")
        #expect(Calculation(before: "first line\n10 km in mi")?.replacing == "10 km in mi")
        #expect(Calculation(before: "so 2+2 =")?.replacing == "")
    }

    @Test func theBarOffersTheAnswerAndATapTypesItInPlace() {
        var engine = TypingEngine()
        let document = TestDocument("I owe you ")
        engine.type("20+5", in: document)
        #expect(engine.suggestions == [Suggestion("25", .answer(replacing: "20+5"))])
        #expect(engine.suggestions.first?.title == "= 25")
        engine.accept(engine.suggestions[0], in: document)
        #expect(document.text == "I owe you 25 ")
    }

    @Test func afterAnEqualsTheAnswerFollowsIt() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.type("6*7=", in: document)
        engine.accept(engine.suggestions[0], in: document)
        #expect(document.text == "6*7=42 ")
        engine.type("so 3/4 =", in: document)
        engine.accept(engine.suggestions[0], in: document)
        #expect(document.text == "6*7=42 so 3/4 = 0.75 ")
    }

    @Test func anAnswerForTextThatChangedIsNotTyped() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.type("6*7=", in: document)
        let answer = engine.suggestions[0]
        engine.type("x", in: document)
        engine.accept(answer, in: document)
        #expect(document.text == "6*7=x")
    }

    @Test func whileTheBarShowsAnAnswerSpaceLeavesTheWordAsTyped() {
        var engine = TypingEngine.correcting(WordListSource(["in", "mine"]))
        let document = TestDocument("it was 3 hrs in ")
        engine.documentChanged(document)
        engine.type("min", in: document)
        #expect(engine.suggestions.map(\.title) == ["= 180 min"])
        engine.type(" ", in: document)
        #expect(document.text == "it was 3 hrs in min ")
    }

    @Test func undoTakesBackATypedAnswer() {
        var engine = TypingEngine()
        let document = TestDocument("so ")
        engine.type("20+5", in: document)
        engine.accept(engine.suggestions[0], in: document)
        engine.perform(.undo, in: document)
        #expect(document.text == "so 20+5")
    }

    @Test func noAnswerWithTheCaretInsideTheCalculation() {
        var engine = TypingEngine()
        let document = TestDocument("20+50")
        document.cursor = 4
        engine.documentChanged(document)
        #expect(engine.suggestions.allSatisfy { if case .answer = $0.kind { false } else { true } })
    }

    @Test func noAnswerWithPredictiveTextOff() {
        var engine = TypingEngine()
        engine.settings.predictiveText = false
        let document = TestDocument()
        engine.type("6*7", in: document)
        #expect(engine.suggestions.isEmpty)
    }
}

struct TextStyleTests {
    private func style(_ name: String) -> TextStyle { TextStyle.all.first { $0.name == name }! }

    @Test func stylesMapLettersAndDigitsAndLeaveTheRest() {
        #expect(style("Bold Serif").apply(to: "Hi, 42!") == "𝐇𝐢, 𝟒𝟐!")
        #expect(style("Script").apply(to: "Hello") == "ℋℯ𝓁𝓁ℴ")
        #expect(style("Fraktur").apply(to: "Zahl") == "ℨ𝔞𝔥𝔩")
        #expect(style("Double-Struck").apply(to: "RN 1") == "ℝℕ 𝟙")
        #expect(style("Monospace").apply(to: "code") == "𝚌𝚘𝚍𝚎")
        #expect(style("Circled").apply(to: "ab 10") == "ⓐⓑ ①⓪")
        #expect(style("Small Caps").apply(to: "Hey") == "Hᴇʏ")
        #expect(style("Italic Serif").apply(to: "ah é") == "𝑎ℎ é")
    }

    @Test func restylingStartsFromThePlainLetters() {
        let bold = style("Bold Serif").apply(to: "Hello")
        #expect(style("Script").apply(to: bold) == style("Script").apply(to: "Hello"))
        #expect(TextStyle.plain(style("Fraktur").apply(to: "Ciao Roma")) == "Ciao Roma")
    }

    @Test func everyStyleHasAFormForEachLetterAndDigit() {
        for style in TextStyle.all {
            #expect(style.forms.count == 62, "\(style.name)")
        }
    }
}

struct LetterCaseTests {
    @Test(arguments: [
        (LetterCase.upper, "hello World", "HELLO WORLD"),
        (.lower, "Hello World", "hello world"),
        (.sentence, "HELLO THERE. how are you? I'm fine\nnext line", "Hello there. How are you? I'm fine\nNext line"),
        (.sentence, "3 men in a boat. ok", "3 men in a boat. Ok"),
        (.sentence, "an i5 chip and the i/o port", "An i5 chip and the i/o port"),
        (.sentence, "Jag bor i Stockholm", "Jag bor i stockholm"),
        (.title, "line one\nthe second line", "Line One\nThe Second Line"),
        (.snake, "😀 👍\nhi there", "😀 👍\nhi_there"),
        (.sentence, "it costs 3.50 today", "It costs 3.50 today"),
        (.title, "the lord of the rings", "The Lord of the Rings"),
        (.title, "what are you looking at", "What Are You Looking At"),
        (.title, "THE WAR OF THE WORLDS", "The War of the Worlds"),
        (.title, "my new iPhone and NASA", "My New iPhone and NASA"),
        (.title, "The Lord Of The Rings in Portland OR", "The Lord of the Rings in Portland OR"),
        (.sentence, "he said \"stop.\" then left", "He said \"stop.\" Then left"),
        (.snake, "Hello, World! It's me", "hello_world_its_me"),
        (.snake, "parseHTTPServer2", "parse_http_server2"),
        (.camel, "hello big world", "helloBigWorld"),
        (.camel, "user_id\nfirst-name", "userId\nfirstName"),
    ])
    func cases(_ letterCase: LetterCase, _ text: String, _ expected: String) {
        #expect(letterCase.apply(to: text) == expected)
    }

    @Test func styledLettersKeepTheirStyle() {
        let bold = TextStyle.all[0].apply(to: "hello world")
        #expect(LetterCase.upper.apply(to: bold) == TextStyle.all[0].apply(to: "HELLO WORLD"))
        #expect(LetterCase.title.apply(to: bold) == TextStyle.all[0].apply(to: "Hello World"))
    }
}

struct RewriteTests {
    private let bold = Rewrite.style(TextStyle.all[0])
    private let script = Rewrite.style(TextStyle.all.first { $0.name == "Script" }!)

    @Test func aRewriteChangesTheSelection() {
        var engine = TypingEngine()
        let document = TestDocument("say hello world")
        document.select("hello")
        engine.handle(.rewrite(.letterCase(.upper)), in: document)
        #expect(document.text == "say HELLO world")
    }

    @Test func withNothingSelectedItChangesTheWholeFieldAndLeavesTheCaretAtItsEnd() {
        var engine = TypingEngine()
        let document = TestDocument("hello there world")
        document.cursor = 5
        engine.handle(.rewrite(.letterCase(.title)), in: document)
        #expect(document.text == "Hello There World")
        #expect(document.cursor == document.text.count)
    }

    @Test func aLongFieldIsReadWindowByWindowAndRewrittenWhole() {
        var engine = TypingEngine()
        let words = (0..<700).map { "w\($0)" }.joined(separator: " ")
        let document = ClippedDocument(words, window: 300)
        document.cursor = 1000
        engine.handle(.rewrite(.letterCase(.upper)), in: document)
        #expect(document.text == words.uppercased())
        #expect(document.cursor == document.text.count)
        engine.handle(.rewrite(bold), in: document)
        #expect(document.text == bold.apply(to: words.uppercased()))
    }

    @Test func aFieldCutAtEachLineIsReadLineByLine() {
        var engine = TypingEngine()
        let document = LineCutDocument("para one\n\npara two\n" + String(repeating: "long line ", count: 80))
        document.cursor = 3
        engine.handle(.rewrite(.letterCase(.upper)), in: document)
        #expect(document.text == "PARA ONE\n\nPARA TWO\n" + String(repeating: "LONG LINE ", count: 80))
        #expect(document.cursor == document.text.count)
    }

    @Test func aFieldThatCantBeReadIsLeftAlone() {
        let document = ShiftingDocument("hello there world")
        document.cursor = 5
        var engine = TypingEngine()
        engine.handle(.rewrite(.letterCase(.upper)), in: document)
        #expect(document.text == "hello there world")
    }

    @Test func undoTakesBackARewrite() {
        var engine = TypingEngine()
        engine.settings.autoCapitalization = false
        let document = TestDocument()
        engine.documentChanged(document)
        engine.type("ab cd", in: document)
        engine.handle(.rewrite(.letterCase(.upper)), in: document)
        #expect(document.text == "AB CD")
        engine.perform(.undo, in: document)
        #expect(document.text == "ab cd")
    }

    @Test func pickingAnotherStyleChangesWhatTheLastOneWrote() {
        var engine = TypingEngine()
        let document = TestDocument("intro ")
        document.text += "hello"
        document.cursor = document.text.count
        document.select("hello")
        engine.handle(.rewrite(bold), in: document)
        engine.handle(.rewrite(script), in: document)
        #expect(document.text == "intro " + script.apply(to: "hello"))
        engine.handle(.rewrite(.letterCase(.upper)), in: document)
        #expect(document.text == "intro " + script.apply(to: "HELLO"))
        #expect(engine.rewriting == script.apply(to: "HELLO"))
    }

    @Test func aStyleWithoutSmallLettersDoesNotLoseThemForTheNext() {
        var engine = TypingEngine()
        let document = TestDocument("Hello World")
        let squared = Rewrite.style(TextStyle.all.first { $0.name == "Squared" }!)
        engine.handle(.rewrite(squared), in: document)
        #expect(engine.preview(bold) == bold.apply(to: "Hello World"))
        engine.handle(.rewrite(bold), in: document)
        #expect(document.text == bold.apply(to: "Hello World"))
    }

    @Test func typingAfterARewriteEndsIt() {
        var engine = TypingEngine()
        let document = TestDocument("ok")
        engine.handle(.rewrite(.letterCase(.upper)), in: document)
        engine.type(" then ok", in: document)
        engine.handle(.rewrite(bold), in: document)
        #expect(document.text == bold.apply(to: "OK then ok"))
    }

    @Test func thePanelsListTheirRewritesAndSearchByName() {
        #expect(Panel.textStyles.rewrites().count == TextStyle.all.count)
        #expect(Panel.changeCase.rewrites(matching: "cam").map(\.name) == ["camelCase"])
        #expect(
            Panel.textStyles.rewrites(matching: "bold s").map(\.name) == [
                "Bold Serif", "Bold Italic Serif", "Bold Sans", "Bold Script",
            ])
        #expect(Rewrite.style(TextStyle.all[0]).title == "𝐁𝐨𝐥𝐝 𝐒𝐞𝐫𝐢𝐟")
    }
}

/// A host whose caret moves one character short of each long move forward, as a host counting in other units might.
private final class ShiftingDocument: TestDocument {
    override func moveCursor(by offset: Int) {
        super.moveCursor(by: offset > 1 ? offset - 1 : offset)
    }
}

/// A host showing 300 characters either side of the caret, and none past the line it's on.
private final class LineCutDocument: TestDocument {
    override var textBeforeInput: String? {
        String(text.prefix(cursor).split(separator: "\n", omittingEmptySubsequences: false).last!.suffix(300))
    }
    override var textAfterInput: String? {
        String(
            text.dropFirst(cursor + selection).split(separator: "\n", omittingEmptySubsequences: false)[0].prefix(300))
    }
}
