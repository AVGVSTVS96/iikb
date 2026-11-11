enum LargePadLayouts {
    static func layout(for context: LayoutContext) -> KeyboardLayout {
        switch context.layer {
        case .letters:
            if let iso = ISO.of(context.language, context.letters) { return letters(context, iso) }
            return KeyboardLayout(
                rows: [
                    numberRow,
                    [tab] + RowItem.keys("qwertyuiop[]\\", secondaries: "          {}|", pairs: true),
                    [capsLock] + RowItem.keys("asdfghjkl;'", secondaries: "         :\"", pairs: true) + [returnKey],
                    [shift] + RowItem.keys("zxcvbnm,./", secondaries: "       <>?", pairs: true) + [trailingShift],
                    bottomRow(context, layerKey: .numbers),
                ], hasNumberRow: true)
        case .numbers, .symbols:
            return KeyboardLayout(
                rows: [
                    RowItem.keys("`1234567890<>") + [.key(Key(.delete, width: .fill))],
                    [tab] + RowItem.keys("[]{}#%^*+=\\|~"),
                    [.key(Key(.undo, width: .pitch(1.77)))] + RowItem.keys("-/:;()$&@£¥") + [returnKey],
                    [.key(Key(.redo, width: .pitch(2.27))), .spacer(.input)] + RowItem.keys("….,?!'\"_€") + [
                        .spacer(.fill)
                    ],
                    bottomRow(context, layerKey: .letters),
                ], hasNumberRow: true)
        }
    }

    private static func letters(_ context: LayoutContext, _ iso: ISO) -> KeyboardLayout {
        let row = { (index: Int) in RowItem.keys(iso.rows[index], secondaries: iso.shifted[index], pairs: true) }
        return KeyboardLayout(
            rows: [
                row(0) + [.key(Key(.delete, width: .fill))],
                [tab] + row(1) + [returnKey],
                [capsLock] + row(2) + [returnKey],
                [.key(Key(.shift, width: .pitch(1.27)))] + row(3) + [trailingShift],
                bottomRow(context, layerKey: .numbers),
            ], hasNumberRow: true)
    }

    /// The European layouts of Apple's 13-inch iPad keyboard, its Magic Keyboard's: a key more on the top letter row,
    /// one between shift and the first letter, and return two rows tall, here a key on each row. Each row's keys are
    /// typed, then shifted. The accents type as themselves.
    struct ISO {
        var rows: [String]
        var shifted: [String]

        static func of(_ language: Language, _ letters: LetterLayout) -> ISO? {
            switch (language, letters) {
            case (.german, .german), (.german, .qwertz):
                ISO(
                    rows: ["^1234567890ß´", "qwertzuiopü+", "asdfghjklöä#", "<yxcvbnm,.-"],
                    shifted: ["°!\"§$%&/()=?`", "           *", "           '", ">       ;:_"])
            case (.swedish, _):
                ISO(
                    rows: ["§1234567890+´", "qwertyuiopå¨", "asdfghjklöä'", "<zxcvbnm,.-"],
                    shifted: ["°!\"#$%&/()=?`", "           ^", "           *", ">       ;:_"])
            case (.spanish, .spanish):
                ISO(
                    rows: ["º1234567890'¡", "qwertyuiop`+", "asdfghjklñ´ç", "<zxcvbnm,.-"],
                    shifted: ["ª!\"·$%&/()=?¿", "          ^*", "          ¨ ", ">       ;:_"])
            case (.french, .french), (.french, .azerty):
                ISO(
                    rows: ["@&é\"'(§è!çà)-", "azertyuiop^$", "qsdfghjklmù`", "<wxcvbn,;:="],
                    shifted: ["#1234567890°_", "          ¨*", "          %£", ">      ?./+"])
            case (.italian, .qwerty):
                ISO(
                    rows: ["\\1234567890'ì", "qwertyuiopè+", "asdfghjklòàù", "<zxcvbnm,.-"],
                    shifted: ["|!\"$€%&/()=?^", "          é*", "         ç°§", ">       ;:_"])
            default: nil
            }
        }
    }

    private static let numberRow: [RowItem] =
        RowItem.keys("`1234567890-=", secondaries: "~!@#$%^&*()_+", pairs: true) + [.key(Key(.delete, width: .fill))]
    private static let tab = RowItem.key(Key(.tab, width: .pitch(1.54)))
    private static let capsLock = RowItem.key(Key(.capsLock, width: .pitch(1.77)))
    private static let returnKey = RowItem.key(Key(.return, width: .fill))
    private static let shift = RowItem.key(Key(.shift, width: .pitch(2.27)))
    private static let trailingShift = RowItem.key(Key(.shift, width: .fill))

    private static func bottomRow(_ context: LayoutContext, layerKey: KeyboardLayer) -> [RowItem] {
        let right = context.isLandscape ? 2.13 : 2.14
        let leading: [RowItem] = context.showsGlobe ? [.key(Key(.nextKeyboard, width: .pitch(1.415)))] : []
        return leading + [
            .key(Key(.layer(layerKey), width: .pitch(1.415))),
            .key(Key(.space, width: .fill)),
            .key(Key(.layer(layerKey), width: .pitch(right))),
            .key(Key(.dismiss, width: .pitch(right))),
        ]
    }
}
