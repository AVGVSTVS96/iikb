import KeyboardCore
import SwiftUI

/// Your quicklinks under Add Quicklink, by name, each opening its editor.
struct QuicklinksPage: View {
    private let model = SettingsModel.shared
    private let router = Router.shared

    private var links: [Quicklink] {
        model.quicklinks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Box(
                footer: links.isEmpty ? "Keep links you use often, and reach them from the keyboard’s Quicklinks." : nil
            ) {
                ActionRow(title: "Add Quicklink", symbol: "plus") {
                    router.editor = .quicklink(Quicklink(name: "", link: "https://"))
                }
            }
            if !links.isEmpty {
                Box(header: links.count == 1 ? "1 Quicklink" : "\(links.count.formatted()) Quicklinks") {
                    ForEach(links) { link in
                        Button {
                            router.editor = .quicklink(link)
                        } label: {
                            QuicklinkRow(link: link)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(link) }
                        }
                    }
                }
            }
        }
    }
}

/// A quicklink's name over its link without `https://`, its arguments in blue.
private struct QuicklinkRow: View {
    let link: Quicklink

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(link.name).foregroundStyle(.primary)
                Template.line(link.shown)
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.appSecondary)
                .accessibilityHidden(true)
        }
        .row()
    }
}

extension Quicklink {
    /// The link as a list shows it, without `https://` and `www.`.
    fileprivate var shown: String {
        var shown = Substring(link)
        for start in ["https://", "www."] where shown.hasPrefix(start) { shown = shown.dropFirst(start.count) }
        return String(shown)
    }

    /// The link as it opens with every argument typed, for checking it is one; without a scheme, `https://` goes first.
    fileprivate static func opens(_ link: String) -> (link: String, url: URL)? {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = Template(link)
        let sample = template.filled(template.arguments.map { _ in "a" }, encode: Template.percentEncoded).text
        if let url = URL(string: sample), url.scheme != nil, url.host() != nil || !url.absoluteString.contains("://") {
            return (link, url)
        }
        guard !link.contains("://"), let url = URL(string: "https://" + sample), url.host()?.contains(".") == true
        else {
            return nil
        }
        return ("https://" + link, url)
    }
}

/// A quicklink's name and link, saved once the link is one iOS can open; a link with no scheme gets `https://`.
struct QuicklinkEditor: View {
    @State private var link: Quicklink
    @State private var isNew: Bool
    @State private var input = TemplateInput()
    @Environment(\.dismiss) private var dismiss
    private let model = SettingsModel.shared
    private let original: Quicklink

    init(link: Quicklink) {
        _link = State(initialValue: link)
        _isNew = State(initialValue: !SettingsModel.shared.quicklinks.contains { $0.id == link.id })
        original = link
    }

    private var opens: (link: String, url: URL)? { Quicklink.opens(link.link) }

    /// The site's name, the quicklink's when you give it none.
    private var site: String {
        guard let host = opens?.url.host() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var typed: Bool { !link.link.trimmingCharacters(in: .whitespaces).isEmpty && link.link != "https://" }

    private var note: String {
        if typed, opens == nil { return "Not a link iikb can open. Start it with https:// or an app’s scheme." }
        return "Argument asks for a value each time, like a search, and puts it in the link."
    }

    var body: some View {
        NavigationStack {
            Column {
                Box(footer: note) {
                    TextField("Name", text: $link.name, prompt: Text(site.isEmpty ? "Name" : site))
                        .textInputAutocapitalization(.words)
                        .row()
                    TemplateField(text: $link.link, prompt: "Link", link: true, input: input)
                        .row()
                    PlaceholderButtons(input: input, source: link.link, cursor: false)
                }
                if !isNew {
                    Box {
                        ActionRow(title: "Delete Quicklink", role: .destructive) {
                            model.delete(original)
                            dismiss()
                        }
                    }
                }
            }
            .pushedPage(isNew ? "New Quicklink" : "Edit Quicklink")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!typed || opens == nil)
                }
            }
        }
        .presentationBackground(Color.appPage)
        .interactiveDismissDisabled(link != original)
    }

    private func save() {
        guard let opens else { return }
        var kept = link
        let name = kept.name.trimmingCharacters(in: .whitespacesAndNewlines)
        kept.name = name.isEmpty ? site : name
        kept.link = opens.link
        model.keep(kept)
        dismiss()
    }
}
