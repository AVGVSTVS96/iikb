import KeyboardCore
import UIKit

/// The bar's mic: a round button of iOS's Liquid Glass, tinted white on dark and black on light, with a green dot while
/// the app keeps the microphone on. While it listens it turns record red and grows into a capsule over the suggestions, which holds the
/// recording, with a white stop where the mic was and a soft red halo that swells as you talk; while the
/// app writes a dictation down a spinner, or what its `stopAnimation` shows, takes the glyph's place, and a tap still starts the next one. Tap to start or
/// stop; only the app turns the microphone off.
public final class MicButton: UIControl {
    public enum Phase { case off, on, listening, writing }

    /// The face's corner radius, where it takes a key's shape; otherwise round.
    var corner: CGFloat? {
        didSet {
            refresh()
            setNeedsLayout()
        }
    }
    /// Whether a halo swells around it with your voice while it listens: in the bar, never as the Record Key, whose
    /// neighbors sit too close.
    var breathes = false
    /// The stop animation the bar plays, which picks what shows while the app writes: Squeeze's ring and check,
    /// Drain's glow, or the spinner.
    public var stopAnimation = StopAnimation.squeeze
    private(set) var phase = Phase.off
    private let halo = UIView()
    private let face = UIView()
    /// The bar's mic is glass tinted the mic's color, red while it listens, so it sits with the glass around it; the
    /// Record Key keeps a key's solid face.
    private let glass = UIVisualEffectView()
    private var tint: UIColor?
    private let glyph = UIImageView()
    private let stop = UIImageView()
    private let dot = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let ring = UIView()
    private let arc = CAShapeLayer()
    private let check = UIImageView()
    /// The check Squeeze shows once a dictation is written, which holds the glyph back until it's gone.
    private var checking = false
    /// Drain's red running out of the Record Key, in its face's shape.
    private var draining: CALayer?
    private var theme = KeyboardTheme.lightCurrent
    private var glyphSide: CGFloat = 0
    private var voice: CGFloat = 0

    override public init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "iikb.mic"
        isAccessibilityElement = true
        accessibilityTraits = .button
        for view in [halo, face] { view.layer.cornerCurve = .continuous }
        glass.cornerConfiguration = .capsule()
        glass.clipsToBounds = true
        for view in [halo, glass, face, glyph, stop, dot, spinner, ring, check] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        halo.alpha = 0
        stop.alpha = 0
        stop.tintColor = .white
        for view in [glyph, stop] { view.contentMode = .center }
        dot.backgroundColor = UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
        spinner.hidesWhenStopped = false
        spinner.alpha = 0
        arc.fillColor = nil
        arc.lineWidth = 2.5
        arc.lineCap = .round
        arc.strokeEnd = 0.3
        ring.layer.addSublayer(arc)
        ring.alpha = 0
        check.contentMode = .center
        check.alpha = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Pressed, it gives by the same 3 points whatever its width.
    override public var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            let scale = isHighlighted ? 1 - 6 / max(bounds.width, 1) : 1
            UIView.animate(
                springDuration: isHighlighted ? 0.16 : 0.3, bounce: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
    }

    /// Into or out of listening it moves on `morph`, the spring the bar grows it on; otherwise it settles.
    public func show(_ phase: Phase, theme: KeyboardTheme) {
        let old = self.phase
        self.phase = phase
        self.theme = theme
        accessibilityLabel = phase == .listening ? "Stop Dictating" : "Dictate"
        accessibilityValue =
            switch phase {
            case .on: "Mic On"
            case .writing: "Writing"
            case .off, .listening: nil
            }
        if phase != .listening { voice = 0 }
        if phase == .listening {
            draining?.removeFromSuperlayer()
            draining = nil
        }
        if old == .listening, phase != .listening, corner != nil, window != nil { release() }
        if phase == .writing { spinner.startAnimating() }
        spin(phase == .writing && stopAnimation == .squeeze)
        glow(phase == .writing && stopAnimation == .drain)
        if old == .writing, phase == .on || phase == .off, stopAnimation == .squeeze, window != nil { written() }
        let done: (Bool) -> Void = { _ in if self.phase != .writing { self.spinner.stopAnimating() } }
        guard phase != old, window != nil else {
            refresh()
            return done(true)
        }
        if (phase == .listening) != (old == .listening) {
            morph(growing: phase == .listening, { self.refresh() }, completion: done)
        } else {
            settle({ self.refresh() }, completion: done)
        }
    }

