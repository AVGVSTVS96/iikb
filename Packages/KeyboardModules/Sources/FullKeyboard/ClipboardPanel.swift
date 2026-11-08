import KeyboardStore
import KeyboardCore
import KeyboardUI
import UIKit

/// The clipboard panel's results (docs/design.md, "Clipboard"): what you copied, pinned items first, as rows scrolling
/// up and down (cards in one row scrolling sideways in the compact layout). A tap types the text, or puts an image back
/// on the clipboard; holding a row shows all of it, with Paste, Pin and Delete (UIKit's context menu). Only the rows on
/// screen are made, and their thumbnails decode off the main thread, so a long history opens as fast as a short one.
final class ClipboardPanel: UIView, PanelContent, UICollectionViewDataSource, UICollectionViewDelegate {
    var fullAccess: () -> Bool = { false }
    /// What a row's length is counted in, Settings › Layout › Clipboard Length.
    var length: () -> ClipboardLength = { .characters }
    var onPaste: (String) -> Void = { _ in }
    var onTurnOn: () -> Void = {}
    /// The search row's notice changed.
    var changed: () -> Void = {}
    let placeholder = "Search clipboard"
    var glyph: UIImage? { UIImage(systemName: "list.clipboard") }
    private(set) var notice: String?

    private struct Shown: Equatable {
        var query: String
        var compact: Bool
        var theme: KeyboardTheme
        var length: ClipboardLength
    }

    private let store: ClipboardStore
    private var search = 0
    private var shown: Shown?
    private var items: [ClipboardHistory.Item] = []
    private let layout = UICollectionViewFlowLayout()
    private lazy var list = UICollectionView(frame: .zero, collectionViewLayout: layout)
    /// In the list's content, ahead of the rows, so in one row it scrolls away with them.
    private let message = PanelNotice()
    private let thumbnails = NSCache<NSString, UIImage>()

