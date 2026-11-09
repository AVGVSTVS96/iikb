import KeyboardCore
import KeyboardUI
import UIKit

/// The keyboard's menu, in the keys' place while the bar's More button is on (docs/design.md, "The menu"): a shelf for
/// each history, its name over its newest items in one row, a tap typing one and the name opening its panel. It fills a
/// keyboard grown as Chats' is, so the screen the keys don't need goes to what you pick from; layouts and iikb Settings
/// stay on holding 123, where you type. Under the shelves, a scroll away with the Theme shelf's name showing, the
/// keyboard's theme and stop animation, picked in place.
final class MenuView: UIView {
    var onOpen: (Panel) -> Void = { _ in }
    var onSettings: () -> Void = {}
    var onTheme: (ThemeName) -> Void = { _ in }
    var onStop: (StopAnimation) -> Void = { _ in }
    var onAppearance: () -> Void = {}
    /// iikb Settings, where there's no holding 123 to open it from (iPad).
    private let settings = UIButton(configuration: .plain())
    private var shelves: [(panel: Panel, head: ShelfHead, content: PanelResults)] = []
    private var block = (minX: CGFloat(0), maxX: CGFloat(0))
    private let scroll = ButtonScrollView()
    private let themeHead = ShelfHead("Theme", id: "theme", icon: "paintpalette.fill", color: .systemTeal)
    private let themes = LookStrip(ThemeName.allCases, width: 84) { theme in
        LookTile(theme.title, id: "theme.\(theme)", art: KeycapSwatchView())
    }
    private let stopHead = ShelfHead("Stop Animation", id: "stop", icon: "stop.fill", color: .systemRed)
    private let stops = LookStrip(StopAnimation.allCases, width: 84) { stop in
        let glyph = UIImageView(
            image: UIImage(
                systemName: stop.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        )
        glyph.contentMode = .center
        return LookTile(stop.title, id: "stop.\(stop)", art: glyph)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for head in [themeHead, stopHead] {
            head.addAction(UIAction { [unowned self] _ in onAppearance() }, for: .touchUpInside)
        }
        themes.onPick = { [unowned self] in onTheme($0) }
        stops.onPick = { [unowned self] in onStop($0) }
        scroll.alwaysBounceVertical = true
        addSubview(scroll)
        [themeHead, themes, stopHead, stops].forEach(scroll.addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Opens the menu with these shelves: each panel's results are reset, as a panel's are when it opens.
    func open(_ shelves: [(Panel, PanelResults)]) {
        self.shelves.forEach {
            $0.head.removeFromSuperview()
            $0.content.removeFromSuperview()
        }
        self.shelves = shelves.map { panel, content in
            let head = ShelfHead(panel.title, id: "\(panel)", image: panel.icon(14), color: panel.color)
            head.addAction(UIAction { [unowned self] _ in onOpen(panel) }, for: .touchUpInside)
            content.reset()
            scroll.addSubview(head)
            scroll.addSubview(content)
            return (panel, head, content)
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
        var row = metrics
        row.toolbar.results = rowHeight
        for shelf in shelves {
            shelf.head.show(theme)
            shelf.content.show(query: "", theme: theme, metrics: row)
        }
    }

    /// The theme and stop animation as the keyboard has them, `dark` the host's appearance, which the swatches follow.
    func show(look settings: KeyboardSettings, dark: Bool, theme: KeyboardTheme) {
        themeHead.show(theme)
        stopHead.show(theme)
        themes.show(picked: settings.theme, theme: theme) { name, tile in
            let appearance = name == settings.theme ? settings.themeAppearance : .automatic
            (tile.art as? KeycapSwatchView)?.show(name, appearance: appearance, dark: dark)
        }
        stops.show(picked: settings.stopAnimation, theme: theme)
    }

    private static let gap: CGFloat = 10, headHeight: CGFloat = 28, headGap: CGFloat = 6
    private static let themeRow: CGFloat = 78, stopRow: CGFloat = 62

    /// The histories share the menu's height but for the Theme shelf's name under them, which says the look's shelves
    /// are a scroll away; those keep their own heights.
    private var rowHeight: Double {
        let count = CGFloat(max(shelves.count, 1))
        let room = bounds.height - Self.headHeight - Self.gap * (count + 1) - (Self.headHeight + Self.headGap) * count
        return Double(max(min(room / count, 96), 0).rounded(.down))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let height = CGFloat(rowHeight)
        let width = block.maxX - block.minX
        var y = Self.gap
        for shelf in shelves {
            let head = min(ceil(shelf.head.sizeThatFits(bounds.size).width), width)
            shelf.head.frame = CGRect(x: block.minX, y: y, width: head, height: Self.headHeight)
            y += Self.headHeight + Self.headGap
            shelf.content.frame = CGRect(x: block.minX, y: y, width: width, height: height)
            y += height + Self.gap
        }
        for (head, strip, height) in [(themeHead, themes, Self.themeRow), (stopHead, stops, Self.stopRow)]
            as [(ShelfHead, UIView, CGFloat)]
        {
            let named = min(ceil(head.sizeThatFits(bounds.size).width), width)
            head.frame = CGRect(x: block.minX, y: y, width: named, height: Self.headHeight)
            y += Self.headHeight + Self.headGap
            strip.frame = CGRect(x: block.minX, y: y, width: width, height: height)
            y += height + Self.gap
        }
        scroll.contentSize = CGSize(width: bounds.width, height: y)
        let fits = ceil(settings.sizeThatFits(bounds.size).width)
        settings.frame = CGRect(x: block.maxX - fits, y: Self.gap, width: fits, height: Self.headHeight)
    }
}

/// A shelf's name: its glyph on a colored tile, as Home's cards have, then the name and a chevron; a tap opens the full
/// panel, or for the look's shelves, iikb's Appearance settings.
private final class ShelfHead: UIControl {
    private let tile = UIImageView()
    private let name = UILabel()
    private let more = UIImageView()

    convenience init(_ title: String, id: String, icon: String, color: UIColor) {
        let image = UIImage(
            systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        self.init(title, id: id, image: image, color: color)
    }

    init(_ title: String, id: String, image: UIImage?, color: UIColor) {
        super.init(frame: .zero)
        accessibilityIdentifier = "iikb.shelf.\(id)"
        accessibilityLabel = title
        accessibilityTraits = .button
        isAccessibilityElement = true
        tile.image = image?.withTintColor(.white, renderingMode: .alwaysOriginal)
        tile.contentMode = .center
        tile.backgroundColor = color
        tile.layer.cornerRadius = 7
        tile.layer.cornerCurve = .continuous
        name.text = title
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        more.image = UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        more.contentMode = .center
        [tile, name, more].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var theme = KeyboardTheme.lightCurrent

    func show(_ theme: KeyboardTheme) {
        self.theme = theme
        name.textColor = theme.label.ui
        more.tintColor = theme.candidate.ui
        refresh()
    }

    override var isHighlighted: Bool { didSet { refresh() } }

    private func refresh() {
        alpha = isHighlighted ? 0.5 : 1
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: 24 + 8 + ceil(name.intrinsicContentSize.width) + 6 + 10, height: 28)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 24
        tile.frame = CGRect(x: 0, y: (bounds.height - side) / 2, width: side, height: side)
        let text = tile.frame.maxX + 8
        let named = min(ceil(name.intrinsicContentSize.width), bounds.width - text - 16)
        name.frame = CGRect(x: text, y: 0, width: named, height: bounds.height)
        more.frame = CGRect(x: name.frame.maxX + 6, y: 0, width: 10, height: bounds.height)
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
