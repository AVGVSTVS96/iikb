import CJNI
import KeyboardCore

/// The app's field, through the Kotlin `Field` over Android's `InputConnection`, as the `TextDocument` that
/// `TypingEngine` edits. Android counts text in UTF-16 units, so the counts in characters the engine gives are turned
/// into UTF-16 here, from the text around the caret, where Swift knows what a character is.
final class HostDocument: TextDocument {
    /// The environment of the call in progress: each call from Kotlin sets it before the engine runs.
    var env: Env
    private let field: jobject
    private let before, after, selected, write, deleteSelection, deleteBefore, move: jmethodID?

    init(env: Env, field: jobject) {
        self.env = env
        self.field = env.jni.NewGlobalRef(env, field)!
        before = env.method(field, "before", "()[B")
        after = env.method(field, "after", "()[B")
        selected = env.method(field, "selected", "()[B")
        write = env.method(field, "insert", "([B)V")
        deleteSelection = env.method(field, "deleteSelection", "()V")
        deleteBefore = env.method(field, "deleteBefore", "(I)V")
        move = env.method(field, "move", "(I)V")
    }

    func release() {
        env.jni.DeleteGlobalRef(env, field)
    }

    var textBeforeInput: String? { text(before) }
    var textAfterInput: String? { text(after) }
    var selectedText: String? { text(selected) }

    func insert(_ text: String) {
        let bytes = env.array(text)
        defer { env.jni.DeleteLocalRef(env, bytes) }
        var arguments = [jvalue(l: bytes)]
        env.jni.CallVoidMethodA(env, field, write, &arguments)
    }

    func deleteBackward(_ count: Int) {
        var left = count
        if let selection = selectedText, !selection.isEmpty {
            env.jni.CallVoidMethodA(env, field, deleteSelection, nil)
            left -= 1
        }
        guard left > 0, let before = textBeforeInput, !before.isEmpty else { return }
        call(deleteBefore, before.suffix(left).utf16.count)
    }

    func moveCursor(by offset: Int) {
        let units =
            offset < 0
            ? -(textBeforeInput ?? "").suffix(-offset).utf16.count
            : (textAfterInput ?? "").prefix(offset).utf16.count
        if units != 0 { call(move, units) }
    }

    private func call(_ method: jmethodID?, _ value: Int) {
        var arguments = [jvalue(i: jint(value))]
        env.jni.CallVoidMethodA(env, field, method, &arguments)
    }

    private func text(_ method: jmethodID?) -> String? {
        guard let array = env.jni.CallObjectMethodA(env, field, method, nil) else { return nil }
        defer { env.jni.DeleteLocalRef(env, array) }
        return env.string(array)
    }
}
