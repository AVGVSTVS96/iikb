/// A language being typed and what the keyboard has of it: its words, and its next-word network where it has one.
public struct LanguagePack: Sendable {
    public let language: Language
    public let lexicon: Lexicon
    public let network: Network?

    public init(_ language: Language, lexicon: Lexicon, network: Network? = nil) {
        self.language = language
        self.lexicon = lexicon
        self.network = network
    }
}

extension Corrector {
    /// How often the next word is in another language than the one before it, in someone's writing who mixes them.
    /// From 0.02 to 0.3, `scripts/eval several` scores English with German within a tenth of a point.
    static let switching = 0.1
    /// The words before the caret that say which language is being written.
    static let heard = 16
    /// How much likelier another language's word on the same keys must be than a word typed where the words before
    /// don't say which language is written, for the space to type it: "Voce" is "Você", and "video" stays beside French's "vidéo",
    /// 12 times likelier in its language than "video" in English.
    static let twinLogOdds = Math.log(100)

    /// How likely the word after `text` is in each of the languages typed, from the words of `text`: each word counts
    /// for a language as its words make it likely, a word none of them has for none, and after every word the next
    /// may switch (`switching`) to any of them alike. Before any word they're all as likely.
    func shares(after text: some StringProtocol) -> [Double] {
        let even = 1 / Double(languages.count)
        var shares = [Double](repeating: even, count: languages.count)
        guard let lexicon, languages.count > 1 else { return shares }
        let model = languageModel(lexicon)
        for word in text.split(whereSeparator: { !Words.isWordCharacter($0) }).suffix(Self.heard) {
            let word = Words.plain(word.lowercased())
            guard !word.contains(where: \.isNumber) else { continue }
            let fits = zip(languages, shares).map { $1 * model.lexical(word, in: $0.lexicon) }
            let total = fits.reduce(0, +)
            guard total > 0 else { continue }
            shares = fits.map { (1 - Self.switching) * $0 / total + Self.switching * even }
        }
        return shares
    }

    /// Reads which language the text before the word being typed is in, so the word is read as that language's first.
    /// The engine calls it as the text changes, before it copies the corrector to rank on another thread, so the copy
    /// and this one rank by the same shares and its rankings are kept (`adopt`).
    func follow(_ context: String?) {
        guard languages.count > 1, let context, context != followed else { return }
        followed = context
        let shares = shares(after: context)
        if shares != self.shares {
            self.shares = shares
            forgetRankings(keys: false)
        }
    }

    /// Whether the words before say the languages with `share` are the ones being written, not those with `other`:
    /// they're twice as likely. One word both have, like "a" in English and Portuguese, doesn't say.
    static func clearly(_ share: Double, over other: Double) -> Bool {
        share >= 2 * other
    }

    /// A word as the lexicon spells it. With several languages, a word some capitalize and others don't has its
    /// capital where those that do are clearly the ones being written: "Kind" after German words, "kind" after
    /// English ones and where nothing says which.
    func canonical(_ word: String) -> String? {
        guard languages.count > 1, let plain = lexicon?.canonical(word) else { return lexicon?.canonical(word) }
        var (capital, lower) = (0.0, 0.0)
        var capitalized: String?
        for (pack, share) in zip(languages, shares) {
            guard let spelling = pack.lexicon.canonical(word) else { continue }
            if spelling == plain {
                lower += share
            } else {
                capital += share
                capitalized = spelling
            }
        }
        return capitalized.flatMap { Self.clearly(capital, over: lower) ? $0 : nil } ?? plain
    }

    /// Whether `word` is the one meant where the same keys type `twin` too, a word of other languages: it is where
    /// its languages are clearly the ones being written, and isn't where the twin's are. Where the words before don't
    /// say, as before a message's first word, it is unless the twin is far the likelier word (`logOdds`,
    /// `twinLogOdds`). A word none of them has is meant, and so is any word with one language, or with a twin only
    /// its own languages have.
    func isWritten(_ word: String, not twin: String, logOdds: Double) -> Bool {
        var (own, others, known) = (0.0, 0.0, false)
        for (pack, share) in zip(languages, shares) {
            if pack.lexicon.isWord(word) {
                own += share
                known = true
            } else if pack.lexicon.isWord(twin) {
                others += share
            }
        }
        guard languages.count > 1, known, others > 0, !Self.clearly(own, over: others) else { return true }
        return !Self.clearly(others, over: own) && logOdds < Self.twinLogOdds
    }

