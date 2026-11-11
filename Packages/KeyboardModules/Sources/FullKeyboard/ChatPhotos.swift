import ImageIO
import KeyboardCore
import KeyboardStore
import KeyboardUI
import Photos
import UIKit
import UniformTypeIdentifiers

/// Photos to send from a chat: your newest photos as a grid in the keys' place, as Telegram shows them under its message
/// box. A tap attaches a photo, numbered in the order picked, and a second tap takes it off, as the ✕ on it in the box
/// does. The library is read with the access you give the iikb app, which the keyboard shares; iOS's own photo picker
/// stays on "Loading…" inside a keyboard (simulator, Nov 10), since it is a view from another process and the keyboard
/// already is one.
final class ChatPhotos: NSObject {
    var changed: () -> Void = {}
    /// The photos attached, in the order picked, as each is ready to send.
    private(set) var attached: [UnsentPhoto] = []
    /// The grid while it's made: from the first tap on the paperclip until the chat closes or the keyboard goes.
    private(set) var shown: PhotoGrid?
    var grid: PhotoGrid {
        if let shown { return shown }
        let grid = PhotoGrid()
        grid.picked = { [unowned self] in picked.map(\.asset) }
        grid.onTap = { [unowned self] in toggle($0) }
        shown = grid
        return grid
    }
    /// The photos picked in the grid, each with its copy once it's ready.
    private var picked: [(asset: String, photo: UnsentPhoto?)] = []
    private var reading: Task<Void, Never>?

    /// Telegram's album holds ten.
    static let most = 10

    /// What was attached before the keyboard last went away (`KeptChat`).
    func restore(_ photos: [UnsentPhoto]) {
        attached = photos
        changed()
    }

    func remove(at index: Int) {
        guard attached.indices.contains(index) else { return }
        let photo = attached.remove(at: index)
        picked.removeAll { $0.photo == photo }
        shown?.refresh()
        changed()
    }

    /// Takes what was sent off the box and out of the grid.
    func clear() {
        (attached, picked) = ([], [])
        shown?.refresh()
        changed()
    }

    /// Lets the grid go, the photos staying attached; a new one starts with nothing ticked.
    func dropGrid() {
        shown?.removeFromSuperview()
        (shown, picked) = (nil, [])
    }

    /// Photos pasted into the box, after those attached, up to ten in all.
    func paste(_ items: [NSItemProvider]) {
        let room = Self.most - attached.count
        guard room > 0 else { return }
        read {
            for item in items.prefix(room) {
                guard let photo = await Self.ready(item) else { continue }
                self.attach(photo)
            }
        }
    }

    private func toggle(_ asset: PHAsset) {
        if let index = picked.firstIndex(where: { $0.asset == asset.localIdentifier }) {
            if let photo = picked.remove(at: index).photo { attached.removeAll { $0 == photo } }
            shown?.refresh()
            return changed()
        }
        guard attached.count + picked.filter({ $0.photo == nil }).count < Self.most else { return }
        let id = asset.localIdentifier
        picked.append((id, nil))
        shown?.refresh()
        read {
            let photo = await Self.ready(asset)
            guard let index = self.picked.firstIndex(where: { $0.asset == id }) else { return }
            guard let photo else {
                self.picked.remove(at: index)
                return self.shown?.refresh() ?? ()
            }
            self.picked[index].photo = photo
            self.attach(photo)
        }
    }

    private func attach(_ photo: UnsentPhoto) {
        guard attached.count < Self.most else { return }
        attached.append(photo)
        changed()
    }

    /// One photo made ready at a time, so only one is in memory.
    private func read(_ work: @escaping () async -> Void) {
        let earlier = reading
        reading = Task {
            await earlier?.value
            await work()
        }
    }

    /// The longer side a photo is sent at, as Telegram sends photos.
    nonisolated static let side = 2048

    /// A photo from the library as a JPEG at most `side` pixels on its longer side, fetched from iCloud when only
    /// iCloud has it, and made small off the main thread.
    private static func ready(_ asset: PHAsset) async -> UnsentPhoto? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return await withCheckedContinuation { done in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                DispatchQueue.global(qos: .userInitiated).async {
                    done.resume(
                        returning: data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap(shrink))
                }
            }
        }
    }

    /// A photo pasted into the box. iOS's copy of its file is there only while its handler runs, off the main thread.
    private static func ready(_ item: NSItemProvider) async -> UnsentPhoto? {
        await withCheckedContinuation { done in
            _ = item.loadFileRepresentation(for: .image, openInPlace: false) { file, _, _ in
                done.resume(returning: file.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }.flatMap(shrink))
            }
        }
    }

    /// The photo at most `side` pixels on its longer side, never decoded whole, since iOS ends the keyboard past its
    /// memory limit (177 MB on the Duo), as a JPEG kept to send.
    nonisolated private static func shrink(_ source: CGImageSource) -> UnsentPhoto? {
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: side,
                ] as CFDictionary)
        else { return nil }
        let jpeg = NSMutableData()
        guard let out = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(out) else { return nil }
        return UnsentStore.keep(jpeg as Data, width: image.width, height: image.height)
    }
}

