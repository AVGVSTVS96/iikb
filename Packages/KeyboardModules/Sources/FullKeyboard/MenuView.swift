import KeyboardCore
import KeyboardUI
import UIKit

/// The keyboard's menu, in the keys' place while the bar's More button is on (docs/design.md, "The menu"): a shelf for
/// each history, its name beside its newest items in one row, a tap typing one and the name opening its panel. It fills a
/// keyboard grown as Chats' is, so the screen the keys don't need goes to what you pick from; layouts and iikb Settings
/// stay on holding 123, where you type. Under the shelves, a scroll away with the Theme shelf's top showing, the
/// keyboard's theme and stop animation, picked in place.
final class MenuView: UIView {
    var onOpen: (Panel) -> Void = { _ in }
    var onSettings: () -> Void = {}
    var onTheme: (ThemeName) -> Void = { _ in }
    var onStop: (StopAnimation) -> Void = { _ in }
    var onAppearance: () -> Void = {}
    /// iikb Settings, where there's no holding 123 to open it from (iPad).
    private let settings = UIButton(configuration: .plain())
    private var shelves: [(panel: Panel, shelf: Shelf, content: PanelResults)] = []
    private var block = (minX: CGFloat(0), maxX: CGFloat(0))
    private let scroll = ButtonScrollView()
    /// Fades the shelves out under the bar as they scroll up, rather than cutting them off.
    private let fade = CAGradientLayer()
    private let themes = LookStrip(ThemeName.allCases, width: 84) { theme in
        LookTile(theme.title, id: "theme.\(theme)", art: KeycapSwatchView())
    }
    private let stops = LookStrip(StopAnimation.allCases, width: 84) { stop in
        let glyph = UIImageView(
            image: UIImage(
                systemName: stop.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        )
        glyph.contentMode = .center
        return LookTile(stop.title, id: "stop.\(stop)", art: glyph)
    }
    private lazy var themeShelf = Shelf("Theme", id: "theme", icon: "paintpalette.fill", color: .systemTeal, themes)
    private lazy var stopShelf = Shelf("Stop Animation", id: "stop", icon: "stop.fill", color: .systemRed, stops)

    override init(frame: CGRect) {
        super.init(frame: frame)
        for shelf in [themeShelf, stopShelf] {
            shelf.head.addAction(UIAction { [unowned self] _ in onAppearance() }, for: .touchUpInside)
        }
        themes.onPick = { [unowned self] in onTheme($0) }
        stops.onPick = { [unowned self] in onStop($0) }
        scroll.alwaysBounceVertical = true
        layer.mask = fade
        fade.colors = [UIColor.clear, .black].map(\.cgColor)
        addSubview(scroll)
        [themeShelf, stopShelf].forEach(scroll.addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Opens the menu with these shelves: each panel's results are reset, as a panel's are when it opens.
    func open(_ shelves: [(Panel, PanelResults)]) {
        self.shelves.forEach { $0.shelf.removeFromSuperview() }
        self.shelves = shelves.map { panel, content in
            let shelf = Shelf(panel.title, id: "\(panel)", image: panel.icon(16), color: panel.color, content)
            shelf.head.addAction(UIAction { [unowned self] _ in onOpen(panel) }, for: .touchUpInside)
            content.reset()
            scroll.insertSubview(shelf, belowSubview: themeShelf)
            return (panel, shelf, content)
        }
        scroll.contentOffset = .zero
        setNeedsLayout()
    }

    func show(
        settings shown: Bool, theme: KeyboardTheme, metrics: KeyboardMetrics, block: (minX: CGFloat, maxX: CGFloat)
    ) {
        if block != self.block || shown == settings.isHidden { setNeedsLayout() }
        self.block = block
        if settings.superview == nil {
            settings.accessibilityIdentifier = "iikb.menu.settings"
            settings.addAction(UIAction { [unowned self] _ in onSettings() }, for: .touchUpInside)
            scroll.addSubview(settings)
        }
        settings.isHidden = !shown
        var look = UIButton.Configuration.plain()
        look.image = UIImage(
            systemName: "gear", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        look.imagePadding = 5
        look.attributedTitle = AttributedString(
            "iikb Settings", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .medium)]))
        look.baseForegroundColor = theme.candidate.ui
        look.contentInsets = .zero
        settings.configuration = look
        overrideUserInterfaceStyle = theme.dark ? .dark : .light
        var row = metrics
        row.toolbar.results = rowHeight
        for (_, shelf, content) in shelves {
            shelf.show(theme)
            content.show(query: "", theme: theme, metrics: row)
        }
    }

    /// The theme and stop animation as the keyboard has them, `dark` the host's appearance, which the swatches follow.
    func show(look settings: KeyboardSettings, dark: Bool, theme: KeyboardTheme) {
        themeShelf.show(theme)
        stopShelf.show(theme)
        themes.show(picked: settings.theme, theme: theme) { name, tile in
            let appearance = name == settings.theme ? settings.themeAppearance : .automatic
            (tile.art as? KeycapSwatchView)?.show(name, appearance: appearance, dark: dark)
        }
        stops.show(picked: settings.stopAnimation, theme: theme)
    }

    private static let themeRow: CGFloat = 78, stopRow: CGFloat = 62
    /// The corners of a card on a shelf, concentric with the shelf's glass.
    static var cardRadius: CGFloat { Shelf.inner }

    private static let gap: CGFloat = 8

    /// Every shelf, the histories then the look's, top to bottom.
    private var all: [Shelf] { shelves.map(\.shelf) + [themeShelf, stopShelf] }

    /// The histories share the menu's height but for the top of the Theme shelf under them, which says the look's
    /// shelves are a scroll away; those keep their own heights.
    private var rowHeight: Double {
        let count = CGFloat(max(shelves.count, 1))
        let room = bounds.height - Self.gap - Shelf.peek - (Shelf.chrome + Self.gap) * count
        return Double(max(min(room / count, Shelf.tallest), 0).rounded(.down))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        fade.locations = [0, NSNumber(value: Self.gap / max(bounds.height, 1))]
        CATransaction.commit()
        let width = block.maxX - block.minX
        var y = Self.gap
        let rows = shelves.map { _ in CGFloat(rowHeight) } + [Self.themeRow, Self.stopRow]
        for (shelf, row) in zip(all, rows) {
            let height = row + Shelf.chrome
            shelf.frame = CGRect(x: block.minX, y: y, width: width, height: height)
            y += height + Self.gap
        }
        if !settings.isHidden {
            let fits = ceil(settings.sizeThatFits(bounds.size).width)
            settings.frame = CGRect(x: (bounds.width - fits) / 2, y: y, width: fits, height: 32)
            y = settings.frame.maxY + Self.gap
        }
        scroll.contentSize = CGSize(width: bounds.width, height: y)
    }
}

/// One shelf: its name down its side, then what it holds in one row, on a platter of iOS's Liquid Glass tinted faintly
/// with its tile's color. The name stays put as the row scrolls past it, and the row gets the shelf's whole height.
private final class Shelf: UIView {
    let head: ShelfHead
    private let body: UIView
    private let color: UIColor
    private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private var dark: Bool?

