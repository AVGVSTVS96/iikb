import KeyboardCore
import UIKit
import UniformTypeIdentifiers

/// A chat's message box: a real `UITextView`, focused while the keys are up under it, so the caret, the loupe, the
/// selection handles and the edit menu are iOS's own. Its text is a `LineDocument` the keys type into through the
/// engine (a keyboard's keys reach only `textDocumentProxy`, so they can't type into its own views); what iOS edits
/// in it, a selection, a cut or a paste, goes to the owner, which applies it to the document and shows it again.
/// Focus inside a keyboard needs Full Access, without which iOS ends the keyboard (keyboardkit.com, "Text input
/// crashes in iOS 17"), so the owner asks for a caret only with it.
public final class MessageField: UIView, UITextViewDelegate {
    /// The caret or selection iOS picked, in characters.
    public var onSelect: (Range<Int>) -> Void = { _ in }
    /// iOS replaced `range`, in characters, with the string: a cut, a paste.
    public var onReplace: (Range<Int>, String) -> Void = { _, _ in }
    public var onSend: () -> Void = {}
    /// The box was tapped without its caret, to bring the keys up.
    public var onTap: () -> Void = {}
    /// The paperclip beside the box was tapped, to pick photos.
    public var onAttach: () -> Void = {}
    /// An attached photo's ✕ was tapped, by its index.
    public var onRemove: (Int) -> Void = { _ in }
    /// Paste in the box's edit menu, with photos on the clipboard: their items, each still to be read.
    public var onPastePhotos: ([NSItemProvider]) -> Void = { _ in }

    /// The box is iOS's Liquid Glass, as the tabs, More and the mic around it are.
    private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let field = Field()
    private let placeholder = UILabel()
    private let send = UIButton(type: .custom)
    /// Photos go with the words: a paperclip beside the box, as in Telegram, and what's attached above the words in it,
    /// as in Messages.
    private let attach = UIButton(type: .custom)
    private let attachGlass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let strip = UIScrollView()
    private var thumbs: [Thumb] = []
    private var shown: Shown?
    /// Set while the box shows the document, so the changes it makes aren't taken for iOS's.
    private var showing = false

    private struct Shown: Equatable {
        var text: String
        var selection: Range<Int>
        var placeholder: String
        var theme: KeyboardTheme
        var caret: Bool
        var photos: [URL]
        var picking: Bool
        var canSend: Bool { !photos.isEmpty || text.contains { !$0.isWhitespace } }
    }

