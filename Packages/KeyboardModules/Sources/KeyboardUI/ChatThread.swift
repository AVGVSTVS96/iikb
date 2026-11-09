import KeyboardCore
import UIKit
import UniformTypeIdentifiers

/// One message in a `ChatThread`: its text, read as inline markdown, the files with it, and whether it's yours.
public struct ChatMessage: Hashable, Sendable {
    public var text: String
    public var mine: Bool
    /// Sent but not yet in the chat's own messages.
    public var pending: Bool
    public var files: [ChatFile]

    public init(text: String, mine: Bool, pending: Bool = false, files: [ChatFile] = []) {
        self.text = text
        self.mine = mine
        self.pending = pending
        self.files = files
    }
}

/// A file sent in a chat: a photo shows as one (`ImageBubble`), anything else as its name.
public struct ChatFile: Hashable, Sendable {
    public var name: String
    public var url: URL
    /// Its MIME type, when it's known.
    public var type: String?
    /// A photo's size in pixels, when it's known, so its bubble takes its shape before it comes.
    public var width: Double?
    public var height: Double?

    public init(name: String, url: URL, type: String? = nil, width: Double? = nil, height: Double? = nil) {
        self.name = name
        self.url = url
        self.type = type
        self.width = width
        self.height = height
    }

    public var isImage: Bool { type?.hasPrefix("image/") == true }
}

/// A bubble a `ChatThread` lays out: one side's, sized to its content, its corners tightened toward its neighbors.
public protocol ChatBubble: UIView {
    var mine: Bool { get }
    var joined: (above: Bool, below: Bool) { get set }
    /// Whether it draws what it shows. Off while it's far from the screen: a message's drawn text costs its whole area in
    /// pixels, and a long chat's added up past the keyboard's memory limit.
    var drawn: Bool { get set }
    func size(within width: CGFloat) -> CGSize
}

/// A chat's messages as Messages lays them out: yours on the right, a turn's bubbles 2 apart and turns 10, the newest
/// at the bottom and kept there as messages come, the ends faded. Each bubble's text is real text (`MessageBubble`):
/// it selects, copies and opens its links as any text in iOS does.
public final class ChatThread: UIView, UIGestureRecognizerDelegate, UIScrollViewDelegate {
    /// A link in a message was opened. A keyboard has no public way to open one, so its owner does.
    public var onOpen: (URL) -> Void = { _ in }
    /// The messages were tapped: you're reading. Selecting text in them leaves the keys where they are.
    public var onRead: () -> Void = {}
    /// A file's bytes, which only the owner can fetch.
    public var fetch: (URL) async -> Data? = { _ in nil }

    private let scroll = UIScrollView()
    /// Messages fade out over a line and a bit as they scroll up under the tabs, and over less into the box below.
    private static let topFade = 28.0
    private static let bottomFade = 10.0
    private let fade = CAGradientLayer()
    private var bubbles: [any ChatBubble] = []
    private var photo: PhotoView?
    private var theme = KeyboardTheme.lightCurrent
    /// A line under the messages, like what went wrong.
    private let footnote = UILabel()

