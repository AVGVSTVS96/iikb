import KeyboardCore
import UIKit

/// A setting's choices folded into the picked one: its name on a platter in a capsule of the bar's glass. A tap opens it
/// leftward, over what's beside it, into every choice with the platter still under the picked one; picking slides the
/// platter to the new one and folds it back around it. VoiceOver adjusts it up and down the choices. The bar's writing
/// style (`SuggestionBar`).
public final class StylePicker: UIView {
    /// A choice was picked, by its index.
    public var onPick: (Int) -> Void = { _ in }
    /// It opened or folded, so what holds it makes room or takes it back.
    public var onOpen: (Bool) -> Void = { _ in }
    public private(set) var isOpen = false

    private let track = UIVisualEffectView(effect: UIGlassEffect.bar(.lightCurrent))
    private let platter = UIView()
    private var labels: [UILabel] = []
    private var names: [String] = []
    private var picked = 0
    private var glassDark: Bool?

    public static let height = ChatTabs.height
    private static let inset = 2.0
    private static let padding = 12.0
    private static let font = UIFont.systemFont(ofSize: 15, weight: .semibold)

    override public init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "iikb.style"
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        track.cornerConfiguration = .capsule()
        track.clipsToBounds = true
        addSubview(track)
        platter.isUserInteractionEnabled = false
        platter.layer.cornerCurve = .continuous
        platter.layer.shadowColor = UIColor.black.cgColor
        platter.layer.shadowOffset = CGSize(width: 0, height: 1)
        platter.layer.shadowRadius = 3
        track.contentView.addSubview(platter)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show(_ names: [String], picked: Int, title: String, theme: KeyboardTheme) {
        if names != self.names {
            self.names = names
            labels.forEach { $0.removeFromSuperview() }
            labels = names.map { name in
                let label = UILabel()
                label.text = name
                label.font = Self.font
                label.textAlignment = .center
                track.contentView.addSubview(label)
                return label
            }
            setNeedsLayout()
        }
        if picked != self.picked { setNeedsLayout() }
        self.picked = picked
        accessibilityLabel = title
        accessibilityValue = names.indices.contains(picked) ? names[picked] : nil
        if theme.dark != glassDark {
            glassDark = theme.dark
            track.effect = UIGlassEffect.bar(theme)
        }
        platter.backgroundColor = UIColor(white: 1, alpha: theme.dark ? 0.14 : 1)
        platter.layer.shadowOpacity = theme.dark ? 0 : 0.12
        for (index, label) in labels.enumerated() {
            label.textColor = index == picked ? theme.label.ui : theme.candidate.ui
        }
    }

    /// Folds it, as typing or dictating does.
    public func fold() {
        guard isOpen else { return }
        isOpen = false
        onOpen(false)
    }

    /// How wide it is open, every choice beside the next.
    public var openWidth: CGFloat { widths.reduce(2 * Self.inset, +) }

    private var widths: [CGFloat] {
        labels.map { ceil($0.intrinsicContentSize.width) + 2 * Self.padding }
    }

    @objc private func tap(_ tap: UITapGestureRecognizer) {
        guard isOpen else {
            isOpen = true
            return onOpen(true)
        }
        let x = tap.location(in: track.contentView).x
        let index = labels.firstIndex { x < $0.frame.maxX } ?? labels.count - 1
        guard index != picked else { return fold() }
        pick(index)
    }

    /// The platter slides to the new choice, then the picker folds around it.
    private func pick(_ index: Int) {
        picked = index
        setNeedsLayout()
        UIView.animate(
            springDuration: 0.4, bounce: 0.18, initialSpringVelocity: 0, delay: 0, options: [.allowUserInteraction],
            animations: { self.layoutIfNeeded() }, completion: { _ in self.fold() })
        onPick(index)
    }

    override public func accessibilityIncrement() { step(1) }
    override public func accessibilityDecrement() { step(-1) }

    private func step(_ by: Int) {
        let index = picked + by
        guard names.indices.contains(index) else { return }
        picked = index
        setNeedsLayout()
        onPick(index)
    }

    /// Open, the choices sit side by side from its left, the platter under the picked one. Folded, they keep those
    /// places shifted so the picked one fills it, the rest faded out, so opening slides them out from behind it.
    override public func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        platter.layer.cornerRadius = (bounds.height - 2 * Self.inset) / 2
        guard labels.indices.contains(picked) else { return }
        var x = Self.inset
        let row = bounds.height - 2 * Self.inset
        let places = widths.map { width in
            defer { x += width }
            return CGRect(x: x, y: Self.inset, width: width, height: row)
        }
        let full = bounds.insetBy(dx: Self.inset, dy: Self.inset)
        let shift = isOpen ? 0 : full.midX - places[picked].midX
        for (index, (label, place)) in zip(labels, places).enumerated() {
            label.frame = index == picked && !isOpen ? full : place.offsetBy(dx: shift, dy: 0)
            label.alpha = isOpen || index == picked ? 1 : 0
        }
        platter.frame = isOpen ? places[picked] : full
    }
}
