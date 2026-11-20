import Foundation

/// What you dictated, for the keyboard's Transcripts panel: the app keeps its transcripts in its own container, where
/// the keyboard can't reach, so it writes this copy to the App Group's caches each time they change and as it starts.
/// It's only a copy, so the backup leaves it out and iOS may clear it. The dictations the keyboard made itself show too,
/// until the app has them (`Dictation.made`).
nonisolated public enum TranscriptFeed {
    public struct Entry: Codable, Hashable, Sendable {
        public var id: String
        /// When it was said, in seconds since 1970.
        public var date: Double
        public var text: String

        public init(id: String, date: Double, text: String) {
            self.id = id
            self.date = date
            self.text = text
        }
    }

    private static var file: StoredFile<[Entry]>? {
        AppGroup.library.map { StoredFile($0.appending(path: "Caches/transcripts.json")) }
    }

    /// Newest first.
    public static func share(_ entries: [Entry]) {
        file?.save(entries)
    }

    /// Reads the file, so call it off the main thread.
    public static func read() -> [Entry] {
        let shared = file?.read().value ?? []
        let kept = Set(shared.map(\.id))
        let made = Dictation.made.map(\.made).compactMap { made in
            made.written.map(\.text).flatMap { $0.isEmpty || kept.contains(made.id.uuidString) ? nil : $0 }.map {
                Entry(id: made.id.uuidString, date: made.date.timeIntervalSince1970, text: $0)
            }
        }
        return (made + shared).sorted { $0.date > $1.date }
    }
}
