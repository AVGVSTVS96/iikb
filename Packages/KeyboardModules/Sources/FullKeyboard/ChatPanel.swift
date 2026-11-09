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
    var onMic: () -> Void = {}
    /// The box was tapped with the keys down.
    var onFocus: () -> Void = {}
    /// The messages were tapped with the keys up.
    var onBrowse: () -> Void = {}
    /// A tap or a drag in the box placed the caret or selected, as offsets into its text.
    var onSelect: (Range<Int>) -> Void = { _ in }
    /// iOS replaced a range of the box's text, by its edit menu's Cut or Paste.
    var onReplace: (Range<Int>, String) -> Void = { _, _ in }
    /// A link in a message was opened.
    var onOpen: (URL) -> Void = { _ in }
    /// A chat's tab was tapped, by its index in the list.
    var onPick: (Int) -> Void = { _ in }
    /// The chats with something newer than what you saw, by index.
    var fresh: Set<Int> = []
    /// The span the bar's tabs take, in the panel's terms, which the tabs over the messages take too.
    var tabsRow: (minX: CGFloat, maxX: CGFloat)? { didSet { setNeedsLayout() } }
    var field: PanelField { .own(composer) }
    private let composer = MessageField()
    private var line: LineDocument?
    private var typing = false
    private var mic = MicButton.Phase.off

    private struct Shown: Equatable {
        var revision: Int
        var theme: KeyboardTheme
    }

    private let chats: Chats
    private var shown: Shown?
    private let thread = ChatThread()
    private let message = PanelNotice()
    /// The chats as tabs over the messages while the keys are up, just where the bar shows them with the keys down,
    /// so they stay put as the keys come and go.
    private let tabs = ChatTabs()
    /// The bar's height, whose row the tabs sit in.
    private var bar = 38.0

    init(chats: Chats) {
        self.chats = chats
        super.init(frame: .zero)
        thread.onOpen = { [unowned self] in onOpen($0) }
        thread.onRead = { [unowned self] in if typing { onBrowse() } }
        thread.fetch = { [chats] in await chats.data(at: $0) }
        composer.onSend = { [unowned self] in onSend() }
        composer.onMic = { [unowned self] in onMic() }
        composer.onTap = { [unowned self] in if !typing { onFocus() } }
        composer.onSelect = { [unowned self] in onSelect($0) }
        composer.onReplace = { [unowned self] in onReplace($0, $1) }
        message.accessibilityIdentifier = "iikb.chat.message"
        message.onTurnOn = { [unowned self] in onTurnOn() }
        tabs.onPick = { [unowned self] in onPick($0) }
        [thread, tabs, message].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        shown = nil
    }

    /// The box shows `line` and the dictation's `mic`; `typing` is whether the keys are up under it.
    func show(_ line: LineDocument, typing: Bool, mic: MicButton.Phase) {
        self.line = line
        self.mic = mic
        if typing != self.typing { setNeedsLayout() }
        self.typing = typing
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        if let line {
            composer.show(
                line, placeholder: chats.open.map { "Message \($0.name)" } ?? "Message", caret: typing && fullAccess(),
                mic: mic,
                theme: theme)
        }
        bar = metrics.toolbar.bar
        tabs.show(
            chats.list.map(\.name), open: chats.list.firstIndex { $0 == chats.open }, fresh: fresh, theme: theme)
        let next = Shown(revision: chats.revision, theme: theme)
        guard next != shown else { return }
        shown = next
        let missing = fullAccess() ? nil : "Chats need Full Access."
        let empty = chats.messages.isEmpty
        let quiet =
            !chats.listed
            ? "Loading chats…" : chats.list.isEmpty ? "No chats yet." : chats.loaded && empty ? "No messages yet." : nil
        message.show(
            missing ?? (empty ? chats.problem : nil) ?? quiet, turnOn: missing != nil, oneRow: false, theme: theme)
        thread.show(
            chats.messages.suffix(40).map { message in
                ChatMessage(
                    text: message.text, mine: message.mine, pending: message.pending == true,
                    files: (message.files ?? []).compactMap { file in
                        chats.url(of: file).map {
                            ChatFile(
                                name: file.name, url: $0, type: file.type, width: file.width, height: file.height)
                        }
                    })
            },
            footnote: empty ? nil : chats.problem, theme: theme)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tabs.isHidden = !typing || chats.list.isEmpty
        let row = CGFloat(bar)
        let span = tabsRow ?? (0, bounds.width)
        tabs.frame = CGRect(
            x: span.minX, y: ((row - ChatTabs.height) / 2).rounded(),
            width: tabs.width(within: min(span.maxX, bounds.width) - span.minX), height: ChatTabs.height)
        thread.frame = bounds.inset(by: UIEdgeInsets(top: tabs.isHidden ? 0 : row - 6, left: 0, bottom: 0, right: 0))
        message.frame = bounds
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
