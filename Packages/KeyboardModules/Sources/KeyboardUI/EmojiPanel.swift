import KeyboardCore
import KeyboardEnglish
import UIKit

/// Apple's emoji keyboard under its search field (docs/design.md, "Emoji"). In the keys' place, `browsing`, every emoji
/// in pages by category scrolling sideways, what you pick most first, over ABC, the categories and delete; with the keys
/// up, one row of what the search finds.
public final class EmojiPanel: UIView, PanelContent, UICollectionViewDataSource, UICollectionViewDelegate {
    /// An emoji tapped, or picked among its skin tones with its untoned version.
    public var onPick: (String, String?) -> Void = { _, _ in }
    /// Delete going down and up, as the keys send it.
    public var onKey: (KeyboardEvent) -> Void = { _ in }
    public var onLetters: () -> Void = {}
    public var onCategory: () -> Void = {}
    /// What you've picked, read as the pages open and as the search changes, so emoji never move under your finger.
    public var history: () -> EmojiHistory = { EmojiHistory() }
    /// In the keys' place, as the emoji keyboard, rather than a row of results over the keys.
    public var browsing = false
    public var field: PanelField { .search(.init("Search Emoji")) }

    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: pagesLayout())
    private let empty = UILabel()
    private var sections: [(category: EmojiCategory?, emoji: [String])] = []
    private var shown: (browsing: Bool, query: String)?
    private var theme = KeyboardTheme.lightCurrent
    private var metrics = KeyboardMetrics.phone(width: 390)
    private let letters = RowKey(Key(.layer(.letters)), face: KeyFace(content: .text("ABC")), name: "ABC")
    private let delete = RowKey(Key(.delete), face: KeyFace(content: .symbol("delete.left")), name: "Delete")
    private let categories = EmojiCategory.allCases.map { CategoryButton($0) }
    private var current = EmojiCategory.recents
    private let tones = AlternatesView()
    private var held: [String] = []
    /// How far the finger sat from the tone it started on, so letting go without sliding picks that tone.
    private var slide: CGFloat = 0

    private static let header = "header"
    private static let headerHeight: CGFloat = 22
    /// The shortest a page's row gets, so the folded Duo's pages hold four rows, as Function's do.
    private static let leastRow: CGFloat = 36
    private static let row = CGSize(width: 43, height: 41)
    private static let rowSpacing: CGFloat = 10

    override public init(frame: CGRect) {
        super.init(frame: frame)
        grid.backgroundColor = .clear
        grid.showsHorizontalScrollIndicator = false
        grid.dataSource = self
        grid.delegate = self
        grid.delaysContentTouches = false
        grid.accessibilityIdentifier = "iikb.emoji"
        [grid.topEdgeEffect, grid.bottomEdgeEffect, grid.leftEdgeEffect, grid.rightEdgeEffect].forEach {
            $0.isHidden = true
        }
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: "emoji")
        grid.register(
            EmojiHeader.self, forSupplementaryViewOfKind: Self.header, withReuseIdentifier: Self.header)
        grid.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(hold)))
        empty.font = .systemFont(ofSize: 15)
        empty.textAlignment = .center
        empty.isHidden = true
        letters.addAction(UIAction { [unowned self] _ in onLetters() }, for: .touchUpInside)
        delete.addAction(UIAction { [unowned self] _ in onKey(.down(Key(.delete), tapCount: 1)) }, for: .touchDown)
        delete.addAction(
            UIAction { [unowned self] _ in onKey(.up(Key(.delete))) },
            for: [.touchUpInside, .touchUpOutside, .touchCancel])
        for button in categories {
            button.addAction(UIAction { [unowned self] _ in jump(to: button.category) }, for: .touchUpInside)
        }
        tones.isHidden = true
        clipsToBounds = false
        ([grid, empty, letters, delete] + categories + [tones]).forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func reset() {
        shown = nil
    }

    public func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        self.metrics = metrics
        if theme != self.theme {
            self.theme = theme
            empty.textColor = theme.candidate.ui
            grid.reloadData()
        }
        [letters, delete].forEach { $0.show(theme: theme, metrics: metrics) }
        categories.forEach { $0.show(selected: $0.category == current, theme: theme) }
        guard shown.map({ $0 != (browsing, browsing ? "" : query) }) ?? true else { return }
        let modeChanged = shown?.browsing != browsing
        shown = (browsing, browsing ? "" : query)
        if browsing {
            sections = EmojiSearch.english.pages(history: history()).map { ($0.category, $0.emoji) }
        } else {
            sections = [(nil, EmojiSearch.english.search(query, history: history()))]
        }
        empty.text = "No emoji for “\(query.trimmingCharacters(in: .whitespaces))”"
        empty.isHidden = browsing || !sections[0].emoji.isEmpty
        ([letters, delete] + categories).forEach { $0.isHidden = !browsing }
        if modeChanged {
            grid.setCollectionViewLayout(browsing ? pagesLayout() : rowLayout(), animated: false)
            setNeedsLayout()
        }
        grid.reloadData()
        grid.contentOffset = .zero
        select(.recents)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        guard browsing else {
            grid.frame = bounds
            empty.frame = bounds
            return
        }
        let keys = EmojiKeys(
            width: bounds.width, height: bounds.height, minX: 0, maxX: bounds.width, bottomInset: metrics.bottomInset)
        let pages = CGRect(keys.pages)
        let row = (top: pages.maxY, height: bounds.height - pages.maxY)
        letters.place(CGRect(keys.letters), top: row.top, height: row.height)
        delete.place(CGRect(keys.delete), top: row.top, height: row.height)
        let area = CGRect(keys.categories)
        let slot = area.width / CGFloat(categories.count)
        for (index, button) in categories.enumerated() {
            button.frame = CGRect(x: area.minX + slot * CGFloat(index), y: area.minY, width: slot, height: area.height)
                .insetBy(dx: 0, dy: row.top - area.minY)
        }
        if grid.frame != pages {
            grid.frame = pages
            grid.collectionViewLayout.invalidateLayout()
        }
    }

    /// Pages of emoji, each a category under its heading, in columns of as many rows as fit, scrolling sideways.
    private func pagesLayout() -> UICollectionViewLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal
        configuration.interSectionSpacing = 8
        return UICollectionViewCompositionalLayout(
            sectionProvider: { _, environment in
                let height = environment.container.contentSize.height - Self.headerHeight
                let rows = max((height / Self.leastRow).rounded(.down), 1)
                let cell = height / rows
                let item = NSCollectionLayoutItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(cell)))
                let column = NSCollectionLayoutGroup.vertical(
                    layoutSize: .init(
                        widthDimension: .absolute(cell + 3),
                        heightDimension: .absolute(environment.container.contentSize.height)),
                    repeatingSubitem: item, count: Int(rows))
                column.contentInsets.top = Self.headerHeight
                let section = NSCollectionLayoutSection(group: column)
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(widthDimension: .estimated(160), heightDimension: .absolute(Self.headerHeight)),
                    elementKind: Self.header, alignment: .topLeading)
                header.extendsBoundary = false
                header.pinToVisibleBounds = true
                section.boundarySupplementaryItems = [header]
                return section
            }, configuration: configuration)
    }

    /// One row of results scrolling sideways, as Apple's search shows them.
    private func rowLayout() -> UICollectionViewLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal
        return UICollectionViewCompositionalLayout(
            sectionProvider: { _, _ in
                let item = NSCollectionLayoutItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(
                        widthDimension: .absolute(Self.row.width), heightDimension: .absolute(Self.row.height)),
                    subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = Self.rowSpacing
                return section
            }, configuration: configuration)
    }

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].emoji.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath) as! EmojiCell
        cell.show(emoji(at: indexPath), pressed: theme.label.ui.withAlphaComponent(0.12))
        return cell
    }

    public func collectionView(
        _ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header =
            collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: Self.header, for: indexPath) as! EmojiHeader
        header.show(sections[indexPath.section].category?.title ?? "", theme: theme)
        return header
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onPick(emoji(at: indexPath), nil)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard browsing, !sections.isEmpty else { return }
        let end = scrollView.contentSize.width - scrollView.bounds.width
        let x = scrollView.contentOffset.x
        let reached = sections.indices.last { start(of: $0) <= x + 1 } ?? 0
        let section = x >= end - 1 && end > 0 ? sections.count - 1 : reached
        if let category = sections[section].category { select(category) }
    }

    private func emoji(at indexPath: IndexPath) -> String {
        sections[indexPath.section].emoji[indexPath.item]
    }

    private func start(of section: Int) -> CGFloat {
        guard !sections[section].emoji.isEmpty else { return .infinity }
        return grid.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: section))?.frame.minX
            ?? .infinity
    }

    /// A category's tap shows its page from its start, as far as the pages scroll.
    private func jump(to category: EmojiCategory) {
        guard let section = sections.firstIndex(where: { $0.category == category }) else { return }
        onCategory()
        grid.layoutIfNeeded()
        let end = max(grid.contentSize.width - grid.bounds.width, 0)
        grid.setContentOffset(CGPoint(x: min(max(start(of: section), 0), end), y: 0), animated: false)
        select(category)
    }

    private func select(_ category: EmojiCategory) {
        current = category
        categories.forEach { $0.show(selected: $0.category == category, theme: theme) }
    }

    /// Holding an emoji that comes in skin tones offers them above it, picked by sliding, like a key's accents.
    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard let indexPath = grid.indexPathForItem(at: gesture.location(in: grid)),
                let cell = grid.cellForItem(at: indexPath),
                let base = EmojiSearch.english.base(of: emoji(at: indexPath)),
                let toned = EmojiSearch.english.tones[base]
            else {
                gesture.state = .failed
                return
            }
            held = [base] + toned
            let area = superview.map { convert($0.bounds, from: $0) } ?? bounds
            tones.show(
                held, selected: held.firstIndex(of: emoji(at: indexPath)) ?? 0,
                over: cell.convert(cell.bounds, to: self), in: area, metrics: metrics, theme: theme)
            slide = tones.selectedMidX - point.x
        case .changed:
            tones.track(CGPoint(x: point.x + slide, y: point.y))
        case .ended:
            if held.indices.contains(tones.selection) { onPick(held[tones.selection], held[0]) }
            fallthrough
        default:
            tones.hide()
            held = []
        }
    }
}

