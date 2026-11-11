/// A word list with frequencies, stored as a flat trie in one run of bytes, read in place without parsing. It carries
/// its own letters, up to 255, so one format serves every alphabet: the engine reads with the letters of the lexicon
/// in use.
///
/// Layout: `HXL2`, the node count, the letters' byte count, the letters (UTF-8, lowercase, in order, a line each),
/// zeros to a multiple of 8 bytes, then 8 bytes per node, children of a node contiguous and in order: letter (its
/// place among the letters), word log-probability, subtree log-mass, flags (last sibling, capitalized), first child
/// index.
/// Probabilities are stored as `-ln p` in tenths of a nat (0 means "not a word").
public final class Lexicon: Sendable {
    public let bytes: Bytes
    /// The letters its words are spelled with, lowercase, in the order its nodes number them.
    public let letters: [String]
    /// The apostrophe's place among the letters, if its words have one: a contraction's apostrophe may go untyped.
    let apostrophe: UInt8?
    /// Where the first node starts.
    let nodes: Int
    private let nodeCount: Int
    private let ascii: [UInt8]
    private let others: [Character: UInt8]

    static let header: [UInt8] = Array("HXL2".utf8)
    /// A letter is one byte in a node.
    static let mostLetters = 255

    public init?(bytes: Bytes) {
        guard bytes.count >= 16, Array(bytes[0..<4]) == Self.header else { return nil }
        let count = Self.u32(bytes, at: 4)
        let length = Self.u32(bytes, at: 8)
        let start = (12 + length + 7) / 8 * 8
        guard start + count * 8 <= bytes.count else { return nil }
        let letters = String(decoding: bytes[12..<(12 + length)], as: UTF8.self).split(separator: "\n").map(String.init)
        guard letters.count <= Self.mostLetters else { return nil }
        var ascii = [UInt8](repeating: UInt8(Self.mostLetters), count: 128)
        var others: [Character: UInt8] = [:]
        for (index, letter) in letters.enumerated() {
            for form in [letter, letter.uppercased()] where form.count == 1 {
                let character = Character(form)
                if let value = character.asciiValue {
                    ascii[Int(value)] = UInt8(index)
                } else {
                    others[character] = UInt8(index)
                }
            }
        }
        self.bytes = bytes
        self.letters = letters
        self.nodes = start
        self.nodeCount = count
        self.ascii = ascii
        self.others = others
        apostrophe = letters.firstIndex(of: "'").map(UInt8.init)
    }

    public convenience init?(bytes: [UInt8]) {
        self.init(bytes: Bytes(bytes))
    }

    private static func u32(_ bytes: Bytes, at offset: Int) -> Int {
        (0..<4).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
    }

    public var wordCount: Int {
        (0..<nodeCount).count { logWord(Node($0, at: nodes)) != nil }
    }

    struct Node: Hashable {
        let index: Int
        let offset: Int
        init(_ index: Int, at nodes: Int) {
            self.index = index
            offset = nodes + index * 8
        }
    }

    var root: Node { Node(0, at: nodes) }

    /// A character's place among the letters, either case.
    func index(of character: Character) -> UInt8? {
        if let value = character.asciiValue {
            let index = ascii[Int(value)]
            return index == Self.mostLetters ? nil : index
        }
        if let index = others[character] { return index }
        let lower = character.lowercased()
        return lower.count == 1 ? others[Character(lower)] : nil
    }

    func letter(_ node: Node) -> UInt8 { bytes[node.offset] }

    func logWord(_ node: Node) -> Double? {
        let q = bytes[node.offset + 1]
        return q == 0 ? nil : -Double(q) / 10
    }

    func logMass(_ node: Node) -> Double { -Double(bytes[node.offset + 2]) / 10 }

    func isCapitalized(_ node: Node) -> Bool { bytes[node.offset + 3] & 2 != 0 }

    func children(_ node: Node) -> Children {
        let o = node.offset + 4
        let first = Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24
        return Children(lexicon: self, first: first)
    }

    func child(_ node: Node, _ letter: UInt8) -> Node? {
        children(node).first { self.letter($0) == letter }
    }

    func node(for word: some StringProtocol) -> Node? {
        var node = root
        for character in word {
            guard let letter = index(of: character), let next = child(node, letter) else { return nil }
            node = next
        }
        return node
    }

    /// The letters' places, spelled out.
    func spelling(_ letters: some Sequence<UInt8>) -> String {
        letters.reduce(into: "") { $0 += self.letters[Int($1)] }
    }

    public func logProbability(of word: some StringProtocol) -> Double? {
        node(for: word).flatMap(logWord)
    }

    /// The word as the lexicon spells it ("I'm" for "im"), if it is one.
    public func canonical(_ word: some StringProtocol) -> String? {
        guard let node = node(for: word), logWord(node) != nil else { return nil }
        let lower = String(word).lowercased()
        return isCapitalized(node) ? lower.prefix(1).uppercased() + lower.dropFirst() : lower
    }

