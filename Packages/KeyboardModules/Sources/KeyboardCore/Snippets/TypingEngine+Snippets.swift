/// Snippets and quicklinks: a keyword you type becoming its snippet, the bar's keywords after the prefix, a pick from a
/// panel, and the fill that asks for arguments, or a new snippet's name, keyword and tag, first.
extension TypingEngine {
    /// The snippet whose keyword the keyboard just typed at a word's start, longest keyword first, and the keyword as
    /// typed.
    var typedKeyword: (snippet: Snippet, typed: String)? {
        let before = text.before
        for snippet in snippets.sorted(by: { $0.keyword.count > $1.keyword.count }) {
            let length = snippet.keyword.count
            guard length > 0, text.owned >= length, before.count >= length else { continue }
            let typed = before.suffix(length)
            guard snippet.isKeyword(typed), Words.startsWord(after: before[..<typed.startIndex].last) else {
                continue
            }
            return (snippet, String(typed))
        }
        return nil
    }

    /// What you've typed of a keyword: the text since a word's start, when it begins with the snippet prefix.
    var typedPrefix: Substring? {
        let prefix = settings.snippetPrefix
        guard !prefix.isEmpty, !snippets.isEmpty else { return nil }
        let before = text.before
        let start = before.lastIndex { Words.startsWord(after: $0) }.map(before.index(after:)) ?? before.startIndex
        let typed = before[start...]
        return typed.hasPrefix(prefix) ? typed : nil
    }

    /// The bar's snippets after the prefix: the keywords that go on from what you've typed, as Raycast's bar shows them.
    var snippetSuggestions: [Suggestion] {
        guard let typed = typedPrefix else { return [] }
        return Snippet.completing(typed, in: snippets).prefix(3).map { Suggestion($0.keyword, .snippet) }
    }

    /// Expands the keyword just typed, when snippets expand in `mode`: its snippet goes in its place, then `trailing`,
    /// the delimiter that set it off, or its arguments are asked for first.
    mutating func expands(_ mode: SnippetExpansion, trailing: String, in document: some TextDocument) -> Bool {
        guard settings.snippetExpansion == mode, mode != .off, let (snippet, typed) = typedKeyword else { return false }
        type(snippet, replacing: typed, trailing: trailing, in: document)
        return true
    }

    /// A snippet from the bar: it takes the place of what you've typed of its keyword.
    mutating func accept(snippet keyword: String, in document: some TextDocument) {
        guard let typed = typedPrefix, let snippet = snippets.first(where: { $0.isKeyword(keyword) }) else { return }
        tally.picked += 1
        type(snippet, replacing: String(typed), trailing: "", in: document)
    }

    /// Types `snippet` in place of `keyword`, typed just before the caret (empty for a pick from a panel), then
    /// `trailing`; with arguments, it asks for them first.
    mutating func type(_ snippet: Snippet, replacing keyword: String, trailing: String, in document: some TextDocument)
    {
        let template = Template(snippet.text)
        let goal = Fill.Goal.type(template, link: false, keyword: keyword, trailing: trailing)
        guard template.arguments.isEmpty else {
            return begin(Fill(snippet.name, goal: goal, fields: template.arguments))
        }
        finish(goal, values: [], in: document)
    }

    /// Types a quicklink's link, or has the keyboard open it, asking for its arguments first.
    mutating func open(_ link: Quicklink, opening: Bool, in document: some TextDocument) {
        let template = Template(link.link)
        let goal = opening ? Fill.Goal.open(template) : .type(template, link: true, keyword: "", trailing: "")
        guard template.arguments.isEmpty else {
            return begin(Fill(link.name, goal: goal, fields: template.arguments))
        }
        finish(goal, values: [], in: document)
    }

