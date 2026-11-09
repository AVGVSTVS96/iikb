import KeyboardCore
import UIKit

/// One of the buttons at the bar's left, the More button or a panel's tool: its glyph, in a circle that shows only while
/// pressed, or while what it opened is out.
public final class BarButton: UIButton {
    public var theme = KeyboardTheme.lightCurrent { didSet { refresh() } }
    var isOn = false { didSet { if isOn != oldValue { refresh() } } }
    /// Set on a circle of iOS's glass as tall as `ChatTabs`, beside them while a chat is read, in place of the on circle.
    public var glassy = false {
        didSet {
            guard glassy != oldValue else { return }
            glass.isHidden = !glassy
            refresh()
            setNeedsLayout()
        }
    }
    private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let draw: @MainActor (CGFloat) -> UIImage?
    private let icon = UIImageView()
    private var glyph: CGFloat = 0
    private var reach = UIEdgeInsets.zero

    /// `draw` makes the glyph to fit a square of a side.
    public init(_ title: String, draw: @escaping @MainActor (CGFloat) -> UIImage?) {
        self.draw = draw
        super.init(frame: .zero)
        accessibilityLabel = title
        icon.isUserInteractionEnabled = false
        icon.contentMode = .center
        layer.cornerCurve = .continuous
        glass.isUserInteractionEnabled = false
        glass.isHidden = true
        glass.cornerConfiguration = .capsule()
        glass.clipsToBounds = true
        addSubview(glass)
        addSubview(icon)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override public var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { refresh() } }
    }

    /// `glyph` is the side of the square its glyph fits; taps out to `reach` around the circle still reach it.
    public func place(_ frame: CGRect, glyph: CGFloat, reach: UIEdgeInsets) {
        self.frame = frame
        self.reach = reach
        guard glyph != self.glyph else { return }
        self.glyph = glyph
        icon.image = draw(glyph)
    }

    private func refresh() {
        icon.tintColor = theme.label.ui
        backgroundColor = !glassy && (isHighlighted || isOn) ? theme.candidatePill.ui : .clear
        icon.alpha = glassy && isHighlighted ? 0.55 : 1
    }

    override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.inset(by: reach).contains(point)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = bounds
        let side = ChatTabs.height
        glass.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
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

    /// The tool's glyph, its longer side `side` long, so every tool and the More button read as one size.
    package func icon(_ side: CGFloat) -> UIImage? {
        switch self {
        case .emoji: Self.symbol("face.smiling", side)
        case .gif: Self.gifGlyph(side)
        case .clipboard: Self.symbol("list.clipboard", side)
        case .transcripts: Self.symbol("text.bubble", side)
        case .chats: Self.symbol("bubble.left.and.bubble.right", side)
        }
    }

    /// A symbol scaled so its glyph, without the margins a symbol image carries, is `side` long on its longer side, in
    /// its light appearance's shape, since iOS draws some filled in dark (`face.smiling`).
    static func symbol(_ name: String, _ side: CGFloat) -> UIImage? {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let configuration = UIImage.SymbolConfiguration(pointSize: side, weight: .regular).withTraitCollection(light)
        guard let image = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
        let ink = CGRect(origin: .zero, size: image.size).inset(by: image.alignmentRectInsets)
        let scale = side / max(ink.width, ink.height)
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

    /// GIF has no SF Symbol: a rounded rect with "GIF" in it, `side` wide (docs/design.md).
    package static func gifGlyph(_ side: CGFloat) -> UIImage {
        let unit = side / 18.4
        let size = CGSize(width: side, height: 14.4 * unit)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(
                roundedRect: box.insetBy(dx: 0.85 * unit, dy: 0.85 * unit), cornerRadius: 3.6 * unit)
            path.lineWidth = 1.7 * unit
            UIColor.black.setStroke()
            path.stroke()
            let text = NSAttributedString(
                string: "GIF",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 8 * unit, weight: .heavy), .foregroundColor: UIColor.black,
                ])
            let bounds = text.size()
            text.draw(at: CGPoint(x: box.midX - bounds.width / 2, y: box.midY - bounds.height / 2))
        }.withRenderingMode(.alwaysTemplate)
    }
}
