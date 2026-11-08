import KeyboardCore
import KeyboardUI
import UIKit

/// The chats panel (docs/extensions.md): the chats in a row, pinned first, and the open one's latest messages, yours on
/// the right; under them the message line the keys type into, and its send button. Opens above the bar, so the bar's
/// suggestions and mic work in the line as in any field.
final class ChatPanel: UIView, PanelContent {
    var fullAccess: () -> Bool = { false }
    var onTurnOn: () -> Void = {}
    var onSend: () -> Void = {}
    var placeholder: String { chats.open.map { "Message \($0.name)" } ?? "Message" }
    var glyph: UIImage? { nil }
    var accessories: [UIView] { [send] }
    /// Send sits where Messages has it, at the line's end, so no clear button beside it: delete empties the line.
    let clears = false

    private struct Shown: Equatable {
        var revision: Int
        var compact: Bool
        var theme: KeyboardTheme
        var canSend: Bool
    }

    private let chats: Chats
    private var shown: Shown?
    private let row = ButtonScrollView()
    private var chips: [UIButton] = []
    private var names: [String] = []
    /// In one row, the open chat's name, whose menu picks another, in the chips' place.
    private let picker = UIButton(configuration: .plain())
    private let thread = UIScrollView()
    /// Holds the thread and fades its top, so a message scrolled under the chips goes soft rather than cut.
    private let well = UIView()
    private let fade = CAGradientLayer()
    private var bubbles: [Bubble] = []
    private let message = PanelNotice()
    /// What went wrong, under the messages, when there are messages to keep showing.
    private let trouble = UILabel()
    private let send = UIButton(type: .custom)

    init(chats: Chats) {
        self.chats = chats
        super.init(frame: .zero)
        row.accessibilityIdentifier = "iikb.chats"
        thread.accessibilityIdentifier = "iikb.chat.messages"
        thread.showsVerticalScrollIndicator = false
        [thread.topEdgeEffect, thread.bottomEdgeEffect, thread.leftEdgeEffect, thread.rightEdgeEffect].forEach { $0.isHidden = true }
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        well.layer.mask = fade
        well.addSubview(thread)
        trouble.font = .systemFont(ofSize: 13)
        trouble.textAlignment = .center
        trouble.numberOfLines = 0
        thread.addSubview(trouble)
        picker.accessibilityIdentifier = "iikb.chat.picker"
        picker.showsMenuAsPrimaryAction = true
        picker.layer.cornerCurve = .continuous
        addSubview(picker)
        send.accessibilityIdentifier = "iikb.chat.send"
        send.accessibilityLabel = "Send"
        send.addAction(UIAction { [unowned self] _ in onSend() }, for: .touchUpInside)
        message.accessibilityIdentifier = "iikb.chat.message"
        message.onTurnOn = { [unowned self] in onTurnOn() }
        [row, well, message].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        shown = nil
    }

