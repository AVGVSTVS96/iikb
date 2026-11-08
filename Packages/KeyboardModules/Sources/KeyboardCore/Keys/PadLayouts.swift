enum PadLayouts {
    static func layout(for context: LayoutContext) -> KeyboardLayout {
        switch context.layer {
        case .letters:
            KeyboardLayout(rows: [
                [tab] + RowItem.keys("qwertyuiop", secondaries: "1234567890") + [delete],
                [capsLock] + RowItem.keys("asdfghjkl", secondaries: "@#$&*()'\"") + [returnKey],
                [.key(Key(.shift, width: .pitch(2)))] + RowItem.keys("zxcvbnm", secondaries: "%-+=/;:") + RowItem.keys(",.", secondaries: "!?", pairs: true) + [.key(Key(.shift, width: .fill))],
                bottomRow(context, layerKey: .numbers),
            ])
        case .numbers:
            KeyboardLayout(rows: [
                [tab] + RowItem.keys("1234567890") + [delete],
                [undo] + RowItem.keys("@#$&*()'\"", secondaries: "€£¥_^[]{}") + [returnKey],
                [.key(Key(.layer(.symbols), width: .pitch(2)))] + RowItem.keys("%-+=/;:", secondaries: "§|~…\\<>") + RowItem.keys(",.", secondaries: "!?", pairs: true) + [.key(Key(.layer(.symbols), width: .fill))],
                bottomRow(context, layerKey: .letters),
            ])
        case .symbols:
            KeyboardLayout(rows: [
                [tab] + RowItem.keys("1234567890") + [delete],
                [redo] + RowItem.keys("€£¥_^[]{}") + [returnKey],
                [.key(Key(.layer(.numbers), width: .pitch(2)))] + RowItem.keys("§|~…\\<>!?") + [.key(Key(.layer(.numbers), width: .fill))],
                bottomRow(context, layerKey: .letters),
            ])
        }
    }

    private static let tab = RowItem.key(Key(.tab, width: .pitch(1.25)))
    private static let delete = RowItem.key(Key(.delete, width: .fill))
    private static let capsLock = RowItem.key(Key(.capsLock, width: .pitch(1.55)))
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