    private static let font = UIFont.systemFont(ofSize: 17)
    private static let lineHeight: CGFloat = 22
    private static let sendSize: CGFloat = 28
    private static let sendMargin: CGFloat = 6
    private static let inset = UIEdgeInsets(top: 9, left: 14, bottom: 9, right: sendSize + 2 * sendMargin)
    private static let cornerRadius: CGFloat = 20
    /// The paperclip's circle, as tall as the box's one line, and its gap to the box.
    private static let attachSize: CGFloat = 40
    private static let attachGap: CGFloat = 8
    /// The attached photos' row inside the box, above the words.
    private static let thumbSize: CGFloat = 76
    private static let stripPadding: CGFloat = 8
    /// The photos' side as laid out: `thumbSize`, or less where the keyboard leaves the box less room than its photos
    /// and a line of words need, as on the folded Duo turned sideways.
    private var thumbSide = MessageField.thumbSize
    private static let lines = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }()
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .paragraphStyle: lines, .baselineOffset: (lineHeight - font.lineHeight) / 4,
    ]

    override public init(frame: CGRect) {
        super.init(frame: frame)
        glass.cornerConfiguration = .uniformCorners(radius: .fixed(Self.cornerRadius))
        glass.isUserInteractionEnabled = false
        addSubview(glass)
        field.delegate = self
        field.backgroundColor = .clear
        field.textContainerInset = Self.inset
        field.textContainer.lineFragmentPadding = 0
        field.alwaysBounceVertical = false
        field.showsHorizontalScrollIndicator = false
        field.typingAttributes = Self.attributes
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.inlinePredictionType = .no
        field.inputView = UIView(frame: .zero)
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.accessibilityIdentifier = "iikb.chat.field"
        field.onActivate = { [unowned self] in onTap() }
        placeholder.font = Self.font
        placeholder.isUserInteractionEnabled = false
        addSubview(field)
        addSubview(placeholder)

        send.accessibilityIdentifier = "iikb.chat.send"
        send.accessibilityLabel = "Send"
        send.layer.cornerRadius = Self.sendSize / 2
        send.addAction(UIAction { [unowned self] _ in onSend() }, for: .touchUpInside)
        addSubview(send)

        attachGlass.cornerConfiguration = .capsule()
        attachGlass.isUserInteractionEnabled = false
        addSubview(attachGlass)
        attach.accessibilityIdentifier = "iikb.chat.attach"
        attach.accessibilityLabel = "Attach photos"
        attach.addAction(UIAction { [unowned self] _ in onAttach() }, for: .touchUpInside)
        addSubview(attach)
        strip.showsHorizontalScrollIndicator = false
        strip.alwaysBounceHorizontal = true
        strip.clipsToBounds = true
        strip.isHidden = true
        addSubview(strip)
        field.onPastePhotos = { [unowned self] in onPastePhotos($0) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `caret` while the keys are up to type into it, which focuses the box as they come up and as the keys change its
    /// line, never otherwise, so text selected in a message keeps its selection while the keys stay up. The box has no
    /// mic of its own: the keyboard's one mic types into it like any field, so dictating works the same everywhere.
    /// `picking` while your photos are up, which colors the paperclip.
    public func show(
        _ line: LineDocument, placeholder text: String, caret: Bool, photos: [URL] = [], picking: Bool = false,
        theme: KeyboardTheme
    ) {
        let next = Shown(
            text: line.text, selection: line.selection, placeholder: text, theme: theme, caret: caret, photos: photos,
            picking: picking)
        guard next != shown else { return }
        let last = shown
        shown = next
        showing = true
        defer { showing = false }
        if next.theme != last?.theme {
            field.tintColor = theme.prominent.ui
            placeholder.textColor = theme.candidate.ui
            var look = UIButton.Configuration.filled()
            look.cornerStyle = .capsule
            look.baseBackgroundColor = theme.prominent.ui
            look.baseForegroundColor = theme.prominentLabel.ui
            look.image = UIImage(
                systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            )
            look.contentInsets = .zero
            send.configuration = look
            thumbs.forEach { $0.show(theme) }
        }
        if next.theme != last?.theme || next.picking != last?.picking {
            var clip = UIButton.Configuration.plain()
            clip.baseForegroundColor = picking ? theme.prominent.ui : theme.label.ui
            clip.image = UIImage(
                systemName: "paperclip",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: picking ? .semibold : .regular))
            clip.contentInsets = .zero
            attach.configuration = clip
            attach.accessibilityTraits = picking ? [.button, .selected] : .button
        }
        if next.photos != last?.photos { showPhotos(next.photos, theme: theme) }
        if next.text != field.text || next.theme != last?.theme {
            var attributes = Self.attributes
            attributes[.foregroundColor] = theme.label.ui
            field.attributedText = NSAttributedString(string: next.text, attributes: attributes)
            field.typingAttributes = attributes
        }
        placeholder.text = text
        placeholder.isHidden = !next.text.isEmpty
        let range = NSRange(
            location: next.text.utf16(fromCharacters: next.selection.lowerBound),
            length: String(next.text.dropFirst(next.selection.lowerBound).prefix(next.selection.count)).utf16.count)
        if field.selectedRange != range { field.selectedRange = range }
        let typed = last?.caret != true || next.text != last?.text || next.selection != last?.selection
        if caret, typed, !field.isFirstResponder {
            field.focusable = true
            field.becomeFirstResponder()
        } else if !caret, field.isFirstResponder {
            field.resignFirstResponder()
        }
        field.focusable = caret
        if next.canSend != last?.canSend { showSend(animated: last != nil && window != nil) }
        setNeedsLayout()
    }

    /// The height for `size.width` at up to five lines, within `size.height`.
    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: min(height(for: size.width, lines: 5), size.height))
    }

    /// The height the box wants at `width`, its photos' row and then its words, growing a line at a time up to
    /// `lines`, past which they scroll.
    public func height(for width: CGFloat, lines: Int) -> CGFloat {
        let inset = textInset(side: Self.thumbSize)
        let box = max(width - Self.attachSize - Self.attachGap, 1)
        let content = field.sizeThatFits(CGSize(width: box, height: .greatestFiniteMagnitude)).height
        let shown = ((content - inset.top - inset.bottom) / Self.lineHeight).rounded()
        return inset.top + inset.bottom + Self.lineHeight * min(max(shown, 1), CGFloat(lines))
    }

    /// The words' inset in the box, below the photos' row, of photos `side` points, when there are photos.
    private func textInset(side: CGFloat) -> UIEdgeInsets {
        var inset = Self.inset
        if shown?.photos.isEmpty == false { inset.top += side + Self.stripPadding }
        return inset
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let clip = Self.attachSize
        attachGlass.frame = CGRect(x: 0, y: bounds.maxY - clip, width: clip, height: clip)
        attach.frame = attachGlass.frame
        let box = bounds.inset(by: UIEdgeInsets(top: 0, left: clip + Self.attachGap, bottom: 0, right: 0))
        glass.frame = box
        field.frame = box
        let around = Self.inset.top + Self.stripPadding + Self.lineHeight + Self.inset.bottom
        thumbSide = min(Self.thumbSize, max(bounds.height - around, 32)).rounded(.down)
        let inset = textInset(side: thumbSide)
        if field.textContainerInset != inset { field.textContainerInset = inset }
        placeholder.frame = CGRect(
            x: box.minX + inset.left, y: inset.top, width: max(box.width - inset.left - inset.right, 0),
            height: Self.lineHeight)
        let size = Self.sendSize
        send.bounds.size = CGSize(width: size, height: size)
        send.center = CGPoint(x: box.maxX - Self.sendMargin - size / 2, y: box.maxY - Self.sendMargin - size / 2)
        let pad = Self.stripPadding
        let left = Self.inset.left
        let side = thumbSide
        strip.frame = CGRect(x: box.minX + left, y: pad, width: box.width - left - pad, height: side)
        for (index, thumb) in thumbs.enumerated() {
            thumb.frame = CGRect(x: CGFloat(index) * (side + pad), y: 0, width: side, height: side)
        }
        strip.contentSize = CGSize(width: max(CGFloat(thumbs.count) * (side + pad) - pad, 0), height: side)
        field.scrollRangeToVisible(field.selectedRange)
    }

    /// The attached photos as thumbnails in the box, each with its ✕; the newest scrolled into view.
    private func showPhotos(_ photos: [URL], theme: KeyboardTheme) {
        let added = photos.count > thumbs.count
        thumbs.forEach { $0.removeFromSuperview() }
        thumbs = photos.enumerated().map { index, url in
            let thumb = Thumb(url)
            thumb.accessibilityIdentifier = "iikb.chat.photo.\(index)"
            thumb.removeIdentifier = "iikb.chat.photo.\(index).remove"
            thumb.onRemove = { [unowned self] in onRemove(index) }
            thumb.show(theme)
            strip.addSubview(thumb)
            return thumb
        }
        strip.isHidden = photos.isEmpty
        field.textContainerInset = textInset(side: thumbSide)
        superview?.setNeedsLayout()
        setNeedsLayout()
        layoutIfNeeded()
        if added {
            strip.scrollRectToVisible(thumbs.last?.frame ?? .zero, animated: false)
        }
    }

    /// Send grows in at the box's end once there's something to send, and shrinks away when there isn't.
    private func showSend(animated: Bool) {
        guard let shown else { return }
        let on = shown.canSend
        let change = { [send] in
            send.alpha = on ? 1 : 0
            send.transform = on ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
        send.isEnabled = on
        if animated { UIView.animate(springDuration: 0.3, bounce: 0.2, animations: change) } else { change() }
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if send.isEnabled, send.frame.insetBy(dx: -4, dy: -8).contains(point) { return send }
        if attach.frame.insetBy(dx: -4, dy: -4).contains(point) { return attach }
        if !strip.isHidden, let hit = strip.hitTest(convert(point, to: strip), with: event) { return hit }
        return super.hitTest(point, with: event)
    }

    public func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        guard field.focusable else {
            onTap()
            return false
        }
        return true
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard !showing, let text = shown?.text else { return }
        let range = textView.selectedRange
        let start = text.characters(fromUTF16: range.location)
        onSelect(start..<max(text.characters(fromUTF16: range.location + range.length), start))
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText: String) -> Bool {
        guard !showing, let text = shown?.text else { return true }
        let start = text.characters(fromUTF16: range.location)
        onReplace(start..<max(text.characters(fromUTF16: range.location + range.length), start), replacementText)
        return false
    }
}