    override public init(frame: CGRect) {
        super.init(frame: frame)
        scroll.accessibilityIdentifier = "iikb.chat.messages"
        scroll.showsVerticalScrollIndicator = false
        scroll.delegate = self
        [scroll.topEdgeEffect, scroll.bottomEdgeEffect, scroll.leftEdgeEffect, scroll.rightEdgeEffect].forEach {
            $0.isHidden = true
        }
        fade.colors = [UIColor.clear, .black, .black, .clear].map(\.cgColor)
        layer.mask = fade
        addSubview(scroll)
        footnote.font = .systemFont(ofSize: 13)
        footnote.textAlignment = .center
        footnote.numberOfLines = 0
        scroll.addSubview(footnote)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Each message as Messages splits one: its photos, then its other files, then its text, each a bubble.
    public func show(_ messages: [ChatMessage], footnote note: String?, theme: KeyboardTheme) {
        self.theme = theme
        var index = 0
        func next<Bubble: ChatBubble>(_ make: () -> Bubble) -> Bubble {
            defer { index += 1 }
            if index < bubbles.count, let bubble = bubbles[index] as? Bubble { return bubble }
            let bubble = make()
            if index < bubbles.count {
                bubbles[index].removeFromSuperview()
                bubbles[index] = bubble
            } else {
                bubbles.append(bubble)
            }
            scroll.addSubview(bubble)
            return bubble
        }
        for message in messages {
            for file in message.files where file.isImage {
                next(image).show(file, mine: message.mine, pending: message.pending, theme: theme)
            }
            for file in message.files where !file.isImage {
                next(text).show(file, mine: message.mine, pending: message.pending, theme: theme)
            }
            if !message.text.isEmpty || message.files.isEmpty { next(text).show(message, theme: theme) }
        }
        while bubbles.count > index { bubbles.removeLast().removeFromSuperview() }
        footnote.text = note
        footnote.textColor = theme.candidate.ui
        setNeedsLayout()
    }

    private func text() -> MessageBubble {
        let bubble = MessageBubble()
        bubble.onOpen = { [unowned self] in onOpen($0) }
        return bubble
    }

    private func image() -> ImageBubble {
        let bubble = ImageBubble()
        bubble.fetch = { [unowned self] in await fetch($0) }
        bubble.onLoad = { [unowned self] in setNeedsLayout() }
        bubble.onTap = { [unowned self] in open($0) }
        return bubble
    }

    private func open(_ bubble: ImageBubble) {
        photo?.removeFromSuperview()
        let view = PhotoView(bubble, fetch: { [unowned self] in await fetch($0) }, theme: theme)
        view.onClose = { [unowned self, unowned view] in
            view.removeFromSuperview()
            if photo === view { photo = nil }
        }
        view.frame = bounds
        addSubview(view)
        photo = view
    }

    @objc private func tapped() {
        onRead()
    }

    /// A tap reads even when it lands on a bubble's text, whose own taps place or clear a selection and open links.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let wasAtEnd = scroll.contentOffset.y >= scroll.contentSize.height - scroll.bounds.height - 1
        scroll.frame = bounds
        photo?.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        let top = bounds.height == 0 ? 0 : min(Self.topFade / bounds.height, 0.5)
        let bottom = bounds.height == 0 ? 0 : min(Self.bottomFade / bounds.height, 0.5)
        fade.locations = [0, top, 1 - bottom, 1].map { NSNumber(value: $0) }
        CATransaction.commit()
        let width = bounds.width
        let widest = min((width * 0.75).rounded(.down), 520)
        var y = Self.topFade - 12
        for (index, bubble) in bubbles.enumerated() {
            let after = index > 0 && bubbles[index - 1].mine == bubble.mine
            let before = index + 1 < bubbles.count && bubbles[index + 1].mine == bubble.mine
            bubble.joined = (above: after, below: before)
            if index > 0 { y += after ? 2 : 10 }
            let size = bubble.size(within: widest)
            bubble.frame = CGRect(x: bubble.mine ? width - size.width : 0, y: y, width: size.width, height: size.height)
            y += size.height
        }
        if let note = footnote.text, !note.isEmpty {
            let fits = footnote.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            footnote.frame = CGRect(x: 0, y: y + 8, width: width, height: ceil(fits.height))
            y = footnote.frame.maxY
        } else {
            footnote.frame = .zero
        }
        y += 14
        scroll.contentInset.top = max(scroll.bounds.height - y, 0)
        scroll.contentSize = CGSize(width: width, height: y)
        if wasAtEnd || y <= scroll.bounds.height { scroll.contentOffset.y = y - scroll.bounds.height }
        drawNear()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        drawNear()
    }

    /// Only the bubbles within a screen of what shows draw.
    private func drawNear() {
        let near = scroll.bounds.insetBy(dx: 0, dy: -scroll.bounds.height)
        for bubble in bubbles { bubble.drawn = bubble.frame.intersects(near) }
    }
}

/// One message as Messages draws it, flat: yours on the accent color, the other side's on a key's, SF Pro 17 on 22 point
/// lines, hugging its text, with markdown's bold, italics, code and links. The text is a `UITextView`, so holding it
/// selects with iOS's handles and edit menu, links and web addresses are links, and a link held offers Open and Copy.
public final class MessageBubble: UIView, ChatBubble, UITextViewDelegate {
    /// A link in the message was tapped, or Open picked from its menu.
    public var onOpen: (URL) -> Void = { _ in }
    public private(set) var mine = false
    /// Whether the message above and below is from the same side, whose corners on that side tighten, as Messages'.
    public var joined = (above: false, below: false) { didSet { if joined != oldValue { setNeedsLayout() } } }

    public var drawn = false {
        didSet { if drawn != oldValue { text.attributedText = drawn ? made : nil } }
    }

    private let shape = CAShapeLayer()
    private let text = UITextView()
    private var shown: (content: Content, theme: KeyboardTheme)?
    private var made = NSAttributedString()
    private var sized: (width: CGFloat, size: CGSize)?
    /// Measures a message's text for one not drawn, laid out as `text` is.
    private static let sizer = {
        let sizer = UITextView()
        MessageBubble.lay(sizer)
        return sizer
    }()

    private enum Content: Equatable {
        case message(ChatMessage)
        case file(ChatFile, mine: Bool, pending: Bool)
    }
    private static let inset = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
    private static let size = 17.0

