import KeyboardCore
import KeyboardStore
import KeyboardUI
import SwiftUI

/// What you copied, as the keyboard's clipboard panel keeps it (`ClipboardStore`, in the App Group): links on top as
/// one-line badges, then the rest pinned first, then by day, newest first. A tap copies an item again; holding it pins,
/// shares or deletes it. Wide, the item last tapped
/// shows in full in the second pane, as Transcripts' picked one does.
struct ClipboardPage: View {
    @State private var store = ClipboardStore()
    @State private var items: [ClipboardHistory.Item] = []
    @State private var query = ""
    @State private var matches: [ClipboardHistory.Item] = []
    @State private var copied: ClipboardHistory.Item.Content?
    @State private var picked: ClipboardHistory.Item.Content?
    @State private var linksOnly = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.arrangement) private var arrangement
    private let status = AppStatus.shared

    private var found: [ClipboardHistory.Item] { query.trimmingCharacters(in: .whitespaces).isEmpty ? items : matches }

    /// The links found: all of them under Links, the six newest under All.
    private var links: [ClipboardHistory.Item] {
        let links = found.filter(\.isLink)
        return linksOnly ? links : Array(links.prefix(6))
    }

    /// Everything else found, in rows; none under Links.
    private var shown: [ClipboardHistory.Item] { linksOnly ? [] : found.filter { !$0.isLink } }

    private var groups: [(title: String, items: [ClipboardHistory.Item])] {
        let calendar = Calendar.current
        var groups: [(day: Date?, items: [ClipboardHistory.Item])] = []
        for item in shown {
            let day = item.pinned ? nil : calendar.startOfDay(for: Date(timeIntervalSince1970: item.found))
            if let last = groups.last, last.day == day {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((day, [item]))
            }
        }
        return groups.map { ($0.day.map(TranscriptsPage.title) ?? "Pinned", $0.items) }
    }

    private var beside: Bool { arrangement == .side }

    /// The item shown in the second pane: the one last tapped, or the newest.
    private var shownInFull: ClipboardHistory.Item? {
        items.first { $0.content == picked } ?? items.first { !$0.pinned } ?? items.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if beside {
                    Panes(list: true) {
                        list
                    } second: {
                        if let item = shownInFull {
                            ClipDetail(
                                item: item, copied: item.content == copied, store: store, copy: { copy(item) },
                                changed: refresh)
                        } else {
                            empty
                        }
                    }
                } else {
                    list
                }
            }
            .appPage()
            .navigationTitle("Clipboard")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar { MicSwitchItem() }
        }
        .task(id: query) { await search() }
        .onAppear(perform: catchUp)
        .onChange(of: scenePhase) { _, phase in if phase == .active { catchUp() } }
        .sensoryFeedback(.success, trigger: copied) { _, new in new != nil }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let missing { setup(missing) }
                if items.isEmpty {
                    empty.frame(minHeight: 360)
                } else {
                    SearchField(text: $query)
                    if shown.isEmpty, links.isEmpty {
                        if linksOnly, query.trimmingCharacters(in: .whitespaces).isEmpty {
                            ContentUnavailableView(
                                "No Links Yet", systemImage: "link", description: Text("Links you copy show up here."))
                        } else {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                    if !links.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Links")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.appSecondary)
                                .padding(.horizontal, 20)
                                .accessibilityAddTraits(.isHeader)
                            Flow(spacing: 8) {
                                let names = ClipLink.names(links.compactMap(\.link))
                                ForEach(Array(zip(links, names)), id: \.0.id) { badge($0, name: $1) }
                            }
                        }
                    }
                    ForEach(groups, id: \.title) { group in
                        Box(header: group.title) {
                            ForEach(group.items) { row($0) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .frame(maxWidth: Arrangement.wide)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollsToEndAtLaunch()
        .safeAreaInset(edge: .top, spacing: 0) {
            if !items.isEmpty {
                SectionPills(sections: [false, true], selection: $linksOnly) { $0 ? "Links" : "All" }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .frame(maxWidth: Arrangement.wide)
                    .frame(maxWidth: .infinity)
                    .background(Color.appPage)
            }
        }
    }

    /// Keeps what's on the clipboard now, as the keyboard would, once the keyboard has started the history and iOS lets
    /// iikb read the clipboard without asking.
    private func catchUp() {
        copied = nil
        store.onChange = { refresh() }
        if store.started, status.fullAccess, status.pasteAllowed { store.catchUp() } else { store.reload() }
        refresh()
    }

    private func refresh() {
        items = store.history.items
        Task { await search() }
        if let copied, !items.contains(where: { $0.content == copied }) { self.copied = nil }
    }

    private func search() async {
        let query = query
        let found = await store.matching(query.trimmingCharacters(in: .whitespaces))
        guard query == self.query else { return }
        matches = found
    }

    private var missing: String? {
        if !status.fullAccess { return "Turn on Allow Full Access, so the keyboard can keep what you copy." }
        if !status.pasteAllowed { return "Set Paste from Other Apps to Allow, so the keyboard can keep what you copy." }
        return nil
    }

    private func setup(_ text: String) -> some View {
        Box {
            Button {
                Router.shared.show(.settings, settings: .access)
            } label: {
                HStack {
                    RowText(title: "Keyboard Access", detail: text)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                }
                .row()
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ item: ClipboardHistory.Item) -> some View {
        Button {
            copy(item)
        } label: {
            ClipRow(item: item, copied: item.content == copied, thumbnail: { store.thumbnail($0, side: 128) })
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .background(beside && item.content == shownInFull?.content ? Color.appPicked : .clear)
        .contextMenu { actions(item) }
    }

    private func badge(_ item: ClipboardHistory.Item, name: String) -> some View {
        Button {
            copy(item)
        } label: {
            LinkBadge(
                item: item, name: name, copied: item.content == copied,
                picked: beside && item.content == shownInFull?.content)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .contextMenu { actions(item) }
    }

    @ViewBuilder private func actions(_ item: ClipboardHistory.Item) -> some View {
        Button("Copy", systemImage: "doc.on.doc") { copy(item) }
        if case .link = item.content.kind,
            let url = URL(string: item.content.preview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        {
            Link(destination: url) { Label("Open", systemImage: "safari") }
        }
        if case .text(let text) = item.content { ShareLink(item: text) }
        if case .textFile(let name, _) = item.content { ShareLink(item: store.file(name)) }
        Button(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin") {
            store.setPinned(!item.pinned, item.content)
            refresh()
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            store.remove(item.content)
            refresh()
        }
    }

    /// Puts an item back on the clipboard. It's already in the history, so the store skips it rather than keeping it again.
    private func copy(_ item: ClipboardHistory.Item) {
        switch item.content {
        case .text(let text):
            UIPasteboard.general.string = text
            store.skip(changeCount: UIPasteboard.general.changeCount)
        case .textFile:
            Task {
                guard let text = await store.text(item.content) else { return }
                UIPasteboard.general.string = text
                store.skip(changeCount: UIPasteboard.general.changeCount)
                copied = item.content
            }
            picked = item.content
            return
        case .image(let name):
            store.copy(image: name)
        }
        copied = item.content
        picked = item.content
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Nothing Copied Yet", systemImage: "list.clipboard")
        } description: {
            Text(
                store.started
                    ? "Everything you copy shows up here and in the keyboard’s clipboard, kept on this \(ThisDevice.name)."
                    : "Type with iikb in any app, and what it keeps of what you copy shows up here.")
        }
    }
}

/// One item in full, in the second pane: all its text, or its image as big as the pane, and what holding its row offers.
private struct ClipDetail: View {
    let item: ClipboardHistory.Item
    let copied: Bool
    let store: ClipboardStore
    let copy: () -> Void
    let changed: () -> Void
    @State private var fullText: String?

    private var time: String {
        Date(timeIntervalSince1970: item.found).formatted(
            .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
    }

    /// When it was copied, and how long all of it is, once a text kept in a file is read.
    private var detail: String {
        let unit = SettingsModel.shared.settings.clipboardLength
        let length =
            fullText.map { ClipboardHistory.length(of: $0, in: unit) }
            ?? ClipboardHistory.length(of: item.content, in: unit)
        return length.map { "\(time) · \($0)" } ?? time
    }

    private var share: some View {
        Image(systemName: "square.and.arrow.up").frame(width: 34, height: 34).accessibilityLabel("Share")
    }

    var body: some View {
        Column(top: 4, fills: true) {
            HStack(spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    Text(detail).lineLimit(1)
                    Text(time).lineLimit(1)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.appSecondary)
                Spacer(minLength: 8)
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(copied ? Color.copied : .primary)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel(copied ? "Copied" : "Copy")
                if case .link = item.content.kind,
                    let url = URL(string: item.content.preview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                {
                    Link(destination: url) { Image(systemName: "safari").frame(width: 34, height: 34) }
                        .accessibilityLabel("Open")
                }
                Group {
                    if case .textFile(let name, _) = item.content { ShareLink(item: store.file(name)) { share } }
                    if case .text(let text) = item.content { ShareLink(item: text) { share } }
                }
                Button {
                    store.setPinned(!item.pinned, item.content)
                    changed()
                } label: {
                    Image(systemName: item.pinned ? "pin.fill" : "pin").frame(width: 34, height: 34)
                }
                .accessibilityLabel(item.pinned ? "Unpin" : "Pin")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            Group {
                switch item.content {
                case .text(let text), .textFile(_, let text):
                    VStack(alignment: .leading, spacing: 10) {
                        if case .link(let link) = item.content.kind {
                            HStack(spacing: 10) {
                                SiteIcon(site: link.site, side: 28)
                                Text(link.site).font(.title3.weight(.semibold))
                            }
                        }
                        Text((fullText ?? text).trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(item.content.kind == .text ? .title3 : .body)
                            .foregroundStyle(item.content.kind == .text ? Color.primary : Color.appSecondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .frame(maxHeight: .infinity, alignment: .top)
                case .image(let name):
                    FullImage(file: store.file(name))
                }
            }
            .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
            .clipShape(.rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
            Box {
                ActionRow(title: "Delete Item", role: .destructive) {
                    store.remove(item.content)
                    changed()
                }
            }
        }
        .task(id: item.content) {
            fullText = nil
            let text = await store.text(item.content)
            guard !Task.isCancelled else { return }
            fullText = text
        }
    }
}

/// An image as big as the pane, decoded off the main thread.
private struct FullImage: View {
    let file: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.clear.aspectRatio(4 / 3, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Image")
        .task(id: file) {
            let file = file
            image = await Task.detached { ClipboardStore.thumbnail(of: file, side: 1600) }.value
        }
    }
}

private struct ClipRow: View {
    let item: ClipboardHistory.Item
    let copied: Bool
    let thumbnail: (String) -> UIImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                switch item.content {
                case .text(let text), .textFile(_, let text):
                    ClipTitle(content: item.content, text: text)
                case .image(let name):
                    if let image = thumbnail(name) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: 8, style: .continuous))
                            .accessibilityLabel("Image")
                    }
                }
                Group {
                    if copied {
                        Label("Copied", systemImage: "checkmark")
                    } else {
                        let time = Date(timeIntervalSince1970: item.found).formatted(
                            item.pinned
                                ? .dateTime.month(.abbreviated).day().hour().minute() : .dateTime.hour().minute())
                        Text(
                            ClipboardHistory.length(of: item.content, in: SettingsModel.shared.settings.clipboardLength)
                                .map { "\(time) · \($0)" } ?? time
                        )
                        .monospacedDigit()
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.appSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondary)
                    .accessibilityLabel("Pinned")
            }
        }
        .row()
    }
}

/// A copied link in one line, as the keyboard's badge has it: its site's icon, its name among the badges
/// (`ClipLink.names`) and how long ago.
private struct LinkBadge: View {
    let item: ClipboardHistory.Item
    let name: String
    let copied: Bool
    let picked: Bool

    var body: some View {
        if case .link(let link) = item.content.kind {
            HStack(spacing: 6) {
                SiteIcon(site: link.site, side: 18)
                if copied {
                    Text(name).fontWeight(.semibold)
                    Image(systemName: "checkmark").foregroundStyle(Color.appSecondary).accessibilityLabel("Copied")
                } else {
                    let age = ClipboardHistory.age(of: item.found, now: Date.now.timeIntervalSince1970)
                    Text(
                        "\(Text(name).fontWeight(.semibold))\(Text(" · " + age).foregroundStyle(Color.appSecondary))"
                    )
                    .monospacedDigit()
                }
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.appSecondary)
                        .accessibilityLabel("Pinned")
                }
            }
            .font(.subheadline)
            .lineLimit(1)
            .padding(.leading, 9)
            .padding(.trailing, 12)
            .frame(height: 34)
            .background(picked ? Color.appPicked : Color.appCard, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.appEdge))
            .contentShape(.capsule)
        }
    }
}

/// Views in lines from the leading edge, each as wide as it needs up to the line, as words wrap.
private struct Flow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var point = CGPoint.zero
        var line = 0.0
        return subviews.map { subview in
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if point.x > 0, point.x + size.width > width {
                point = CGPoint(x: 0, y: point.y + line + spacing)
                line = 0
            }
            defer {
                point.x += size.width + spacing
                line = max(line, size.height)
            }
            return CGRect(origin: point, size: CGSize(width: min(size.width, width), height: size.height))
        }
    }
}

/// A row's text by its kind (docs/design.md, "Clipboard"), links being badges: an address or a phone number after its glyph; a color after a swatch of it; any
/// other text up to four lines.
private struct ClipTitle: View {
    let content: ClipboardHistory.Item.Content
    let text: String

    private var plain: String { String(text.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        switch content.kind {
        case .email: glyph("envelope")
        case .phone: glyph("phone")
        case .color(let red, let green, let blue):
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255))
                    .overlay(Circle().strokeBorder(Color.appEdge))
                    .frame(width: 20, height: 20)
                Text(plain.uppercased()).monospaced()
            }
        case .text, .image, .link:
            Text(plain).lineLimit(4)
        }
    }

    private func glyph(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.appSecondary)
                .frame(width: 20, height: 20)
            Text(plain).lineLimit(1)
        }
    }
}

/// A link's site icon (`LinkIcons`), or a globe until it comes or when the site has none.
private struct SiteIcon: View {
    let site: String
    let side: CGFloat
    @State private var icon: UIImage?

    init(site: String, side: CGFloat) {
        self.site = site
        self.side = side
        _icon = State(initialValue: LinkIcons.shared.cached(site))
    }

    var body: some View {
        Group {
            if let icon {
                Image(uiImage: icon).resizable()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: side * 0.62, weight: .medium))
                    .foregroundStyle(Color.appSecondary)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .task(id: site) { icon = await LinkIcons.shared.icon(site) }
    }
}

extension ClipboardHistory.Item {
    fileprivate var isLink: Bool { link != nil }
    fileprivate var link: ClipLink? { if case .link(let link) = content.kind { link } else { nil } }
}
