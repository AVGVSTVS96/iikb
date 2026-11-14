import KeyboardStore
import UIKit

/// While a newer build is on the install link (`InstallLink`), a notice atop the app each time it comes forward: a tap
/// opens the link to install it, and its close button puts it away until a newer build.
final class UpdateToast: UIView {
    private static var dismissed = 0
    let build: Int

    static func show(in window: UIWindow?) {
        guard InstallLink.page != nil, let window else { return }
        Task {
            guard let build = await InstallLink.newer(), build > dismissed else { return }
            let shown = window.subviews.compactMap { $0 as? UpdateToast }
            guard !shown.contains(where: { $0.build == build }) else { return }
            shown.forEach { $0.removeFromSuperview() }
            UpdateToast(build: build).present(in: window)
        }
    }

    private init(build: Int) {
        self.build = build
        super.init(frame: .zero)
        let glass = UIVisualEffectView(effect: UIGlassEffect())
        glass.cornerConfiguration = .capsule()
        glass.isUserInteractionEnabled = false
        let install = Install()
        install.accessibilityIdentifier = "iikb.update.toast"
        install.accessibilityLabel = "iikb \(build) is ready. Install"
        install.addAction(
            UIAction { [unowned self] _ in
                if let page = InstallLink.page { UIApplication.shared.open(page) }
                dismiss()
            }, for: .touchUpInside)
        let icon = UIImageView(image: UIImage(systemName: "arrow.down.circle.fill"))
        icon.tintColor = .systemBlue
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        let title = UILabel()
        title.text = "iikb \(build) is ready"
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        let action = UILabel()
        action.text = "Install"
        action.font = .systemFont(ofSize: 16, weight: .semibold)
        action.textColor = .systemBlue
        let row = UIStackView(arrangedSubviews: [icon, title, action])
        row.spacing = 10
        row.alignment = .center
        row.setCustomSpacing(16, after: title)
        row.isUserInteractionEnabled = false
        let close = UIButton(type: .system)
        close.setImage(
            UIImage(
                systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
            for: .normal)
        close.tintColor = AppStyle.secondary
        close.accessibilityLabel = "Not Now"
        close.accessibilityIdentifier = "iikb.update.toast.close"
        close.addAction(UIAction { [unowned self] _ in dismiss() }, for: .touchUpInside)
        for view in [glass, install, row, close] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        install.dims = row
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor), glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            install.topAnchor.constraint(equalTo: topAnchor), install.bottomAnchor.constraint(equalTo: bottomAnchor),
            install.leadingAnchor.constraint(equalTo: leadingAnchor),
            install.trailingAnchor.constraint(equalTo: close.leadingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            close.leadingAnchor.constraint(equalTo: row.trailingAnchor, constant: 4),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 30), close.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func present(in window: UIWindow) {
        translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
            centerXAnchor.constraint(equalTo: window.centerXAnchor),
            widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -32),
        ])
        window.layoutIfNeeded()
        transform = CGAffineTransform(translationX: 0, y: -frame.maxY)
        UIView.animate(springDuration: 0.5, bounce: 0.2) { self.transform = .identity }
    }

    private func dismiss() {
        Self.dismissed = build
        UIView.animate(springDuration: 0.35, bounce: 0) {
            self.transform = CGAffineTransform(translationX: 0, y: -self.frame.maxY)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    /// The toast but its close button, one button to VoiceOver, its words dimmed while held.
    private final class Install: UIControl {
        weak var dims: UIView?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityTraits = .button
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isHighlighted: Bool {
            didSet { dims?.alpha = isHighlighted ? 0.5 : 1 }
        }
    }
}
