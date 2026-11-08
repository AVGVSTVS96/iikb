/// What the keyboard wrote, for an iPad's undo and redo keys: each step a word as it was typed, with what ended it (its
/// correction, its space), or whatever went in whole (a pick, an emoji, a dictation). A keyboard can't reach the app's own
/// undo, so these undo the keyboard's writing at the caret, and only while the text there is still what it wrote.
struct EditHistory: Hashable, Sendable {
    /// At the caret, `removed` became `inserted`.
    struct Step: Hashable, Sendable {
        var removed: String
        var inserted: String
    }

    private(set) var undos: [Step] = []
    private(set) var redos: [Step] = []
    /// The last step takes the writes that follow it, until a space, a return or anything whole ends it.
    private var isOpen = false

    var canUndo: Bool { !undos.isEmpty }
    var canRedo: Bool { !redos.isEmpty }

    /// A write at the end of `before`: its last `count` characters replaced by `string`. A write reaching past what the
    /// keyboard can see can't be undone, so it forgets every step.
    mutating func record(replacing count: Int, of before: String, with string: String) {
        guard before.suffix(count).count == count else { return clear() }
        redos = []
        if isOpen, var step = undos.popLast() {
            let typed = step.inserted.count
            if count <= typed {
                step.inserted = String(step.inserted.dropLast(count)) + string
            } else {
                step.removed = String(before.dropLast(typed).suffix(count - typed)) + step.removed
                step.inserted = string
            }
            if step.removed == step.inserted { isOpen = false } else { undos.append(step) }
        } else if count > 0 || !string.isEmpty {
            undos.append(Step(removed: String(before.suffix(count)), inserted: string))
            isOpen = true
        }
    }

    /// The next write starts a step of its own.
    mutating func close() {
        isOpen = false
    }

    mutating func clear() {
        self = EditHistory()
    }

    /// The step to take back when `before` still ends with what it wrote, moved to the redos.
    mutating func undo(before: String) -> Step? {
        guard let step = undos.last, before.hasSuffix(step.inserted) else {
            clear()
            return nil
        }
        undos.removeLast()
        redos.append(step)
        isOpen = false
        return step
    }

    /// The step to write again when `before` still ends where its undo left it, moved back to the undos.
    mutating func redo(before: String) -> Step? {
        guard let step = redos.last, before.hasSuffix(step.removed) else {
            clear()
            return nil
        }
        redos.removeLast()
        undos.append(step)
        isOpen = false
        return step
    }
}
