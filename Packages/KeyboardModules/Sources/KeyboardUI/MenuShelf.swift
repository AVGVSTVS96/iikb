import KeyboardCore
import UIKit

/// One shelf: its name down its side, then what it holds in one row, on a platter of iOS's Liquid Glass tinted faintly
/// with its tile's color. The name stays put as the row scrolls past it, and the row gets the shelf's whole height.
public final class MenuShelf: UIView {
    public let head: MenuShelfHead
    private let body: UIView
    private let color: UIColor
    private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private var dark: Bool?

    public static let radius = 22.0, inset = 6.0, side = 66.0
    /// The corners of what sits on a shelf, concentric with the shelf's.
    public static let inner = radius - inset
    /// A shelf's height beyond its row.
    public static let chrome = 2 * inset
    /// A row's least height: a card's line of text over its length and age, or two link badges.
    public static let shortest = 56.0

    public convenience init(_ title: String, id: String, icon: String, color: UIColor, _ body: UIView) {
        let image = UIImage(
            systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        self.init(title, id: id, image: image, color: color, body)
    }

    public init(_ title: String, id: String, image: UIImage?, color: UIColor, _ body: UIView) {
        head = MenuShelfHead(title, id: id, image: image, color: color)
        self.body = body
        self.color = color
        super.init(frame: .zero)
        glass.cornerConfiguration = .uniformCorners(radius: .fixed(Self.radius))
        glass.clipsToBounds = true
        addSubview(glass)
        body.layer.cornerRadius = Self.inner
        body.layer.cornerCurve = .continuous
        body.clipsToBounds = true
        glass.contentView.addSubview(head)
        glass.contentView.addSubview(body)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show(_ theme: KeyboardTheme) {
        head.show(theme)
        guard theme.dark != dark else { return }
        dark = theme.dark
        let effect = UIGlassEffect(style: .regular)
        effect.tintColor = color.withAlphaComponent(theme.dark ? 0.12 : 0.08)
        glass.effect = effect
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        let row = bounds.insetBy(dx: Self.inset, dy: Self.inset)
        head.frame = CGRect(x: row.minX, y: row.minY, width: Self.side, height: row.height)
        body.frame = CGRect(x: row.minX + Self.side, y: row.minY, width: row.width - Self.side, height: row.height)
    }
}

/// A shelf's name: its glyph on a colored tile, as Home's cards have, over the name; a tap opens the full panel, or for
/// the look's shelves, iikb's Appearance settings.
public final class MenuShelfHead: UIControl {
    private let tile = UIImageView()
    private let name = UILabel()

    init(_ title: String, id: String, image: UIImage?, color: UIColor) {
        super.init(frame: .zero)
        accessibilityIdentifier = "iikb.shelf.\(id)"
        accessibilityLabel = title
        accessibilityTraits = .button
        isAccessibilityElement = true
        tile.image = image?.withTintColor(.white, renderingMode: .alwaysOriginal)
        tile.contentMode = .center
        tile.backgroundColor = color
        tile.layer.cornerRadius = 9
        tile.layer.cornerCurve = .continuous
        name.text = title
        name.font = .systemFont(ofSize: 11, weight: .semibold)
        name.textAlignment = .center
        name.numberOfLines = 2
        [tile, name].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ theme: KeyboardTheme) {
        name.textColor = theme.label.ui
    }

    override public var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(springDuration: isHighlighted ? 0.16 : 0.3, bounce: 0, options: [.allowUserInteraction]) {
                self.tile.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
                self.name.alpha = self.isHighlighted ? 0.5 : 1
            }
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 32
        let named = ceil(name.sizeThatFits(CGSize(width: bounds.width, height: .infinity)).height)
        name.isHidden = bounds.height < side + 4 + named
        let top = ((bounds.height - side - (name.isHidden ? 0 : 4 + named)) / 2).rounded()
        tile.transform = .identity
        tile.frame = CGRect(x: (bounds.width - side) / 2, y: max(top, 0), width: side, height: side)
        name.frame = CGRect(x: 0, y: tile.frame.maxY + 4, width: bounds.width, height: named)
    }
}

extension Panel {
    /// Its tile's color, the one Home's card for it has.
    public var color: UIColor {
        switch self {
        case .emoji: .systemYellow
        case .clipboard: .systemOrange
        case .transcripts: .systemPink
        case .gif: .systemPurple
        case .chats: .systemIndigo
        }
    }
}
