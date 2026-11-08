import KeyboardUI
import UIKit

/// The dictation going on, in the tab bar's accessory, where Music shows what's playing: while you talk, the
/// keyboard's own recording (cancel, then the red capsule with the time and the waveform, which stops when tapped);
/// while it's written down, what the model is doing; and why it couldn't listen or write. `Tabs` shows it only while
/// `Listener.shown` has something, so it goes by itself once a dictation is typed.
final class DictationBar: UIView {
    enum State: Equatable {
        case listening
        /// What the dictation waits for, as `VoiceModel.waiting` says, nil while the model writes.
        case writing(waiting: String?)
        case failed(title: String, reason: String)
    }

    private let cancel = UIButton(configuration: .plain())
    private let capsule = UIButton(configuration: .prominentGlass())
    private let waveform = Waveform()
    private let stop = UIImageView(image: UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let warning = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
    private let title = UILabel()
    private let detail = UILabel()
    private let close = UIButton(configuration: .plain())
    private var state: State?
    private var recorded: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        cancel.configuration?.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        cancel.configuration?.baseForegroundColor = .label
        cancel.configuration?.background.backgroundColor = .tertiarySystemFill
        cancel.configuration?.cornerStyle = .capsule
        cancel.accessibilityLabel = "Cancel Dictation"
        cancel.addAction(UIAction { _ in Listener.shared.cancel() }, for: .touchUpInside)

        capsule.tintColor = .systemRed
        capsule.accessibilityLabel = "Stop Dictating"
        capsule.accessibilityIdentifier = "iikb.app.stop"
        capsule.addAction(UIAction { _ in Task { await Listener.shared.finish() } }, for: .touchUpInside)
        stop.tintColor = .white
        stop.contentMode = .center
        for view in [waveform, stop] as [UIView] {
            view.isUserInteractionEnabled = false
            capsule.addSubview(view)
        }

        spinner.hidesWhenStopped = false
        spinner.color = .secondaryLabel
        warning.tintColor = .systemOrange
        warning.contentMode = .center
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.adjustsFontForContentSizeCategory = false
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = AppStyle.secondary
        detail.lineBreakMode = .byTruncatingTail
        close.configuration?.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        close.configuration?.baseForegroundColor = AppStyle.secondary
        close.accessibilityLabel = "Dismiss"
        close.addAction(UIAction { _ in Listener.shared.dismissFailure() }, for: .touchUpInside)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(explain)))

        for view in [cancel, capsule, spinner, warning, title, detail, close] as [UIView] { addSubview(view) }
        accessibilityIdentifier = "iikb.app.dictation"
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ state: State) {
        let was = self.state
        guard state != was else { return }
        self.state = state
        let listening = state == .listening
        if listening != (was == .listening) {
            if listening { recorded = 0 }
            waveform.show(listening ? .listening : .writing, recorded: recorded, saved: 0, tint: .white)
        }
        switch state {
        case .listening:
            title.text = nil
            detail.text = nil
        case .writing(let waiting):
            title.text = "Writing it down"
            detail.text = waiting
            spinner.startAnimating()
        case .failed(let failed, _):
            title.text = failed
            detail.text = "Tap to see why"
        }
        let shown: [UIView] = switch state {
        case .listening: [cancel, capsule]
        case .writing: [spinner, title, detail]
        case .failed: [warning, title, detail, close]
        }
        for view in [cancel, capsule, spinner, warning, title, detail, close] as [UIView] { view.isHidden = !shown.contains(view) }
        if case .writing = state {} else { spinner.stopAnimating() }
        setNeedsLayout()
    }

    func hear(_ level: Float, recorded: Double) {
        self.recorded = recorded
        waveform.hear(level, recorded: recorded)
    }

    /// Why it failed, which the bar has no room for.
    @objc private func explain() {
        guard case .failed(let failed, let reason) = state, let root = window?.rootViewController else { return }
        let alert = UIAlertController(title: failed, message: reason, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { _ in Listener.shared.dismissFailure() })
        root.present(alert, animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height, inset: CGFloat = 6
        let button = min(height - 2 * inset, 36)
        let middle = (height - button) / 2
        let width = min(bounds.width - 2 * inset, 400), left = ((bounds.width - width) / 2).rounded()
        cancel.frame = CGRect(x: left, y: middle, width: button, height: button)
        capsule.frame = CGRect(x: cancel.frame.maxX + 8, y: middle, width: width - button - 8, height: button)
        waveform.frame = capsule.bounds
        waveform.insets = (14, 38)
        stop.frame = CGRect(x: capsule.bounds.width - 30, y: 0, width: 16, height: button)

        let lead = left + 10, glyph: CGFloat = 24
        spinner.frame = CGRect(x: lead, y: (height - glyph) / 2, width: glyph, height: glyph)
        warning.frame = spinner.frame
        close.frame = CGRect(x: left + width - 38, y: (height - 44) / 2, width: 44, height: 44)
        let text = lead + glyph + 10
        let end = close.isHidden ? left + width - 10 : close.frame.minX
        let lines = detail.text?.isEmpty == false
        let titleHeight = title.font.lineHeight.rounded(.up), detailHeight = detail.font.lineHeight.rounded(.up)
        let top = ((height - titleHeight - (lines ? detailHeight + 1 : 0)) / 2).rounded()
        title.frame = CGRect(x: text, y: top, width: end - text, height: titleHeight)
        detail.frame = CGRect(x: text, y: title.frame.maxY + 1, width: end - text, height: detailHeight)
    }
}
