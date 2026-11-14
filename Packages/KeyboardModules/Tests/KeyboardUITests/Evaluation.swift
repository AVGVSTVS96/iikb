import Foundation
import KeyboardCore
import KeyboardEnglish
import Testing

/// Types the MacKenzie & Soukoreff phrase set through `TypingEngine` with simulated taps and reports word accuracy.
///
/// Three keyboards: (a) nearest-key hit-testing + `UITextChecker` (the old default), (b) iikb's decoder with the touch
/// model held at its prior, (c) the same decoder learning from every word it commits.
@MainActor
struct Evaluation {
    static let width = 402.0
    static let noiseLevels = [0.0, 0.15, 0.25, 0.35]

    enum Keyboard: String, CaseIterable {
        case baseline, decoder, learning

        /// The baseline needs `UITextChecker`, so off Apple's platforms (scripts/eval on Linux) only iikb's two run.
        static var scored: [Keyboard] {
            #if canImport(UIKit)
                allCases
            #else
                [.decoder, .learning]
            #endif
        }
    }

    static func phrases(_ name: String = "phrases") throws -> [String] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { $0.lowercased() }
    }

    @Test func noise() throws {
        let phrases = try Self.phrases()
        for keyboard in Keyboard.scored {
            for noise in Self.noiseLevels {
                var user = SimulatedUser(width: Self.width, noise: noise, seed: 2026)
                var session = Session(keyboard, grid: user.grid)
                for phrase in phrases {
                    session.startPhrase()
                    for word in phrase.split(separator: " ") {
                        session.type(String(word), by: &user, tappingSpace: false)
                    }
                }
                print("EVAL noise=\(noise) keyboard=\(keyboard.rawValue) \(session.score)")
            }
        }
    }

    /// Each other language typed the same way, from its own phrases (Common Voice's, `phrases.<id>.txt`) on its own
    /// layout, with its own words (`scripts/eval languages` downloads them into `LANGUAGES`) and no next-word network,
    /// since none is trained for it yet. A letter no key shows is tapped on the key it's under, and the lexicon is left
    /// to put it back ("espanol" → "español"). `LANGUAGE` picks one, so scripts/eval runs each in its own process.
    @Test(arguments: Language.all.filter { $0 != .english }.map(\.id)) func languages(_ id: String) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let folder = environment["LANGUAGES"], environment["LANGUAGE"] ?? id == id else { return }
        let language = Language.named(id)
        let file = URL(fileURLWithPath: folder).appending(path: "\(language.id).lexicon")
        let lexicon = try #require(Lexicon(bytes: [UInt8](Data(contentsOf: file))))
        let phrases = try Self.phrases("phrases.\(language.id)")
        var context = LayoutContext(device: .phone, layer: .letters)
        context.language = language
        context.letters = language.layout(nil)
        for keyboard in Keyboard.scored where keyboard != .baseline {
            for noise in Self.noiseLevels {
                var user = SimulatedUser(width: Self.width, noise: noise, seed: 2026, context: context)
                var session = Session(keyboard, grid: user.grid, lexicon: lexicon)
                for phrase in phrases {
                    session.startPhrase()
                    for word in phrase.split(separator: " ") {
                        session.type(String(word), by: &user, tappingSpace: false)
                    }
                }
                print(
                    "EVAL language=\(language.id) layout=\(context.letters.id) noise=\(noise) keyboard=\(keyboard.rawValue) \(session.score)"
                )
            }
        }
    }

    /// Main-thread cost per keystroke of what the extension runs for one key: hit-testing on touch down, the key on
    /// touch up, and the document refresh the host's `textDidChange` triggers.
    @Test func latency() throws {
        let phrases = try Self.phrases().prefix(100)
        var user = SimulatedUser(width: Self.width, noise: 0.2, seed: 2026)
        var session = Session(.learning, grid: user.grid)
        var down: [Duration] = []
        var letters: [Duration] = []
        var spaces: [Duration] = []
        var changed: [Duration] = []
        let clock = ContinuousClock()
        for phrase in phrases {
            session.startPhrase()
            for character in phrase + " " {
                let (x, y) = user.tap(character)
                var hit: (row: Int, key: Int)?
                down.append(clock.measure { hit = session.engine.key(atX: x, y: y, in: session.grid) })
                guard let hit, let label = session.grid.rows[hit.row][hit.key].key.label else { continue }
                let up = clock.measure {
                    session.engine.perform(
                        label == " " ? .space : .character(label), in: session.document,
                        tap: Tap(x: x, y: y, key: label))
                }
                if label == " " { spaces.append(up) } else { letters.append(up) }
                changed.append(clock.measure { session.engine.documentChanged(session.document) })
            }
        }
        func summary(_ name: String, _ samples: [Duration]) -> String {
            let ms = samples.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1000 }
                .sorted()
            let at = { (q: Double) in String(format: "%.2f", ms[min(ms.count - 1, Int(Double(ms.count) * q))]) }
            return "\(name) median=\(at(0.5)) p95=\(at(0.95)) p99=\(at(0.99)) max=\(at(1))"
        }
        print(
            "EVAL latency ms keys=\(down.count) \(summary("down", down)) | \(summary("letter up", letters)) | \(summary("space up", spaces)) | \(summary("textDidChange", changed))"
        )
    }

    /// The suggestion bar before each word: how often the word you type next is one of the three it shows, and how
    /// often it's the first. Each corpus is typed once by a new user (memory cleared every phrase) and once by a user
    /// whose memory keeps every phrase before it. `chat.txt` is one sentence from each of 1,000 user turns in Google's
    /// Taskmaster-1 self-dialogs (CC BY 4.0, github.com/google-research-datasets/Taskmaster).
    @Test func predictions() throws {
        for corpus in ["phrases", "chat"] {
            let url = try #require(Bundle.module.url(forResource: corpus, withExtension: "txt"))
            let phrases = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            for learning in [false, true] {
                var prediction = Prediction()
                for phrase in phrases {
                    if !learning { prediction.engine.corrector?.changeMemory { $0 = TypingMemory() } }
                    prediction.type(phrase.split(separator: " ").map(String.init))
                }
                print("EVAL predict corpus=\(corpus) user=\(learning ? "learning" : "new") \(prediction.summary)")
            }
        }
    }

    /// The bar's emoji: the share of each corpus's words that find any once typed. Which emoji they find is checked
    /// in `EnglishEmojiTests`.
    @Test func emoji() throws {
        for corpus in ["phrases", "chat"] {
            let url = try #require(Bundle.module.url(forResource: corpus, withExtension: "txt"))
            let words = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isWhitespace)
                .map { String($0.filter { $0.isLetter || $0.isNumber || $0 == "'" }) }.filter { !$0.isEmpty }
            let found = words.filter { !EmojiCatalog.english.suggestions(for: $0, history: EmojiHistory()).isEmpty }
            print(
                "EVAL emoji corpus=\(corpus) words=\(words.count) withEmoji=\(String(format: "%.1f", 100.0 * Double(found.count) / Double(words.count)))%"
            )
        }
    }

    /// A thumb that misses the space bar between two words and lands on the row above it ("great day" typed
    /// "greatvday"): each phrase is typed up to a word pair, the pair with the space's tap drawn wider around the space
    /// bar until it lands on a letter. Counts the taps the key map already reads as the space, and of those it reads as a letter, how
    /// often the bar offers the pair, and the pairs whose words have a typo of their own.
    @Test func missedSpaces() throws {
        let phrases = try Self.phrases()
        for (spaces, skipped) in [(1, false), (2, false), (3, false), (1, true), (2, true)] {
            let seed = UInt64(spaces - 1) * 1000 + (skipped ? 10000 : 0)
            var user = SimulatedUser(width: Self.width, noise: 0.25, seed: 2027 + seed)
            var thumb = SimulatedUser(width: Self.width, noise: 0.4, seed: 2028 + seed)
            var random = SplitMix64(seed: 2029 + seed)
            var runs = 0
            var spaced = 0
            var shown = 0
            var first = 0
            var mistyped = 0
            for phrase in phrases {
                let words = phrase.split(separator: " ").map(String.init)
                guard words.count > spaces else { continue }
                let pick = Int(random.next() % UInt64(words.count - spaces))
                var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
                let corrector = Corrector(source: Lexicon.english, network: .english)
                corrector.grid = user.grid
                engine.corrector = corrector
                let document = Document()
                engine.suggestionsChanged()
                func tap(_ character: Character) -> String? {
                    let (x, y) = user.tap(character)
                    return tap(x, y)
                }
                func tap(_ x: Double, _ y: Double) -> String? {
                    guard let hit = engine.key(atX: x, y: y, in: user.grid),
                        let label = user.grid.rows[hit.row][hit.key].key.label
                    else { return nil }
                    engine.perform(
                        label == " " ? .space : .character(label), in: document, tap: Tap(x: x, y: y, key: label))
                    return label
                }
                for word in words[..<pick] {
                    for character in word + " " { _ = tap(character) }
                }
                let run = words[pick...(pick + spaces)]
                var landed: [String?] = []
                var typo = false
                for (index, word) in run.enumerated() {
                    if index > 0, skipped {
                        landed.append(nil)
                    } else if index > 0 {
                        var space: (Double, Double)?
                        for _ in 0..<500 {
                            let point = thumb.tap(" ")
                            if let label = user.grid.key(atX: point.0, y: point.1)?.label, label.count == 1,
                                label.first!.isLetter
                            {
                                space = point
                                break
                            }
                        }
                        guard let space else { break }
                        landed.append(tap(space.0, space.1))
                    }
                    var typed = ""
                    for character in word { typed += tap(character) ?? "" }
                    if typed != word { typo = true }
                }
                guard landed.count == spaces else { continue }
                let bar = engine.suggestions.map { $0.text.lowercased() }
                runs += 1
                if typo { mistyped += 1 }
                if landed.contains(" ") {
                    spaced += 1
                } else if bar.contains(run.joined(separator: " ")) {
                    shown += 1
                    if bar.dropFirst().first == run.joined(separator: " ") { first += 1 }
                }
            }
            let share = { (count: Int, of: Int) in String(format: "%.1f%%", 100.0 * Double(count) / Double(max(of, 1)))
            }
            print(
                "EVAL missedSpaces spaces=\(spaces)\(skipped ? " untyped" : "") keyboard=decoder runs=\(runs) withTypo=\(mistyped) aSpaceReadAsSpace=\(share(spaced, runs)) allAsLetters: shown=\(share(shown, runs - spaced)) firstAlternative=\(share(first, runs - spaced))"
            )
        }
    }

    /// A thumb that means the space on the open Duo's split keyboard in an Instagram field, whose @ and # sit between
    /// the space bars, and goes where the bars are in every other field: each phrase is typed up to a word pair by
    /// someone who has typed the corpus, the pair with the space's tap drawn around either bar (spread as a key's taps
    /// are, the bar's width for its pitch) until it lands on @ or #. Counts the pairs the space after them reads apart,
    /// of all and of those with no typo of their own, and, with that tap aimed at the @ key instead, the pairs left as
    /// typed.
    @Test func strayKeys() throws {
        let phrases = try Self.phrases()
        var settings = KeyboardSettings()
        settings.split = true
        let screen = Duo.Screen.openLandscape.size
        let field = KeyboardGeometry(
            LayoutContext(device: .phone, layer: .letters, kind: .twitter, screen: screen, settings: settings),
            screen: screen, style: .ios27
        ).grid
        var user = SimulatedUser(grid: field, noise: 0.25, seed: 2031)
        var thumb = SplitMix64(seed: 2032)
        let bars = field.rows.last!.map(\.frame).filter { field.key(atX: $0.midX, y: $0.midY)?.action == .space }
        var random = SplitMix64(seed: 2033)
        var typed = TypingMemory()
        for phrase in phrases {
            var previous = ""
            for word in phrase.split(separator: " ").map(String.init) {
                typed.record(word, after: previous)
                previous = word
            }
        }
        var runs = 0
        var mistyped = 0
        var read = 0
        var readSpelled = 0
        var meant = 0
        var kept = 0
        for phrase in phrases {
            let words = phrase.split(separator: " ").map(String.init)
            guard words.count > 1 else { continue }
            let pick = Int(random.next() % UInt64(words.count - 1))
            let pair = words[pick] + " " + words[pick + 1]
            /// The text after the pair is typed with `stray` where its space belonged, and whether a word had a typo.
            func type(_ stray: (x: Double, y: Double), _ key: String) -> (text: String, typo: Bool) {
                var engine = TypingEngine(traits: InputTraits(kind: .twitter, autocapitalization: .none))
                let corrector = Corrector(source: Lexicon.english, network: .english)
                corrector.changeMemory { $0 = typed }
                engine.corrector = corrector
                engine.use(field)
                let document = Document()
                engine.suggestionsChanged()
                var typo = false
                func tap(_ x: Double, _ y: Double) -> String {
                    let hit = engine.key(atX: x, y: y, in: field)!
                    let key = field.rows[hit.row][hit.key].key
                    guard let text = key.action == .space ? " " : key.text(shifted: false) else { return "" }
                    engine.handle(.type(key, Tap(x: x, y: y, key: text)), in: document)
                    return text
                }
                func space() { _ = tap(field.frame(of: " ")!.midX, field.frame(of: " ")!.midY) }
                for word in words[..<pick] {
                    for character in word {
                        _ = tap(field.frame(of: String(character))!.midX, field.frame(of: String(character))!.midY)
                    }
                    space()
                }
                for (index, word) in words[pick...(pick + 1)].enumerated() {
                    if index > 0 {
                        engine.handle(.type(Key(.character(key)), Tap(x: stray.x, y: stray.y, key: key)), in: document)
                    }
                    var spelled = ""
                    for character in word {
                        let point = user.tap(character)
                        spelled += tap(point.0, point.1)
                    }
                    if spelled != word { typo = true }
                }
                space()
                return (document.text, typo)
            }
            func landing(_ aim: () -> (Double, Double)) -> (point: (x: Double, y: Double), key: String)? {
                for _ in 0..<500 {
                    let point = aim()
                    if let key = field.key(atX: point.0, y: point.1)?.text(shifted: false), key == "@" || key == "#" {
                        return (point, key)
                    }
                }
                return nil
            }
            guard
                let missed = landing({
                    let bar = bars[Int(thumb.next() % UInt64(bars.count))]
                    return (
                        bar.midX + thumb.gaussian() * 0.4 * bar.width,
                        bar.midY + thumb.gaussian() * 0.4 * (bar.height + 11)
                    )
                })
            else { continue }
            let result = type(missed.point, missed.key)
            runs += 1
            if result.typo { mistyped += 1 }
            if result.text.hasSuffix(pair + " ") {
                read += 1
                if !result.typo { readSpelled += 1 }
            }
            let at = field.frame(of: "@")!
            guard
                let aimed = landing({
                    (at.midX + random.gaussian() * 0.25 * at.width, at.midY + random.gaussian() * 0.25 * at.height)
                })
            else { continue }
            let deliberate = type(aimed.point, aimed.key)
            if !deliberate.typo {
                meant += 1
                if deliberate.text.hasSuffix(words[pick] + aimed.key + words[pick + 1] + " ") { kept += 1 }
            }
        }
        let share = { (count: Int, of: Int) in String(format: "%.1f%%", 100.0 * Double(count) / Double(max(of, 1))) }
        print(
            "EVAL strayKeys keyboard=decoder runs=\(runs) withTypo=\(mistyped) readAsSpace=\(share(read, runs)) spelledRight: readAsSpace=\(share(readSpelled, runs - mistyped)) meantTheKey: kept=\(share(kept, meant))"
        )
    }

    @Test func biasedThumbs() throws {
        let phrases = try Self.phrases()
        let block = 500
        for keyboard in Keyboard.scored {
            var user = SimulatedUser(width: Self.width, noise: 0.2, seed: 7, bias: SimulatedUser.thumbs)
            var session = Session(keyboard, grid: user.grid)
            var curve: [String] = []
            for _ in 0..<2 {
                for phrase in phrases {
                    session.startPhrase()
                    for word in phrase.split(separator: " ") {
                        session.type(String(word), by: &user, tappingSpace: true)
                        if session.score.words % block == 0 {
                            curve.append(session.window.summary)
                            session.window = Score()
                        }
                    }
                }
            }
            print("EVAL thumbs keyboard=\(keyboard.rawValue) total: \(session.score)")
            print(
                "EVAL thumbs keyboard=\(keyboard.rawValue) per \(block) words (raw/final): \(curve.joined(separator: " "))"
            )
            if keyboard == .learning, let corrector = session.engine.corrector {
                let centers = ["m", "b", "o", "e"].map { label in
                    let c = corrector.memory.touches.center(of: label, on: user.grid)
                    return "\(label)=(\(String(format: "%+.2f", c.x)),\(String(format: "%+.2f", c.y)))"
                }
                print("EVAL thumbs learned centers: \(centers.joined(separator: " "))")
            }
        }
    }

    /// A user who has typed the corpus with `thumbs`, then changes how they hold the phone: every tap lands lower and
    /// to the right, o and e swing to the other side, b and m drop further. Prints the corpus typed after the change,
    /// with the first 500 words per 100.
    @Test func aimShift() throws {
        let phrases = try Self.phrases()
        var user = SimulatedUser(width: Self.width, noise: 0.2, seed: 11, bias: SimulatedUser.thumbs)
        var session = Session(.learning, grid: user.grid)
        for phrase in phrases {
            session.startPhrase()
            for word in phrase.split(separator: " ") { session.type(String(word), by: &user, tappingSpace: true) }
        }
        user = SimulatedUser(width: Self.width, noise: 0.2, seed: 12, bias: SimulatedUser.shifted)
        session.score = Score()
        session.window = Score()
        var curve: [String] = []
        for phrase in phrases {
            session.startPhrase()
            for word in phrase.split(separator: " ") {
                session.type(String(word), by: &user, tappingSpace: true)
                let words = session.score.words
                if words <= 500 ? words % 100 == 0 : words % 500 == 0 {
                    curve.append(session.window.summary)
                    session.window = Score()
                }
            }
        }
        print("EVAL aimShift keyboard=learning after: \(session.score)")
        print(
            "EVAL aimShift keyboard=learning per 100 words to 500, then per 500 (raw/final): \(curve.joined(separator: " "))"
        )
    }
}

