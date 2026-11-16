import Foundation
import KeyboardCore
import KeyboardEnglish
import Testing

/// Autocorrect on real people's typing instead of `SimulatedUser`'s: `scripts/realtyping.py` downloads it into
/// `REAL_DATA` and writes the three files read here (its header says what each holds and where it's from). dev is what
/// a change is tuned against; test is people kept out of that, and the number to report.
@MainActor
extension Evaluation {
    static func real(_ name: String) throws -> [[String]]? {
        guard let folder = ProcessInfo.processInfo.environment["REAL_DATA"] else { return nil }
        let url = URL(fileURLWithPath: folder).appending(path: name)
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    /// Real taps replayed on iikb's iPhone 17 grid, each where it landed on the keyboard it was typed on, measured from
    /// the q key's center in key pitches, and a space's from the space bar's. Each person types on a keyboard of their own, so the learning one learns them.
    /// Each word is scored as its space leaves it, and each phrase by its words' error rate once typed, after any later
    /// space read a tap again (a space tap on v is a missed space only the next word shows).
    @Test func realTaps() throws {
        guard let lines = try Self.real("taps.txt") else { return }
        let grid = SimulatedUser(width: Self.width, noise: 0, seed: 0).grid
        let q = grid.frame(of: "q")!
        let w = grid.frame(of: "w")!
        let a = grid.frame(of: "a")!
        let bar = grid.frame(of: " ")!
        func point(_ text: Substring) -> (Double, Double) {
            let pitches = text.split(separator: ",").map { Double($0)! }
            return (q.midX + pitches[0] * (w.midX - q.midX), q.midY + pitches[1] * (a.midY - q.midY))
        }
        func space(_ text: Substring) -> (Double, Double) {
            let offset = text.split(separator: ",").map { Double($0)! }
            return (bar.midX + offset[0] * bar.width / 2, bar.midY + offset[1] * (a.midY - q.midY))
        }
        for source in ["tsi", "vertanen"] {
            let people = Dictionary(grouping: lines.filter { $0[0] == source }, by: { $0[1] })
            for keyboard in Keyboard.scored where keyboard != .baseline {
                var score = Score()
                var words = 0
                var wrong = 0
                for person in people.keys.sorted() {
                    var session = Session(keyboard, grid: grid)
                    for line in people[person]! {
                        session.startPhrase()
                        let meant = line[2].split(separator: " ").map(String.init)
                        for (word, taps) in zip(meant, line[3].split(separator: "|")) {
                            let parts = taps.split(separator: "/", omittingEmptySubsequences: false)
                            session.type(
                                word, taps: parts[0].split(separator: " ").map(point),
                                space: parts.count > 1 ? space(parts[1]) : nil)
                        }
                        words += meant.count
                        wrong += Tally.distance(
                            Self.plain(session.document.text[...]).split(separator: " ").map(String.init), meant)
                    }
                    score.add(session.score)
                }
                let phrases = String(format: "%.1f%%", 100.0 * Double(wrong) / Double(max(words, 1)))
                print(
                    "EVAL real=taps source=\(source) people=\(people.count) keyboard=\(keyboard.rawValue) phrasesWer=\(phrases) \(score)"
                )
            }
        }
    }

    /// Sentences typed on people's own phones with no autocorrect, typed again here a letter at a time with no taps to
    /// read, as a new user: how many words are wrong before and after, and which typos are fixed or correct words broken.
    @Test func realTypos() throws {
        guard let lines = try Self.real("typed.txt") else { return }
        for split in ["dev", "test"] {
            var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
            let corrector = Corrector(source: Lexicon.english, network: .english)
            var tally = Tally()
            for line in lines where line[0] == split {
                corrector.changeMemory { $0 = TypingMemory() }
                engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
                engine.corrector = corrector
                let document = Document()
                engine.suggestionsChanged()
                let typed = line[3].split(separator: " ").map(String.init)
                var out: [String] = []
                var bars: [[String]] = []
                for word in typed {
                    let start = document.text.count
                    for character in word { engine.perform(.character(String(character)), in: document) }
                    bars.append(engine.suggestions.map { Self.plain($0.text[...]) })
                    engine.perform(.space, in: document)
                    out.append(Self.plain(document.text.dropFirst(start)))
                }
                tally.add(
                    meant: line[2].split(separator: " ").map(String.init), typed: typed.map { $0.lowercased() },
                    out: out,
                    bars: bars)
            }
            print("EVAL real=typed split=\(split) \(tally)")
        }
    }

    /// Words a phone's own autocorrect changed (an iPhone's or an Android's), typed here after the same text, a letter at
    /// a time with no taps to read: how often the word that comes out is the one meant, here and on the phone, and how often
    /// iikb's bar offers it.
    @Test func realAutocorrect() throws {
        guard let lines = try Self.real("autocorrect.txt") else { return }
        for split in ["dev", "test"] {
            let corrector = Corrector(source: Lexicon.english, network: .english)
            var rows = 0
            var typedRight = 0
            var phoneRight = 0
            var right = 0
            var offered = 0
            var phoneBroke = 0
            var broke = 0
            var misses: [String] = []
            for line in lines where line[0] == split {
                let (before, word, phone, meant) = (line[1], line[2], line[3], line[4])
                corrector.changeMemory { $0 = TypingMemory() }
                var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
                engine.corrector = corrector
                let document = Document(before.isEmpty ? "" : before + " ")
                engine.documentChanged(document)
                engine.suggestionsChanged()
                let start = document.text.count
                for character in word { engine.perform(.character(String(character)), in: document) }
                if engine.suggestions.contains(where: { Self.plain($0.text[...]) == meant }) { offered += 1 }
                engine.perform(.space, in: document)
                let out = Self.plain(document.text.dropFirst(start))
                rows += 1
                if word.lowercased() == meant { typedRight += 1 }
                if phone == meant { phoneRight += 1 }
                if out == meant { right += 1 } else if misses.count < 8 { misses.append("\(word)→\(out) (\(meant))") }
                if word.lowercased() == meant, phone != meant { phoneBroke += 1 }
                if word.lowercased() == meant, out != meant { broke += 1 }
            }
            let share = { (count: Int) in String(format: "%.1f%%", 100.0 * Double(count) / Double(max(rows, 1))) }
            print(
                "EVAL real=phone split=\(split) words=\(rows) asMeant: typed=\(share(typedRight)) phone=\(share(phoneRight)) iikb=\(share(right)) inIikbsBar=\(share(offered)) brokeCorrect: phone=\(phoneBroke) iikb=\(broke) \(misses)"
            )
        }
    }

    static func plain(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "’", with: "'")
    }
}

