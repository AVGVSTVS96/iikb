import KeyboardCore
import UIKit

/// A form's field, where the keys fill in one value at a time (KeyboardCore's `Fill`): the value's name, a real
/// `UITextField` with what the keys typed and the value's default as its placeholder, and the button that does what
/// return does. The text field is focused while `caret` is set, so the caret is iOS's own; focus inside a keyboard needs
/// Full Access (`MessageField`), so the owner sets it only then.
public final class FormField: UIView {
    public var onDone: () -> Void = {}
    private let name = UILabel()
    private let input = SearchInput()
    private let done = UIButton(configuration: .filled())
    private var height: CGFloat = 40

    override public init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        name.font = .systemFont(ofSize: 17, weight: .medium)
        input.accessibilityIdentifier = "iikb.form.value"
        input.font = .systemFont(ofSize: 17)
        input.autocorrectionType = .no
        input.spellCheckingType = .no
        input.inputView = UIView(frame: .zero)
        input.inputAssistantItem.leadingBarButtonGroups = []
        input.inputAssistantItem.trailingBarButtonGroups = []
        done.accessibilityIdentifier = "iikb.form.done"
        done.configuration?.cornerStyle = .capsule
        done.addAction(UIAction { [unowned self] _ in onDone() }, for: .touchUpInside)
        [name, input].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        addSubview(done)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show(
        _ label: String, value: String, placeholder: String, button: String, caret: Bool, height: CGFloat,
        theme: KeyboardTheme
    ) {
        self.height = height
        name.text = label
        name.textColor = theme.candidate.ui
        input.text = value
        input.accessibilityLabel = label
        input.attributedPlaceholder = NSAttributedString(
            string: placeholder, attributes: [.foregroundColor: theme.candidate.ui])
        input.textColor = theme.label.ui
        input.tintColor = theme.prominent.ui
        if caret, !input.isFirstResponder {
            input.becomeFirstResponder()
        } else if !caret, input.isFirstResponder {
            input.resignFirstResponder()
        }
        let end = input.endOfDocument
        if caret, input.selectedTextRange?.start != end {
            input.selectedTextRange = input.textRange(from: end, to: end)
        }
        backgroundColor = theme.searchField.ui
        var look = done.configuration ?? .filled()
        look.attributedTitle = AttributedString(
            button, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]))
        look.baseBackgroundColor = theme.prominent.ui
        look.baseForegroundColor = theme.prominentLabel.ui
        look.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        done.configuration = look
        setNeedsLayout()
    }

    override public func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: height) }

    override public func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        let button = ceil(done.sizeThatFits(bounds.size).width)
        done.frame = CGRect(x: bounds.width - button - 4, y: 4, width: button, height: bounds.height - 8)
        let label = min(ceil(name.sizeThatFits(bounds.size).width), bounds.width * 0.4)
        name.frame = CGRect(x: 16, y: 0, width: label, height: bounds.height)
        let start = name.frame.maxX + 10
        input.frame = CGRect(x: start, y: 0, width: max(done.frame.minX - 10 - start, 0), height: bounds.height)
    }
}
