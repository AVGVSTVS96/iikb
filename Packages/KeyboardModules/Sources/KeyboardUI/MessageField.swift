import KeyboardCore
import UIKit

/// A chat's message box, as Messages draws one: it wraps and grows to the height its owner allows, then scrolls,
/// keeping the caret in view. It draws a `LineDocument` the keys type into and turns touches into caret and selection
/// changes; its owner applies them to the document and shows it again.
public final class MessageField: UIView, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
    /// The caret or selection a touch picked, in characters.
    public var onSelect: (Range<Int>) -> Void = { _ in }
    public var onSend: () -> Void = {}
    /// The box's mic was tapped, to start or stop a dictation into it.
    public var onMic: () -> Void = {}
    /// Any tap on the field, before the `onSelect` it brings.
    public var onTap: () -> Void = {}
    /// Cut, Copy or Paste picked from the selection's menu, for the selection the owner holds.
    public var onEdit: (SuggestionBar.Edit) -> Void = { _ in }

    private let canvas = Canvas()
    private let highlight = UIView()
    private let caret = UIView()
    private let handles = [Handle(), Handle()]
    private let send = UIButton(type: .custom)
    private let mic = MicButton()
    private var shown: Shown?
    private var drag: Drag?
    private var taps = 1
    private lazy var menu = UIEditMenuInteraction(delegate: self)
    private var menuWanted = false

    private struct Shown: Equatable {
        var text: String
        var selection: Range<Int>
        var placeholder: String
        var theme: KeyboardTheme
        var caret: Bool
        var mic: MicButton.Phase
        var canSend: Bool { text.contains { !$0.isWhitespace } }
    }

    private enum Drag { case caret, start, end }

    private static let font = UIFont.systemFont(ofSize: 17)
    private static let lineHeight: CGFloat = 22
    private static let sendSize: CGFloat = 28
    private static let sendMargin: CGFloat = 6
    private static let inset = UIEdgeInsets(top: 9, left: 14, bottom: 9, right: 2 * sendSize + 3 * sendMargin)
    private static let cornerRadius: CGFloat = 20

    override public init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        layer.cornerRadius = Self.cornerRadius
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        canvas.layer.cornerCurve = .continuous
        canvas.layer.cornerRadius = Self.cornerRadius
        canvas.isEditable = false
        canvas.isSelectable = false
        canvas.backgroundColor = .clear
        canvas.textContainerInset = Self.inset
        canvas.textContainer.lineFragmentPadding = 0
        canvas.alwaysBounceVertical = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.accessibilityIdentifier = "iikb.chat.field"
        canvas.onActivate = { [unowned self] in onTap() }
        highlight.isUserInteractionEnabled = false
        caret.isUserInteractionEnabled = false
        caret.layer.cornerRadius = 1
        canvas.insertSubview(highlight, at: 0)
        ([caret] + handles).forEach(canvas.addSubview)
        addSubview(canvas)

        send.accessibilityIdentifier = "iikb.chat.send"
        send.accessibilityLabel = "Send"
        send.layer.cornerRadius = Self.sendSize / 2
        send.addAction(UIAction { [unowned self] _ in onSend() }, for: .touchUpInside)
        addSubview(send)
        mic.accessibilityIdentifier = "iikb.chat.mic"
        mic.addAction(UIAction { [unowned self] _ in onMic() }, for: .touchUpInside)
        addSubview(mic)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.delegate = self
        addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged))
        pan.delegate = self
        addGestureRecognizer(pan)
        canvas.panGestureRecognizer.require(toFail: pan)
        addInteraction(menu)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.showShadow() }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `caret` while the keys are up to type into it; `mic` the dictation's phase, which the box's mic shows, so a
    /// message can be said and sent with the keys down.
    public func show(
        _ line: LineDocument, placeholder: String, caret: Bool, mic: MicButton.Phase, theme: KeyboardTheme
    ) {
        let next = Shown(
            text: line.text, selection: line.selection, placeholder: placeholder, theme: theme, caret: caret, mic: mic)
        self.mic.show(mic, theme: theme)
        guard next != shown else { return }
        let last = shown
        shown = next
        if next.text != last?.text || next.placeholder != last?.placeholder || next.theme != last?.theme {
            let empty = next.text.isEmpty
            canvas.attributedText = NSAttributedString(
                string: empty ? placeholder : next.text,
                attributes: [
                    .font: Self.font,
                    .foregroundColor: empty ? theme.candidate.ui : theme.label.ui,
                    .paragraphStyle: Self.lines,
                    .baselineOffset: (Self.lineHeight - Self.font.lineHeight) / 4,
                ])
            canvas.line = next.text
            canvas.accessibilityLabel = placeholder
        }
        if next.theme != last?.theme {
            backgroundColor = theme.searchField.ui
            layer.shadowColor = theme.shadow.ui.withAlphaComponent(1).cgColor
            showShadow()
            self.caret.backgroundColor = theme.prominent.ui
            highlight.backgroundColor = theme.prominent.ui.withAlphaComponent(0.25)
            handles.forEach { $0.color = theme.prominent.ui }
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
        if next.canSend != last?.canSend { showSend(next.canSend, animated: last != nil && window != nil) }
        if next.text != last?.text || next.selection != last?.selection || next.caret != last?.caret { blink() }
        if next.text != last?.text || next.selection != last?.selection { menu.dismissMenu() }
        setNeedsLayout()
    }

    /// The height for `size.width` at up to five lines, within `size.height`.
    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: min(height(for: size.width, lines: 5), size.height))
    }

    /// The height the field wants at `width`, growing a line at a time up to `lines`, past which it scrolls.
    public func height(for width: CGFloat, lines: Int) -> CGFloat {
        let content = canvas.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let shown = ((content - Self.inset.top - Self.inset.bottom) / Self.lineHeight).rounded()
        return Self.inset.top + Self.inset.bottom + Self.lineHeight * min(max(shown, 1), CGFloat(lines))
    }

    private static let lines = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }()

    /// The keys' shadow, which only light keys have.
    private func showShadow() {
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0 : Float(shown?.theme.shadow.alpha ?? 0)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        let size = Self.sendSize
        send.bounds.size = CGSize(width: size, height: size)
        send.center = CGPoint(x: bounds.maxX - Self.sendMargin - size / 2, y: bounds.maxY - Self.sendMargin - size / 2)
        mic.frame = send.frame.offsetBy(dx: -(size + Self.sendMargin), dy: 0)
        canvas.layoutIfNeeded()
        drawSelection()
        guard let shown, let range = textRange(shown.selection) else { return }
        let end = canvas.caretRect(for: drag == .start ? range.start : range.end)
        canvas.scrollRectToVisible(end.insetBy(dx: 0, dy: -Self.inset.top), animated: false)
        guard menuWanted else { return }
        menuWanted = false
        showMenu()
    }

    private func showMenu() {
        guard shown?.selection.isEmpty == false else { return }
        let target = selectionBox
        menu.presentEditMenu(
            with: UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: target.midX, y: target.minY)))
    }

    private var selectionBox: CGRect {
        canvas.convert(highlight.frame, to: self).intersection(bounds)
    }

    public func editMenuInteraction(
        _ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration
    ) -> CGRect {
        selectionBox
    }

    public func editMenuInteraction(
        _ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard let shown, !shown.selection.isEmpty else { return nil }
        var actions = [
            UIAction(title: "Cut") { [unowned self] _ in onEdit(.cut) },
            UIAction(title: "Copy") { [unowned self] _ in onEdit(.copy) },
        ]
        if UIPasteboard.general.hasStrings {
            actions.append(UIAction(title: "Paste") { [unowned self] _ in onEdit(.paste) })
        }
        if shown.selection.count < shown.text.count {
            actions.append(
                UIAction(title: "Select All") { [unowned self] _ in
                    menuWanted = true
                    onSelect(0..<shown.text.count)
                })
        }
        return UIMenu(children: actions)
    }

    private func drawSelection() {
        guard let shown, let range = textRange(shown.selection) else { return }
        let selecting = !shown.selection.isEmpty
        caret.isHidden = selecting || !shown.caret
        highlight.isHidden = !selecting
        handles.forEach { $0.isHidden = !selecting }
        guard selecting else {
            caret.frame = canvas.caretRect(for: range.start)
            return
        }
        let rects = canvas.selectionRects(for: range).filter { !$0.rect.isEmpty }
        let box = rects.reduce(CGRect.null) { $0.union($1.rect) }
        highlight.frame = box
        let mask = CAShapeLayer()
        mask.path = rects.reduce(into: CGMutablePath()) { $0.addRect($1.rect.offsetBy(dx: -box.minX, dy: -box.minY)) }
        highlight.layer.mask = mask
        let start = canvas.caretRect(for: range.start)
        let end = canvas.caretRect(for: range.end)
        handles[0].place(at: start, knobOnTop: true)
        handles[1].place(at: end, knobOnTop: false)
    }

    /// UIKit's rhythm: solid for half a second after each change, then blinking once a second.
    private func blink() {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1, 1, 0, 0, 1]
        animation.keyTimes = [0, 0.5, 0.6, 0.9, 1]
        animation.duration = 1
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        caret.layer.removeAnimation(forKey: "blink")
        caret.layer.add(animation, forKey: "blink")
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { blink() }
    }

    private func showSend(_ visible: Bool, animated: Bool) {
        let change = { [send] in
            send.alpha = visible ? 1 : 0.3
        }
        send.isEnabled = visible
        if animated { UIView.animate(springDuration: 0.3, bounce: 0.2, animations: change) } else { change() }
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if send.frame.insetBy(dx: -4, dy: -8).contains(point) { return send }
        if mic.frame.insetBy(dx: -4, dy: -8).contains(point) { return mic }
        return super.hitTest(point, with: event)
    }

    public func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard touch.view != send, touch.view?.isDescendant(of: mic) != true else { return false }
        if recognizer is UITapGestureRecognizer { taps = touch.tapCount }
        return true
    }

    public override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer, let shown else { return true }
        guard shown.caret else { return false }
        let point = pan.location(in: canvas)
        drag = Self.drag(at: point, near: shown.selection.isEmpty ? [caret.frame] : handles.map(\.frame))
        if drag != nil { return true }
        let velocity = pan.velocity(in: canvas)
        let scrolls = canvas.contentSize.height > canvas.bounds.height
        drag = !scrolls || abs(velocity.x) > abs(velocity.y) ? .caret : nil
        return drag != nil
    }

    private static func drag(at point: CGPoint, near grips: [CGRect]) -> Drag? {
        let reach: CGFloat = 22
        let hits = grips.map { $0.insetBy(dx: -reach, dy: -reach / 2).contains(point) }
        if grips.count == 1 { return hits[0] ? .caret : nil }
        return hits[0] ? .start : hits[1] ? .end : nil
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        onTap()
        guard let shown, !shown.text.isEmpty else { return onSelect(0..<0) }
        let at = offset(at: tap.location(in: canvas))
        menuWanted = taps > 1
        switch taps {
        case 1
        where shown.selection.count > 0 && (shown.selection.lowerBound...shown.selection.upperBound).contains(at):
            showMenu()
        case 1: onSelect(at..<at)
        case 2: onSelect(word(at: tap.location(in: canvas)) ?? at..<at)
        default: onSelect(0..<shown.text.count)
        }
    }

    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        guard let shown, let drag else { return }
        if pan.state == .ended || pan.state == .cancelled {
            self.drag = nil
            menuWanted = drag != .caret
            return setNeedsLayout()
        }
        guard !shown.text.isEmpty else { return }
        let at = offset(at: pan.location(in: canvas))
        let picked =
            switch drag {
            case .caret: at..<at
            case .start: min(at, shown.selection.upperBound - 1)..<shown.selection.upperBound
            case .end: shown.selection.lowerBound..<max(at, shown.selection.lowerBound + 1)
            }
        if picked != shown.selection { onSelect(picked) }
    }

    /// The character offset nearest `point` in the canvas.
    func offset(at point: CGPoint) -> Int {
        guard let shown, let position = canvas.closestPosition(to: point) else { return 0 }
        return shown.text.characters(fromUTF16: canvas.offset(from: canvas.beginningOfDocument, to: position))
    }

    private func word(at point: CGPoint) -> Range<Int>? {
        guard let shown, let position = canvas.closestPosition(to: point) else { return nil }
        let tokenizer = canvas.tokenizer
        let backward = UITextDirection(rawValue: UITextStorageDirection.backward.rawValue)
        let forward = UITextDirection(rawValue: UITextStorageDirection.forward.rawValue)
        guard
            let range = tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: backward)
                ?? tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: forward)
        else { return nil }
        let start = canvas.offset(from: canvas.beginningOfDocument, to: range.start)
        let end = canvas.offset(from: canvas.beginningOfDocument, to: range.end)
        return shown.text.characters(fromUTF16: start)..<shown.text.characters(fromUTF16: end)
    }

    private func textRange(_ selection: Range<Int>) -> UITextRange? {
        guard let shown else { return nil }
        let text = shown.text
        let start = canvas.position(
            from: canvas.beginningOfDocument, offset: text.utf16(fromCharacters: selection.lowerBound))
        let end = canvas.position(
            from: canvas.beginningOfDocument, offset: text.utf16(fromCharacters: selection.upperBound))
        return start.flatMap { start in end.flatMap { canvas.textRange(from: start, to: $0) } }
    }
}

