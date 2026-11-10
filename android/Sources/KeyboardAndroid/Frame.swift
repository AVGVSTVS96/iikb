import KeyboardCore

/// Everything Kotlin draws, made from the engine after each event: the keys with their faces, the bar's parts, the
/// suggestions, and the theme's paint. Sizes are points, which Android draws as dp.
struct Frame: Encodable {
    var layout: String
    var width: Double
    /// The keys' height, from the bar's bottom to the keyboard's.
    var height: Double
    var toolbar: Bar
    var caps: [Cap]
    var showsSuggestions: Bool
    var chips: [Chip]
    var emoji: [String]
    var look: Look
    var theme: Theme
    /// Holding these keys opens the menu of `items`, `current` the layout in use.
    var menuKeys: [Int]
    var menu: [MenuItem]
    var menuCurrent: Int?
    var panel: String?
    var query: String
    var uppercase: Bool
    /// The chevron in a one-handed keyboard's margin that brings both hands back, in the keys' points.
    var expander: Expander?
}

struct Expander: Encodable {
    var x, y, width, height: Double
    var pointsRight: Bool
}

struct Cap: Encodable {
    var x, y, width, height: Double
    var face: String
    var label: String
    var secondary: String?
    var secondaryDimmed: Bool
    var corner: String?
    var align: String
    var prominent: Bool
    var dimmed: Bool
    var paint: String
    var action: String
    var isInput: Bool
    var typed: String?
    var flicked: String?
    var shown: String?
    var alternates: [String]
    var startsSwipe: Bool
}

struct Chip: Encodable {
    var text: String
    var kind: String
}

struct Bar: Encodable {
    var top, bar, button, glyph: Double
    /// An open panel's results and search row, in the bar's place (docs/design.md, "Panels").
    var results, field, panelHeight: Double
    var compact: Bool
    /// The keys block's edges, which a panel's results and search row span.
    var blockMinX, blockMaxX: Double
    /// Between the tools and the mic, where the suggestions and a notice go.
    var minX, maxX: Double
    var more: Box?
    /// Where the top row's first key starts, as an open chat's More does.
    var keysMinX: Double
    var mic: Box?
    var tools: [Box]
    var slots: [Box]
    var emoji: Box
    var emojiBeside: Bool
    var cancel: Box
    var recording: Box
}

struct Box: Encodable {
    var x, y, width, height: Double

    init(_ rect: Rect) {
        (x, y, width, height) = (rect.x, rect.y, rect.width, rect.height)
    }
}

struct MenuItem: Encodable {
    var symbol: String
    var title: String
}

/// The keys' sizes as the theme draws them (`KeyView`): Raycast's corners and its shares of Apple's sizes.
struct Look: Encodable {
    var keyHeight, rowGap, cornerRadius: Double
    var letterSize, numberRowLetterSize, labelSize, smallLabelSize, symbolSize, secondarySize, cornerSize,
        pairSize: Double
    var letterOffset, numberRowLetterOffset, labelLift: Double
    var edgeInsetX, edgeInsetY, textInset, textBaselineInset, letterBaselineInset, secondaryCapTop: Double
    var pairCapTopRatio, pairBaselineRatio: Double
    var numberRowHeight: Double
    var dimsKeyUnderAccents: Bool

    init(_ m: KeyboardMetrics, shape: KeyShape?, style: KeyboardStyle) {
        let labelScale = (m.wordsAsGlyphs ? shape?.symbolScale : shape?.labelScale) ?? 1
        keyHeight = m.keyHeight
        rowGap = m.rowGap
        cornerRadius = m.cornerRadius
        letterSize = m.letterSize * (shape?.letterScale ?? 1)
        numberRowLetterSize = (m.numberRowLetterSize ?? m.letterSize) * (shape?.letterScale ?? 1)
        labelSize = m.labelSize * labelScale
        smallLabelSize = m.labelSize * 0.75 * labelScale
        symbolSize = m.symbolSize * (shape?.symbolScale ?? 1)
        secondarySize = m.secondarySize
        cornerSize = (m.secondarySize + 3) * (shape?.labelScale ?? 1)
        pairSize = m.pairSize
        letterOffset = m.letterOffset
        numberRowLetterOffset = m.numberRowLetterOffset ?? m.letterOffset
        labelLift = shape?.labelLift ?? 0
        edgeInsetX = m.edgeInset.width
        edgeInsetY = m.edgeInset.height
        textInset = m.textInset
        textBaselineInset = m.textBaselineInset
        letterBaselineInset = m.letterBaselineInset
        secondaryCapTop = m.secondaryCapTop
        pairCapTopRatio = m.pairCapTopRatio
        pairBaselineRatio = m.pairBaselineRatio
        numberRowHeight = m.numberRowHeight
        dimsKeyUnderAccents = style.dimsKeyUnderAccents
    }
}

