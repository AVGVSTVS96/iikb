import KeyboardCore
import KeyboardUI
import UIKit

/// The keyboard's menu, in the keys' place while the bar's More button is on (docs/design.md, "The menu"): a shelf for
/// each history, its name and then its newest items in one row, a tap typing one and the name opening its panel, over
/// the layouts, Next Keyboard and iikb Settings.
final class MenuView: UIView {
    var onOpen: (Panel) -> Void = { _ in }
    var onEvent: (KeyboardEvent) -> Void = { _ in }
    private var shelves: [(panel: Panel, head: ShelfHead, content: PanelContent)] = []
    private var footer: [(event: KeyboardEvent, button: UIButton)] = []
    private var picked: KeyboardEvent?
    private var block = (minX: CGFloat(0), maxX: CGFloat(0))
    private var theme = KeyboardTheme.lightCurrent

    /// Opens the menu with these shelves: each panel's results are reset, as a panel's are when it opens.
    func open(_ shelves: [(Panel, PanelContent)]) {
        self.shelves.forEach {
            $0.head.removeFromSuperview()
            $0.content.removeFromSuperview()
        }
        self.shelves = shelves.map { panel, content in
            let head = ShelfHead(panel)
            head.addAction(UIAction { [unowned self] _ in onOpen(panel) }, for: .touchUpInside)
            content.reset()
            addSubview(head)
            addSubview(content)
            return (panel, head, content)
        }
        setNeedsLayout()
    }

    /// `footer` are the More button's items, `picked` the layout in use among them.
    func show(footer events: [KeyboardEvent], picked: KeyboardEvent, theme: KeyboardTheme, metrics: KeyboardMetrics, block: (minX: CGFloat, maxX: CGFloat)) {
        if events != footer.map(\.event) {
            footer.forEach { $0.button.removeFromSuperview() }
            footer = events.map { event in
                let button = UIButton(type: .custom)
                button.accessibilityIdentifier = "iikb.menu.\(event.title)"
                button.accessibilityLabel = event.title
                button.layer.cornerCurve = .continuous
                button.addAction(UIAction { [unowned self] _ in onEvent(event) }, for: .touchUpInside)
                addSubview(button)
                return (event, button)
            }
            setNeedsLayout()
        }
        if picked != self.picked || theme != self.theme || block != self.block { setNeedsLayout() }
        self.picked = picked
        self.theme = theme
        self.block = block
        var row = metrics
        row.toolbar.results = shelfHeight
        for shelf in shelves {
            shelf.head.show(theme)
            shelf.content.show(query: "", theme: theme, metrics: row)
        }
    }

    private static let footerHeight: CGFloat = 36, gap: CGFloat = 8, headWidth: CGFloat = 136

    private var shelfHeight: Double {
        let room = bounds.height - Self.footerHeight - Self.gap * CGFloat(shelves.count + 2)
        return Double(max(min(room / CGFloat(max(shelves.count, 1)), 60), 0).rounded(.down))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = CGFloat(shelfHeight)
        var y = Self.gap
        for shelf in shelves {
            shelf.head.frame = CGRect(x: block.minX, y: y, width: Self.headWidth, height: height)
            shelf.content.frame = CGRect(x: block.minX + Self.headWidth + Self.gap, y: y, width: block.maxX - block.minX - Self.headWidth - Self.gap, height: height)
            y += height + Self.gap
        }
        let wide = block.maxX - block.minX > 600
        let row = CGRect(x: block.minX, y: y, width: block.maxX - block.minX, height: Self.footerHeight)
        let layouts = footer.filter { $0.event != .settings && $0.event != .nextKeyboard }
        let ends = footer.filter { $0.event == .settings || $0.event == .nextKeyboard }
        var left = row.minX
        for (event, button) in layouts {
            style(button, event: event, titled: true, on: event == picked)
            let width = ceil(button.intrinsicContentSize.width) + 24
            button.frame = CGRect(x: left, y: row.minY, width: width, height: row.height)
            left += width + 4
        }
        var right = row.maxX
        for (event, button) in ends.reversed() {
            style(button, event: event, titled: wide, on: false)
            let width = wide ? ceil(button.intrinsicContentSize.width) + 28 : 48
            button.frame = CGRect(x: right - width, y: row.minY, width: width, height: row.height)
            right -= width + Self.gap
        }
    }

    /// Each layout says its name and shows filled while it's the one in use; Next Keyboard and Settings say theirs where
    /// the bar is wide.
    private func style(_ button: UIButton, event: KeyboardEvent, titled: Bool, on: Bool) {
        let image = UIImage(systemName: event.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        button.setImage(image, for: .normal)
        button.setTitle(titled ? " " + event.title : nil, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.setTitleColor(theme.label.ui, for: .normal)
        let layout = event != .settings && event != .nextKeyboard
        button.tintColor = !layout || on ? theme.label.ui : theme.candidate.ui
        button.backgroundColor = on ? theme.keyPressed.ui : theme.key.ui
        button.layer.cornerRadius = Self.footerHeight / 2
    }
}

/// A shelf's name: its glyph on a colored tile, as Home's cards have, over the name; a tap opens the full panel.
private final class ShelfHead: UIControl {
    private let tile = UIImageView()
    private let name = UILabel()
    private let more = UIImageView()

    init(_ panel: Panel) {
        super.init(frame: .zero)
        accessibilityIdentifier = "iikb.shelf.\(panel)"
        accessibilityLabel = panel.title
        accessibilityTraits = .button
        isAccessibilityElement = true
        tile.image = panel.icon(16)?.withTintColor(.white, renderingMode: .alwaysOriginal)
        tile.contentMode = .center
        tile.backgroundColor = panel.color
        tile.layer.cornerRadius = 8
        tile.layer.cornerCurve = .continuous
        name.text = panel.title
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.75
        more.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 30
        tile.frame = CGRect(x: 0, y: (bounds.height - side) / 2, width: side, height: side)
        let text = tile.frame.maxX + 8
        more.frame = CGRect(x: bounds.width - 14, y: 0, width: 10, height: bounds.height)
        name.frame = CGRect(x: text, y: 0, width: more.frame.minX - text - 2, height: bounds.height)
    }
}

private extension Panel {
    /// Its tile's color, the one Home's card for it has.
    var color: UIColor {
        switch self {
        case .clipboard: .systemOrange
        case .transcripts: .systemPink
        case .gif: .systemPurple
        default: .systemBlue
        }
    }
}