    /// The halo swells with your voice, on a softer spring than the bars, so it breathes rather than flickers. As the
    /// Record Key, whose neighbors sit too close for a halo, its stop swells instead.
    public func hear(_ level: Float) {
        guard phase == .listening else { return }
        voice = loudness(level)
        guard breathes else {
            let scale = 1 + 0.4 * voice
            return follow(duration: 0.32) { self.stop.transform = CGAffineTransform(scaleX: scale, y: scale) }
        }
        follow(duration: 0.32) { self.layoutHalo() }
    }

    /// As the Record Key, it answers the bar's stop in its own place: Squeeze squeezes it, Drain lets its red run down out
    /// of it and ripples its edge, and Card lets it give and spring back as the card lifts off the bar.
    private func release() {
        switch stopAnimation {
        case .squeeze: give(x: 0.8, y: 0.9)
        case .drain: sink()
        case .card: give(x: 0.9, y: 0.9)
        }
    }

    private func give(x: CGFloat, y: CGFloat) {
        UIView.animate(
            withDuration: 0.12, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.transform = CGAffineTransform(scaleX: x, y: y)
        } completion: { _ in
            UIView.animate(springDuration: 0.5, bounce: 0.45, options: [.beginFromCurrentState, .allowUserInteraction])
            {
                self.transform = .identity
            }
        }
    }

