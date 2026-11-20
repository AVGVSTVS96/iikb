import Foundation
import KeyboardCore
import KeyboardEnglish
import Testing

/// The bar on many people's own writing, as `scripts/barbench` scores it on one: each person's messages
/// (`people.txt`, from `scripts/realtyping.py`) typed in the order they wrote them through the engine with
/// Auto-Correction off, each key tapped at its center, and the bar scored on their last 10%: before each word, is it
/// among the bar's words and first, and after its first letter, is it among them. `new` types only those messages, as
/// someone who just installed iikb; `learned` types everything they wrote before them first, so the gap between the two
/// is what learning a person's words is worth, and a model that trusts their typing too much shows as `learned`
/// falling behind. At most `scoredWords` words of each person count, so the prolific don't outweigh the rest, and a
/// learned user has typed their latest `historyWords` words before them, which keeps a run to minutes. `PEOPLE` picks
/// one source, split and user ("enron dev learned"), so scripts/eval runs each in its own process.
@MainActor
extension Evaluation {
    static let scoredWords = 300
    static let historyWords = 10_000

    @Test func people() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let shard = environment["PEOPLE"]?.split(separator: " ").map(String.init), shard.count == 3,
            let lines = try Self.real("people.txt")
        else { return }
        let (source, split, learned) = (shard[0], shard[1], shard[2] == "learned")
        let grid = SimulatedUser(width: Self.width, noise: 0, seed: 0).grid
        let people = Dictionary(grouping: lines.filter { $0[0] == source && $0[1] == split }, by: { $0[2] })
            .mapValues { $0.map { $0[3] } }
        var score = BarScore()
        for person in people.keys.sorted() {
            let messages = people[person]!
            let held = messages.count - max(1, messages.count / 10)
            var typist = BarTypist(grid: grid)
            var budget = 0
            if learned {
                for message in Self.latest(messages[..<held], words: Self.historyWords) {
                    typist.type(message, into: &score, budget: &budget)
                }
            }
            budget = Self.scoredWords
            for message in messages[held...] where budget > 0 {
                typist.type(message, into: &score, budget: &budget)
            }
        }
        print("EVAL people source=\(source) split=\(split) people=\(people.count) user=\(shard[2]) \(score)")
    }

    /// The last messages of `messages` that hold `words` words between them.
    static func latest(_ messages: ArraySlice<String>, words: Int) -> ArraySlice<String> {
        var count = 0
        var start = messages.endIndex
        while start > messages.startIndex, count < words {
            start -= 1
            count += messages[start].split(separator: " ").count
        }
        return messages[start...]
    }
}

struct BarScore: CustomStringConvertible {
    var words = 0, next = 0, first = 0, letter = 0, letterWords = 0

    var description: String {
        func percent(_ n: Int, _ d: Int) -> String { String(format: "%.1f%%", 100 * Double(n) / Double(max(d, 1))) }
        return
            "words=\(words) next3=\(percent(next, words)) next1=\(percent(first, words)) letter=\(percent(letter, letterWords))"
    }
}

/// Types a message into a new field with Auto-Correction off, each key tapped at its center, scoring the bar on its
/// words while `budget` lasts, one word at a time.
@MainActor
struct BarTypist {
    let corrector: Corrector
    var engine = TypingEngine()

    init(grid: KeyGrid) {
        corrector = Corrector(source: Lexicon.english, network: .english)
        corrector.grid = grid
        engine.corrector = corrector
        engine.settings.autoCorrection = false
        engine.defersSuggestions = true
    }

    mutating func type(_ message: String, into score: inout BarScore, budget: inout Int) {
        let document = Document()
        engine.documentChanged(document)
        let characters = Array(message)
        var word = ""
        for (at, character) in characters.enumerated() {
            if budget > 0, word.isEmpty, character.isLetter, at == 0 || characters[at - 1] == " " {
                word = String(characters[at...].prefix { $0.isLetter || $0 == "'" || $0 == "’" })
                    .lowercased().replacingOccurrences(of: "’", with: "'")
                let shown = bar()
                score.words += 1
                budget -= 1
                if shown.contains(word) { score.next += 1 }
                if shown.first == word { score.first += 1 }
            }
            let key = String(character)
            let center = corrector.grid.frame(of: key).map { Tap(x: $0.midX, y: $0.midY, key: key) }
            engine.perform(character == " " ? .space : .character(key), in: document, tap: center)
            if !word.isEmpty {
                if word.count > 1 {
                    score.letterWords += 1
                    if bar().contains(word) { score.letter += 1 }
                }
                word = ""
            }
        }
    }

    /// The bar's words as scripts/gate reads them: the first three, two beside an emoji.
    private mutating func bar() -> [String] {
        if var job = engine.suggestionJob() {
            job.run()
            engine.finish(job)
        }
        return engine.suggestions.prefix(engine.emojiSuggestions.isEmpty ? 3 : 2)
            .filter { $0.kind != .literal }
            .map { $0.text.lowercased().replacingOccurrences(of: "’", with: "'") }
    }
}