    /// Asks for a new snippet's name, keyword and tag, to keep the selected text or else all of the field the keyboard
    /// is given, as Raycast's Create Snippet does. The keyword starts with the prefix. With nothing to keep it does
    /// nothing.
    mutating func createSnippet() {
        let all = text.selected.isEmpty ? text.before + (text.after ?? "") : text.selected
        guard !all.allSatisfy(\.isWhitespace) else { return }
        let fields = [
            Template.Argument(name: "Name", defaultValue: Self.name(for: all)), Template.Argument(name: "Keyword"),
            Template.Argument(name: "Tag"),
        ]
        begin(Fill("New Snippet", goal: .keep(all), fields: fields, values: ["", settings.snippetPrefix, ""]))
    }

    /// The first words of a snippet's text, its name when you give it none.
    public static func name(for text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let words = line.split(separator: " ")
        let name = words.prefix(5).joined(separator: " ")
        return words.count > 5 ? name + "…" : name
    }

    /// What a fill finished asks of the keyboard: a snippet to keep, or a link to open.
    public mutating func takeFinished() -> Fill.Finished? {
        defer { finished = nil }
        return finished
    }

    private mutating func begin(_ fill: Fill) {
        learnPending()
        typing = WordTaps()
        revert = nil
        self.fill = fill
        query = fill.values[0]
        layer = .letters
        refreshShift()
        suggestionsChanged()
    }

    mutating func pick(field index: Int) {
        guard let fill, fill.fields.indices.contains(index) else { return }
        self.fill?.at = index
        query = fill.values[index]
        suggestionsChanged()
    }

    mutating func nextField(in document: some TextDocument) {
        guard let fill else { return }
        guard fill.isLast else { return pick(field: fill.at + 1) }
        submit(in: document)
    }

    /// Finishes the fill as its fields stand, unless a new snippet's keyword can't be its own: then the keyword's field
    /// says why.
    mutating func submit(in document: some TextDocument) {
        guard let fill else { return }
        if case .keep = fill.goal,
            let problem = Snippet.problem(with: newKeyword(fill.values[1]), for: nil, in: snippets)
        {
            pick(field: 1)
            self.fill?.problem = problem
            return
        }
        close()
        finish(fill.goal, values: fill.values, in: document)
    }

    /// Back on a fill: nothing goes in, and a keyword that opened it stays as typed, with its delimiter after it.
    mutating func cancelFill(in document: some TextDocument) {
        guard let fill else { return }
        close()
        if case .type(_, _, let keyword, let trailing) = fill.goal, !keyword.isEmpty, !trailing.isEmpty {
            write(trailing, in: document)
        }
        refreshShift()
        suggestionsChanged()
    }

    /// A new snippet's keyword as typed in its field, none when it's the prefix alone, as the app's editor reads one.
    private func newKeyword(_ typed: String) -> String {
        let keyword = String(typed[...].trimmingSpaces())
        return keyword == settings.snippetPrefix ? "" : keyword
    }

    private mutating func close() {
        fill = nil
        query = ""
        if opened == nil { layer = Self.initialLayer(for: traits.kind) }
    }

    private mutating func finish(_ goal: Fill.Goal, values: [String], in document: some TextDocument) {
        attach(document)
        switch goal {
        case .type(let template, let link, let keyword, let trailing):
            let filled = template.filled(values, encode: link ? Template.percentEncoded : { $0 })
            if keyword.isEmpty { commitWord(in: document) }
            learnPending()
            typing = WordTaps()
            revert = nil
            lastSpace = nil
            let replacing = text.before.lowercased().hasSuffix(keyword.lowercased()) ? keyword.count : 0
            history.close()
            write(filled.text + trailing, replacing: replacing, in: document)
            history.close()
            if let cursor = filled.cursor { moveCaret(by: cursor - filled.text.count - trailing.count, in: document) }
        case .open(let template):
            finished = .open(template.filled(values, encode: Template.percentEncoded).text)
        case .keep(let text):
            let name = values[0].isEmpty ? Self.name(for: text) : values[0]
            finished = .keep(Snippet(name: name, text: text, keyword: newKeyword(values[1]), tag: values[2]))
        }
        refreshShift()
        suggestionsChanged()
    }
}
