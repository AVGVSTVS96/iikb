import Foundation
import Testing

@testable import KeyboardCore

/// scripts/barbench: the bar on someone's own typing it never learned from. The lines in BAR_LINES are typed in order
/// through the engine with Auto-Correction off, the first 90% to learn from and the last 10% scored, the same split
/// scripts/personal holds out, so BAR_NETWORK (that person's network) never saw them either. Before each scored word it
/// counts whether the bar shows it, and first, and after its first letter whether the bar shows it. Typing is private,
/// so only the counts print; BAR_HITS names files that get each check's hit or miss, to compare two builds word by word.
struct BarBenchTests {
    private static let environment = ProcessInfo.processInfo.environment
    private static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/KeyboardEnglish/Resources")

    private static func bytes(_ path: String) -> [UInt8] { [UInt8](FileManager.default.contents(atPath: path)!) }

    private struct Score {
        var words = 0
        var next = 0
        var first = 0
        var letter = 0
        var letterWords = 0

        var summary: String {
            func pct(_ n: Int, _ d: Int) -> String { String(format: "%.2f%%", 100 * Double(n) / Double(max(d, 1))) }
            return "words=\(words) next3=\(pct(next, words)) next1=\(pct(first, words)) "
                + "letter=\(pct(letter, letterWords)) of \(letterWords)"
        }
    }

    @Test(.enabled(if: environment["BAR_LINES"] != nil), arguments: ["shipped", "personal"])
    func heldOut(_ condition: String) throws {
        if condition == "personal", Self.environment["BAR_NETWORK"] == nil { return }
        let lexicon = Lexicon(bytes: Bytes(Self.bytes(Self.resources.appending(path: "en.lexicon").path)))!
        let personal = condition == "personal"
        let network = Network(
            bytes: Self.bytes(
                personal ? Self.environment["BAR_NETWORK"]! : Self.resources.appending(path: "en.network").path),
            personal: personal)!
        let lines = try String(contentsOfFile: Self.environment["BAR_LINES"]!, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        let held = max(1, lines.count / 10)
        let corrector = Corrector(source: lexicon, network: network)
        var engine = TypingEngine()
        engine.corrector = corrector
        engine.settings.autoCorrection = false
        engine.defersSuggestions = true
        var score = Score()
        var marks = Self.environment["BAR_HITS"].map { _ in [String]() }
        for (index, line) in lines.enumerated() {
            let scored = index >= lines.count - held
            let document = TestDocument()
            engine.documentChanged(document)
            var word = ""
            let characters = Array(line)
            for (at, character) in characters.enumerated() {
                let key = String(character)
                if scored, word.isEmpty, character.isLetter, at == 0 || characters[at - 1] == " " {
                    let target = String(characters[at...].prefix { $0.isLetter || $0 == "'" || $0 == "’" })
                        .lowercased().replacingOccurrences(of: "’", with: "'")
                    let shown = Self.bar(&engine)
                    score.words += 1
                    let isNext = shown.contains(target)
                    if isNext { score.next += 1 }
                    if shown.first == target { score.first += 1 }
                    word = target
                    marks?.append(isNext ? "1" : "0")
                }
                let center = corrector.grid.frame(of: key).map { Tap(x: $0.midX, y: $0.midY, key: key) }
                engine.perform(character == " " ? .space : .character(key), in: document, tap: center)
                if !word.isEmpty {
                    if word.count > 1 {
                        score.letterWords += 1
                        let isShown = Self.bar(&engine).contains(word)
                        if isShown { score.letter += 1 }
                        marks?.append(isShown ? "1" : "0")
                    }
                    word = ""
                }
            }
        }
        print("BAR \(condition) \(score.summary)")
        if let path = Self.environment["BAR_HITS"], let marks {
            try (marks.joined() + "\n").write(toFile: path + "." + condition, atomically: true, encoding: .utf8)
        }
    }

    /// The bar's words as the gate reads them: the first three, two beside an emoji.
    private static func bar(_ engine: inout TypingEngine) -> [String] {
        if var job = engine.suggestionJob() {
            job.run()
            engine.finish(job)
        }
        return engine.suggestions.prefix(engine.emojiSuggestions.isEmpty ? 3 : 2)
            .filter { $0.kind != .literal }
            .map { $0.text.lowercased().replacingOccurrences(of: "’", with: "'") }
    }
}
