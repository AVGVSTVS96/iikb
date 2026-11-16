import KeyboardCore
import KeyboardUI
import UIKit

/// The keyboard's menu, in the keys' place while the bar's More button is on (docs/design.md, "The menu"): a shelf for
/// each history, its name beside its newest items in one row, a tap typing one and the name opening its panel. It takes
/// the keys' place at their height, so nothing above it moves as it opens; layouts and iikb Settings stay on holding 123,
/// where you type. Under the shelves, a scroll away, the keyboard's theme and stop animation, picked in place.
final class MenuView: UIView {
    var onOpen: (Panel) -> Void = { _ in }
    var onSettings: () -> Void = {}
    var onTheme: (ThemeName) -> Void = { _ in }
    var onStop: (StopAnimation) -> Void = { _ in }
    var onAppearance: () -> Void = {}
    /// iikb Settings, where there's no holding 123 to open it from (iPad).
    private let settings = UIButton(configuration: .plain())
    private var shelves: [(panel: Panel, shelf: MenuShelf, content: PanelResults)] = []
    private var block = (minX: CGFloat(0), maxX: CGFloat(0))
    private let scroll = ButtonScrollView()
    /// The menu just opened, so its scroll bar shows once laid out, saying what's a scroll away.
    private var opened = false
    /// Fades the shelves out under the bar as they scroll up, and the next shelf's glow at the bottom, rather than
    /// cutting them off.
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
    private lazy var themeShelf = MenuShelf("Theme", id: "theme", icon: "paintpalette.fill", color: .systemTeal, themes)
    private lazy var stopShelf = MenuShelf("Stop Animation", id: "stop", icon: "stop.fill", color: .systemRed, stops)

    override init(frame: CGRect) {
        super.init(frame: frame)
        for shelf in [themeShelf, stopShelf] {
            shelf.head.addAction(UIAction { [unowned self] _ in onAppearance() }, for: .touchUpInside)
        }
        themes.onPick = { [unowned self] in onTheme($0) }
        stops.onPick = { [unowned self] in onStop($0) }
        scroll.alwaysBounceVertical = true
        layer.mask = fade
        fade.colors = [UIColor.clear, .black, .black, .clear].map(\.cgColor)
        addSubview(scroll)
        [themeShelf, stopShelf].forEach(scroll.addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Opens the menu with these shelves: each panel's results are reset, as a panel's are when it opens.
    func open(_ shelves: [(Panel, PanelResults)]) {
        self.shelves.forEach { $0.shelf.removeFromSuperview() }
        self.shelves = shelves.map { panel, content in
            let shelf = MenuShelf(panel.title, id: "\(panel)", image: panel.icon(16), color: panel.color, content)
            shelf.head.addAction(UIAction { [unowned self] _ in onOpen(panel) }, for: .touchUpInside)
            content.reset()
            scroll.insertSubview(shelf, belowSubview: themeShelf)
            return (panel, shelf, content)
        }
        scroll.contentOffset = .zero
        opened = true
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
    static var cardRadius: CGFloat { MenuShelf.inner }

    private static let gap: CGFloat = 8

    /// Every shelf, the histories then the look's, top to bottom.
    private var all: [MenuShelf] { shelves.map(\.shelf) + [themeShelf, stopShelf] }

    /// The histories share the menu's height in whole shelves, as many as fit `MenuShelf.shortest` tall, so none is cut off at
    /// the bottom or leaves a gap under it, and the cards' text fills them; the rest, and the look's shelves at their own heights, are a scroll
    /// away.
    private var rowHeight: Double {
        let room = bounds.height - Self.gap
        let fits = Int(room / (MenuShelf.shortest + MenuShelf.chrome + Self.gap))
        let shown = CGFloat(max(min(fits, shelves.count), 1))
        return Double(max(room / shown - MenuShelf.chrome - Self.gap, 0))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        let edge = Self.gap / max(bounds.height, 1)
        fade.locations = [0, edge, 1 - edge, 1].map { NSNumber(value: $0) }
        CATransaction.commit()
        let width = block.maxX - block.minX
        var y = Self.gap
        let rows = shelves.map { _ in CGFloat(rowHeight) } + [Self.themeRow, Self.stopRow]
        for (shelf, row) in zip(all, rows) {
            let height = row + MenuShelf.chrome
            shelf.frame = CGRect(x: block.minX, y: y, width: width, height: height)
            y += height + Self.gap
        }
        if !settings.isHidden {
            let fits = ceil(settings.sizeThatFits(bounds.size).width)
            settings.frame = CGRect(x: (bounds.width - fits) / 2, y: y, width: fits, height: 32)
            y = settings.frame.maxY + Self.gap
        }
        scroll.contentSize = CGSize(width: bounds.width, height: y)
        if opened, bounds.height > 0 {
            opened = false
            scroll.flashScrollIndicators()
        }
    }
}