    /// Drain's red runs down out of the key, its surface dipping as over a drain, then a ripple from its edge.
    private func sink() {
        let clip = CALayer()
        clip.frame = bounds
        clip.cornerRadius = face.layer.cornerRadius
        clip.cornerCurve = .continuous
        clip.masksToBounds = true
        let red = CAShapeLayer()
        red.fillColor = theme.record.ui.cgColor
        clip.addSublayer(red)
        layer.insertSublayer(clip, above: face.layer)
        draining?.removeFromSuperlayer()
        draining = clip
        let steps = 12
        let paths = (0...steps).map { step -> CGPath in
            let u = CGFloat(step) / CGFloat(steps)
            return sinking(bounds, level: u * u)
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak clip] in
            guard let self, let clip, draining === clip else { return }
            clip.removeFromSuperlayer()
            draining = nil
            ripple(
                UIBezierPath(roundedRect: bounds, cornerRadius: face.layer.cornerRadius).cgPath, in: frame,
                color: theme.record.ui, on: superview ?? self)
        }
        let flow = CAKeyframeAnimation(keyPath: "path")
        flow.values = paths
        flow.duration = 0.45
        red.path = paths[steps]
        red.add(flow, forKey: "flow")
        CATransaction.commit()
    }

    /// The glyphs never change color: the mic's waveform shrinks away in its own color as the stop, always white,
    /// grows in its place, so neither flashes against the face while it turns red.
    private func refresh() {
        let listening = phase == .listening
        let idle = phase == .off || phase == .on
        let color = listening ? theme.record.ui : theme.mic.ui
        glass.isHidden = corner != nil
        if corner == nil, color != tint {
            tint = color
            let tinted = UIGlassEffect(style: .regular)
            tinted.tintColor = color.withAlphaComponent(listening ? 1 : 0.85)
            glass.effect = tinted
        }
        face.backgroundColor = corner == nil ? .clear : color
        halo.backgroundColor = theme.record.ui
        halo.alpha = listening && breathes ? 0.2 : 0
        glyph.tintColor = theme.micGlyph.ui
        glyph.alpha = idle && !checking ? 1 : 0
        glyph.transform = idle ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        stop.alpha = listening ? 1 : 0
        stop.transform = listening ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        dot.alpha = phase == .on ? 1 : 0
        dot.transform = phase == .on ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        spinner.color = theme.micGlyph.ui
        spinner.alpha = phase == .writing && stopAnimation != .squeeze ? 1 : 0
        arc.strokeColor = theme.micGlyph.ui.cgColor
        check.tintColor = theme.micGlyph.ui
        ring.alpha = phase == .writing && stopAnimation == .squeeze ? 1 : 0
        spinner.transform = CGAffineTransform(scaleX: phase == .writing ? 0.75 : 0.5, y: phase == .writing ? 0.75 : 0.5)
        layoutHalo()
    }

    /// Squeeze's ring turns around the mic while it writes.
    private func spin(_ on: Bool) {
        guard on != (arc.animation(forKey: "spin") != nil) else { return }
        guard on else { return arc.removeAnimation(forKey: "spin") }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 2 * CGFloat.pi
        turn.duration = 0.9
        turn.repeatCount = .infinity
        arc.add(turn, forKey: "spin")
    }

    /// Drain's mic glows softly in and out while it writes.
    private func glow(_ on: Bool) {
        guard on != (face.layer.animation(forKey: "glow") != nil) else { return }
        guard on else {
            face.layer.removeAnimation(forKey: "glow")
            face.layer.shadowOpacity = 0
            return
        }
        face.layer.shadowColor = theme.mic.ui.cgColor
        face.layer.shadowPath = UIBezierPath(roundedRect: face.bounds, cornerRadius: face.layer.cornerRadius).cgPath
        face.layer.shadowOffset = .zero
        face.layer.shadowRadius = 10
        let pulse = CABasicAnimation(keyPath: "shadowOpacity")
        pulse.fromValue = 0.25
        pulse.toValue = 0.9
        pulse.duration = 0.55
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        face.layer.add(pulse, forKey: "glow")
    }

    /// Squeeze's check, once a dictation is written, before the mic's own glyph comes back.
    private func written() {
        checking = true
        glyph.alpha = 0
        check.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(springDuration: 0.3, bounce: 0.3) {
            self.check.alpha = 1
            self.check.transform = .identity
        }
        UIView.animate(withDuration: 0.2, delay: 0.5, options: [.curveEaseIn, .allowUserInteraction]) {
            self.check.alpha = 0
            self.check.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        } completion: { _ in
            self.checking = false
            settle { self.refresh() }
        }
    }

    /// The glyphs in proportion with the circle (the waveform 15 points in a 28 one, the stop 12), and no bigger than 17
    /// and 13 in the Record Key's key.
    private static func symbol(_ name: String, side: CGFloat, ratio: CGFloat, largest: CGFloat) -> UIImage? {
        UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: min((side * ratio).rounded(), largest), weight: .semibold))
    }

    /// The circle is smaller than a fingertip; taps a little around it still reach it.
    override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    /// The glyphs, spinner and dot sit in the square at the right end of the capsule, or in the middle of a circle or key,
    /// however wide the key is.
    override public func layoutSubviews() {
        super.layoutSubviews()
        face.frame = bounds
        glass.frame = bounds
        face.layer.cornerRadius = corner ?? bounds.height / 2
        let side = min(bounds.width, bounds.height)
        let end = CGRect(
            x: corner == nil && bounds.width > bounds.height * 1.5 ? bounds.width - side : (bounds.width - side) / 2,
            y: (bounds.height - side) / 2, width: side, height: side)
        if glyphSide != side, side > 0 {
            glyphSide = side
            glyph.image = Self.symbol("waveform", side: side, ratio: 0.54, largest: 17)
            stop.image = Self.symbol("stop.fill", side: side, ratio: 0.43, largest: 13)
            check.image = Self.symbol("checkmark", side: side, ratio: 0.43, largest: 13)
        }
        for view in [glyph, stop] {
            view.bounds.size = end.size
            view.center = CGPoint(x: end.midX, y: end.midY)
        }
        spinner.center = CGPoint(x: end.midX, y: end.midY)
        for view in [ring, check] {
            view.bounds.size = end.size
            view.center = CGPoint(x: end.midX, y: end.midY)
        }
        arc.frame = ring.bounds
        arc.path = UIBezierPath(ovalIn: ring.bounds.insetBy(dx: end.width * 0.22, dy: end.width * 0.22)).cgPath
        let dotSide: CGFloat = 6
        dot.bounds = CGRect(x: 0, y: 0, width: dotSide, height: dotSide)
        dot.center = CGPoint(x: end.maxX - dotSide / 2 - end.width * 0.04, y: end.minY + end.width * 0.04 + dotSide / 2)
        dot.layer.cornerRadius = dotSide / 2
        layoutHalo()
    }

    /// The halo hugs the capsule, a point out when you're quiet and four when you're loud.
    private func layoutHalo() {
        let out = phase == .listening ? 1 + 3 * voice : 0
        halo.bounds.size = CGSize(width: bounds.width + 2 * out, height: bounds.height + 2 * out)
        halo.center = CGPoint(x: bounds.midX, y: bounds.midY)
        halo.layer.cornerRadius = (corner ?? bounds.height / 2) + out
    }
}
