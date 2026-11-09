import CJNI
import FoundationEssentials
import KeyboardCore

/// What you copied, as `ClipboardHistory` keeps it (docs/design.md, "Clipboard"). Kotlin's `Clips` holds one for the
/// app's process, so the keyboard and the app's Clipboard tab share it, and saves it as this JSON.
final class Clips {
    var history: ClipboardHistory

    init(_ json: [UInt8]) {
        history = (try? JSONDecoder().decode(ClipboardHistory.self, from: Data(json))) ?? ClipboardHistory()
    }

    /// One clip as a row, a card or a link's badge draws it.
    struct Row: Encodable {
        var text: String
        var kind: String
        /// `312 chars`, `48 words`; none for a link, an address, a number or a color, which show by kind.
        var length: String?
        /// `now`, `5m`, `2d`.
        var age: String
        var pinned: Bool
        var site: String?
        /// The site as a badge names it: `github`, `x`.
        var name: String?
        var color: Int32?
    }

    func rows(matching search: String, in unit: ClipboardLength, now: Double) -> [Row] {
        history.matching(search).compactMap { item in
            guard let text = item.content.preview else { return nil }
            var row = Row(
                text: text, kind: "text", length: ClipboardHistory.length(of: item.content, in: unit),
                age: ClipboardHistory.age(of: item.found, now: now), pinned: item.pinned)
            switch item.content.kind {
            case .link(let link):
                (row.kind, row.site, row.name) = ("link", link.site, link.name)
            case .email: row.kind = "email"
            case .phone: row.kind = "phone"
            case .color(let red, let green, let blue):
                row.kind = "color"
                row.color = Int32(bitPattern: 0xFF00_0000 | UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue))
            case .text, .image: break
            }
            return row
        }
    }
}

private func clips(_ handle: jlong) -> Clips {
    Unmanaged<Clips>.fromOpaque(UnsafeRawPointer(bitPattern: Int(handle))!).takeUnretainedValue()
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsCreate")
public func clipsCreate(env: Env, _: jclass, json: jbyteArray?) -> jlong {
    jlong(Int(bitPattern: Unmanaged.passRetained(Clips(env.bytes(json))).toOpaque()))
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsSave")
public func clipsSave(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    env.array(Json.encode(clips(handle).history))
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsKeep")
public func clipsKeep(env: Env, _: jclass, handle: jlong, text: jbyteArray?, time: jdouble) {
    guard let text = env.string(text), !text.isEmpty else { return }
    clips(handle).history.keep(.text(text), at: time)
}

/// The clips holding `search`, pinned first, then newest, as JSON rows.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsRows")
public func clipsRows(env: Env, _: jclass, handle: jlong, search: jbyteArray?, words: jboolean, now: jdouble)
    -> jbyteArray?
{
    env.array(
        Json.encode(clips(handle).rows(matching: env.string(search) ?? "", in: words != 0 ? .words : .characters, now: now)))
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsPin")
public func clipsPin(env: Env, _: jclass, handle: jlong, text: jbyteArray?, pinned: jboolean) {
    guard let text = env.string(text) else { return }
    clips(handle).history.setPinned(pinned != 0, .text(text))
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsRemove")
public func clipsRemove(env: Env, _: jclass, handle: jlong, text: jbyteArray?) {
    guard let text = env.string(text) else { return }
    clips(handle).history.remove(.text(text))
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsClear")
public func clipsClear(env: Env, _: jclass, handle: jlong) {
    _ = clips(handle).history.removeUnpinned()
}

/// How long ago, as a row shows it: "now", "5m", "2d" (`ClipboardHistory.age`).
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_age")
public func age(env: Env, _: jclass, found: jdouble, now: jdouble) -> jbyteArray? {
    env.array(ClipboardHistory.age(of: found, now: now))
}

/// A text's length as a row shows it: "48 words", "312 chars" (`ClipboardHistory.length`).
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_length")
public func length(env: Env, _: jclass, text: jbyteArray?, words: jboolean) -> jbyteArray? {
    env.array(ClipboardHistory.length(of: env.string(text) ?? "", in: words != 0 ? .words : .characters))
}
