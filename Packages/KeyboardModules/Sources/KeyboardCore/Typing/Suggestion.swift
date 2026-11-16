public struct Suggestion: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case literal, correction, candidate, revert
        /// A snippet's keyword, which goes on from what you've typed after the prefix.
        case snippet
    }

    public var text: String
    public var kind: Kind

    public init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }

    public var title: String {
        kind == .literal ? "“\(text)”" : text
    }
}
