import Foundation
import KeyboardCore

/// Your `Vocabulary`, for the dictations the keyboard writes down itself: the app keeps it in its own container, where
/// the keyboard can't reach, so it writes this copy to the App Group's caches each time it changes and as it starts.
/// It's only a copy, so the backup leaves it out and iOS may clear it.
nonisolated public enum VocabularyFeed {
    private static var file: StoredFile<Vocabulary>? {
        AppGroup.library.map { StoredFile($0.appending(path: "Caches/vocabulary.json")) }
    }

    public static func share(_ vocabulary: Vocabulary) {
        file?.save(vocabulary)
    }

    public static func read() -> Vocabulary {
        file?.read().value ?? Vocabulary()
    }
}
