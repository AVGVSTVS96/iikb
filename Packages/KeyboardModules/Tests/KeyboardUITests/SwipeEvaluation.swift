import Dispatch
import Foundation
import KeyboardEnglish
import Testing

@testable import KeyboardCore

/// How well swipes are read, on swipe.futo.org's test split (MIT; `scripts/swipe data` writes it to `SWIPE_DATA`): the
/// share of swipes whose word is the first, among the first three and among the first ten candidates, with iikb's own
/// lexicon and with the targets added to it as the technical report does, from the encoder alone and with the decoder.
private final class Slots<Value: Sendable>: @unchecked Sendable {
    let lock = NSLock()
    var values: [Value?]
    init(_ count: Int) { values = Array(repeating: nil, count: count) }
}

extension Evaluation {
    struct Swipes {
        struct Item {
            let word: String
            let path: [SwipePoint]
            var context = ""
        }

        let items: [Item]

        /// The same swipes as touches on `layout`'s keyboard: the dataset's coordinates are fractions of the letter keys' box.
        func placed(on layout: SwipeLayout) -> [Item] {
            items.map { item in
                Item(
                    word: item.word,
                    path: item.path.map {
                        SwipePoint(
                            x: layout.frame.x + $0.x * layout.frame.width,
                            y: layout.frame.y + $0.y * layout.frame.height, time: $0.time)
                    }, context: item.context)
            }
        }

        static var directory: URL {
            URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWIPE_DATA"] ?? "build/swipe")
        }

        static func exists(_ split: String) -> Bool {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(split).swipes").path)
        }

        init(items: [Item]) { self.items = items }

        /// The swipes whose word is letters and apostrophes, after trimming punctuation, of at least two letters: a–z's
        /// alone unless `anyLetters`.
        init(_ split: String, limit: Int = .max, anyLetters: Bool = false) throws {
            let data = [UInt8](try Data(contentsOf: Self.directory.appendingPathComponent("\(split).swipes")))
            func u32(_ at: Int) -> Int {
                Int(data[at]) | Int(data[at + 1]) << 8 | Int(data[at + 2]) << 16 | Int(data[at + 3]) << 24
            }
            var at = 8
            var items: [Item] = []
            let contexts =
                (try? String(contentsOf: Self.directory.appendingPathComponent("\(split).context"), encoding: .utf8))?
                .split(separator: "\n", omittingEmptySubsequences: false)
            for index in 0..<u32(4) where items.count < limit {
                let length = Int(data[at]) | Int(data[at + 1]) << 8
                let count = Int(data[at + 2]) | Int(data[at + 3]) << 8
                let raw = String(decoding: data[at + 4..<at + 4 + length], as: UTF8.self)
                at += 4 + length
                let numbers = data[at..<at + count * 12].withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                at += count * 12
                let word = raw.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(
                    in: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
                guard word.allSatisfy({ ($0.isLetter && (anyLetters || $0.isASCII)) || $0 == "'" }),
                    word.count(where: { $0 != "'" }) >= 2
                else { continue }
                items.append(
                    Item(
                        word: word,
                        path: (0..<count).map {
                            SwipePoint(
                                x: Double(numbers[3 * $0]), y: Double(numbers[3 * $0 + 1]),
                                time: Double(numbers[3 * $0 + 2]) / 1000)
                        },
                        context: contexts.flatMap { index < $0.count ? String($0[index]) : nil } ?? ""))
            }
            self.items = items
        }
    }

    /// The lexicon with each of `words` it lacks added at ln P = -`floor` (25.5 is the lowest it stores).
    static func lexicon(adding words: some Sequence<String>, at floor: Double) -> Lexicon {
        var entries: [(word: String, count: Double)] = []
        var seen = Set<String>()
        let english = Lexicon.english
        func visit(_ node: Lexicon.Node, _ spelling: String) {
            if let log = english.logWord(node) {
                entries.append((spelling, Math.exp(log)))
                seen.insert(spelling)
            }
            for child in english.children(node) { visit(child, spelling + english.letters[Int(english.letter(child))]) }
        }
        visit(english.root, "")
        for word in Set(words) where !seen.contains(word) { entries.append((word, Math.exp(-floor))) }
        return Lexicon(counts: entries)
    }

