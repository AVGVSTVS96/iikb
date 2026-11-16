import KeyboardCore
import KeyboardUI
import UIKit

/// A snippet's or quicklink's arguments, or a new snippet's name, keyword and tag, asked for one at a time
/// (`TypingEngine.fill`, docs/design.md, "Snippets and Quicklinks"): a chip for each field over what will go in as they
/// stand, or what keeps them from finishing, and under them the field the keys type into, with Next, or Insert, Open or
/// Save on the last.
final class FormPanel: UIView, PanelContent {
    var fill: () -> Fill? = { nil }
    var onField: (Int) -> Void = { _ in }
    var onNext: () -> Void = {}
    /// Whether the field may show iOS's caret, which needs Full Access.
    var focuses: () -> Bool = { false }
    var field: PanelField { .own(input) }

    private let input = FormField()
    private let chips = UIScrollView()
    private var titleButton: UIButton?
    private var buttons: [UIButton] = []
    private let preview = UILabel()
    private var shown: Shown?

    private struct Shown: Equatable {
        var fill: Fill
        var compact: Bool
        var theme: KeyboardTheme
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        chips.showsHorizontalScrollIndicator = false
        chips.alwaysBounceHorizontal = true
        preview.numberOfLines = 0
        preview.lineBreakMode = .byTruncatingTail
        preview.accessibilityIdentifier = "iikb.form.preview"
        input.onDone = { [unowned self] in onNext() }
        [chips, preview].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() { shown = nil }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        guard let fill = fill() else { return }
        let field = fill.fields[fill.at]
        let button =
            switch (fill.isLast, fill.goal) {
            case (false, _): "Next"
            case (true, .type): "Insert"
            case (true, .open): "Open"
            case (true, .keep): "Save"
            }
        input.show(
            field.name, value: query, placeholder: field.defaultValue, button: button, caret: focuses(),
            height: CGFloat(metrics.toolbar.field), theme: theme)
        let next = Shown(fill: fill, compact: metrics.toolbar.isCompact, theme: theme)
        guard next != shown else { return }
        if fill.fields != shown?.fill.fields || fill.title != shown?.fill.title { makeChips(fill) }
        shown = next
        for (index, button) in buttons.enumerated() {
            var look = button.configuration ?? .filled()
            let on = index == fill.at
            look.baseBackgroundColor = on ? theme.prominent.ui : theme.candidatePill.ui
            look.baseForegroundColor = on ? theme.prominentLabel.ui : theme.label.ui
            button.configuration = look
        }
        let text = fill.problem ?? fill.preview.text
        preview.attributedText = NSAttributedString(
            string: text.isEmpty ? " " : text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: fill.problem == nil ? theme.candidate.ui : theme.record.ui,
            ])
        preview.isHidden = next.compact && fill.problem == nil
        chips.isHidden = next.compact && fill.problem != nil
        setNeedsLayout()
    }

    /// The fill's title, then a chip for each field, which jumps to it.
    private func makeChips(_ fill: Fill) {
        buttons.forEach { $0.removeFromSuperview() }
        let title = UIButton(configuration: .plain())
        title.configuration?.attributedTitle = AttributedString(
            fill.title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]))
        title.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 6)
        title.isUserInteractionEnabled = false
        buttons = fill.fields.enumerated().map { index, field in
            var look = UIButton.Configuration.filled()
            look.cornerStyle = .capsule
            look.attributedTitle = AttributedString(
                field.name, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .medium)]))
            look.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
            let button = UIButton(configuration: look)
            button.accessibilityIdentifier = "iikb.form.field.\(index)"
            button.addAction(UIAction { [unowned self] _ in onField(index) }, for: .touchUpInside)
            return button
        }
        titleButton?.removeFromSuperview()
        titleButton = title
        ([title] + buttons).forEach(chips.addSubview)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let row: CGFloat = 32
        let compact = shown?.compact == true
        if compact, !preview.isHidden {
            preview.frame = bounds.insetBy(dx: 4, dy: 0)
            return
        }
        chips.frame = CGRect(
            x: 0, y: compact ? (bounds.height - row) / 2 : 4, width: bounds.width, height: row)
        titleButton?.configuration?.baseForegroundColor = shown?.theme.label.ui
        var x: CGFloat = 0
        for view in ([titleButton].compactMap { $0 } + buttons) {
            let width = ceil(view.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: row)).width)
            view.frame = CGRect(x: x, y: 0, width: width, height: row)
            x += width + 6
        }
        chips.contentSize = CGSize(width: max(x - 6, 0), height: row)
        if let at = shown?.fill.at, buttons.indices.contains(at) {
            chips.scrollRectToVisible(buttons[at].frame.insetBy(dx: -12, dy: 0), animated: false)
        }
        let top = chips.frame.maxY + 10
        preview.frame = CGRect(x: 4, y: top, width: bounds.width - 8, height: max(bounds.height - top, 0))
    }
}
