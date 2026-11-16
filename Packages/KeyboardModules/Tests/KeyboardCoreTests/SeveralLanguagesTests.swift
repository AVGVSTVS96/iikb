import Foundation
import Testing

@testable import KeyboardCore

/// English and German typed at once on the iPhone's English layout: English's bundled words with German's from
/// Languages/de.tsv.
struct SeveralLanguagesTests {
    static let english: Lexicon = {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/KeyboardEnglish/Resources/en.lexicon")
        return Lexicon(bytes: [UInt8](FileManager.default.contents(atPath: file.path)!))!
    }()
    static let german = AlphabetTests.german
    static let packs = [LanguagePack(.english, lexicon: english), LanguagePack(.german, lexicon: german)]
    static let both = Lexicon(merging: [english, german])

    static func corrector() -> Corrector {
        let corrector = Corrector(typing: packs, words: both)
        corrector.grid = AlphabetTests.grid
        return corrector
    }

    @Test func oneLexiconHoldsTheWordsOfBoth() throws {
        let both = Self.both
        #expect(Set(both.letters) == Set(Self.english.letters + Self.german.letters))
        #expect(try #require(Lexicon(bytes: both.bytes)).wordCount == both.wordCount)
        var words = 0
        for (lexicon, other) in [(Self.english, Self.german), (Self.german, Self.english)] {
            for prefix in lexicon.letters {
                for word in lexicon.mostFrequent(count: 40, startingWith: prefix) {
                    words += 1
                    let own = try #require(lexicon.logProbability(of: word))
                    let mean = (Math.exp(own) + (other.logProbability(of: word).map(Math.exp) ?? 0)) / 2
                    let merged = try #require(both.logProbability(of: word), "\(word)")
                    #expect(abs(merged - Math.log(mean)) < 0.11, "\(word)")
                }
            }
        }
        #expect(words > 1500)
        #expect(both.canonical("haus") == "Haus" && both.canonical("über") == "über")
        #expect(both.canonical("hand") == "hand" && both.canonical("i") == "I")
        #expect(both.mostFrequent(count: 3).contains("the"))
    }

    @Test func theWordsBeforeSayWhichLanguageIsWritten() {
        let corrector = Self.corrector()
        #expect(corrector.shares(after: "") == [0.5, 0.5])
        #expect(corrector.shares(after: "see you tomorrow ")[0] > 0.9)
        #expect(corrector.shares(after: "wir haben heute nicht ")[1] > 0.9)
        #expect(corrector.shares(after: "see you tomorrow, wir haben heute nicht ")[1] > 0.9)
        #expect(corrector.shares(after: "wir haben heute nicht. See you tomorrow ")[0] > 0.9)
        let named = corrector.shares(after: "Zbigniew 2026 ")
        #expect(abs(named[0] - 0.5) < 0.05)
        #expect(corrector.language(writing: "wir haben") == .german)
        #expect(corrector.language(writing: "see you") == .english)
        #expect(AlphabetTests.corrector(Self.german).language(writing: "see you") == nil)
    }

    /// A word either language's own corrector leaves as typed stays that word with both, whichever language the words
    /// before it are in, with the capital the language written gives it ("see" is German's "See").
    @Test func aWordOfEitherLanguageIsNeverChanged() {
        let corrector = Self.corrector()
        let alone = [AlphabetTests.corrector(Self.english), AlphabetTests.corrector(Self.german)]
        let words = [
            ["see", "you", "tomorrow", "please", "thanks", "with", "were", "about", "night", "their", "die", "hat"],
            ["ich", "nicht", "aber", "heute", "wir", "sind", "mit", "später", "über", "haben", "immer", "wieder"],
        ]
        var kept = 0
        for (words, alone) in zip(words, alone) {
            for word in words {
                let typed = AlphabetTests.typed(word, previous: "")
                guard alone.correction(for: typed, context: "") == nil else { continue }
                kept += 1
                for context in ["", "see you tomorrow ", "wir haben heute nicht "] {
                    let read = corrector.correction(for: typed, context: context) ?? word
                    #expect(read.lowercased() == word, "\(word) after \"\(context)\"")
                }
            }
        }
        #expect(kept >= 20)
    }