    override public init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(shape, at: 0)
        text.delegate = self
        text.isEditable = false
        text.isSelectable = true
        text.backgroundColor = .clear
        text.dataDetectorTypes = [.link]
        Self.lay(text)
        addSubview(text)
    }

    private static func lay(_ text: UITextView) {
        text.isScrollEnabled = false
        text.textContainerInset = .zero
        text.textContainer.lineFragmentPadding = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show(_ message: ChatMessage, theme: KeyboardTheme) {
        show(.message(message), mine: message.mine, pending: message.pending, theme: theme) { color in
            Self.attributed(message.text, color: color)
        }
    }

    /// A file that isn't a photo, as its name after a document glyph.
    public func show(_ file: ChatFile, mine: Bool, pending: Bool, theme: KeyboardTheme) {
        show(.file(file, mine: mine, pending: pending), mine: mine, pending: pending, theme: theme) { color in
            let glyph = UIImage(systemName: "doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15))?
                .withTintColor(color, renderingMode: .alwaysOriginal)
            let text = NSMutableAttributedString(attachment: NSTextAttachment(image: glyph ?? UIImage()))
            text.append(NSAttributedString(string: " " + file.name))
            text.addAttribute(.font, value: UIFont.systemFont(ofSize: Self.size), range: NSRange(0..<text.length))
            return Self.lined(text, color: color)
        }
    }

    private func show(
        _ content: Content, mine: Bool, pending: Bool, theme: KeyboardTheme, text made: (UIColor) -> NSAttributedString
    ) {
        if let shown, shown.content == content, shown.theme == theme { return }
        shown = (content, theme)
        self.mine = mine
        shape.fillColor = (mine ? theme.prominent.ui : theme.key.ui).cgColor
        alpha = pending ? 0.6 : 1
        let color = mine ? theme.prominentLabel.ui : theme.label.ui
        text.tintColor = mine ? theme.prominentLabel.ui : theme.prominent.ui
        text.linkTextAttributes = [.foregroundColor: color, .underlineStyle: NSUnderlineStyle.single.rawValue]
        self.made = made(color)
        sized = nil
        if drawn { text.attributedText = self.made }
        text.accessibilityLabel = mine ? "You" : nil
        setNeedsLayout()
    }

    private static func attributed(_ markdown: String, color: UIColor) -> NSAttributedString {
        let parsed = try? NSMutableAttributedString(
            AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        let text = parsed ?? NSMutableAttributedString(string: markdown)
        let whole = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.inlinePresentationIntent, in: whole) { intent, range, _ in
            let intent = (intent as? NSNumber).map { InlinePresentationIntent(rawValue: $0.uintValue) } ?? []
            let font: UIFont =
                intent.contains(.code)
                ? .monospacedSystemFont(ofSize: size - 2, weight: .regular)
                : intent.contains(.stronglyEmphasized)
                    ? .systemFont(ofSize: size, weight: .semibold)
                    : intent.contains(.emphasized) ? .italicSystemFont(ofSize: size) : .systemFont(ofSize: size)
            text.addAttribute(.font, value: font, range: range)
        }
        return lined(text, color: color)
    }

    /// SF Pro's 22 point lines in `color`.
    private static func lined(_ text: NSMutableAttributedString, color: UIColor) -> NSAttributedString {
        let lines = NSMutableParagraphStyle()
        lines.minimumLineHeight = 22
        lines.maximumLineHeight = 22
        text.addAttributes([.foregroundColor: color, .paragraphStyle: lines], range: NSRange(0..<text.length))
        return text
    }

    /// Its size hugging its text, its lines at most `width` with the insets.
    public func size(within width: CGFloat) -> CGSize {
        if let sized, sized.width == width { return sized.size }
        let inset = Self.inset
        let room = width - inset.left - inset.right
        let used = made.boundingRect(
            with: CGSize(width: room, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
        let lineWidth = min(ceil(used.width) + 1, room)
        Self.sizer.attributedText = made
        let height = Self.sizer.sizeThatFits(CGSize(width: lineWidth, height: .greatestFiniteMagnitude)).height
        let size = CGSize(width: lineWidth + inset.left + inset.right, height: ceil(height) + inset.top + inset.bottom)
        sized = (width, size)
        return size
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        text.frame = bounds.inset(by: Self.inset)
        let path = UIBezierPath(bubble: bounds, mine: mine, joined: joined)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.path = path.cgPath
        CATransaction.commit()
    }

    public func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction)
        -> UIAction?
    {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return UIAction { [unowned self] _ in onOpen(url) }
    }

    public func textView(
        _ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
        guard case .link(let url) = textItem.content else { return .init(menu: defaultMenu) }
        let open = UIAction(title: "Open Link", image: UIImage(systemName: "safari")) { [unowned self] _ in
            onOpen(url)
        }
        let copy = UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
            let item: [String: Any] = [UTType.url.identifier: url, UTType.plainText.identifier: url.absoluteString]
            UIPasteboard.general.items = [item]
        }
        return .init(menu: UIMenu(children: [open, copy]))
    }
}

extension UIBezierPath {
    /// A bubble's outline: corners of 18, tightened to 6 on its side toward a neighbor from the same side, as Messages'.
    convenience init(bubble rect: CGRect, mine: Bool, joined: (above: Bool, below: Bool)) {
        let round: CGFloat = 18
        let tight: CGFloat = 6
        let side = (top: joined.above ? tight : round, bottom: joined.below ? tight : round)
        self.init(
            shape: rect,
            mine
                ? (topLeft: round, topRight: side.top, bottomLeft: round, bottomRight: side.bottom)
                : (topLeft: side.top, topRight: round, bottomLeft: side.bottom, bottomRight: round))
    }

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
