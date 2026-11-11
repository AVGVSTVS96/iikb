enum CompactPadLayouts {
    static func layout(for context: LayoutContext) -> KeyboardLayout {
        switch context.layer {
        case .letters:
            letters(context, PadLayouts.Letters.of(context.letters), Fit.of(context.letters))
        case .numbers:
            KeyboardLayout(rows: [
                RowItem.keys("1234567890") + [delete],
                [.spacer(.pitch(0.4))] + RowItem.keys("@#$&*()'\"", secondaries: "€£¥_^[]{}") + [returnKey],
                [.key(Key(.layer(.symbols)))] + RowItem.keys("%-+=/;:", secondaries: "§|~…\\<>")
                    + RowItem.keys(",.", secondaries: "!?", pairs: true) + [.key(Key(.layer(.symbols), width: .fill))],
                bottomRow(context, layerKey: .letters),
            ])
        case .symbols:
            KeyboardLayout(rows: [
                RowItem.keys("1234567890") + [delete],
                [.spacer(.pitch(0.4))] + RowItem.keys("€£¥_^[]{}") + [returnKey],
                [.key(Key(.layer(.numbers)))] + RowItem.keys("§|~…\\<>!?") + [
                    .key(Key(.layer(.numbers), width: .fill))
                ],
                bottomRow(context, layerKey: .letters),
            ])
        }
    }

    private static func letters(_ context: LayoutContext, _ letters: PadLayouts.Letters, _ fit: Fit) -> KeyboardLayout {
        let row = { (index: Int) in RowItem.keys(letters.rows[index], secondaries: letters.secondaries[index]) }
        return KeyboardLayout(
            rows: [
                row(0) + [delete],
                [.spacer(.pitch(fit.indent))] + row(1) + [returnKey],
                [.key(Key(.shift, width: fit.shift.map { .pitch($0) } ?? .input))] + row(2)
                    + RowItem.keys(",.", secondaries: letters.pairs, pairs: true)
                    + RowItem.keys(letters.last, secondaries: letters.lastSecondary)
                    + [.key(Key(.shift, width: .fill))],
                bottomRow(context, layerKey: .numbers).widened(by: fit.columns / 11.2),
            ], extraColumns: fit.columns - 11.2)
    }

    /// How Apple's iPad mini fits a layout's letters, measured in the simulator: the second row's indent and shift's
    /// width in its own keys where it isn't a letter's, and the columns a row spans. The 11-inch iPad's keys and flicks are the mini's too.
    struct Fit {
        var indent = 0.4
        var shift: Double?
        var columns = 11.2

        static func of(_ layout: LetterLayout) -> Fit {
            switch layout {
            case .german: Fit(indent: 0.3, columns: 12.5)
            case .swedish: Fit(shift: 1.2, columns: 12.95)
            case .spanish: Fit(indent: 0.17, columns: 11.31)
            case .french, .azerty: Fit(indent: 0.2, shift: 1.05, columns: 11.41)
            default: Fit()
            }
        }
    }

    private static let delete = RowItem.key(Key(.delete, width: .fill))
    private static let returnKey = RowItem.key(Key(.return, width: .fill))

    /// Apple's number layers put undo, or redo on the symbols, before the right layer key, and the three share the room
    /// the letters' two take.
    private static func bottomRow(_ context: LayoutContext, layerKey: KeyboardLayer) -> [RowItem] {
        let (left, right) = context.isLandscape ? (1.02, 1.52) : (1.04, 1.56)
        let leading: [RowItem] = context.showsGlobe ? [.key(Key(.nextKeyboard, width: .pitch(left)))] : []
        let trailing: [Key] =
            switch context.layer {
            case .letters: [Key(.layer(layerKey), width: .pitch(right)), Key(.dismiss, width: .pitch(right))]
            case .numbers:
                [
                    Key(.undo, width: .pitch(left)), Key(.layer(layerKey), width: .pitch(left)),
                    Key(.dismiss, width: .pitch(left)),
                ]
            case .symbols:
                [
                    Key(.redo, width: .pitch(left)), Key(.layer(layerKey), width: .pitch(left)),
                    Key(.dismiss, width: .pitch(left)),
                ]
            }
        return leading + [.key(Key(.layer(layerKey), width: .pitch(left))), .key(Key(.space, width: .fill))]
            + trailing.map(RowItem.key)
    }
}
