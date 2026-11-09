import KeyboardCore
import UIKit

/// What the menu's shelves and a panel's results share: the results for `query`, laid out for `metrics`.
public protocol PanelResults: UIView {
    /// Called on every render; redraw only when something changed, so results never move under a finger.
    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics)
    /// The panel or shelf just opened.
    func reset()
}

/// A panel: its results, and under them the field the keys type into, which each panel picks for its job.
public protocol PanelContent: PanelResults {
    var field: PanelField { get }
}

/// The field under a panel's results. Search is iOS's one-line search field; anything else (a message, a note) is a
/// view of the panel's own that does that job as iOS's own field for it does, never search made to look like it.
public enum PanelField {
    case search(Search)
    /// As tall as its `sizeThatFits` for the row's width, up to what the panel leaves it.
    case own(UIView)

    public struct Search {
        public var placeholder: String
        public var glyph: UIImage?
        /// Buttons at the field's right end, before its clear button.
        public var accessories: [UIView]
        /// What the field says in place of the search, like "Copied", until the panel takes it back.
        public var notice: String?

        public init(
            _ placeholder: String, glyph: UIImage? = UIImage(systemName: "magnifyingglass"), accessories: [UIView] = [],
            notice: String? = nil
        ) {
            self.placeholder = placeholder
            self.glyph = glyph
            self.accessories = accessories
            self.notice = notice
        }
    }
}

/// A panel: its results over a back button and its field. Above the keys (`inKeysPlace` false) it takes the bar's place,
/// its results `toolbar.results` tall; in the keys' place, as a panel opened from the menu is until you tap its field,
/// its results fill what its field leaves.
public final class PanelView: UIView {
    public var onClose: () -> Void = {}
    public var onClear: () -> Void = {}
    /// The field was tapped while the panel is in the keys' place, so the keys come up to type into it.
    public var onField: () -> Void = {}
    public var block = (minX: CGFloat(0), maxX: CGFloat(0)) { didSet { if block != oldValue { setNeedsLayout() } } }
    public var inKeysPlace = false { didSet { if inKeysPlace != oldValue { setNeedsLayout() } } }
    /// Whether the search field may take focus while the keys are up, which iOS allows a keyboard only with Full Access
    /// (`MessageField`).
    public var focuses = false
    /// Chats has no back button: More, still on, takes you back.
    public var showsBack = true { didSet { if showsBack != oldValue { setNeedsLayout() } } }
    /// Under the field in the keys' place, so it ends where the bottom row of keys would.
    public var bottomInset = PanelView.inset { didSet { if bottomInset != oldValue { setNeedsLayout() } } }
    private(set) var content: PanelContent?
    private var toolbar = KeyboardMetrics.phone(width: 390).toolbar
    private let back = UIButton(type: .custom)
    private let search = SearchField()
    private var own: UIView?

    /// Padding around a panel in the keys' place, the menu's gap.
    public static let inset: CGFloat = 8

