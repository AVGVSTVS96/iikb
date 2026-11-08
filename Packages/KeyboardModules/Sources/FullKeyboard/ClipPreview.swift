import ImageIO
import UIKit

/// All of a held clip, transcript or GIF, as its context menu's preview: text in full, scrolling where it's long, or the
/// image, a GIF playing.
final class ClipPreview: UIViewController {
    private let text: String?
    private let image: UIImage?
    private let gif: Data?

    init(text: String) {
        self.text = text
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
        let width: CGFloat = 300
        preferredContentSize = CGSize(width: width, height: (width * size.height / max(size.width, 1)).rounded())
        self.view = view
    }

    private var playing = false

    /// The text in place of what it showed, as a long clip's whole text once it's read.
    func show(_ text: String) {
        guard let view = view as? UITextView else { return }
        view.text = text
        let width: CGFloat = 340
        let height = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        preferredContentSize = CGSize(width: width, height: min(height, 480))
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
