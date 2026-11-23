public struct Copied: Equatable, Sendable {
    public var text: String?

    public init(text: String?) {
        self.text = text
    }
}

extension TypingEngine {
    public var pasteOffer: Copied? {
        guard let copied, panel == nil, fill == nil, text.isKnown, text.isEmpty else { return nil }
        return copied
    }
}
