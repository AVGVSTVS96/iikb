enum PhoneLayouts {
    static func layout(for context: LayoutContext) -> KeyboardLayout {
        switch (context.layer, context.isSplit) {
        case (.letters, false): letters(context)
        case (.numbers, false): numbers(context)
        case (.symbols, false): symbols(context)
        case (.letters, true): splitLetters(context)
        case (.numbers, true): split(context, "12345", "67890", "-/:;(", ")$&@\"", layerKey: .symbols)
        case (.symbols, true): split(context, "[]{}#", "%^*+=", "_\\|~<", ">€£¥•", layerKey: .numbers)
        }
    }

    /// Apple's split keyboard on the open Duo: half of each row under each thumb, the middle a gap, and the key
    /// between the hands in a row of odd length (G and V on QWERTY) on both halves.
    private static func splitLetters(_ context: LayoutContext) -> KeyboardLayout {
        let letters = context.letters.rows
        let widest = letters.map(\.count).max() ?? 10
        let keys = { (letters: Substring) in RowItem.keys(String(letters)) }
        let halves = { (row: String) in (keys(row.prefix((row.count + 1) / 2)), keys(row.suffix((row.count + 1) / 2))) }
        let row = { (row: String) -> [RowItem] in
            let (left, right) = halves(row)
            let inset: [RowItem] = row.count < widest ? [.spacer(.pitch(Double(widest - row.count) / 2))] : []
            return inset + left + [.flexible] + right + inset
        }
        let (left, right) = halves(letters[2])
        let rows = [
            row(letters[0]),
            row(letters[1]),
            [.key(Key(.shift, width: .pitch(1.3))), .spacer(.pitch(0.2))] + left + [.flexible]
                + right + [.spacer(.pitch(0.2)), .key(Key(.delete, width: .pitch(1.3)))],
            splitBottomRow(context, layerKey: .numbers),
        ]
        let extraColumns = Double((widest + 1) / 2 - 5) * 2
        guard context.showsNumberRow else { return KeyboardLayout(rows: rows, extraColumns: extraColumns) }
        return KeyboardLayout(
            rows: [RowItem.keys("12345") + [.flexible] + RowItem.keys("67890")] + rows, hasNumberRow: true,
            extraColumns: extraColumns)
    }

    private static func split(
        _ context: LayoutContext, _ topLeft: String, _ topRight: String, _ middleLeft: String, _ middleRight: String,
        layerKey: KeyboardLayer
    ) -> KeyboardLayout {
        let marks = punctuation.map { item -> RowItem in
            guard case .key(var key) = item else { return item }
            key.width = .pitch(1.4)
            return .key(key)
        }
        return KeyboardLayout(rows: [
            RowItem.keys(topLeft) + [.flexible] + RowItem.keys(topRight),
            RowItem.keys(middleLeft) + [.flexible] + RowItem.keys(middleRight),
            [.key(Key(.layer(layerKey), width: .pitch(1.3))), .spacer(.pitch(0.2))] + marks.prefix(3) + [.flexible]
                + marks.suffix(3) + [.spacer(.pitch(0.2)), .key(Key(.delete, width: .pitch(1.3)))],
            splitBottomRow(context, layerKey: .letters),
        ])
    }

    /// Each half five keys wide: the globe or the record button, layer and emoji keys and a space bar on the left, a space bar and return
    /// on the right, and the field's own keys in the gap between, clear of where the thumbs press space.
    private static func splitBottomRow(_ context: LayoutContext, layerKey: KeyboardLayer) -> [RowItem] {
        let character = { (value: String) in RowItem.key(Key(.character(value))) }
        let leading =
            (context.showsMicKey ? [Key(.dictate)] : context.showsGlobeKey ? [Key(context.globe)] : []) + [
                Key(.layer(layerKey))
            ]
            + (context.showsEmoji ? [Key(.emoji)] : [])
        let leadingSpan = leading.compactMap(\.width.span).reduce(0, +)
        let trailing: [RowItem] =
            switch context.kind {
            case .email: [character("@"), character(".")]
            case .url: [character("/"), character(".com")]
            case .twitter: [character("@"), character("#")]
            case .webSearch: [character(".")]
            default: []
            }
        let space = { (span: Double) in RowItem.key(Key(.space, width: .pitch(span))) }
        return leading.map(RowItem.key) + [space(5 - leadingSpan), .flexible] + trailing
            + [.flexible, space(3.5), .key(Key(.return, width: .pitch(1.5)))]
    }

    /// The language's letters, a row shorter than the longest centered, Apple's keys narrowed to fit a longer row and
    /// the keys around them kept as wide as on QWERTY.
    private static func letters(_ context: LayoutContext) -> KeyboardLayout {
        let letters = context.letters.rows
        let widest = letters.map(\.count).max() ?? 10
        let scale = Double(widest) / 10
        let keys = { (letters: String) in RowItem.keys(letters) }
        let row = { (letters: String) in
            letters.count < widest ? [.flexible] + keys(letters) + [.flexible] : keys(letters)
        }
        let rows = [
            row(letters[0]),
            row(letters[1]),
            [.key(Key(.shift, width: .pitch(1.3 * scale))), .flexible] + keys(letters[2]) + [
                .flexible, .key(Key(.delete, width: .pitch(1.3 * scale))),
            ],
            bottomRow(context, layerKey: .numbers).widened(by: scale),
        ]
        let extraColumns = Double(widest - 10)
        guard context.showsNumberRow else { return KeyboardLayout(rows: rows, extraColumns: extraColumns) }
        return KeyboardLayout(
            rows: [RowItem.keys("1234567890").widened(by: scale)] + rows, hasNumberRow: true,
            extraColumns: extraColumns)
    }

    private static func numbers(_ context: LayoutContext) -> KeyboardLayout {
        KeyboardLayout(rows: [
            RowItem.keys("1234567890"),
            RowItem.keys("-/:;()$&@\""),
            [.key(Key(.layer(.symbols), width: .pitch(1.3))), .flexible] + punctuation + [
                .flexible, .key(Key(.delete, width: .pitch(1.3))),
            ],
            bottomRow(context, layerKey: .letters),
        ])
    }

    private static func symbols(_ context: LayoutContext) -> KeyboardLayout {
        KeyboardLayout(rows: [
            RowItem.keys("[]{}#%^*+="),
            RowItem.keys("_\\|~<>€£¥•"),
            [.key(Key(.layer(.numbers), width: .pitch(1.3))), .flexible] + punctuation + [
                .flexible, .key(Key(.delete, width: .pitch(1.3))),
            ],
            bottomRow(context, layerKey: .letters),
        ])
    }

    private static var punctuation: [RowItem] {
        [".", ",", "?", "!", "'"].map { .key(Key(.character($0), width: .pitch(1.4), alternates: Alternates.for($0))) }
    }

    /// Return beside the emoji key, as wide as Raycast's on the open Duo in portrait and landscape.
    private static let raycastReturn = KeyWidth.pitch(1.4)

    /// The globe, as wide as Raycast's, or the record button in its place, the layer key, the emoji key in every field (it's the one Bassim taps most),
    /// space, the field's own keys and return.
    private static func bottomRow(_ context: LayoutContext, layerKey: KeyboardLayer) -> [RowItem] {
        let side = context.isLandscape ? 2.0 : 2.5
        let first =
            context.showsMicKey
            ? Key(.dictate, width: .pitch(0.93)) : context.showsGlobeKey ? Key(context.globe, width: .pitch(0.93)) : nil
        let leading: [RowItem] =
            (first.map { [.key($0)] } ?? [])
            + [.key(Key(.layer(layerKey), width: .pitch(side / 2)))]
            + (context.showsEmoji ? [.key(Key(.emoji, width: .pitch(side / 2)))] : [])
        let space = RowItem.key(Key(.space, width: .fill))
        let returnKey = RowItem.key(Key(.return, width: context.showsEmoji ? raycastReturn : .pitch(side)))
        let character = { (value: String, width: KeyWidth) in RowItem.key(Key(.character(value), width: width)) }
        switch context.kind {
        case .email:
            return leading + [space, character("@", .pitch(1.25)), character(".", .pitch(1.25)), returnKey]
        case .url:
            return leading + [character(".", .fill), character("/", .fill), character(".com", .fill), returnKey]
        case .twitter:
            return leading + [space, character("@", .pitch(1.25)), character("#", .pitch(1.25)), returnKey]
        case .webSearch:
            return leading + [space, character(".", .input), .key(Key(.return, width: .pitch(1.75)))]
        default:
            return leading + [space, returnKey]
        }
    }
}
