import KeyboardCore
import KeyboardUI
import UIKit

/// The chats panel (docs/extensions.md): the open chat's messages, yours on the right, over the message box the keys
/// and the bar's mic type into (`MessageField`). Opened from the menu it fills a keyboard grown for it, the chats as
/// pills in the bar, so you read and dictate with the keys down; a tap on the box brings them up under it at the same
/// height, and a tap on the messages puts them away.
final class ChatPanel: UIView, PanelContent {
    var fullAccess: () -> Bool = { false }
    var onTurnOn: () -> Void = {}
    var onSend: () -> Void = {}
    /// The box was tapped with the keys down.
    var onFocus: () -> Void = {}
    /// The messages were tapped with the keys up.
    var onBrowse: () -> Void = {}
    /// A tap or a drag in the box placed the caret or selected, as offsets into its text.
    var onSelect: (Range<Int>) -> Void = { _ in }
    /// Cut, Copy or Paste from the box's edit menu.
    var onEdit: (SuggestionBar.Edit) -> Void = { _ in }
    var field: PanelField { .own(composer) }
    private let composer = MessageField()
    private var line: LineDocument?
    private var typing = false

    private struct Shown: Equatable {
        var revision: Int
        var theme: KeyboardTheme
    }

    private let chats: Chats
    private var shown: Shown?
    private let thread = UIScrollView()
    /// Holds the thread and fades its top, so a message scrolled up goes soft rather than cut.
    private let well = UIView()
    private let fade = CAGradientLayer()
    private var bubbles: [Bubble] = []
    private let message = PanelNotice()
    /// What went wrong, under the messages, when there are messages to keep showing.
    private let trouble = UILabel()

    init(chats: Chats) {
        self.chats = chats
        super.init(frame: .zero)
        thread.accessibilityIdentifier = "iikb.chat.messages"
        thread.showsVerticalScrollIndicator = false
        [thread.topEdgeEffect, thread.bottomEdgeEffect, thread.leftEdgeEffect, thread.rightEdgeEffect].forEach {
            $0.isHidden = true
        }
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        well.layer.mask = fade
        well.addSubview(thread)
        trouble.font = .systemFont(ofSize: 13)
        trouble.textAlignment = .center
        trouble.numberOfLines = 0
        thread.addSubview(trouble)
        composer.onSend = { [unowned self] in onSend() }
        composer.onTap = { [unowned self] in if !typing { onFocus() } }
        composer.onSelect = { [unowned self] in onSelect($0) }
        composer.onEdit = { [unowned self] in onEdit($0) }
        well.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapMessages)))
        message.accessibilityIdentifier = "iikb.chat.message"
        message.onTurnOn = { [unowned self] in onTurnOn() }
        [well, message].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        shown = nil
    }

    /// The box shows `line`; `typing` is whether the keys are up under it.
    func show(_ line: LineDocument, typing: Bool) {
        self.line = line
        self.typing = typing
    }

    @objc private func tapMessages() {
        if typing { onBrowse() }
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        if let line {
            composer.show(
                line, placeholder: chats.open.map { "Message \($0.name)" } ?? "Message", caret: typing, sends: !typing,
                theme: theme)
        }
        let next = Shown(revision: chats.revision, theme: theme)
        guard next != shown else { return }
        shown = next
        showMessages(theme)
        let missing = fullAccess() ? nil : "Chats need Full Access."
        let empty = chats.messages.isEmpty
        let quiet =
            !chats.listed
            ? "Loading chats…" : chats.list.isEmpty ? "No chats yet." : chats.loaded && empty ? "No messages yet." : nil
        message.show(
            missing ?? (empty ? chats.problem : nil) ?? quiet, turnOn: missing != nil, oneRow: false, theme: theme)
        trouble.text = empty ? nil : chats.problem
        trouble.textColor = theme.candidate.ui
        setNeedsLayout()
    }

    private func showMessages(_ theme: KeyboardTheme) {
        let shown = Array(chats.messages.suffix(40))
        while bubbles.count < shown.count {
            let bubble = Bubble()
            thread.addSubview(bubble)
            bubbles.append(bubble)
        }
        while bubbles.count > shown.count { bubbles.removeLast().removeFromSuperview() }
        for (bubble, message) in zip(bubbles, shown) { bubble.show(message, theme: theme) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        well.frame = bounds
        thread.frame = well.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = well.bounds
        fade.locations = [0, NSNumber(value: well.bounds.height == 0 ? 0 : min(14 / well.bounds.height, 1))]
        CATransaction.commit()
        message.frame = bounds
        let width = thread.bounds.width
        let widest = min((width * 0.75).rounded(.down), 520)
        var y = 0.0
        for (index, bubble) in bubbles.enumerated() {
            let after = index > 0 && bubbles[index - 1].mine == bubble.mine
            let before = index + 1 < bubbles.count && bubbles[index + 1].mine == bubble.mine
            bubble.joined = (above: after, below: before)
            if index > 0 { y += after ? 2 : 10 }
            let size = bubble.size(within: widest)
            bubble.frame = CGRect(x: bubble.mine ? width - size.width : 0, y: y, width: size.width, height: size.height)
            y += size.height
        }
        if let problem = trouble.text, !problem.isEmpty {
            let fits = trouble.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            trouble.frame = CGRect(x: 0, y: y + 8, width: width, height: ceil(fits.height))
            y = trouble.frame.maxY
        } else {
            trouble.frame = .zero
        }
        thread.contentInset.top = max(thread.bounds.height - y, 0)
        let wasAtEnd = thread.contentOffset.y >= thread.contentSize.height - thread.bounds.height - 1
        thread.contentSize = CGSize(width: width, height: y)
        if wasAtEnd || y <= thread.bounds.height { thread.contentOffset.y = y - thread.bounds.height }
    }
}

