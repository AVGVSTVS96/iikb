public enum DeviceClass: Hashable, Sendable, CaseIterable {
    case phone
    case compactPad
    case pad
    case largePad

    /// An iPad by its short side, or an iPhone.
    public init(isPad: Bool, shortSide: Double) {
        self = !isPad ? .phone : shortSide >= 1000 ? .largePad : shortSide < 800 ? .compactPad : .pad
    }
}

public struct LayoutContext: Hashable, Sendable {
    public var device: DeviceClass
    public var layer: KeyboardLayer
    public var kind: InputKind
    /// iOS wants a way to the next keyboard: an iPad's keys carry a globe, and an iPhone's either do (`showsGlobeKey`)
    /// or its menus offer Next Keyboard.
    public var showsGlobe: Bool
    /// The globe key at the far left of an iPhone's bottom row, away from `123` and emoji, so it's never hit for them.
    public var showsGlobeKey: Bool
    /// That globe drawn as a spacer that does nothing, with Next Keyboard in the menu.
    public var globeIsSpacer: Bool
    /// The record button in the globe key's place, which then goes to the menu.
    public var showsMicKey: Bool
    /// Wider than tall.
    public var isLandscape: Bool
    /// The iPhone Duo open, on its inner screen, whose keys are half again as wide as folded, on its cover.
    public var isOpen: Bool
    public var oneHanded: OneHanded
    /// The open Duo in landscape with its keys in two halves, one under each thumb.
    public var isSplit: Bool
    /// The emoji key in an iPhone's bottom row, beside space.
    public var showsEmoji: Bool
    /// A row of digits above an iPhone's letters.
    public var showsNumberRow: Bool
    public var keySpacing = KeySpacing.standard
    public var keyRoundness = KeyRoundness.standard
    /// The More button at the bar's left, or none; an iPad keeps its button.
    public var leadingButton: LeadingButton
    /// The actions as a row of keys above the letters, in their order; none where they show elsewhere (`actionPlace`).
    public var actions: [Panel] = []
    /// The keys beside space in their order, space among them, as Settings arranges them (`BottomKey`).
    public var order = BottomKey.standard
    /// A period key in the bottom row, in fields with none of their own.
    public var showsPeriodKey = false
    /// What the snippet key types, on an iPhone's letters; empty with no snippet key.
    public var snippetPrefix = ""
    /// The languages being typed, the one the keys are laid out for first: a long press offers its letters, then the
    /// others'.
    public var languages = [Language.english]
    /// The letters' layout, one of the languages'.
    public var letters = LetterLayout.qwerty
    /// A digit in the corner of each top letter, which holding the key types: an iPhone's, without the number row.
    public var showsNumberHints = false
    /// The sign on the currency key, which trades places with $ wherever the layout has both.
    public var currency = "$"
    /// Where the device is, whose web address endings the period offers in an email, URL or search field.
    public var region = Region()

    public init(
        device: DeviceClass, layer: KeyboardLayer, kind: InputKind = .text, showsGlobe: Bool = false,
        isLandscape: Bool = false, isOpen: Bool = false, oneHanded: OneHanded = .off, isSplit: Bool = false,
        showsEmoji: Bool = false, showsGlobeKey: Bool = false, globeIsSpacer: Bool = false, showsMicKey: Bool = false,
        showsNumberRow: Bool = false, leadingButton: LeadingButton = .menu
    ) {
        self.device = device
        self.layer = layer
        self.kind = kind
        self.showsGlobe = showsGlobe
        self.isLandscape = isLandscape
        self.isOpen = isOpen && device == .phone
        self.oneHanded = oneHanded
        self.isSplit = isSplit
        self.showsEmoji = showsEmoji && device == .phone
        self.showsMicKey = showsMicKey && device == .phone
        self.showsGlobeKey = showsGlobeKey && showsGlobe && device == .phone && !self.showsMicKey
        self.globeIsSpacer = globeIsSpacer && self.showsGlobeKey
        self.showsNumberRow = showsNumberRow && device == .phone && layer == .letters
        self.leadingButton = device == .phone ? leadingButton : .menu
        if !allowsOneHanded { self.oneHanded = .off }
        if !allowsSplit { self.isSplit = false }
    }

