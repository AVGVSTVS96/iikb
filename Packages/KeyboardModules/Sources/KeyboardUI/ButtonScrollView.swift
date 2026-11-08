import UIKit

/// A scroll view of buttons that still scrolls when a drag starts on one: UIKit's own never cancels a control's touch,
/// so rows that fill it would never let it move.
package final class ButtonScrollView: UIScrollView {
    override package init(frame: CGRect) {
        super.init(frame: frame)
        delaysContentTouches = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        [topEdgeEffect, bottomEdgeEffect, leftEdgeEffect, rightEdgeEffect].forEach { $0.isHidden = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    override package func touchesShouldCancel(in view: UIView) -> Bool { true }

    /// Whether a row cut by either end fades out there, so the cut-off button reads as more to scroll to.
    package var fadesEnds = false {
        didSet { setNeedsLayout() }
    }
    private lazy var fade: CAGradientLayer = {
        let fade = CAGradientLayer()
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear, .black, .black, .clear].map(\.cgColor)
        return fade
    }()

    override package func layoutSubviews() {
        super.layoutSubviews()
        guard fadesEnds, bounds.width > 0 else {
            layer.mask = nil
            return
        }
        let edge = min(16 / bounds.width, 0.5)
        let before = contentOffset.x > 0.5 ? edge : 0
        let after = contentOffset.x + bounds.width < contentSize.width - 0.5 ? edge : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        fade.locations = [0, before, 1 - after, 1].map { NSNumber(value: $0) }
        CATransaction.commit()
        layer.mask = fade
    }
}
