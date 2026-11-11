import Foundation
import Testing

@testable import KeyboardCore

/// German and Spanish typed on lexicons built from word counts (Languages/, from AOSP's word lists), on the iPhone's
/// English layout, where ä, ö, ü, ß, á, é, í, ñ, ó and ú sit under long-presses.
struct AlphabetTests {
    static func counts(_ language: String) -> [(word: String, count: Double)] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(
            path: "Languages/\(language).tsv")
        return ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t")
            guard fields.count == 2, let count = Double(fields[1]) else { return nil }
            return (String(fields[0]), count)
        }
    }

    static let german = Lexicon(counts: counts("de"))
    static let spanish = Lexicon(counts: counts("es"))
    static let grid = KeyGrid(
        Layouts.layout(for: LayoutContext(device: .phone, layer: .letters)), width: 402,
        metrics: KeyboardMetrics.phone(width: 402).grid, signature: "languages")

    /// The word typed dead center on the keys that hold its letters, without a long-press.
    static func typed(_ word: String, previous: String? = nil) -> TypedWord {
        let keys = word.map { grid.key(holding: String($0).lowercased())! }
        let taps = keys.map { key in
            let frame = grid.frame(of: key)!
            return Tap(x: frame.midX, y: frame.midY, key: key)
        }
        let text = zip(word, keys).map { $0.isUppercase ? $1.uppercased() : $1 }.joined()
        return TypedWord(text, taps: taps, previous: previous)
    }

    static func corrector(_ lexicon: Lexicon) -> Corrector {
        let corrector = Corrector(source: lexicon)
        corrector.grid = grid
        return corrector
    }

    @Test func aLexiconCarriesItsOwnLetters() throws {
        #expect(
            Lexicon(counts: [(word: "don't", count: 2.0), (word: "Cat", count: 1.0)]).letters == [
                "'", "a", "c", "d", "n", "o", "t",
            ])
        let english = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/KeyboardEnglish/Resources/en.lexicon")
        let bytes = try #require(FileManager.default.contents(atPath: english.path))
        #expect(try #require(Lexicon(bytes: [UInt8](bytes))).letters.joined() == "'abcdefghijklmnopqrstuvwxyz")
        for letter in ["ä", "ö", "ü", "ß"] { #expect(Self.german.letters.contains(letter)) }
        #expect(Self.spanish.letters.contains("ñ"))
        #expect(!Self.german.letters.contains { $0 != $0.lowercased() })
        let copy = try #require(Lexicon(bytes: Self.german.bytes))
        #expect(copy.letters == Self.german.letters)
        #expect(copy.wordCount == Self.german.wordCount)
        #expect(Self.german.canonical("ÜBER") == "über")
        #expect(Self.german.canonical("haus") == "Haus")
        #expect(Self.spanish.canonical("ESPAÑOL") == "español")
    }

    @Test func aWordGivenInLowercaseAtAllStaysLowercase() {
        let lexicon = Lexicon(
            counts: [("Essen", 2), ("essen", 1), ("Haus", 1), ("’s", 1)].map { (word: $0.0, count: Double($0.1)) })
        #expect(lexicon.canonical("essen") == "essen")
        #expect(lexicon.canonical("haus") == "Haus")
        #expect(lexicon.isWord("'s"))
    }

    @Test func aLetterWithNoKeyOfItsOwnIsTheKeyItIsUnder() {
        let keys = LetterKeys(Self.german, on: Self.grid)
        let key = { (letter: String) in keys.keys[Self.german.letters.firstIndex(of: letter)!] }
        #expect(key("ü") == "u")
        #expect(key("ß") == "s")
        #expect(key("u") == "u")
        let qwertz = KeyGrid(
            KeyboardLayout(rows: [RowItem.keys("qwertzuiopü"), RowItem.keys("asdfghjklöä"), RowItem.keys("yxcvbnm")]),
            width: 402, metrics: KeyboardMetrics.phone(width: 402).grid)
        let own = LetterKeys(Self.german, on: qwertz)
        #expect(own.keys[Self.german.letters.firstIndex(of: "ö")!] == "ö")
    }

    /// A key showing a letter none of the words use still types it, as likely as a letter no word continues with.
    @Test func aKeyWhoseLetterNoWordUsesStillTypes() {
        let lexicon = Lexicon(counts: [(word: "day", count: 1.0)])
        let corrector = Self.corrector(lexicon)
        #expect(corrector.letters(lexicon).letters.count == 26)
        #expect(corrector.correction(for: Self.typed("qzxv")) == nil)
        let odds = corrector.letters(lexicon).keyOdds(corrector.languageModel(lexicon).next(after: "d"))
        #expect(odds["q"] == odds["z"] && odds["q"]! < odds["a"]!)
    }

    @Test func accentsComeBackFromTheWordList() {
        let german = Self.corrector(Self.german)
        for (typed, meant) in [("uber", "über"), ("fur", "für"), ("spater", "später"), ("mussen", "müssen")] {
            #expect(german.correction(for: Self.typed(typed)) == meant, "\(typed)")
        }
        let spanish = Self.corrector(Self.spanish)
        for (typed, meant) in [("espanol", "español"), ("tambien", "también"), ("manana", "mañana"), ("nino", "niño")] {
            #expect(spanish.correction(for: Self.typed(typed)) == meant, "\(typed)")
        }
        #expect(spanish.correction(for: Self.typed("Espanol")) == "Español")
    }

    @Test func aRealWordTypedRightStaysAndTheBarOffersItsTwin() {
        let german = Self.corrector(Self.german)
        #expect(german.correction(for: Self.typed("schon")) == nil)
        #expect(Self.german.isWord("schön"))
        let spanish = Self.corrector(Self.spanish)
        for word in ["esta", "como", "si"] {
            #expect(spanish.correction(for: Self.typed(word)) == nil, "\(word)")
        }
        let bar = spanish.suggestions(for: Self.typed("esta"), correcting: true, guessing: true).map(\.text)
        #expect(bar.first == "esta")
        #expect(bar.contains("está"), "\(bar)")
    }

    /// Words drawn by how often they're written, each typed on the keys that hold its letters with taps spread a
    /// quarter key around their centers, then a space.
    @Test(arguments: ["de", "es"]) func typesWithNoisyTaps(language: String) {
        let lexicon = language == "de" ? Self.german : Self.spanish
        let counts = Self.counts(language)
        let total = counts.reduce(0) { $0 + $1.count }
        var random = Random(seed: 2026)
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        engine.corrector = Self.corrector(lexicon)
        let document = TestDocument()
        var (words, keysRight, right, accented, restored) = (0, 0, 0, 0, 0)
        for _ in 0..<400 {
            var pick = random.unit() * total
            let word =
                counts.first {
                    pick -= $0.count
                    return pick < 0
                }?.word ?? counts[0].word
            let start = document.text.count
            var typed = ""
            for character in word {
                let key = Self.grid.key(holding: String(character).lowercased())!
                let frame = Self.grid.frame(of: key)!
                let (x, y) = (
                    frame.midX + random.gaussian() * 0.25 * (frame.width + 6),
                    frame.midY + random.gaussian() * 0.25 * (frame.height + 11)
                )
                guard let hit = engine.key(atX: x, y: y, in: Self.grid),
                    let label = Self.grid.rows[hit.row][hit.key].key.label, label != " "
                else { continue }
                typed += label
                engine.perform(.character(label), in: document, tap: Tap(x: x, y: y, key: label))
            }
            engine.perform(.space, in: document)
            let final = String(document.text.dropFirst(start)).trimmingCharacters(in: .whitespaces)
            words += 1
            if typed == word.map({ Self.grid.key(holding: String($0).lowercased())! }).joined() { keysRight += 1 }
            if final == word { right += 1 }
            if word.lowercased().contains(where: { !$0.isASCII }) {
                accented += 1
                if final == word { restored += 1 }
            }
        }
        let share = { (count: Int, of: Int) in Double(count) / Double(max(of, 1)) }
        print(
            "LANGUAGE \(language) words=\(words) keysRight=\(share(keysRight, words)) right=\(share(right, words)) accented=\(accented) restored=\(share(restored, accented))"
        )
        #expect(share(right, words) > 0.9)
        #expect(share(restored, accented) > 0.8)
    }
}