    /// The layout on a `screen`-sized device as `settings` set it up in `region`: the keyboard's, and the app's preview
    /// of it.
    public init(
        device: DeviceClass, layer: KeyboardLayer, kind: InputKind = .text, showsGlobe: Bool = false, screen: Size,
        settings: KeyboardSettings, region: Region = Region()
    ) {
        self.init(
            device: device, layer: layer, kind: kind, showsGlobe: showsGlobe, isLandscape: screen.width > screen.height,
            isOpen: Duo.isOpen(short: min(screen.width, screen.height)), oneHanded: settings.oneHanded,
            isSplit: settings.split,
            showsEmoji: settings.emojiKey, showsGlobeKey: settings.globeKey != .hidden,
            globeIsSpacer: settings.globeKey == .spacer, showsMicKey: settings.micKey && settings.dictationButton,
            showsNumberRow: settings.numberRow, leadingButton: settings.leadingButton
        )
        if device == .phone, settings.actionPlace(phone: true, landscape: isLandscape) == .row {
            actions = settings.actions
        }
        order = settings.aroundSpace
        showsPeriodKey = settings.periodKey && device == .phone
        snippetPrefix = settings.snippetKey && device == .phone ? settings.snippetPrefix : ""
        keySpacing = settings.keySpacing
        keyRoundness = settings.keyRoundness
        letters = settings.letters
        languages = settings.languages.filter { $0.layouts.contains(letters) }
        languages += settings.languages.filter { !languages.contains($0) }
        showsNumberHints = settings.numberHints && device == .phone && layer == .letters && !showsNumberRow
        currency = settings.currency.symbol(in: region)
        self.region = region
    }

    /// Like Apple's, only an iPhone in portrait narrows its keys for one hand, and on the Duo only folded.
    public var allowsOneHanded: Bool { device == .phone && !isLandscape && !isOpen }

    /// Like Apple's, only the open Duo in landscape splits its keys.
    public var allowsSplit: Bool { isOpen && isLandscape }

    /// The keys in the bottom row whose hold opens the layer menu: the layer key, Bassim's way in, and the emoji key,
    /// whose hold opens Apple's menu with the same layouts (Left and Right folded, Full and Split open). The globe's
    /// touches go to the control `handleInputModeList` drives, so holding it opens the system's list of keyboards.
    /// The bottom row's globe as Settings has it: one that switches keyboards, or the spacer.
    public var globe: KeyAction { globeIsSpacer ? .globeSpacer : .nextKeyboard }

    public func menuKeys(in layout: KeyboardLayout) -> [Key] {
        (layout.rows.last ?? []).compactMap { item -> Key? in
            guard case .key(let key) = item else { return nil }
            switch key.action {
            case .layer, .emoji: return key
            default: return nil
            }
        }
    }

    /// What holding `123` or emoji offers (`menu`), top to bottom: the layouts that apply here (one hand or the other on an
    /// iPhone in portrait, Full and Split on the open Duo in landscape), the next keyboard where an iPhone needs one
    /// and its keys carry no globe that switches, then iikb's settings.
    public var moreMenu: [KeyboardEvent] {
        layoutPicks + (showsGlobe && device == .phone && (!showsGlobeKey || globeIsSpacer) ? [.nextKeyboard] : []) + [
            .settings
        ]
    }

    /// What holding an iPhone's layer key offers, left to right, on every screen, the only place they are, since they're
    /// for typing: the layouts, the next keyboard and iikb Settings, after the layout in use where no other applies, so
    /// letting go without sliding changes nothing.
    public var menu: [KeyboardEvent] {
        guard device == .phone else { return [] }
        return (layoutPicks.isEmpty ? [.keep] : []) + moreMenu
    }

    /// Whether the bar shows its More button.
    public var showsMoreButton: Bool { leadingButton == .menu }

    /// The keys between the layer key and return, in their order, space among them: the emoji key and, on the letters of a field with no keys of its own beside space (a period, Instagram's @ and #), the period key, and the snippet key on the letters, where each shows.
    public var aroundSpace: [BottomKey] {
        BottomKey.arranged(order).filter { key in
            switch key {
            case .space: true
            case .emoji: showsEmoji
            case .period: showsPeriodKey && layer == .letters && ![.email, .url, .webSearch, .twitter].contains(kind)
            case .snippet: !snippetPrefix.isEmpty && layer == .letters
            }
        }
    }

