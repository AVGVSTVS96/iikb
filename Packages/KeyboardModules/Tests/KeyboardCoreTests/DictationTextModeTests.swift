import Testing

@testable import KeyboardCore

struct DictationTextModeTests {
    private func write(_ heard: String, _ mode: DictationTextMode) -> String {
        DictationWriting(style: .casual, textMode: mode).written(heard)
    }

    private func typed(_ heard: String, _ mode: DictationTextMode) -> String {
        DictationWriting(style: .casual, textMode: mode).typed(heard, lexicon: nil)
    }

    @Test func spelledOutKeepsEveryWord() {
        let heard = "By the way, are you free tonight?"
        #expect(write(heard, .spelledOut) == heard)
        #expect(KeyboardSettings.initial.dictation(in: nil).textMode == .spelledOut)
    }

    @Test func abbreviatedWritesPhrasesAsLettersAndKeepsSingleWords() {
        #expect(
            typed("By the way, I don't know if you're free tonight. Let me know.", .abbreviated)
                == "Btw, idk if you're free tonight. Lmk")
        #expect(write("I DON’T KNOW", .abbreviated) == "idk")
    }

    @Test func textingAlsoShortensWordsInLowercase() {
        #expect(typed("By the way, are you free tonight? Talk to you later.", .texting) == "btw, r u free tn? ttyl")
        #expect(typed("See you later, thank you.", .texting) == "cya l8r, ty")
    }

    @Test func genZTradesWordsForSlang() {
        #expect(
            typed("For real, the food was really amazing. That's hilarious.", .genZ)
                == "fr, the food was highkey fire. i'm dead 💀")
        #expect(
            typed("I don't know, you're excited. An amazing show. I'm serious.", .genZ)
                == "idk, ur hyped. a fire show. no cap")
    }

    @Test func aWordWithOtherSensesStaysOutsideAPhraseThatPinsItDown() {
        #expect(
            typed("I'm going to the store, what kind of car, a great deal, I don't really care.", .genZ)
                == "i'm going to the store, what kind of car, a great deal, i don't rly care")
        #expect(
            typed("I can't see you, we had a good night, what exactly happened.", .genZ)
                == "i can't see u, we had a good night, what exactly happened")
        #expect(
            write(
                "That's so funny you mention it. I'm serious about quitting. It looks like rain, what kinda car.", .genZ
            ) == "That's so funny u mention it. I'm serious about quitting. It looks like rain, what kinda car")
    }

    @Test func aPhraseIsSwappedOnlyAsWholeWordsWithSpacesBetween() {
        #expect(write("By the, way", .abbreviated) == "By the, way")
        #expect(write("Yours, your house", .texting) == "Yours, ur house")
        #expect(write("So amazing, amazingly", .genZ) == "So fire, amazingly")
    }

    @Test func textingIsTypedWithoutCapitalsWhateverTheStyle() {
        #expect(DictationWriting(style: .formal, textMode: .texting).capitals(in: .sentences) == .none)
        #expect(DictationWriting(style: .formal, textMode: .abbreviated).capitals(in: .sentences) == .sentences)
    }
}
