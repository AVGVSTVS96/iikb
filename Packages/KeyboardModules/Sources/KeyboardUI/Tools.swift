import KeyboardCore
import UIKit

/// One of the buttons at the bar's left, the More button or a panel's tool: its glyph, with its title beside it where
/// the bar has room, in a circle that shows only while pressed, or while what it opened is out.
public final class BarButton: UIButton {
    public var theme = KeyboardTheme.lightCurrent {
        didSet {
            if theme.dark != oldValue.dark { glass.effect = UIGlassEffect.bar(theme) }
            refresh()
        }
    }
    var isOn = false { didSet { if isOn != oldValue { refresh() } } }
    /// Set on a circle of the bar's glass `glassSide` tall, in place of the on circle.
    public var glassy = false {
        didSet {
            guard glassy != oldValue else { return }
            glass.isHidden = !glassy
            refresh()
            setNeedsLayout()
        }
    }
    var glassSide = ChatTabs.height { didSet { if glassSide != oldValue { setNeedsLayout() } } }
    /// The title beside the glyph.
    var titled = false {
        didSet {
            guard titled != oldValue else { return }
            label.alpha = titled ? 1 : 0
            setNeedsLayout()
        }
    }
    private let glass = UIVisualEffectView(effect: UIGlassEffect.bar(.lightCurrent))
    private let draw: @MainActor (CGFloat) -> UIImage?
    private let icon = UIImageView()
    private let label = UILabel()
    private var glyph: CGFloat = 0
    private var reach = UIEdgeInsets.zero

    static let titleGap: CGFloat = 6

    /// `draw` makes the glyph to fit a square of a side.
    public init(_ title: String, draw: @escaping @MainActor (CGFloat) -> UIImage?) {
        self.draw = draw
        super.init(frame: .zero)
        accessibilityLabel = title
        icon.isUserInteractionEnabled = false
        icon.contentMode = .center
        label.text = title
        label.alpha = 0
        label.isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
        glass.isUserInteractionEnabled = false
        glass.isHidden = true
        glass.cornerConfiguration = .capsule()
        glass.clipsToBounds = true
        addSubview(glass)
        addSubview(icon)
        addSubview(label)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// How wide its glyph and title are side by side, a gap apart, with a glyph's room before and after them.
    func titledWidth(_ side: CGFloat) -> CGFloat {
        let ink = icon.image?.size.width ?? 0
        return ink + Self.titleGap + label.intrinsicContentSize.width.rounded(.up) + (side - ink)
    }

    override public var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { refresh() } }
    }

    /// `glyph` is the side of the square its glyph fits; taps out to `reach` around the circle still reach it.
    public func place(_ frame: CGRect, glyph: CGFloat, reach: UIEdgeInsets) {
        self.frame = frame
        self.reach = reach
        use(glyph: glyph)
    }

    /// Its glyph drawn to fit a `glyph` square, and its title in proportion with it.
    func use(glyph: CGFloat) {
        guard glyph != self.glyph else { return }
        self.glyph = glyph
        icon.image = draw(glyph)
        label.font = .systemFont(ofSize: (glyph * 0.7).rounded(), weight: .medium)
    }

    private func refresh() {
        icon.tintColor = theme.label.ui
        label.textColor = theme.label.ui
        backgroundColor = !glassy && (isHighlighted || isOn) ? theme.candidatePill.ui : .clear
        icon.alpha = glassy && isHighlighted ? 0.55 : 1
    }

    override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.inset(by: reach).contains(point)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        if titled {
            let ink = icon.image?.size.width ?? 0
            let text = label.intrinsicContentSize.width.rounded(.up)
            let start = ((bounds.width - ink - Self.titleGap - text) / 2).rounded()
            icon.frame = CGRect(x: start, y: 0, width: ink, height: bounds.height)
            label.frame = CGRect(x: start + ink + Self.titleGap, y: 0, width: text, height: bounds.height)
        } else {
            icon.frame = bounds
        }
        glass.frame = CGRect(
            x: bounds.midX - glassSide / 2, y: bounds.midY - glassSide / 2, width: glassSide, height: glassSide)
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }
}

extension KeyboardTheme {
    /// Drawn for dark, its label light.
    package var dark: Bool { label.red > 0.5 }
}

extension UIGlassEffect {
    /// The bar's glass: iOS's, tinted toward the label 8% in light and 12% in dark, as the menu's shelves are toward their
    /// color, so it stands off the keyboard's own glass.
    static func bar(_ theme: KeyboardTheme) -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.tintColor = theme.label.ui.withAlphaComponent(theme.dark ? 0.12 : 0.08)
        return effect
    }
}

