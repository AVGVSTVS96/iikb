import KeyboardCore
import UIKit

/// The text laid out as the field the keyboard types into lays it out, from what's measured of that field
/// (`HostField`), so the space bar trackpad moves up and down the lines the field wraps.
public struct HostLayout: LineLayout {
    public var width: CGFloat
    public var font: UIFont

    public init(width: CGFloat, font: UIFont) {
        self.width = width
        self.font = font
    }

    public func carets(in paragraph: String) -> [Caret] {
        let storage = NSTextStorage(string: paragraph, attributes: [.font: font])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        var lines: [NSRange] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) {
            _, _, _, glyphs, _ in
            lines.append(glyphs)
        }
        var carets: [Caret] = []
        var line = 0
        var offset = 0
        for character in paragraph {
            let glyph = manager.glyphIndexForCharacter(at: offset)
            while line < lines.count - 1, glyph >= NSMaxRange(lines[line]) { line += 1 }
            carets.append(Caret(line: line, x: manager.location(forGlyphAt: glyph).x))
            offset += character.utf16.count
        }
        let last = max(lines.count - 1, 0)
        carets.append(
            Caret(
                line: last,
                x: lines.isEmpty
                    ? 0 : manager.lineFragmentUsedRect(forGlyphAt: lines[last].location, effectiveRange: nil).maxX))
        return carets
    }
}