/// Your newest photos, about 110 points each across the width, drawn at the size they're shown so the grid costs the
/// keyboard little memory; each picked one shows its number. Without access to the library it says so, and Allow Photos opens iikb to ask.
final class PhotoGrid: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onTap: (PHAsset) -> Void = { _ in }
    /// The picked photos' asset ids, in order.
    var picked: () -> [String] = { [] }
    var onAllow: () -> Void = {}

    private let layout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let notice = PanelNotice()
    private let images = PHCachingImageManager()
    private var assets: PHFetchResult<PHAsset>?
    private var theme = KeyboardTheme.lightCurrent
    /// The newest this many; Telegram's sheet scrolls further, and a keyboard is for the photo you just took.
    private static let newest = 500
    private static let gap: CGFloat = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        layout.minimumInteritemSpacing = Self.gap
        layout.minimumLineSpacing = Self.gap
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(PhotoCell.self, forCellWithReuseIdentifier: "photo")
        collection.accessibilityIdentifier = "iikb.chat.photos"
        notice.onTurnOn = { [unowned self] in onAllow() }
        addSubview(collection)
        addSubview(notice)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Reads the library again as the grid comes up, so a photo just taken is first.
    func show(theme: KeyboardTheme) {
        self.theme = theme
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = Self.newest
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let found = PHAsset.fetchAssets(with: .image, options: options)
        // The status a keyboard reads first stays for as long as it runs, so access given in iikb since shows in what
        // the library gives, not in the status.
        let allowed = status == .authorized || status == .limited || found.count > 0
        notice.show(
            allowed ? nil : "Photos need their own permission to show here. Full Access doesn’t include them.",
            turnOn: !allowed, action: "Allow Photos", oneRow: false, theme: theme)
        collection.isHidden = !allowed
        guard allowed else { return }
        assets = found
        collection.reloadData()
    }

    /// Redraws the numbers on the picked photos.
    func refresh() {
        let picked = picked()
        for cell in collection.visibleCells {
            guard let cell = cell as? PhotoCell, let id = cell.asset else { continue }
            cell.number(picked.firstIndex(of: id).map { $0 + 1 }, full: picked.count >= ChatPhotos.most, theme: theme)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        collection.frame = bounds
        notice.frame = bounds.insetBy(dx: 24, dy: 0)
        let across = max(3, (bounds.width / 110).rounded())
        let side = ((bounds.width - Self.gap * (across - 1)) / across).rounded(.down)
        if layout.itemSize.width != side { layout.itemSize = CGSize(width: side, height: side) }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        assets?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "photo", for: path)
        guard let cell = cell as? PhotoCell, let asset = assets?.object(at: path.item) else { return cell }
        let scale = window?.screen.scale ?? 3
        let size = CGSize(width: layout.itemSize.width * scale, height: layout.itemSize.height * scale)
        cell.show(asset, from: images, size: size, theme: theme)
        cell.accessibilityIdentifier = "iikb.chat.photos.\(path.item)"
        let picked = picked()
        cell.number(
            picked.firstIndex(of: asset.localIdentifier).map { $0 + 1 }, full: picked.count >= ChatPhotos.most,
            theme: theme)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt path: IndexPath) {
        collectionView.deselectItem(at: path, animated: false)
        guard let asset = assets?.object(at: path.item) else { return }
        onTap(asset)
    }
}

/// A photo in the grid, and its number once it's picked, in a circle at its corner as Telegram's.
private final class PhotoCell: UICollectionViewCell {
    private(set) var asset: String?
    private let picture = UIImageView()
    private let badge = UILabel()
    private let ring = UIView()
    private var request: PHImageRequestID?
    private static let badgeSize: CGFloat = 24

    override init(frame: CGRect) {
        super.init(frame: frame)
        picture.contentMode = .scaleAspectFill
        picture.clipsToBounds = true
        contentView.addSubview(picture)
        ring.layer.borderWidth = 1.5
        ring.layer.borderColor = UIColor.white.cgColor
        ring.layer.cornerRadius = Self.badgeSize / 2
        ring.backgroundColor = UIColor.black.withAlphaComponent(0.15)
        ring.isUserInteractionEnabled = false
        contentView.addSubview(ring)
        badge.font = .systemFont(ofSize: 13, weight: .semibold)
        badge.textAlignment = .center
        badge.clipsToBounds = true
        badge.layer.cornerRadius = Self.badgeSize / 2
        contentView.addSubview(badge)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ asset: PHAsset, from images: PHCachingImageManager, size: CGSize, theme: KeyboardTheme) {
        if let request { images.cancelImageRequest(request) }
        self.asset = asset.localIdentifier
        picture.image = nil
        picture.backgroundColor = theme.key.ui
        accessibilityLabel = "Photo"
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let id = asset.localIdentifier
        request = images.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) {
            [weak self] image, _ in
            guard let self, self.asset == id else { return }
            picture.image = image
        }
    }

    /// Its number once picked, ringed in white like the empty circle; with `full`, ten picked, the rest dim.
    func number(_ number: Int?, full: Bool, theme: KeyboardTheme) {
        badge.isHidden = number == nil
        badge.text = number.map(String.init)
        badge.backgroundColor = theme.prominent.ui
        badge.textColor = theme.prominentLabel.ui
        badge.layer.borderWidth = 1.5
        badge.layer.borderColor = UIColor.white.cgColor
        ring.isHidden = number == nil && full
        picture.alpha = number == nil ? (full ? 0.4 : 1) : 0.8
        accessibilityTraits = number == nil ? .button : [.button, .selected]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picture.frame = contentView.bounds
        let side = Self.badgeSize
        let frame = CGRect(x: contentView.bounds.maxX - side - 6, y: 6, width: side, height: side)
        ring.frame = frame
        badge.frame = frame
    }
}
