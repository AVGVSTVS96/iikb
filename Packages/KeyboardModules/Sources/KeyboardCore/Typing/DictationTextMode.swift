/// How far a dictation's words go toward texting, as steps on one scale, each taking every swap of the steps before
/// it: Spelled Out keeps the words; Abbreviated writes the phrases people type as letters ("by the way" btw, "I don't
/// know" idk); Texting also shortens single words ("you" u, "tonight" tn, "later" l8r) in lowercase; Gen Z also
/// trades words for its slang ("really" highkey, "amazing" fire, "seriously" fr). A phrase is swapped only as whole
/// words with nothing but spaces between them, the longest first, and
/// a later step's swap over an earlier one's.
public enum DictationTextMode: String, CaseIterable, Hashable, Sendable {
    case spelledOut
    case abbreviated
    case texting
    case genZ

    public static let standard = DictationTextMode.spelledOut

    /// Texting and Gen Z are typed in lowercase, whatever the style.
    var lowercases: Bool { self == .texting || self == .genZ }

    func swapped(_ text: [Character]) -> [Character] {
        let table: [(String, String)] = switch self {
        case .spelledOut: []
        case .abbreviated: Self.abbreviatedSwaps
        case .texting: Self.textingSwaps + Self.abbreviatedSwaps
        case .genZ: Self.genZSwaps + Self.textingSwaps + Self.abbreviatedSwaps
        }
        guard !table.isEmpty else { return text }
        let phrases = table.map { (words: $0.0.split(separator: " ").map(String.init), with: Array($0.1)) }
        let words = Words.ranges(in: text)
        var out: [Character] = []
        var copied = 0
        var at = 0
        while at < words.count {
            let found = phrases.filter { Self.matches($0.words, in: text, words: words, from: at) }
            guard let phrase = found.max(by: { $0.words.count < $1.words.count }) else {
                at += 1
                continue
            }
            out += text[copied ..< words[at].lowerBound] + phrase.with
            copied = words[at + phrase.words.count - 1].upperBound
            at += phrase.words.count
        }
        return out + text[copied...]
    }

    /// Whether `phrase` is said starting at `words[from]`.
    private static func matches(_ phrase: [String], in text: [Character], words: [Range<Int>], from: Int) -> Bool {
        guard from + phrase.count <= words.count else { return false }
        for (offset, word) in phrase.enumerated() {
            let range = words[from + offset]
            guard Words.plain(String(text[range])).lowercased() == word else { return false }
            if offset > 0, text[words[from + offset - 1].upperBound ..< range.lowerBound] != [" "] { return false }
        }
        return true
    }

    private static let abbreviatedSwaps = [
        ("by the way", "btw"), ("to be honest", "tbh"), ("i don't know", "idk"), ("i do not know", "idk"),
        ("right now", "rn"), ("on my way", "omw"), ("in my opinion", "imo"), ("as soon as possible", "asap"),
        ("for your information", "fyi"), ("let me know", "lmk"), ("oh my god", "omg"), ("oh my gosh", "omg"),
        ("never mind", "nvm"), ("talk to you later", "ttyl"), ("be right back", "brb"), ("for what it's worth", "fwiw"),
        ("in real life", "irl"), ("laughing out loud", "lol"), ("not gonna lie", "ngl"), ("not going to lie", "ngl"),
        ("what are you doing", "wyd"), ("how about you", "hbu"), ("i love you", "ily"), ("good night", "gn"),
    ]

    private static let textingSwaps = [
        ("you", "u"), ("your", "ur"), ("you're", "ur"), ("are", "r"), ("tonight", "tn"), ("later", "l8r"),
        ("tomorrow", "tmrw"), ("please", "pls"), ("thanks", "thx"), ("thank you", "ty"), ("because", "bc"),
        ("people", "ppl"), ("probably", "prob"), ("message", "msg"), ("before", "b4"), ("see you", "cya"),
        ("okay", "ok"), ("with", "w/"), ("without", "w/o"), ("something", "smth"), ("definitely", "def"),
        ("really", "rly"), ("what's up", "wassup"), ("going to", "gonna"), ("want to", "wanna"),
    ]

    private static let genZSwaps = [
        ("for real", "fr"), ("seriously", "fr fr"), ("i'm serious", "no cap"), ("no lie", "no cap"),
        ("really", "highkey"), ("very", "highkey"), ("kind of", "lowkey"), ("kinda", "lowkey"), ("sort of", "lowkey"),
        ("amazing", "fire"), ("awesome", "fire"), ("great", "fire"), ("delicious", "bussin"), ("boring", "mid"),
        ("mediocre", "mid"), ("suspicious", "sus"), ("excited", "hyped"), ("embarrassing", "cringe"),
        ("that's hilarious", "i'm dead 💀"), ("that's so funny", "i'm dead 💀"), ("hilarious", "sending me 💀"),
        ("exactly", "facts"), ("i agree", "real"), ("friend", "bestie"), ("everyone", "y'all"), ("you guys", "y'all"),
        ("it looks like", "it's giving"), ("it seems like", "it's giving"), ("showing off", "flexing"),
        ("well done", "slay"), ("good job", "slay"), ("gossip", "tea"), ("obviously", "obvi"),
    ]
}
