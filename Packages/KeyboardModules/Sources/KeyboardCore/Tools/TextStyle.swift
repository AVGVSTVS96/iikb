/// Letters drawn in Unicode's own styles, which keep their look in any app, as Raycast's Text Styles are
/// (docs/design.md, "Text Styles").
public struct TextStyle: Hashable, Sendable {
    public let name: String
    /// A to Z, a to z and 0 to 9 in this style, in `plain`'s order.
    let forms: [Character]

    static let plain = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    private static let place = Dictionary(uniqueKeysWithValues: plain.enumerated().map { ($1, $0) })

    public static let all: [TextStyle] = [
        math("Bold Serif", 0x1D400, 0x1D41A, digits: 0x1D7CE),
        math("Italic Serif", 0x1D434, 0x1D44E, holes: ["h": 0x210E]),
        math("Bold Italic Serif", 0x1D468, 0x1D482),
        math("Bold Sans", 0x1D5D4, 0x1D5EE, digits: 0x1D7EC),
        math("Italic Sans", 0x1D608, 0x1D622),
        math(
            "Script", 0x1D49C, 0x1D4B6,
            holes: [
                "B": 0x212C, "E": 0x2130, "F": 0x2131, "H": 0x210B, "I": 0x2110, "L": 0x2112, "M": 0x2133, "R": 0x211B,
                "e": 0x212F, "g": 0x210A, "o": 0x2134,
            ]),
        math("Bold Script", 0x1D4D0, 0x1D4EA),
        math("Fraktur", 0x1D504, 0x1D51E, holes: ["C": 0x212D, "H": 0x210C, "I": 0x2111, "R": 0x211C, "Z": 0x2128]),
        math(
            "Double-Struck", 0x1D538, 0x1D552, digits: 0x1D7D8,
            holes: ["C": 0x2102, "H": 0x210D, "N": 0x2115, "P": 0x2119, "Q": 0x211A, "R": 0x211D, "Z": 0x2124]),
        math("Monospace", 0x1D670, 0x1D68A, digits: 0x1D7F6),
        TextStyle(name: "Circled", forms: run(0x24B6) + run(0x24D0) + Array("⓪①②③④⑤⑥⑦⑧⑨")),
        TextStyle(name: "Squared", forms: run(0x1F130) + run(0x1F130) + plain.suffix(10)),
        TextStyle(name: "Small Caps", forms: plain.prefix(26) + Array("ᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀꜱᴛᴜᴠᴡxʏᴢ") + plain.suffix(10)),
        TextStyle(name: "Wide", forms: run(0xFF21) + run(0xFF41) + run(0xFF10, count: 10)),
    ]

    /// Every styled form back to its plain letter, and the style it's in. A form the plain letter shares with its style
    /// (Small Caps' capitals) isn't styled; a form two letters share (Squared's) reads as the first, its capital.
    private static let styled: [Character: (plain: Character, style: Int)] = {
        var styled: [Character: (plain: Character, style: Int)] = [:]
        for (index, style) in all.enumerated() {
            for (plain, form) in zip(plain, style.forms) where form != plain && styled[form] == nil {
                styled[form] = (plain, index)
            }
        }
        return styled
    }()

    /// The text in this style, from its plain letters, so styling styled text changes its style.
    public func apply(to text: String) -> String {
        String(Self.plain(text).map { character in Self.place[character].map { forms[$0] } ?? character })
    }

    /// The text with every styled letter plain again.
    public static func plain(_ text: String) -> String {
        String(text.map { styled[$0]?.plain ?? $0 })
    }

    /// The character as a capital or a small letter, kept in its style where the style has that form.
    static func cased(_ character: Character, upper: Bool) -> String {
        guard let (plain, style) = styled[character] else {
            return upper ? character.uppercased() : character.lowercased()
        }
        let changed = Character(upper ? plain.uppercased() : plain.lowercased())
        return String(place[changed].map { all[style].forms[$0] } ?? character)
    }

    /// Whether the character is a letter that `cased` makes a capital or a small letter, styled or not.
    static func isLetter(_ character: Character) -> Bool {
        styled[character].map { $0.plain.isLetter } ?? character.isLetter
    }

    private static func math(
        _ name: String, _ upper: UInt32, _ lower: UInt32, digits: UInt32? = nil, holes: [Character: UInt32] = [:]
    ) -> TextStyle {
        var forms = run(upper) + run(lower) + (digits.map { run($0, count: 10) } ?? Array(plain.suffix(10)))
        for (letter, scalar) in holes {
            forms[place[letter]!] = Character(Unicode.Scalar(scalar)!)
        }
        return TextStyle(name: name, forms: forms)
    }

    private static func run(_ first: UInt32, count: UInt32 = 26) -> [Character] {
        (first..<first + count).map { Character(Unicode.Scalar($0)!) }
    }
}
