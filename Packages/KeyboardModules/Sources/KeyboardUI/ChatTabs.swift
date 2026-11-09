import KeyboardCore
import UIKit

/// The chats as tabs in one capsule, as iOS's tab bar holds its tabs and Telegram's top bar its topics: each chat's
/// name, the open one on a platter that slides to the tab you pick on a spring, and the capsule hugging the tabs, or
/// scrolling with its cut ends faded when they don't fit. The capsule is iOS's Liquid Glass. Holding it lists every chat
/// in iOS's menu, the open one checked, so a chat far along the row is one pick away. A chat with something you haven't
/// seen has a dot after its name, in its padding, so marking it moves nothing.
public final class ChatTabs: UIView, UIContextMenuInteractionDelegate {
    /// A tab was tapped, by its index.
    public var onPick: (Int) -> Void = { _ in }

    private let track = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let scroll = ButtonScrollView()
    private let platter = UIView()
    private var tabs: [UIButton] = []
    private var dots: [UIView] = []
    private var fresh: Set<Int> = []
    private var names: [String] = []
    private var open: Int?
    private var theme = KeyboardTheme.lightCurrent
    /// The platter's tab as last laid out, so a new one slides there and the first is set in place.
    private var placed: Int?

    public static let height = 32.0
    private static let inset = 2.0
    private static let padding = 12.0
    private static let dot = 6.0

    override public init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "iikb.chats"
        track.cornerConfiguration = .capsule()
        track.clipsToBounds = true
        addSubview(track)
        scroll.fadesEnds = true
        scroll.fadeLength = 36
        scroll.alwaysBounceHorizontal = false
        track.contentView.addSubview(scroll)
        platter.isUserInteractionEnabled = false
        platter.layer.cornerCurve = .continuous
        scroll.addSubview(platter)
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show(_ names: [String], open: Int?, fresh: Set<Int> = [], theme: KeyboardTheme) {
        if names != self.names {
            self.names = names
            tabs.forEach { $0.removeFromSuperview() }
            dots.forEach { $0.removeFromSuperview() }
            tabs = names.enumerated().map { index, name in
                let tab = UIButton(configuration: .plain())
                tab.accessibilityIdentifier = "iikb.chat.\(index)"
                tab.accessibilityLabel = name
                tab.addAction(UIAction { [unowned self] _ in pick(index) }, for: .touchUpInside)
                scroll.addSubview(tab)
                return tab
            }
            dots = names.map { _ in
                let dot = UIView()
                dot.isUserInteractionEnabled = false
                dot.layer.cornerRadius = Self.dot / 2
                scroll.addSubview(dot)
                return dot
            }
            placed = nil
            setNeedsLayout()
        }
        if fresh != self.fresh {
            self.fresh = fresh
            setNeedsLayout()
        }
        let moved = open != self.open
        self.open = open
        self.theme = theme
        let dark = traitCollection.userInterfaceStyle == .dark
        platter.backgroundColor = UIColor(white: dark ? 1 : 0, alpha: dark ? 0.14 : 0.08)
        for (index, tab) in tabs.enumerated() {
            var look = UIButton.Configuration.plain()
            look.attributedTitle = AttributedString(
                names[index], attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]))
            look.baseForegroundColor = index == open ? theme.label.ui : theme.candidate.ui
            look.contentInsets = NSDirectionalEdgeInsets(
                top: 0, leading: Self.padding, bottom: 0, trailing: Self.padding)
            look.titleLineBreakMode = .byTruncatingTail
            tab.configuration = look
            tab.configurationUpdateHandler = { button in button.alpha = button.isHighlighted ? 0.55 : 1 }
            tab.accessibilityTraits = index == open ? [.button, .selected] : .button
            tab.accessibilityValue = fresh.contains(index) ? "New" : nil
            dots[index].backgroundColor = theme.prominent.ui
        }
        if moved { setNeedsLayout() }
    }

    /// The tapped tab's platter moves at once, before its chat has loaded.
    private func pick(_ index: Int) {
        guard index != open else { return }
        show(names, open: index, fresh: fresh.subtracting([index]), theme: theme)
        onPick(index)
    }

    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard names.count > 1 else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(
                children: names.enumerated().map { index, name in
                    UIAction(title: name, state: index == open ? .on : .off) { [weak self] _ in self?.pick(index) }
                })
        })
    }

    /// As wide as the tabs need, up to `width`.
    public func width(within width: CGFloat) -> CGFloat {
        min(tabWidths().reduce(2 * Self.inset, +), width)
    }

    private func tabWidths() -> [CGFloat] {
        tabs.map { min(ceil($0.sizeThatFits(CGSize(width: 220, height: Self.height)).width), 220) }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        scroll.frame = bounds
        var x = Self.inset
        let row = bounds.height - 2 * Self.inset
        for (tab, width) in zip(tabs, tabWidths()) {
            tab.frame = CGRect(x: x, y: Self.inset, width: width, height: row)
            x += width
        }
        for (index, (tab, dot)) in zip(tabs, dots).enumerated() {
            dot.isHidden = !fresh.contains(index)
            tab.layoutIfNeeded()
            let text = tab.titleLabel?.frame ?? .zero
            dot.frame = CGRect(
                x: tab.frame.minX + text.maxX + 3, y: tab.frame.midY - Self.dot / 2, width: Self.dot, height: Self.dot)
        }
        scroll.contentSize = CGSize(width: x + Self.inset, height: bounds.height)
        platter.layer.cornerRadius = row / 2
        guard let open, tabs.indices.contains(open) else {
            platter.isHidden = true
            return
        }
        platter.isHidden = false
        let target = tabs[open].frame
        let slides = placed != nil && placed != open && window != nil
        placed = open
        let visible = target.insetBy(dx: -40, dy: 0)
        let offset = min(
            max(scroll.contentOffset.x, visible.maxX - scroll.bounds.width), visible.minX,
            max(scroll.contentSize.width - scroll.bounds.width, 0))
        let settle = {
            self.platter.frame = target
            self.scroll.contentOffset.x = max(offset, 0)
        }
        if slides {
            UIView.animate(
                springDuration: 0.4, bounce: 0.18, initialSpringVelocity: 0, delay: 0, options: [.allowUserInteraction],
                animations: settle)
        } else {
            settle()
        }
    }
}