    /// `body` for each of 0..<count on every core, in order.
    static func parallel<Result: Sendable>(_ count: Int, _ body: @Sendable (Int) -> Result) -> [Result] {
        let slots = Slots<Result>(count)
        DispatchQueue.concurrentPerform(iterations: count) { i in
            let value = body(i)
            slots.lock.lock()
            slots.values[i] = value
            slots.lock.unlock()
        }
        return slots.values.map { $0! }
    }

    static var layout: SwipeLayout {
        SwipeLayout(
            grid: KeyGrid(
                Layouts.layout(for: LayoutContext(device: .phone, layer: .letters)), width: width,
                metrics: KeyboardMetrics.phone(width: width).grid, signature: "swipe"))!
    }

    struct Accuracy {
        var first = 0, three = 0, ten = 0, total = 0

        mutating func add(_ words: [String], _ target: String) {
            total += 1
            guard let rank = words.firstIndex(of: target) else { return }
            if rank < 1 { first += 1 }
            if rank < 3 { three += 1 }
            ten += 1
        }

        func percent(_ count: Int) -> String { String(format: "%.2f", 100 * Double(count) / Double(max(total, 1))) }
        var topThree: String { "top1=\(percent(first)) top3=\(percent(three))" }
        var summary: String { "top1=\(percent(first)) top3=\(percent(three)) top10=\(percent(ten))" }
    }

    @Test(.enabled(if: Swipes.exists("test")))
    func swipe() throws {
        let layout = Self.layout
        let model = Swipe.english
        let swipes = Swipes(
            items: try Swipes("test", limit: Int(ProcessInfo.processInfo.environment["SWIPE_LIMIT"] ?? "") ?? .max)
                .placed(on: layout))
        let targets = Set(swipes.items.map(\.word))
        let ours = Lexicon.english
        let inLexicon = swipes.items.count { ours.logProbability(of: $0.word) != nil }
        print(
            "EVAL swipe swipes=\(swipes.items.count) inLexicon=\(String(format: "%.2f", 100 * Double(inLexicon) / Double(swipes.items.count)))%"
        )
        for refined in [false, true] {
            let emissions = Self.parallel(swipes.items.count) {
                (refined ? model : model.withoutDecoder).emissions(of: swipes.items[$0].path, on: layout)!
            }
            for (name, lexicon) in [("ours", ours)]
                + [25.5, 18.0, 12.0].map({ ("forced at -\($0)", Self.lexicon(adding: targets, at: $0)) })
            {
                let ranked = Self.parallel(swipes.items.count) {
                    Swipe.rank(emissions[$0], in: lexicon, refined ? .refined : .encoderOnly, limit: 10).map {
                        $0.word.lowercased()
                    }
                }
                var accuracy = Accuracy()
                for (item, words) in zip(swipes.items, ranked) { accuracy.add(words, item.word) }
                print("EVAL swipe \(refined ? "encoder+decoder" : "encoder") lexicon=\(name) \(accuracy.summary)")
            }
        }
    }

