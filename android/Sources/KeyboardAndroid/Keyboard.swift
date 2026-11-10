import FoundationEssentials
import KeyboardCore

/// iikb's keyboard on Android: `TypingEngine` and the keys it lays out, driven by the Kotlin input method the way
/// `FullKeyboardViewController` drives them on iOS. Kotlin owns the screen, touches and timers; this owns what they do.
final class Keyboard {
    var engine = TypingEngine()
    let document: HostDocument
    /// A chat's message line while one is open, which the keys type into in place of the app's field.
    var line: LineDocument?
    /// What the keys type into: the open chat's line, or the app's field.
    var typing: any TextDocument { line ?? document }
    /// What the sources you added are sent, and their hints.
    var sources = SourceFeeds()
    private var grid = KeyGrid()
    private var context: LayoutContext?
    private var geometry: KeyboardGeometry?
    private var offsets: [Int] = []
    private var screen = Size(width: 411, height: 914)
    private var width = 411.0
    private var bottom = 0.0
    private var dark = false
    private var showsGlobe = false
    private var folds = false
    /// What Kotlin's `IikbService` shows: the menu open, a chat open, and the keys up under a chat or panel.
    var shown = (menu: false, chat: false, keysUp: false)
    /// The bar shows More, which it leaves out while a chat with the keys up has its own beside its tabs.
    private var barMore: Bool { !(shown.chat && shown.keysUp) }
    /// Whether the keys are in sight, not under the menu or a chat or panel in their place: iOS's `placeMic`, which
    /// puts the one mic in the bar while they aren't, even with the Record Key on.
    private var keysShown: Bool {
        let panelOpen = shown.chat || engine.panel != nil
        let inPlace = panelOpen && !shown.keysUp && engine.panel != .emoji
        return !inPlace && !(shown.menu && !panelOpen)
    }
    private let style = KeyboardStyle.ios27
    private let emojiSearch: EmojiSearch

    init(document: HostDocument, lexicon: Lexicon?, network: Network?, swipe: Swipe?, emoji: String, search: String) {
        self.document = document
        emojiSearch = EmojiSearch(text: search)
        engine.defersSuggestions = true
        engine.corrector = lexicon.map { Corrector(source: $0, network: network) }
        engine.swipeModel = swipe
        engine.emojiCatalog = EmojiCatalog(text: emoji, search: emojiSearch)
        engine.settings = .initial
    }

    /// The room Android gives the keyboard, in dp: its width, the screen's size, and what the navigation bar takes
    /// under it, on a phone that `folds` or not.
    func place(width: Double, screen: Size, folds: Bool, bottom: Double, dark: Bool, showsGlobe: Bool) {
        self.width = width
        self.screen = screen
        self.folds = folds
        self.bottom = bottom
        self.dark = dark
        self.showsGlobe = showsGlobe
        render()
    }

    func configure(_ settings: String) {
        engine.settings = KeyboardSettings(parsing: settings)
        engine.emojiHistory.skinTone = engine.settings.skinTone
        engine.suggestionsChanged()
    }

    private var device: DeviceClass { DeviceClass(screen: screen, folds: folds) }

    private var theme: KeyboardTheme {
        KeyboardTheme.named(
            engine.settings.theme, appearance: engine.settings.themeAppearance, dark: dark, style: style)
    }

    func render() {
        let context = engine.layout(on: device, screen: screen, showsGlobe: showsGlobe)
        var geometry = KeyboardGeometry(context, screen: screen, window: width, style: style)
        geometry.metrics.toolbar = geometry.metrics.toolbar.showing(
            engine.panel, compact: engine.settings.compactPanels)
        geometry.metrics.bottomInset += bottom
        self.context = context
        self.geometry = geometry
        grid = KeyGrid(geometry.layout, width: width, metrics: geometry.metrics.grid, signature: context.signature)
        offsets = grid.rows.reduce(into: [0]) { $0.append($0.last! + $1.count) }
        engine.use(grid)
    }

