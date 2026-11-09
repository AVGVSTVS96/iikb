import ImageIO
import KeyboardCore
import UIKit
import UniformTypeIdentifiers

/// A photo in a chat, as Messages shows one: the picture itself, rounded as a bubble, up to 240 wide, in its shape
/// before it comes when the file says its size. A tap opens it large; holding it is iOS's own context menu: the photo
/// larger above Copy, which copies the original file.
public final class ImageBubble: UIView, ChatBubble, UIContextMenuInteractionDelegate {
    /// The file's bytes, which only the owner can fetch.
    public var fetch: (URL) async -> Data? = { _ in nil }
    /// The photo came, so its size is known.
    public var onLoad: () -> Void = {}
    /// The photo was tapped, to see it large.
    public var onTap: (ImageBubble) -> Void = { _ in }
    public private(set) var mine = false
    public var joined = (above: false, below: false) { didSet { if joined != oldValue { setNeedsLayout() } } }
    public var drawn = false {
        didSet {
            guard drawn != oldValue else { return }
            if drawn { return load() }
            loading?.cancel()
            loading = nil
            picture.image = nil
        }
    }

    private let picture = UIImageView()
    private let shape = CAShapeLayer()
    public private(set) var file: ChatFile?
    public var image: UIImage? { picture.image }
    /// The photo's size once it came, kept while it isn't drawn.
    private var came: CGSize?
    private var loading: Task<Void, Never>?
    private static let widest: CGFloat = 240
    private static let tallest: CGFloat = 320
    /// Photos decoded for as long as the keyboard runs, so a chat opened again shows them at once; capped, since iOS
    /// ends a keyboard past its memory limit.
    private static let decoded = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 16 << 20
        return cache
    }()

    override public init(frame: CGRect) {
        super.init(frame: frame)
        picture.contentMode = .scaleAspectFill
        picture.clipsToBounds = true
        picture.layer.mask = shape
        addSubview(picture)
        addInteraction(UIContextMenuInteraction(delegate: self))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
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
        loading?.cancel()
        loading = nil
        picture.image = nil
        came = nil
        if drawn { load() }
    }

    private func load() {
        guard let file, picture.image == nil, loading == nil else { return }
        picture.image = Self.decoded.object(forKey: file.url as NSURL)
        if let image = picture.image {
            came = image.size
            return
        }
        loading = Task { [weak self, fetch] in
            guard let data = await fetch(file.url), !Task.isCancelled,
                let image = await Self.decode(data, side: 480)
            else { return }
            let pixels = image.size.width * image.size.height * image.scale * image.scale
            Self.decoded.setObject(image, forKey: file.url as NSURL, cost: Int(pixels) * 4)
            guard let self, !Task.isCancelled, self.file == file else { return }
            loading = nil
            picture.image = image
            came = image.size
            onLoad()
        }
    }

    @objc private func tapped() {
        if picture.image != nil { onTap(self) }
    }

    /// The photo at most `side` pixels on its longer side, decoded off the main thread, so a big one never holds the
    /// keyboard's memory at full size.
    @concurrent nonisolated static func decode(_ data: Data, side: Int) async -> UIImage? {
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
        let size =
            came
            ?? file.flatMap { file in file.width.flatMap { w in file.height.map { CGSize(width: w, height: $0) } } }
            ?? CGSize(width: 4, height: 3)
        guard size.width > 0, size.height > 0 else { return CGSize(width: widest, height: (widest * 0.75).rounded()) }
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
            guard let data = await fetch(file.url), let sharp = await ImageBubble.decode(data, side: 1000) else {
                return
            }
            self?.picture.image = sharp
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = picture
    }
}

/// A photo opened from its bubble, as large as the thread, over the messages until a tap closes it. Holding it is the
/// bubble's own menu.
final class PhotoView: UIView {
    var onClose: () -> Void = {}
    private let picture = UIImageView()

    init(_ bubble: ImageBubble, fetch: @escaping (URL) async -> Data?, theme: KeyboardTheme) {
        super.init(frame: .zero)
        backgroundColor = theme.card.ui
        accessibilityIdentifier = "iikb.chat.photo"
        picture.image = bubble.image
        picture.contentMode = .scaleAspectFit
        picture.isUserInteractionEnabled = true
        picture.addInteraction(UIContextMenuInteraction(delegate: bubble))
        addSubview(picture)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        guard let file = bubble.file else { return }
        Task { [weak self] in
            guard let data = await fetch(file.url), let sharp = await ImageBubble.decode(data, side: 1000) else {
                return
            }
            self?.picture.image = sharp
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func close() {
        onClose()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picture.frame = bounds.insetBy(dx: 8, dy: 8)
    }
}
