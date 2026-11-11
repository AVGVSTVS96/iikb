import CJNI
import FoundationEssentials
import KeyboardCore

// What the app's Stats tab reads from KeyboardCore: the hours the keyboard typed (`TypingLog`), and the board Taps draws,
// laid out and measured as iOS's `TapBoard` does.

private final class Log {
    var log = TypingLog()
}

private func log(_ handle: jlong) -> Log {
    Unmanaged<Log>.fromOpaque(UnsafeRawPointer(bitPattern: Int(handle))!).takeUnretainedValue()
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_typingLog")
public func typingLog(env: Env, _: jclass) -> jlong {
    jlong(Int(bitPattern: Unmanaged.passRetained(Log()).toOpaque()))
}

/// Notes the engine's tally at `time` (seconds on a steady clock), in the local `day` (`2026-11-04`) and hour, and the app.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_noteTyping")
public func noteTyping(
    env: Env, _: jclass, log handle: jlong, keyboard: jlong, time: jdouble, day: jbyteArray?, hour: jint,
    app: jbyteArray?
) {
    let keyboard = Unmanaged<Keyboard>.fromOpaque(UnsafeRawPointer(bitPattern: Int(keyboard))!).takeUnretainedValue()
    log(handle).log.note(
        keyboard.engine.tally, at: time, day: env.string(day) ?? "", hour: Int(hour), app: env.string(app) ?? "")
}

/// The hours noted since the last take, a `TypingHour` as JSON a line, as iOS's `TypingStats` keeps them.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_takeTyping")
public func takeTyping(env: Env, _: jclass, log handle: jlong) -> jbyteArray? {
    let hours = log(handle).log.take()
    return env.array(hours.flatMap { Json.encode($0) + [UInt8(ascii: "\n")] })
}

/// Taps' board for the screen named by `signature` (else the one the app is on, else the one with most taps), from the
/// kept `TypingMemory`, laid out with the settings' `name=value` lines on a `width` × `height` screen in dp, on a phone
/// that `folds` or not.
@_cdecl("Java_com_shahidy_iikb_keyboard_Native_taps")
public func taps(
    env: Env, _: jclass, memory: jbyteArray?, settings: jbyteArray?, signature: jbyteArray?, width: jdouble,
    height: jdouble, folds: jboolean
) -> jbyteArray? {
    let touches =
        (try? JSONDecoder().decode(TypingMemory.self, from: Data(env.bytes(memory))))?.touches.finite() ?? TouchModel()
    let screen = Size(width: width, height: height)
    let device = DeviceClass(screen: screen, folds: folds != 0)
    let board = TapsBoard(
        touches, settings: KeyboardSettings(parsing: env.string(settings) ?? ""), device: device, screen: screen,
        signature: env.string(signature))
    return env.array(Json.encode(board))
}

/// What Taps draws: the screens with taps, and for the picked one its keys and what each learned, keys by their place in
/// `keys`.
struct TapsBoard: Encodable {
    struct Screen: Encodable {
        let signature: String
        let title: String
        let taps: Int
    }

    struct Box: Encodable {
        let name: String
        /// What the keyboard draws on the key (`KeyFace.Content`'s kind and value), as the map shows a key that doesn't learn.
        let face, label: String
        let x, y, width, height: Double
        /// A letter or the space bar, which learn from your taps.
        let learns: Bool
    }

    struct Point: Encodable {
        let x, y: Double
    }

    struct Tap: Encodable {
        let x, y: Double
        let landed: Int?
    }

    struct Memory: Encodable {
        let x, y, weight: Double
    }

    struct Share: Encodable {
        let key: Int
        let share: Double
    }

    struct Learned: Encodable {
        let key: Int
        let taps: Int
        let center: Point
        let spread: [Double]
        let recent: [Tap]
        let memories: [Memory]
        let landing: [Share]
    }

    let screens: [Screen]
    let signature: String?
    let width: Double
    let height: Double
    let keys: [Box]
    let aims: [Learned]

    init(_ touches: TouchModel, settings: KeyboardSettings, device: DeviceClass, screen: Size, signature: String?) {
        let current = LayoutContext(device: device, layer: .letters, isLandscape: screen.width > screen.height)
            .signature
        let kept = touches.signatures.filter { LayoutContext(signature: $0.signature)?.device == device }
        screens = kept.map { Screen(signature: $0.signature, title: Self.title(of: $0.signature), taps: $0.taps) }
        let names = Set(kept.map(\.signature))
        let picked =
            signature.flatMap { names.contains($0) ? $0 : nil } ?? (names.contains(current) ? current : nil)
            ?? kept.first?.signature
        self.signature = picked
        guard let picked, let kept = LayoutContext(signature: picked) else {
            (width, height, keys, aims) = (0, 0, [], [])
            return
        }
        var context = LayoutContext(
            device: device, layer: kept.layer, screen: kept.screen(on: screen), settings: settings)
        context.oneHanded = kept.oneHanded
        context.isSplit = kept.isSplit
        (context.language, context.letters) = (kept.language, kept.letters)
        let geometry = KeyboardGeometry(context, screen: kept.screen(on: screen), style: .ios27)
        let grid = KeyGrid(geometry.layout, width: geometry.width, metrics: geometry.metrics.grid, signature: picked)
        let items = Array(grid.rows.joined())
        let faces = KeyFaceContext(
            device: device, layer: kept.layer, kind: .text, shift: .off, returnKind: .default, returnEnabled: true)
        width = geometry.width
        height = geometry.height
        keys = items.map { key, frame in
            let face = KeyFace(key, trailing: frame.midX > geometry.width / 2, context: faces).content
            return Box(
                name: Self.name(of: key), face: face.kind, label: face.value, x: frame.x, y: frame.y,
                width: frame.width, height: frame.height, learns: key.label != nil)
        }
        let index = { (key: Key?) in key.flatMap { key in items.firstIndex { $0.key == key } } }
        aims = touches.aims(on: grid).compactMap { aim in
            index(aim.key).map { key in
                Learned(
                    key: key, taps: aim.taps, center: Point(x: aim.center.x, y: aim.center.y),
                    spread: [aim.spread.xx, aim.spread.xy, aim.spread.yy],
                    recent: aim.recent.map { Tap(x: $0.x, y: $0.y, landed: index($0.landed)) },
                    memories: aim.memories.map { Memory(x: $0.center.x, y: $0.center.y, weight: $0.weight) },
                    landing: aim.landing.compactMap { landing in
                        index(landing.key).map { Share(key: $0, share: landing.share) }
                    })
            }
        }
    }

    /// A screen as Taps names it: which way the phone was held, then the keys and hand when they weren't the usual.
    static func title(of signature: String) -> String {
        guard let context = LayoutContext(signature: signature) else { return signature }
        let layer =
            switch context.layer {
            case .letters: ""
            case .numbers: ", numbers"
            case .symbols: ", symbols"
            }
        let hand =
            switch context.oneHanded {
            case .left: ", left hand"
            case .right: ", right hand"
            case .off: ""
            }
        return (context.isLandscape ? "Landscape" : "Portrait") + layer + hand + (context.isSplit ? ", split" : "")
    }

    /// A key as iOS's `TapMapPalette.name(of:)` names it.
    static func name(of key: Key) -> String {
        switch key.action {
        case .character(let value): value
        case .space: "space"
        case .delete: "delete"
        case .shift, .capsLock: "shift"
        case .return: "return"
        case .tab: "tab"
        case .layer(.letters): "ABC"
        case .layer(.numbers): "123"
        case .layer(.symbols): "#+="
        case .nextKeyboard, .globeSpacer: "globe"
        case .dictate: "record"
        case .dismiss: "hide"
        case .undo: "undo"
        case .redo: "redo"
        case .emoji: "emoji"
        }
    }
}
