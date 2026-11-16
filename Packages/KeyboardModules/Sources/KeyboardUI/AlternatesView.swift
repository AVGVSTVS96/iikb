import KeyboardCore
import UIKit

/// The panel a held key opens, picked by sliding: a key's accents, or the menu of the layer and emoji keys, with the
/// emoji key's emoji in rows above it.
final class AlternatesView: UIView {
    private struct Row {
        var labels: [UILabel]
        var highlightHeight: CGFloat
    }

    private let panel = UIView()
    private let highlight = UIView()
    private var rows: [Row] = []
    private var cellWidth: CGFloat = 0
    private var labels: [UILabel] { rows.flatMap(\.labels) }
    private let padding: CGFloat = 10
    private var labelColor = UIColor.black
    private var selectedLabelColor = UIColor.white
    /// The option picked, counted across the rows, top row first.
    private(set) var selection = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        panel.layer.cornerCurve = .continuous
        panel.layer.shadowOffset = CGSize(width: 0, height: 2)
        panel.layer.shadowRadius = 8
        panel.layer.shadowOpacity = 1
        highlight.layer.cornerCurve = .continuous
        addSubview(panel)
        panel.addSubview(highlight)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `selected` sits right above `key`, so letting go without sliding picks it. An option longer than a character, as
    /// an address's .co.uk, is set in the key labels' size, and every cell widens to fit the longest.
    func show(
        _ options: [String], selected: Int, over key: CGRect, in area: CGRect, metrics: KeyboardMetrics,
        theme: KeyboardTheme
    ) {
        let words = options.contains { $0.count > 1 }
        let font = words ? UIFont.systemFont(ofSize: metrics.labelSize) : KeyboardFont.letter(metrics.letterSize)
        let texts = options.map { NSAttributedString(string: $0, attributes: [.font: font]) }
        let widest = words ? (texts.map { ceil($0.size().width) }.max() ?? 0) + 16 : 0
        let fits = (area.width - 14 - padding * 2) / CGFloat(max(options.count, 1))
        let cell = CGSize(width: min(max(key.width + 4, widest), fits), height: key.height * 1.57)
        present(
            [(texts, cell.height, key.height + 4)], cellWidth: cell.width, selected: selected, over: key, in: area,
            metrics: metrics, theme: theme)
    }

    /// The menu's choices as their symbols, under the emoji key's `emoji` in rows of up to four.
    func show(
        symbols: [String], emoji: [[String]] = [], selected: Int, over key: CGRect, in area: CGRect,
        metrics: KeyboardMetrics, theme: KeyboardTheme
    ) {
        let configuration = UIImage.SymbolConfiguration(pointSize: metrics.symbolSize, weight: .regular)
        let images = symbols.map {
            NSAttributedString(
                attachment: NSTextAttachment(
                    image: UIImage(systemName: $0, withConfiguration: configuration) ?? UIImage()))
        }
        let face = UIFont.systemFont(ofSize: metrics.letterSize * 1.15)
        let height = key.height + 4
        let grid = emoji.map { row in
            (row.map { NSAttributedString(string: $0, attributes: [.font: face]) }, height, height - 4)
        }
        let menu = images.isEmpty ? [] : [(images, key.height + 18, key.height + 2)]
        present(
            grid + menu, cellWidth: 50, selected: selected, over: key,
            in: area, metrics: metrics, theme: theme)
    }

    /// Rows top to bottom, each its options, its height and its highlight's, in cells `cellWidth` wide from the panel's
    /// left, so a row keeps its places whatever the others hold; the panel is as wide as the longest.
    private func present(
        _ contents: [(options: [NSAttributedString], height: CGFloat, highlight: CGFloat)], cellWidth: CGFloat,
        selected: Int, over key: CGRect, in area: CGRect, metrics: KeyboardMetrics, theme: KeyboardTheme
    ) {
        labels.forEach { $0.removeFromSuperview() }
        let columns = CGFloat(contents.map(\.options.count).max() ?? 1)
        let width = cellWidth * columns + padding * 2
        let height = contents.reduce(0) { $0 + $1.height }
        self.cellWidth = cellWidth
        let flat = contents.flatMap(\.options.indices)
        let start = flat.indices.contains(selected) ? flat[selected] : 0
        let x = key.midX - padding - cellWidth * (CGFloat(start) + 0.5)
        frame = CGRect(
            x: min(max(x, area.minX + 7), area.maxX - width - 7), y: max(key.minY - height - 3, area.minY + 1),
            width: width, height: height)
        panel.frame = bounds
        panel.layer.cornerRadius = metrics.cornerRadius * 2
        panel.layer.shadowPath = UIBezierPath(roundedRect: panel.bounds, cornerRadius: panel.layer.cornerRadius).cgPath
        panel.backgroundColor = theme.bubble.ui
        panel.layer.shadowColor = theme.shadow.ui.cgColor
        highlight.backgroundColor = theme.selection.ui
        highlight.layer.cornerRadius = metrics.cornerRadius * 1.25
        labelColor = theme.bubbleLabel.ui
        selectedLabelColor = theme.selectionLabel.ui
        var top: CGFloat = 0
        rows = contents.map { row in
            let labels = row.options.enumerated().map { index, content in
                let label = UILabel(
                    frame: CGRect(x: padding + CGFloat(index) * cellWidth, y: top, width: cellWidth, height: row.height)
                )
                label.attributedText = content
                label.textAlignment = .center
                panel.addSubview(label)
                return label
            }
            top += row.height
            return Row(labels: labels, highlightHeight: row.highlight)
        }
        isHidden = false
        select(selected)
    }

    /// Where the selected option's middle is, in the superview's coordinates.
    var selectedMidX: CGFloat { frame.minX + (labels.indices.contains(selection) ? labels[selection].frame.midX : 0) }

    /// Picks the option under `point`: the row it's level with, the top or bottom one past the panel's edges, and the
    /// cell it's over in that row.
    func track(_ point: CGPoint) {
        guard !rows.isEmpty else { return }
        let y = point.y - frame.minY
        let row = rows.lastIndex { ($0.labels.first?.frame.minY ?? 0) <= y } ?? 0
        let cells = rows[row].labels
        guard !cells.isEmpty else { return }
        let column = min(max(Int((point.x - frame.minX - padding) / cellWidth), 0), cells.count - 1)
        select(rows[..<row].reduce(0) { $0 + $1.labels.count } + column)
    }

    func hide() {
        isHidden = true
        labels.forEach { $0.removeFromSuperview() }
        rows = []
    }

    private func select(_ index: Int) {
        let labels = labels
        guard labels.indices.contains(index) else { return }
        selection = index
        for (other, label) in labels.enumerated() {
            label.textColor = other == index ? selectedLabelColor : labelColor
        }
        let cell = labels[index].frame
        let height = rows.first { $0.labels.contains(labels[index]) }?.highlightHeight ?? cell.height
        highlight.frame = CGRect(x: cell.minX, y: cell.midY - height / 2, width: cell.width, height: height)
    }
}
