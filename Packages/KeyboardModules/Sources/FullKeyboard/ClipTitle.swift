import KeyboardCore
import KeyboardStore
import UIKit

/// How a clip is written in a row, a link's badge and a held clip's preview (docs/design.md, "Clipboard"): plain text as
/// it is; a link as its site's icon and its site; an address or a phone number after its glyph; a color after a swatch
/// of it. Nil for plain text and images, which rows show as they always have.
enum ClipTitle {
    /// `short` names a link's site as ChatGPT's source pills do, `ClipLink.name`, as a badge has it.
    static func make(_ content: ClipboardHistory.Item.Content, font: UIFont, label: UIColor, secondary: UIColor, short: Bool = false) -> NSAttributedString? {
        guard case .text(let text) = content else { return nil }
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let size = (font.pointSize * 1.1).rounded()
        let body: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: label]
        let title = NSMutableAttributedString()
        func glyph(_ image: UIImage?) {
            guard let image else { return }
            let attachment = NSTextAttachment(image: image)
            attachment.bounds = CGRect(x: 0, y: ((font.capHeight - size) / 2).rounded(), width: size, height: size)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: "\u{2002}", attributes: body))
        }
        func symbol(_ name: String) -> UIImage? {
            UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: font.pointSize * 0.8, weight: .medium))?
                .withTintColor(secondary, renderingMode: .alwaysOriginal)
        }
        switch content.kind {
        case .text, .image: return nil
        case .link(let link):
            glyph(LinkIcons.shared.cached(link.site) ?? symbol("globe"))
            title.append(NSAttributedString(string: short ? link.name : link.site, attributes: [.font: font.withWeight(.semibold), .foregroundColor: label]))
        case .email:
            glyph(symbol("envelope"))
            title.append(NSAttributedString(string: plain, attributes: body))
        case .phone:
            glyph(symbol("phone"))
            title.append(NSAttributedString(string: plain, attributes: body))
        case .color(let red, let green, let blue):
            glyph(swatch(UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1), edge: secondary, side: size))
            title.append(NSAttributedString(string: plain.uppercased(), attributes: [.font: UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular), .foregroundColor: label]))
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        title.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: title.length))
        return title
    }

    /// A held link's preview heading: its site's icon and its site, over the whole link.
    static func heading(_ content: ClipboardHistory.Item.Content) -> NSAttributedString? {
        guard case .link(let link) = content.kind else { return nil }
        return make(.text("https://" + link.site), font: .systemFont(ofSize: 17), label: .label, secondary: .secondaryLabel)
    }

    /// A link's badge, on one line: its icon, its site's name and how long ago, `github · 5m`, with a pin when pinned.
    static func badge(_ content: ClipboardHistory.Item.Content, age: String, pinned: Bool, font: UIFont, label: UIColor, secondary: UIColor) -> NSAttributedString? {
        guard let title = make(content, font: font, label: label, secondary: secondary, short: true)?.mutableCopy() as? NSMutableAttributedString else { return nil }
        let detail: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular), .foregroundColor: secondary]
        title.append(NSAttributedString(string: " · " + age, attributes: detail))
        if pinned, let pin = UIImage(systemName: "pin.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: font.pointSize * 0.75))?.withTintColor(secondary, renderingMode: .alwaysOriginal) {
            title.append(NSAttributedString(string: " ", attributes: detail))
            let attachment = NSTextAttachment(image: pin)
            attachment.bounds = CGRect(x: 0, y: ((font.capHeight - pin.size.height) / 2).rounded(), width: pin.size.width, height: pin.size.height)
            title.append(NSAttributedString(attachment: attachment))
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        title.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: title.length))
        return title
    }

    /// The site whose icon a link's title shows, or nil when it's not a link.
    static func site(_ content: ClipboardHistory.Item.Content) -> String? {
        guard case .link(let link) = content.kind else { return nil }
        return link.site
    }

    private static func swatch(_ color: UIColor, edge: UIColor, side: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(x: 0.5, y: 0.5, width: side - 1, height: side - 1))
            color.setFill()
            circle.fill()
            edge.withAlphaComponent(0.4).setStroke()
            circle.lineWidth = 1
            circle.stroke()
        }
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont { .systemFont(ofSize: pointSize, weight: weight) }
}