/// ABC or delete in the emoji keyboard's row: a key drawn as the keyboard's are, taking touches over the row's height.
private final class RowKey: UIControl {
    private let key: KeyView
    private let face: KeyFace

    init(_ key: Key, face: KeyFace, name: String) {
        self.key = KeyView(key: key)
        self.face = face
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        accessibilityLabel = name
        accessibilityIdentifier = "iikb.emoji.\(name.lowercased())"
        addSubview(self.key)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { key.isPressed = isHighlighted }
    }

    func show(theme: KeyboardTheme, metrics: KeyboardMetrics) {
        key.theme = theme
        key.configure(face, metrics: metrics)
    }

    /// The key at `frame`, taking touches across its row, from `top` and `height` tall.
    func place(_ frame: CGRect, top: CGFloat, height: CGFloat) {
        self.frame = CGRect(x: frame.minX, y: top, width: frame.width, height: height)
        key.frame = frame.offsetBy(dx: -frame.minX, dy: -top)
    }
}

/// A category's glyph in the emoji keyboard's row, on a round platter while its page shows.
private final class CategoryButton: UIControl {
    let category: EmojiCategory
    private let glyph = UIImageView()
    private let platter = UIView()

    init(_ category: EmojiCategory) {
        self.category = category
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = category.title
        accessibilityIdentifier = "iikb.emoji.category.\(category)"
        platter.isUserInteractionEnabled = false
        glyph.contentMode = .center
        glyph.image = Panel.symbol(Self.symbols[category] ?? "", 20)
        [platter, glyph].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let symbols: [EmojiCategory: String] = [
        .recents: "clock", .people: "face.smiling", .nature: "leaf", .food: "fork.knife", .activity: "soccerball",
        .travel: "car", .objects: "lightbulb", .symbols: "heart", .flags: "flag",
    ]

    override var isHighlighted: Bool {
        didSet { glyph.alpha = isHighlighted ? 0.5 : 1 }
    }

    func show(selected: Bool, theme: KeyboardTheme) {
        isSelected = selected
        platter.isHidden = !selected
        platter.backgroundColor = theme.label.ui.withAlphaComponent(0.1)
        glyph.tintColor = selected ? theme.label.ui : theme.candidate.ui
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, 32)
        platter.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        platter.layer.cornerRadius = side / 2
        glyph.frame = bounds
    }
}

