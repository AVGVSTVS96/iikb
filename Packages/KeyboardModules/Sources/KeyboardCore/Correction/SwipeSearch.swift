extension Swipe {
    /// A word the swipe may have meant, scored as `-CTC/L^γ + λ·ln P(word) + β·L` (L its letters): the more the better.
    /// To blend in a language model's ln P(word | context), add α times it to `score`.
    public struct Candidate: Sendable, Equatable {
        public let word: String
        public let score: Double
    }

    /// The constants of that score, and of the pruning that keeps `beam` prefixes per step by `ln P / depth^γ + β·depth`.
    public struct Scoring: Sendable, Equatable {
        public var gamma: Double
        public var lambda: Double
        public var beta: Double
        public var pruneGamma: Double
        public var pruneBeta: Double
        public var beam = 100
        public var cutoff: Float = -14

        public static let refined = Scoring(gamma: 0.595, lambda: 0.31, beta: 0.727, pruneGamma: 0.14, pruneBeta: 0.85)
        public static let encoderOnly = Scoring(
            gamma: 0.608, lambda: 0.392, beta: 0.658, pruneGamma: 0.282, pruneBeta: 1.038)
    }

    /// The words of `lexicon` the path may have been swiped for, likeliest first: a CTC beam search over the lexicon's
    /// trie on the network's emissions, each word then scored. Each letter is read on the key it's swiped on (é on e),
    /// an apostrophe on its key where there is one and otherwise for nothing (a swipe for "I'm" is "im"), and a word
    /// with a letter no key holds is never found. An
    /// elision the lexicon lists, a word ending in an apostrophe as French's "l'" or Italian's "dell'", goes on to any
    /// word, as "l'armée" is swiped in one, scored as likely as the two words together.
    public func decode(
        _ path: [SwipePoint], on layout: SwipeLayout, in lexicon: Lexicon, scoring: Scoring? = nil, limit: Int = 10
    ) -> [Candidate] {
        guard let emissions = emissions(of: path, on: layout) else { return [] }
        return Self.rank(emissions, in: lexicon, scoring, limit: limit)
    }

    /// The words of `lexicon` the emissions may be, scored as `scoring` says, or as fits the network that made them.
    static func rank(_ emissions: Emissions, in lexicon: Lexicon, _ scoring: Scoring? = nil, limit: Int) -> [Candidate]
    {
        Search(emissions, lexicon, scoring ?? (emissions.refined ? .refined : .encoderOnly)).candidates(limit: limit)
    }
}

private struct Search {
    let emissions: Swipe.Emissions
    let lexicon: Lexicon
    let scoring: Swipe.Scoring

    init(_ emissions: Swipe.Emissions, _ lexicon: Lexicon, _ scoring: Swipe.Scoring) {
        self.emissions = emissions
        self.lexicon = lexicon
        self.scoring = scoring
    }

    struct Hypothesis {
        var node: Int32
        /// The elision the word goes on from, 0 for none.
        var head: Int32
        var last: Int8
        var depth: Int16
        var spelling: Int32
        var blank: Float
        var letter: Float

        var total: Float { Search.add(blank, letter) }
    }

    /// ln(e^a + e^b).
    static func add(_ a: Float, _ b: Float) -> Float {
        let (high, low) = a > b ? (a, b) : (b, a)
        guard low > -.infinity else { return high }
        let distance = (high - low) * 32
        guard distance < 511 else { return high }
        let index = Int(distance)
        let fraction = distance - Float(index)
        return high + softplus[index] + (softplus[index + 1] - softplus[index]) * fraction
    }

    static let softplus: [Float] = (0...512).map { Float(Math.log(1 + Math.exp(-Double($0) / 32))) }

