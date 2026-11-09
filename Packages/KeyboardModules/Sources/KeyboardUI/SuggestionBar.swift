import KeyboardCore
import UIKit

/// Apple's three suggestions with the word's emoji (as many as fit, and the rest a swipe left away), a round mic at the
/// right end that starts and stops dictation, and the tools at the left end, all placed on the top row's keys by
/// `BarLayout`. While the app listens, the mic grows into a red capsule over the suggestions holding the time so far and
/// the waveform of your voice, and lets out a cancel button before it. Once you stop, dictations still waiting for the
/// model stack as cards in its place. While the menu is out (the More button), cut, copy and paste stand over the
/// suggestions as labeled pills, grown out of the More button.
public final class SuggestionBar: UIView {
    public enum Edit: CaseIterable, Sendable {
        case cut, copy, paste
    }

    /// Which edits can be done now: cut and copy with a selection, paste with text on the clipboard.
    public struct Edits: Equatable, Sendable {
        public var cut, copy, paste: Bool

        public init(cut: Bool, copy: Bool, paste: Bool) {
            self.cut = cut
            self.copy = copy
            self.paste = paste
        }

        func allows(_ edit: Edit) -> Bool {
            switch edit {
            case .cut: cut
            case .copy: copy
            case .paste: paste
            }
        }
    }

    public var onSelect: (Suggestion) -> Void = { _ in }
    public var onEmoji: (String) -> Void = { _ in }
    public var onMic: () -> Void = {}
    public var onCancel: () -> Void = {}
    public var onNotice: () -> Void = {}
    public var onTool: (Panel) -> Void = { _ in }
    public var onMore: () -> Void = {}
    public var onEdit: (Edit) -> Void = { _ in }
    /// A chat's pill was tapped, by its index.
    public var onChat: (Int) -> Void = { _ in }
    /// How the recording goes back into the mic when you stop (Settings › Appearance).
    public var stopAnimation = StopAnimation.squeeze { didSet { mic.stopAnimation = stopAnimation } }
    public var maximumSlotWidth = CGFloat.infinity { didSet { setNeedsLayout() } }
    /// The top row's keys, left to right, as their edges.
    public var keys: [(minX: Double, maxX: Double)] = [] {
        didSet { if !keys.elementsEqual(oldValue, by: ==) { setNeedsLayout() } }
    }
    public var toolbar = KeyboardMetrics.phone(width: 390).toolbar {
        didSet { if toolbar != oldValue { setNeedsLayout() } }
    }
    /// Whether the mic sits at the bar's right, or in the bottom row (Settings › Layout › Record Key), where the bar
    /// has none and the recording runs as the bar's own waveform.
    public var micInBar = true {
        didSet {
            guard micInBar != oldValue else { return }
            mic.isHidden = !micInBar
            waveform.mask = micInBar ? capsule : nil
            setNeedsLayout()
        }
    }

    private let slots = (0..<3).map { SuggestionSlot(index: $0) }
    private let dividers = (0..<2).map { _ in UIView() }
    private var emoji: [EmojiPick] = []
    private let strip = ButtonScrollView()
    /// While a chat is read with the keys down, the chats as pills in the suggestions' place.
    private let chatStrip = ButtonScrollView()
    private var chatPills: [UIButton] = []
    private var chatNames: [String]?
    private var tools: [(panel: Panel, button: BarButton)] = []
    private let more = BarButton("More", draw: Panel.moreGlyph)
    /// The edits while the menu is out, nil while they're tucked into the More button.
    private var edits: Edits?
    /// Something the More button opened is out in the keys' place, the menu or a panel from it.
    private var moreOn = false
    private let editButtons: [(edit: Edit, button: EditPill)] = Edit.allCases.map { edit in
        let button = EditPill(title: edit.title, symbol: edit.symbol)
        button.accessibilityIdentifier = "iikb.edit.\(edit)"
        return (edit, button)
    }
    private let mic = MicButton()
    private let cancel = CancelButton()
    private let waveform = Waveform()
    /// The waveform's mask in the bar: the mic's own shape, moved with it, so the recording shows only inside the red.
    private let capsule = UIView()
    private let stack = PendingStack()
    private let notice = UILabel()
    private var emojiBeside = false
    /// The recording just cancelled, gone to dust, so the mic comes back in its place instead of shrinking out of it.
    private var dissolving = false
    /// How long the recording ran, for Card's card.
    private var heard: Double = 0
    /// Where the recording runs: the mic's capsule, or the waveform's track beside the Record Key.
    private var span = CGRect.zero
    /// What a stop animation laid over the bar, taken away once it's played, or as the next recording starts.
    private var stopping: [UIView] = []
    private var enabled = true
    private var noticed = false
    private var theme = KeyboardTheme.lightCurrent

