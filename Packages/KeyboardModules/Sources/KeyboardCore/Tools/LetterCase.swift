/// Change Case's cases, as Raycast's (docs/design.md, "Change Case"). Styled letters keep their style (`TextStyle`),
/// but for snake_case and camelCase, which name things in code.
public enum LetterCase: CaseIterable, Hashable, Sendable {
    case upper, lower, sentence, title, snake, camel

    /// Each name is written in its case.
    public var name: String {
        switch self {
        case .upper: "UPPERCASE"
        case .lower: "lowercase"
        case .sentence: "Sentence case"
        case .title: "Title Case"
        case .snake: "snake_case"
        case .camel: "camelCase"
        }
    }

    public func apply(to text: String) -> String {
        switch self {
        case .upper: Self.cased(text, upper: true)
        case .lower: Self.cased(text, upper: false)
        case .sentence: Self.sentence(text)
        case .title: Self.title(text)
        case .snake: Self.lines(text) { $0.joined(separator: "_") }
        case .camel:
            Self.lines(text) { words in
                words.enumerated().map { $0 == 0 ? $1 : $1.prefix(1).uppercased() + $1.dropFirst() }.joined()
            }
        }
    }

    /// Words a title keeps small unless they start or end it.
    static let small: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "nor", "of", "on", "onto", "or", "per",
        "so", "the", "to", "up", "via", "vs", "with", "yet",
    ]

    private static func cased(_ text: some StringProtocol, upper: Bool) -> String {
        text.map { TextStyle.cased($0, upper: upper) }.joined()
    }

    /// Small letters, with a capital starting each sentence and line, and "I" kept where it stands alone as typed.
    private static func sentence(_ text: String) -> String {
        let characters = Array(text)
        func inWord(_ index: Int) -> Bool {
            characters.indices.contains(index) && (TextStyle.isLetter(characters[index]) || characters[index].isNumber)
        }
        var result = ""
        var starts = true
        var ended = false
        for (index, character) in characters.enumerated() {
            if TextStyle.isLetter(character) {
                let pronoun = TextStyle.plain(String(character)) == "I" && !inWord(index - 1) && !inWord(index + 1)
                result += TextStyle.cased(character, upper: starts || pronoun)
                (starts, ended) = (false, false)
                continue
            }
            result.append(character)
            if character.isNewline {
                starts = true
            } else if character.isWhitespace {
                starts = starts || ended
            } else {
                ended = ".!?".contains(character) || ended && "\"'”’)]»".contains(character)
                if character.isNumber { starts = false }
            }
        }
        return result
    }

    /// A capital starting each word but the small ones inside a line. A word with a capital already keeps its case
    /// (iPhone, NASA, OR), unless the whole text is capitals; a small word only capitalized (Of) is small again.
    private static func title(_ text: String) -> String {
        let shouting = !text.contains { TextStyle.cased($0, upper: true) != String($0) }
        let text = shouting ? cased(text, upper: false) : text
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            words(of: String(line)) { word, first, last in
                let bare = TextStyle.plain(cased(word.filter(TextStyle.isLetter), upper: false))
                let capitals = word.count(where: { TextStyle.cased($0, upper: false) != String($0) })
                if !first, !last, small.contains(bare), capitals <= 1 { return cased(word, upper: false) }
                if word.contains(where: { TextStyle.cased($0, upper: false) != String($0) }) { return String(word) }
                guard let letter = word.firstIndex(where: TextStyle.isLetter) else { return String(word) }
                return word[..<letter] + TextStyle.cased(word[letter], upper: true) + word[word.index(after: letter)...]
            }
        }.joined(separator: "\n")
    }

    /// The text with each run of non-space characters changed, told whether it's the first and the last.
    private static func words(of text: String, _ change: (Substring, Bool, Bool) -> String) -> String {
        let runs = text.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        var result = ""
        var index = text.startIndex
        for (place, run) in runs.enumerated() {
            result += text[index..<run.startIndex]
            result += change(run, place == 0, place == runs.count - 1)
            index = run.endIndex
        }
        return result + text[index...]
    }

    /// Each line as one name of its plain words, small letters, joined by `join`; a line with no letters or digits as
    /// it is.
    private static func lines(_ text: String, join: ([String]) -> String) -> String {
        TextStyle.plain(text).split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let parts = parts(of: line)
            return parts.isEmpty ? String(line) : join(parts.map { cased($0, upper: false) })
        }.joined(separator: "\n")
    }

    /// The words of a line: runs of letters and digits, split where a small letter meets a capital (camelCase) and
    /// before a capital that starts a word after capitals (HTTPServer). Apostrophes join a word's parts (don't).
    private static func parts(of line: Substring) -> [String] {
        var parts: [String] = []
        var part: [Character] = []
        let characters = Array(line.filter { !Words.apostrophes.contains($0) })
        for (index, character) in characters.enumerated() {
            guard character.isLetter || character.isNumber else {
                if !part.isEmpty { parts.append(String(part)) }
                part = []
                continue
            }
            if let last = part.last, character.isUppercase,
                last.isLowercase || last.isNumber
                    || last.isUppercase && index + 1 < characters.count && characters[index + 1].isLowercase
            {
                parts.append(String(part))
                part = []
            }
            part.append(character)
        }
        if !part.isEmpty { parts.append(String(part)) }
        return parts
    }
}
