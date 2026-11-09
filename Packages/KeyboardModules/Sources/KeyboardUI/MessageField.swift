import KeyboardCore
import UIKit

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
    /// The box's mic was tapped, to start or stop a dictation into it.
    public var onMic: () -> Void = {}
    /// The box was tapped without its caret, to bring the keys up.
    public var onTap: () -> Void = {}

    private let field = Field()
    private let placeholder = UILabel()
    private let send = UIButton(type: .custom)
    private let mic = MicButton()
    private var shown: Shown?
    /// Set while the box shows the document, so the changes it makes aren't taken for iOS's.
    private var showing = false

    private struct Shown: Equatable {
        var text: String
        var selection: Range<Int>
        var placeholder: String
        var theme: KeyboardTheme
        var caret: Bool
        var mic: MicButton.Phase
        var canSend: Bool { text.contains { !$0.isWhitespace } }
    }

    private static let font = UIFont.systemFont(ofSize: 17)
    private static let lineHeight: CGFloat = 22
    private static let sendSize: CGFloat = 28
    private static let sendMargin: CGFloat = 6
    private static let inset = UIEdgeInsets(top: 9, left: 14, bottom: 9, right: 2 * sendSize + 3 * sendMargin)
    private static let cornerRadius: CGFloat = 20
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
        layer.cornerCurve = .continuous
        layer.cornerRadius = Self.cornerRadius
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
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
        mic.accessibilityIdentifier = "iikb.chat.mic"
        mic.addAction(UIAction { [unowned self] _ in onMic() }, for: .touchUpInside)
        addSubview(mic)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.showShadow() }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `caret` while the keys are up to type into it, which focuses the box; `mic` the dictation's phase, which the
    /// box's mic shows, so a message can be said and sent with the keys down.
    public func show(
        _ line: LineDocument, placeholder text: String, caret: Bool, mic: MicButton.Phase, theme: KeyboardTheme
    ) {
        let next = Shown(
            text: line.text, selection: line.selection, placeholder: text, theme: theme, caret: caret, mic: mic)
        self.mic.show(mic, theme: theme)
        guard next != shown else { return }
        let last = shown
        shown = next
        showing = true
        defer { showing = false }
        if next.theme != last?.theme {
            backgroundColor = theme.searchField.ui
            layer.shadowColor = theme.shadow.ui.withAlphaComponent(1).cgColor
            showShadow()
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
        }
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
        if caret, !field.isFirstResponder {
            field.focusable = true
            field.becomeFirstResponder()
        } else if !caret, field.isFirstResponder {
            field.resignFirstResponder()
        }
        field.focusable = caret
        if next.canSend != last?.canSend { showSend(next.canSend, animated: last != nil && window != nil) }
        setNeedsLayout()
    }

    /// The height for `size.width` at up to five lines, within `size.height`.
    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: min(height(for: size.width, lines: 5), size.height))
    }

    /// The height the field wants at `width`, growing a line at a time up to `lines`, past which it scrolls.
    public func height(for width: CGFloat, lines: Int) -> CGFloat {
        let content = field.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let shown = ((content - Self.inset.top - Self.inset.bottom) / Self.lineHeight).rounded()
        return Self.inset.top + Self.inset.bottom + Self.lineHeight * min(max(shown, 1), CGFloat(lines))
    }

    /// The keys' shadow, which only light keys have.
    private func showShadow() {
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0 : Float(shown?.theme.shadow.alpha ?? 0)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        field.frame = bounds
        let inset = Self.inset
        placeholder.frame = CGRect(
            x: inset.left, y: inset.top, width: max(bounds.width - inset.left - inset.right, 0), height: Self.lineHeight
        )
        let size = Self.sendSize
        send.bounds.size = CGSize(width: size, height: size)
        send.center = CGPoint(x: bounds.maxX - Self.sendMargin - size / 2, y: bounds.maxY - Self.sendMargin - size / 2)
        mic.frame = send.frame.offsetBy(dx: -(size + Self.sendMargin), dy: 0)
        field.scrollRangeToVisible(field.selectedRange)
    }

    private func showSend(_ visible: Bool, animated: Bool) {
        let change = { [send] in send.alpha = visible ? 1 : 0.3 }
        send.isEnabled = visible
        if animated { UIView.animate(springDuration: 0.3, bounce: 0.2, animations: change) } else { change() }
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if send.frame.insetBy(dx: -4, dy: -8).contains(point) { return send }
        if mic.frame.insetBy(dx: -4, dy: -8).contains(point) { return mic }
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
/// otherwise asks for the keys.
private final class Field: UITextView {
    var onActivate: () -> Void = {}
    var focusable = false

    override func accessibilityActivate() -> Bool {
        onActivate()
        return true
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