/// One of the menu's edits in the bar: its glyph and title on a pill drawn as a key is, dimmed while it can't be done.
final class EditPill: UIButton {
    var theme = KeyboardTheme.lightCurrent { didSet { refresh() } }
    private let icon = UIImageView()
    private let label = UILabel()

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        accessibilityLabel = title
        icon.image = UIImage(
            systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        icon.contentMode = .center
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        [icon, label].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        layer.cornerCurve = .continuous
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool { didSet { refresh() } }
    override var isEnabled: Bool { didSet { refresh() } }

    private func refresh() {
        backgroundColor = isHighlighted ? theme.keyPressed.ui : theme.key.ui
        let tint = isEnabled ? theme.label.ui : theme.candidate.ui
        icon.tintColor = tint
        label.textColor = tint
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        let glyph = icon.image?.size.width ?? 0
        let spacing: CGFloat = 6
        let text = min(label.intrinsicContentSize.width, bounds.width - glyph - spacing - 16)
        let showsTitle = text >= 24
        label.isHidden = !showsTitle
        let total = showsTitle ? glyph + spacing + text : glyph
        let left = ((bounds.width - total) / 2).rounded()
        icon.frame = CGRect(x: left, y: 0, width: glyph, height: bounds.height)
        label.frame = CGRect(x: left + glyph + spacing, y: 0, width: max(text, 0), height: bounds.height)
    }
}

extension Panel {
    package var title: String {
        switch self {
        case .emoji: "Emoji"
        case .gif: "GIFs"
        case .clipboard: "Clipboard"
        case .transcripts: "Transcripts"
        case .chats: "Chats"
        }
    }

    /// The tool's glyph, filled as the More button's squares are, at one size with every tool's (`symbol`).
    package func icon(_ side: CGFloat) -> UIImage? {
        switch self {
        case .emoji: Self.symbol("face.smiling.inverse", side)
        case .gif: Self.gifGlyph(side, filled: true)
        case .clipboard: Self.symbol("list.clipboard.fill", side)
        case .transcripts: Self.symbol("text.bubble.fill", side)
        case .chats: Self.symbol("bubble.left.and.bubble.right.fill", side)
        }
    }

    /// A symbol scaled so its glyph, without the margins a symbol image carries, covers as much as a square 0.8 of
    /// `side` and stands no taller than that square, so a tall one (the clipboard) and a wide one (the bubble) read as one
    /// size beside each other; in its light appearance's shape, since iOS draws some filled in dark (`face.smiling`).
    static func symbol(_ name: String, _ side: CGFloat) -> UIImage? {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let configuration = UIImage.SymbolConfiguration(pointSize: side, weight: .regular).withTraitCollection(light)
        guard let image = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
        let ink = CGRect(origin: .zero, size: image.size).inset(by: image.alignmentRectInsets)
        let scale = min(
            0.8 * side / (ink.width * ink.height).squareRoot(), 0.8 * side / ink.height, side / ink.width)
        let size = CGSize(width: ink.width * scale, height: ink.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            light.performAsCurrent {
                image.withTintColor(.black).draw(
                    in: CGRect(
                        x: -ink.minX * scale, y: -ink.minY * scale, width: image.size.width * scale,
                        height: image.size.height * scale))
            }
        }.withRenderingMode(.alwaysTemplate)
    }

    /// Raycast's four rounded squares, for the More button, drawn in a `side` square. They span 0.72 of it, so the
    /// circle the button shows while the menu is out has room around them.
    public static func moreGlyph(_ side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        let extent = side * 0.72
        let gap = side * 0.11
        let square = (extent - gap) / 2
        return UIGraphicsImageRenderer(size: size).image { _ in
            let origin = (side - extent) / 2
            UIColor.black.setFill()
            for row in 0..<2 {
                for column in 0..<2 {
                    let rect = CGRect(
                        x: origin + CGFloat(column) * (square + gap), y: origin + CGFloat(row) * (square + gap),
                        width: square, height: square)
                    UIBezierPath(roundedRect: rect, cornerRadius: square * 0.28).fill()
                }
            }
        }.withRenderingMode(.alwaysTemplate)
    }

    /// GIF has no SF Symbol: a rounded rect with "GIF" in it, 0.88 of `side` wide, outlined as thin as the regular
    /// symbols' line or, `filled`, 0.76 wide, so its solid block weighs what a filled symbol does, with the letters cut
    /// out of it (docs/design.md).
    package static func gifGlyph(_ side: CGFloat, filled: Bool = false) -> UIImage {
        let unit = (filled ? 0.76 : 0.88) * side / 18.4
        let size = CGSize(width: 18.4 * unit, height: 14.4 * unit)
        return UIGraphicsImageRenderer(size: size).image { context in
            let box = CGRect(origin: .zero, size: size)
            UIColor.black.set()
            if filled {
                UIBezierPath(roundedRect: box, cornerRadius: 3.6 * unit).fill()
                context.cgContext.setBlendMode(.destinationOut)
            } else {
                let path = UIBezierPath(
                    roundedRect: box.insetBy(dx: 0.65 * unit, dy: 0.65 * unit), cornerRadius: 3.6 * unit)
                path.lineWidth = 1.3 * unit
                path.stroke()
            }
            let text = NSAttributedString(
                string: "GIF",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 8 * unit, weight: .bold), .foregroundColor: UIColor.black,
                ])
            let bounds = text.size()
            text.draw(at: CGPoint(x: box.midX - bounds.width / 2, y: box.midY - bounds.height / 2))
        }.withRenderingMode(.alwaysTemplate)
    }
}
