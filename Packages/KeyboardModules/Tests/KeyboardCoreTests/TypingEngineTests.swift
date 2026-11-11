import Testing

@testable import KeyboardCore

struct TypingEngineTests {
    @Test func capitalizesFirstLetterOfDocument() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.documentChanged(document)
        #expect(engine.shift == .on)
        engine.type("hello", in: document)
        #expect(document.text == "Hello")
        #expect(engine.shift == .off)
    }

    @Test func autoCapitalizationTakesEffectTheMomentItChanges() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.documentChanged(document)
        engine.settings.autoCapitalization = false
        #expect(engine.shift == .off)
        engine.type("a", in: document)
        #expect(document.text == "a")

        engine.perform(.delete, in: document)
        engine.settings.autoCapitalization = true
        #expect(engine.shift == .on)
        engine.type("a", in: document)
        #expect(document.text == "A")
    }

    @Test func aSettingsChangeKeepsTheShiftYouPressed() {
        var engine = TypingEngine()
        let document = TestDocument("hi ")
        engine.documentChanged(document)
        engine.perform(.shift, in: document)
        engine.settings.oneHanded = .left
        #expect(engine.shift == .on)
    }

    @Test func capitalizesAfterSentenceEnd() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.documentChanged(document)
        engine.type("hi. there", in: document)
        #expect(document.text == "Hi. There")
    }

    @Test func doesNotCapitalizeAfterAbbreviationWithoutSpace() {
        #expect(!TypingEngine.shouldCapitalize("e.g.", mode: .sentences))
        #expect(TypingEngine.shouldCapitalize("Done!  ", mode: .sentences))
        #expect(TypingEngine.shouldCapitalize("Line\n", mode: .sentences))
        #expect(!TypingEngine.shouldCapitalize("one two ", mode: .sentences))
    }

    @Test func autocapitalizationModes() {
        #expect(!TypingEngine.shouldCapitalize("", mode: .none))
        #expect(TypingEngine.shouldCapitalize("one ", mode: .words))
        #expect(!TypingEngine.shouldCapitalize("one", mode: .words))
        #expect(TypingEngine.shouldCapitalize("anything", mode: .allCharacters))
    }

    @Test func doubleSpaceInsertsPeriod() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.documentChanged(document)
        engine.type("ok  go", in: document)
        #expect(document.text == "Ok. Go")
    }

    @Test func doubleSpaceNeedsAWordBefore() {
        var engine = TypingEngine()
        let document = TestDocument("Ok. ")
        engine.documentChanged(document)
        engine.perform(.space, in: document)
        #expect(document.text == "Ok.  ")
    }

    @Test func doubleSpaceRequiresConsecutiveSpaces() {
        var engine = TypingEngine()
        let document = TestDocument("ok ")
        engine.documentChanged(document)
        engine.perform(.space, in: document)
        #expect(document.text == "ok  ")
    }

    @Test func doubleSpacePeriodRespectsSmartPunctuation() {
        var engine = TypingEngine(traits: InputTraits(smartPunctuation: false))
        let document = TestDocument()
        engine.type("ok  ", in: document)
        #expect(document.text == "ok  ")
    }

    @Test func shiftTogglesAndDoubleTapLocks() {
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        let document = TestDocument()
        engine.pressShift(doubleTap: false)
        engine.releaseShift(in: document)
        #expect(engine.shift == .on)
        engine.pressShift(doubleTap: true)
        engine.releaseShift(in: document)
        #expect(engine.shift == .locked)
        engine.type("abc", in: document)
        #expect(document.text == "ABC")
        #expect(engine.shift == .locked)
        engine.pressShift(doubleTap: false)
        #expect(engine.shift == .off)
    }

    @Test func holdingShiftTypesCapitalsUntilReleased() {
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        let document = TestDocument()
        engine.pressShift(doubleTap: false)
        engine.type("ab", in: document)
        engine.releaseShift(in: document)
        engine.type("c", in: document)
        #expect(document.text == "ABc")
    }

    @Test func spaceReturnsToLettersFromNumbers() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.perform(.layer(.numbers), in: document)
        engine.perform(.character("4"), in: document)
        #expect(engine.layer == .numbers)
        engine.perform(.space, in: document)
        #expect(engine.layer == .letters)
    }

    @Test func apostropheReturnsToLetters() {
        var engine = TypingEngine()
        let document = TestDocument("don")
        engine.perform(.layer(.numbers), in: document)
        engine.perform(.character("'"), in: document)
        #expect(engine.layer == .letters)
    }

    @Test func numberFieldsStartOnNumbers() {
        var engine = TypingEngine()
        engine.update(InputTraits(kind: .number))
        #expect(engine.layer == .numbers)
        engine.perform(.layer(.letters), in: TestDocument())
        engine.update(InputTraits(kind: .number, returnKind: .done))
        #expect(engine.layer == .letters)
    }

    @Test func deleteWordRemovesWordAndTrailingSpace() {
        var engine = TypingEngine()
        let document = TestDocument("Hello there  ")
        engine.deleteWord(in: document)
        #expect(document.text == "Hello ")
        engine.deleteWord(in: document)
        #expect(document.text == "")
        engine.deleteWord(in: document)
        #expect(document.text == "")
    }

    @Test func deleteWordTreatsPunctuationAsOneCharacter() {
        #expect(TypingEngine.wordLength(before: "Hi!!") == 1)
        #expect(TypingEngine.wordLength(before: "it's") == 4)
    }

    @Test func returnInsertsNewlineAndCapitalizes() {
        var engine = TypingEngine()
        let document = TestDocument("one")
        engine.perform(.return, in: document)
        #expect(document.text == "one\n")
        #expect(engine.shift == .on)
    }

    @Test func smartPunctuationCurlsQuotesAndJoinsDashes() {
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        let document = TestDocument()
        engine.type("\"don't\" a--b", in: document)
        #expect(document.text == "“don’t” a—b")
        engine.settings.smartPunctuation = false
        engine.type(" 'x'", in: document)
        #expect(document.text == "“don’t” a—b 'x'")
    }

    /// What Apple's keyboard typed for the same keys in each language, read off it in the simulator.
    @Test func smartQuotesAreTheLanguagesOwn() {
        let typed = { (language: String, text: String) -> String in
            var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
            engine.settings.language = language
            let document = TestDocument()
            engine.type(text, in: document)
            return document.text
        }
        let typedOnApple = "\"a\" 'b' c'd x\"e\""
        #expect(typed("de", typedOnApple) == "„a“ ‚b‘ c‘d x“e“")
        #expect(typed("fr", typedOnApple) == "«\u{A0}a\u{A0}» ‘b’ c’d x\u{A0}»e\u{A0}»")
        #expect(typed("sv", typedOnApple) == "”a” ’b’ c’d x”e”")
        for language in ["en", "es", "pt", "it"] {
            #expect(typed(language, typedOnApple) == "“a” ‘b’ c’d x”e”")
        }
        #expect(typed("de", "(\"so\")") == "(„so“)")
    }

    /// A 13-inch iPad's accent key, as Apple's: its accent lands on the letter typed next, ´ then e is é, while a
    /// letter that can't take it, a space or the accent again comes after it, and a delete leaves nothing waiting.
    @Test func aDeadKeyAccentsTheNextLetter() {
        var accent = Key.character("´")
        accent.isDeadKey = true
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        let document = TestDocument()
        let press = { (engine: inout TypingEngine) in
            _ = engine.handle(.type(accent, Tap(x: 0, y: 0, key: "´")), in: document)
        }
        for typed in ["e", "a", "q", "n", " ", "´"] {
            press(&engine)
            if typed == "´" { press(&engine) } else { engine.type(typed, in: document) }
            engine.type(" ", in: document)
        }
        press(&engine)
        engine.perform(.shift, in: document)
        engine.type("e ", in: document)
        press(&engine)
        engine.perform(.delete, in: document)
        engine.type("e", in: document)
        #expect(document.text == "é á ´q ń ´  ´´ É e")
    }

    /// French's ’ key on an iPhone, as Apple's: it accents the vowel before it, types ’ after any other letter and ´
    /// anywhere else, shifted or not.
    @Test func frenchsAccentKeyAccentsTheLetterBeforeIt() {
        var key = Key.character("'")
        key.shifted = "´"
        key.accentsLetterBefore = true
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        let document = TestDocument()
        let press = { (engine: inout TypingEngine) in
            _ = engine.handle(.type(key, Tap(x: 0, y: 0, key: "'")), in: document)
        }
        for typed in ["", "e", "a", "u", "o", "i", "c", "n", "ee", "l"] {
            engine.type(typed, in: document)
            press(&engine)
            if typed == "ee" { press(&engine) }
            if typed == "l" { engine.type("e", in: document) }
            engine.type(" ", in: document)
        }
        engine.type("e", in: document)
        engine.perform(.shift, in: document)
        press(&engine)
        #expect(document.text == "´ é à û ô î c’ n’ eé’ l’e é")
    }

    @Test func keysActOnTheirOwnPhaseOfTheTouch() {
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        let document = TestDocument("ab")
        let letter = Key.character("c")
        let events: [KeyboardEvent] = [
            .down(letter, tapCount: 1), .type(letter, Tap(x: 0, y: 0, key: "c")), .down(Key(.delete), tapCount: 1),
            .trigger(Key(.return)), .trigger(Key(.dismiss)),
        ]
        let handled = events.map { engine.handle($0, in: document) }
        #expect(handled == [false, true, true, true, false])
        #expect(document.text == "ab\n")
    }

    @Test func slidingFromALayerKeyTypesOneSymbolAndComesBack() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.handle(.down(Key(.layer(.numbers)), tapCount: 1), in: document)
        engine.handle(.slide("4"), in: document)
        #expect(document.text == "4")
        #expect(engine.layer == .letters)
    }
}