    override public init(frame: CGRect) {
        super.init(frame: frame)
        back.accessibilityIdentifier = "iikb.panel.back"
        back.accessibilityLabel = "Back"
        back.setImage(
            UIImage(
                systemName: "chevron.left",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)), for: .normal)
        back.addAction(UIAction { [unowned self] _ in onClose() }, for: .touchUpInside)
        search.onClear = { [unowned self] in onClear() }
        search.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapField)))
        addSubview(back)
        addSubview(search)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapField() {
        if inKeysPlace { onField() }
    }

    public func open(_ content: PanelContent?) {
        guard content !== self.content else { return }
        self.content?.removeFromSuperview()
        own?.removeFromSuperview()
        own = nil
        search.unfocus()
        self.content = content
        guard let content else { return }
        content.reset()
        insertSubview(content, at: 0)
        if case .own(let view) = content.field {
            own = view
            addSubview(view)
        }
        search.isHidden = own != nil
        setNeedsLayout()
    }

    /// `caret` is how many characters of `query` are before the caret, at its end when nil.
    public func show(query: String, caret: Int? = nil, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        if metrics.toolbar != toolbar {
            toolbar = metrics.toolbar
            setNeedsLayout()
        }
        back.tintColor = theme.label.ui
        content?.show(query: query, theme: theme, metrics: metrics)
        guard case .search(let look) = content?.field else { return }
        search.accessories = look.accessories
        search.show(
            query, caretAt: caret ?? query.count, look: look, typing: !inKeysPlace && focuses && !isHidden, theme: theme
        )
    }

    /// How tall the results are in the keys' place, `height` tall, with a search field under them.
    public static func results(inKeysPlace height: CGFloat, field: Double) -> Double {
        max(Double(height - 2 * inset) - Toolbar.fieldGap - field, 0)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let width = block.maxX - block.minX
        let top = inKeysPlace ? Self.inset : CGFloat(toolbar.top)
        let bottom = inKeysPlace ? bounds.height - bottomInset : bounds.height
        back.isHidden = !showsBack
        let fieldX = block.minX + (showsBack ? 40 : 0)
        let fieldWidth = max(block.maxX - fieldX, 0)
        let room = bottom - top - CGFloat(Toolbar.fieldGap)
        let fieldHeight =
            own.map { min(ceil($0.sizeThatFits(CGSize(width: fieldWidth, height: room - 46)).height), room - 46) }
            ?? CGFloat(toolbar.field)
        let row = CGRect(x: block.minX, y: bottom - fieldHeight, width: width, height: fieldHeight)
        content?.frame = CGRect(
            x: block.minX, y: top, width: width, height: max(row.minY - CGFloat(Toolbar.fieldGap) - top, 0))
        let line = CGFloat(own == nil ? toolbar.field : min(toolbar.field, 36))
        back.frame = CGRect(x: row.minX, y: row.maxY - line, width: 36, height: line)
        (own ?? search).frame = CGRect(x: fieldX, y: row.minY, width: fieldWidth, height: row.height)
    }
}

