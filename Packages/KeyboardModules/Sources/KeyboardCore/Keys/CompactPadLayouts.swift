enum CompactPadLayouts {
    static func layout(for context: LayoutContext) -> KeyboardLayout {
        switch context.layer {
        case .letters:
            KeyboardLayout(rows: [
                RowItem.keys("qwertyuiop", secondaries: "1234567890") + [delete],
                [.spacer(.pitch(0.4))] + RowItem.keys("asdfghjkl", secondaries: "@#$&*()'\"") + [returnKey],
                [.key(Key(.shift))] + RowItem.keys("zxcvbnm", secondaries: "%-+=/;:") + RowItem.keys(",.", secondaries: "!?", pairs: true) + [.key(Key(.shift, width: .fill))],
                bottomRow(context, layerKey: .numbers),
            ])
        case .numbers:
            KeyboardLayout(rows: [
                RowItem.keys("1234567890") + [delete],
                [.spacer(.pitch(0.4))] + RowItem.keys("@#$&*()'\"", secondaries: "€£¥_^[]{}") + [returnKey],
                [.key(Key(.layer(.symbols)))] + RowItem.keys("%-+=/;:", secondaries: "§|~…\\<>") + RowItem.keys(",.", secondaries: "!?", pairs: true) + [.key(Key(.layer(.symbols), width: .fill))],
                bottomRow(context, layerKey: .letters),
            ])
        case .symbols:
            KeyboardLayout(rows: [
                RowItem.keys("1234567890") + [delete],
                [.spacer(.pitch(0.4))] + RowItem.keys("€£¥_^[]{}") + [returnKey],
                [.key(Key(.layer(.numbers)))] + RowItem.keys("§|~…\\<>!?") + [.key(Key(.layer(.numbers), width: .fill))],
                bottomRow(context, layerKey: .letters),
            ])
        }
    }

    private static let delete = RowItem.key(Key(.delete, width: .fill))
    private static let returnKey = RowItem.key(Key(.return, width: .fill))

    /// Apple's number layers put undo, or redo on the symbols, before the right layer key, and the three share the room
    /// the letters' two take.
    private static func bottomRow(_ context: LayoutContext, layerKey: KeyboardLayer) -> [RowItem] {
        let (left, right) = context.isLandscape ? (1.02, 1.52) : (1.04, 1.56)
        let leading: [RowItem] = context.showsGlobe ? [.key(Key(.nextKeyboard, width: .pitch(left)))] : []
        let trailing: [Key] = switch context.layer {
        case .letters: [Key(.layer(layerKey), width: .pitch(right)), Key(.dismiss, width: .pitch(right))]
        case .numbers: [Key(.undo, width: .pitch(left)), Key(.layer(layerKey), width: .pitch(left)), Key(.dismiss, width: .pitch(left))]
        case .symbols: [Key(.redo, width: .pitch(left)), Key(.layer(layerKey), width: .pitch(left)), Key(.dismiss, width: .pitch(left))]
        }
        return leading + [.key(Key(.layer(layerKey), width: .pitch(left))), .key(Key(.space, width: .fill))] + trailing.map(RowItem.key)
    }
}
