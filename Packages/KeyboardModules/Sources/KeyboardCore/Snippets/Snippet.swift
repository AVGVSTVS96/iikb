/// A text you keep to type again, as Raycast's are: by its keyword, typed at a word's start in any app
/// (`TypingEngine`'s expansion), or picked in the keyboard's Snippets panel. Its text is a `Template`.
public struct Snippet: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var text: String
    /// What becomes the snippet when typed, prefix and all ("!addr"); empty for none.
    public var keyword: String
    public var tag: String

    public init(id: String = Snippet.newID(), name: String, text: String, keyword: String = "", tag: String = "") {
        self.id = id
        self.name = name
        self.text = text
        self.keyword = keyword
        self.tag = tag
    }

    public init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword) ?? ""
        tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? ""
    }

    /// 128 random bits in hex, an id no other snippet or quicklink has.
    public static func newID() -> String {
        (0..<2).map { _ in
            let hex = String(UInt64.random(in: .min ... .max), radix: 16)
            return String(repeating: "0", count: 16 - hex.count) + hex
        }.joined()
    }

    /// Whether `typed` is this snippet's keyword, as auto-capitalization may have changed its case.
    public func isKeyword(_ typed: some StringProtocol) -> Bool {
        !keyword.isEmpty && typed.lowercased() == keyword.lowercased()
    }

    /// The snippets whose keywords go on from what you've typed of one, the one it spells first, then the shortest.
    public static func completing(_ typed: some StringProtocol, in snippets: [Snippet]) -> [Snippet] {
        let typed = typed.lowercased()
        return snippets.filter { !$0.keyword.isEmpty && $0.keyword.lowercased().hasPrefix(typed) }.sorted {
            ($0.keyword.count, $0.keyword.lowercased()) < ($1.keyword.count, $1.keyword.lowercased())
        }
    }

    /// Whether a keyword may start right after `character`: at the text's start, after a space, a line break or an
    /// opener, never inside a word.
    static func startsWord(after character: Character?) -> Bool {
        character.map { $0.isWhitespace || Words.openers.contains($0) } ?? true
    }
}

/// A link you keep, typed by a tap in the keyboard's Quicklinks panel or opened from it, as Raycast's are. Its link is a
/// `Template`, whose arguments are asked for first and percent-encoded into it.
public struct Quicklink: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var link: String

    public init(id: String = Snippet.newID(), name: String, link: String) {
        self.id = id
        self.name = name
        self.link = link
    }
}

/// How a snippet's keyword you type becomes its text: as soon as its last character is typed, once a space, return or
/// punctuation follows it (which stays after the snippet), or never, leaving the Snippets panel and the bar.
public enum SnippetExpansion: String, CaseIterable, Hashable, Sendable {
    case immediately, afterDelimiter, off

    public var title: String {
        switch self {
        case .immediately: "Immediately"
        case .afterDelimiter: "After Delimiter"
        case .off: "Off"
        }
    }
}
