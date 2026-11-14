import KeyboardCore
import KeyboardStore
import KeyboardUI
import UIKit

/// The clipboard panel's results (docs/design.md, "Clipboard"): what you copied, pinned items first, as rows scrolling
/// up and down (cards in one row scrolling sideways in the compact layout), with copied links out of them in a section of
/// their own ahead, each a one-line badge. A tap types the text, or puts an image back on the clipboard; holding one
/// shows all of it, with Paste, Pin and Delete (UIKit's context menu). Only the items on screen are made, and their
/// thumbnails decode off the main thread, so a long history opens as fast as a short one.
final class ClipboardPanel: UIView, PanelContent, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var fullAccess: () -> Bool = { false }
    /// What a row's length is counted in, Settings › Layout › Clipboard Length.
    var length: () -> ClipboardLength = { .characters }
    var onPaste: (String) -> Void = { _ in }
    var onTurnOn: () -> Void = {}
    /// The search row's notice changed.
    var changed: () -> Void = {}
    var field: PanelField {
        .search(
            .init(
                linksOnly ? "Search links" : "Search clipboard", glyph: UIImage(systemName: "list.clipboard"),
                accessories: [linksButton], notice: notice))
    }
    private(set) var notice: String?
    /// Whether only links show, the search row's link button on.
    private var linksOnly = false
    private let linksButton = UIButton(type: .custom)

    private struct Shown: Equatable {
        var query: String
        var compact: Bool
        var theme: KeyboardTheme
        var length: ClipboardLength
        var linksOnly: Bool
    }

    private let store: ClipboardStore
    private var search = 0
    private var shown: Shown?
    /// The links found, newest first, of which the first `badges` show in section 0.
    private var links: [ClipboardHistory.Item] = []
    /// Each link's name on its badge, told apart from the others shown (`ClipLink.names`).
    private var names: [String] = []
    private var badges = 0
    /// Everything else found, section 1.
    private var items: [ClipboardHistory.Item] = []
    private let layout = BadgeFlowLayout()
    private lazy var list = UICollectionView(frame: .zero, collectionViewLayout: layout)
    /// In the list's content, ahead of the rows, so in one row it scrolls away with them.
    private let message = PanelNotice()
    private let thumbnails = NSCache<NSString, UIImage>()
    private static let gap = 6.0

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
        [list.topEdgeEffect, list.bottomEdgeEffect, list.leftEdgeEffect, list.rightEdgeEffect].forEach {
            $0.isHidden = true
        }
        list.register(LinkBadge.self, forCellWithReuseIdentifier: "link")
        list.register(ClipRow.self, forCellWithReuseIdentifier: "clip")
        message.accessibilityIdentifier = "iikb.clipboard.message"
        message.onTurnOn = { [unowned self] in onTurnOn() }
        linksButton.accessibilityIdentifier = "iikb.clipboard.links"
        linksButton.accessibilityLabel = "Links"
        linksButton.setImage(
            UIImage(
                systemName: "link", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)),
            for: .normal)
        linksButton.addAction(
            UIAction { [unowned self] _ in
                linksOnly.toggle()
                linksButton.accessibilityTraits = linksOnly ? [.button, .selected] : .button
                notice = nil
                changed()
            }, for: .touchUpInside)
        list.addSubview(message)
        addSubview(list)
        store.onChange = { [unowned self] in refresh() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        search += 1
        if fullAccess() { store.catchUp() }
        linksOnly = false
        linksButton.accessibilityTraits = .button
        notice = nil
        shown = nil
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        linksButton.tintColor = linksOnly ? theme.prominent.ui : theme.candidate.ui
        let next = Shown(
            query: query, compact: metrics.toolbar.isCompact, theme: theme, length: length(), linksOnly: linksOnly)
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
            let found = fullAccess() && store.loaded ? await store.matching(shown.query) : []
            guard request == search else { return }
            let links = found.filter { ClipTitle.site($0.content) != nil }
            display(
                links: links, items: shown.linksOnly ? [] : found.filter { ClipTitle.site($0.content) == nil },
                shown: shown)
        }
    }

    private func display(links: [ClipboardHistory.Item], items: [ClipboardHistory.Item], shown: Shown) {
        let loaded = fullAccess() && store.loaded
        let found = !links.isEmpty || !items.isEmpty
        let missing: String? =
            if !fullAccess() {
                "Clipboard needs Full Access."
            } else if store.refused, !(found && shown.compact) {
                found ? "New copies aren’t being kept." : "To keep what you copy, set Paste from Other Apps to Allow."
            } else { nil }
        let empty: String? =
            loaded && !found
            ? (shown.query.isEmpty
                ? (shown.linksOnly ? "Links you copy show up here." : "Things you copy show up here.")
                : "Nothing copied with “\(shown.query)”") : nil
        message.show(missing ?? empty, turnOn: missing != nil, oneRow: shown.compact, theme: shown.theme)
        let moved = (links + items).map(\.content) != (self.links + self.items).map(\.content)
        self.links = links
        self.items = items
        layout.scrollDirection = shown.compact ? .horizontal : .vertical
        fitBadges()
        list.reloadData()
        if moved { list.contentOffset = .zero }
        setNeedsLayout()
    }

    /// Sets how many badges show and their names: told apart among all the links to fit them, then among those that
    /// fit, which only narrows their badges. True when either changed.
    @discardableResult private func fitBadges() -> Bool {
        func told(_ links: some Collection<ClipboardHistory.Item>) -> [String] {
            ClipLink.names(links.compactMap { if case .link(let link) = $0.content.kind { link } else { nil } })
        }
        let before = (badges, names)
        names = told(links)
        badges = fittingBadges()
        names = told(links.prefix(badges)) + names.dropFirst(badges)
        return before != (badges, names)
    }

    private func item(at path: IndexPath) -> ClipboardHistory.Item {
        path.section == 0 ? links[path.item] : items[path.item]
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

    func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? badges : items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    {
        let item = item(at: indexPath)
        if indexPath.section == 0 {
            let badge = collectionView.dequeueReusableCell(withReuseIdentifier: "link", for: indexPath) as! LinkBadge
            let name = names[indexPath.item]
            configure(badge, item, name)
            if let site = ClipTitle.site(item.content), LinkIcons.shared.cached(site) == nil {
                Task {
                    guard await LinkIcons.shared.icon(site) != nil, badge.shown == item.content else { return }
                    configure(badge, item, name)
                }
            }
            return badge
        }
        let row = collectionView.dequeueReusableCell(withReuseIdentifier: "clip", for: indexPath) as! ClipRow
        configure(row, item)
        row.accessibilityIdentifier = "iikb.clip.\(item.content.label)"
        if case .image(let name) = item.content { thumbnail(name, for: row) }
        return row
    }

    private func configure(_ row: ClipRow, _ item: ClipboardHistory.Item) {
        let compact = shown?.compact == true
        let theme = shown?.theme ?? .lightCurrent
        let age = ClipboardHistory.age(of: item.found, now: Date.now.timeIntervalSince1970)
        let detail = [ClipboardHistory.length(of: item.content, in: shown?.length ?? .characters), age].compactMap {
            $0
        }.joined(separator: " · ")
        let title = ClipTitle.make(
            item.content, font: ClipRow.font(compact: compact), label: theme.label.ui,
            secondary: compact ? theme.onKeySecondary : theme.candidate.ui)
        row.show(
            text: item.content.preview, styled: title, detail: detail, pinned: item.pinned,
            compact: compact, theme: theme
        )
        row.shown = item.content
    }

    private func configure(_ badge: LinkBadge, _ item: ClipboardHistory.Item, _ name: String) {
        let theme = shown?.theme ?? .lightCurrent
        badge.show(badgeTitle(item, name), theme: theme)
        badge.shown = item.content
        badge.accessibilityIdentifier = "iikb.clip.\(item.content.label)"
        badge.accessibilityLabel =
            "\(name), \(ClipboardHistory.age(of: item.found, now: Date.now.timeIntervalSince1970))"
    }

    private func badgeTitle(_ item: ClipboardHistory.Item, _ name: String) -> NSAttributedString? {
        let theme = shown?.theme ?? .lightCurrent
        let age = ClipboardHistory.age(of: item.found, now: Date.now.timeIntervalSince1970)
        return ClipTitle.badge(
            item.content, name: name, age: age, pinned: item.pinned,
            font: LinkBadge.font(compact: shown?.compact == true),
            label: theme.label.ui, secondary: theme.onKeySecondary)
    }

    private func badgeWidth(_ index: Int) -> CGFloat {
        ceil(badgeTitle(links[index], names[index])?.size().width ?? 0) + 2 * LinkBadge.padding
    }

    /// How many badges stack in a column in one row: as many as fit at least 26 tall.
    private var stacked: Int { max(Int((bounds.height + Self.gap) / (26 + Self.gap)), 1) }

    /// A badge's height in one row: a column's share of it, at most 36.
    private var badgeHeight: CGFloat {
        min(((bounds.height - Self.gap * CGFloat(stacked - 1)) / CGFloat(stacked)).rounded(.down), 36)
    }

    /// The gap between a column's badges in one row, so its first and last sit on the cards' top and bottom edges.
    private var stackGap: CGFloat {
        stacked > 1 ? (bounds.height - CGFloat(stacked) * badgeHeight) / CGFloat(stacked - 1) : Self.gap
    }

    /// A badge's size: one line, as wide as its words up to 200; in one row they stack in columns, each as wide as its
    /// widest.
    private func badgeSize(_ index: Int) -> CGSize {
        guard shown?.compact == true else { return CGSize(width: min(badgeWidth(index), 200), height: 32) }
        let column = (index / stacked * stacked)..<min(index / stacked * stacked + stacked, badges)
        return CGSize(width: min(column.map(badgeWidth).max() ?? 0, 200), height: badgeHeight)
    }

    /// How many link badges show: all of them for the link button; in one row the newest two columns of them, before
    /// the rest; otherwise as many as fit one line above the rows.
    private func fittingBadges() -> Int {
        if shown?.linksOnly == true { return links.count }
        if shown?.compact == true { return min(links.count, 2 * stacked) }
        var used = -Self.gap
        for index in links.indices {
            used += min(badgeWidth(index), 200) + Self.gap
            if used > bounds.width { return max(index, 1) }
        }
        return links.count
    }

    func collectionView(
        _ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        if indexPath.section == 0 { return badgeSize(indexPath.item) }
        return shown?.compact == true
            ? CGSize(width: ((bounds.width - 2 * Self.gap) / 3).rounded(.down), height: bounds.height)
            : CGSize(width: bounds.width, height: 44)
    }

    /// The notice goes ahead of the first section that has anything, and the badges keep a gap from the rows after them.
    func collectionView(
        _ collectionView: UICollectionView, layout: UICollectionViewLayout, insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        let compact = shown?.compact == true
        let ahead = message.isHidden || (badges == 0 && items.isEmpty) ? 0.0 : (compact ? bounds.width + Self.gap : 46)
        let first = section == 0 ? badges > 0 : badges == 0
        let before = first ? ahead : 0
        let after = section == 0 && badges > 0 && !items.isEmpty ? (compact ? Self.gap : 8) : 0
        let stack = CGFloat(stacked) * badgeHeight + CGFloat(stacked - 1) * stackGap
        let middle = section == 0 && compact ? ((bounds.height - stack) / 2).rounded(.down) : 0
        return compact
            ? UIEdgeInsets(top: middle, left: before, bottom: middle, right: after)
            : UIEdgeInsets(top: before, left: 0, bottom: after, right: 0)
    }

    func collectionView(
        _ collectionView: UICollectionView, layout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        section == 0 || shown?.compact == true ? Self.gap : 2
    }

    func collectionView(
        _ collectionView: UICollectionView, layout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat {
        section == 0 ? Self.gap : 0
    }

    func collectionView(
        _ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let item = indexPaths.first.map(item(at:)) else { return nil }
        let room = collectionView.window?.bounds.height ?? .infinity
        return UIContextMenuConfiguration(identifier: nil) { [unowned self] in
            preview(item.content).fitting(room)
        } actionProvider: { [unowned self] _ in
            UIMenu(
                preferredElementSize: .medium,
                children: [
                    UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { _ in self.pick(item) },
                    UIAction(
                        title: item.pinned ? "Unpin" : "Pin",
                        image: UIImage(systemName: item.pinned ? "pin.slash" : "pin")
                    ) { _ in
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
        pick(item(at: indexPath))
    }

    private func thumbnail(_ name: String, for row: ClipRow) {
        if let image = thumbnails.object(forKey: name as NSString) {
            row.thumbnail = image
            return
        }
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
        let compact = shown?.compact == true
        let found = badges > 0 || !items.isEmpty
        message.frame = found ? CGRect(x: 0, y: 0, width: bounds.width, height: compact ? bounds.height : 44) : bounds
        if fitBadges() { list.reloadData() }
        layout.badgeGap = compact ? stackGap : Self.gap
        layout.invalidateLayout()
    }
}

/// The clipboard's flow, with section 0's badges set from the start of their line, as words are, rather than spread
/// across it as a flow layout spreads a line's items.
private final class BadgeFlowLayout: UICollectionViewFlowLayout {
    var badgeGap = 0.0
    private var badges: [IndexPath: UICollectionViewLayoutAttributes] = [:]

    override func prepare() {
        super.prepare()
        badges = [:]
        let across = scrollDirection == .vertical
        let cells =
            (super.layoutAttributesForElements(in: CGRect(origin: .zero, size: collectionViewContentSize)) ?? [])
            .filter { $0.representedElementCategory == .cell && $0.indexPath.section == 0 }
            .sorted { $0.indexPath.item < $1.indexPath.item }
        var line: CGFloat?
        var start: CGFloat?
        var next = 0.0
        for cell in cells {
            guard let attributes = cell.copy() as? UICollectionViewLayoutAttributes else { continue }
            let frame = attributes.frame
            if start == nil { start = across ? frame.minX : frame.minY }
            if line != (across ? frame.midY : frame.midX) {
                line = across ? frame.midY : frame.midX
                next = start ?? 0
            }
            if across { attributes.frame.origin.x = next } else { attributes.frame.origin.y = next }
            next += (across ? frame.width : frame.height) + badgeGap
            badges[attributes.indexPath] = attributes
        }
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        super.layoutAttributesForElements(in: rect)?.map { attributes in
            attributes.representedElementCategory == .cell ? badges[attributes.indexPath] ?? attributes : attributes
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        badges[indexPath] ?? super.layoutAttributesForItem(at: indexPath)
    }
}

/// A copied link in one line: its site's icon, the site's name and how long ago, on a capsule of the key fill.
final class LinkBadge: UICollectionViewCell {
    /// What the badge shows, so an icon that loads late lands only on its own badge.
    var shown: ClipboardHistory.Item.Content?
    static let padding = 10.0
    private let text = UILabel()
    private let backdrop = UIView()
    private var fill = UIColor.clear
    private var pressedFill = UIColor.clear

    override init(frame: CGRect) {
        super.init(frame: frame)
        backdrop.layer.cornerCurve = .continuous
        text.lineBreakMode = .byTruncatingTail
        text.accessibilityIdentifier = "iikb.clip.text"
        [backdrop, text].forEach {
            $0.isUserInteractionEnabled = false
            contentView.addSubview($0)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError() }

    static func font(compact: Bool) -> UIFont { .systemFont(ofSize: compact ? 13 : 14) }

    func show(_ title: NSAttributedString?, theme: KeyboardTheme) {
        fill = theme.shelfCard
        pressedFill = theme.keyPressed.ui
        text.attributedText = title
        setNeedsLayout()
    }

    override var isHighlighted: Bool {
        didSet { backdrop.backgroundColor = isHighlighted ? pressedFill : fill }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = contentView.bounds
        backdrop.layer.cornerRadius = contentView.bounds.height / 2
        backdrop.backgroundColor = isHighlighted ? pressedFill : fill
        text.frame = contentView.bounds.insetBy(dx: Self.padding, dy: 0)
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
        backdrop.layer.cornerCurve = .continuous
        pin.image = UIImage(systemName: "pin.fill")
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
    func show(
        text string: String?, styled: NSAttributedString? = nil, detail: String, pinned: Bool, compact: Bool,
        theme: KeyboardTheme
    ) {
        self.pinned = pinned
        self.compact = compact
        fill = compact ? theme.shelfCard : .clear
        pressedFill = compact ? theme.keyPressed.ui : theme.label.ui.withAlphaComponent(0.12)
        pin.tintColor = compact ? theme.onKeySecondary : theme.candidate.ui
        pin.isHidden = !pinned
        pin.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: compact ? 10 : 13)
        text.textColor = theme.label.ui
        text.font = Self.font(compact: compact)
        text.numberOfLines = 1
        age.textColor = compact ? theme.onKeySecondary : theme.candidate.ui
        age.font = .monospacedDigitSystemFont(ofSize: compact ? 11 : 13, weight: .regular)
        age.text = detail
        age.textAlignment = compact ? .left : .right
        if let styled {
            text.attributedText = styled
        } else {
            text.text = string.map { String($0.prefix(300)).split(whereSeparator: \.isNewline).joined(separator: " ") }
        }
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
        backdrop.layer.cornerRadius = compact ? MenuView.cardRadius : 10
        backdrop.backgroundColor = isHighlighted ? pressedFill : fill
        if compact {
            let inset = bounds.insetBy(dx: 10, dy: 6)
            let room = inset.height - 15
            pin.frame = CGRect(x: inset.maxX - 14, y: inset.maxY - 13, width: 14, height: 13)
            text.numberOfLines = max(Int(room / text.font.lineHeight), 1)
            let fits = ceil(text.sizeThatFits(CGSize(width: inset.width, height: .greatestFiniteMagnitude)).height)
            text.frame = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: min(fits, room))
            image.frame = CGRect(x: inset.minX, y: inset.minY, width: inset.height - 13, height: inset.height - 13)
            age.frame = CGRect(
                x: inset.minX, y: inset.maxY - 13, width: inset.width - (pinned ? 16 : 0), height: 13)
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

extension KeyboardTheme {
    /// Secondary text on the key fill, a card's or a badge's, 4.5:1 or more against it in light and dark.
    var onKeySecondary: UIColor { label.ui.withAlphaComponent(0.62) }
    /// A card's fill on a menu shelf's glass (and on iOS's backdrop, in a panel), letting the glass's tint show through.
    var shelfCard: UIColor { dark ? UIColor(white: 1, alpha: 0.1) : UIColor(white: 1, alpha: 0.7) }
}

extension ClipboardHistory.Item.Content {
    fileprivate var label: String {
        switch self {
        case .text(let text), .textFile(_, let text): String(text.prefix(40))
        case .image(let name): name
        }
    }
}
