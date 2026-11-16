/// P(word | previous word), from the lexicon and what you've typed.
///
/// Every level backs off to the next with Witten-Bell weights, which come from the counts themselves (a context
/// seen N times with T different words trusts itself N / (N + T)): your next-word counts → your word counts → the
/// lexicon → a word the lexicon doesn't know, spelled letter by letter from the lexicon's letters. Each word's count
/// in a context gives `discount` to the level below (absolute discounting), since a word seen there once is mostly
/// chance and shouldn't outrank a word the level below knows far better. How often you keep new words is itself
/// learned: (new + 1) / (all + 2), Laplace's rule of succession.
struct LanguageModel {
    let lexicon: Lexicon
    let memory: TypingMemory
    let novelty: Double
    let app: AppWords?
    /// The letters a word the lexicon doesn't know is spelled with: its own, and any a key shows (`LetterKeys`).
    let letters: [String]
    /// ln P(each letter) of such a word.
    let spellingLogProbability: Double
    /// With several languages typed, each one's own words and how likely the next word is in it (`Corrector.shares`);
    /// `lexicon` then holds the words of them all, and a word is as likely as the languages make it, each by its share.
    let among: [(lexicon: Lexicon, share: Double)]
    /// Which of `among` the network reads the words before as. The others' words come as often as they are.
    let speaking: Int?

    static let discount = 0.5

    /// `novel` is `novel(in:lexicon:)`, when the caller keeps it counted.
    init(
        lexicon: Lexicon, memory: TypingMemory, novel: Int? = nil, app: AppWords? = nil, letters: [String]? = nil,
        among: [(lexicon: Lexicon, share: Double)] = [], speaking: Int? = nil
    ) {
        self.app = app
        self.among = among
        self.speaking = speaking
        self.lexicon = lexicon
        self.memory = memory
        self.letters = letters ?? lexicon.letters
        spellingLogProbability = -Math.log(Double(self.letters.count))
        let novel = novel ?? Self.novel(in: memory, lexicon: lexicon)
        novelty = (Double(novel) + 1) / (Double(memory.total) + 2)
    }

    /// How many of the words you've typed the lexicon doesn't know.
    static func novel(in memory: TypingMemory, lexicon: Lexicon) -> Int {
        memory.counts.reduce(0) { $0 + (lexicon.logProbability(of: $1.key) == nil ? $1.value : 0) }
    }

    func logProbability(_ word: String, after previous: String?) -> Double {
        Math.log(probability(word, after: previous, earlier: nil, over: unigram(word)))
    }

    /// The same for the word you'll type next, after both words before it, with what the network `expected` from the
    /// text before under your next-word counts. Corrections leave the network out: its vocabulary is the corpus's
    /// commonest words, so it would push the rest down. Over the network your counts trust themselves N / (N + 8T):
    /// it reads the last 16 words where they read one or two, and on Bassim's own messages that weight ranks best.
    /// `previous` is "" at a sentence's start and nil when unknown; `earlier` is the word before it, read the same way.
    func predictor(after previous: String?, earlier: String?, expected: Network.Next?) -> (String) -> Double {
        { word in
            guard let expected else {
                return Math.log(probability(word, after: previous, earlier: earlier, over: unigram(word)))
            }
            let read =
                among.isEmpty
                ? expected.probability(of: word, below: unigram(word))
                : among.enumerated().reduce(0) { sum, language in
                    let below = unigram(word, lexical: lexical(word, in: language.element.lexicon))
                    let read = language.offset == speaking ? expected.probability(of: word, below: below) : below
                    return sum + language.element.share * read
                }
            return Math.log(probability(word, after: previous, earlier: earlier, over: read, trusting: 8))
        }
    }

    private func probability(
        _ word: String, after previous: String?, earlier: String?, over corpus: Double, trusting trust: Double = 1
    ) -> Double {
        var p = corpus
        for context in TypingMemory.contexts(previous, earlier) {
            let (count, total, types) = memory.count(of: word, after: context)
            let below = trust * Double(types)
            if total > 0 {
                p =
                    (max(Double(count) - Self.discount, 0) + (below + Self.discount * Double(types)) * p)
                    / (Double(total) + below)
            }
        }
        return app?.probability(of: word, after: previous, below: p) ?? p
    }

    private func unigram(_ word: String) -> Double {
        unigram(word, lexical: lexical(word))
    }

    /// A word as often as you've typed it, over how likely `p` its words make it.
    private func unigram(_ word: String, lexical p: Double) -> Double {
        guard memory.total > 0 else { return p }
        let types = Double(memory.counts.count)
        return (Double(memory.count(of: word)) + types * p) / (Double(memory.total) + types)
    }

    func lexical(_ word: String) -> Double {
        among.isEmpty ? lexical(word, in: lexicon) : among.reduce(0) { $0 + $1.share * lexical(word, in: $1.lexicon) }
    }

    /// How likely a word is as one of `lexicon`'s, or one it doesn't know.
    func lexical(_ word: String, in lexicon: Lexicon) -> Double {
        let known = lexicon.logProbability(of: word).map(Math.exp) ?? 0
        return (1 - novelty) * known + novelty * Math.exp(spellingLogProbability * Double(word.count + 1))
    }

    /// P(next letter | the letters so far), over the lexicon and novel spellings, and P(the word ends here) as `" "`.
    /// Before a word starts, `" "` is how often you type a second space, by the rule of succession. With several
    /// languages the letters are each one's by its share, so the key map leans to the language being written.
    func next(after prefix: String) -> [String: Double] {
        let length = Double(prefix.count)
        let words = (among.isEmpty ? [(lexicon: lexicon, share: 1.0)] : among).map {
            (lexicon: $0.lexicon, share: $0.share, node: $0.lexicon.node(for: prefix))
        }
        let novel = { (letters: Double) in novelty * Math.exp(spellingLogProbability * letters) }
        /// What the languages have, each by its share, of what `log` reads at its node for the prefix.
        func mass(_ log: (Lexicon, Lexicon.Node) -> Double?) -> Double {
            words.reduce(0) { sum, language in
                guard let node = language.node, let log = log(language.lexicon, node) else { return sum }
                return sum + language.share * (1 - novelty) * Math.exp(log)
            }
        }
        let total = mass { $0.logMass($1) } + novel(length)
        var result: [String: Double] = [:]
        for letter in letters {
            let under = mass { lexicon, node in
                letter.first.flatMap(lexicon.index(of:)).flatMap { lexicon.child(node, $0) }.map(lexicon.logMass)
            }
            result[letter] = (under + novel(length + 1)) / total
        }
        if prefix.isEmpty {
            let space = (Double(memory.spacesAfterSpace) + 1) / (Double(memory.keysAfterSpace) + 2)
            for (key, p) in result { result[key] = p * (1 - space) }
            result[" "] = space
        } else {
            result[" "] = (mass { $0.logWord($1) } + novel(length + 1)) / total
        }
        return result
    }
}