    func frame() -> Frame {
        render()
        guard let geometry, let context else { fatalError("rendered above") }
        let theme = theme
        var metrics = geometry.metrics
        let topRow = grid.rows.first ?? []
        if let width = topRow.map(\.frame.width).min() {
            if let shape = theme.keyShape { metrics.cornerRadius = shape.cornerRadius(letterWidth: width) }
            metrics.cornerRadius = metrics.rounded(
                metrics.cornerRadius, key: Size(width: width, height: metrics.keyHeight))
        }
        let faces = engine.faces(on: context.device)
        let uppercase = faces.shift.isUppercase
        let swipes = engine.settings.slideToType && engine.panel == nil && faces.layer == .letters
        let caps = grid.rows.joined().map { key, frame in
            let face = KeyFace(key, trailing: frame.midX > width / 2, context: faces)
            let typed = key.text(shifted: uppercase)
            let paint =
                face.isProminent ? "prominent" : key.isInput ? "letter" : "function"
            return Cap(
                x: frame.x, y: frame.y, width: frame.width, height: frame.height,
                face: face.content.kind, label: face.content.value, secondary: face.secondary,
                secondaryDimmed: face.secondaryIsDimmed, corner: face.corner, align: face.alignment.name,
                prominent: face.isProminent, dimmed: face.isDimmed || key.action == .globeSpacer, paint: paint,
                action: key.action.name, isInput: key.isInput, typed: typed,
                flicked: key.text(shifted: uppercase, flicked: true).flatMap { $0 == typed ? nil : $0 },
                shown: typed.map { uppercase ? $0.uppercased() : $0 },
                alternates: key.alternates.map { uppercase ? $0.uppercased() : $0 },
                startsSwipe: swipes && key.label?.first?.isLetter == true
            )
        }
        let toolbar = metrics.toolbar
        let keyed = grid.rows.joined().contains { $0.key.action == .dictate }
        let tools: [Panel] = engine.settings.emojiKey && context.device != .phone ? [.emoji] : []
        let keys = topRow.map { (minX: $0.frame.x, maxX: $0.frame.x + $0.frame.width) }
        let bar = BarLayout(
            toolbar, keys: keys, tools: tools.count, more: barMore, mic: !(keyed && keysShown), maximumSlot: toolbar.slot)
        let menuKeys = context.menuKeys(in: geometry.layout)
        let items = context.menu
        return Frame(
            layout: grid.signature,
            width: width,
            height: geometry.metrics.height(
                rows: geometry.layout.rows.count, hasNumberRow: geometry.layout.hasNumberRow),
            toolbar: Bar(
                top: toolbar.top, bar: toolbar.bar, button: toolbar.button, glyph: toolbar.glyph,
                results: toolbar.results, field: toolbar.field, panelHeight: toolbar.panelHeight,
                compact: toolbar.isCompact, blockMinX: metrics.margin.leading + metrics.sideInset,
                blockMaxX: width - metrics.margin.trailing - metrics.sideInset, minX: bar.minX, maxX: bar.maxX,
                more: bar.more.map(Box.init), keysMinX: keys.first?.minX ?? 0, mic: bar.mic.map(Box.init),
                tools: bar.tools.map(Box.init),
                slots: bar.slots.map(Box.init), emoji: Box(bar.emoji), emojiBeside: bar.emojiBeside,
                cancel: Box(bar.cancel), recording: Box(bar.recording)),
            caps: caps,
            showsSuggestions: engine.showsSuggestions,
            chips: engine.suggestions.map { Chip(text: $0.title, kind: $0.kind.name) },
            emoji: engine.emojiSuggestions,
            look: Look(metrics, shape: theme.keyShape, style: style),
            theme: Theme(theme),
            menuKeys: grid.rows.joined().enumerated().compactMap { menuKeys.contains($1.key) ? $0 : nil },
            menu: items.map { MenuItem(symbol: $0.symbol, title: $0.title) },
            menuCurrent: items.firstIndex(of: context.menuPick),
            panel: engine.panel.map { "\($0)" },
            query: engine.query,
            uppercase: uppercase,
            expander: grid.expander.map {
                Expander(
                    x: $0.frame.x, y: $0.frame.y, width: $0.frame.width, height: $0.frame.height,
                    pointsRight: $0.pointsRight)
            }
        )
    }

    func resolve(x: Double, y: Double) -> Int {
        guard let index = engine.key(atX: x, y: y, in: grid) else { return -1 }
        return offsets[index.row] + index.key
    }

    func key(at index: Int) -> Key? {
        guard let row = offsets.lastIndex(where: { $0 <= index }), row < grid.rows.count,
            index - offsets[row] < grid.rows[row].count
        else { return nil }
        return grid.rows[row][index - offsets[row]].key
    }

    /// One of the hold menu's items, by its place in `Frame.menu`.
    func menuEvent(at index: Int) -> KeyboardEvent? {
        guard let items = context?.menu, items.indices.contains(index) else { return nil }
        return items[index]
    }

    @discardableResult
    func handle(_ event: KeyboardEvent) -> Bool {
        engine.handle(event, in: typing)
    }

    /// The emoji panel's results for its search: what you pick most, then every emoji, or what the search finds.
    func emojiResults() -> [String] {
        emojiSearch.search(engine.query, history: engine.emojiHistory)
    }

    /// The skin tones of an emoji the panel shows, for its hold.
    func tones(of emoji: String) -> [String] {
        let base = emojiSearch.base(of: emoji) ?? emoji
        return emojiSearch.tones[base].map { [base] + $0 } ?? []
    }

    func base(of emoji: String) -> String? { emojiSearch.base(of: emoji) }
}

extension KeyboardEvent {
    /// How the layer menu shows a pick, with the names of iikb's glyphs.
    var symbol: String {
        switch self {
        case .pick(.left): "keyboard.onehanded.left"
        case .pick(.right): "keyboard.onehanded.right"
        case .split(true): "rectangle.split.2x1"
        case .settings: "gearshape"
        case .nextKeyboard: "globe"
        default: "keyboard"
        }
    }