    /// A slip is read as a word of the language being written, and accents come back in German whatever came before.
    @Test func aSlipIsReadInTheLanguageBeingWritten() {
        let corrector = Self.corrector()
        let read = { (word: String, context: String) in
            corrector.correction(
                for: AlphabetTests.typed(word, previous: context.split(separator: " ").last.map { $0.lowercased() }),
                context: context)
        }
        #expect(read("nivht", "wir haben ") == "nicht")
        #expect(read("tomorrpw", "see you ") == "tomorrow")
        #expect(read("spater", "see you tomorrow, wir sind ") == "später")
        #expect(read("uber", "wir sprechen ") == "über")
        #expect(read("thr", "see you at ") == "the")
    }

    /// Where no key shows ü, "fur" is how "für" is typed: after German words it's read as that, and stays English's
    /// word after English ones. Where the words before don't say which, at a message's start or after a word of both,
    /// the far likelier word is read, and a word about as likely as its twin stays ("stuck", "Stück").
    @Test func aWordOnAnothersKeysIsReadInTheLanguageWritten() {
        let corrector = Self.corrector()
        #expect(Self.english.isWord("fur") && !Self.german.isWord("fur") && Self.german.isWord("für"))
        #expect(Self.english.isWord("stuck") && !Self.german.isWord("stuck") && Self.german.isWord("stück"))
        let read = { (word: String, context: String) in
            corrector.correction(
                for: AlphabetTests.typed(word, previous: context.split(separator: " ").last.map(String.init)),
                context: context)
        }
        #expect(read("fur", "wir haben heute ") == "für")
        #expect(read("fur", "see you tomorrow with the ") == nil)
        #expect(read("fur", "") == "für")
        #expect(read("stuck", "") == nil)
        #expect(read("stuck", "wir haben heute ein ") == "Stück")
        #expect(read("stuck", "in ") == nil)
    }

    /// A word both languages have is spelled as the one being written spells it, and as typed where the words before
    /// don't say which ("in" is a word of both). The bar offers the words of the one being written.
    @Test func capitalsAndTheBarFollowTheLanguageWritten() {
        let corrector = Self.corrector()
        #expect(Self.german.canonical("hand") == "Hand" && Self.english.canonical("hand") == "hand")
        let hand = AlphabetTests.typed("hand", previous: "die")
        #expect(corrector.correction(for: hand, context: "wir haben heute die ") == "Hand")
        #expect(corrector.correction(for: hand, context: "see you tomorrow with the ") == nil)
        #expect(Self.german.isWord("in") && Self.english.isWord("in"))
        #expect(corrector.correction(for: AlphabetTests.typed("hand", previous: "in"), context: "in ") == nil)
        #expect(corrector.correction(for: AlphabetTests.typed("hand"), context: "") == nil)
        let german = corrector.predictions(after: "nicht", earlier: "heute", context: "wir haben heute nicht ")
        #expect(german.prefix(3).allSatisfy { Self.german.isWord($0.text.lowercased()) }, "\(german.map(\.text))")
        let english = corrector.predictions(after: "tomorrow", earlier: "you", context: "see you tomorrow ")
        #expect(english.prefix(3).allSatisfy { Self.english.isWord($0.text.lowercased()) }, "\(english.map(\.text))")
    }

    /// Smart quotes are those of the language being written: German's after German words, English's after English.
    @Test func quotesFollowTheLanguageWritten() {
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        engine.settings.languages = [.english, .german]
        engine.settings.autoCorrection = false
        engine.corrector = Self.corrector()
        let document = TestDocument()
        for character in "wir haben heute \"nicht\" and then she said \"no\"" {
            engine.perform(character == " " ? .space : .character(String(character)), in: document)
        }
        #expect(document.text == "wir haben heute „nicht“ and then she said “no”")
    }

    /// One language typed is exactly the corrector it was: no shares, the language's own lexicon.
    @Test func oneLanguageTypesAsBefore() {
        let one = Corrector(typing: [Self.packs[1]])
        #expect(one.languages.map(\.language) == [.german] && one.lexicon === Self.german)
        one.grid = AlphabetTests.grid
        let alone = AlphabetTests.corrector(Self.german)
        for word in ["nivht", "uber", "strasse", "hsus", "mogren"] {
            let typed = AlphabetTests.typed(word)
            #expect(one.correction(for: typed, context: "") == alone.correction(for: typed, context: ""))
        }
    }
}