    /// The layouts that apply here.
    public var layoutPicks: [KeyboardEvent] {
        if allowsSplit {
            [.split(false), .split(true)]
        } else if allowsOneHanded {
            OneHanded.menuOrder.map(KeyboardEvent.pick)
        } else {
            []
        }
    }

    /// The layout in use, as the menu offers it.
    public var menuPick: KeyboardEvent {
        allowsSplit ? .split(isSplit) : allowsOneHanded ? .pick(oneHanded) : .keep
    }
}

extension LayoutContext {
    /// What a touch model is kept per: the same keys under the same hands, so the open Duo's wider keys learn apart
    /// from its cover's, and a QWERTZ z from a QWERTY z. QWERTY's letters keep the name they had before there were
    /// others, so nothing learned on them is lost.
    public var signature: String {
        "\(device)-\(isLandscape ? "landscape" : "portrait")-\(layer)" + (isOpen ? "-open" : "")
            + (oneHanded == .off ? "" : "-\(oneHanded)") + (isSplit ? "-split" : "")
            + (layer == .letters && letters != .qwerty ? "-\(letters.id)" : "")
    }

    /// The layout a touch model's signature was kept for.
    public init?(signature: String) {
        let letters = LetterLayout.all.first { $0 != .qwerty && signature.hasSuffix("-\($0.id)") }
        let base = letters.map { String(signature.dropLast($0.id.count + 1)) } ?? signature
        let contexts = DeviceClass.allCases.flatMap { device in
            KeyboardLayer.allCases.flatMap { layer in
                [false, true].flatMap { landscape in
                    [false, true].flatMap { open in
                        OneHanded.allCases.flatMap { hand in
                            [false, true].map {
                                LayoutContext(
                                    device: device, layer: layer, isLandscape: landscape, isOpen: open, oneHanded: hand,
                                    isSplit: $0)
                            }
                        }
                    }
                }
            }
        }
        guard var context = contexts.first(where: { $0.signature == base }) else { return nil }
        if let letters, context.layer == .letters {
            context.letters = letters
            context.languages = [Language.all.first { $0.layouts.contains(letters) } ?? .english]
        }
        guard context.signature == signature else { return nil }
        self = context
    }
}

/// The iPhone Duo, the only iPhone over 440 points on the short side.
public enum Duo {
    /// Its four screens, in Bassim's words: folded (the cover) or open (the inner screen), each in portrait (taller
    /// than wide) or landscape (wider than tall). Slightly folding the open screen keeps its screen: iOS only gives the
    /// keyboard a different height (`KeyboardMetrics.filling`).
    public enum Screen: CaseIterable, Sendable {
        case foldedPortrait, foldedLandscape, openPortrait, openLandscape

        public init(open: Bool, landscape: Bool) {
            self =
                switch (open, landscape) {
                case (false, false): .foldedPortrait
                case (false, true): .foldedLandscape
                case (true, false): .openPortrait
                case (true, true): .openLandscape
                }
        }

        /// The Duo's screen of that size, or nil on any other device.
        public init?(width: Double, height: Double) {
            let short = min(width, height)
            guard Duo.isDuo(short: short) else { return nil }
            self.init(open: Duo.isOpen(short: short), landscape: width > height)
        }

        public var isOpen: Bool { self == .openPortrait || self == .openLandscape }
        public var isLandscape: Bool { self == .foldedLandscape || self == .openLandscape }

        public var size: Size {
            switch self {
            case .foldedPortrait: Size(width: 466, height: 678)
            case .foldedLandscape: Size(width: 678, height: 466)
            case .openPortrait: Size(width: 669, height: 951)
            case .openLandscape: Size(width: 951, height: 669)
            }
        }

        /// What iOS gives a third-party keyboard of the screen's width, centered on it (iOS 27.1 simulator).
        public var keyboardWidth: Double {
            switch self {
            case .foldedPortrait: 452
            case .foldedLandscape: 528
            case .openPortrait: size.width
            case .openLandscape: 801
            }
        }

        public var name: String {
            switch self {
            case .foldedPortrait: "Folded, portrait"
            case .foldedLandscape: "Folded, landscape"
            case .openPortrait: "Open, portrait"
            case .openLandscape: "Open, landscape"
            }
        }
    }