    struct Children: Sequence, IteratorProtocol {
        let lexicon: Lexicon
        var upcoming: Int

        init(lexicon: Lexicon, first: Int) {
            self.lexicon = lexicon
            self.upcoming = first
        }

        mutating func next() -> Node? {
            guard upcoming != 0 else { return nil }
            let node = Node(upcoming, at: lexicon.nodes)
            upcoming = lexicon.bytes[node.offset + 3] & 1 != 0 ? 0 : upcoming + 1
            return node
        }
    }
}

extension Lexicon {
    /// Builds a lexicon from word counts, in any alphabet: its letters are the ones its words are spelled with. A word
    /// is letters and apostrophes (’ is read as '); anything else is skipped. Words are folded to lowercase, keeping a
    /// leading capital ("I", "English", "Haus") when that's the only way it's given: a word given in lowercase at all
    /// is lowercase, so "essen" next to "Essen" stays as typed.
    public convenience init(counts: some Sequence<(word: String, count: Double)>) {
        let entries = counts.compactMap { entry -> (word: [String], capital: Bool, count: Double)? in
            let word = Words.plain(entry.word)
            guard entry.count > 0, !word.isEmpty,
                word.allSatisfy({ ($0.isLetter || $0 == "'") && $0.lowercased().count == 1 })
            else { return nil }
            return (word.map { $0.lowercased() }, word.first?.isUppercase == true, entry.count)
        }
        let letters = Set(entries.flatMap(\.word)).sorted()
        precondition(letters.count <= Self.mostLetters, "a lexicon holds at most \(Self.mostLetters) letters")
        let places = Dictionary(uniqueKeysWithValues: letters.enumerated().map { ($1, UInt8($0)) })
        let total = entries.reduce(0) { $0 + $1.count }
        let root = Building()
        for (word, capital, count) in entries {
            var node = root
            let p = count / total
            node.mass += p
            for letter in word {
                let place = places[letter]!
                let next = node.children[place] ?? Building()
                node.children[place] = next
                node = next
                node.mass += p
            }
            node.probability += p
            if capital { node.capital = true } else { node.lowercase = true }
        }

        func quantize(_ p: Double) -> UInt8 {
            p <= 0 ? 0 : UInt8(min(max((-Math.log(p) * 10).rounded(), 1), 255))
        }
        var order: [(node: Building, letter: UInt8, last: Bool)] = [(root, 0, true)]
        var firstChild: [Int] = []
        var cursor = 0
        while cursor < order.count {
            let node = order[cursor].node
            let children = node.children.keys.sorted()
            firstChild.append(children.isEmpty ? 0 : order.count)
            for (i, letter) in children.enumerated() {
                order.append((node.children[letter]!, letter, i == children.count - 1))
            }
            cursor += 1
        }
        func u32(_ value: Int) -> [UInt8] {
            stride(from: 0, to: 32, by: 8).map { UInt8(truncatingIfNeeded: value >> $0) }
        }
        let spelled = Array(letters.joined(separator: "\n").utf8)
        var bytes = Self.header + u32(order.count) + u32(spelled.count) + spelled
        bytes += [UInt8](repeating: 0, count: (8 - bytes.count % 8) % 8)
        for (index, entry) in order.enumerated() {
            let capitalized = entry.node.capital && !entry.node.lowercase
            let flags: UInt8 = (entry.last ? 1 : 0) | (capitalized ? 2 : 0)
            bytes += [entry.letter, quantize(entry.node.probability), quantize(min(entry.node.mass, 1)), flags]
            bytes += u32(firstChild[index])
        }
        self.init(bytes: bytes)!
    }
}

extension Lexicon: CandidateSource {
    public func isWord(_ word: String) -> Bool {
        logProbability(of: word) != nil
    }

    public func guesses(for word: TypedWord) -> [String] {
        Corrector(source: self).ranked(word).filter { !$0.isCompletion && !$0.isLiteral }.map(\.word)
    }

    public func completions(for prefix: String) -> [String] {
        mostFrequent(count: 3, startingWith: prefix).filter { $0.count > prefix.count }
    }

    public func mostFrequent(count: Int, startingWith prefix: String = "") -> [String] {
        guard let start = node(for: prefix) else { return [] }
        var heap = Heap<(node: Node, spelling: String, terminal: Bool)>()
        heap.push((start, prefix.lowercased(), false), priority: logMass(start))
        var words: [String] = []
        while words.count < count, let (node, spelling, terminal) = heap.pop() {
            if terminal {
                words.append(canonical(spelling) ?? "")
                continue
            }
            if let word = logWord(node) { heap.push((node, spelling, true), priority: word) }
            for child in children(node) {
                heap.push((child, spelling + letters[Int(letter(child))], false), priority: logMass(child))
            }
        }
        return words
    }
}

private final class Building {
    var children: [UInt8: Building] = [:]
    var probability = 0.0
    var mass = 0.0
    var capital = false
    var lowercase = false
}