    override public init(frame: CGRect) {
        super.init(frame: frame)
        for slot in slots {
            slot.addAction(
                UIAction { [unowned self, unowned slot] _ in
                    if let suggestion = slot.suggestion { onSelect(suggestion) }
                }, for: .touchUpInside)
            slot.onHighlight = { [unowned self] in refreshDividers() }
            addSubview(slot)
        }
        dividers.forEach(addSubview)
        for (edit, button) in editButtons {
            button.addAction(UIAction { [unowned self] _ in onEdit(edit) }, for: .touchUpInside)
            addSubview(button)
        }
        more.addAction(UIAction { [unowned self] _ in onMore() }, for: .touchUpInside)
        more.isHidden = true
        more.accessibilityIdentifier = "iikb.more"
        addSubview(more)
        strip.alwaysBounceHorizontal = false
        strip.accessibilityIdentifier = "iikb.suggestion.emoji"
        addSubview(strip)
        chatStrip.accessibilityIdentifier = "iikb.chats"
        chatStrip.fadesEnds = true
        addSubview(chatStrip)
        mic.addAction(UIAction { [unowned self] _ in onMic() }, for: .touchUpInside)
        cancel.addAction(
            UIAction { [unowned self] _ in
                dissolve()
                onCancel()
            }, for: .touchUpInside)
        mic.breathes = true
        capsule.backgroundColor = .black
        capsule.layer.cornerCurve = .continuous
        waveform.mask = capsule
        for view in [stack, cancel, mic, waveform] { addSubview(view) }
        notice.isHidden = true
        notice.font = .systemFont(ofSize: 15)
        notice.textAlignment = .center
        notice.adjustsFontSizeToFitWidth = true
        notice.minimumScaleFactor = 0.7
        notice.lineBreakMode = .byTruncatingTail
        notice.accessibilityIdentifier = "iikb.notice"
        notice.isUserInteractionEnabled = true
        notice.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapNotice)))
        addSubview(notice)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func update(_ suggestions: [Suggestion], emoji: [String], enabled: Bool, theme: KeyboardTheme) {
        self.enabled = enabled
        self.theme = theme
        for (index, slot) in slots.enumerated() {
            slot.configure(suggestions.indices.contains(index) ? suggestions[index] : nil, theme: theme)
        }
        if emoji != self.emoji.map(\.emoji) {
            self.emoji.forEach { $0.removeFromSuperview() }
            self.emoji = emoji.enumerated().map { index, emoji in
                let pick = EmojiPick(emoji: emoji, index: index)
                pick.addAction(UIAction { [unowned self] _ in onEmoji(emoji) }, for: .touchUpInside)
                pick.onHighlight = { [unowned self] in refreshDividers() }
                strip.addSubview(pick)
                return pick
            }
            strip.contentOffset = .zero
            setNeedsLayout()
        }
        self.emoji.forEach { $0.theme = theme }
        dividers.forEach { $0.backgroundColor = theme.candidateDivider.ui }
        more.theme = theme
        refresh()
    }

    /// `notice` (why voice couldn't start, or a source's hint) stands in for the suggestions. Tapping it dismisses it.
    /// `recorded` is how many seconds the app has recorded, for the time beside the waveform; `saved` are the lengths of
    /// the dictations recorded and still to be written, and `waitingFor` what they wait for while the model gets ready.
    public func update(
        mic: MicButton.Phase, recorded: Double, saved: [Double], waitingFor: String?, notice: String?,
        theme: KeyboardTheme
    ) {
        let grows = (mic == .listening) != (self.mic.phase == .listening)
        if (mic == .listening || mic == .writing) != recording { setNeedsLayout() }
        let shown = CGRect(
            x: self.mic.center.x - self.mic.bounds.width / 2, y: self.mic.center.y - self.mic.bounds.height / 2,
            width: self.mic.bounds.width, height: self.mic.bounds.height)
        if mic == .listening { heard = recorded }
        if mic == .listening { cancel.isHidden = false }
        self.mic.show(mic, theme: theme)
        cancel.paint(theme)
        waveform.show(
            mic, recorded: recorded, saved: waitingFor == nil ? 0 : saved.count,
            tint: micInBar ? .white : theme.label.ui)
        stack.show(mic, saved: saved, waitingFor: waitingFor, theme: theme)
        self.notice.text = notice
        self.notice.textColor = theme.candidate.ui
        noticed = notice != nil
        refresh()
        guard grows else { return }
        setNeedsLayout()
        if mic == .listening { endStop() }
        guard window != nil else {
            cancel.isHidden = mic != .listening
            return
        }
        if dissolving, mic != .listening {
            reappear()
            return
        }
        if mic != .listening {
            switch (stopAnimation, micInBar) {
            case (.squeeze, true): waveform.rush(toward: 1)
            case (.squeeze, false): waveform.rush(toward: -1)
            case (.drain, true): return drain(shown, theme: theme)
            case (.drain, false): waveform.sink()
            case (.card, true): return lift(shown, theme: theme)
            case (.card, false): return lift(span, theme: theme)
            }
        }
        morph(
            growing: mic == .listening, { self.layoutIfNeeded() },
            completion: { _ in
                if self.mic.phase != .listening { self.cancel.isHidden = true }
            })
    }

    /// The tools at the bar's left, where there's no pill row for them.
    /// `open` is the panel whose tool shows it's out, besides the clipboard's, whose tray says so.
    public func update(tools panels: [Panel], open: Panel? = nil, theme: KeyboardTheme) {
        if panels != tools.map(\.panel) {
            tools.forEach { $0.button.removeFromSuperview() }
            tools = panels.map { panel in
                let tool = BarButton(panel.title, draw: panel.icon)
                tool.accessibilityIdentifier = "iikb.tool.\(panel)"
                tool.addAction(UIAction { [unowned self] _ in onTool(panel) }, for: .touchUpInside)
                addSubview(tool)
                return (panel, tool)
            }
            setNeedsLayout()
        }
        for (panel, button) in tools {
            button.theme = theme
            if panel != .clipboard { button.isOn = panel == open }
        }
    }

    /// The chats as pills in the suggestions' place, `open` the one shown, or the suggestions back with nil.
    public func update(chats names: [String]?, open: Int?, theme: KeyboardTheme) {
        if names != chatNames {
            chatNames = names
            chatPills.forEach { $0.removeFromSuperview() }
            chatPills = (names ?? []).enumerated().map { index, name in
                let pill = UIButton(configuration: .plain())
                pill.accessibilityIdentifier = "iikb.chat.\(index)"
                pill.layer.cornerCurve = .continuous
                pill.addAction(UIAction { [unowned self] _ in onChat(index) }, for: .touchUpInside)
                chatStrip.addSubview(pill)
                return pill
            }
            setNeedsLayout()
        }
        for (index, pill) in chatPills.enumerated() {
            let on = index == open
            var look = UIButton.Configuration.plain()
            look.attributedTitle = AttributedString(
                chatNames?[index] ?? "",
                attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: on ? .semibold : .medium)])
            )
            look.baseForegroundColor = on ? theme.label.ui : theme.candidate.ui
            look.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 13, bottom: 0, trailing: 13)
            look.titleLineBreakMode = .byTruncatingTail
            pill.configuration = look
            pill.backgroundColor = on ? theme.key.ui : .clear
            pill.layer.shadowColor = theme.shadow.ui.cgColor
            pill.layer.shadowOpacity = on ? 1 : 0
            pill.layer.shadowOffset = CGSize(width: 0, height: 1)
            pill.layer.shadowRadius = 0
            pill.accessibilityTraits = on ? [.button, .selected] : .button
        }
        refresh()
    }

    /// The menu's edits: out of the More button while `edits` says what they can do, tucked back in with nil.
    public func update(edits: Edits?, theme: KeyboardTheme) {
        let moves = (edits == nil) != (self.edits == nil)
        if edits != self.edits { setNeedsLayout() }
        self.edits = edits
        for (edit, button) in editButtons {
            button.theme = theme
            button.isEnabled = edits?.allows(edit) ?? false
        }
        guard moves, window != nil else { return }
        morph(growing: edits != nil) { self.layoutIfNeeded() }
    }

    /// The More button at the far left, before the tools, which opens the menu in the keys' place, and shows `on` while
    /// what it opened is out.
    public func update(more shown: Bool, on: Bool = false) {
        if on != moreOn {
            moreOn = on
            setNeedsLayout()
        }
        guard more.isHidden == shown else { return }
        more.isHidden = !shown
        setNeedsLayout()
    }

    public func hear(_ level: Float, recorded: Double) {
        heard = recorded
        waveform.hear(level, recorded: recorded)
        mic.hear(level)
    }

    /// The cancelled recording, its cancel button and capsule, breaks into dust from the cancel button across, and
    /// the mic comes back in its place once the app has stopped; if it still listens once the dust settles, the recording shows again.
    private func dissolve() {
        let parts: [UIView] = micInBar ? [cancel, mic, waveform] : [cancel, waveform]
        let area = parts.map(\.frame).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -2, dy: -2)
        guard let dust = Dust(of: self, in: area, from: cancel.frame.midX) else { return }
        addSubview(dust)
        parts.forEach { $0.alpha = 0 }
        dissolving = true
        dust.play(away: effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1) { [weak self] in
            guard let self, dissolving, mic.phase == .listening else { return }
            dissolving = false
            parts.forEach { $0.alpha = 1 }
        }
    }

    /// A stop animation's leftovers go, and the mic and waveform are as a recording needs them, whether it finished or a
    /// new recording cut it short.
    private func endStop() {
        stopping.forEach { $0.removeFromSuperview() }
        stopping = []
        mic.layer.removeAllAnimations()
        mic.alpha = 1
        mic.transform = .identity
        waveform.mask = micInBar ? capsule : nil
    }

    /// Drain and Card start from the bar as it is once stopped, the mic hidden in its place until the recording has left.
    /// The cancel button fades where it was rather than tucking behind a capsule that's gone.
    private func settleUnder() {
        endStop()
        if let ghost = cancel.snapshotView(afterScreenUpdates: false) {
            ghost.frame = cancel.frame
            addSubview(ghost)
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                ghost.alpha = 0
                ghost.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            } completion: { _ in
                ghost.removeFromSuperview()
            }
        }
        UIView.performWithoutAnimation { layoutIfNeeded() }
        cancel.isHidden = true
        mic.alpha = 0
    }

    /// Drain: the red pours into the mic, its tail thinning, the bars riding in inside it; then a ripple as it lands
    /// and the mic comes up in its place as the red goes.
    private func drain(_ capsule: CGRect, theme: KeyboardTheme) {
        settleUnder()
        let circle = mic.frame
        let steps = 16
        let paths = (0...steps).map { step -> CGPath in
            let u = CGFloat(step) / CGFloat(steps)
            let along = u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
            let thinning = pow(min(u / 0.65, 1), 3)
            return liquid(
                left: capsule.minX + (circle.minX - capsule.minX) * along, mic: circle, neck: 1 - 0.78 * thinning)
        }
        let red = ShapeView(frame: bounds)
        red.shape.fillColor = theme.record.ui.cgColor
        insertSubview(red, belowSubview: waveform)
        let inside = ShapeView(frame: waveform.bounds)
        var moved = CGAffineTransform(translationX: -waveform.frame.minX, y: -waveform.frame.minY)
        let insidePaths = paths.compactMap { $0.copy(using: &moved) }
        waveform.mask = inside
        waveform.rush(toward: 1, duration: 0.5)
        stopping += [red]
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak red] in
            guard let self, let red, red.superview != nil else { return }
            ripple(
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: circle.size)).cgPath, in: circle,
                color: theme.record.ui, on: self)
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.mic.alpha = 1
                red.alpha = 0
            } completion: { _ in
                self.endStop()
            }
        }
        for (view, keyframes) in [(red, paths), (inside, insidePaths)] {
            let flow = CAKeyframeAnimation(keyPath: "path")
            flow.values = keyframes
            flow.duration = 0.5
            view.shape.path = keyframes[steps]
            view.shape.add(flow, forKey: "flow")
        }
        CATransaction.commit()
    }

    /// Card: the recording folds into a card with its length, beside the mic or where the waveform began beside the Record
    /// Key, its time holding still as the bars give way to a little waveform; then it lifts off the bar as the mic comes
    /// back. In the bar it stays the recording's red; beside the Record Key, whose red is the key's, it's a gray pill.
    private func lift(_ from: CGRect, theme: KeyboardTheme) {
        settleUnder()
        let card = StopCard(length: Waveform.clock(Int(heard)), tint: micInBar ? .white : theme.label.ui)
        card.backgroundColor = micInBar ? theme.record.ui : theme.candidatePill.ui
        let start =
            micInBar
            ? from : CGRect(x: from.minX - StopCard.inset, y: from.minY, width: from.width, height: from.height)
        card.frame = start
        addSubview(card)
        stopping.append(card)
        let width = card.fittingWidth
        let rest = CGRect(
            x: micInBar ? mic.frame.minX - 8 - width : start.minX, y: start.minY, width: width, height: start.height)
        if !micInBar { card.alpha = 0 }
        UIView.animate(springDuration: 0.4, bounce: 0.15) {
            card.frame = rest
            card.alpha = 1
        }
        UIView.animate(withDuration: 0.28, delay: 0.5, options: [.curveEaseIn]) {
            card.transform = CGAffineTransform(translationX: 0, y: -14).scaledBy(x: 1.08, y: 1.08)
            card.alpha = 0
        } completion: { _ in
            card.removeFromSuperview()
        }
        guard micInBar else { return }
        mic.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(springDuration: 0.45, bounce: 0.25, delay: 0.25, options: [.allowUserInteraction]) {
            self.mic.alpha = 1
            self.mic.transform = .identity
        }
    }

    private func reappear() {
        dissolving = false
        UIView.performWithoutAnimation { layoutIfNeeded() }
        cancel.isHidden = true
        let returning: [UIView] = slots + dividers + [strip]
        returning.forEach { $0.alpha = 0 }
        mic.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(springDuration: 0.45, bounce: 0.25, delay: 0.3, options: [.allowUserInteraction]) {
            self.mic.alpha = 1
            self.mic.transform = .identity
        }
        UIView.animate(withDuration: 0.3, delay: 0.35, options: [.curveEaseOut, .allowUserInteraction]) {
            returning.forEach { $0.alpha = 1 }
        }
    }

    /// While you dictate, the cancel button sits in its place, before the recording. Otherwise it waits tucked at half
    /// its size behind the mic, so as the mic grows it comes out from under the capsule's leading edge and rides out to
    /// its place on the same spring, and tucks back in as the capsule shrinks; it's hidden only once it's behind. Where
    /// the mic is the Record Key, it fades in and out in its place.
    private func placeCancel(_ place: CGRect, behind mic: CGRect?) {
        let listening = self.mic.phase == .listening
        let tucked = listening ? nil : mic
        cancel.bounds.size = place.size
        cancel.center = CGPoint(x: (tucked ?? place).midX, y: (tucked ?? place).midY)
        let scale: CGFloat = listening ? 1 : mic == nil ? 0.9 : 0.5
        cancel.transform = CGAffineTransform(scaleX: scale, y: scale)
        cancel.alpha = listening || mic != nil ? 1 : 0
    }

    /// Out, the edits share the bar between the last tool and the mic; tucked, they shrink into the More button. The
    /// suggestions fade under them.
    private func placeEdits(end: CGFloat) {
        let anchor = more.frame
        let out = edits != nil && !more.isHidden
        more.isOn = out || moreOn
        let gap: CGFloat = 8
        let start = (tools.last?.button.frame ?? anchor).maxX + gap
        let width = max((end - start - gap * CGFloat(editButtons.count - 1)) / CGFloat(editButtons.count), 0)
        let height = min(toolbar.bar - 4, toolbar.button + 8)
        for (index, (_, button)) in editButtons.enumerated() {
            let place = CGRect(
                x: start + CGFloat(index) * (width + gap), y: toolbar.top + (toolbar.bar - height) / 2, width: width,
                height: height)
            button.isHidden = more.isHidden
            button.transform = .identity
            button.bounds.size = place.size
            button.center = out ? CGPoint(x: place.midX, y: place.midY) : CGPoint(x: anchor.midX, y: anchor.midY)
            button.transform = out ? .identity : CGAffineTransform(scaleX: 0.2, y: 0.2)
            button.alpha = out ? 1 : 0
            button.isUserInteractionEnabled = out
        }
        let under: CGFloat = out ? 0 : 1
        (slots + dividers + [strip, notice, stack] as [UIView]).forEach { $0.alpha = under }
    }

    @objc private func tapNotice() {
        onNotice()
    }

    private var recording: Bool { mic.phase == .listening || mic.phase == .writing }

    private func refresh() {
        let quiet = !enabled || noticed || recording
        notice.isHidden = !noticed || recording
        cancel.shows = mic.phase == .listening
        let chatting = chatNames != nil
        chatStrip.isHidden = !chatting
        slots.forEach { $0.isHidden = quiet || chatting }
        strip.isHidden = quiet || chatting || emoji.isEmpty
        emoji.forEach { $0.isHidden = quiet }
        if !emoji.isEmpty, !emojiBeside { slots[slots.count - 1].isHidden = true }
        refreshDividers()
    }

    /// A divider shows only between two things shown without a pill.
    private func refreshDividers() {
        func hidesDivider(_ index: Int, leading: Bool) -> Bool {
            if index == slots.count - 1, !emojiBeside, let pick = leading ? emoji.first : emoji.last {
                return pick.isHidden || pick.isHighlighted
            }
            return slots[index].isHidden || slots[index].showsPill
        }
        for (index, divider) in dividers.enumerated() {
            divider.isHidden = hidesDivider(index, leading: false) || hidesDivider(index + 1, leading: true)
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        guard !keys.isEmpty else { return }
        let layout = BarLayout(
            toolbar, keys: keys, tools: tools.count, more: !more.isHidden, mic: micInBar, maximumSlot: maximumSlotWidth)
        let micPlace = CGRect(mic.phase == .listening ? layout.recording : layout.mic ?? layout.recording)
        mic.bounds.size = micPlace.size
        mic.center = CGPoint(x: micPlace.midX, y: micPlace.midY)
        placeCancel(CGRect(layout.cancel), behind: layout.mic.map { CGRect($0) })
        let around = (layout.pitch - toolbar.button) / 2
        let reach = UIEdgeInsets(
            top: -(toolbar.top + (toolbar.bar - toolbar.button) / 2), left: -around,
            bottom: -(toolbar.bar - toolbar.button) / 2, right: -around
        )
        for (tool, frame) in zip(tools, layout.tools) {
            tool.button.place(CGRect(frame), glyph: toolbar.glyph, reach: reach)
        }
        if let frame = layout.more { more.place(CGRect(frame), glyph: toolbar.glyph, reach: reach) }
        let edge = CGFloat(layout.mic.map { $0.x - BarLayout.gap } ?? layout.maxX)
        placeEdits(end: recording ? min(edge, CGRect(layout.cancel).minX - 8) : edge)
        for (slot, frame) in zip(slots, layout.slots) {
            let minX = CGFloat(frame.x).rounded(scale: scale)
            let maxX = CGFloat(frame.x + frame.width).rounded(scale: scale)
            slot.frame = CGRect(x: minX, y: frame.y, width: maxX - minX, height: frame.height)
        }
        if layout.emojiBeside != emojiBeside {
            emojiBeside = layout.emojiBeside
            refresh()
        }
        let place = CGRect(layout.emoji)
        strip.frame = place
        let pitch = BarLayout.emojiPitch
        let total = pitch * CGFloat(emoji.count)
        let left = max((place.width - total) / 2, 0)
        for (index, pick) in emoji.enumerated() {
            let minX = (left + CGFloat(index) * pitch).rounded(scale: scale)
            let glyph = CGRect(
                x: minX, y: 0, width: (left + CGFloat(index + 1) * pitch).rounded(scale: scale) - minX,
                height: place.height)
            let frameMinX = index == 0 ? 0 : glyph.minX
            let frameMaxX = index == emoji.count - 1 ? max(place.width, glyph.maxX) : glyph.maxX
            pick.frame = CGRect(x: frameMinX, y: 0, width: frameMaxX - frameMinX, height: place.height)
            pick.glyph = glyph.offsetBy(dx: -pick.frame.minX, dy: 0)
        }
        strip.contentSize = CGSize(width: max(total, place.width), height: place.height)
        let row = CGRect(x: layout.minX, y: toolbar.top, width: layout.maxX - layout.minX, height: toolbar.bar)
        chatStrip.frame =
            recording
            ? CGRect(
                x: row.minX, y: row.minY, width: max(CGRect(layout.cancel).minX - 8 - row.minX, 0), height: row.height)
            : row
        var x = 0.0
        for pill in chatPills {
            let width = min(ceil(pill.sizeThatFits(CGSize(width: 200, height: 30)).width), 200)
            pill.frame = CGRect(x: x, y: (row.height - 30) / 2, width: width, height: 30)
            pill.layer.cornerRadius = 15
            x += width + 4
        }
        chatStrip.contentSize = CGSize(width: max(x - 4, 0), height: row.height)
        for (index, divider) in dividers.enumerated() {
            divider.frame = CGRect(x: slots[index].frame.maxX - 0.5, y: row.midY - 14, width: 1, height: 28)
        }
        span = CGRect(layout.recording)
        if micInBar {
            waveform.frame = span
            waveform.insets = (leading: 12, trailing: span.height)
            capsule.frame = micPlace.offsetBy(dx: -span.minX, dy: -span.minY)
            capsule.layer.cornerRadius = micPlace.height / 2
        } else {
            waveform.frame = CGRect(x: span.minX, y: row.minY, width: span.width, height: row.height)
            waveform.insets = (leading: 0, trailing: 0)
        }
        let waits = layout.mic.map { CGFloat($0.x) - 6 } ?? span.maxX
        stack.frame = CGRect(x: span.minX, y: row.minY, width: max(waits - span.minX, 0), height: row.height)
        notice.frame = row.insetBy(dx: 4, dy: 0)
    }
}