    /// The swipes FUTO collected in other languages and on other layouts (swipe-5, `scripts/swipe languages`), each read
    /// on the keys of the keyboard it was swiped on (its `layouts/` file), with the long-press letters of iikb's layout
    /// of it in its language and its apostrophe key where it has one, and its language's words (`LANGUAGES`, as
    /// `scripts/eval languages` downloads them): top 1/3/10 from a–z's keys alone with the decoder, as swipe read before
    /// it read every key (the language's own, and each letter on the key it's under: é on e), then with every key by the
    /// encoder alone and with the decoder where the keys are a–z's. `keysOff` is how far iikb's own keys are from that
    /// keyboard's, in the box around them.
    @Test(.enabled(if: Swipes.exists("swipe5/de-german") && ProcessInfo.processInfo.environment["LANGUAGES"] != nil))
    func swipeLanguages() throws {
        let model = Swipe.english
        for set in try Self.languageSets() {
            print(
                "EVAL swipe language=\(set.name) layout=\(set.layout) swipes=\(set.swipes.count) inLexicon=\(String(format: "%.2f", set.inLexicon))% keysOff=\(String(format: "%.3f", set.keysOff))"
            )
            for (name, on, refined) in [
                ("a-z keys+decoder", set.aToZ, true), ("encoder", set.keys, false), ("encoder+decoder", set.keys, true),
            ] where name != "encoder+decoder" || set.keys.isAToZ {
                let ranked = Self.parallel(set.swipes.count) {
                    (refined ? model : model.withoutDecoder).emissions(of: set.swipes[$0].path, on: on).map {
                        Swipe.rank($0, in: set.lexicon, limit: 10).map { $0.word.lowercased() }
                    } ?? []
                }
                var accuracy = Accuracy()
                for (item, words) in zip(set.swipes, ranked) { accuracy.add(words, item.word) }
                print("EVAL swipe language=\(set.name) \(name) \(accuracy.summary)")
            }
        }
    }