/// The box's text view, which takes focus only while the box shows a caret (`textViewShouldBeginEditing`): a tap on it
/// otherwise asks for the keys. Paste with photos on the clipboard attaches them.
private final class Field: UITextView {
    var onActivate: () -> Void = {}
    var onPastePhotos: ([NSItemProvider]) -> Void = { _ in }
    var focusable = false

    override func accessibilityActivate() -> Bool {
        onActivate()
        return true
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        guard board.hasImages else { return super.paste(sender) }
        onPastePhotos(board.itemProviders.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
    }
}

/// An attached photo in the box: the picture, rounded, and a ✕ in its corner that takes it off.
private final class Thumb: UIView {
    var onRemove: () -> Void = {}
    var removeIdentifier: String? {
        get { remove.accessibilityIdentifier }
        set { remove.accessibilityIdentifier = newValue }
    }
    private let picture = UIImageView()
    private let remove = UIButton(type: .custom)
    private let url: URL
    private var loading: Task<Void, Never>?

    init(_ url: URL) {
        self.url = url
        super.init(frame: .zero)
        picture.contentMode = .scaleAspectFill
        picture.clipsToBounds = true
        picture.layer.cornerRadius = 12
        picture.layer.cornerCurve = .continuous
        addSubview(picture)
        var look = UIButton.Configuration.filled()
        look.cornerStyle = .capsule
        look.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        look.baseForegroundColor = .white
        look.image = UIImage(
            systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold))
        look.contentInsets = .zero
        remove.configuration = look
        remove.accessibilityLabel = "Remove photo"
        remove.addAction(UIAction { [unowned self] _ in onRemove() }, for: .touchUpInside)
        addSubview(remove)
        isAccessibilityElement = false
        loading = Task { [weak self, url] in
            let image = await Self.thumbnail(url)
            self?.picture.image = image
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { loading?.cancel() }

    func show(_ theme: KeyboardTheme) {
        picture.backgroundColor = theme.key.ui
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picture.frame = bounds
        remove.frame = CGRect(x: bounds.maxX - 26, y: 4, width: 22, height: 22)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        remove.frame.insetBy(dx: -8, dy: -8).contains(point) ? remove : nil
    }

    @concurrent nonisolated private static func thumbnail(_ url: URL) async -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }  // file: a photo to send
        return await ImageBubble.decode(data, side: 240)
    }
}

extension String {
    fileprivate func utf16(fromCharacters count: Int) -> Int {
        prefix(count).utf16.count
    }

    /// The characters before `offset` UTF-16 units, a character cut by it counted as before.
    fileprivate func characters(fromUTF16 offset: Int) -> Int {
        var units = 0
        var characters = 0
        for character in self {
            guard units < offset else { break }
            units += character.utf16.count
            characters += 1
        }
        return characters
    }
}
