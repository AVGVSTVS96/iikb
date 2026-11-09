import ImageIO
import UIKit

/// All of a held clip, transcript or GIF, as its context menu's preview: text in full, scrolling where it's long, or the
/// image, a GIF playing.
final class ClipPreview: UIViewController {
    private let text: String?
    private let image: UIImage?
    private let gif: Data?

    private var heading: NSAttributedString?

    private var tallest = 480.0

    /// The preview held to half of `room`, the keyboard window's height, leaving the other half to the one-row menu
    /// under it, which UIKit would otherwise squeeze and scroll.
    func fitting(_ room: CGFloat) -> Self {
        tallest = min(tallest, (room / 2).rounded(.down))
        return self
    }

    /// `heading`, when there is one, is how the clip's row writes it (`ClipTitle`), over all of it: a link's site over
    /// the whole link.
    init(text: String, heading: NSAttributedString? = nil) {
        self.text = text
        self.heading = heading
        image = nil
        gif = nil
        super.init(nibName: nil, bundle: nil)
    }

    init(image: UIImage?, gif: Data? = nil) {
        text = nil
        self.image = image
        self.gif = gif
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        if let text {
            let view = UITextView()
            view.font = .systemFont(ofSize: 17)
            view.isEditable = false
            view.isSelectable = false
            view.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
            view.backgroundColor = .secondarySystemBackground
            self.view = view
            show(text)
            return
        }
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        let size = image?.size ?? CGSize(width: 1, height: 1)
        let height = min((300 * size.height / max(size.width, 1)).rounded(), tallest)
        preferredContentSize = CGSize(width: (height * size.width / max(size.height, 1)).rounded(), height: height)
        self.view = view
    }

    private var playing = false

    /// The text in place of what it showed, as a long clip's whole text once it's read.
    func show(_ text: String) {
        guard let view = view as? UITextView else { return }
        if let heading {
            let full = NSMutableAttributedString(attributedString: heading)
            let gap = NSMutableParagraphStyle()
            gap.paragraphSpacingBefore = 6
            full.append(
                NSAttributedString(
                    string: "\n" + text.trimmingCharacters(in: .whitespacesAndNewlines),
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.secondaryLabel,
                        .paragraphStyle: gap,
                    ]))
            view.attributedText = full
        } else {
            view.text = text
        }
        let width: CGFloat = 340
        let height = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        preferredContentSize = CGSize(width: width, height: min(height, tallest))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let gif, let view = view as? UIImageView else { return }
        playing = true
        CGAnimateImageDataWithBlock(gif as CFData, nil) { [weak self, weak view] _, frame, stop in
            let playing = MainActor.assumeIsolated {
                guard self?.playing == true, let view else { return false }
                view.image = UIImage(cgImage: frame)
                return true
            }
            if !playing { stop.pointee = true }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        playing = false
    }
}
