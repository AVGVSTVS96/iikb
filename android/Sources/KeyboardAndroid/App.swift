import CJNI
import FoundationEssentials
import KeyboardCore

// What the app's pages ask the engine (Kotlin's `app.Core`): the keyboard preview's own engine, how Writing Style types
// its examples, which layout settings apply on this phone, and how many taps the keyboard has learned.

/// The Keyboard pages' preview: a keyboard of its own on `field`, a `PreviewField` with no text, driven through `Native`
/// like the input method's, with the lexicon and network so its bar suggests as the keyboard's does.
@_cdecl("Java_com_shahidy_iikb_app_Core_preview")
public func preview(env: Env, type: jclass, field: jobject, lexicon: jobject?, network: jobject?) -> jlong {
    create(env: env, type, field: field, lexicon: lexicon, network: network, swipe: nil, emoji: nil, search: nil)
}

/// `said` as a dictation is typed with `settings` (`Settings.lines`), as iOS's `WritingSettings` shows each choice.
@_cdecl("Java_com_shahidy_iikb_app_Core_typed")
public func typed(env: Env, _: jclass, said: jbyteArray?, settings: jbyteArray?, lexicon: jobject?) -> jbyteArray? {
    let lexicon = env.direct(lexicon).flatMap { Lexicon(bytes: Bytes($0, owner: Mapped())) }
    let writing = KeyboardSettings(parsing: env.string(settings) ?? "").dictation(in: nil)
    return env.array(writing.typed(env.string(said) ?? "", lexicon: lexicon))
}

/// Kotlin holds the mapped lexicon for as long as the app runs.
private final class Mapped {}

/// Which of Appearance's layout settings change iikb's keys on a screen this size (iOS's `KeysHere`). Android draws its
/// own keyboard switcher, so there's never a globe.
struct KeysHere: Encodable {
    var numberRow, emojiKey, recordKey, keyboardMenu, split, oneHanded, largePanels, characterPreview: Bool
}

@_cdecl("Java_com_shahidy_iikb_app_Core_keysHere")
public func keysHere(env: Env, _: jclass, width: jdouble, height: jdouble) -> jbyteArray? {
    let short = min(width, height)
    let device = DeviceClass(isPad: short >= 600, shortSide: short)
    let all = LayoutContext(
        device: device, layer: .letters, showsEmoji: true, showsNumberRow: true, keyboardMenu: .hold)
    let upright = Size(width: short, height: max(width, height))
    let keys = KeysHere(
        numberRow: all.showsNumberRow, emojiKey: all.showsEmoji,
        recordKey: LayoutContext(device: device, layer: .letters, showsMicKey: true).showsMicKey,
        keyboardMenu: all.keyboardMenu == .hold,
        split: LayoutContext(device: device, layer: .letters, isLandscape: true, isOpen: Duo.isOpen(short: short))
            .allowsSplit,
        oneHanded: LayoutContext(device: device, layer: .letters).allowsOneHanded,
        largePanels: !KeyboardGeometry(LayoutContext(device: device, layer: .letters), screen: upright, style: .ios27)
            .metrics.toolbar.isCompact,
        characterPreview: device == .phone)
    return env.array(Json.encode(keys))
}

/// What a dictation heard with your Dictionary (`vocabulary.json`) put on it, as iOS's `VoiceVocabulary` puts it on
/// every dictation before it's typed.
@_cdecl("Java_com_shahidy_iikb_Vocabulary_corrected")
public func corrected(env: Env, _: jclass, text: jbyteArray?, vocabulary: jbyteArray?) -> jbyteArray? {
    let text = env.string(text) ?? ""
    guard let vocabulary = try? JSONDecoder().decode(Vocabulary.self, from: Data(env.bytes(vocabulary))) else {
        return env.array(text)
    }
    return env.array(vocabulary.corrected(text))
}

/// The taps the keyboard has learned where your thumbs land, from its saved memory (`typing-memory.json`).
@_cdecl("Java_com_shahidy_iikb_app_Core_taps")
public func taps(env: Env, _: jclass, memory: jbyteArray?) -> jint {
    guard let memory = try? JSONDecoder().decode(TypingMemory.self, from: Data(env.bytes(memory))) else { return 0 }
    return jint(clamping: memory.touches.finite().signatures.reduce(0) { $0 + $1.taps })
}