/// One message as Messages draws it: yours on the accent color, hex's on a key's, SF Pro 17 on 22 point lines, hugging
/// its text; markdown's bold, italics and code drawn.
private final class Bubble: UIView {
    private(set) var mine = false
    /// Whether the message above and below is from the same side, whose corners on that side tighten, as Messages'.
    var joined = (above: false, below: false) { didSet { if joined != oldValue { setNeedsLayout() } } }
    private let shape = CAShapeLayer()
    private let label = UILabel()
    private static let inset = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
    private static let size = 17.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(shape, at: 0)
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        label.numberOfLines = 0
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ message: Chats.Message, theme: KeyboardTheme) {
        mine = message.mine
        shape.fillColor = (mine ? theme.prominent.ui : theme.key.ui).cgColor
        layer.shadowColor = theme.shadow.ui.cgColor
        layer.shadowOpacity = mine ? 0 : 1
        alpha = message.pending == true ? 0.6 : 1
        let color = mine ? theme.prominentLabel.ui : theme.label.ui
        let markdown = try? NSMutableAttributedString(
            AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        )
        let text = markdown ?? NSMutableAttributedString(string: message.text)
        let whole = NSRange(location: 0, length: text.length)
        let lines = NSMutableParagraphStyle()
        lines.minimumLineHeight = 22
        lines.maximumLineHeight = 22
        text.addAttributes([.foregroundColor: color, .paragraphStyle: lines], range: whole)
        text.enumerateAttribute(.inlinePresentationIntent, in: whole) { intent, range, _ in
            let intent = (intent as? NSNumber).map { InlinePresentationIntent(rawValue: $0.uintValue) } ?? []
            let font: UIFont =
                intent.contains(.code)
                ? .monospacedSystemFont(ofSize: Self.size - 2, weight: .regular)
                : intent.contains(.stronglyEmphasized)
                    ? .systemFont(ofSize: Self.size, weight: .semibold)
                    : intent.contains(.emphasized)
                        ? .italicSystemFont(ofSize: Self.size) : .systemFont(ofSize: Self.size)
            text.addAttribute(.font, value: font, range: range)
        }
        label.attributedText = text
        accessibilityLabel = (mine ? "You: " : "") + text.string
        isAccessibilityElement = true
    }

    func size(within width: CGFloat) -> CGSize {
        let inset = Self.inset
        let fits = label.sizeThatFits(CGSize(width: width - inset.left - inset.right, height: .greatestFiniteMagnitude))
        return CGSize(
            width: ceil(fits.width) + inset.left + inset.right, height: ceil(fits.height) + inset.top + inset.bottom)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.inset(by: Self.inset)
        let round: CGFloat = 18
        let tight: CGFloat = 6
        let side = (top: joined.above ? tight : round, bottom: joined.below ? tight : round)
        let radii =
            mine
            ? (topLeft: round, topRight: side.top, bottomLeft: round, bottomRight: side.bottom)
            : (topLeft: side.top, topRight: round, bottomLeft: side.bottom, bottomRight: round)
        let path = UIBezierPath(shape: bounds, radii)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.path = path.cgPath
        layer.shadowPath = path.cgPath
        CATransaction.commit()
    }
}

