import Foundation
import KeyboardCore
import KeyboardEnglish

/// The word data of a language other than English, which the app downloads into the App Group's `Library/Languages/`
/// as `<id>.lexicon` and the keyboard reads in place. It downloads again, so the backup and iCloud leave it out.
/// English is bundled (`Lexicon.english`) and is what the keyboard types when a language's file isn't here.
/// Beside each file, `<id>.sha256` names the manifest entry it came from, so a build whose manifest names a newer list
/// sees the file as out of date, and the app downloads the new one while the keyboard goes on with the old.
nonisolated public enum LanguageFiles {
    /// The files `Resources/Languages/manifest.json` lists, by language, which `scripts/languages` writes as it
    /// publishes them, so the app shows sizes and checks downloads without asking a server.
    public static let downloads: [String: Download] = {
        struct Listed: Decodable {
            let id: String
            let size: Int
            let sha256: String
            let url: URL
        }
        struct Manifest: Decodable { let lexicons: [Listed] }
        guard let url = Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "Languages"),
            let data = try? Data(contentsOf: url),  // file: bundled manifest
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return [:] }
        return Dictionary(
            manifest.lexicons.map { ($0.id, Download(url: $0.url, size: $0.size, sha256: $0.sha256)) },
            uniquingKeysWith: { first, _ in first })
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
    public static func isCurrent(_ id: String, as download: Download, in folder: URL? = folder) -> Bool {
        installed(id, in: folder) == download.sha256
    }

    /// The words the keyboard types for `id`: English's for English, a downloaded language's read in place, or nil when
    /// it isn't here or isn't a lexicon.
    public static func lexicon(_ id: String) -> Lexicon? {
        if id == "en" { return .english }
        guard let url = url(of: id), let bytes = Bytes.mapped(url) else { return nil }
        return Lexicon(bytes: bytes)
    }

    /// Downloads `id`'s file as `download` names it, which the keyboard reads only once it's whole and checked, then
    /// stamps it with the manifest entry it came from.
    public static func install(
        _ id: String, from download: Download, in folder: URL? = folder, resumingFrom resumeData: Data? = nil,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws(Download.Failure) {
        guard let url = url(of: id, in: folder), let stamp = stamp(of: id, in: folder) else {
            throw Download.Failure(reason: CocoaError(.fileNoSuchFile).localizedDescription)
        }
        try await download.fetch(to: url, resumingFrom: resumeData, progress: progress)
        do {
            try Data(download.sha256.utf8).write(to: stamp, options: .atomic)  // file: language stamp
        } catch {
            throw Download.Failure(reason: error.localizedDescription)
        }
    }

    public static func remove(_ id: String, in folder: URL? = folder) {
        for url in [url(of: id, in: folder), stamp(of: id, in: folder)].compactMap(\.self) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
