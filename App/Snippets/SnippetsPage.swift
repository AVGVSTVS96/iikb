import KeyboardCore
import SwiftUI

/// Your snippets under Add Snippet, by tag and then by name, each opening its editor, over how keywords expand. A
/// search field comes once there are enough to look for one.
struct SnippetsPage: View {
    private let model = SettingsModel.shared
    private let router = Router.shared
    @State private var query = ""

    private var shown: [Snippet] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.snippets }
        return model.snippets.filter { snippet in
            [snippet.name, snippet.keyword, snippet.tag, snippet.text].contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    /// The snippets with no tag first, then each tag's, each by name.
    private var groups: [(tag: String, snippets: [Snippet])] {
        Dictionary(grouping: shown, by: \.tag)
            .map {
                (
                    tag: $0.key,
                    snippets: $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                )
            }
            .sorted {
                $0.tag.isEmpty != $1.tag.isEmpty
                    ? $0.tag.isEmpty : $0.tag.localizedStandardCompare($1.tag) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if model.snippets.count >= 8 { SearchField(text: $query) }
            Box(
                footer: model.snippets.isEmpty
                    ? "Keep text you type often, and type it again by its keyword or from the keyboard’s Snippets."
                    : nil
            ) {
                ActionRow(title: "Add Snippet", symbol: "plus") {
                    router.editor = .snippet(Snippet(name: "", text: "", keyword: model.settings.snippetPrefix))
                }
            }
            let groups = groups
            ForEach(groups, id: \.tag) { group in
                Box(header: header(group.tag, count: group.snippets.count, tagged: groups.contains { !$0.tag.isEmpty }))
                {
                    ForEach(group.snippets) { snippet in
                        Button {
                            router.editor = .snippet(snippet)
                        } label: {
                            SnippetRow(snippet: snippet)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(snippet) }
                        }
                    }
                }
            }
            KeywordSettings()
        }
    }

    private func header(_ tag: String, count: Int, tagged: Bool) -> String {
        if !tag.isEmpty { return tag }
        if tagged { return "No Tag" }
        return count == 1 ? "1 Snippet" : "\(count.formatted()) Snippets"
    }
}

/// A snippet's or quicklink's editor, open over Settings (`Router.editor`).
enum SettingsEditor: Identifiable {
    case snippet(Snippet)
    case quicklink(Quicklink)

    var id: String {
        switch self {
        case .snippet(let snippet): "snippet " + snippet.id
        case .quicklink(let link): "quicklink " + link.id
        }
    }

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .snippet(let snippet): SnippetEditor(snippet: snippet)
        case .quicklink(let link): QuicklinkEditor(link: link)
        }
    }
}

/// A snippet's name over the start of its text, its keyword at the right.
private struct SnippetRow: View {
    let snippet: Snippet

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snippet.name).foregroundStyle(.primary)
                Template.line(snippet.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !snippet.keyword.isEmpty { Keyword(snippet.keyword) }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.appSecondary)
                .accessibilityHidden(true)
        }
        .row()
    }
}

/// A keyword as you type it, in a gray capsule.
struct Keyword: View {
    let keyword: String

    init(_ keyword: String) {
        self.keyword = keyword
    }

    var body: some View {
        Text(verbatim: keyword)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.appSecondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color.appPressed, in: .capsule)
            .accessibilityLabel("Keyword \(keyword)")
    }
}

/// How a keyword you type becomes its snippet, and the prefix that starts it.
private struct KeywordSettings: View {
    private let model = SettingsModel.shared

    private var about: String {
        let expansion =
            switch model.settings.snippetExpansion {
            case .immediately: "A keyword becomes its snippet as soon as you type it."
            case .afterDelimiter: "A keyword becomes its snippet once a space, return or punctuation follows it."
            case .off: "Keywords stay as you type them."
            }
        return expansion
            + " Typing the prefix shows your keywords in the bar. Changing it changes the keywords that start with it."
    }

    var body: some View {
        Box(header: "Keywords", footer: about) {
            MenuRow(
                title: "Expansion", selection: model.binding(\.snippetExpansion), choices: SnippetExpansion.allCases
            ) { $0.title }
            PrefixRow()
        }
    }
}

/// The prefix, kept once you're done typing it, so the keywords change once; left empty, it stays as it was.
private struct PrefixRow: View {
    private let model = SettingsModel.shared
    @State private var prefix = SettingsModel.shared.settings.snippetPrefix
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text("Prefix")
            Spacer()
            TextField("!", text: $prefix)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(keep)
                .frame(maxWidth: 120)
        }
        .row()
        .onChange(of: focused) { _, focused in if !focused { keep() } }
        .onChange(of: model.settings.snippetPrefix) { _, kept in if !focused { prefix = kept } }
    }

    private func keep() {
        let typed = prefix.filter { !$0.isWhitespace }
        guard !typed.isEmpty else {
            prefix = model.settings.snippetPrefix
            return
        }
        prefix = typed
        model.setSnippetPrefix(typed)
    }
}

