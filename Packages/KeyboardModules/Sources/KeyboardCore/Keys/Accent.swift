/// The accents Apple's accent keys put on a letter, and what they make of it.
public enum Accent {
    /// Each accent as it's typed, and the mark it puts on a letter. Apple's accent keys type these, ˋ and ˆ rather than
    /// ` and ^, which a key types as they are, as German's ^ does on a 13-inch iPad.
    public static let marks: [String: String] = ["´": "\u{301}", "ˋ": "\u{300}", "ˆ": "\u{302}", "¨": "\u{308}"]

    /// The Latin letters that have an accent built in, each found by itself plus its mark, since Swift's strings match
    /// é to e and ◌́.
    private static let letters: [String: String] = Dictionary(
        (Array(0xC0...0x24F) + Array(0x1E00...0x1EFF)).compactMap(Unicode.Scalar.init).map { (String($0), String($0)) },
        uniquingKeysWith: { first, _ in first })

    /// `letter` with `accent` on it, é from ´ and e, or nil where no single letter has it, as ´ on q: there Apple types
    /// the accent and then the letter.
    public static func compose(_ accent: String, _ letter: String) -> String? {
        guard let mark = marks[accent], letter.count == 1 else { return nil }
        return letters[letter + mark]
    }

    /// What French's accent key on an iPhone makes of the vowel before it, as Apple's does: é, à, î, ô and û.
    public static func before(_ letter: Character) -> String? {
        let accented: [Character: String] = ["a": "à", "e": "é", "i": "î", "o": "ô", "u": "û"]
        guard let lower = String(letter).lowercased().first, let made = accented[lower] else { return nil }
        return letter.isUppercase ? made.uppercased() : made
    }
}
