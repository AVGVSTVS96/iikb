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
        /// Empty for an image.
        var text: String
        var kind: String
        /// `312 chars`, `48 words`; none for a link, an address, a number or a color, which show by kind.
        var length: String?
        /// `now`, `5m`, `2d`.
        var age: String
        var pinned: Bool
        /// When it was copied, in seconds since 1970.
        var found: Double
        var site: String?
        /// The site as a badge names it, `github`, `x`, with a part of its path where another link found shares it,
        /// `github/swift` (`ClipLink.names`).
        var name: String?
        var color: Int32?
        /// An image's file, by the name `Clips.kt` saved it under.
        var image: String?
    }

    func rows(matching search: String, in unit: ClipboardLength, now: Double) -> [Row] {
        let found = history.matching(search)
        let links = found.compactMap { if case .link(let link) = $0.content.kind { link } else { nil } }
        var names = ClipLink.names(links).makeIterator()
        return found.map { item in
            var row = Row(
                text: item.content.preview ?? "", kind: "text",
                length: ClipboardHistory.length(of: item.content, in: unit),
                age: ClipboardHistory.age(of: item.found, now: now), pinned: item.pinned, found: item.found)
            switch item.content.kind {
            case .link(let link):
                (row.kind, row.site, row.name) = ("link", link.site, names.next())
            case .email: row.kind = "email"
            case .phone: row.kind = "phone"
            case .color(let red, let green, let blue):
                row.kind = "color"
                row.color = Int32(bitPattern: 0xFF00_0000 | UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue))
            case .image: (row.kind, row.image) = ("image", item.content.fileName)
            case .text: break
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

/// A clip by its text, or, given `image`, by its image's file.
private func content(_ env: Env, text: jbyteArray?, image: jbyteArray?) -> ClipboardHistory.Item.Content? {
    if let image = env.string(image) { return .image(image) }
    return env.string(text).map { .text($0) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsKeep")
public func clipsKeep(env: Env, _: jclass, handle: jlong, text: jbyteArray?, image: jbyteArray?, time: jdouble) {
    guard let content = content(env, text: text, image: image), content.preview?.isEmpty != true else { return }
    clips(handle).history.keep(content, at: time)
}

/// The clips holding `search`, pinned first, then newest, as JSON rows.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsRows")
public func clipsRows(env: Env, _: jclass, handle: jlong, search: jbyteArray?, words: jboolean, now: jdouble)
    -> jbyteArray?
{
    env.array(
        Json.encode(
            clips(handle).rows(matching: env.string(search) ?? "", in: words != 0 ? .words : .characters, now: now)))
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsPin")
public func clipsPin(env: Env, _: jclass, handle: jlong, text: jbyteArray?, image: jbyteArray?, pinned: jboolean) {
    guard let content = content(env, text: text, image: image) else { return }
    clips(handle).history.setPinned(pinned != 0, content)
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsRemove")
public func clipsRemove(env: Env, _: jclass, handle: jlong, text: jbyteArray?, image: jbyteArray?) {
    guard let content = content(env, text: text, image: image) else { return }
    clips(handle).history.remove(content)
}

/// Deletes every clip but the pinned, and names the image files that went, as JSON.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_clipsClear")
public func clipsClear(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    let gone = clips(handle).history.removeUnpinned().compactMap { content -> String? in
        if case .image(let name) = content { name } else { nil }
    }
    return env.array(Json.encode(gone))
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
