/// Text of the keyboard's own that the keys type into in place of the app's field, like a chat's message box: the
/// engine edits it as it edits any field, return starting a new line, and `take` empties it to send.
public final class LineDocument: TextDocument {
    public private(set) var text: String
    /// The selected characters, as offsets; empty is the caret, before `lowerBound` characters.
    public private(set) var selection: Range<Int>

    public init(_ text: String = "") {
        self.text = text
        selection = text.count..<text.count
    }

    /// How many characters are before the caret, or before the selection.
    public var caret: Int { selection.lowerBound }

    public var textBeforeInput: String? { String(text.prefix(selection.lowerBound)) }

    public var textAfterInput: String? { String(text.dropFirst(selection.upperBound)) }

    public var selectedText: String? { String(text.dropFirst(selection.lowerBound).prefix(selection.count)) }

    /// Selects `range`, kept inside the text; an empty one places the caret.
    public func select(_ range: Range<Int>) {
        let lower = min(max(range.lowerBound, 0), text.count)
        selection = lower..<min(max(range.upperBound, lower), text.count)
    }

    public func placeCaret(at offset: Int) {
        select(offset..<offset)
    }

    public func insert(_ string: String) {
        text.replaceSubrange(indices(selection), with: string)
        placeCaret(at: selection.lowerBound + string.count)
    }

    /// A selection goes first and counts as one of `count`, as in a field.
    public func deleteBackward(_ count: Int) {
        let removed = min(max(selection.isEmpty ? count : count - 1, 0), caret)
        let range = caret - removed..<selection.upperBound
        text.removeSubrange(indices(range))
        placeCaret(at: range.lowerBound)
    }

    /// Moves the caret from the selection's start going back and from its end going on, collapsing it.
    public func moveCursor(by offset: Int) {
        placeCaret(at: (offset < 0 ? selection.lowerBound : selection.upperBound) + offset)
    }

    public func clear() {
        text = ""
        selection = 0..<0
    }

    /// All of the text, which is left empty, as a message's send button takes it.
    public func take() -> String {
        defer { clear() }
        return text
    }

    private func indices(_ range: Range<Int>) -> Range<String.Index> {
        let start = text.index(text.startIndex, offsetBy: range.lowerBound)
        return start..<text.index(start, offsetBy: range.count)
    }
}
