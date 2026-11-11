public struct KeyFace: Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        case letter(String)
        case text(String)
        case smallText(String)
        case symbol(String)
        case none
    }

    public enum Alignment: Hashable, Sendable {
        case center, bottomLeading, bottomTrailing
    }

    public var content: Content
    public var secondary: String?
    public var corner: String?
    public var secondaryIsDimmed = true
    public var alignment: Alignment = .center
    public var isProminent = false
    /// A key with nothing to do now, as undo with nothing to undo: its glyph dimmed, as Apple's are.
    public var isDimmed = false

    public init(
        content: Content, secondary: String? = nil, secondaryIsDimmed: Bool = true, alignment: Alignment = .center,
        isProminent: Bool = false
    ) {
        self.content = content
        self.secondary = secondary
        self.secondaryIsDimmed = secondaryIsDimmed
        self.alignment = alignment
        self.isProminent = isProminent
    }
}

public struct KeyFaceContext: Hashable, Sendable {
    public var device: DeviceClass
    public var layer: KeyboardLayer
    public var kind: InputKind
    public var shift: ShiftState
    public var returnKind: ReturnKind
    public var returnEnabled: Bool
    public var canUndo = false
    public var canRedo = false

    public init(
        device: DeviceClass, layer: KeyboardLayer, kind: InputKind, shift: ShiftState, returnKind: ReturnKind,
        returnEnabled: Bool
    ) {
        self.device = device
        self.layer = layer
        self.kind = kind
        self.shift = shift
        self.returnKind = returnKind
        self.returnEnabled = returnEnabled
    }
}

extension KeyFace {
    public init(_ key: Key, trailing: Bool, context: KeyFaceContext) {
        let corners = context.device == .pad || context.device == .largePad
        let edge: Alignment = corners ? (trailing ? .bottomTrailing : .bottomLeading) : .center
        switch key.action {
        case .character(let value):
            let glyph = Self.glyphs[value, default: value]
            let shown =
                context.shift.isUppercase ? key.shifted ?? (value.count == 1 ? value.uppercased() : glyph) : glyph
            self.init(content: value.count == 1 ? .letter(shown) : .text(shown))
            secondary = key.secondary.map { Self.glyphs[$0, default: $0] }
            secondaryIsDimmed = !key.isPair
        case .space:
            self.init(content: .none)
            corner = "iikb"
        case .delete:
            self.init(content: .symbol("delete.left"), alignment: edge)
        case .shift:
            let name =
                switch context.shift {
                case .off: "shift"
                case .on: "shift.fill"
                case .locked: "capslock.fill"
                }
            self.init(content: .symbol(name), alignment: edge)
        case .capsLock:
            self.init(content: .symbol(context.shift == .locked ? "capslock.fill" : "capslock"), alignment: edge)
        case .return:
            let kind = context.returnKind
            self.init(
                content: kind.symbol.map { .symbol($0) } ?? .text(kind.title),
                alignment: edge,
                isProminent: kind.isProminent && context.returnEnabled
            )
        case .tab:
            self.init(content: .symbol("arrow.right.to.line"), alignment: edge)
        case .layer(let layer):
            let title =
                context.kind == .url && layer == .numbers && context.device == .phone
                ? ".?123" : Self.title(for: layer, from: context.layer, device: context.device)
            let small = context.device == .phone && context.layer != .letters && layer != .letters
            self.init(content: small ? .smallText(title) : .text(title), alignment: edge)
        case .nextKeyboard, .globeSpacer:
            self.init(content: .symbol("globe"), alignment: edge)
        case .dictate:
            self.init(content: .symbol("waveform"), alignment: edge)
        case .dismiss:
            self.init(content: .symbol("keyboard.chevron.compact.down"), alignment: edge)
        case .emoji:
            self.init(content: .symbol("face.smiling"), alignment: edge)
        case .undo:
            self.init(content: .symbol("arrow.uturn.backward"), alignment: edge)
            isDimmed = !context.canUndo
        case .redo:
            self.init(content: .symbol("arrow.uturn.forward"), alignment: edge)
            isDimmed = !context.canRedo
        }
    }

    private static let glyphs = ["\"": "”", "'": "’"]

    /// An iPad's letters go to `.?123`, its symbols back to `123`, as Apple's do.
    private static func title(for layer: KeyboardLayer, from current: KeyboardLayer, device: DeviceClass) -> String {
        switch (layer, device) {
        case (.letters, _): "ABC"
        case (.numbers, .phone): "123"
        case (.numbers, _): current == .symbols ? "123" : ".?123"
        case (.symbols, _): "#+="
        }
    }
}
