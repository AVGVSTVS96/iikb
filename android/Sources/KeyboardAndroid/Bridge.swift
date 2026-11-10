import CJNI
import FoundationEssentials
import KeyboardCore

// The functions Kotlin's `Native` object declares, by JNI's names. A keyboard crosses as the address of its
// `Keyboard`, and each call that may edit the field first points the field at the calling thread's environment.

func keyboard(_ handle: jlong) -> Keyboard {
    Unmanaged<Keyboard>.fromOpaque(UnsafeRawPointer(bitPattern: Int(handle))!).takeUnretainedValue()
}

@discardableResult
func with<T>(_ env: Env, _ handle: jlong, _ body: (Keyboard) -> T) -> T {
    let keyboard = keyboard(handle)
    keyboard.document.env = env
    return body(keyboard)
}

private func bytes(_ buffer: UnsafeRawBufferPointer?) -> Bytes? {
    buffer.map { Bytes($0, owner: Owner()) }
}

/// Kotlin holds the mapped files, so the bytes need no owner here.
private final class Owner {}

/// A ranking packed to run off the main thread (`TypingEngine.suggestionJob`).
private final class Job: @unchecked Sendable {
    var job: SuggestionJob

    init(_ job: SuggestionJob) {
        self.job = job
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_create")
public func create(
    env: Env, _: jclass, field: jobject, lexicon: jobject?, network: jobject?, swipe: jobject?, emoji: jbyteArray?,
    search: jbyteArray?
) -> jlong {
    let keyboard = Keyboard(
        document: HostDocument(env: env, field: field),
        lexicon: bytes(env.direct(lexicon)).flatMap { Lexicon(bytes: $0) },
        network: bytes(env.direct(network)).flatMap { Network(bytes: $0) },
        swipe: bytes(env.direct(swipe)).flatMap { Swipe(bytes: $0) },
        emoji: env.string(emoji) ?? "", search: env.string(search) ?? "")
    return jlong(Int(bitPattern: Unmanaged.passRetained(keyboard).toOpaque()))
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_destroy")
public func destroy(env: Env, _: jclass, handle: jlong) {
    let unmanaged = Unmanaged<Keyboard>.fromOpaque(UnsafeRawPointer(bitPattern: Int(handle))!)
    unmanaged.takeUnretainedValue().document.env = env
    unmanaged.takeUnretainedValue().document.release()
    unmanaged.release()
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_place")
public func place(
    env: Env, _: jclass, handle: jlong, width: jdouble, screenWidth: jdouble, screenHeight: jdouble, folds: jboolean,
    bottom: jdouble, dark: jboolean, globe: jboolean
) {
    with(env, handle) {
        $0.place(
            width: width, screen: Size(width: screenWidth, height: screenHeight), folds: folds != 0, bottom: bottom,
            dark: dark != 0, showsGlobe: globe != 0)
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_configure")
public func configure(env: Env, _: jclass, handle: jlong, settings: jbyteArray?) {
    with(env, handle) { $0.configure(env.string(settings) ?? "") }
}

/// The field's traits as `kind content return capitals`, by the names of KeyboardCore's cases.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_traits")
public func traits(
    env: Env, _: jclass, handle: jlong, names: jbyteArray?, smartPunctuation: jboolean, requiresText: jboolean,
    autocorrection: jboolean
) {
    let names = (env.string(names) ?? "").split(separator: " ").map(String.init) + ["", "", "", ""]
    let traits = InputTraits(
        kind: InputKind(rawValue: names[0]) ?? .text,
        content: InputContent(rawValue: names[1]) ?? .other,
        returnKind: ReturnKind(name: names[2]),
        autocapitalization: Autocapitalization(name: names[3]),
        smartPunctuation: smartPunctuation != 0,
        returnRequiresText: requiresText != 0,
        autocorrection: autocorrection != 0)
    with(env, handle) { $0.engine.update(traits) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_frame")
public func frame(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    with(env, handle) { keyboard in env.array(Json.encode(keyboard.frame())) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_resolve")
public func resolve(env: Env, _: jclass, handle: jlong, x: jdouble, y: jdouble) -> jint {
    with(env, handle) { jint($0.resolve(x: x, y: y)) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_down")
public func down(env: Env, _: jclass, handle: jlong, index: jint, taps: jint) {
    with(env, handle) { keyboard in
        guard let key = keyboard.key(at: Int(index)) else { return }
        keyboard.handle(.down(key, tapCount: Int(taps)))
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_up")
public func up(env: Env, _: jclass, handle: jlong, index: jint) {
    with(env, handle) { keyboard in
        guard let key = keyboard.key(at: Int(index)) else { return }
        keyboard.handle(.up(key))
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_type")
public func type(env: Env, _: jclass, handle: jlong, index: jint, text: jbyteArray?, x: jdouble, y: jdouble) {
    with(env, handle) { keyboard in
        guard let key = keyboard.key(at: Int(index)), let text = env.string(text) else { return }
        keyboard.handle(.type(key, Tap(x: x, y: y, key: text)))
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_trigger")
public func trigger(env: Env, _: jclass, handle: jlong, index: jint) {
    with(env, handle) { keyboard in
        guard let key = keyboard.key(at: Int(index)) else { return }
        keyboard.handle(.trigger(key))
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_slide")
public func slide(env: Env, _: jclass, handle: jlong, text: jbyteArray?) {
    with(env, handle) { keyboard in
        guard let text = env.string(text) else { return }
        keyboard.handle(.slide(text))
    }
}

/// A swipe's path as three arrays of the same length: x and y in dp, and seconds since the finger went down.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_swipe")
public func swipe(env: Env, _: jclass, handle: jlong, xs: jfloatArray?, ys: jfloatArray?, times: jfloatArray?) {
    let (xs, ys, times) = (env.floats(xs), env.floats(ys), env.floats(times))
    let path = zip(xs, zip(ys, times)).map { SwipePoint(x: Double($0), y: Double($1.0), time: Double($1.1)) }
    with(env, handle) { $0.handle(.swipe(path)) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_cursor")
public func cursor(env: Env, _: jclass, handle: jlong, offset: jint) {
    with(env, handle) { $0.handle(.cursor(offset: Int(offset))) }
}

/// The width the trackpad's finger travels for one step crosses this character, nil at the text's end.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_crossed")
public func crossed(env: Env, _: jclass, handle: jlong, step: jint) -> jbyteArray? {
    with(env, handle) { keyboard in keyboard.engine.character(crossedBy: Int(step)).flatMap { env.array(String($0)) } }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_menu")
public func menu(env: Env, _: jclass, handle: jlong, item: jint) {
    with(env, handle) { keyboard in
        guard let event = keyboard.menuEvent(at: Int(item)) else { return }
        keyboard.handle(event)
    }
}

/// The one-handed keyboard's chevron: both hands back.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_expand")
public func expand(env: Env, _: jclass, handle: jlong) {
    with(env, handle) { $0.handle(.oneHanded(.off)) }
}

/// The one-handed side the engine is on now, as the setting saves it, so a pick from the menu outlives the next change.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_oneHanded")
public func oneHanded(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    with(env, handle) { env.array($0.engine.settings.oneHanded.rawValue) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_select")
public func select(env: Env, _: jclass, handle: jlong, index: jint) {
    with(env, handle) { keyboard in
        let suggestions = keyboard.engine.suggestions
        guard suggestions.indices.contains(Int(index)) else { return }
        keyboard.engine.accept(suggestions[Int(index)], in: keyboard.typing)
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_acceptEmoji")
public func acceptEmoji(env: Env, _: jclass, handle: jlong, emoji: jbyteArray?) {
    with(env, handle) { keyboard in
        guard let emoji = env.string(emoji) else { return }
        keyboard.engine.accept(emoji: emoji, in: keyboard.typing)
    }
}

/// An emoji picked in the emoji panel, with the untoned one it was picked among skin tones of.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_pickEmoji")
public func pickEmoji(env: Env, _: jclass, handle: jlong, emoji: jbyteArray?, base: jbyteArray?) {
    with(env, handle) { keyboard in
        guard let emoji = env.string(emoji) else { return }
        keyboard.handle(.emoji(emoji, base: env.string(base)))
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_paste")
public func paste(env: Env, _: jclass, handle: jlong, text: jbyteArray?) {
    with(env, handle) { keyboard in
        guard let text = env.string(text) else { return }
        keyboard.handle(.paste(text))
    }
}

/// Opens a panel by its name in KeyboardCore (`emoji`, `gif`, `clipboard`, `transcripts`), or closes it with none.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_panel")
public func panel(env: Env, _: jclass, handle: jlong, name: jbyteArray?) {
    let name = env.string(name)
    let panel = Panel.allCases.first { "\($0)" == name }
    with(env, handle) { $0.handle(.panel(panel)) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_emojiResults")
public func emojiResults(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    with(env, handle) { env.array($0.emojiResults().joined(separator: "\n")) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_tones")
public func tones(env: Env, _: jclass, handle: jlong, emoji: jbyteArray?) -> jbyteArray? {
    with(env, handle) { keyboard in env.array(keyboard.tones(of: env.string(emoji) ?? "").joined(separator: "\n")) }
}

/// What iikb types for what a voice model heard, in the Writing Style picked for `app`, as iOS's app writes it
/// (`DictationWriting.typed`) before handing it to the keyboard.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_written")
public func written(env: Env, _: jclass, handle: jlong, heard: jbyteArray?, app: jbyteArray?) -> jbyteArray? {
    with(env, handle) { keyboard in
        env.array(keyboard.engine.settings.dictation(in: env.string(app)).written(env.string(heard) ?? ""))
    }
}

/// A dictation typed at the caret: `text` as `written` styled it, `plain` as the model wrote it, which a field of
/// addresses or digits reads instead (`KeyboardEvent.dictated`).
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_dictated")
public func dictated(env: Env, _: jclass, handle: jlong, text: jbyteArray?, plain: jbyteArray?, id: jbyteArray?) {
    with(env, handle) { keyboard in
        guard let text = env.string(text) else { return }
        keyboard.handle(.dictated(text, plain: env.string(plain), id: env.string(id)))
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_deleteRepeat")
public func deleteRepeat(env: Env, _: jclass, handle: jlong, words: jboolean) {
    with(env, handle) { keyboard in
        if words != 0 {
            keyboard.engine.deleteWord(in: keyboard.typing)
        } else {
            keyboard.engine.perform(.delete, in: keyboard.typing)
        }
    }
}

/// The app changed the field, or the caret moved. True when it was a change the keyboard didn't make.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_documentChanged")
public func documentChanged(env: Env, _: jclass, handle: jlong) -> jboolean {
    with(env, handle) { $0.engine.documentChanged($0.typing) == .changed ? 1 : 0 }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_barMore")
public func barMore(env: Env, _: jclass, handle: jlong, shown: jboolean) {
    with(env, handle) { $0.barMore = shown != 0 }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_leaveField")
public func leaveField(env: Env, _: jclass, handle: jlong) {
    with(env, handle) { $0.engine.leaveField() }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_endSession")
public func endSession(env: Env, _: jclass, handle: jlong) {
    with(env, handle) { keyboard in
        keyboard.engine.endSession()
        keyboard.handle(.panel(nil))
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_suggestionJob")
public func suggestionJob(env: Env, _: jclass, handle: jlong) -> jlong {
    with(env, handle) { keyboard in
        guard let job = keyboard.engine.suggestionJob() else { return 0 }
        return jlong(Int(bitPattern: Unmanaged.passRetained(Job(job)).toOpaque()))
    }
}

/// Runs a job on the calling thread, any but the main one.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_runJob")
public func runJob(env: Env, _: jclass, job: jlong) {
    Unmanaged<Job>.fromOpaque(UnsafeRawPointer(bitPattern: Int(job))!).takeUnretainedValue().job.run()
}

/// Keeps a job's rankings, on the main thread, and lets the job go.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_finishJob")
public func finishJob(env: Env, _: jclass, handle: jlong, job: jlong) {
    let job = Unmanaged<Job>.fromOpaque(UnsafeRawPointer(bitPattern: Int(job))!).takeRetainedValue()
    with(env, handle) { $0.engine.finish(job.job) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_memory")
public func memory(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    with(env, handle) { keyboard in keyboard.memory().flatMap { env.array($0) } }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_restoreMemory")
public func restoreMemory(env: Env, _: jclass, handle: jlong, bytes: jbyteArray?) {
    with(env, handle) { $0.restore(memory: env.bytes(bytes)) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_emojiHistory")
public func emojiHistory(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    with(env, handle) { keyboard in keyboard.emojiHistory().flatMap { env.array($0) } }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_restoreEmojiHistory")
public func restoreEmojiHistory(env: Env, _: jclass, handle: jlong, bytes: jbyteArray?) {
    with(env, handle) { $0.restore(emojiHistory: env.bytes(bytes)) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_changeApp")
public func changeApp(env: Env, _: jclass, handle: jlong, app: jbyteArray?) {
    with(env, handle) { keyboard in
        keyboard.engine.changeApp(env.string(app))
        keyboard.engine.emojiHistory.app = env.string(app)
    }
}

extension ReturnKind {
    init(name: String) {
        self =
            switch name {
            case "go": .go
            case "next": .next
            case "search": .search
            case "send": .send
            case "done": .done
            default: .default
            }
    }
}

extension Autocapitalization {
    init(name: String) {
        self =
            switch name {
            case "none": .none
            case "words": .words
            case "allCharacters": .allCharacters
            default: .sentences
            }
    }
}

/// Settings › Privacy & Data › Reset Learned Words and Taps.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_resetMemory")
public func resetMemory(env: Env, _: jclass, handle: jlong) {
    with(env, handle) { keyboard in
        keyboard.engine.corrector?.changeMemory { $0 = TypingMemory() }
        keyboard.engine.suggestionsChanged()
    }
}

/// Android's personal dictionary as iOS's `UILexicon` gives a keyboard its Text Replacements and names: a JSON list of
/// `[word, shortcut]`, a word with a shortcut typed for it and one without kept as yours, spelled as you added it.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_learnLexicon")
public func learnLexicon(env: Env, _: jclass, handle: jlong, entries: jbyteArray?) {
    let entries = (try? JSONDecoder().decode([[String]].self, from: Data(env.bytes(entries)))) ?? []
    with(env, handle) { keyboard in
        let replacements = entries.compactMap { entry -> (shortcut: String, phrase: String)? in
            guard entry.count == 2, !entry[1].isEmpty, entry[1] != entry[0] else { return nil }
            return (entry[1], entry[0])
        }
        keyboard.engine.corrector?.setReplacements(replacements)
        keyboard.engine.corrector?.setNames(entries.filter { $0.count == 1 || $0[1].isEmpty }.map { $0[0] })
        keyboard.engine.suggestionsChanged()
    }
}
