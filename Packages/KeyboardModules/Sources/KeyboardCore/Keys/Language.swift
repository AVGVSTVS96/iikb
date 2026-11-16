/// A language iikb types: its own name, and the letter layouts Apple's keyboard offers it with its own first. It's
/// code, so every language is listed and laid out with no download; its words are the download. Its currency isn't
/// its own: Apple's keyboard shows the region's whatever the language.
public struct Language: Sendable, Identifiable {
    /// Its ISO 639-1 code, as settings keep it.
    public let id: String
    /// As it calls itself: Deutsch, Svenska.
    public let name: String
    /// What Apple's keyboard offers it, its own first.
    public let layouts: [LetterLayout]
    /// What smart punctuation types for " and ', as Apple's keyboard does in it: the double quotes that open and
    /// close, then the single ones, the closing one also its apostrophe. French's hold a no-break space inside.
    public let quotes: [String]
    /// The language `id` names, or English for one iikb doesn't have.
    public static func named(_ id: String) -> Language {
        all.first { $0.id == id } ?? .english
    }

    public static let all: [Language] = [english, spanish, french, german, portuguese, italian, swedish]

    public static let english = Language(
        id: "en", name: "English", layouts: [.qwerty, .azerty, .qwertz, .dvorak, .colemak, .colemakDH, .workman],
        quotes: ["“", "”", "‘", "’"])
    public static let spanish = Language(
        id: "es", name: "Español", layouts: [.spanish, .qwerty, .azerty, .qwertz], quotes: ["“", "”", "‘", "’"])
    public static let french = Language(
        id: "fr", name: "Français", layouts: [.french, .azerty, .qwerty, .qwertz],
        quotes: ["«\u{A0}", "\u{A0}»", "‘", "’"])
    public static let german = Language(
        id: "de", name: "Deutsch", layouts: [.german, .qwertz, .qwerty, .azerty], quotes: ["„", "“", "‚", "‘"])
    public static let portuguese = Language(
        id: "pt", name: "Português", layouts: [.qwerty, .azerty, .qwertz], quotes: ["“", "”", "‘", "’"])
    public static let italian = Language(
        id: "it", name: "Italiano", layouts: [.qwerty, .azerty, .qwertz], quotes: ["“", "”", "‘", "’"])
    public static let swedish = Language(
        id: "sv", name: "Svenska", layouts: [.swedish], quotes: ["”", "”", "’", "’"])
}

extension Language: Hashable {
    public static func == (a: Language, b: Language) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The letters' rows of one of Apple's layouts, top to bottom, on an iPhone.
public struct LetterLayout: Hashable, Sendable, Identifiable {
    /// As `KeyboardSettings.layout` keeps it.
    public let id: String
    /// As Apple's Settings names it.
    public let name: String
    public let rows: [String]
    /// What shift types on a key where it isn't the capital.
    public var shifted: [String: String] = [:]
    /// Shift and delete narrow with the letters of a longer row, as Swedish's do on an iPhone; German's keep English's.
    public var narrowsShift = false
    /// Delete ends the top row and the bottom row's letters run to the edge, as on Apple's Dvorak.
    public var deleteOnTop = false

    /// Every layout some language offers.
    public static let all: [LetterLayout] = [
        qwerty, qwertz, azerty, spanish, french, german, swedish, dvorak, colemak, colemakDH, workman,
    ]

    public static let qwerty = LetterLayout(id: "qwerty", name: "QWERTY", rows: ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
    public static let qwertz = LetterLayout(id: "qwertz", name: "QWERTZ", rows: ["qwertzuiop", "asdfghjkl", "yxcvbnm"])
    public static let azerty = LetterLayout(id: "azerty", name: "AZERTY", rows: ["azertyuiop", "qsdfghjklm", "wxcvbn"])
    public static let spanish = LetterLayout(
        id: "spanish", name: "Spanish", rows: ["qwertyuiop", "asdfghjklñ", "zxcvbnm"])
    public static let french = LetterLayout(
        id: "french", name: "French", rows: ["azertyuiop", "qsdfghjklm", "wxcvbn'"], shifted: ["'": "´"])
    public static let german = LetterLayout(
        id: "german", name: "German", rows: ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"])
    public static let swedish = LetterLayout(
        id: "swedish", name: "Swedish", rows: ["qwertyuiopå", "asdfghjklöä", "zxcvbnm"], narrowsShift: true)
    /// Apple's English Dvorak.
    public static let dvorak = LetterLayout(
        id: "dvorak", name: "Dvorak", rows: ["pyfgcrl", "aoeuidhtns", "qjkxbmwvz"], deleteOnTop: true)
    /// Apple has none of the next three, so each is its letters on Apple's keys, as Raycast's are: what the layout puts
    /// on a desk keyboard's letter keys, each row in its place.
    public static let colemak = LetterLayout(
        id: "colemak", name: "Colemak", rows: ["qwfpgjluy", "arstdhneio", "zxcvbkm"])
    public static let colemakDH = LetterLayout(
        id: "colemakdh", name: "Colemak-DH", rows: ["qwfpbjluy", "arstgmneio", "zxcdvkh"])
    public static let workman = LetterLayout(
        id: "workman", name: "Workman", rows: ["qdrwbjfup", "ashtgyneoi", "zxmcvkl"])
}

extension Sequence where Element: Equatable {
    /// Each element once, where it first comes.
    var uniqued: [Element] {
        reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
