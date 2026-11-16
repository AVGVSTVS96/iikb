/// Fields the keys type into one at a time, in the `.form` panel, before something goes in: a snippet's or quicklink's
/// arguments, or a new snippet's name, keyword and tag. Return goes to the next field and, on the last, finishes.
public struct Fill: Hashable, Sendable {
    public enum Goal: Hashable, Sendable {
        /// Types `template` filled in, its values percent-encoded for a `link`, in place of the `keyword` typed before the
        /// caret (empty for a pick from a panel), then `trailing`, the delimiter that set the keyword off.
        case type(Template, link: Bool, keyword: String, trailing: String)
        /// Opens the quicklink's link filled in.
        case open(Template)
        /// Keeps `text` as a new snippet, named, given a keyword and tagged by the fields.
        case keep(String)
    }

    /// What's being filled in: the snippet's or quicklink's name, or "New Snippet".
    public let title: String
    public let goal: Goal
    public let fields: [Template.Argument]
    public internal(set) var values: [String]
    /// The field the keys type into.
    public internal(set) var at = 0

    init(_ title: String, goal: Goal, fields: [Template.Argument], values: [String]? = nil) {
        self.title = title
        self.goal = goal
        self.fields = fields
        self.values = values ?? fields.map { _ in "" }
    }

    public var isLast: Bool { at == fields.count - 1 }

    /// The text that will go in as the fields stand now, and where `{cursor}` puts the caret in it; for a new snippet,
    /// its text.
    public var preview: (text: String, cursor: Int?) {
        switch goal {
        case .type(let template, let link, _, _):
            template.filled(values, encode: link ? Template.percentEncoded : { $0 })
        case .open(let template): template.filled(values, encode: Template.percentEncoded)
        case .keep(let text): (text, nil)
        }
    }

    /// What a finished fill asks of the keyboard beyond typing, which the engine can't do itself.
    public enum Finished: Hashable, Sendable {
        case keep(Snippet)
        case open(String)
    }
}
