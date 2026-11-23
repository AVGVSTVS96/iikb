public struct SessionLog: Codable, Sendable {
    public static let most = 20_000

    public var build = ""
    public internal(set) var steps: [Step] = []
    var isOpen = false
    var seen = Seen()

    public init(build: String = "") {
        self.build = build
    }

    private enum CodingKeys: String, CodingKey { case build, steps }

    public var isFull: Bool { steps.count >= Self.most }

    public struct Step: Codable, Sendable {
        public var input: Input
        public var setup: Setup?
        public var words: Words?
        public var reads: [Window]?
        public var edits: [Edit]?
        public var bar: Bar?

        public init(
            _ input: Input, setup: Setup? = nil, words: Words? = nil, reads: [Window]? = nil, edits: [Edit]? = nil,
            bar: Bar? = nil
        ) {
            self.input = input
            self.setup = setup
            self.words = words
            self.reads = reads
            self.edits = edits
            self.bar = bar
        }
    }

    public enum Input: Codable, Sendable {
        case event(KeyboardEvent)
        case action(KeyAction, tap: Tap?)
        case deleteWord
        case pick(Suggestion)
        case pickEmoji(String)
        case host
        case grid(KeyGrid)
        case traits(InputTraits)
        case app(String?)
        case endSession, finishWord, leaveField, ranked
    }

    public struct Window: Codable, Sendable, Hashable {
        public var before: String?
        public var selected: String?
        public var after: String?

        public init(before: String?, selected: String?, after: String?) {
            self.before = before
            self.selected = selected
            self.after = after
        }
    }

    public enum Edit: Codable, Sendable, Hashable {
        case delete(Int)
        case insert(String)
        case move(Int)
    }

    public struct Bar: Codable, Sendable, Hashable {
        public var words: [Suggestion]
        public var emoji: [String]
    }

    public struct Setup: Codable, Sendable, Hashable {
        public var settings: KeyboardSettings
        public var region: Region
        public var snippets: [Snippet]
        public var emoji: EmojiHistory
        public var emojiApp: String?
        public var skinTone: SkinTone?
        public var catalog: Bool
        public var swipe: Bool?
        public var defers: Bool
    }

    public struct Words: Codable, Sendable {
        public var lexicon: Model?
        public var network: Model?
        public var memory: TypingMemory
        public var names: [String: String]
        public var replacements: [String: String]
        public var app: String?
        public var grid: KeyGrid
    }

    public struct Model: Codable, Sendable, Hashable {
        public var size: Int
        public var personal: Bool

        public init(size: Int, personal: Bool = false) {
            self.size = size
            self.personal = personal
        }
    }

    struct Seen: Sendable {
        var setup: Setup?
        var corrector: ObjectIdentifier?
        var version = 0
        var bar: Bar?
    }

    mutating func note(read window: Window) {
        guard isOpen else { return }
        steps[steps.count - 1].reads = (steps[steps.count - 1].reads ?? []) + [window]
    }

    mutating func note(_ edit: Edit) {
        guard isOpen else { return }
        steps[steps.count - 1].edits = (steps[steps.count - 1].edits ?? []) + [edit]
    }
}

extension SessionLog.Window {
    init(_ document: some TextDocument) {
        before = document.textBeforeInput
        after = document.textAfterInput
        selected = document.selectedText
    }
}

extension TypingEngine {
    var setup: SessionLog.Setup {
        SessionLog.Setup(
            settings: settings, region: region, snippets: snippets, emoji: emojiHistory, emojiApp: emojiHistory.app,
            skinTone: emojiHistory.skinTone, catalog: emojiCatalog != nil, swipe: swipeModel?.decodes,
            defers: defersSuggestions)
    }

    var words: SessionLog.Words? {
        guard let corrector else { return nil }
        return SessionLog.Words(
            lexicon: corrector.lexicon.map { SessionLog.Model(size: $0.bytes.count) },
            network: corrector.network.map { SessionLog.Model(size: $0.bytes.count, personal: $0.personal) },
            memory: corrector.memory, names: corrector.names, replacements: corrector.replacements,
            app: corrector.app, grid: corrector.grid)
    }

    mutating func begins(_ input: SessionLog.Input) -> Bool {
        guard log?.isOpen == false, log?.isFull == false else { return false }
        let changed = corrector.map { ObjectIdentifier($0) != log?.seen.corrector || $0.version != log?.seen.version }
        let (setup, words) = (setup, changed == true ? words : nil)
        log?.begin(input, setup: setup, words: words)
        return true
    }

    mutating func ends() {
        let (setup, corrector) = (setup, corrector)
        let bar = suggestionsAreStale ? nil : SessionLog.Bar(words: suggestions, emoji: emojiSuggestions)
        log?.end(setup: setup, corrector: corrector, bar: bar)
    }
}

extension SessionLog {
    mutating func begin(_ input: Input, setup: Setup, words: Words?) {
        steps.append(Step(input, setup: setup == seen.setup ? nil : setup, words: words))
        isOpen = true
    }

    mutating func end(setup: Setup, corrector: Corrector?, bar: Bar?) {
        isOpen = false
        seen.setup = setup
        seen.corrector = corrector.map(ObjectIdentifier.init)
        seen.version = corrector?.version ?? 0
        guard let bar, bar != seen.bar else { return }
        steps[steps.count - 1].bar = bar
        seen.bar = bar
    }
}

extension Language: Codable {
    public init(from decoder: any Swift.Decoder) throws {
        self = .named(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

extension TextStyle: Codable {
    public init(from decoder: any Swift.Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let style = Self.all.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: name))
        }
        self = style
    }

    public func encode(to encoder: any Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

extension OneHanded: Codable {}
extension Panel: Codable {}
extension SkinTone: Codable {}
extension ThemeName: Codable {}
extension StopAnimation: Codable {}
extension ThemeAppearance: Codable {}
extension LeadingButton: Codable {}
extension BottomKey: Codable {}
extension DictationStyle: Codable {}
extension DictationLists: Codable {}
extension DictationEditing: Codable {}
extension DictationTextMode: Codable {}
extension SnippetExpansion: Codable {}
extension EmojiGrid: Codable {}
extension GlobeKey: Codable {}
extension ClipboardLength: Codable {}
extension CharacterPreview: Codable {}
extension HapticFeedback: Codable {}
extension KeySpacing: Codable {}
extension KeyRoundness: Codable {}
extension Currency: Codable {}
