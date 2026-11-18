public enum KeyboardLayer: Hashable, Sendable, CaseIterable {
    case letters, numbers, symbols
}

public enum KeyAction: Hashable, Sendable {
    case character(String)
    case space
    case delete
    case shift
    case capsLock
    case `return`
    case tab
    case layer(KeyboardLayer)
    case nextKeyboard
    /// The globe as Settings › Layout › Globe Key's Spacer draws it: dimmed, taking taps and doing nothing, so it keeps
    /// `123` in from the corner while Next Keyboard is in the menu.
    case globeSpacer
    /// The record button, in the globe's place where Settings puts it there: the keyboard's mic, which draws and
    /// handles it, so the engine never sees it.
    case dictate
    case dismiss
    /// An iPad's undo and redo keys on its number layers, for what the keyboard wrote (`EditHistory`).
    case undo, redo
    /// Opens the emoji panel, or closes it when it's open.
    case emoji
    /// The snippet key beside space, which starts a keyword: it types the snippet prefix at a word's start, so the bar
    /// offers the keywords that go on from it (`KeyboardSettings.snippetPrefix`).
    case snippetPrefix(String)
}

public enum KeyWidth: Hashable, Sendable {
    case input
    case pitch(Double)
    case fill

    public var span: Double? {
        switch self {
        case .input: 1
        case .pitch(let value): value
        case .fill: nil
        }
    }
}

public struct Key: Hashable, Sendable {
    public var action: KeyAction
    public var width: KeyWidth
    public var alternates: [String]
    public var secondary: String?
    public var isPair: Bool
    /// What shift types where it isn't the capital, as French's ’ key types ´ on an iPhone.
    public var shifted: String?
    /// Its accents wait for the next letter and land on it, ´ then e typing é, as Apple's accent keys do
    /// (`Accent.compose`).
    public var isDeadKey = false
    /// It accents the vowel before it instead, types ’ after any other letter and ´ anywhere else, as French's ’ key
    /// does on Apple's iPhone keyboard, shifted or not (`Accent.before`).
    public var accentsLetterBefore = false
    /// The long press's choice it opens on, when that isn't the key's own character: a number hint's digit, or .com on
    /// the period of an address. Letting go without sliding types it.
    public var holdPick: String?

    public init(
        _ action: KeyAction, width: KeyWidth = .input, alternates: [String] = [], secondary: String? = nil,
        isPair: Bool = false
    ) {
        self.action = action
        self.width = width
        self.alternates = alternates
        self.secondary = secondary
        self.isPair = isPair
    }

    public static func character(_ value: String, alternates: [String] = [], secondary: String? = nil) -> Key {
        Key(.character(value), alternates: alternates, secondary: secondary)
    }

    public func text(shifted: Bool, flicked: Bool = false) -> String? {
        guard case .character(let value) = action else { return nil }
        if flicked, let secondary { return secondary }
        if shifted, let shifted = self.shifted { return shifted }
        if shifted, isPair, let secondary { return secondary }
        return value
    }

    public var isInput: Bool {
        switch action {
        case .character, .space: true
        default: false
        }
    }
}

public enum RowItem: Hashable, Sendable {
    case key(Key)
    case spacer(KeyWidth)

    public var width: KeyWidth {
        switch self {
        case .key(let key): key.width
        case .spacer(let width): width
        }
    }
}

public struct KeyboardLayout: Hashable, Sendable {
    public var rows: [[RowItem]]
    /// How many of the top rows are short ones, 0.8 of a key: the number row.
    public var shortRows: Int
    /// Keys more than the device's usual rows hold, as Swedish's å and ä: Apple narrows every key to fit them.
    public var extraColumns: Double

    public init(rows: [[RowItem]], shortRows: Int = 0, extraColumns: Double = 0) {
        self.rows = rows
        self.shortRows = shortRows
        self.extraColumns = extraColumns
    }

    public var keys: [Key] {
        rows.flatMap { $0.compactMap { if case .key(let key) = $0 { key } else { nil } } }
    }
}
