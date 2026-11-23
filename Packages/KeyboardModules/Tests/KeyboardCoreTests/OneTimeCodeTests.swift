import Testing

@testable import KeyboardCore

struct OneTimeCodeTests {
    private func marked(_ kind: InputKind, setsAutocorrection: Bool) -> InputTraits {
        InputTraits(
            kind: kind, content: InputContent(.oneTimeCode, kind: kind, setsAutocorrection: setsAutocorrection),
            autocorrection: true)
    }

    private func dictate(_ heard: String, into traits: InputTraits) -> String {
        var engine = TypingEngine(traits: traits)
        engine.corrector = Corrector(source: testLexicon)
        let document = TestDocument()
        engine.handle(.dictated(heard, plain: nil), in: document)
        return document.text
    }

    @Test func aCodeFieldIsOneBuiltForACode() {
        #expect(marked(.number, setsAutocorrection: false).content == .oneTimeCode, "a number pad")
        #expect(marked(.decimal, setsAutocorrection: false).content == .oneTimeCode, "a decimal pad")
        #expect(marked(.text, setsAutocorrection: true).content == .oneTimeCode, "Safari's one-time-code input")
        #expect(marked(.text, setsAutocorrection: false).content == .other, "a chat box marked a code")
        #expect(InputContent(.postalCode, kind: .text, setsAutocorrection: false) == .postalCode)
        #expect(InputContent(.other, kind: .number, setsAutocorrection: true) == .other)
    }

    @Test func aChatBoxMarkedACodeCorrectsAndTakesProse() {
        let chat = marked(.text, setsAutocorrection: false)
        #expect(chat.allowsCorrection)
        #expect(dictate("See you at seven.", into: chat).contains("seven"))
        let safari = marked(.text, setsAutocorrection: true)
        #expect(!safari.allowsCorrection)
        #expect(dictate("Oh seven, oh nine.", into: safari) == "0709")
        #expect(dictate("Oh seven, oh nine.", into: marked(.number, setsAutocorrection: false)) == "0709")
    }
}
