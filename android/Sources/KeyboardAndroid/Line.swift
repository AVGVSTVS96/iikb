import CJNI
import KeyboardCore

/// A chat's message line (docs/extensions.md): while one is open, the engine types into it as into any field, with
/// suggestions and autocorrect, and never into the app's field.
struct LineState: Encodable {
    var text: String
    var caret: Int
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_lineOpen")
public func lineOpen(env: Env, _: jclass, handle: jlong, text: jbyteArray?) {
    let keyboard = keyboard(handle)
    let line = LineDocument(env.string(text) ?? "")
    keyboard.line = line
    keyboard.engine.documentChanged(line)
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_lineClose")
public func lineClose(env: Env, _: jclass, handle: jlong) {
    let keyboard = keyboard(handle)
    keyboard.document.env = env
    keyboard.line = nil
    keyboard.engine.documentChanged(keyboard.document)
}

/// The line's text and caret, as JSON, or nothing when no chat is open.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_lineState")
public func lineState(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    guard let line = keyboard(handle).line else { return nil }
    return env.array(Json.encode(LineState(text: line.text, caret: line.caret)))
}

/// What return took from the line to send, once.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_lineTake")
public func lineTake(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    keyboard(handle).line?.takeReturned().map { env.array($0) } ?? nil
}

/// Puts text back in the line, like a message that couldn't be sent.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_lineRestore")
public func lineRestore(env: Env, _: jclass, handle: jlong, text: jbyteArray?) {
    let keyboard = keyboard(handle)
    guard let line = keyboard.line else { return }
    line.clear()
    line.insert(env.string(text) ?? "")
    keyboard.engine.documentChanged(line)
}
