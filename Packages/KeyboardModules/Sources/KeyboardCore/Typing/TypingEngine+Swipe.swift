/// The word a swipe just typed, which delete takes out whole and the bar offers alternatives to, for as long as the text
/// before the caret is as the swipe left it.
struct Swiped: Hashable {
    var word: String
    var length: Int
    var end: String
    var alternatives: [Suggestion]

    static func key(_ word: String) -> String { Words.plain(word).lowercased() }
}

struct TakenBack: Hashable {
    var end: String
    var words: Set<String>
}

extension TypingEngine {

    /// Types the likeliest word for a swipe, as a word follows a word: a space first when the caret follows one, none
    /// after. Returns false when nothing was typed.
    mutating func swipe(_ path: [SwipePoint], in document: some TextDocument) -> Bool {
        guard settings.slideToType, panel == nil, layer == .letters, let corrector,
            let decoded = candidates(for: path, corrector)
        else { return false }
        attach(document)
        lastSpace = nil
        revert = nil
        commitWord(in: document)
        let joins = !Words.startsWord(after: text.before.last) && !corrector.elides(text.before)
        let continues = corrector.continuation(after: text.before + (joins ? " " : ""))
        let starting = corrector.continuation(after: "")
        var seen: Set<String> = []
        let ranked =
            decoded
            .map { (word: corrector.spelling(of: $0.word), swipe: $0.score) }
            .map {
                (
                    word: $0.word,
                    score: $0.swipe + Swipe.Scoring.contextWeight * (continues($0.word) - starting($0.word))
                )
            }
            .filter { seen.insert($0.word.lowercased()).inserted }
            .sorted { $0.score > $1.score }
        let taken = takenBack.flatMap { $0.end == text.before ? $0.words : nil } ?? []
        let words =
            (ranked.filter { !taken.contains(Swiped.key($0.word)) }
            + ranked.filter { taken.contains(Swiped.key($0.word)) })
            .prefix(4)
            .map { written(cased($0.word)) }
        guard let best = words.first else { return false }
        write((joins ? " " : "") + best, in: document)
        tally.characters += best.count + (joins ? 1 : 0)
        swiped = Swiped(
            word: Swiped.key(best), length: best.count + (joins ? 1 : 0), end: text.before,
            alternatives: words.dropFirst().map { Suggestion($0, .candidate) })
        refreshShift()
        suggestionsChanged()
        return true
    }

    /// What the swipe may have spelled, in the lexicon and in the words you've taught the keyboard, which a lexicon of their
    /// own holds (made again only when they change). Nil for a path too short to read.
    private mutating func candidates(for path: [SwipePoint], _ corrector: Corrector) -> [Swipe.Candidate]? {
        guard let model = swipeModel, let lexicon = corrector.lexicon,
            let layout = corrector.grid.swipeLayout(near: path),
            let emissions = model.emissions(of: path, on: layout)
        else { return nil }
        var found = Swipe.rank(emissions, in: lexicon, limit: 10)
        if let own = ownWords(corrector, besides: lexicon) {
            found += Swipe.rank(emissions, in: own, limit: 3)
        }
        return found.isEmpty ? nil : found
    }

    private mutating func ownWords(_ corrector: Corrector, besides lexicon: Lexicon) -> Lexicon? {
        let words = Set(
            (Array(corrector.memory.familiar) + Array(corrector.names.values)).filter {
                lexicon.logProbability(of: $0) == nil
            })
        guard !words.isEmpty else { return nil }
        if ownedWords?.words != words { ownedWords = (words, Lexicon(counts: words.map { (word: $0, count: 1.0) })) }
        return ownedWords?.lexicon
    }

    /// The swipe's word while it's still the last thing typed.
    var swipedWord: Swiped? {
        swiped.flatMap { text.before == $0.end && text.owned >= $0.length ? $0 : nil }
    }

    private func cased(_ word: String) -> String {
        switch shift {
        case .off: word
        case .on: word.prefix(1).uppercased() + word.dropFirst()
        case .locked: word.uppercased()
        }
    }
}

extension Corrector {
    /// A word as the keyboard spells it: a name, or the lexicon's capitals ("I", "London").
    func spelling(of word: String) -> String {
        names[word.lowercased()] ?? lexicon?.canonical(word) ?? word
    }

    /// Whether the text ends in an elision the lexicon lists, French's "l’" or Italian's "dell’", which the next word
    /// goes on without a space.
    func elides(_ text: String) -> Bool {
        guard let lexicon, let last = text.last, Words.apostrophes.contains(last) else { return false }
        return lexicon.isWord(Words.plain(String(Words.current(in: text))).lowercased())
    }

    /// log P(word | the text before it) as the bar ranks the words that come next. `text` ends where the word starts.
    func continuation(after text: String) -> (String) -> Double {
        guard let lexicon else { return { _ in 0 } }
        let context = Words.context(before: text[text.endIndex...], in: text)
        return languageModel(lexicon).predictor(
            after: context.previous, earlier: context.earlier, expected: expected(after: text))
    }
}

extension Swipe.Scoring {
    /// How much the sentence counts against the swipe, as a multiple of how far it moves ln P(word) from its value at a
    /// sentence start, which the decoder's own λ·ln f already holds, so an empty field ranks as the decoder alone.
    static let contextWeight = 0.3
}

extension KeyGrid {
    /// The letters as the model reads them: each key's center, and where the halves of a split keyboard both have one,
    /// the one nearer the swipe's middle.
    func swipeLayout(near path: [SwipePoint]) -> SwipeLayout? {
        guard let box = SwipeLayout(grid: self), !path.isEmpty else { return nil }
        let x = path.reduce(0) { $0 + $1.x } / Double(path.count)
        let y = path.reduce(0) { $0 + $1.y } / Double(path.count)
        var nearest: [String: Rect] = [:]
        for (key, frame) in rows.joined() {
            guard let letter = key.swiped else { continue }
            if let known = nearest[letter], known.distanceSquared(toX: x, y: y) <= frame.distanceSquared(toX: x, y: y) {
                continue
            }
            nearest[letter] = frame
        }
        return SwipeLayout(
            centers: nearest.mapValues { ($0.midX, $0.midY) }, frame: box.frame,
            under: box.keys.compactMapValues { box.letters[$0] })
    }
}
