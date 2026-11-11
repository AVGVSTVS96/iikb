import Foundation
import KeyboardCore
import KeyboardEnglish

/// The word data of a language other than English, which the app downloads into the App Group's `Library/Languages/`
/// as `<id>.lexicon` and the keyboard reads in place. It downloads again, so the backup and iCloud leave it out.
/// English is bundled (`Lexicon.english`) and is what the keyboard types when a language's file isn't here.
nonisolated public enum LanguageFiles {
    /// A language's file as `Resources/Languages/manifest.json` lists it, which `scripts/languages` writes as it
    /// publishes the files, so the app shows sizes and checks downloads without asking a server.
    public struct Download: Decodable, Sendable {
        public let id: String
        public let size: Int
        public let sha256: String
        public let url: URL
    }

    /// The manifest's files, by language.
    public static let downloads: [String: Download] = {
        struct Manifest: Decodable { let lexicons: [Download] }
        guard let url = Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "Languages"),
            let data = try? Data(contentsOf: url),  // file: bundled manifest
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return [:] }
        return Dictionary(manifest.lexicons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    public static var folder: URL? {
        AppGroup.library?.appending(path: "Languages", directoryHint: .isDirectory)
    }

    public static func url(of id: String) -> URL? {
        folder?.appending(path: "\(id).lexicon")
    }

    public static func has(_ id: String) -> Bool {
        url(of: id).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// The words the keyboard types for `id`: English's for English, a downloaded language's read in place, or nil when
    /// it isn't here or isn't a lexicon.
    public static func lexicon(_ id: String) -> Lexicon? {
        if id == "en" { return .english }
        guard let url = url(of: id), let bytes = Bytes.mapped(url) else { return nil }
        return Lexicon(bytes: bytes)
    }

    /// Puts a downloaded, checked file in place in one move, so the keyboard never maps half a file.
    public static func install(_ file: URL, as id: String) throws {
        guard let folder, var url = url(of: id) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: file)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    public static func remove(_ id: String) {
        if let url = url(of: id) { try? FileManager.default.removeItem(at: url) }
    }
}