/// Word error rate before and after, the typos fixed or offered in the bar, and correct words broken, with what was
/// typed lined up against what was meant word for word.
struct Tally: CustomStringConvertible {
    var sentences = 0, words = 0, typedErrors = 0, outErrors = 0, typos = 0, fixed = 0, offered = 0, correct = 0
    var broken = 0
    var brokenWords: [String] = []

    /// `bars` is what the bar showed as each typed word's last letter went in.
    mutating func add(meant: [String], typed: [String], out: [String], bars: [[String]]) {
        sentences += 1
        words += meant.count
        typedErrors += Self.distance(typed, meant)
        outErrors += Self.distance(out.flatMap { $0.split(separator: " ").map(String.init) }, meant)
        for (index, other) in Self.aligned(typed, meant) {
            guard let other else { continue }
            if typed[index] == other {
                correct += 1
                if out[index] != other {
                    broken += 1
                    brokenWords.append("\(other)→\(out[index])")
                }
            } else {
                typos += 1
                if out[index] == other { fixed += 1 }
                if bars[index].contains(other) { offered += 1 }
            }
        }
    }

    /// Word-level edit distance.
    static func distance(_ a: [String], _ b: [String]) -> Int {
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var next = [i + 1]
            for (j, y) in b.enumerated() { next.append(min(row[j + 1] + 1, next[j] + 1, row[j] + (x == y ? 0 : 1))) }
            row = next
        }
        return row[b.count]
    }

    /// Each typed word's partner in `meant` on a cheapest edit path (a substitution or a match), or nil.
    static func aligned(_ typed: [String], _ meant: [String]) -> [(Int, String?)] {
        let n = typed.count
        let m = meant.count
        var cost = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { cost[i][0] = i }
        for j in 0...m { cost[0][j] = j }
        for i in stride(from: 1, through: n, by: 1) {
            for j in stride(from: 1, through: m, by: 1) {
                cost[i][j] = min(
                    cost[i - 1][j] + 1, cost[i][j - 1] + 1, cost[i - 1][j - 1] + (typed[i - 1] == meant[j - 1] ? 0 : 1))
            }
        }
        var pairs: [(Int, String?)] = []
        var i = n
        var j = m
        while i > 0 {
            if j > 0, cost[i][j] == cost[i - 1][j - 1] + (typed[i - 1] == meant[j - 1] ? 0 : 1) {
                pairs.append((i - 1, meant[j - 1]))
                j -= 1
            } else if j > 0, cost[i][j] == cost[i][j - 1] + 1 {
                j -= 1
                continue
            } else {
                pairs.append((i - 1, nil))
            }
            i -= 1
        }
        return pairs.reversed()
    }

    private func percent(_ count: Int, of total: Int) -> String {
        String(format: "%.1f%%", 100.0 * Double(count) / Double(max(total, 1)))
    }

    var description: String {
        "sentences=\(sentences) words=\(words) wer: typed=\(percent(typedErrors, of: words)) autocorrected=\(percent(outErrors, of: words)) typos=\(typos) fixed=\(percent(fixed, of: typos)) inBar=\(percent(offered, of: typos)) broken=\(broken) of \(correct) \(brokenWords.prefix(8))"
    }
}
