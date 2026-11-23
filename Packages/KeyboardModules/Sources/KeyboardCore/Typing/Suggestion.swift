public struct Suggestion: Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case literal, correction, candidate, revert
        /// A snippet's keyword, which goes on from what you've typed after the prefix.
        case snippet
        /// The calculator's answer, which replaces this text before the caret (`Calculation`).
        case answer(replacing: String)
    }

    public var text: String
    public var kind: Kind

    public init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }

    public var title: String {
        switch kind {
        case .literal: "“\(text)”"
        case .answer: "= \(text)"
        default: text
        }
    }
}