/// Colors are ARGB, as Android's `Color` ints are.
struct Theme: Encodable {
    /// The plain key fill and its pressed fill, which iOS's cards, badges and tiles take, whatever the keys' own paint.
    var key, keyPressed: Int32
    var card, label, secondaryLabel, prominent, prominentLabel, shadow: Int32
    var candidate, candidateHighlighted, candidatePill, candidateDivider, expander: Int32
    var mic, micGlyph, record, searchField, bubble, bubbleLabel, selection, selectionLabel: Int32
    var continuous: Bool
    var letter, function, prominentKey: Paint

    init(_ t: KeyboardTheme) {
        key = t.key.argb
        keyPressed = t.keyPressed.argb
        card = t.card.argb
        label = t.label.argb
        secondaryLabel = t.secondaryLabel.argb
        prominent = t.prominent.argb
        prominentLabel = t.prominentLabel.argb
        shadow = t.shadow.argb
        candidate = t.candidate.argb
        candidateHighlighted = t.candidateHighlighted.argb
        candidatePill = t.candidatePill.argb
        candidateDivider = t.candidateDivider.argb
        expander = t.expander.argb
        mic = t.mic.argb
        micGlyph = t.micGlyph.argb
        record = t.record.argb
        searchField = t.searchField.argb
        bubble = t.bubble.argb
        bubbleLabel = t.bubbleLabel.argb
        selection = t.selection.argb
        selectionLabel = t.selectionLabel.argb
        continuous = t.keyShape != nil
        letter = Paint(t.letterKey)
        function = Paint(t.functionKey)
        prominentKey = Paint(t.prominentKey)
    }
}

struct Paint: Encodable {
    struct Shadow: Encodable { var color: Int32, y: Double }
    struct Line: Encodable { var color: Int32, width, fade: Double }
    struct Cap: Encodable { var sides: [Int32], at: [Double], glow: Int32 }
    struct Drop: Encodable { var color: Int32, y, blur: Double }

    var top, bottom, pressedTop, pressedBottom, label: Int32
    var labelShadow: Shadow?
    var rim: Line?
    var keycap: Cap?
    var drop: Drop?

    init(_ p: KeyPaint) {
        (top, bottom, pressedTop, pressedBottom, label) = (
            p.top.argb, p.bottom.argb, p.pressedTop.argb, p.pressedBottom.argb, p.label.argb
        )
        labelShadow = p.labelShadow.map { Shadow(color: $0.color.argb, y: $0.y) }
        rim = p.rim.map { Line(color: $0.color.argb, width: $0.width, fade: $0.fade) }
        keycap = p.keycap.map { Cap(sides: $0.sides.map(\.color.argb), at: $0.sides.map(\.at), glow: $0.glow.argb) }
        drop = p.drop.map { Drop(color: $0.color.argb, y: $0.y, blur: $0.blur) }
    }
}

extension RGBA {
    var argb: Int32 {
        let channel = { (value: Double) in UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return Int32(
            bitPattern: channel(alpha) << 24 | channel(red) << 16 | channel(green) << 8 | channel(blue))
    }
}

extension KeyFace.Content {
    var kind: String {
        switch self {
        case .letter: "letter"
        case .text: "text"
        case .smallText: "smallText"
        case .symbol: "symbol"
        case .none: "none"
        }
    }

    var value: String {
        switch self {
        case .letter(let text), .text(let text), .smallText(let text), .symbol(let text): text
        case .none: ""
        }
    }
}

extension KeyFace.Alignment {
    var name: String {
        switch self {
        case .center: "center"
        case .bottomLeading: "leading"
        case .bottomTrailing: "trailing"
        }
    }
}

extension KeyAction {
    var name: String {
        switch self {
        case .character: "character"
        case .space: "space"
        case .delete: "delete"
        case .shift: "shift"
        case .capsLock: "capsLock"
        case .return: "return"
        case .tab: "tab"
        case .layer: "layer"
        case .nextKeyboard: "nextKeyboard"
        case .globeSpacer: "globeSpacer"
        case .dictate: "dictate"
        case .dismiss: "dismiss"
        case .undo: "undo"
        case .redo: "redo"
        case .emoji: "emoji"
        }
    }
}

extension Suggestion.Kind {
    var name: String { "\(self)" }
}