    func candidates(limit: Int) -> [Swipe.Candidate] {
        let nodes = lexicon.nodes
        let apostrophe = lexicon.apostrophe
        let classes = lexicon.letters.map { emissions.keys[$0] }
        return lexicon.bytes.withUnsafeBytes { trie in
            func letter(_ node: Int32) -> UInt8 { trie[nodes + Int(node) * 8] }
            func flags(_ node: Int32) -> UInt8 { trie[nodes + Int(node) * 8 + 3] }
            func first(_ node: Int32) -> Int32 {
                let at = nodes + Int(node) * 8 + 4
                return Int32(
                    truncatingIfNeeded: Int(trie[at]) | Int(trie[at + 1]) << 8 | Int(trie[at + 2]) << 16 | Int(
                        trie[at + 3]) << 24)
            }
            func probability(_ node: Int32) -> UInt8 { trie[nodes + Int(node) * 8 + 1] }
            func each(_ parent: Int32, _ body: (Int32) -> Void) {
                var child = first(parent)
                while child != 0 {
                    body(child)
                    child = flags(child) & 1 != 0 ? 0 : child + 1
                }
            }
            func isElision(_ node: Int32) -> Bool { node != 0 && letter(node) == apostrophe && probability(node) != 0 }
            /// Each child of `node` on a key, the children of an apostrophe's in its place, and the first letters of
            /// every word after an elision, as (key, node, after an unswiped apostrophe, the elision before the word).
            func extensions(_ node: Int32, _ head: Int32, _ body: (Int, Int32, Bool, Int32) -> Void) {
                func words(after elision: Int32, unswiped: Bool) {
                    each(0) { if let index = classes[Int(letter($0))] { body(index, $0, unswiped, elision) } }
                }
                if head == 0, isElision(node) { words(after: node, unswiped: false) }
                each(node) { child in
                    if let index = classes[Int(letter(child))] { body(index, child, false, head) }
                    guard letter(child) == apostrophe else { return }
                    each(child) { if let index = classes[Int(letter($0))] { body(index, $0, true, head) } }
                    if head == 0, isElision(child) { words(after: child, unswiped: true) }
                }
            }

            let gamma = (0...Swipe.steps + 1).map {
                Float(Math.exp(Math.log(Double(max($0, 1))) * -scoring.pruneGamma))
            }
            func pruneScore(_ h: Hypothesis) -> Float {
                h.total * gamma[Int(h.depth)] + Float(scoring.pruneBeta) * Float(h.depth)
            }

            var spellings: [(parent: Int32, node: Int32, apostrophe: Bool, word: Bool)] = [(-1, 0, false, false)]
            var beam = [Hypothesis(node: 0, head: 0, last: -1, depth: 0, spelling: 0, blank: 0, letter: -.infinity)]
            let size = 8192
            var keys = [Int64](repeating: -1, count: size)
            var slots = [Int32](repeating: 0, count: size)
            var used: [Int] = []
            var next: [Hypothesis] = []
            let blank = emissions.classes - 1

            for step in 0..<Swipe.steps {
                let row = (0..<emissions.classes).map { emissions[step, $0] }
                next.removeAll(keepingCapacity: true)
                used.removeAll(keepingCapacity: true)
                func slot(_ node: Int32, _ head: Int32, _ last: Int8, _ depth: Int16, _ spelling: Int32) -> Int {
                    let key = Int64(node) | Int64(head) << 32
                    var at = (Int(node) &* 40503 &+ Int(head) &* 9973) & (size - 1)
                    while keys[at] != -1 && keys[at] != key { at = (at + 1) & (size - 1) }
                    if keys[at] == -1 {
                        keys[at] = key
                        used.append(at)
                        slots[at] = Int32(next.count)
                        next.append(
                            Hypothesis(
                                node: node, head: head, last: last, depth: depth, spelling: spelling,
                                blank: -.infinity, letter: -.infinity))
                    }
                    return Int(slots[at])
                }
                for h in beam {
                    let total = h.total
                    let stay = slot(h.node, h.head, h.last, h.depth, h.spelling)
                    next[stay].blank = Search.add(next[stay].blank, total + row[blank])
                    if h.last >= 0 { next[stay].letter = Search.add(next[stay].letter, h.letter + row[Int(h.last)]) }
                    guard Int(h.depth) < Swipe.steps else { continue }
                    extensions(h.node, h.head) { index, node, apostrophe, head in
                        guard row[index] > scoring.cutoff else { return }
                        let repeated = h.last == Int8(index)
                        let source = repeated ? h.blank : total
                        guard source > -.infinity else { return }
                        let target = slot(node, head, Int8(index), h.depth + 1, -1)
                        if next[target].spelling == -1 {
                            spellings.append((h.spelling, node, apostrophe, head != h.head))
                            next[target].spelling = Int32(spellings.count - 1)
                        }
                        next[target].letter = Search.add(next[target].letter, source + row[index])
                    }
                }
                for at in used { keys[at] = -1 }
                if next.count > scoring.beam {
                    let scores = next.map(pruneScore)
                    let order = next.indices.sorted { scores[$0] > scores[$1] }
                    beam = order.prefix(scoring.beam).map { next[$0] }
                } else {
                    beam = next
                }
            }

            var found: [Swipe.Candidate] = []
            func capitalized(_ node: Int32) -> Bool { flags(node) & 2 != 0 }
            for h in beam where h.depth > 0 && probability(h.node) != 0 {
                var letters: [String] = []
                var at = h.spelling
                while at > 0 {
                    let entry = spellings[Int(at)]
                    let spelled = lexicon.letters[Int(letter(entry.node))]
                    letters.append(entry.word && capitalized(h.node) ? spelled.uppercased() : spelled)
                    if entry.apostrophe { letters.append("'") }
                    at = entry.parent
                }
                letters.reverse()
                if capitalized(h.head == 0 ? h.node : h.head) { letters[0] = letters[0].uppercased() }
                let length = Double(h.depth)
                let lnP = -Double(probability(h.node)) / 10 - (h.head == 0 ? 0 : Double(probability(h.head)) / 10)
                let score =
                    Double(h.total) / Math.exp(Math.log(length) * scoring.gamma) + scoring.lambda * lnP + scoring.beta
                    * length
                found.append(Swipe.Candidate(word: letters.joined(), score: score))
            }
            return Array(found.sorted { $0.score > $1.score }.prefix(limit))
        }
    }
}