/// The text view that lays the line out; it never edits, since the keys type through the engine.
private final class Canvas: UITextView {
    var onActivate: () -> Void = {}
    /// What the line holds, which VoiceOver reads in place of the placeholder drawn when it's empty.
    var line = ""

    override var accessibilityValue: String? {
        get { line }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        onActivate()
        return true
    }
}

/// A selection's end as iOS draws it: a bar as tall as the line and a round knob above the start or below the end.
private final class Handle: UIView {
    private let bar = UIView()
    private let knob = UIView()
    private static let knobSize: CGFloat = 10

    var color: UIColor = .tintColor {
        didSet { [bar, knob].forEach { $0.backgroundColor = color } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        knob.layer.cornerRadius = Self.knobSize / 2
        bar.layer.cornerRadius = 1
        [bar, knob].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func place(at caret: CGRect, knobOnTop: Bool) {
        let size = Self.knobSize
        frame = CGRect(
            x: caret.midX - size / 2, y: caret.minY - (knobOnTop ? size : 0), width: size, height: caret.height + size)
        bar.frame = CGRect(
            x: (size - caret.width) / 2, y: knobOnTop ? size : 0, width: caret.width, height: caret.height)
        knob.frame = CGRect(x: 0, y: knobOnTop ? 1 : caret.height - 1, width: size, height: size)
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
