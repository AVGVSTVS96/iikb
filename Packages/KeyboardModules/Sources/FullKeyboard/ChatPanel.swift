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
    /// iOS replaced a range of the box's text, by its edit menu's Cut or Paste.
    var onReplace: (Range<Int>, String) -> Void = { _, _ in }
    /// The paperclip was tapped, to pick photos.
    var onAttach: () -> Void = {}
    /// An attached photo was taken off, by its index.
    var onRemove: (Int) -> Void = { _ in }
    /// Photos pasted into the box, still to be read.
    var onPastePhotos: ([NSItemProvider]) -> Void = { _ in }
    /// The photos attached to the next message, shown in the box.
    var photos: [URL] = []
    /// A link in a message was opened.
    var onOpen: (URL) -> Void = { _ in }
    /// A chat's tab was tapped, by its index in the list.
    var onPick: (Int) -> Void = { _ in }
    /// The chats with something newer than what you saw, by index.
    var fresh: Set<Int> = []
    /// The span the bar's tabs take, in the panel's terms, which the tabs over the messages take too.
    var tabsRow: (minX: CGFloat, maxX: CGFloat)? { didSet { setNeedsLayout() } }
    /// Where the bar's More sits beside its tabs, in the panel's terms; with the keys up the chat's own More sits there.
    var moreFrame = CGRect.zero { didSet { setNeedsLayout() } }
    var onMore: () -> Void = {}
    /// More beside the tabs with the keys up, where the bar has it with the keys down, so the spot holds More either way.
    private let more = BarButton("More", draw: Panel.moreGlyph)
    private var glyph = 0.0
    var field: PanelField { .own(composer) }
    private let composer = MessageField()
    private var line: LineDocument?
    private var typing = false
    private var picking = false

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
        composer.onTap = { [unowned self] in if !typing || picking { onFocus() } }
        composer.onSelect = { [unowned self] in onSelect($0) }
        composer.onReplace = { [unowned self] in onReplace($0, $1) }
        composer.onAttach = { [unowned self] in onAttach() }
        composer.onRemove = { [unowned self] in onRemove($0) }
        composer.onPastePhotos = { [unowned self] in onPastePhotos($0) }
        message.accessibilityIdentifier = "iikb.chat.message"
        message.onTurnOn = { [unowned self] in onTurnOn() }
        tabs.onPick = { [unowned self] in onPick($0) }
        more.accessibilityIdentifier = "iikb.chat.more"
        more.glassy = true
        more.addAction(UIAction { [unowned self] _ in onMore() }, for: .touchUpInside)
        addSubview(more)
        [thread, tabs, message].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        shown = nil
    }

    /// The box shows `line`; `typing` is whether the keys are up under it, or the photo grid when `picking`, which
    /// leaves the box without its caret, so a tap on it brings the keys back.
    func show(_ line: LineDocument, typing: Bool, picking: Bool) {
        self.line = line
        if typing != self.typing { setNeedsLayout() }
        (self.typing, self.picking) = (typing, picking)
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        if let line {
            composer.show(
                line, placeholder: chats.open.map { "Message \($0.name)" } ?? "Message",
                caret: typing && !picking && fullAccess(), photos: photos, picking: picking, theme: theme)
        }
        bar = metrics.toolbar.bar
        glyph = metrics.toolbar.glyph
        more.theme = theme
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
                    failed: message.failed == true,
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
        let row = CGFloat(bar)
        tabs.isHidden = !typing || chats.list.isEmpty || bounds.height < row
        more.isHidden = tabs.isHidden
        let around = (row - ChatTabs.height) / 2
        more.place(
            CGRect(
                x: moreFrame.minX, y: (row - moreFrame.height) / 2, width: moreFrame.width, height: moreFrame.height),
            glyph: glyph, reach: UIEdgeInsets(top: -around, left: -4, bottom: -around, right: -4))
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
        layer.cornerRadius = MenuView.cardRadius
        layer.cornerCurve = .continuous
        name.text = chat.name
        name.font = .systemFont(ofSize: 14, weight: .semibold)
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
        backgroundColor = isHighlighted ? theme.keyPressed.ui : theme.shelfCard
    }

    override var isHighlighted: Bool { didSet { show(theme) } }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = bounds.insetBy(dx: 10, dy: 8)
        let both = line.text != nil && inset.height >= 30
        line.isHidden = !both
        guard both else {
            name.frame = inset
            return
        }
        name.frame = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: 18)
        line.numberOfLines = max(Int((inset.height - 20) / 15), 1)
        let fits = line.sizeThatFits(CGSize(width: inset.width, height: inset.height - 20)).height
        line.frame = CGRect(
            x: inset.minX, y: name.frame.maxY + 2, width: inset.width, height: min(fits, inset.height - 20))
    }
}