    public static func isDuo(short side: Double) -> Bool { side > 440 }
    public static func isOpen(short side: Double) -> Bool { side >= 600 }
}

public enum Layouts {
    public static func layout(for context: LayoutContext) -> KeyboardLayout {
        let layout =
            switch context.device {
            case .phone: PhoneLayouts.layout(for: context)
            case .compactPad: CompactPadLayouts.layout(for: context)
            case .pad: PadLayouts.layout(for: context)
            case .largePad: LargePadLayouts.layout(for: context)
            }
        var local = context.languages == [.english] ? layout : layout.in(context.languages)
        if context.layer == .letters, context.languages != [.english], context.languages[0] != .italian {
            local = local.accenting(context.letters)
        }
        if context.showsNumberHints { local = local.hinted() }
        if context.device == .phone, context.currency != "$" { local = local.priced(context.currency) }
        if [.email, .url, .webSearch].contains(context.kind) {
            local = local.ending(context.region.endings(typing: context.languages[0]))
        }
        return local.withActions(context)
    }
}

extension KeyboardLayout {
    /// The action row on top, as Raycast's: short pills centered over the letters, or on the open Duo's split keys half
    /// on each side, each half's centered over its letters. A pill is 1.6 letters wide, narrower when that many don't fit.
    func withActions(_ context: LayoutContext) -> KeyboardLayout {
        guard !context.actions.isEmpty else { return self }
        let group = { (panels: ArraySlice<Panel>, columns: Double) -> (keys: [RowItem], margin: RowItem) in
            let pitch = min(1.6, columns / Double(max(panels.count, 1)))
            let keys = panels.map { RowItem.key(Key(.tool($0), width: .pitch(pitch))) }
            return (keys, .spacer(.pitch((columns - pitch * Double(panels.count)) / 2)))
        }
        let row: [RowItem]
        if context.isSplit {
            let half = 5 + extraColumns / 2
            let left = group(context.actions.prefix((context.actions.count + 1) / 2), half)
            let right = group(context.actions.dropFirst((context.actions.count + 1) / 2), half)
            row = [left.margin] + left.keys + [.flexible] + right.keys + [right.margin]
        } else {
            let all = group(context.actions[...], 10 + extraColumns)
            row = [.flexible] + all.keys + [.flexible]
        }
        var layout = self
        layout.rows.insert(row, at: 0)
        layout.shortRows += 1
        return layout
    }
}

extension RowItem {
    static func keys(_ primary: String, secondaries: String = "", pairs: Bool = false) -> [RowItem] {
        let secondaries = secondaries.map { $0 == " " ? nil : String($0) }
        return primary.enumerated().map { index, character in
            let value = String(character)
            return .key(
                Key(
                    .character(value),
                    alternates: Alternates.for(value),
                    secondary: index < secondaries.count ? secondaries[index] : nil,
                    isPair: pairs
                ))
        }
    }

    static let flexible = RowItem.spacer(.fill)
}

extension KeyboardLayout {
    /// The keys with what a long press on each offers in `languages`. A long press opens on the key's own character,
    /// the first language's likeliest next to it and running toward the keyboard's middle, then what the other
    /// languages add, without letters that have keys of their own. A key the first language lists nothing for keeps
    /// English's, with the others' after them.
    func `in`(_ languages: [Language]) -> KeyboardLayout {
        let keyed = Set(rows.flatMap { $0.compactMap(\.character) })
        var layout = self
        layout.rows = rows.map { row in
            let characters = row.compactMap(\.character)
            return row.map { item in
                guard case .key(var key) = item, let value = item.character else { return item }
                let lists = languages.map { Alternates.for(value, in: $0) }
                let added = lists.dropFirst().flatMap { $0 ?? [] }.filter { $0 != value && !keyed.contains($0) }
                if let listed = lists[0] {
                    let options = ([value] + listed.filter { $0 != value && !keyed.contains($0) } + added).uniqued
                    let right = characters.firstIndex(of: value)! >= characters.count / 2
                    key.alternates = options.count > 1 ? (right ? options.reversed() : options) : []
                } else if !added.isEmpty {
                    key.alternates = ((key.alternates.isEmpty ? [value] : key.alternates) + added).uniqued
                }
                return .key(key)
            }
        }
        return layout
    }
}

