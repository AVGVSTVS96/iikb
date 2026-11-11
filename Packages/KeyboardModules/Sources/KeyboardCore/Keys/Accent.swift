/// The accents Apple's accent keys hold for the next letter, and what they make of it.
public enum Accent {
    /// Each accent as it's typed, and the mark it puts on a letter.
    public static let marks: [String: String] = [
        "´": "\u{301}", "`": "\u{300}", "^": "\u{302}", "¨": "\u{308}", "~": "\u{303}",
    ]

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
}