private final class EmojiHeader: UICollectionReusableView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ title: String, theme: KeyboardTheme) {
        label.text = title.uppercased()
        label.textColor = theme.candidate.ui
        setNeedsLayout()
    }

    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes)
        -> UICollectionViewLayoutAttributes
    {
        let fitted = super.preferredLayoutAttributesFitting(attributes)
        fitted.size.width = ceil(label.sizeThatFits(.zero).width) + 8
        return fitted
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 4, y: 0, width: bounds.width - 8, height: bounds.height)
    }
}

private final class EmojiCell: UICollectionViewCell {
    private let label = UILabel()
    private let backdrop = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backdrop.layer.cornerRadius = 8
        backdrop.layer.cornerCurve = .continuous
        backdrop.isHidden = true
        label.textAlignment = .center
        contentView.addSubview(backdrop)
        contentView.addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ emoji: String, pressed: UIColor) {
        label.text = emoji
        backdrop.backgroundColor = pressed
        accessibilityLabel = emoji
        accessibilityIdentifier = "iikb.emoji.\(emoji)"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
        label.font = .systemFont(ofSize: (min(bounds.width, bounds.height) * 0.78).rounded())
        backdrop.frame = contentView.bounds.insetBy(dx: 1, dy: 1)
    }

    override var isHighlighted: Bool {
        didSet { backdrop.isHidden = !isHighlighted }
    }
}
