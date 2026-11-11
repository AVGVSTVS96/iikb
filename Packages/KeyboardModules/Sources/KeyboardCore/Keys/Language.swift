/// A language iikb types: its own name, and the letter layouts Apple's keyboard offers it with its own first. It's
/// code, so every language is listed and laid out with no download; its words are the download. Its currency isn't
/// its own: Apple's keyboard shows the region's whatever the language.
public struct Language: Sendable, Identifiable {
    /// Its ISO 639-1 code, as `KeyboardSettings.language` keeps it.
    public let id: String
    /// As it calls itself: Deutsch, Svenska.
    public let name: String
    /// What Apple's keyboard offers it, its own first.
    public let layouts: [LetterLayout]
    /// The layout `id` names (`KeyboardSettings.layout`), or the language's own where it offers none by that name.
    public func layout(_ id: String?) -> LetterLayout {
        layouts.first { $0.id == id } ?? layouts[0]
    }

    /// The language `id` names, or English for one iikb doesn't have.
    public static func named(_ id: String) -> Language {
        all.first { $0.id == id } ?? .english
    }

    public static let all: [Language] = [english, spanish, french, german, portuguese, italian, swedish]

    public static let english = Language(
        id: "en", name: "English", layouts: [.qwerty, .azerty, .qwertz])
    public static let spanish = Language(
        id: "es", name: "Español", layouts: [.spanish, .qwerty, .azerty, .qwertz])
    public static let french = Language(
        id: "fr", name: "Français", layouts: [.french, .azerty, .qwerty, .qwertz])
    public static let german = Language(
        id: "de", name: "Deutsch", layouts: [.german, .qwertz, .qwerty, .azerty])
    public static let portuguese = Language(
        id: "pt", name: "Português", layouts: [.qwerty, .azerty, .qwertz])
    public static let italian = Language(
        id: "it", name: "Italiano", layouts: [.qwerty, .azerty, .qwertz])
    public static let swedish = Language(
        id: "sv", name: "Svenska", layouts: [.swedish])
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

    /// Every layout some language offers.
    public static let all: [LetterLayout] = [qwerty, qwertz, azerty, spanish, french, german, swedish]

    public static let qwerty = LetterLayout(id: "qwerty", name: "QWERTY", rows: ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
    public static let qwertz = LetterLayout(id: "qwertz", name: "QWERTZ", rows: ["qwertzuiop", "asdfghjkl", "yxcvbnm"])
    public static let azerty = LetterLayout(id: "azerty", name: "AZERTY", rows: ["azertyuiop", "qsdfghjklm", "wxcvbn"])
    public static let spanish = LetterLayout(
        id: "spanish", name: "Spanish", rows: ["qwertyuiop", "asdfghjklñ", "zxcvbnm"])
    public static let french = LetterLayout(
        id: "french", name: "French", rows: ["azertyuiop", "qsdfghjklm", "wxcvbn'"])
    public static let german = LetterLayout(
        id: "german", name: "German", rows: ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"])
    public static let swedish = LetterLayout(
        id: "swedish", name: "Swedish", rows: ["qwertyuiopå", "asdfghjklöä", "zxcvbnm"])
}