@MainActor
struct Session {
    let keyboard: Evaluation.Keyboard
    let grid: KeyGrid
    var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
    var document = Document()
    var score = Score()
    var window = Score()

    /// With `lexicon`, another language's words and no next-word network.
    init(_ keyboard: Evaluation.Keyboard, grid: KeyGrid, lexicon: Lexicon? = nil) {
        self.keyboard = keyboard
        self.grid = grid
        #if canImport(UIKit)
            let source: any CandidateSource =
                keyboard == .baseline ? TextCheckerSource(language: "en-US") : lexicon ?? Lexicon.english
        #else
            let source: any CandidateSource = lexicon ?? Lexicon.english
        #endif
        let corrector = Corrector(source: source, network: keyboard == .baseline || lexicon != nil ? nil : .english)
        corrector.grid = grid
        engine.corrector = corrector
    }

    mutating func startPhrase() {
        engine.endSession()
        let corrector = engine.corrector
        engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        engine.corrector = corrector
        document = Document()
        engine.suggestionsChanged()
    }

    mutating func type(_ word: String, by user: inout SimulatedUser, tappingSpace: Bool) {
        let start = document.text.count
        let predictions = engine.suggestions.map { $0.text.lowercased() }
        var typed = ""
        for character in word + (tappingSpace ? " " : "") where user.canTap(character) {
            let (x, y) = user.tap(character)
            let hit = keyboard == .baseline ? grid.index(atX: x, y: y) : engine.key(atX: x, y: y, in: grid)
            guard let hit, let label = grid.rows[hit.row][hit.key].key.label, tappingSpace || label != " " else {
                continue
            }
            if character != " " { typed += label }
            if character == " " { shown = engine.suggestions.map { $0.text.lowercased() } }
            engine.perform(label == " " ? .space : .character(label), in: document, tap: Tap(x: x, y: y, key: label))
        }
        if !tappingSpace {
            shown = engine.suggestions.map { $0.text.lowercased() }
            engine.perform(.space, in: document)
        }
        if keyboard == .decoder {
            engine.endSession()
            engine.corrector?.changeMemory { $0.touches = TouchModel() }
        }
        let final = String(document.text.dropFirst(start)).trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "’", with: "'")
        score.add(word: word, typed: typed, final: final, shown: shown, predictions: predictions)
        window.add(word: word, typed: typed, final: final, shown: shown, predictions: predictions)
    }

    private var shown: [String] = []
}

