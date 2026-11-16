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
            rows: [RowItem.keys("12345") + [.flexible] + RowItem.keys("67890")] + rows, shortRows: 1,
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

    /// Each half five keys wide: the globe or the record button, layer key, the keys arranged before space and a space bar on
    /// the left, a space bar, those after space and return on the right, and the field's own keys in the gap between,
    /// clear of where the thumbs press space. Each space bar stays at least two keys wide, a key arranged on a side
    /// without room for it going to the other, beside the same space, and the snippet key, then the period key, left
    /// out when the halves have no room for them.
    private static func splitBottomRow(_ context: LayoutContext, layerKey: KeyboardLayer) -> [RowItem] {
        let character = { (value: String) in RowItem.key(Key(.character(value))) }
        let span = { (keys: [Key]) in keys.compactMap(\.width.span).reduce(0, +) }
        var (before, after) = beside(context, width: .input)
        let lead =
            (context.showsMicKey ? [Key(.dictate)] : context.showsGlobeKey ? [Key(context.globe)] : [])
            + [Key(.layer(layerKey))]
        for dropped in [KeyAction.snippetPrefix(context.snippetPrefix), .character(".")]
        where span(before + after) > 3 - span(lead) + 1.5 {
            before.removeAll { $0.action == dropped }
            after.removeAll { $0.action == dropped }
        }
        while span(after) > 1.5, !after.isEmpty { before.append(after.removeFirst()) }
        while span(before) > 3 - span(lead), !before.isEmpty { after.insert(before.removeLast(), at: 0) }
        let leading = lead + before
        let leadingSpan = span(leading)
        let afterSpan = span(after)
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
            + [.flexible, space(3.5 - afterSpan)] + after.map(RowItem.key) + [.key(Key(.return, width: .pitch(1.5)))]
    }

    /// The keys arranged before space and after it (`LayoutContext.aroundSpace`): emoji as wide as the layer key, the
    /// period key a key wide, its long press offering the punctuation the letters lack, and the snippet key a key wide.
    private static func beside(_ context: LayoutContext, width emoji: KeyWidth) -> (before: [Key], after: [Key]) {
        let keys = context.aroundSpace.map { key -> Key? in
            switch key {
            case .space: nil
            case .emoji: Key(.emoji, width: emoji)
            case .period: Key(.character("."), alternates: Alternates.periodKey)
            case .snippet: Key(.snippetPrefix(context.snippetPrefix))
            }
        }
        let space = keys.firstIndex(of: nil) ?? keys.count
        return (keys[..<space].compactMap { $0 }, keys[space...].compactMap { $0 })
    }

    /// The language's letters, a row shorter than the longest centered, Apple's keys narrowed to fit a longer row and
    /// the keys around them kept as wide as on QWERTY.
    private static func letters(_ context: LayoutContext) -> KeyboardLayout {
        let letters = context.letters.rows
        let widest = letters.map(\.count).max() ?? 10
        let scale = Double(widest) / 10
        let shift = context.letters.narrowsShift ? 1.3 : 1.3 * scale
        let keys = { (letters: String) in RowItem.keys(letters) }
        let row = { (letters: String) in
            letters.count < widest ? [.flexible] + keys(letters) + [.flexible] : keys(letters)
        }
        if context.letters.deleteOnTop { return deleteOnTop(context) }
        let rows = [
            row(letters[0]),
            row(letters[1]),
            [.key(Key(.shift, width: .pitch(shift))), .flexible] + keys(letters[2]) + [
                .flexible, .key(Key(.delete, width: .pitch(shift))),
            ],
            bottomRow(context, layerKey: .numbers).widened(by: scale),
        ]
        let extraColumns = Double(widest - 10)
        guard context.showsNumberRow else { return KeyboardLayout(rows: rows, extraColumns: extraColumns) }
        return KeyboardLayout(
            rows: [RowItem.keys("1234567890").widened(by: scale)] + rows, shortRows: 1,
            extraColumns: extraColumns)
    }

    /// Apple's Dvorak, measured on the Duo: delete ends the top row, set to the right; the home row starts at the left
    /// edge; shift and the bottom row's letters fill theirs, 0.3 of a key wider than ten keys.
    private static func deleteOnTop(_ context: LayoutContext) -> KeyboardLayout {
        let letters = context.letters.rows
        let columns = 1.3 + Double(letters[2].count)
        let rows = [
            [.flexible] + RowItem.keys(letters[0]) + [.key(Key(.delete, width: .pitch(1.5)))],
            RowItem.keys(letters[1]) + [.flexible],
            [.key(Key(.shift, width: .pitch(1.3)))] + RowItem.keys(letters[2]),
            bottomRow(context, layerKey: .numbers).widened(by: columns / 10),
        ]
        guard context.showsNumberRow else { return KeyboardLayout(rows: rows, extraColumns: columns - 10) }
        return KeyboardLayout(
            rows: [RowItem.keys("1234567890").widened(by: columns / 10)] + rows, shortRows: 1,
            extraColumns: columns - 10)
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

    /// The globe, as wide as Raycast's, or the record button in its place, the layer key, the keys arranged before space
    /// (the emoji key in every field, as it's the one Bassim taps most), space, the field's own keys, those arranged after
    /// space, and return.
    private static func bottomRow(_ context: LayoutContext, layerKey: KeyboardLayer) -> [RowItem] {
        let side = context.isLandscape ? 2.0 : 2.5
        let first =
            context.showsMicKey
            ? Key(.dictate, width: .pitch(0.93)) : context.showsGlobeKey ? Key(context.globe, width: .pitch(0.93)) : nil
        let (before, after) = beside(context, width: .pitch(side / 2))
        let leading: [RowItem] =
            (first.map { [.key($0)] } ?? []) + [.key(Key(.layer(layerKey), width: .pitch(side / 2)))]
            + before.map(RowItem.key)
        let trailing = after.map(RowItem.key)
        let space = RowItem.key(Key(.space, width: .fill))
        let returnKey = RowItem.key(Key(.return, width: context.showsEmoji ? raycastReturn : .pitch(side)))
        let character = { (value: String, width: KeyWidth) in RowItem.key(Key(.character(value), width: width)) }
        switch context.kind {
        case .email:
            return leading + [space, character("@", .pitch(1.25)), character(".", .pitch(1.25))] + trailing + [
                returnKey
            ]
        case .url:
            return leading + [character(".", .fill), character("/", .fill), character(".com", .fill)] + trailing
                + [returnKey]
        case .twitter:
            return leading + [space, character("@", .pitch(1.25)), character("#", .pitch(1.25))] + trailing + [
                returnKey
            ]
        case .webSearch:
            return leading + [space, character(".", .input)] + trailing + [.key(Key(.return, width: .pitch(1.75)))]
        default:
            return leading + [space] + trailing + [returnKey]
        }
    }
}
