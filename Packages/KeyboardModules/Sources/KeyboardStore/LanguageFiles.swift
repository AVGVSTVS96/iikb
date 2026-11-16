import Foundation
import KeyboardCore
import KeyboardEnglish

/// The word data of a language other than English, which the app downloads into the App Group's `Library/Languages/`
/// as `<id>.lexicon` and the keyboard reads in place. It downloads again, so the backup and iCloud leave it out.
/// English is bundled (`Lexicon.english`) and is what the keyboard types when a language's file isn't here.
/// Beside each file, `<id>.sha256` names the manifest entry it came from, so a build whose manifest names a newer list
/// sees the file as out of date, and the app downloads the new one while the keyboard goes on with the old.
/// Several languages typed at once also have all their words in one file, which the app makes (`merge`).
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
    /// it isn't here or isn't a lexicon. With several ids joined (`together`), all their words as the app merged them.
    public static func lexicon(_ id: String, in folder: URL? = folder) -> Lexicon? {
        if id == "en" { return .english }
        guard let url = url(of: id, in: folder), let bytes = Bytes.mapped(url) else { return nil }
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

    /// The name the words of several languages are kept under as one file: their ids in order, as `de+en`.
    public static func together(_ ids: [String]) -> String {
        ids.sorted().joined(separator: "+")
    }

    /// Keeps the words of the languages `ids` in one file, `<together>.lexicon` (`Lexicon(merging:)`), which the
    /// keyboard types several languages from, stamped with the lists it's made of, and drops the file of any other
    /// set. A file already made of these lists stays as it is. The app's to call, since merging holds every word in
    /// memory, more than a keyboard may; until the file is here the keyboard types the first language alone.
    /// True when the file changed.
    @discardableResult
    public static func merge(_ ids: [String], in folder: URL? = folder) -> Bool {
        guard let folder else { return false }
        let name = together(ids)
        // file: the languages' folder, for the merged files of other sets
        for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        where file.contains("+") && !file.hasPrefix("\(name).") {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
        let lexicons = ids.sorted().compactMap { id in lexicon(id, in: folder).map { (id: id, words: $0) } }
        guard ids.count > 1, lexicons.count == ids.count, var url = url(of: name, in: folder),
            let stamp = stamp(of: name, in: folder)
        else { return false }
        let parts = lexicons.map { "\($0.id) \(installed($0.id, in: folder) ?? String($0.words.bytes.count))" }
            .joined(separator: "\n")
        guard installed(name, in: folder) != parts else { return false }
        let merged = Lexicon(merging: lexicons.map(\.words))
        do {
            // file: merged languages
            try merged.bytes.withUnsafeBytes { try Data($0).write(to: url, options: .atomic) }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            try Data(parts.utf8).write(to: stamp, options: .atomic)  // file: language stamp
            return true
        } catch {
            return false
        }
    }
}