@MainActor
struct Prediction {
    var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
    var words = 0, first = 0, topThree = 0

    init() {
        engine.corrector = Corrector(source: Lexicon.english, network: .english)
    }

    mutating func type(_ phrase: [String]) {
        engine.endSession()
        let corrector = engine.corrector
        engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        engine.corrector = corrector
        let document = Document()
        engine.suggestionsChanged()
        for word in phrase {
            let shown = engine.suggestions.map { $0.text.lowercased() }
            words += 1
            if shown.first == word.lowercased() { first += 1 }
            if shown.contains(word.lowercased()) { topThree += 1 }
            for character in word { engine.perform(.character(String(character)), in: document) }
            engine.perform(.space, in: document)
        }
    }

    var summary: String {
        func percent(_ count: Int) -> String { String(format: "%.1f%%", Double(count) * 100 / Double(max(words, 1))) }
        return "words=\(words) top1=\(percent(first)) top3=\(percent(topThree))"
    }
}

@MainActor
struct SimulatedUser {
    let grid: KeyGrid
    let noise: Double
    let bias: [Character: (x: Double, y: Double)]
    var random: SplitMix64

    /// Offsets in key pitches: m drifts toward n, b toward the space bar, o toward i, and every tap lands a bit low.
    static let thumbs: [Character: (x: Double, y: Double)] = [
        "m": (-0.4, 0.1), "b": (0, 0.55), "o": (-0.45, 0.1), "*": (0, 0.1),
    ]
    static let shifted: [Character: (x: Double, y: Double)] = [
        "m": (-0.4, 0.4), "b": (0, 0.7), "o": (0.4, 0.3), "e": (-0.45, 0.3), "*": (0.1, 0.3),
    ]

