/// How far a dictation's words go toward texting, as steps on one scale, each taking every swap of the steps before
/// it: Spelled Out keeps the words; Abbreviated writes the phrases people type as letters ("by the way" btw, "I don't
/// know" idk); Texting also shortens single words ("you" u, "tonight" tn, "later" l8r) in lowercase; Gen Z also
/// trades words for its slang ("amazing" fire, "for real" fr). Each swap means the same wherever it lands, so a word
/// with other senses ("kind of", "great", "going to") is swapped only in a phrase that pins it down. A phrase is swapped
/// only as whole words with nothing but spaces between them, the longest first, and a later step's swap over an
/// earlier one's.
public enum DictationTextMode: String, CaseIterable, Hashable, Sendable {
    case spelledOut
    case abbreviated
    case texting
    case genZ

    public static let standard = DictationTextMode.spelledOut

    /// Texting and Gen Z are typed in lowercase, whatever the style.
    var lowercases: Bool { self == .texting || self == .genZ }

    func swapped(_ text: [Character]) -> [Character] {
        let table: [(String, String)] =
            switch self {
            case .spelledOut: []
            case .abbreviated: Self.abbreviatedSwaps
            case .texting: Self.textingSwaps + Self.abbreviatedSwaps
            case .genZ: Self.genZSwaps + Self.textingSwaps + Self.abbreviatedSwaps
            }
        let replies = self == .genZ ? Self.genZReplies : []
        guard !table.isEmpty else { return text }
        let phrases = (replies.map { ($0, true) } + table.map { ($0, false) }).map { swap, alone in
            (words: swap.0.split(separator: " ").map(String.init), with: Array(swap.1), alone: alone)
        }
        let words = Words.ranges(in: text)
        var out: [Character] = []
        var copied = 0
        var at = 0
        while at < words.count {
            let found = phrases.filter { Self.matches($0.words, in: text, words: words, from: at, alone: $0.alone) }
            guard let phrase = found.max(by: { $0.words.count < $1.words.count }) else {
                at += 1
                continue
            }
            out += text[copied..<words[at].lowerBound] + phrase.with
            copied = words[at + phrase.words.count - 1].upperBound
            at += phrase.words.count
        }
        return out + text[copied...]
    }

    /// Whether `phrase` is said starting at `words[from]`, and when `alone`, with no word going on from it.
    private static func matches(_ phrase: [String], in text: [Character], words: [Range<Int>], from: Int, alone: Bool)
        -> Bool
    {
        guard from + phrase.count <= words.count else { return false }
        if alone, from + phrase.count < words.count,
            text[words[from + phrase.count - 1].upperBound..<words[from + phrase.count].lowerBound].allSatisfy(
                \.isWhitespace)
        {
            return false
        }
        for (offset, word) in phrase.enumerated() {
            let range = words[from + offset]
            guard Words.plain(String(text[range])).lowercased() == word else { return false }
            if offset > 0, text[words[from + offset - 1].upperBound..<range.lowerBound] != [" "] { return false }
        }
        return true
    }

    private static let abbreviatedSwaps = [
        ("by the way", "btw"), ("to be honest", "tbh"), ("i don't know", "idk"), ("i do not know", "idk"),
        ("right now", "rn"), ("on my way", "omw"), ("in my opinion", "imo"), ("as soon as possible", "asap"),
        ("for your information", "fyi"), ("let me know", "lmk"), ("oh my god", "omg"), ("oh my gosh", "omg"),
        ("never mind", "nvm"), ("talk to you later", "ttyl"), ("be right back", "brb"), ("for what it's worth", "fwiw"),
        ("in real life", "irl"), ("laughing out loud", "lol"), ("not gonna lie", "ngl"), ("not going to lie", "ngl"),
        ("what are you doing", "wyd"), ("how about you", "hbu"), ("i love you", "ily"),
    ]

    private static let textingSwaps = [
        ("you", "u"), ("your", "ur"), ("you're", "ur"), ("are", "r"), ("tonight", "tn"), ("later", "l8r"),
        ("tomorrow", "tmrw"), ("please", "pls"), ("thanks", "thx"), ("thank you", "ty"), ("because", "bc"),
        ("people", "ppl"), ("probably", "prob"), ("message", "msg"), ("before", "b4"), ("see you later", "cya l8r"),
        ("see you soon", "cya soon"), ("okay", "ok"), ("with", "w/"), ("without", "w/o"), ("something", "smth"),
        ("definitely", "def"), ("really", "rly"), ("what's up", "wassup"), ("want to", "wanna"),
    ]

    private static let genZSwaps = [
        ("for real", "fr"), ("no lie", "no cap"),
        ("really amazing", "highkey fire"), ("really good", "highkey good"), ("really excited", "highkey hyped"),
        ("an amazing", "a fire"), ("an awesome", "a fire"), ("amazing", "fire"), ("awesome", "fire"),
        ("that's great", "that's fire"), ("delicious", "bussin"), ("mediocre", "mid"), ("excited", "hyped"),
        ("you guys", "y'all"), ("showing off", "flexing"), ("obviously", "obvi"),
    ]

    /// Replies that mean what they say only as a whole sentence: "that's so funny you mention it" stays.
    private static let genZReplies = [
        ("i'm serious", "no cap"), ("that's hilarious", "i'm dead 💀"), ("that's so funny", "i'm dead 💀"),
        ("that's embarrassing", "that's cringe"), ("that's suspicious", "that's sus"),
    ]
}
