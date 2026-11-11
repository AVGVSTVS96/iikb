enum PadLayouts {
    static func layout(for context: LayoutContext) -> KeyboardLayout {
        switch context.layer {
        case .letters:
            letters(context, Letters.of(context.letters))
        case .numbers:
            KeyboardLayout(rows: [
                [tab] + RowItem.keys("1234567890") + [delete],
                [undo] + RowItem.keys("@#$&*()'\"", secondaries: "€£¥_^[]{}") + [returnKey],
                [.key(Key(.layer(.symbols), width: .pitch(2)))] + RowItem.keys("%-+=/;:", secondaries: "§|~…\\<>")
                    + RowItem.keys(",.", secondaries: "!?", pairs: true) + [.key(Key(.layer(.symbols), width: .fill))],
                bottomRow(context, layerKey: .letters),
            ])
        case .symbols:
            KeyboardLayout(rows: [
                [tab] + RowItem.keys("1234567890") + [delete],
                [redo] + RowItem.keys("€£¥_^[]{}") + [returnKey],
                [.key(Key(.layer(.numbers), width: .pitch(2)))] + RowItem.keys("§|~…\\<>!?") + [
                    .key(Key(.layer(.numbers), width: .fill))
                ],
                bottomRow(context, layerKey: .letters),
            ])
        }
    }

    private static func letters(_ context: LayoutContext, _ letters: Letters) -> KeyboardLayout {
        let row = { (index: Int) in RowItem.keys(letters.rows[index], secondaries: letters.secondaries[index]) }
        return KeyboardLayout(
            rows: [
                [.key(Key(.tab, width: .pitch(letters.tab)))] + row(0) + [delete],
                [.key(Key(.capsLock, width: .pitch(letters.capsLock)))] + row(1) + [returnKey],
                [.key(Key(.shift, width: .pitch(letters.shift)))] + row(2)
                    + RowItem.keys(",.", secondaries: letters.pairs, pairs: true)
                    + RowItem.keys(letters.last, secondaries: letters.lastSecondary)
                    + [.key(Key(.shift, width: .fill))],
                bottomRow(context, layerKey: .numbers).widened(by: letters.columns / 12.5),
            ], extraColumns: letters.columns - 12.5)
    }

    /// The letters of one of Apple's layouts on an 11-inch iPad, with what a flick down on each types. A layout with
    /// more keys a row narrows every key, so tab, caps lock and shift are given in its own keys' widths, and the
    /// bottom row keeps its size.
    struct Letters {
        var rows: [String]
        var secondaries: [String]
        var pairs = "!?"
        var last = ""
        var lastSecondary = ""
        var tab = 1.25
        var capsLock = 1.55
        var shift = 2.0
        var columns = 12.5

        static func of(_ layout: LetterLayout) -> Letters {
            switch layout {
            case .german:
                Letters(
                    rows: ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"],
                    secondaries: ["1234567890+", "\"§$%&/()='#", "—`´…@;:"], last: "ß", lastSecondary: "-", tab: 1,
                    capsLock: 1.3, shift: 1.75, columns: 13.75)
            case .swedish:
                Letters(
                    rows: ["qwertyuiopå", "asdfghjklöä", "zxcvbnm"],
                    secondaries: ["1234567890`", "@#$&*()'\"+•", "%_-=/;:"], tab: 1, capsLock: 1.25, columns: 13.5)
            case .spanish:
                Letters(
                    rows: ["qwertyuiop", "asdfghjklñ", "zxcvbnm"],
                    secondaries: ["1234567890", "@#$&*()'\"+", "%_-=/;:"], tab: 1, capsLock: 1.25, shift: 1.75,
                    columns: 12.25)
            case .french, .azerty:
                Letters(
                    rows: ["azertyuiop", "qsdfghjklm", "wxcvbn'"],
                    secondaries: ["1234567890", "@#&\"$(!)-*", "%_+=/;:"], pairs: "?’", tab: 1, capsLock: 1.3,
                    columns: 12.5)
            default:
                Letters(
                    rows: layout.rows, secondaries: ["1234567890", "@#$&*()'\"", "%-+=/;:"])
            }
        }
    }

    private static let tab = RowItem.key(Key(.tab, width: .pitch(1.25)))
    private static let delete = RowItem.key(Key(.delete, width: .fill))
    private static let undo = RowItem.key(Key(.undo, width: .pitch(1.55)))
    private static let redo = RowItem.key(Key(.redo, width: .pitch(1.55)))
    private static let returnKey = RowItem.key(Key(.return, width: .fill))

    private static func bottomRow(_ context: LayoutContext, layerKey: KeyboardLayer) -> [RowItem] {
        let (left, right) = context.isLandscape ? (1.0, 1.42) : (1.05, 1.5)
        let leading: [RowItem] = context.showsGlobe ? [.key(Key(.nextKeyboard, width: .pitch(left)))] : []
        return leading + [
            .key(Key(.layer(layerKey), width: .pitch(left))),
            .key(Key(.space, width: .fill)),
            .key(Key(.layer(layerKey), width: .pitch(right))),
            .key(Key(.dismiss, width: .pitch(right))),
        ]
    }
}