    /// `query` is what the line holds.
    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        let next = Shown(revision: chats.revision, compact: metrics.toolbar.isCompact, theme: theme, canSend: !query.trimmingCharacters(in: .whitespaces).isEmpty)
        guard next != shown else { return }
        let moved = next.revision != shown?.revision || next.theme != shown?.theme
        shown = next
        let colors = next.canSend ? [theme.prominentLabel.ui, theme.prominent.ui] : [theme.searchField.ui, theme.candidate.ui]
        let look = UIImage.SymbolConfiguration(pointSize: 24).applying(UIImage.SymbolConfiguration(paletteColors: colors))
        send.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: look), for: .normal)
        send.isEnabled = next.canSend
        guard moved else { return }
        showChips(theme)
        showMessages(theme)
        let missing = fullAccess() ? nil : "Chats need Full Access."
        let empty = chats.messages.isEmpty
        let quiet = !chats.listed ? "Loading chats…" : chats.list.isEmpty ? "No chats yet." : chats.loaded && empty ? "No messages yet." : nil
        message.show(missing ?? (empty ? chats.problem : nil) ?? quiet, turnOn: missing != nil, oneRow: true, theme: theme)
        trouble.text = empty ? nil : chats.problem
        trouble.textColor = theme.candidate.ui
        setNeedsLayout()
    }

    private func showChips(_ theme: KeyboardTheme) {
        if names != chats.list.map(\.name) {
            names = chats.list.map(\.name)
            chips.forEach { $0.removeFromSuperview() }
            chips = chats.list.enumerated().map { index, chat in
                var look = UIButton.Configuration.plain()
                look.attributedTitle = AttributedString(chat.name, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .medium)]))
                look.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
                look.titleLineBreakMode = .byTruncatingTail
                let chip = UIButton(configuration: look)
                chip.layer.cornerCurve = .continuous
                chip.accessibilityIdentifier = "iikb.chat.\(index)"
                chip.addAction(UIAction { [unowned self] _ in chats.pick(chat) }, for: .touchUpInside)
                row.addSubview(chip)
                return chip
            }
        }
        var look = UIButton.Configuration.plain()
        look.attributedTitle = AttributedString(chats.open?.name ?? "Chats", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .medium)]))
        look.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        look.imagePlacement = .trailing
        look.imagePadding = 4
        look.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 10)
        look.titleLineBreakMode = .byTruncatingTail
        look.baseForegroundColor = theme.label.ui
        picker.configuration = look
        picker.backgroundColor = theme.key.ui
        picker.menu = UIMenu(children: chats.list.map { chat in
            UIAction(title: chat.name, state: chat == chats.open ? .on : .off) { [unowned self] _ in chats.pick(chat) }
        })
        for (chip, chat) in zip(chips, chats.list) {
            let open = chat == chats.open
            chip.backgroundColor = open ? theme.key.ui : .clear
            chip.configuration?.baseForegroundColor = open ? theme.label.ui : theme.candidate.ui
            chip.accessibilityTraits = open ? [.button, .selected] : .button
        }
    }

    private func showMessages(_ theme: KeyboardTheme) {
        let shown = chats.messages.suffix(20)
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
        let compact = shown?.compact == true
        let rowHeight = min(32.0, bounds.height)
        row.frame = CGRect(x: 0, y: 0, width: bounds.width, height: rowHeight)
        row.isHidden = compact
        picker.isHidden = !compact || chats.list.isEmpty
        let pick = picker.isHidden ? 0 : min(ceil(picker.sizeThatFits(CGSize(width: 200, height: rowHeight)).width), bounds.width * 0.4)
        picker.frame = CGRect(x: 0, y: (bounds.height - rowHeight) / 2, width: pick, height: rowHeight)
        picker.layer.cornerRadius = rowHeight / 2
        var x = 0.0
        for chip in chips {
            let width = ceil(chip.sizeThatFits(CGSize(width: 240, height: rowHeight)).width)
            chip.frame = CGRect(x: x, y: 0, width: min(width, 240), height: rowHeight)
            chip.layer.cornerRadius = rowHeight / 2
            x += chip.frame.width + 4
        }
        row.contentSize = CGSize(width: max(x - 4, 0), height: rowHeight)
        well.frame = compact
            ? CGRect(x: pick + 6, y: 0, width: max(bounds.width - pick - 6, 0), height: bounds.height)
            : CGRect(x: 0, y: rowHeight + 6, width: bounds.width, height: max(bounds.height - rowHeight - 6, 0))
        thread.frame = well.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = well.bounds
        fade.locations = [0, NSNumber(value: compact || well.bounds.height == 0 ? 0 : min(14 / well.bounds.height, 1))]
        CATransaction.commit()
        message.frame = well.frame
        let width = thread.bounds.width
        let widest = compact ? width : (width * 0.82).rounded(.down)
        var y = 0.0
        for (index, bubble) in bubbles.enumerated() {
            bubble.oneLine = compact
            bubble.isHidden = compact && index != bubbles.count - 1
            guard !bubble.isHidden else { continue }
            let size = bubble.size(within: widest)
            bubble.frame = CGRect(x: bubble.mine ? width - size.width : 0, y: y, width: size.width, height: size.height)
            y += size.height + 4
        }
        if let problem = trouble.text, !problem.isEmpty, !compact {
            let fits = trouble.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            trouble.frame = CGRect(x: 0, y: y + 2, width: width, height: ceil(fits.height))
            y = trouble.frame.maxY + 4
        } else {
            trouble.frame = .zero
        }
        let height = max(y - 4, 0)
        thread.contentInset.top = max(thread.bounds.height - height, 0)
        let wasAtEnd = thread.contentOffset.y >= thread.contentSize.height - thread.bounds.height - 1
        thread.contentSize = CGSize(width: width, height: height)
        if wasAtEnd || height <= thread.bounds.height { thread.contentOffset.y = height - thread.bounds.height }
    }
}

/// One message: yours on the prominent color, the other side's on a key's, its markdown's bold, italics and code drawn.
private final class Bubble: UIView {
    private(set) var mine = false
    /// In one row, a message is one line, cut off at its end.
    var oneLine = false { didSet { label.numberOfLines = oneLine ? 1 : 0 } }
    private let label = UILabel()
    private static let inset = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 15
        layer.cornerCurve = .continuous
        label.numberOfLines = 0
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ message: Chats.Message, theme: KeyboardTheme) {
        mine = message.mine
        backgroundColor = mine ? theme.prominent.ui : theme.key.ui
        alpha = message.pending == true ? 0.6 : 1
        let color = mine ? theme.prominentLabel.ui : theme.label.ui
        let markdown = try? NSMutableAttributedString(
            AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        )
        let text = markdown ?? NSMutableAttributedString(string: message.text)
        let whole = NSRange(location: 0, length: text.length)
        text.addAttribute(.foregroundColor, value: color, range: whole)
        text.enumerateAttribute(.inlinePresentationIntent, in: whole) { intent, range, _ in
            let intent = (intent as? NSNumber).map { InlinePresentationIntent(rawValue: $0.uintValue) } ?? []
            let size = 15.0
            let font: UIFont = intent.contains(.code) ? .monospacedSystemFont(ofSize: size - 1, weight: .regular)
                : intent.contains(.stronglyEmphasized) ? .systemFont(ofSize: size, weight: .semibold)
                : intent.contains(.emphasized) ? .italicSystemFont(ofSize: size) : .systemFont(ofSize: size)
            text.addAttribute(.font, value: font, range: range)
        }
        label.attributedText = text
        accessibilityLabel = (mine ? "You: " : "") + text.string
        isAccessibilityElement = true
    }

    func size(within width: CGFloat) -> CGSize {
        let inset = Self.inset
        let fits = label.sizeThatFits(CGSize(width: width - inset.left - inset.right, height: .greatestFiniteMagnitude))
        return CGSize(width: ceil(fits.width) + inset.left + inset.right, height: ceil(fits.height) + inset.top + inset.bottom)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.inset(by: Self.inset)
    }
}