    /// Each language's own phrases (`phrases.<id>.txt`, and English's phrase set) swiped word by word on iikb's keys
    /// for it by a finger drawn from key to key, each corner a little off its key's center (seeded), since swipe-5 has
    /// no swipes in Portuguese, Italian or Swedish. Read as the keyboard reads it, with the decoder for English alone;
    /// German's, French's, Spanish's and English's lines say how far a drawn finger sits from real ones.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LANGUAGES"] != nil))
    func swipeDrawn() throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LANGUAGES"]!)
        for language in Language.all {
            let english = language == .english
            let lexicon =
                english
                ? Lexicon.english
                : try #require(
                    Lexicon(bytes: [UInt8](Data(contentsOf: folder.appending(path: "\(language.id).lexicon")))))
            var context = LayoutContext(device: .phone, layer: .letters)
            context.languages = [language]
            context.letters = language.layouts[0]
            let layout = try #require(
                SwipeLayout(
                    grid: KeyGrid(
                        Layouts.layout(for: context), width: Self.width,
                        metrics: KeyboardMetrics.phone(width: Self.width).grid,
                        signature: context.signature)))
            var random = SplitMix64(seed: 2026)
            var drawn: [Swipes.Item] = []
            let kept = CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted
            for phrase in try Self.phrases(english ? "phrases" : "phrases.\(language.id)") {
                for token in phrase.split(separator: " ") {
                    let word = Words.plain(String(token)).trimmingCharacters(in: kept)
                    guard word.count(where: \.isLetter) >= 2, word.allSatisfy({ $0.isLetter || $0 == "'" }) else {
                        continue
                    }
                    let keys = word.compactMap { layout.keys[String($0)] }
                    guard keys.count == word.count(where: { $0 != "'" || layout.keys["'"] != nil }) else { continue }
                    let corners = keys.map {
                        (
                            x: layout.centers[$0].x + 0.025 * random.gaussian(),
                            y: layout.centers[$0].y + 0.05 * random.gaussian()
                        )
                    }
                    var path: [SwipePoint] = []
                    for (from, to) in zip(corners, corners.dropFirst() + [corners.last!]) {
                        let steps = max(Int((hypot(to.x - from.x, to.y - from.y) / 0.02).rounded(.up)), 1)
                        for step in 0..<steps {
                            let share = Double(step) / Double(steps)
                            path.append(
                                SwipePoint(
                                    x: layout.frame.x + (from.x + (to.x - from.x) * share) * layout.frame.width,
                                    y: layout.frame.y + (from.y + (to.y - from.y) * share) * layout.frame.height,
                                    time: Double(path.count) * 0.01))
                        }
                    }
                    drawn.append(Swipes.Item(word: word, path: path))
                }
            }
            let items = drawn
            let model = english ? Swipe.english : Swipe.english.withoutDecoder
            let ranked = Self.parallel(items.count) {
                model.emissions(of: items[$0].path, on: layout).map {
                    Swipe.rank($0, in: lexicon, limit: 3).map { $0.word.lowercased() }
                } ?? []
            }
            var accuracy = Accuracy()
            for (item, words) in zip(items, ranked) { accuracy.add(words, item.word) }
            print(
                "EVAL swipe drawn language=\(language.id) layout=\(context.letters.id) words=\(items.count) \(accuracy.topThree)"
            )
        }
    }

    struct LanguageSet {
        let name: String
        let language: Language
        let layout: String
        let lexicon: Lexicon
        let swipes: [Swipes.Item]
        /// The keys it was swiped on, and a–z's of them alone.
        let keys: SwipeLayout
        let aToZ: SwipeLayout
        let inLexicon: Double
        let keysOff: Double
    }

    static func languageSets() throws -> [LanguageSet] {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LANGUAGES"]!)
        let sets: [(name: String, language: Language, layout: LetterLayout, theirs: String)] = [
            ("de-german", .german, .german, "german"), ("de-qwertz", .german, .qwertz, "qwertz"),
            ("de-qwerty", .german, .qwerty, "qwerty"), ("fr-azerty", .french, .french, "azerty"),
            ("fr-qwerty", .french, .qwerty, "qwerty"), ("es-spanish", .spanish, .spanish, "spanish"),
            ("en-qwerty", .english, .qwerty, "qwerty"), ("en-qwertz", .english, .qwertz, "qwertz"),
            ("en-azerty", .english, .azerty, "azerty"),
        ]
        return try sets.filter { Swipes.exists("swipe5/\($0.name)") }.map { set in
            let lexicon =
                set.language == .english
                ? Lexicon.english
                : try #require(
                    Lexicon(bytes: [UInt8](Data(contentsOf: folder.appending(path: "\(set.language.id).lexicon")))))
            var context = LayoutContext(device: .phone, layer: .letters)
            context.languages = [set.language]
            context.letters = set.layout
            let ours = try #require(
                SwipeLayout(
                    grid: KeyGrid(
                        Layouts.layout(for: context), width: width, metrics: KeyboardMetrics.phone(width: width).grid,
                        signature: context.signature)))
            let file = try JSONSerialization.jsonObject(
                with: Data(contentsOf: Swipes.directory.appending(path: "swipe-5/layouts/\(set.theirs).json")))
            let theirs = try #require(file as? [String: Any])["keys"] as? [[String: Any]] ?? []
            var centers: [String: (x: Double, y: Double)] = [:]
            for key in theirs {
                guard let letter = key["letter"] as? String, letter.first?.isLetter == true || ours.keys[letter] != nil,
                    let x = key["cx"] as? Double, let y = key["cy"] as? Double
                else { continue }
                centers[letter] = (x, y)
            }
            let unit = Rect(x: 0, y: 0, width: 1, height: 1)
            let under = ours.keys.mapValues { ours.letters[$0] }
            let keys = try #require(SwipeLayout(centers: centers, frame: unit, under: under))
            let aToZ = try #require(
                SwipeLayout(centers: centers.filter { Swipe.alphabet.contains($0.key) }, frame: unit))
            let off =
                zip(ours.letters, ours.centers).compactMap { letter, center -> Double? in
                    centers[letter].map { max(abs($0.x - center.x), abs($0.y - center.y)) }
                }.max() ?? 0
            let swipes = try Swipes("swipe5/\(set.name)", anyLetters: true).items
            let inLexicon =
                100 * Double(swipes.count { lexicon.logProbability(of: $0.word) != nil })
                / Double(max(swipes.count, 1))
            return LanguageSet(
                name: set.name, language: set.language, layout: set.layout.id, lexicon: lexicon, swipes: swipes,
                keys: keys, aToZ: aToZ,
                inLexicon: inLexicon, keysOff: off)
        }
    }

    /// One decode's cost on one core, from the points to the ranked words.
    @Test(.enabled(if: Swipes.exists("test")))
    func swipeLatency() throws {
        let layout = Self.layout
        let swipes = Swipes(items: try Swipes("test", limit: 600).placed(on: layout))
        let clock = ContinuousClock()
        let model = Swipe.english
        let lexicon = Lexicon.english
        for refined in [false, true] {
            var network: [Double] = []
            var search: [Double] = []
            for item in swipes.items {
                let start = clock.now
                let emissions = (refined ? model : model.withoutDecoder).emissions(of: item.path, on: layout)!
                let middle = clock.now
                _ = Swipe.rank(emissions, in: lexicon, refined ? .refined : .encoderOnly, limit: 10)
                let end = clock.now
                network.append(
                    Double((middle - start).components.attoseconds) / 1e15 + Double((middle - start).components.seconds)
                        * 1000)
                search.append(
                    Double((end - middle).components.attoseconds) / 1e15 + Double((end - middle).components.seconds)
                        * 1000)
            }
            func summary(_ values: [Double]) -> String {
                let sorted = values.sorted()
                return String(format: "median %.2f p95 %.2f", sorted[sorted.count / 2], sorted[sorted.count * 95 / 100])
            }
            print(
                "EVAL latency swipe ms \(refined ? "encoder+decoder" : "encoder"): network \(summary(network)) | search \(summary(search)) | both \(summary(zip(network, search).map(+)))"
            )
        }
    }

    /// Retunes `Swipe.Scoring` by coordinate search, keeping the best of top 1 and top 3 together, and prints the
    /// constants to put in it: `SWIPE_TUNE=refined|encoder scripts/eval swipeTune` on the validation split, or
    /// `SWIPE_TUNE=languages` on every other swipe of swipe-5's in other languages, read by the encoder alone, then
    /// scored on the swipes it left out.
    @Test(.enabled(if: Swipes.exists("dev") && ProcessInfo.processInfo.environment["SWIPE_TUNE"] != nil))
    func swipeTune() throws {
        let tune = ProcessInfo.processInfo.environment["SWIPE_TUNE"]!
        let model = tune == "refined" ? Swipe.english : Swipe.english.withoutDecoder
        typealias Read = (emissions: Swipe.Emissions, lexicon: Lexicon, word: String)
        var reads: [Read] = []
        var held: [Read] = []
        if tune == "languages" {
            for set in try Self.languageSets() where set.language != .english {
                let emissions = Self.parallel(set.swipes.count) {
                    model.emissions(of: set.swipes[$0].path, on: set.keys)!
                }
                for (index, (item, emissions)) in zip(set.swipes, emissions).enumerated() {
                    let read = (emissions, set.lexicon, item.word)
                    if index.isMultiple(of: 2) { reads.append(read) } else { held.append(read) }
                }
            }
        } else {
            let layout = Self.layout
            let swipes = try Swipes(
                "dev", limit: Int(ProcessInfo.processInfo.environment["SWIPE_LIMIT"] ?? "") ?? 8000
            ).placed(on: layout)
            let emissions = Self.parallel(swipes.count) { model.emissions(of: swipes[$0].path, on: layout)! }
            reads = zip(swipes, emissions).map { ($1, Lexicon.english, $0.word) }
        }
        func score(_ scoring: Swipe.Scoring, on reads: [Read]) -> (Double, Accuracy) {
            let ranked = Self.parallel(reads.count) {
                Swipe.rank(reads[$0].emissions, in: reads[$0].lexicon, scoring, limit: 3).map { $0.word.lowercased() }
            }
            var accuracy = Accuracy()
            for (read, words) in zip(reads, ranked) { accuracy.add(words, read.word) }
            return (Double(accuracy.first + accuracy.three) / Double(accuracy.total), accuracy)
        }
        var best = tune == "refined" ? Swipe.Scoring.refined : .encoderOnly
        if let b = ProcessInfo.processInfo.environment["SWIPE_BEAM"] { best.beam = Int(b)! }
        if let c = ProcessInfo.processInfo.environment["SWIPE_CUTOFF"] { best.cutoff = Float(c)! }
        let start = best
        var (value, accuracy) = score(best, on: reads)
        print("EVAL tune start \(accuracy.summary) \(best)")
        let fields: [WritableKeyPath<Swipe.Scoring, Double>] = [\.gamma, \.lambda, \.beta, \.pruneGamma, \.pruneBeta]
        for factor in [1.5, 1.25, 1.1] {
            for field in fields {
                for direction in [factor, 1 / factor] {
                    var trial = best
                    trial[keyPath: field] *= direction
                    let (trialValue, trialAccuracy) = score(trial, on: reads)
                    if trialValue > value { (best, value, accuracy) = (trial, trialValue, trialAccuracy) }
                }
            }
            print("EVAL tune factor=\(factor) \(accuracy.summary) \(best)")
        }
        if !held.isEmpty {
            print(
                "EVAL tune held out: start \(score(start, on: held).1.summary) | tuned \(score(best, on: held).1.summary)"
            )
        }
    }

    /// How much the sentence helps: every swipe of a split read with its sentence's words before it, and again in an empty
    /// field, through the bar's own next-word model (`Corrector.continuation`, a fresh memory). Three scores meet: the
    /// decoder alone, the old blend (α·ln P(word | context) with λ and β retuned) and the new one (α times how much the
    /// context moves ln P(word) from its value at a sentence start). The grid search over α, λ and β runs on the
    /// validation split (`SWIPE_LIMIT` swipes, every few-th, 6000 by default) with the candidates of the first 30
    /// re-scored exactly, since the score is linear in λ and β, for the best of the two cases together.
    @Test(.enabled(if: Swipes.exists("dev") && Swipes.exists("test")))
    func swipeContext() throws {
        let layout = Self.layout
        let model = Swipe.english
        let lexicon = Lexicon.english
        let base = Swipe.Scoring.refined
        let limit = Int(ProcessInfo.processInfo.environment["SWIPE_LIMIT"] ?? "") ?? 6000

        struct Read {
            let word: String
            let candidates:
                [(word: String, score: Double, prior: Double, length: Double, context: Double, empty: Double)]
        }
        func read(_ items: [Swipes.Item]) -> [Read] {
            let ranked = Self.parallel(items.count) { index in
                model.emissions(of: items[index].path, on: layout).map { Swipe.rank($0, in: lexicon, base, limit: 30) }
                    ?? []
            }
            let corrector = Corrector(source: lexicon, network: .english)
            let none = corrector.continuation(after: "")
            return zip(items, ranked).map { item, found in
                let continues = corrector.continuation(after: item.context.isEmpty ? "" : item.context + " ")
                return Read(
                    word: item.word,
                    candidates: found.map {
                        (
                            $0.word, $0.score, lexicon.logProbability(of: $0.word) ?? 0,
                            Double($0.word.utf8.count(where: { $0 != 39 })), continues($0.word), none($0.word)
                        )
                    })
            }
        }
        enum Blend { case decoder, old, new }
        func accuracy(_ reads: [Read], _ blend: Blend, context: Bool, alpha: Double, lambda: Double, beta: Double)
            -> Accuracy
        {
            var accuracy = Accuracy()
            for item in reads {
                let words = item.candidates
                    .map { candidate -> (String, Double) in
                        let seen = context ? candidate.context : candidate.empty
                        let moved: Double =
                            switch blend {
                            case .decoder: 0
                            case .old: alpha * seen
                            case .new: alpha * (seen - candidate.empty)
                            }
                        let tuned =
                            blend == .decoder
                            ? 0 : (lambda - base.lambda) * candidate.prior + (beta - base.beta) * candidate.length
                        return (candidate.word, candidate.score + tuned + moved)
                    }
                    .sorted { $0.1 > $1.1 }.prefix(3).map { $0.0.lowercased() }
                accuracy.add(Array(words), item.word)
            }
            return accuracy
        }
        func both(_ reads: [Read], _ blend: Blend, alpha: Double, lambda: Double, beta: Double) -> Double {
            [true, false].map { context in
                let result = accuracy(reads, blend, context: context, alpha: alpha, lambda: lambda, beta: beta)
                return Double(result.first + result.three) / Double(result.total)
            }.reduce(0, +)
        }

        let all = try Swipes("dev").placed(on: layout)
        let stride = max(all.count / limit, 1)
        let dev = read((0..<min(limit, all.count)).map { all[$0 * stride] })
        var best: [Blend: (alpha: Double, lambda: Double, beta: Double)] = [:]
        for blend in [Blend.old, .new] {
            var bestValue = 0.0
            for alpha in [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.65, 0.8, 1.0] {
                for lambda in [0, 0.03, 0.06, 0.1, 0.15, base.lambda] {
                    for beta in [0.5, 0.6, base.beta, 0.727, 0.85, 1.0] {
                        let value = both(dev, blend, alpha: alpha, lambda: lambda, beta: beta)
                        if value > bestValue { (best[blend], bestValue) = ((alpha, lambda, beta), value) }
                    }
                }
            }
            print("EVAL swipe context dev=\(dev.count) \(blend) \(best[blend]!)")
        }

        let test = read(try Swipes("test").placed(on: layout))
        func report(_ name: String, _ blend: Blend, _ given: (alpha: Double, lambda: Double, beta: Double)? = nil) {
            let setting = given ?? best[blend] ?? (0, base.lambda, base.beta)
            let with = accuracy(
                test, blend, context: true, alpha: setting.alpha, lambda: setting.lambda, beta: setting.beta)
            let without = accuracy(
                test, blend, context: false, alpha: setting.alpha, lambda: setting.lambda, beta: setting.beta)
            print(
                "EVAL swipe context test=\(test.count) \(name) alpha=\(setting.alpha) lambda=\(setting.lambda) beta=\(setting.beta): context \(with.topThree) | empty \(without.topThree)"
            )
        }
        report("decoder", .decoder)
        report("before", .old, (0.4, 0, 0.85))
        report("old", .old)
        report("new", .new)
    }

    /// The 400 recorded swipes of `scripts/swipebench.tsv`, each into an empty field through the whole `TypingEngine` on
    /// the folded Duo in portrait (`SWIPE_BENCH=1 scripts/eval swipeBench`), against the decoder alone on the same grid.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIPE_BENCH"] != nil))
    @MainActor func swipeBench() throws {
        let duo = Duo.Screen.foldedPortrait
        let context = LayoutContext(
            device: .phone, layer: .letters, showsGlobe: true, isLandscape: false, isOpen: false, showsEmoji: true)
        let metrics = KeyboardMetrics.for(context, screen: duo.size, window: duo.keyboardWidth, style: .ios26)
        let grid = KeyGrid(
            Layouts.layout(for: context), width: duo.keyboardWidth, metrics: metrics.grid, signature: context.signature)
        let frame = SwipeLayout(grid: grid)!.frame
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWIPE_BENCH"]!)
        let rows = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").filter { !$0.hasPrefix("#") }.map
        { $0.split(separator: "\t") }
        let model = Swipe.english
        let lexicon = Lexicon.english
        var engine = Accuracy()
        var decoder = Accuracy()
        for row in rows {
            let word = String(row[0])
            let points = row[1].split(separator: ";").map { $0.split(separator: ",").map { Double($0)! } }
            let path = points.map {
                SwipePoint(
                    x: frame.x + $0[0] / 1000 * frame.width, y: frame.y + $0[1] / 1000 * frame.height,
                    time: $0[2] / 1000)
            }
            if let emissions = model.emissions(of: path, on: SwipeLayout(grid: grid)!) {
                decoder.add(Swipe.rank(emissions, in: lexicon, .refined, limit: 3).map { $0.word.lowercased() }, word)
            } else {
                decoder.total += 1
            }
            var typing = TypingEngine(traits: InputTraits(autocapitalization: .none))
            typing.corrector = Corrector(source: lexicon, network: .english)
            typing.swipeModel = model
            typing.use(grid)
            let document = Document()
            typing.documentChanged(document)
            typing.handle(.swipe(path), in: document)
            let typed = document.text.lowercased()
            engine.add(
                [typed] + (typing.swipedWord?.alternatives.map { $0.text.lowercased() }.filter { $0 != typed } ?? []),
                word)
        }
        print(
            "EVAL swipe bench swipes=\(rows.count) decoder \(decoder.topThree) engine \(engine.topThree) (top1 \(engine.first)/\(engine.total), decoder \(decoder.first)/\(decoder.total))"
        )
    }
}
