import ImageIO
import KeyboardCore
import UIKit
import UniformTypeIdentifiers

/// A photo in a chat, as Messages shows one: the picture itself, rounded as a bubble, up to 240 wide. Holding it is
/// iOS's own context menu: the photo larger above Copy, which copies the original file.
public final class ImageBubble: UIView, ChatBubble, UIContextMenuInteractionDelegate {
    /// The file's bytes, which only the owner can fetch.
    public var fetch: (URL) async -> Data? = { _ in nil }
    /// The photo came, so its size is known.
    public var onLoad: () -> Void = {}
    public private(set) var mine = false
    public var joined = (above: false, below: false) { didSet { if joined != oldValue { setNeedsLayout() } } }

    private let picture = UIImageView()
    private let shape = CAShapeLayer()
    private var file: ChatFile?
    private var loading: Task<Void, Never>?
    private static let widest: CGFloat = 240
    private static let tallest: CGFloat = 320

    override public init(frame: CGRect) {
        super.init(frame: frame)
        picture.contentMode = .scaleAspectFill
        picture.clipsToBounds = true
        picture.layer.mask = shape
        addSubview(picture)
        addInteraction(UIContextMenuInteraction(delegate: self))
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show(_ file: ChatFile, mine: Bool, pending: Bool, theme: KeyboardTheme) {
        self.mine = mine
        alpha = pending ? 0.6 : 1
        picture.backgroundColor = theme.key.ui
        accessibilityLabel = (mine ? "You: " : "") + "Photo, \(file.name)"
        guard file != self.file else { return }
        self.file = file
        picture.image = nil
        loading?.cancel()
        loading = Task { [weak self, fetch] in
            guard let data = await fetch(file.url), !Task.isCancelled else { return }
            let image = await Self.decode(data, side: 480)
            guard let self, !Task.isCancelled, self.file == file else { return }
            picture.image = image
            onLoad()
        }
    }

    /// The photo at most `side` pixels on its longer side, decoded off the main thread, so a big one never holds the
    /// keyboard's memory at full size.
    @concurrent nonisolated private static func decode(_ data: Data, side: Int) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: side,
                ] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }

    public func size(within width: CGFloat) -> CGSize {
        let widest = min(width, Self.widest)
        guard let size = picture.image?.size, size.width > 0, size.height > 0 else {
            return CGSize(width: widest, height: (widest * 0.75).rounded())
        }
        let scale = min(widest / size.width, Self.tallest / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        picture.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.path = UIBezierPath(bubble: bounds, mine: mine, joined: joined).cgPath
        CATransaction.commit()
    }

    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let file, let image = picture.image else { return nil }
        let room = window?.bounds.size ?? CGSize(width: 400, height: 600)
        return UIContextMenuConfiguration(identifier: nil) { [fetch] in
            PhotoPreview(image, file: file, fetch: fetch, room: room)
        } actionProvider: { [fetch] _ in
            UIMenu(children: [
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.image = image
                    Task {
                        guard let data = await fetch(file.url) else { return }
                        let type = file.type.flatMap { UTType(mimeType: $0) } ?? .image
                        UIPasteboard.general.setData(data, forPasteboardType: type.identifier)
                    }
                }
            ])
        }
    }
}

/// The held photo, as large as the keyboard leaves it with the menu under it, sharpened once the original comes.
private final class PhotoPreview: UIViewController {
    private let picture = UIImageView()

    init(_ image: UIImage, file: ChatFile, fetch: @escaping (URL) async -> Data?, room: CGSize) {
        super.init(nibName: nil, bundle: nil)
        picture.image = image
        picture.contentMode = .scaleAspectFit
        let scale = min((room.width - 32) / image.size.width, (room.height / 2).rounded(.down) / image.size.height)
        preferredContentSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        Task { [weak self] in
            guard let data = await fetch(file.url), let source = CGImageSourceCreateWithData(data as CFData, nil),
                let sharp = CGImageSourceCreateThumbnailAtIndex(
                    source, 0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1000,
                    ] as CFDictionary)
            else { return }
            self?.picture.image = UIImage(cgImage: sharp)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = picture
    }
}