    init(
        width: Double, noise: Double, seed: UInt64, bias: [Character: (x: Double, y: Double)] = [:],
        context: LayoutContext = LayoutContext(device: .phone, layer: .letters)
    ) {
        let layout = Layouts.layout(for: context)
        self.init(
            grid: KeyGrid(layout, width: width, metrics: KeyboardMetrics.phone(width: width).grid, signature: "eval"),
            noise: noise, seed: seed, bias: bias)
    }

    init(grid: KeyGrid, noise: Double, seed: UInt64, bias: [Character: (x: Double, y: Double)] = [:]) {
        self.grid = grid
        self.noise = noise
        self.bias = bias
        random = SplitMix64(seed: seed)
    }

    /// Whether a key holds it, on its face or under its long-press; an apostrophe on a layout without one goes untyped.
    func canTap(_ character: Character) -> Bool {
        grid.key(holding: String(character)) != nil
    }

    /// Where a tap for `character` lands: on the key that holds it, around its middle.
    mutating func tap(_ character: Character) -> (Double, Double) {
        let frame = grid.frame(of: grid.key(holding: String(character))!)!
        let pitchX = character == " " ? 45.0 : frame.width + 6
        let pitchY = frame.height + 11
        let offset = bias[character] ?? bias["*"] ?? (0, 0)
        return (
            frame.midX + (offset.x + random.gaussian() * noise) * pitchX,
            frame.midY + (offset.y + random.gaussian() * noise) * pitchY
        )
    }
}

