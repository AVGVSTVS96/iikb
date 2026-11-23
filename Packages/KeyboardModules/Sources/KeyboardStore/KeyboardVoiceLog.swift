import Foundation

/// What the keyboard's own dictations did (FullKeyboard's `LocalDictation`), its last 300 lines and a day back at most,
/// in the group's `Library/Application Support`, which the backup carries with the app's: the app reads only its own
/// process's log, so it adds these to its voice log too (`VoiceLog`).
nonisolated public enum KeyboardVoiceLog {
    public struct Line: Codable, Sendable {
        public var at: Date
        public var text: String
    }

    private static var file: StoredFile<[Line]>? {
        AppGroup.library.map { StoredFile($0.appending(path: "Application Support/keyboard-voice.json")) }
    }

    private static let queue = DispatchQueue(label: "com.shahidy.iikb.keyboard-voice-log", qos: .utility)

    public static func write(_ text: String) {
        let line = Line(at: .now, text: text)
        queue.async {
            guard let file else { return }
            let kept = (file.read().value ?? []).filter { line.at.timeIntervalSince($0.at) < 86_400 }.suffix(299)
            file.save(kept + [line])
        }
    }

    public static func read() -> [Line] {
        file?.read().value ?? []
    }
}
