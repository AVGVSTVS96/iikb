import KeyboardCore
import UIKit

final class PasteOffer: UIControl {
    private let title = UILabel()
    private let subtitle = UILabel()
    private let pill = UIView()
    private var theme = KeyboardTheme.lightCurrent

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "iikb.paste"
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        pill.isUserInteractionEnabled = false
        pill.isHidden = true
        title.font = .systemFont(ofSize: 17)
        title.textAlignment = .center
        title.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textAlignment = .center
        subtitle.text = "Paste"
        [pill, title, subtitle].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { pill.isHidden = !isHighlighted }
    }

    func configure(_ copied: Copied, theme: KeyboardTheme) {
        self.theme = theme
        let text = copied.text.map { $0.split(whereSeparator: \.isNewline).joined(separator: " ") }
        title.text = text?.trimmingCharacters(in: .whitespaces)
        title.isHidden = text == nil
        subtitle.font = .systemFont(ofSize: text == nil ? 17 : 13)
        title.textColor = theme.label.ui
        subtitle.textColor = text == nil ? theme.label.ui : theme.candidate.ui
        pill.backgroundColor = theme.candidatePill.ui
        accessibilityLabel = title.text.map { "Paste \($0.prefix(100))" } ?? "Paste"
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        pill.frame = bounds.insetBy(dx: 8 / 3, dy: 2)
        pill.layer.cornerRadius = pill.bounds.height / 2
        let inset = bounds.insetBy(dx: 12, dy: 0)
        guard !title.isHidden, let top = title.font, let bottom = subtitle.font else {
            subtitle.frame = inset
            return
        }
        let height = top.lineHeight + bottom.lineHeight
        let y = ((bounds.height - height) / 2).rounded(scale: scale)
        title.frame = CGRect(x: inset.minX, y: y, width: inset.width, height: top.lineHeight)
        subtitle.frame = CGRect(x: inset.minX, y: title.frame.maxY, width: inset.width, height: bottom.lineHeight)
    }
}
