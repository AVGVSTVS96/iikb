import CJNI
import FoundationEssentials
import KeyboardCore

// What the app's pages ask the engine (Kotlin's `app.Core`): the keyboard preview's own engine, the writing styles, how
// Writing Style types its examples and Transcribe Again writes, which layout settings apply on this phone, and how many
// taps the keyboard has learned.

/// The Keyboard pages' preview: a keyboard of its own on `field`, a `PreviewField` with no text, driven through `Native`
/// like the input method's, with the lexicon and network so its bar suggests as the keyboard's does.
@_cdecl("Java_com_shahidy_iikb_app_Core_preview")
public func preview(env: Env, type: jclass, field: jobject, lexicon: jobject?, network: jobject?) -> jlong {
    create(
        env: env, type, field: field, lexicon: lexicon, network: network, swipe: nil, emoji: nil, search: nil,
        panels: nil)
}

/// `said` as a dictation is typed with `settings` (`Settings.lines`), as iOS's `WritingSettings` shows each choice.
@_cdecl("Java_com_shahidy_iikb_app_Core_typed")
public func typed(env: Env, _: jclass, said: jbyteArray?, settings: jbyteArray?, lexicon: jobject?) -> jbyteArray? {
    let lexicon = env.direct(lexicon).flatMap { Lexicon(bytes: Bytes($0, owner: Mapped())) }
    let writing = KeyboardSettings(parsing: env.string(settings) ?? "").dictation(in: nil)
    return env.array(writing.typed(env.string(said) ?? "", lexicon: lexicon))
}

/// What the voice model heard as a dictation said in `app` writes it, with `settings` (`Settings.lines`), before your
/// Dictionary and the field's capitals: Transcribe Again's, as the keyboard's `Native.written` is a dictation's.
@_cdecl("Java_com_shahidy_iikb_app_Core_written")
public func written(env: Env, _: jclass, heard: jbyteArray?, settings: jbyteArray?, app: jbyteArray?) -> jbyteArray? {
    let writing = KeyboardSettings(parsing: env.string(settings) ?? "").dictation(in: env.string(app))
    return env.array(writing.written(env.string(heard) ?? ""))
}

/// The writing styles in order, each as it's kept and as it's titled, for Writing Style's Style card.
@_cdecl("Java_com_shahidy_iikb_app_Core_styles")
public func styles(env: Env, _: jclass) -> jbyteArray? {
    env.array(Json.encode(DictationStyle.allCases.map { Writing.Style(value: $0.rawValue, title: $0.title) }))
}

/// The style `settings` (`Settings.lines`) write in, a Text Mode kept from before folded into it as iOS's
/// `SettingsStore` folds it (`DictationStyle.with`), so Kotlin can keep it and forget the Text Mode.
@_cdecl("Java_com_shahidy_iikb_app_Core_style")
public func style(env: Env, _: jclass, settings: jbyteArray?) -> jbyteArray? {
    env.array(KeyboardSettings(parsing: env.string(settings) ?? "").dictationStyle.rawValue)
}

/// Kotlin holds the mapped lexicon for as long as the app runs.
private final class Mapped {}

/// Which of Appearance's layout settings change iikb's keys on a screen this size (iOS's `KeysHere`). Android draws its
/// own keyboard switcher, so there's never a globe. Split shows on every phone, as iOS lists it on every iPhone, its
/// footer saying it splits an open foldable, and never on a tablet.
struct KeysHere: Encodable {
    var numberRow, emojiKey, recordKey, keyboardMenu, split, oneHanded, largePanels, characterPreview: Bool
}

@_cdecl("Java_com_shahidy_iikb_app_Core_keysHere")
public func keysHere(env: Env, _: jclass, width: jdouble, height: jdouble, folds: jboolean) -> jbyteArray? {
    let short = min(width, height)
    let device = DeviceClass(screen: Size(width: width, height: height), folds: folds != 0)
    let all = LayoutContext(
        device: device, layer: .letters, showsEmoji: true, showsNumberRow: true, keyboardMenu: .hold)
    let upright = Size(width: short, height: max(width, height))
    let keys = KeysHere(
        numberRow: all.showsNumberRow, emojiKey: all.showsEmoji,
        recordKey: LayoutContext(device: device, layer: .letters, showsMicKey: true).showsMicKey,
        keyboardMenu: all.keyboardMenu == .hold,
        split: LayoutContext(device: device, layer: .letters, isLandscape: true, isOpen: true).allowsSplit,
        oneHanded: LayoutContext(device: device, layer: .letters).allowsOneHanded,
        largePanels: !KeyboardGeometry(LayoutContext(device: device, layer: .letters), screen: upright, style: .ios27)
            .metrics.toolbar.isCompact,
        characterPreview: device == .phone)
    return env.array(Json.encode(keys))
}

/// What a dictation heard with your Dictionary (`vocabulary.json`) put on it, as iOS's `VoiceVocabulary` puts it on
/// every dictation before it's typed, with the English lexicon, so a made-up word that sounds like a term becomes it.
@_cdecl("Java_com_shahidy_iikb_Vocabulary_corrected")
public func corrected(env: Env, _: jclass, text: jbyteArray?, vocabulary: jbyteArray?, lexicon: jobject?) -> jbyteArray?
{
    let text = env.string(text) ?? ""
    guard let vocabulary = try? JSONDecoder().decode(Vocabulary.self, from: Data(env.bytes(vocabulary))) else {
        return env.array(text)
    }
    let lexicon = env.direct(lexicon).flatMap { Lexicon(bytes: Bytes($0, owner: Mapped())) }
    return env.array(vocabulary.corrected(text, lexicon: lexicon))
}

/// The taps the keyboard has learned where your thumbs land, from its saved memory (`typing-memory.json`).
@_cdecl("Java_com_shahidy_iikb_app_Core_taps")
public func taps(env: Env, _: jclass, memory: jbyteArray?) -> jint {
    guard let memory = try? JSONDecoder().decode(TypingMemory.self, from: Data(env.bytes(memory))) else { return 0 }
    return jint(clamping: memory.touches.finite().signatures.reduce(0) { $0 + $1.taps })
}