struct Score: CustomStringConvertible {
    var words = 0, raw = 0, corrected = 0, topThree = 0, predicted = 0, fixed = 0, broken = 0
    var brokenWords: [String] = []

    mutating func add(word: String, typed: String, final: String, shown: [String], predictions: [String]) {
        words += 1
        if predictions.contains(word) { predicted += 1 }
        if typed == word { raw += 1 }
        if final == word { corrected += 1 }
        if shown.contains(word) { topThree += 1 }
        if typed != word, final == word { fixed += 1 }
        if typed == word, final != word {
            broken += 1
            brokenWords.append("\(word)→\(final)")
        }
    }

    private func percent(_ count: Int) -> String {
        String(format: "%.1f%%", Double(count) * 100 / Double(max(words, 1)))
    }

    var summary: String { "\(percent(raw))/\(percent(corrected))" }

    var description: String {
        "words=\(words) raw=\(percent(raw)) autocorrect=\(percent(corrected)) top3=\(percent(topThree)) next3=\(percent(predicted)) fixed=\(fixed) broken=\(broken) \(brokenWords.prefix(8))"
    }
}

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func gaussian() -> Double {
        sqrt(-2 * log(max(uniform(), .leastNormalMagnitude))) * cos(2 * .pi * uniform())
    }
}

final class Document: TextDocument {
    private(set) var text = ""

    var textBeforeInput: String? { text }
    var textAfterInput: String? { nil }
    func insert(_ value: String) { text += value }
    func deleteBackward(_ count: Int) { text.removeLast(min(count, text.count)) }
    func moveCursor(by offset: Int) {}
}