    static let radius = 22.0, inset = 6.0, side = 66.0
    /// The corners of what sits on a shelf, concentric with the shelf's.
    static let inner = radius - inset
    /// A shelf's height beyond its row.
    static let chrome = 2 * inset
    /// How much of the shelf under the histories shows, enough for its tile to say there's more.
    static let peek = 40.0
    static let tallest = 104.0

    convenience init(_ title: String, id: String, icon: String, color: UIColor, _ body: UIView) {
        let image = UIImage(
            systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        self.init(title, id: id, image: image, color: color, body)
    }

    init(_ title: String, id: String, image: UIImage?, color: UIColor, _ body: UIView) {
        head = ShelfHead(title, id: id, image: image, color: color)
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

    func show(_ theme: KeyboardTheme) {
        head.show(theme)
        guard theme.dark != dark else { return }
        dark = theme.dark
        let effect = UIGlassEffect(style: .regular)
        effect.tintColor = color.withAlphaComponent(theme.dark ? 0.12 : 0.08)
        glass.effect = effect
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        let row = bounds.insetBy(dx: Self.inset, dy: Self.inset)
        head.frame = CGRect(x: row.minX, y: row.minY, width: Self.side, height: row.height)
        body.frame = CGRect(x: row.minX + Self.side, y: row.minY, width: row.width - Self.side, height: row.height)
    }
}

/// A shelf's name: its glyph on a colored tile, as Home's cards have, over the name; a tap opens the full panel, or for
/// the look's shelves, iikb's Appearance settings.
private final class ShelfHead: UIControl {
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

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(springDuration: isHighlighted ? 0.16 : 0.3, bounce: 0, options: [.allowUserInteraction]) {
                self.tile.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
                self.name.alpha = self.isHighlighted ? 0.5 : 1
            }
        }
    }

    override func layoutSubviews() {
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
    fileprivate var color: UIColor {
        switch self {
        case .clipboard: .systemOrange
        case .transcripts: .systemPink
        case .gif: .systemPurple
        case .chats: .systemIndigo
        default: .systemBlue
        }
    }
}