/// One emoji in the bar's last slot: a tap types it in place of the word. The outer ones also take the slot's
/// margins, so the whole slot answers a tap.
private final class EmojiPick: UIControl {
    let emoji: String
    var glyph = CGRect.zero { didSet { setNeedsLayout() } }
    var onHighlight: () -> Void = {}
    var theme = KeyboardTheme.lightCurrent { didSet { pill.backgroundColor = theme.candidatePill.ui } }
    private let label = UILabel()
    private let pill = UIView()

    init(emoji: String, index: Int) {
        self.emoji = emoji
        super.init(frame: .zero)
        accessibilityIdentifier = "iikb.suggestion.emoji.\(index)"
        accessibilityLabel = emoji
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        pill.isUserInteractionEnabled = false
        pill.isHidden = true
        label.text = emoji
        label.font = .systemFont(ofSize: 24)
        label.textAlignment = .center
        addSubview(pill)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            pill.isHidden = !isHighlighted
            onHighlight()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pill.frame = glyph.insetBy(dx: 8 / 3, dy: 2)
        pill.layer.cornerRadius = min(pill.bounds.width, pill.bounds.height) / 2
        label.frame = glyph
    }
}

/// A suggestion: the middle one, which a space would type, in the label color and medium weight, the others in the
/// secondary color.
private final class SuggestionSlot: UIControl {
    private(set) var suggestion: Suggestion?
    var onHighlight: () -> Void = {}
    private let index: Int
    private let label = UILabel()
    private let pill = UIView()
    private var theme = KeyboardTheme.lightCurrent

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        accessibilityIdentifier = "iikb.suggestion.\(index)"
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        pill.isUserInteractionEnabled = false
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 17, weight: index == 1 ? .medium : .regular)
        addSubview(pill)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Apple's pills stop 8px (@3x) short of each slot's edge, so neighbors sit 16px apart and the outer ones keep
    /// clear of the keyboard's edge (iOS 27 simulator, held suggestions).
    private static let pillInset: CGFloat = 8 / 3

    var showsPill: Bool { suggestion != nil && (suggestion?.kind == .correction || isHighlighted) }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            refresh()
            onHighlight()
        }
    }

    func configure(_ suggestion: Suggestion?, theme: KeyboardTheme) {
        self.suggestion = suggestion
        self.theme = theme
        label.text = suggestion?.title
        accessibilityLabel = suggestion?.text
        refresh()
        setNeedsLayout()
    }

    private func refresh() {
        pill.isHidden = !showsPill
        pill.backgroundColor = theme.candidatePill.ui
        label.textColor = showsPill ? theme.candidateHighlighted.ui : index == 1 ? theme.label.ui : theme.candidate.ui
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pill.frame = bounds.insetBy(dx: Self.pillInset, dy: 2)
        pill.layer.cornerRadius = pill.bounds.height / 2
        guard let font = label.font else { return }
        let baseline = (bounds.midY + font.capHeight / 2).rounded(scale: traitCollection.displayScale)
        let width = min(label.intrinsicContentSize.width, bounds.width - 8)
        label.frame = CGRect(
            x: (bounds.width - width) / 2, y: baseline - font.ascender, width: width, height: font.lineHeight)
    }
}

extension SuggestionBar.Edit {
    var title: String {
        switch self {
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste: "Paste"
        }
    }

    var symbol: String {
        switch self {
        case .cut: "scissors"
        case .copy: "square.on.square"
        case .paste: "doc.on.clipboard"
        }
    }
}
