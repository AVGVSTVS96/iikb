import CJNI
import FoundationEssentials
import KeyboardCore

/// What each source you added is sent and the hint it last answered (KeyboardCore's `SourceFeed`, one per source), for
/// Kotlin's `keyboard.Sources`, which posts each update and hands the answer back. A feed has one update on its way at a
/// time, kept here until it's answered.
struct SourceFeeds {
    private var feeds: [SourceFeed] = []
    private var sent: [FieldUpdate?] = []

    mutating func reset(count: Int) {
        feeds = Array(repeating: SourceFeed(), count: count)
        sent = Array(repeating: nil, count: count)
    }

    mutating func observe(_ update: FieldUpdate) {
        for index in feeds.indices { feeds[index].observe(update) }
    }

    /// The request body for the update `index` sends now, unless one is already on its way (docs/sources.md).
    mutating func next(_ index: Int) -> [UInt8]? {
        guard feeds.indices.contains(index), let update = feeds[index].next() else { return nil }
        sent[index] = update
        return Json.encode(Request(update))
    }

    mutating func answered(_ index: Int, hint: String?) {
        guard sent.indices.contains(index), let update = sent[index] else { return }
        sent[index] = nil
        feeds[index].answered(update, hint: hint)
    }

    mutating func failed(_ index: Int) {
        guard sent.indices.contains(index), let update = sent[index] else { return }
        sent[index] = nil
        feeds[index].failed(update)
    }

    func hint(for field: String, app: String?) -> String? {
        feeds.lazy.compactMap { $0.hint(for: field, app: app) }.first
    }

    mutating func dismissHint() {
        feeds.indices.forEach { feeds[$0].dismissHint() }
    }

    private struct Request: Encodable {
        let app: String
        let field: String
        let before: String
        let after: String
        let by: String
        let kind: String
        let returnKey: String
        let at: String

        init(_ update: FieldUpdate) {
            app = update.app ?? ""
            field = update.field
            before = update.before
            after = update.after
            by = update.by.rawValue
            kind = "\(update.traits.kind)"
            returnKey = "\(update.traits.returnKind)"
            at = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(
                Date(timeIntervalSince1970: update.at))
        }
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_sourcesReset")
public func sourcesReset(env: Env, _: jclass, handle: jlong, count: jint) {
    keyboard(handle).sources.reset(count: Int(count))
}

/// The field as the keyboard knows it now, changed last by you (`keyboard`) or by the app.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_sourcesObserve")
public func sourcesObserve(
    env: Env, _: jclass, handle: jlong, field: jbyteArray?, app: jbyteArray?, byKeyboard: jboolean, at: jdouble
) {
    with(env, handle) { keyboard in
        keyboard.sources.observe(
            FieldUpdate(
                field: env.string(field) ?? "", before: keyboard.engine.text.before,
                after: keyboard.engine.text.after ?? "", by: byKeyboard != 0 ? .keyboard : .app,
                traits: keyboard.engine.traits, at: at, app: env.string(app)))
    }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_sourcesNext")
public func sourcesNext(env: Env, _: jclass, handle: jlong, index: jint) -> jbyteArray? {
    keyboard(handle).sources.next(Int(index)).flatMap { env.array($0) }
}

/// `hint` is the source's answer, nil for none; a source that couldn't be reached is `sourcesFailed`.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_sourcesAnswered")
public func sourcesAnswered(env: Env, _: jclass, handle: jlong, index: jint, hint: jbyteArray?) {
    keyboard(handle).sources.answered(Int(index), hint: env.string(hint))
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_sourcesFailed")
public func sourcesFailed(env: Env, _: jclass, handle: jlong, index: jint) {
    keyboard(handle).sources.failed(Int(index))
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_sourcesHint")
public func sourcesHint(env: Env, _: jclass, handle: jlong, field: jbyteArray?, app: jbyteArray?) -> jbyteArray? {
    keyboard(handle).sources.hint(for: env.string(field) ?? "", app: env.string(app)).flatMap { env.array($0) }
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_sourcesDismiss")
public func sourcesDismiss(env: Env, _: jclass, handle: jlong) {
    keyboard(handle).sources.dismissHint()
}
