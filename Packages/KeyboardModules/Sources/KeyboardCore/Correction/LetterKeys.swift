/// The letters taps are read as on a grid, and the key that holds each, so a tap on a key is evidence for every letter
/// it holds. They're the lexicon's letters, in its order, then any letter a key shows that its words never use, which
/// you can still type. A letter with no key of its own is the long-press's under it, so a tap on n can mean ñ and the
/// lexicon chooses ("espanol" → "español", "uber" → "über"); no language needs a table of accents.
struct LetterKeys {
    let lexicon: Lexicon
    let grid: KeyGrid
    let letters: [String]
    /// Each letter's key, by its place among `letters`; nil when no key holds it.
    let keys: [String?]
    private let shown: [Character: Int]

    init(_ lexicon: Lexicon, on grid: KeyGrid) {
        self.lexicon = lexicon
        self.grid = grid
        let faces = grid.rows.flatMap { $0.compactMap { $0.key.label?.lowercased() } }
            .filter { $0.count == 1 && $0.first!.isLetter && lexicon.index(of: $0.first!) == nil }
        let shown = Set(faces).sorted()
        letters = lexicon.letters + shown
        keys = letters.map(grid.key(holding:))
        self.shown = Dictionary(
            uniqueKeysWithValues: shown.enumerated().map { (Character($1), lexicon.letters.count + $0) })
    }

    /// A character's place among `letters`, either case.
    func place(of character: Character) -> Int? {
        if let index = lexicon.index(of: character) { return Int(index) }
        let lower = character.lowercased()
        return lower.count == 1 ? shown[Character(lower)] : nil
    }

    /// The word's letters, by place, or nil when one isn't among `letters`.
    func places(of word: String) -> [Int]? {
        var places: [Int] = []
        for character in word {
            guard let place = place(of: character) else { return nil }
            places.append(place)
        }
        return places
    }

    /// The key of the character typed, the space's included.
    func key(of character: Character) -> String? {
        if character == " " { return " " }
        return place(of: character).flatMap { keys[$0] }
    }

    /// How likely each key is next, from how likely each letter is (`LanguageModel.next`): a key's odds are those of
    /// every letter it holds.
    func keyOdds(_ next: [String: Double]) -> [String: Double] {
        var odds: [String: Double] = [:]
        if let space = next[" "] { odds[" "] = space }
        for (letter, key) in zip(letters, keys) {
            guard let key, let p = next[letter] else { continue }
            odds[key, default: 0] += p
        }
        return odds
    }
}

extension KeyGrid {
    /// The key that holds `letter`: the one showing it, or else the one it's under on a long-press. A tap there is
    /// evidence for it, and is learned as that key's.
    public func key(holding letter: String) -> String? {
        if index(of: letter) != nil { return letter }
        for row in rows {
            for item in row where item.key.alternates.contains(letter) {
                if let label = item.key.label { return label }
            }
        }
        return nil
    }
}