    var title: String {
        switch self {
        case .pick(.left): "Left"
        case .pick(.right): "Right"
        case .split(true): "Split"
        case .settings: "iikb Settings"
        case .nextKeyboard: "Next Keyboard"
        default: "Full"
        }
    }
}

extension KeyboardSettings {
    /// Settings as the app keeps them, a `name=value` line each under the names iOS's `SettingsStore` uses, so both
    /// apps keep them alike. Names missing keep iikb's defaults.
    init(parsing text: String) {
        let toggles: [String: WritableKeyPath<KeyboardSettings, Bool>] = [
            "autoCapitalization": \.autoCapitalization, "autoCorrection": \.autoCorrection, "capsLock": \.capsLock,
            "smartPunctuation": \.smartPunctuation, "periodShortcut": \.periodShortcut,
            "predictiveText": \.predictiveText, "slideToType": \.slideToType, "sound": \.sound,
            "emojiKey": \.emojiKey, "micKey": \.micKey, "numberRow": \.numberRow, "split": \.split,
            "compactPanels": \.compactPanels,
        ]
        self = .initial
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let (name, value) = (parts[0], parts[1])
            if let toggle = toggles[name] {
                self[keyPath: toggle] = value == "true"
                continue
            }
            switch name {
            case "theme": theme = ThemeName(rawValue: value) ?? theme
            case "themeAppearance": themeAppearance = ThemeAppearance(rawValue: value) ?? themeAppearance
            case "stopAnimation": stopAnimation = StopAnimation(rawValue: value) ?? stopAnimation
            case "characterPreviewStyle": characterPreview = CharacterPreview(rawValue: value) ?? characterPreview
            case "hapticFeedback": haptics = HapticFeedback(rawValue: value) ?? haptics
            case "keySpacing": keySpacing = KeySpacing(rawValue: value) ?? keySpacing
            case "keyRoundness": keyRoundness = KeyRoundness(rawValue: value) ?? keyRoundness
            case "keyboardMenu": keyboardMenu = KeyboardMenu(rawValue: value) ?? keyboardMenu
            case "clipboardLength": clipboardLength = ClipboardLength(rawValue: value) ?? clipboardLength
            case "globe": globeKey = GlobeKey(rawValue: value) ?? globeKey
            case "oneHanded": oneHanded = OneHanded(rawValue: value) ?? oneHanded
            case "skinTone": skinTone = SkinTone(rawValue: value)
            case "writingStyle": dictationStyle = DictationStyle(rawValue: value) ?? dictationStyle
            case "dictationEditing": dictationEditing = DictationEditing(rawValue: value) ?? dictationEditing
            case "spokenLists": dictationLists = DictationLists(rawValue: value) ?? dictationLists
            case "textMode": dictationTextMode = DictationTextMode(rawValue: value) ?? dictationTextMode
            case "appWritingStyles": appDictationStyles = Self.appStyles(value)
            default: continue
            }
        }
    }

    /// Style in Each App as `package:style` pairs split by commas, which a package name can't hold.
    private static func appStyles(_ value: String) -> [String: DictationStyle] {
        var styles: [String: DictationStyle] = [:]
        for pair in value.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let style = DictationStyle(rawValue: parts[1]) { styles[parts[0]] = style }
        }
        return styles
    }
}

/// What's learned, kept as JSON in the app's files by Kotlin.
extension Keyboard {
    func memory() -> [UInt8]? {
        guard let memory = engine.corrector?.memory else { return nil }
        return (try? JSONEncoder().encode(memory)).map { [UInt8]($0) }
    }

    func restore(memory bytes: [UInt8]) {
        guard let memory = try? JSONDecoder().decode(TypingMemory.self, from: Data(bytes)) else { return }
        engine.corrector?.changeMemory { $0 = memory }
        engine.suggestionsChanged()
    }

    func emojiHistory() -> [UInt8]? {
        (try? JSONEncoder().encode(engine.emojiHistory)).map { [UInt8]($0) }
    }

    func restore(emojiHistory bytes: [UInt8]) {
        guard var history = try? JSONDecoder().decode(EmojiHistory.self, from: Data(bytes)) else { return }
        history.skinTone = engine.settings.skinTone
        engine.emojiHistory = history
    }
}

enum Json {
    static func encode(_ value: some Encodable) -> [UInt8] {
        (try? JSONEncoder().encode(value)).map { [UInt8]($0) } ?? []
    }
}

extension DeviceClass {
    /// What Android's device is on a `screen` this size in dp, as iOS's idiom tells an iPhone from an iPad: a phone that
    /// folds is a phone open or folded, as the iPhone Duo is, and which of its screens it's on follows the screen's size
    /// (`Duo.isOpen`), never the hinge; anything else is a tablet once its short side reaches 600.
    init(screen: Size, folds: Bool) {
        let short = min(screen.width, screen.height)
        self.init(isPad: !folds && short >= 600, shortSide: short)
    }
}
