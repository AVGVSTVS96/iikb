import KeyboardCore
import KeyboardStore
import KeyboardUI
import UIKit

/// Your snippets or quicklinks as you made them in the app (docs/design.md, "Snippets and Quicklinks"), in the
/// clipboard's rows: a snippet's name and keyword, a quicklink's name and site. A tap types one, asking for its
/// arguments first; holding one shows all of it with Copy, a quicklink's Open, and Edit, which opens it in the app. The
/// search finds one by any of its words. The snippets' field holds Create Snippet, which keeps what you've written.
final class SnippetsPanel: UIView, PanelContent, UICollectionViewDataSource, UICollectionViewDelegate {
    /// A snippet or quicklink as a row shows it.
    struct Item {
        var id: String
        var name: String
        /// The keyword, or the link's site.
        var detail: String
        /// What it types, as its preview shows it.
        var text: String
        /// Everything the search looks in.
        var words: [String]
    }

    var items: () -> [Item] = { [] }
    var fullAccess: () -> Bool = { false }
    var onPick: (String) -> Void = { _ in }
    /// Opens a quicklink by its id.
    var onOpen: ((String) -> Void)?
    /// Opens a snippet or quicklink in the app by its id, or the page that lists them.
    var onEdit: (String?) -> Void = { _ in }
    /// Starts Create Snippet, or says why it can't.
    var onCreate: (() -> Refusal?)?

    enum Refusal: String {
        case fullAccess = "Keeping a snippet needs Full Access."
        case empty = "Type or select the text to keep first."
    }

    var onTurnOn: () -> Void = {}
    var field: PanelField {
        .search(
            .init(
                isSnippets ? "Search snippets" : "Search quicklinks", glyph: UIImage(systemName: panel.symbol),
                accessories: onCreate == nil ? [] : [create]))
    }

    private let panel: Panel
    private var isSnippets: Bool { panel == .snippets }
    private var listed: [Item] = []
    private var shown: Shown?
    /// Why Create Snippet, just tapped, can't start, shown in the list's place until the search moves.
    private var refused: Refusal?
    private let layout = UICollectionViewFlowLayout()
    private lazy var list = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let message = PanelNotice()
    private let create = UIButton(type: .custom)

    private struct Shown: Equatable {
        var query: String
        var compact: Bool
        var theme: KeyboardTheme
    }

    init(_ panel: Panel) {
        self.panel = panel
        super.init(frame: .zero)
        list.backgroundColor = .clear
        list.showsVerticalScrollIndicator = false
        list.showsHorizontalScrollIndicator = false
        list.delaysContentTouches = false
        list.dataSource = self
        list.delegate = self
        list.accessibilityIdentifier = "iikb.\(panel)"
        [list.topEdgeEffect, list.bottomEdgeEffect, list.leftEdgeEffect, list.rightEdgeEffect].forEach {
            $0.isHidden = true
        }
        list.register(ClipRow.self, forCellWithReuseIdentifier: "item")
        message.accessibilityIdentifier = "iikb.\(panel).message"
        message.onTurnOn = { [unowned self] in refused == .fullAccess ? onTurnOn() : onEdit(nil) }
        list.addSubview(message)
        addSubview(list)
        create.accessibilityIdentifier = "iikb.snippets.create"
        create.accessibilityLabel = "Create Snippet"
        create.setImage(
            UIImage(
                systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)),
            for: .normal)
        create.addAction(
            UIAction { [unowned self] _ in
                refused = onCreate?()
                if refused != nil { refresh() }
            }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        shown = nil
        refused = nil
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        let next = Shown(query: query, compact: metrics.toolbar.isCompact, theme: theme)
        create.tintColor = theme.candidate.ui
        guard next != shown else { return }
        let moved = query != shown?.query
        shown = next
        if moved { refused = nil }
        refresh()
        if moved { list.contentOffset = .zero }
    }

