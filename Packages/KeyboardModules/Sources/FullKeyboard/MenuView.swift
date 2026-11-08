import KeyboardCore
import KeyboardUI
import UIKit

/// The keyboard's menu, in the keys' place while the bar's More button is on (docs/design.md, "The menu"): a shelf for
/// each history, its name over its newest items in one row, a tap typing one and the name opening its panel. It fills a
/// keyboard grown as Chats' is, so the screen the keys don't need goes to what you pick from; layouts and iikb Settings
/// stay on holding 123, where you type.
final class MenuView: UIView {
    var onOpen: (Panel) -> Void = { _ in }
    var onSettings: () -> Void = {}
    /// iikb Settings, where there's no holding 123 to open it from (iPad).
    private let settings = UIButton(configuration: .plain())
    private var shelves: [(panel: Panel, head: ShelfHead, content: PanelResults)] = []
    private var block = (minX: CGFloat(0), maxX: CGFloat(0))

    /// Opens the menu with these shelves: each panel's results are reset, as a panel's are when it opens.
    func open(_ shelves: [(Panel, PanelResults)]) {
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

    func show(
        settings shown: Bool, theme: KeyboardTheme, metrics: KeyboardMetrics, block: (minX: CGFloat, maxX: CGFloat)
    ) {
        if block != self.block || shown == settings.isHidden { setNeedsLayout() }
        self.block = block
        if settings.superview == nil {
            settings.accessibilityIdentifier = "iikb.menu.settings"
            settings.addAction(UIAction { [unowned self] _ in onSettings() }, for: .touchUpInside)
            addSubview(settings)
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

    private static let gap: CGFloat = 10, headHeight: CGFloat = 28, headGap: CGFloat = 6

    private var rowHeight: Double {
        let count = CGFloat(max(shelves.count, 1))
        let room = bounds.height - Self.gap * (count + 1) - (Self.headHeight + Self.headGap) * count
        return Double(max(min(room / count, 96), 0).rounded(.down))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
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
        let fits = ceil(settings.sizeThatFits(bounds.size).width)
        settings.frame = CGRect(x: block.maxX - fits, y: Self.gap, width: fits, height: Self.headHeight)
    }
}

/// A shelf's name: its glyph on a colored tile, as Home's cards have, then the name and a chevron; a tap opens the full
/// panel.
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
        tile.image = panel.icon(14)?.withTintColor(.white, renderingMode: .alwaysOriginal)
        tile.contentMode = .center
        tile.backgroundColor = panel.color
        tile.layer.cornerRadius = 7
        tile.layer.cornerCurve = .continuous
        name.text = panel.title
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
