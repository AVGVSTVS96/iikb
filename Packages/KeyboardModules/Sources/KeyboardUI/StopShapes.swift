import UIKit

/// Drain's liquid: the capsule from its left end `left` to the mic's circle, its tail thinned to `neck` of the
/// capsule's height, as if pulled into the mic through a straw. At `neck` 1 it's the capsule itself. One outline, the
/// mic's round end its head, so no part of it cancels another out.
func liquid(left: CGFloat, mic: CGRect, neck: CGFloat) -> CGPath {
    let radius = mic.height / 2
    let middle = mic.midY
    let head = mic.minX
    let tail = max(head - left, 0)
    let thin = radius * neck
    let path = UIBezierPath()
    path.move(to: CGPoint(x: head + radius, y: mic.minY))
    path.addCurve(
        to: CGPoint(x: left + thin, y: middle - thin),
        controlPoint1: CGPoint(x: head - tail * 0.25, y: mic.minY),
        controlPoint2: CGPoint(x: head - tail * 0.45, y: middle - thin)
    )
    path.addArc(
        withCenter: CGPoint(x: left + thin, y: middle), radius: thin, startAngle: -.pi / 2, endAngle: .pi / 2,
        clockwise: false)
    path.addCurve(
        to: CGPoint(x: head + radius, y: mic.maxY),
        controlPoint1: CGPoint(x: head - tail * 0.45, y: middle + thin),
        controlPoint2: CGPoint(x: head - tail * 0.25, y: mic.maxY)
    )
    path.addArc(
        withCenter: CGPoint(x: head + radius, y: middle), radius: radius, startAngle: .pi / 2, endAngle: -.pi / 2,
        clockwise: false)
    path.close()
    return path.cgPath
}

/// Drain's red in the Record Key, run down to `level` of its height: its surface dips in the middle, as water does over
/// a drain.
func sinking(_ bounds: CGRect, level: CGFloat) -> CGPath {
    let dip = bounds.height * 0.16
    let top = bounds.minY - dip + (bounds.height + dip) * level
    let path = UIBezierPath()
    path.move(to: CGPoint(x: bounds.minX, y: top))
    path.addQuadCurve(to: CGPoint(x: bounds.maxX, y: top), controlPoint: CGPoint(x: bounds.midX, y: top + 2 * dip))
    path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY + 2 * dip))
    path.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY + 2 * dip))
    path.close()
    return path.cgPath
}

/// A view drawn by one shape, so a stop animation's red is a view the bar can take away like any other.
final class ShapeView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }
    var shape: CAShapeLayer { layer as! CAShapeLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// A ripple out from `path`'s edge, in `color`, gone once it's spread.
func ripple(_ path: CGPath, in frame: CGRect, color: UIColor, on view: UIView) {
    let ring = ShapeView(frame: frame)
    ring.shape.path = path
    ring.shape.fillColor = nil
    ring.shape.strokeColor = color.cgColor
    ring.shape.lineWidth = 2
    ring.alpha = 0.6
    view.addSubview(ring)
    UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
        ring.transform = CGAffineTransform(scaleX: 1 + 12 / max(frame.width, 1), y: 1 + 12 / max(frame.height, 1))
        ring.alpha = 0
    } completion: { _ in
        ring.removeFromSuperview()
    }
}

/// Card's card: the recording's length and a little waveform, in a pill, `inset` in from its leading end, where the
/// waveform's time was, so the time holds still as the recording folds around it.
final class StopCard: UIView {
    static let inset: CGFloat = 12
    private let row: UIStackView

    init(length: String, tint: UIColor) {
        let time = UILabel()
        time.text = length
        time.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        time.textColor = tint.withAlphaComponent(0.9)
        let wave = UIImageView(
            image: UIImage(
                systemName: "waveform", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            ))
        wave.tintColor = tint.withAlphaComponent(0.85)
        row = UIStackView(arrangedSubviews: [time, wave])
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// As wide as its length and waveform with the inset at both ends.
    var fittingWidth: CGFloat {
        ceil(row.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width) + 2 * Self.inset
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