extension UIBezierPath {
    /// A rectangle with each corner its own radius.
    fileprivate convenience init(
        shape rect: CGRect, _ r: (topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat)
    ) {
        self.init()
        move(to: CGPoint(x: rect.minX + r.topLeft, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX - r.topRight, y: rect.minY))
        addArc(
            withCenter: CGPoint(x: rect.maxX - r.topRight, y: rect.minY + r.topRight), radius: r.topRight,
            startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r.bottomRight))
        addArc(
            withCenter: CGPoint(x: rect.maxX - r.bottomRight, y: rect.maxY - r.bottomRight), radius: r.bottomRight,
            startAngle: 0, endAngle: .pi / 2, clockwise: true)
        addLine(to: CGPoint(x: rect.minX + r.bottomLeft, y: rect.maxY))
        addArc(
            withCenter: CGPoint(x: rect.minX + r.bottomLeft, y: rect.maxY - r.bottomLeft), radius: r.bottomLeft,
            startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        addLine(to: CGPoint(x: rect.minX, y: rect.minY + r.topLeft))
        addArc(
            withCenter: CGPoint(x: rect.minX + r.topLeft, y: rect.minY + r.topLeft), radius: r.topLeft, startAngle: .pi,
            endAngle: -.pi / 2, clockwise: true)
        close()
    }
}

/// Chats' shelf in the menu: a card for each chat, pinned first, its name over its latest line, as the clipboard's
/// shelf has cards; a tap opens that chat.
final class ChatShelf: UIView, PanelResults {
    var fullAccess: () -> Bool = { false }
    var onTurnOn: () -> Void = {}
    var onPick: (Chats.Chat) -> Void = { _ in }

    private let chats: Chats
    private let row = ButtonScrollView()
    private var cards: [ChatCard] = []
    private let message = PanelNotice()
    private var shown: (revision: Int, theme: KeyboardTheme)?

    init(chats: Chats) {
        self.chats = chats
        super.init(frame: .zero)
        row.accessibilityIdentifier = "iikb.chats.shelf"
        message.onTurnOn = { [unowned self] in onTurnOn() }
        [row, message].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        shown = nil
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        guard shown?.revision != chats.revision || shown?.theme != theme else { return }
        shown = (chats.revision, theme)
        if cards.map(\.chat) != chats.list {
            cards.forEach { $0.removeFromSuperview() }
            cards = chats.list.enumerated().map { index, chat in
                let card = ChatCard(chat)
                card.accessibilityIdentifier = "iikb.chats.shelf.\(index)"
                card.addAction(UIAction { [unowned self] _ in onPick(chat) }, for: .touchUpInside)
                row.addSubview(card)
                return card
            }
        }
        cards.forEach { $0.show(theme) }
        let missing = fullAccess() ? nil : "Chats need Full Access."
        message.show(
            missing ?? (!chats.listed ? "Loading chats…" : chats.list.isEmpty ? chats.problem ?? "No chats yet." : nil),
            turnOn: missing != nil, oneRow: true, theme: theme)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        row.frame = bounds
        message.frame = bounds
        let gap = 6.0
        let width = ((bounds.width - 2 * gap) / 3).rounded(.down)
        for (index, card) in cards.enumerated() {
            card.frame = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: bounds.height)
        }
        row.contentSize = CGSize(width: max(CGFloat(cards.count) * (width + gap) - gap, 0), height: bounds.height)
    }
}

private final class ChatCard: UIControl {
    let chat: Chats.Chat
    private let name = UILabel()
    private let line = UILabel()
    private var theme = KeyboardTheme.lightCurrent

    init(_ chat: Chats.Chat) {
        self.chat = chat
        super.init(frame: .zero)
        accessibilityLabel = chat.name
        accessibilityTraits = .button
        isAccessibilityElement = true
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        name.text = chat.name
        name.font = .systemFont(ofSize: 14)
        line.text = chat.line.map { line in
            (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                .map { String($0.characters) } ?? line
        }
        line.font = .systemFont(ofSize: 12)
        [name, line].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ theme: KeyboardTheme) {
        self.theme = theme
        name.textColor = theme.label.ui
        line.textColor = theme.candidate.ui
        backgroundColor = isHighlighted ? theme.keyPressed.ui : theme.key.ui
    }

    override var isHighlighted: Bool { didSet { show(theme) } }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = bounds.insetBy(dx: 10, dy: 6)
        let both = line.text != nil && inset.height >= 30
        line.isHidden = !both
        name.frame = both ? CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height - 15) : inset
        line.frame = CGRect(x: inset.minX, y: inset.maxY - 15, width: inset.width, height: 15)
    }
}