    /// The language `text` is likeliest being written in as it ends, among those typed; nil with one language.
    public func language(writing text: String) -> Language? {
        guard languages.count > 1 else { return nil }
        let shares = shares(after: text)
        return zip(languages, shares).max { $0.1 < $1.1 }?.0.language
    }
}

extension Lexicon {
    /// The words of several lexicons in one, in the letters of them all, each word as likely as it is across them
    /// counted alike, so one search reads taps as a word of any. A word is capitalized where every lexicon that has it
    /// capitalizes it.
    public convenience init(merging lexicons: [Lexicon]) {
        let letters = Set(lexicons.flatMap(\.letters)).sorted()
        precondition(letters.count <= Self.mostLetters, "a lexicon holds at most \(Self.mostLetters) letters")
        let places = lexicons.map { $0.letters.map { UInt8(letters.firstIndex(of: $0)!) } }
        let share = 1 / Double(lexicons.count)
        var bytes = Self.heading(letters)
        let nodes = bytes.count
        bytes.reserveCapacity(nodes + lexicons.reduce(0) { $0 + $1.bytes.count })
        bytes += [0, 0, Self.quantize(1), 1, 0, 0, 0, 0]
        var count = 1
        var pending: [(index: Int, sources: [Node?])] = [(0, lexicons.map(\.root))]
        var children: [(place: UInt8, lexicon: Int, node: Node)] = []
        while let (index, sources) = pending.popLast() {
            children.removeAll(keepingCapacity: true)
            for (i, source) in sources.enumerated() {
                guard let source else { continue }
                for child in lexicons[i].children(source) {
                    children.append((places[i][Int(lexicons[i].letter(child))], i, child))
                }
            }
            guard !children.isEmpty else { continue }
            children.sort { $0.place < $1.place }
            Self.write(count, at: nodes + index * 8 + 4, in: &bytes)
            var at = 0
            while at < children.count {
                let place = children[at].place
                var merged = [Node?](repeating: nil, count: lexicons.count)
                var word = 0.0
                var mass = 0.0
                var capital = true
                while at < children.count, children[at].place == place {
                    let (_, i, node) = children[at]
                    merged[i] = node
                    mass += share * Math.exp(lexicons[i].logMass(node))
                    if let known = lexicons[i].logWord(node) {
                        word += share * Math.exp(known)
                        capital = capital && lexicons[i].isCapitalized(node)
                    }
                    at += 1
                }
                let flags: UInt8 = (at == children.count ? 1 : 0) | (word > 0 && capital ? 2 : 0)
                bytes += [place, Self.quantize(word), Self.quantize(min(mass, 1)), flags, 0, 0, 0, 0]
                pending.append((count, merged))
                count += 1
            }
        }
        Self.write(count, at: 4, in: &bytes)
        self.init(bytes: bytes)!
    }

    /// A lexicon's bytes before its nodes: the header, a node count to fill in, and its letters.
    static func heading(_ letters: [String]) -> [UInt8] {
        let spelled = Array(letters.joined(separator: "\n").utf8)
        var bytes = header + [0, 0, 0, 0]
        bytes += stride(from: 0, to: 32, by: 8).map { UInt8(truncatingIfNeeded: spelled.count >> $0) }
        bytes += spelled
        return bytes + [UInt8](repeating: 0, count: (8 - bytes.count % 8) % 8)
    }

    static func write(_ value: Int, at offset: Int, in bytes: inout [UInt8]) {
        for byte in 0..<4 { bytes[offset + byte] = UInt8(truncatingIfNeeded: value >> (8 * byte)) }
    }

    /// A probability as a node keeps it: `-ln p` in tenths of a nat, 0 for none.
    static func quantize(_ p: Double) -> UInt8 {
        p <= 0 ? 0 : UInt8(min(max((-Math.log(p) * 10).rounded(), 1), 255))
    }
}
