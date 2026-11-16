import KeyboardCore
import KeyboardUI
import UIKit

/// Text Styles or Change Case (docs/design.md, "Text Styles"): each style or case showing what it would make of the text
/// it acts on (`TypingEngine.rewriting`, `preview`), or its own name while there's none, in the clipboard's rows. A tap
/// writes it in that text's place, and the rows show the new text, so another tap changes it again.
final class RewritePanel: UIView, PanelContent, UICollectionViewDataSource, UICollectionViewDelegate {
    var target: () -> String = { "" }
    var preview: (Rewrite) -> String = { $0.title }
    var onPick: (Rewrite) -> Void = { _ in }
    let field: PanelField

    private struct Shown: Equatable {
        var query: String
        var target: String
        var compact: Bool
        var theme: KeyboardTheme
    }

    private let panel: Panel
    private var rewrites: [Rewrite] = []
    private var shown: Shown?
    private let layout = UICollectionViewFlowLayout()
    private lazy var list = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let message = PanelNotice()

    init(_ panel: Panel, placeholder: String) {
        self.panel = panel
        field = .search(.init(placeholder, glyph: panel.icon(20)))
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
        list.register(ClipRow.self, forCellWithReuseIdentifier: "rewrite")
        list.addSubview(message)
        addSubview(list)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        shown = nil
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        let next = Shown(query: query, target: target(), compact: metrics.toolbar.isCompact, theme: theme)
        guard next != shown else { return }
        let moved = query != shown?.query
        shown = next
        rewrites = panel.rewrites(matching: query)
        message.show(
            rewrites.isEmpty ? "Nothing called “\(query)”" : nil, turnOn: false, oneRow: next.compact, theme: theme)
        layout.scrollDirection = next.compact ? .horizontal : .vertical
        list.reloadData()
        setNeedsLayout()
        if moved { list.contentOffset = .zero }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        rewrites.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    {
        let row = collectionView.dequeueReusableCell(withReuseIdentifier: "rewrite", for: indexPath) as! ClipRow
        let rewrite = rewrites[indexPath.item]
        let target = shown?.target ?? ""
        row.show(
            text: target.isEmpty ? rewrite.title : String(preview(rewrite).prefix(300)), detail: rewrite.name,
            pinned: false, compact: shown?.compact == true, theme: shown?.theme ?? .lightCurrent)
        row.accessibilityIdentifier = "iikb.rewrite.\(rewrite.name)"
        return row
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onPick(rewrites[indexPath.item])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        list.frame = bounds
        message.frame = bounds
        let compact = shown?.compact == true
        let gap = 6.0
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
