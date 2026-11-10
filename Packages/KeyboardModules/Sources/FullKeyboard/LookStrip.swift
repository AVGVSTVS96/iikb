import KeyboardCore
import KeyboardUI
import UIKit

/// A menu row of the keyboard's look, one choice picked, scrolling sideways where the choices don't fit: the themes,
/// each as its keycaps, or the stop animations, each as its glyph. A tap picks at once, without leaving for the app.
final class LookStrip<Choice: Hashable>: UIView {
    var onPick: (Choice) -> Void = { _ in }
    private let row = ButtonScrollView()
    private let tiles: [(choice: Choice, tile: LookTile)]
    private let width: CGFloat

    init(_ choices: [Choice], width: CGFloat, tile: (Choice) -> LookTile) {
        self.width = width
        tiles = choices.map { ($0, tile($0)) }
        super.init(frame: .zero)
        row.fadesEnds = true
        addSubview(row)
        for (choice, tile) in tiles {
            tile.addAction(
                UIAction { [unowned self, unowned tile] _ in
                    guard !tile.picked else { return }
                    onPick(choice)
                }, for: .touchUpInside)
            row.addSubview(tile)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(picked: Choice, theme: KeyboardTheme, art: (Choice, LookTile) -> Void = { _, _ in }) {
        for (choice, tile) in tiles {
            tile.show(picked: choice == picked, theme: theme)
            art(choice, tile)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        row.frame = bounds
        let gap: CGFloat = 8
        for (index, (_, tile)) in tiles.enumerated() {
            tile.frame = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: bounds.height)
        }
        row.contentSize = CGSize(width: CGFloat(tiles.count) * (width + gap) - gap, height: bounds.height)
    }
}

/// One choice: its art over its name on a card in the key fill, ringed in the theme's blue while it's the one picked.
final class LookTile: UIControl {
    let art: UIView
    private let name = UILabel()
    private let card = UIView()
    private let ring = UIView()
    private(set) var picked = false
    private var theme = KeyboardTheme.lightCurrent

    init(_ title: String, id: String, art: UIView) {
        self.art = art
        super.init(frame: .zero)
        accessibilityIdentifier = "iikb.look.\(id)"
        accessibilityLabel = title
        isAccessibilityElement = true
        name.text = title
        name.textAlignment = .center
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.8
        for view in [card, ring] { view.layer.cornerCurve = .continuous }
        ring.layer.borderWidth = 2
        [ring, card, art, name].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(picked: Bool, theme: KeyboardTheme) {
        let picks = picked && !self.picked && window != nil
        self.picked = picked
        self.theme = theme
        accessibilityTraits = picked ? [.button, .selected] : .button
        card.backgroundColor = theme.shelfCard
        name.textColor = picked ? theme.label.ui : theme.candidate.ui
        name.font = .systemFont(ofSize: 12, weight: picked ? .semibold : .medium)
        art.tintColor = picked ? theme.record.ui : theme.label.ui
        ring.layer.borderColor = theme.prominent.ui.cgColor
        guard picks else {
            ring.alpha = picked ? 1 : 0
            ring.transform = .identity
            return
        }
        ring.alpha = 0
        ring.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        UIView.animate(springDuration: 0.35, bounce: 0.3, options: [.allowUserInteraction]) {
            self.ring.alpha = 1
            self.ring.transform = .identity
        }
        (art as? UIImageView)?.addSymbolEffect(.bounce)
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(springDuration: isHighlighted ? 0.16 : 0.3, bounce: 0, options: [.allowUserInteraction]) {
                self.card.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
                self.art.alpha = self.isHighlighted ? 0.6 : 1
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 3
        card.transform = .identity
        card.frame = bounds.insetBy(dx: inset, dy: inset)
        card.layer.cornerRadius = MenuView.cardRadius - inset
        ring.frame = bounds
        ring.layer.cornerRadius = MenuView.cardRadius
        let label: CGFloat = 16
        name.frame = CGRect(x: inset + 4, y: card.frame.maxY - label - 5, width: card.frame.width - 8, height: label)
        art.frame = CGRect(
            x: card.frame.minX + 6, y: card.frame.minY + 5, width: card.frame.width - 12,
            height: max(name.frame.minY - card.frame.minY - 7, 0))
    }
}

extension StopAnimation {
    /// Its glyph in the menu: the recording squeezed, a drop, a card lifting away.
    var symbol: String {
        switch self {
        case .squeeze: "rectangle.arrowtriangle.2.inward"
        case .drain: "drop.fill"
        case .card: "rectangle.fill.on.rectangle.angled.fill"
        }
    }
}
