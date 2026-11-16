import CoreText
import UIKit

/// One line of text as a screenshot shows it, in points of the window.
struct InkLine {
    var top: Double
    var bottom: Double
    var minX: Double
    var maxX: Double
}

/// The text of a screenshot's field read as lines of ink, and a layout of a known text to match them against
/// (AppleFields, t707).
enum FieldInk {
    /// The lines of dark ink inside `frame` (points of the window), given the screenshot's `scale` in pixels per point.
    /// A pixel is ink when it's far darker than the field's background (the lightest common color), which leaves out
    /// light borders and shadows. `inset` keeps the frame's own edge out of it.
    static func lines(in image: CGImage, frame: CGRect, scale: Double, inset: Double = 2, darkness: Double = 110)
        -> [InkLine]
    {
        let width = image.width
        let height = image.height
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        let bytesPerPixel = image.bitsPerPixel / 8
        let rowBytes = image.bytesPerRow
        func luminance(_ x: Int, _ y: Int) -> Double {
            let pixel = bytes + y * rowBytes + x * bytesPerPixel
            return (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2]))
        }
        let x0 = max(0, Int((frame.minX + inset) * scale))
        let x1 = min(width, Int((frame.maxX - inset) * scale))
        let y0 = max(0, Int((frame.minY + inset) * scale))
        let y1 = min(height, Int((frame.maxY - inset) * scale))
        guard x1 > x0, y1 > y0 else { return [] }
        var histogram = [Int](repeating: 0, count: 256)
        for y in stride(from: y0, to: y1, by: 3) {
            for x in stride(from: x0, to: x1, by: 3) { histogram[Int(luminance(x, y))] += 1 }
        }
        let background = Double(histogram.enumerated().max { $0.element < $1.element }!.offset)
        var rows: [(y: Int, minX: Int, maxX: Int)] = []
        for y in y0..<y1 {
            var first = -1
            var last = -1
            for x in x0..<x1 where abs(luminance(x, y) - background) > darkness {
                if first < 0 { first = x }
                last = x
            }
            if first >= 0 { rows.append((y, first, last)) }
        }
        var lines: [InkLine] = []
        var current: [(y: Int, minX: Int, maxX: Int)] = []
        for row in rows {
            if let last = current.last, row.y - last.y > 1 {
                lines.append(line(current, scale))
                current = []
            }
            current.append(row)
        }
        if !current.isEmpty { lines.append(line(current, scale)) }
        return lines
    }

    private static func line(_ rows: [(y: Int, minX: Int, maxX: Int)], _ scale: Double) -> InkLine {
        InkLine(
            top: Double(rows.first!.y) / scale, bottom: Double(rows.last!.y + 1) / scale,
            minX: Double(rows.map(\.minX).min()!) / scale, maxX: Double(rows.map(\.maxX).max()! + 1) / scale)
    }

    /// Where each line of `text` breaks in a container `width` wide at `font`, as the substring and its ink bounds
    /// relative to the line's origin.
    static func layout(_ text: String, font: UIFont, width: Double)
        -> [(text: String, ink: CGRect)]
    {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var lines: [(text: String, ink: CGRect)] = []
        let whole = text as NSString
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) {
            _, _, _, glyphs, _ in
            let range = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let piece = whole.substring(with: range).trimmingCharacters(in: .whitespaces)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: piece, attributes: [.font: font]))
            lines.append((text: piece, ink: CTLineGetImageBounds(line, nil)))
        }
        return lines
    }

    struct Fit {
        var font: String
        var width: Double
        var origin: Double
        var spread: Double
    }

    /// Every (font, wrap width) whose layout of `text` breaks into as many lines as were seen and puts each line's ink
    /// where it was seen, for one text origin: the origin is the same for every line within `tolerance`.
    static func fits(
        _ text: String, seen: [InkLine], fonts: [(String, UIFont)], widths: StrideThrough<Double>,
        tolerance: Double = 1.0
    ) -> [Fit] {
        var found: [Fit] = []
        for (name, font) in fonts {
            for width in widths {
                let predicted = layout(text, font: font, width: width)
                guard predicted.count == seen.count else { continue }
                var origins: [Double] = []
                for (line, ink) in zip(seen, predicted) {
                    origins.append(line.minX - Double(ink.ink.minX))
                    origins.append(line.maxX - Double(ink.ink.maxX))
                }
                let spread = origins.max()! - origins.min()!
                if spread <= tolerance * 2 {
                    found.append(Fit(font: name, width: width, origin: origins.reduce(0, +) / Double(origins.count), spread: spread))
                }
            }
        }
        return found
    }
}
