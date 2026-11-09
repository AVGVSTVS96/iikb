import CJNI
import FoundationEssentials
import KeyboardCore

/// The GIF panel's search and recents (docs/design.md, "GIF"): KeyboardCore's `GifSearch` decides which one request is
/// out and what shows, Kotlin sends it to KLIPY and hands back what came. A feed crosses as `trending`,
/// `search:<words>` or `recents`; recents are the slugs `GifRecents` keeps.
final class Gifs {
    var search = GifSearch()
    var recents: GifRecents

    init(_ json: [UInt8]) {
        recents = (try? JSONDecoder().decode(GifRecents.self, from: Data(json))) ?? GifRecents()
    }

    func feed(_ name: String, app: String?) -> GifSearch.Feed {
        if name == "recents" { return .recents(recents.slugs(in: app)) }
        if name.hasPrefix("search:") { return GifSearch.feed(for: String(name.dropFirst(7))) }
        return .trending
    }

    struct Request: Encodable {
        var feed: String
        var page: Int
        /// The slugs a recents request fetches.
        var slugs: [String]
    }

    func request(_ feed: GifSearch.Feed?, page: Int = 1) -> Request? {
        switch feed {
        case nil: nil
        case .trending: Request(feed: "trending", page: page, slugs: [])
        case .search(let words): Request(feed: "search:\(words)", page: page, slugs: [])
        case .recents(let slugs): Request(feed: "recents", page: page, slugs: slugs)
        }
    }

    struct Shown: Encodable {
        /// `loading`, `gifs` or `failed`.
        var state: String
        var gifs: [Gif]
    }

    var shown: Shown {
        switch search.results {
        case .loading: Shown(state: "loading", gifs: [])
        case .failed: Shown(state: "failed", gifs: [])
        case .gifs(let gifs): Shown(state: "gifs", gifs: gifs)
        }
    }
}

private func gifs(_ handle: jlong) -> Gifs {
    Unmanaged<Gifs>.fromOpaque(UnsafeRawPointer(bitPattern: Int(handle))!).takeUnretainedValue()
}

private func encoded(_ env: Env, _ request: Gifs.Request?) -> jbyteArray? {
    request.map { env.array(Json.encode($0)) } ?? nil
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_gifsCreate")
public func gifsCreate(env: Env, _: jclass, recents: jbyteArray?) -> jlong {
    jlong(Int(bitPattern: Unmanaged.passRetained(Gifs(env.bytes(recents))).toOpaque()))
}

/// Shows a feed; returns the request to send now, if one should go out.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_gifsWant")
public func gifsWant(env: Env, _: jclass, handle: jlong, feed: jbyteArray?, app: jbyteArray?) -> jbyteArray? {
    let gifs = gifs(handle)
    return encoded(env, gifs.request(gifs.search.want(gifs.feed(env.string(feed) ?? "", app: env.string(app)))))
}

/// The next page of what shows, scrolled near its end, if there's one and no request is out.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_gifsMore")
public func gifsMore(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    let gifs = gifs(handle)
    guard let (feed, page) = gifs.search.more() else { return nil }
    return encoded(env, gifs.request(feed, page: page))
}

/// What a request brought: its GIFs as JSON (`[Gif]`), or none when it failed. Returns the next request, if any.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_gifsReceived")
public func gifsReceived(
    env: Env, _: jclass, handle: jlong, request: jbyteArray?, found: jbyteArray?, hasNext: jboolean
) -> jbyteArray? {
    let gifs = gifs(handle)
    struct Sent: Decodable {
        var feed: String
        var page: Int
        var slugs: [String]
    }
    guard let sent = try? JSONDecoder().decode(Sent.self, from: Data(env.bytes(request))) else { return nil }
    let feed: GifSearch.Feed = sent.feed == "recents" ? .recents(sent.slugs) : gifs.feed(sent.feed, app: nil)
    let list = found.flatMap { try? JSONDecoder().decode([Gif].self, from: Data(env.bytes($0))) }
    return encoded(env, gifs.request(gifs.search.received(list, for: feed, page: sent.page, hasNext: hasNext != 0)))
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_gifsShown")
public func gifsShown(env: Env, _: jclass, handle: jlong) -> jbyteArray? {
    env.array(Json.encode(gifs(handle).shown))
}

/// A GIF sent: it goes first in recents. Returns recents to save.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_gifsUse")
public func gifsUse(env: Env, _: jclass, handle: jlong, slug: jbyteArray?, app: jbyteArray?) -> jbyteArray? {
    let gifs = gifs(handle)
    guard let slug = env.string(slug) else { return nil }
    gifs.recents.use(slug, app: env.string(app))
    return env.array(Json.encode(gifs.recents))
}
