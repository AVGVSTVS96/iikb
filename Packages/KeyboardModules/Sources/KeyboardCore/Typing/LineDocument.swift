/// A line of the keyboard's own that the keys type into in place of the app's field, like a chat's message line: the
/// engine edits it as it edits any field, and return takes what it holds and leaves it empty.
public final class LineDocument: TextDocument {
    public private(set) var text: String
    /// How many characters are before the caret.
    public private(set) var caret: Int
    private var returned: String?

    public init(_ text: String = "") {
        self.text = text
        caret = text.count
    }

    public var textBeforeInput: String? { String(text.prefix(caret)) }

    public var textAfterInput: String? { String(text.dropFirst(caret)) }

    public func insert(_ string: String) {
        guard let end = string.firstIndex(where: \.isNewline) else {
            text.insert(contentsOf: string, at: text.index(text.startIndex, offsetBy: caret))
            caret += string.count
            return
        }
        insert(String(string[..<end]))
        returned = text
        clear()
    }

    public func deleteBackward(_ count: Int) {
        let removed = min(count, caret)
        let end = text.index(text.startIndex, offsetBy: caret)
        text.removeSubrange(text.index(end, offsetBy: -removed)..<end)
        caret -= removed
    }

    public func moveCursor(by offset: Int) {
        caret = min(max(caret + offset, 0), text.count)
    }

    public func clear() {
        text = ""
        caret = 0
    }

    /// What the line held when return was typed, once.
    public func takeReturned() -> String? {
        defer { returned = nil }
        return returned
    }
}