    private func refresh() {
        guard let shown else { return }
        let words = shown.query.lowercased().split(separator: " ")
        let all = items()
        listed = all.filter { item in
            words.allSatisfy { word in item.words.contains { $0.lowercased().contains(word) } }
        }
        let kind = isSnippets ? "snippet" : "quicklink"
        let empty: String? =
            !listed.isEmpty ? nil : all.isEmpty ? "Your \(kind)s show here." : "No \(kind) with “\(shown.query)”"
        if let refused {
            message.show(
                refused.rawValue, turnOn: refused == .fullAccess, oneRow: shown.compact, theme: shown.theme)
        } else {
            message.show(
                empty, turnOn: all.isEmpty, action: isSnippets ? "Add Snippet" : "Add Quicklink",
                oneRow: shown.compact, theme: shown.theme)
        }
        list.isScrollEnabled = refused == nil
        layout.scrollDirection = shown.compact ? .horizontal : .vertical
        list.reloadData()
        setNeedsLayout()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        refused == nil ? listed.count : 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    {
        let row = collectionView.dequeueReusableCell(withReuseIdentifier: "item", for: indexPath) as! ClipRow
        let item = listed[indexPath.item]
        row.show(
            text: item.name, detail: item.detail, pinned: false, compact: shown?.compact == true,
            theme: shown?.theme ?? .lightCurrent)
        row.accessibilityIdentifier = "iikb.\(panel).\(indexPath.item)"
        return row
    }

    func collectionView(
        _ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let item = indexPaths.first.map({ listed[$0.item] }) else { return nil }
        let room = collectionView.window?.bounds.height ?? .infinity
        let heading = NSAttributedString(
            string: item.name, attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)])
        let encode = isSnippets ? { $0 } : Template.percentEncoded
        let copy = UIAction(title: "Copy", image: UIImage(systemName: "square.on.square")) { _ in
            UIPasteboard.general.string = Template(item.text).filled(encode: encode).text
        }
        let open = onOpen.map { open in
            UIAction(title: "Open", image: UIImage(systemName: "safari")) { _ in open(item.id) }
        }
        let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { [unowned self] _ in
            onEdit(item.id)
        }
        return UIContextMenuConfiguration(identifier: nil) {
            ClipPreview(text: item.text, heading: heading).fitting(room)
        } actionProvider: { [unowned self] _ in
            UIMenu(
                preferredElementSize: .medium,
                children: (fullAccess() ? [copy] : []) + (open.map { [$0] } ?? []) + [edit])
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onPick(listed[indexPath.item].id)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        list.frame = bounds
        let compact = shown?.compact == true
        let gap = 6.0
        message.frame = bounds
        layout.sectionInset = .zero
        layout.minimumLineSpacing = compact ? gap : 2
        layout.minimumInteritemSpacing = 0
        let size =
            compact
            ? CGSize(width: ((bounds.width - 2 * gap) / 3).rounded(.down), height: bounds.height)
            : CGSize(width: bounds.width, height: 44)
        if layout.itemSize != size { layout.itemSize = size }
        layout.invalidateLayout()
    }
}

extension SnippetsPanel.Item {
    init(_ snippet: Snippet) {
        self.init(
            id: snippet.id, name: snippet.name, detail: snippet.keyword, text: snippet.text,
            words: [snippet.name, snippet.keyword, snippet.text, snippet.tag])
    }

    init(_ link: Quicklink) {
        var site = Substring(link.link)
        if let scheme = site.range(of: "://") { site = site[scheme.upperBound...] }
        site = site.prefix { $0 != "/" && $0 != "?" }
        if site.hasPrefix("www.") { site = site.dropFirst(4) }
        self.init(id: link.id, name: link.name, detail: String(site), text: link.link, words: [link.name, link.link])
    }
}

extension Panel {
    /// The glyph in the panel's search field.
    fileprivate var symbol: String { self == .snippets ? "text.quote" : "link" }
}