    init(store: ClipboardStore) {
        self.store = store
        super.init(frame: .zero)
        list.backgroundColor = .clear
        list.showsVerticalScrollIndicator = false
        list.showsHorizontalScrollIndicator = false
        list.delaysContentTouches = false
        list.dataSource = self
        list.delegate = self
        list.accessibilityIdentifier = "iikb.clipboard"
        [list.topEdgeEffect, list.bottomEdgeEffect, list.leftEdgeEffect, list.rightEdgeEffect].forEach { $0.isHidden = true }
        list.register(ClipRow.self, forCellWithReuseIdentifier: "clip")
        message.accessibilityIdentifier = "iikb.clipboard.message"
        message.onTurnOn = { [unowned self] in onTurnOn() }
        list.addSubview(message)
        addSubview(list)
        store.onChange = { [unowned self] in refresh() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        search += 1
        if fullAccess() { store.catchUp() }
        notice = nil
        shown = nil
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        let next = Shown(query: query, compact: metrics.toolbar.isCompact, theme: theme, length: length())
        guard next != shown else { return }
        if query != shown?.query { notice = nil }
        shown = next
        refresh()
    }

    /// Runs only when the search, the look or the history changed, never on a keystroke that changed none of them.
    private func refresh() {
        guard let shown, window != nil else { return }
        search += 1
        let request = search
        Task {
            let items = fullAccess() && store.loaded ? await store.matching(shown.query) : []
            guard request == search else { return }
            display(items, shown: shown)
        }
    }

    private func display(_ items: [ClipboardHistory.Item], shown: Shown) {
        let loaded = fullAccess() && store.loaded
        let missing: String? = if !fullAccess() { "Clipboard needs Full Access." } else if store.refused { "To keep what you copy, set Paste from Other Apps to Allow." } else { nil }
        let empty: String? = loaded && items.isEmpty ? (shown.query.isEmpty ? "Things you copy show up here." : "Nothing copied with “\(shown.query)”") : nil
        message.show(missing ?? empty, turnOn: missing != nil, oneRow: shown.compact, theme: shown.theme)
        let moved = items.map(\.content) != self.items.map(\.content)
        self.items = items
        layout.scrollDirection = shown.compact ? .horizontal : .vertical
        list.reloadData()
        if moved { list.contentOffset = .zero }
        setNeedsLayout()
    }

    private func pick(_ item: ClipboardHistory.Item) {
        switch item.content {
        case .text(let text): onPaste(text)
        case .textFile:
            let request = search
            Task {
                guard let text = await store.text(item.content), request == search, window != nil else { return }
                onPaste(text)
            }
        case .image(let name):
            store.copy(image: name)
            notice = "Copied. Paste it in your message."
            changed()
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let row = collectionView.dequeueReusableCell(withReuseIdentifier: "clip", for: indexPath) as! ClipRow
        let item = items[indexPath.item]
        configure(row, item)
        row.accessibilityIdentifier = "iikb.clip.\(item.content.label)"
        if case .image(let name) = item.content { thumbnail(name, for: row) }
        if let site = ClipTitle.site(item.content), LinkIcons.shared.cached(site) == nil {
            Task {
                guard await LinkIcons.shared.icon(site) != nil, row.shown == item.content else { return }
                configure(row, item)
            }
        }
        return row
    }

    private func configure(_ row: ClipRow, _ item: ClipboardHistory.Item) {
        let compact = shown?.compact == true, theme = shown?.theme ?? .lightCurrent
        let detail = [ClipboardHistory.length(of: item.content, in: shown?.length ?? .characters), ClipboardHistory.age(of: item.found, now: Date.now.timeIntervalSince1970)]
        let title = ClipTitle.make(item.content, font: ClipRow.font(compact: compact), label: theme.label.ui, secondary: theme.candidate.ui, short: compact && layout.itemSize.width < 160)
        row.show(
            text: item.content.preview, styled: title, detail: detail.compactMap { $0 }.joined(separator: " · "), pinned: item.pinned,
            compact: compact, theme: theme
        )
        row.shown = item.content
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = indexPaths.first.map({ items[$0.item] }) else { return nil }
        return UIContextMenuConfiguration(identifier: nil) { [unowned self] in preview(item.content) } actionProvider: { [unowned self] _ in
            UIMenu(children: [
                UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { _ in self.pick(item) },
                UIAction(title: item.pinned ? "Unpin" : "Pin", image: UIImage(systemName: item.pinned ? "pin.slash" : "pin")) { _ in
                    self.store.setPinned(!item.pinned, item.content)
                    self.refresh()
                },
                UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self.store.remove(item.content)
                    self.refresh()
                },
            ])
        }
    }

    private func preview(_ content: ClipboardHistory.Item.Content) -> ClipPreview {
        switch content {
        case .text(let text):
            return ClipPreview(text: text, heading: ClipTitle.heading(content))
        case .textFile(_, let start):
            let preview = ClipPreview(text: start)
            Task { [store] in if let text = await store.text(content) { preview.show(text) } }
            return preview
        case .image(let name): return ClipPreview(image: store.thumbnail(name, side: 900))
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        pick(items[indexPath.item])
    }

    private func thumbnail(_ name: String, for row: ClipRow) {
        if let image = thumbnails.object(forKey: name as NSString) { return row.thumbnail = image }
        Task { [store] in
            let image = await Task.detached(priority: .userInitiated) { store.thumbnail(name, side: 96) }.value
            guard let image else { return }
            thumbnails.setObject(image, forKey: name as NSString)
            if row.shown == .image(name) { row.thumbnail = image }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        list.frame = bounds
        let compact = shown?.compact == true, gap = 6.0
        let ahead = items.isEmpty || message.isHidden ? 0.0 : (compact ? bounds.width + gap : 46)
        message.frame = items.isEmpty ? bounds : CGRect(x: 0, y: 0, width: bounds.width, height: compact ? bounds.height : 44)
        layout.sectionInset = compact ? UIEdgeInsets(top: 0, left: ahead, bottom: 0, right: 0) : UIEdgeInsets(top: ahead, left: 0, bottom: 0, right: 0)
        layout.minimumLineSpacing = compact ? gap : 2
        layout.minimumInteritemSpacing = 0
        let size = compact ? CGSize(width: ((bounds.width - 2 * gap) / 3).rounded(.down), height: bounds.height) : CGSize(width: bounds.width, height: 44)
        if layout.itemSize != size { layout.itemSize = size }
        layout.invalidateLayout()
    }
}

/// One row of a drawer, the clipboard's or Transcripts': its pin, its text or a thumbnail, and its length and age.
final class ClipRow: UICollectionViewCell {
    var thumbnail: UIImage? {
        get { image.image }
        set { image.image = newValue }
    }
    /// What the row shows, so a thumbnail that loads late lands only on its own row.
    var shown: ClipboardHistory.Item.Content?
    private var pinned = false
    private var compact = false
    private let pin = UIImageView()
    private let text = UILabel()
    private let image = UIImageView()
    private let age = UILabel()
    private let backdrop = UIView()
    private var fill = UIColor.clear
    private var pressedFill = UIColor.clear

    override init(frame: CGRect) {
        super.init(frame: frame)
        backdrop.layer.cornerRadius = 10
        backdrop.layer.cornerCurve = .continuous
        pin.image = UIImage(systemName: "pin.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))
        pin.contentMode = .center
        image.layer.cornerRadius = 6
        image.clipsToBounds = true
        image.contentMode = .scaleAspectFill
        [backdrop, pin, text, image, age].forEach {
            $0.isUserInteractionEnabled = false
            contentView.addSubview($0)
        }
        text.accessibilityIdentifier = "iikb.clip.text"
        age.accessibilityIdentifier = "iikb.clip.detail"
    }

    required init?(coder: NSCoder) { fatalError() }

    static func font(compact: Bool) -> UIFont { .systemFont(ofSize: compact ? 14 : 16) }

    /// `text` nil shows the thumbnail; `styled`, when there is one, is how the text is written (`ClipTitle`); `detail`
    /// is the length and age, "312 chars · 5m".
    func show(text string: String?, styled: NSAttributedString? = nil, detail: String, pinned: Bool, compact: Bool, theme: KeyboardTheme) {
        self.pinned = pinned
        self.compact = compact
        fill = compact ? theme.key.ui : .clear
        pressedFill = compact ? theme.keyPressed.ui : theme.label.ui.withAlphaComponent(0.12)
        pin.tintColor = theme.candidate.ui
        pin.isHidden = !pinned
        text.textColor = theme.label.ui
        text.font = Self.font(compact: compact)
        text.numberOfLines = compact ? 2 : 1
        age.textColor = theme.candidate.ui
        age.font = .monospacedDigitSystemFont(ofSize: compact ? 11 : 13, weight: .regular)
        age.text = detail
        age.textAlignment = compact ? .left : .right
        if let styled { text.attributedText = styled } else { text.text = string.map { String($0.prefix(300)).split(whereSeparator: \.isNewline).joined(separator: " ") } }
        text.isHidden = string == nil
        image.isHidden = string != nil
        if string != nil { image.image = nil }
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        image.image = nil
    }

    override var isHighlighted: Bool {
        didSet { backdrop.backgroundColor = isHighlighted ? pressedFill : fill }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        backdrop.frame = bounds
        backdrop.backgroundColor = isHighlighted ? pressedFill : fill
        if compact {
            let inset = bounds.insetBy(dx: 10, dy: 6)
            pin.frame = CGRect(x: inset.maxX - 14, y: inset.minY, width: 14, height: 14)
            text.frame = CGRect(x: inset.minX, y: inset.minY, width: inset.width - (pinned ? 16 : 0), height: inset.height - 13)
            image.frame = CGRect(x: inset.minX, y: inset.minY, width: inset.height - 13, height: inset.height - 13)
            age.frame = CGRect(x: inset.minX, y: inset.maxY - 13, width: inset.width, height: 13)
            return
        }
        pin.frame = CGRect(x: 0, y: 0, width: 16, height: bounds.height)
        let detail = ceil(age.sizeThatFits(bounds.size).width)
        let right = bounds.width - max(detail, 28)
        age.frame = CGRect(x: right, y: 0, width: bounds.width - right, height: bounds.height)
        image.frame = CGRect(x: 22, y: (bounds.height - 32) / 2, width: 32, height: 32)
        text.frame = CGRect(x: 22, y: 0, width: right - 34, height: bounds.height)
    }
}

private extension ClipboardHistory.Item.Content {
    var label: String {
        switch self {
        case .text(let text), .textFile(_, let text): String(text.prefix(40))
        case .image(let name): name
        }
    }
}