/// A snippet's name, text, keyword and tag, as Raycast's Create Snippet asks for them, saved once its text has
/// something and its keyword no other snippet's.
private struct SnippetEditor: View {
    @State private var snippet: Snippet
    @State private var isNew: Bool
    @State private var input = TemplateInput()
    @Environment(\.dismiss) private var dismiss
    private let model = SettingsModel.shared
    private let original: Snippet

    init(snippet: Snippet) {
        _snippet = State(initialValue: snippet)
        _isNew = State(initialValue: !SettingsModel.shared.snippets.contains { $0.id == snippet.id })
        original = snippet
    }

    private var prefix: String { model.settings.snippetPrefix }
    private var keyword: String {
        let typed = snippet.keyword.trimmingCharacters(in: .whitespaces)
        return typed == prefix ? "" : typed
    }

    /// What keeps the snippet from being saved.
    private var problem: String? {
        guard !keyword.isEmpty else { return nil }
        if keyword.contains(where: \.isWhitespace) { return "A keyword is one word, with no spaces." }
        if let other = model.snippets.first(where: { $0.id != snippet.id && $0.isKeyword(keyword) }) {
            return "“\(other.keyword)” is already \(other.name)’s keyword."
        }
        return nil
    }

    /// Why it can't be saved, or a keyword that Immediately expands before you can type this one or that this one
    /// cuts short.
    private var keywordNote: String? {
        if let problem { return problem }
        guard model.settings.snippetExpansion == .immediately, !keyword.isEmpty else { return nil }
        let lowered = keyword.lowercased()
        guard
            let other = model.snippets.first(where: {
                $0.id != snippet.id && !$0.keyword.isEmpty
                    && ($0.keyword.lowercased().hasPrefix(lowered) || lowered.hasPrefix($0.keyword.lowercased()))
            })
        else { return nil }
        let (short, long) = other.keyword.count < keyword.count ? (other.keyword, keyword) : (keyword, other.keyword)
        return "With Expansion set to Immediately, “\(short)” becomes its snippet before you can type “\(long)”."
    }

    var body: some View {
        NavigationStack {
            Column {
                Box(footer: "Cursor sets where the caret ends. Argument asks for a value each time.") {
                    TextField(
                        "Name", text: $snippet.name,
                        prompt: Text(
                            TypingEngine.name(for: snippet.text).isEmpty ? "Name" : TypingEngine.name(for: snippet.text)
                        )
                    )
                    .textInputAutocapitalization(.words)
                    .row()
                    TemplateField(text: $snippet.text, prompt: "Text", input: input)
                        .overlay(alignment: .topLeading) {
                            if snippet.text.isEmpty {
                                Text("Text").foregroundStyle(Color(.placeholderText)).allowsHitTesting(false)
                            }
                        }
                        .row()
                    PlaceholderButtons(input: input, source: snippet.text)
                }
                Box(footer: keywordNote) {
                    FieldRow(title: "Keyword", prompt: prefix + "keyword", text: $snippet.keyword)
                    FieldRow(title: "Tag", prompt: "None", text: $snippet.tag, capitalization: .words, choices: tags)
                }
                if !isNew {
                    Box {
                        ActionRow(title: "Delete Snippet", role: .destructive) {
                            model.delete(original)
                            dismiss()
                        }
                    }
                }
            }
            .pushedPage(isNew ? "New Snippet" : "Edit Snippet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(
                            snippet.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || problem != nil)
                }
            }
        }
        .presentationBackground(Color.appPage)
        .interactiveDismissDisabled(snippet != original)
    }

    /// The tags your other snippets have, to pick one again as it's spelled.
    private var tags: [String] {
        Set(model.snippets.map(\.tag)).filter { !$0.isEmpty }.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func save() {
        var kept = snippet
        let name = kept.name.trimmingCharacters(in: .whitespacesAndNewlines)
        kept.name = name.isEmpty ? TypingEngine.name(for: kept.text) : name
        kept.keyword = keyword
        kept.tag = kept.tag.trimmingCharacters(in: .whitespaces)
        model.keep(kept)
        dismiss()
    }
}

/// A field's name on the left and what you type at the right, as a form row in iOS Settings; `choices`, when there are
/// any, open from a menu at its end.
struct FieldRow: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var capitalization = TextInputAutocapitalization.never
    var choices: [String] = []

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            TextField(title, text: $text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
            if !choices.isEmpty {
                Menu {
                    ForEach(choices, id: \.self) { choice in Button(choice) { text = choice } }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                        .frame(width: 24, height: 32)
                }
                .accessibilityLabel("Your \(title)s")
            }
        }
        .row()
    }
}