/// A panel's search field: a glyph, a real `UITextField` with what the keys typed (or the placeholder), focused while the
/// keys are up so its caret is iOS's own, its accessories, and a clear button once there's text. The keys type into it
/// through the engine; a tap on it only brings them up.
private final class SearchField: UIView {
    var onClear: () -> Void = {}
    var accessories: [UIView] = [] {
        didSet {
            guard !accessories.elementsEqual(oldValue, by: ===) else { return }
            oldValue.forEach { $0.removeFromSuperview() }
            accessories.forEach(addSubview)
            setNeedsLayout()
        }
    }
    private let glyph = UIImageView()
    private let input = SearchInput()
    private let clear = UIButton(type: .custom)
    private var query = ""
    private var caretAt = 0
    private var notice: String?
    private var clearTheme: KeyboardTheme?

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "iikb.panel.search"
        isAccessibilityElement = true
        accessibilityTraits = .searchField
        layer.cornerCurve = .continuous
        glyph.contentMode = .center
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        input.font = .systemFont(ofSize: 17)
        input.autocorrectionType = .no
        input.spellCheckingType = .no
        input.inputView = UIView(frame: .zero)
        input.inputAssistantItem.leadingBarButtonGroups = []
        input.inputAssistantItem.trailingBarButtonGroups = []
        clear.accessibilityIdentifier = "iikb.panel.clear"
        clear.accessibilityLabel = "Clear"
        clear.addAction(UIAction { [unowned self] _ in onClear() }, for: .touchUpInside)
        [glyph, input].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        addSubview(clear)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ query: String, caretAt: Int, look: PanelField.Search, typing: Bool, theme: KeyboardTheme) {
        let (placeholder, image, notice) = (look.placeholder, look.glyph, look.notice)
        if query != self.query || caretAt != self.caretAt || notice != self.notice { setNeedsLayout() }
        self.query = query
        self.caretAt = caretAt
        self.notice = notice
        accessibilityLabel = placeholder
        accessibilityValue = notice ?? query
        input.text = notice ?? query
        input.textColor = theme.label.ui
        input.tintColor = theme.prominent.ui
        input.attributedPlaceholder = NSAttributedString(
            string: placeholder, attributes: [.foregroundColor: theme.candidate.ui])
        let focus = typing && notice == nil
        if focus, !input.isFirstResponder {
            input.becomeFirstResponder()
        } else if !focus, input.isFirstResponder {
            input.resignFirstResponder()
        }
        let at = input.position(from: input.beginningOfDocument, offset: String(query.prefix(caretAt)).utf16.count)
        if focus, let at, input.selectedTextRange?.start != at {
            input.selectedTextRange = input.textRange(from: at, to: at)
        }
        let shown = notice == nil ? image : UIImage(systemName: "checkmark.circle.fill")
        if (shown == nil) != (glyph.image == nil) { setNeedsLayout() }
        glyph.image = shown
        glyph.tintColor = theme.candidate.ui
        backgroundColor = theme.searchField.ui
        clear.isHidden = query.isEmpty || notice != nil
        guard theme != clearTheme else { return }
        clearTheme = theme
        let mark = UIImage(
            systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        clear.setImage(
            Self.clearImage(mark: mark, circle: theme.candidate.ui, field: theme.searchField.ui), for: .normal)
    }

    private static func clearImage(mark: UIImage?, circle: UIColor, field: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in
            circle.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 20, height: 20)).fill()
            guard let mark = mark?.withTintColor(field, renderingMode: .alwaysOriginal) else { return }
            mark.draw(at: CGPoint(x: (20 - mark.size.width) / 2, y: (20 - mark.size.height) / 2))
        }
    }

    func unfocus() {
        if input.isFirstResponder { input.resignFirstResponder() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        glyph.frame = CGRect(x: 14, y: 0, width: 20, height: bounds.height)
        var right = bounds.width - 12
        if !clear.isHidden {
            clear.frame = CGRect(x: right - 28, y: 0, width: 28, height: bounds.height)
            right = clear.frame.minX
        }
        for accessory in accessories.reversed() {
            accessory.frame = CGRect(x: right - 32, y: 0, width: 32, height: bounds.height)
            right = accessory.frame.minX
        }
        let text = glyph.image == nil ? 14 : glyph.frame.maxX + 6
        input.frame = CGRect(x: text, y: 0, width: max(right - text - 4, 0), height: bounds.height)
    }
}

/// The search field's text field, which takes focus while it's not taking touches: a tap on the field brings the keys
/// up, and the engine keeps the caret.
private final class SearchInput: UITextField {
    override var canBecomeFirstResponder: Bool { true }
}

/// What a panel says in place of results, like "GIF search needs Full Access.", with Turn On after it when Settings has
/// the answer; then the whole notice opens Settings. In one row, Turn On follows on the same line, so it fits 46pt.
package final class PanelNotice: UIButton {
    package var onTurnOn: () -> Void = {}
    private var turnsOn = false

    override package init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel?.numberOfLines = 0
        titleLabel?.textAlignment = .center
        addAction(UIAction { [unowned self] _ in if turnsOn { onTurnOn() } }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    override package var isHighlighted: Bool {
        didSet { alpha = isHighlighted && turnsOn ? 0.5 : 1 }
    }

    package func show(_ text: String?, turnOn: Bool, oneRow: Bool, theme: KeyboardTheme) {
        turnsOn = turnOn && text != nil
        isHidden = text == nil
        setAttributedTitle(
            text.map { text in
                let title = NSMutableAttributedString(
                    string: text,
                    attributes: [.foregroundColor: theme.candidate.ui, .font: UIFont.systemFont(ofSize: 15)])
                if turnsOn {
                    title.append(
                        NSAttributedString(
                            string: (oneRow ? " " : "\n") + "Turn On",
                            attributes: [
                                .foregroundColor: theme.prominent.ui,
                                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                            ]))
                }
                return title
            }, for: .normal)
    }
}
