import KeyboardCore
import UIKit

/// A message's photos as Telegram groups them: one bubble, the photos in rows across its width, each row as tall as
/// its photos' shapes make it, and the words under them in the same bubble. A tap on a photo opens it, and holding one
/// is its own menu (`ImageBubble`).
public final class AlbumBubble: UIView, ChatBubble {
    /// A photo's bytes, which only the owner can fetch.
    public var fetch: (URL) async -> Data? = { _ in nil }
    /// A photo came, so its shape is known.
    public var onLoad: () -> Void = {}
    /// A photo was tapped, to see it large.
    public var onTap: (ImageBubble) -> Void = { _ in }
    public private(set) var mine = false
    public var joined = (above: false, below: false) { didSet { if joined != oldValue { setNeedsLayout() } } }
    public var drawn = false {
        didSet {
            tiles.forEach { $0.drawn = drawn }
            caption.drawn = drawn
        }
    }

    private let shape = CAShapeLayer()
    private let photos = UIView()
    private let clip = CAShapeLayer()
    private var tiles: [ImageBubble] = []
    private let caption = MessageBubble()
    private var captioned = false
    private static let gap: CGFloat = 2
    /// Around the photos when words are under them, the bubble's color showing as a rim.
    private static let rim: CGFloat = 2
    private static let widest: CGFloat = 300

    override public init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(shape, at: 0)
        photos.layer.mask = clip
        addSubview(photos)
        caption.bare = true
        addSubview(caption)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show(_ files: [ChatFile], text: String, mine: Bool, pending: Bool, theme: KeyboardTheme) {
        self.mine = mine
        alpha = pending ? 0.6 : 1
        while tiles.count < files.count {
            let tile = ImageBubble()
            tile.tile = true
            tile.fetch = { [unowned self] in await fetch($0) }
            tile.onLoad = { [unowned self] in
                setNeedsLayout()
                onLoad()
            }
            tile.onTap = { [unowned self] in onTap($0) }
            tile.drawn = drawn
            photos.addSubview(tile)
            tiles.append(tile)
        }
        while tiles.count > files.count { tiles.removeLast().removeFromSuperview() }
        for (tile, file) in zip(tiles, files) { tile.show(file, mine: mine, pending: false, theme: theme) }
        captioned = !text.isEmpty
        caption.isHidden = !captioned
        if captioned { caption.show(ChatMessage(text: text, mine: mine), theme: theme) }
        shape.fillColor = captioned ? (mine ? theme.prominent.ui : theme.chatBubble.ui).cgColor : nil
        setNeedsLayout()
    }

    /// How many photos go in each row: one row for one or two, a wide one over two for three, else rows of two and
    /// three, the twos first.
    static func rows(_ count: Int) -> [Int] {
        guard count > 2 else { return count == 0 ? [] : [count] }
        if count == 3 { return [1, 2] }
        let rows = (count + 2) / 3
        let base = count / rows
        let more = count % rows
        return Array(repeating: base, count: rows - more) + Array(repeating: base + 1, count: more)
    }

    /// The photos' frames in a block `width` wide, each row filling it.
    private func layout(width: CGFloat) -> [CGRect] {
        guard tiles.count > 1 else {
            guard let tile = tiles.first else { return [] }
            let size = tile.size(within: width)
            return [CGRect(origin: .zero, size: size)]
        }
        var frames: [CGRect] = []
        var y: CGFloat = 0
        var at = 0
        for count in Self.rows(tiles.count) {
            let row = tiles[at..<at + count]
            let room = width - Self.gap * CGFloat(count - 1)
            let shapes = row.map(\.aspect).reduce(0, +)
            let height = min(max(room / shapes, width / 4), width * 0.75).rounded()
            var x: CGFloat = 0
            for (index, tile) in row.enumerated() {
                let last = index == count - 1
                let tileWidth = last ? width - x : (room * tile.aspect / shapes).rounded()
                frames.append(CGRect(x: x, y: y, width: tileWidth, height: height))
                x += tileWidth + Self.gap
            }
            y += height + Self.gap
            at += count
        }
        return frames
    }

    public func size(within width: CGFloat) -> CGSize {
        let rim = captioned ? Self.rim : 0
        let block = min(width, Self.widest) - 2 * rim
        let frames = layout(width: block)
        let photosSize = CGSize(
            width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
        guard captioned else { return photosSize }
        let words = caption.size(within: photosSize.width + 2 * rim)
        return CGSize(width: photosSize.width + 2 * rim, height: photosSize.height + rim + words.height)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let rim = captioned ? Self.rim : 0
        let frames = layout(width: bounds.width - 2 * rim)
        let height = frames.map(\.maxY).max() ?? 0
        photos.frame = CGRect(x: rim, y: rim, width: bounds.width - 2 * rim, height: height)
        for (tile, frame) in zip(tiles, frames) { tile.frame = frame }
        caption.frame = CGRect(
            x: 0, y: photos.frame.maxY, width: bounds.width, height: bounds.height - photos.frame.maxY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.path = UIBezierPath(bubble: bounds, mine: mine, joined: joined, tail: captioned && !joined.below).cgPath
        clip.frame = photos.bounds
        clip.path =
            captioned
            ? UIBezierPath(
                roundedRect: photos.bounds, byRoundingCorners: [.topLeft, .topRight],
                cornerRadii: CGSize(width: 16, height: 16)
            ).cgPath
            : UIBezierPath(bubble: photos.bounds, mine: mine, joined: joined).cgPath
        CATransaction.commit()
    }
}
