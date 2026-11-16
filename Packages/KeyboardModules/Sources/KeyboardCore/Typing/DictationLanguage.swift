extension Language {
    /// The language `text` was said in, of `candidates`: the one whose lexicon knows its words best, each word scored by
    /// how often the language says it. A word rarer than one in about 500 million, or unknown, scores the same in every
    /// language, so English's long tail of rare words weighs nothing against a lexicon that stops sooner. The first
    /// candidate keeps it unless another knows the words clearly better, so "ok" and "Super!" stay in the language you
    /// picked first. Addresses and numbers say nothing of a language, and a word with an apostrophe the lexicon lacks
    /// counts as what follows it ("c'est" as "est").
    public static func of(_ text: String, among candidates: [(language: Language, lexicon: Lexicon)]) -> Language {
        guard let first = candidates.first else { return .english }
        let words = text.split(whereSeparator: \.isWhitespace).filter { token in
            !token.contains { $0.isNumber || $0 == "@" || $0 == "/" }
                && !token.reversed().drop { !$0.isLetter }.contains(".")
        }.flatMap { token in
            let token = Array(token)
            return Words.ranges(in: token).map { Words.plain(String(token[$0]).lowercased()) }
        }
        let scores = candidates.map { _, lexicon in
            words.reduce(0.0) { total, word in
                let known =
                    lexicon.logProbability(of: word)
                    ?? word.lastIndex(of: "'").flatMap { lexicon.logProbability(of: word[word.index(after: $0)...]) }
                return total + max(known ?? rarest, rarest)
            }
        }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[best] - scores[0] >= margin else {
            return first.language
        }
        return candidates[best].language
    }

    /// The log probability, in nats, of the rarest word that counts.
    private static let rarest = -20.0
    /// How much better, in nats, another language must know the words than the first candidate does.
    private static let margin = 3.0
}

extension KeyboardSettings {
    /// The languages a dictation may be in: the ones you type, in the order picked, then English.
    public var dictationLanguages: [Language] {
        (languages + [.english]).uniqued
    }
}