extension KeyboardLayout {
    /// The layout's accent keys made Apple's: shift typing what `letters` says, a key that types an accent, or whose
    /// pair does, waiting for the next letter, and one that types an accent only when shifted, French's ’ on an iPhone,
    /// accenting the letter before it.
    func accenting(_ letters: LetterLayout) -> KeyboardLayout {
        var layout = self
        layout.rows = rows.map { row in
            row.map { item in
                guard case .key(var key) = item, let value = item.character else { return item }
                if !key.isPair { key.shifted = letters.shifted[value] }
                let accents = { (typed: String?) in typed.map { Accent.marks[$0] != nil } ?? false }
                key.isDeadKey = accents(value) || key.isPair && accents(key.secondary)
                key.accentsLetterBefore = !key.isDeadKey && accents(key.shifted)
                return .key(key)
            }
        }
        return layout
    }
}

extension KeyboardLayout {
    /// Each top letter with its digit, 1 to 0, in its corner and on its long press, at the end nearest the key's own edge
    /// of the keyboard, where the hold opens.
    func hinted() -> KeyboardLayout {
        guard let top = rows.first else { return self }
        var digits: [String: String] = [:]
        for value in top.compactMap(\.character) where digits[value] == nil && digits.count < 10 {
            digits[value] = String((digits.count + 1) % 10)
        }
        var layout = self
        layout.rows[0] = top.map { item in
            guard case .key(var key) = item, let value = item.character, let digit = digits[value] else { return item }
            let options = key.alternates.isEmpty ? [value] : key.alternates
            key.alternates = Self.isRight(item, in: top) ? options + [digit] : [digit] + options
            key.secondary = digit
            key.holdPick = digit
            return .key(key)
        }
        return layout
    }

    /// The currency key showing `symbol`, which trades places with $ wherever the layout has both, and offers $ among the
    /// rest on its long press.
    func priced(_ symbol: String) -> KeyboardLayout {
        let swap = { (text: String) in text == "$" ? symbol : text == symbol ? "$" : text }
        var layout = self
        layout.rows = rows.map { row in
            row.map { item in
                guard case .key(var key) = item, let value = item.character else { return item }
                key.action = .character(swap(value))
                key.secondary = key.secondary.map(swap)
                key.alternates = key.alternates.map(swap)
                if value == "$", !key.alternates.isEmpty, !key.alternates.contains("$") { key.alternates.append("$") }
                return .key(key)
            }
        }
        return layout
    }

    /// The bottom row's .com, or its period where it has none, offering `endings` on a long press that opens on the
    /// first, so a hold let go types .com.
    func ending(_ endings: [String]) -> KeyboardLayout {
        guard let bottom = rows.last, let first = endings.first else { return self }
        let held = bottom.contains { $0.character == ".com" } ? ".com" : "."
        var layout = self
        layout.rows[rows.count - 1] = bottom.map { item in
            guard case .key(var key) = item, item.character == held else { return item }
            key.alternates = Self.isRight(item, in: bottom) ? endings.reversed() : endings
            key.holdPick = first
            return .key(key)
        }
        return layout
    }

    /// Whether a key sits in the right half of its row's keys, where its long press runs leftward.
    private static func isRight(_ item: RowItem, in row: [RowItem]) -> Bool {
        let keys = row.filter { if case .key = $0 { true } else { false } }
        return (keys.firstIndex(of: item) ?? 0) >= keys.count / 2
    }
}

extension RowItem {
    fileprivate var character: String? {
        guard case .key(let key) = self, case .character(let value) = key.action else { return nil }
        return value
    }
}

extension [RowItem] {
    /// Each key and gap of a set width `scale` times as many columns wide, so it keeps its size in a layout whose rows
    /// hold more keys.
    func widened(by scale: Double) -> [RowItem] {
        guard scale != 1 else { return self }
        return map { item in
            guard case .pitch(let span) = item.width else { return item }
            switch item {
            case .key(var key):
                key.width = .pitch(span * scale)
                return .key(key)
            case .spacer: return .spacer(.pitch(span * scale))
            }
        }
    }
}
