import Foundation
import KeyboardCore
import KeyboardEnglish

/// The word data of a language other than English, which the app downloads into the App Group's `Library/Languages/`
/// as `<id>.lexicon` and the keyboard reads in place. It downloads again, so the backup and iCloud leave it out.
/// English is bundled (`Lexicon.english`) and is what the keyboard types when a language's file isn't here.
/// Beside each file, `<id>.sha256` names the manifest entry it came from, so a build whose manifest names a newer list
/// sees the file as out of date, and the app downloads the new one while the keyboard goes on with the old.
nonisolated public enum LanguageFiles {
    /// A language's file as `Resources/Languages/manifest.json` lists it, which `scripts/languages` writes as it
    /// publishes the files, so the app shows sizes and checks downloads without asking a server.
    public struct Download: Decodable, Sendable {
        public let id: String
        public let size: Int
        public let sha256: String
        public let url: URL

        public init(id: String, size: Int, sha256: String, url: URL) {
            self.id = id
            self.size = size
            self.sha256 = sha256
            self.url = url
        }
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

    public static func url(of id: String, in folder: URL? = folder) -> URL? {
        folder?.appending(path: "\(id).lexicon")
    }

    private static func stamp(of id: String, in folder: URL?) -> URL? {
        folder?.appending(path: "\(id).sha256")
    }

    public static func has(_ id: String, in folder: URL? = folder) -> Bool {
        url(of: id, in: folder).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// The SHA-256 of the manifest entry the file here came from, or nil when there's no file or it came before stamps.
    public static func installed(_ id: String, in folder: URL? = folder) -> String? {
        guard has(id, in: folder), let stamp = stamp(of: id, in: folder) else { return nil }
        return try? String(contentsOf: stamp, encoding: .utf8)  // file: language stamp
    }

    /// Whether the file here is the one `download` names, rather than a list an older build downloaded.
    public static func isCurrent(_ download: Download, in folder: URL? = folder) -> Bool {
        installed(download.id, in: folder) == download.sha256
    }

    /// The words the keyboard types for `id`: English's for English, a downloaded language's read in place, or nil when
    /// it isn't here or isn't a lexicon.
    public static func lexicon(_ id: String) -> Lexicon? {
        if id == "en" { return .english }
        guard let url = url(of: id), let bytes = Bytes.mapped(url) else { return nil }
        return Lexicon(bytes: bytes)
    }

    /// Puts a downloaded, checked file in place in one move, so the keyboard never maps half a file, then stamps it
    /// with the manifest entry it came from.
    public static func install(_ file: URL, as download: Download, in folder: URL? = folder) throws {
        guard let folder, var url = url(of: download.id, in: folder), let stamp = stamp(of: download.id, in: folder)
        else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: file)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        try Data(download.sha256.utf8).write(to: stamp, options: .atomic)  // file: language stamp
    }

    public static func remove(_ id: String, in folder: URL? = folder) {
        for url in [url(of: id, in: folder), stamp(of: id, in: folder)].compactMap(\.self) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
