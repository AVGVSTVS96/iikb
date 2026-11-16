import Foundation
import KeyboardCore
import KeyboardEnglish

/// The data of a language other than English, which the app downloads into the App Group's `Library/Languages/` and
/// the keyboard reads in place: its words, `<id>.lexicon`, and its next-word network, `<id>.network`. It downloads
/// again, so the backup and iCloud leave it out. English is bundled (`Lexicon.english`, `Network.english`) and is what
/// the keyboard types when a language's words aren't here; a language whose words are here and network isn't yet
/// types without one. Beside each file, `<name>.sha256` names the manifest entry it came from, so a build whose
/// manifest names a newer file sees it as out of date, and the app downloads the new one while the keyboard goes on
/// with the old.
nonisolated public enum LanguageFiles {
    /// One of a language's files as `Resources/Languages/manifest.json` lists it, which `scripts/languages` writes as
    /// it publishes the files, so the app shows sizes and checks downloads without asking a server.
    public struct File: Decodable, Sendable {
        public let id: String
        public let name: String
        public let size: Int
        public let sha256: String
        public let url: URL

        public init(id: String, name: String, size: Int, sha256: String, url: URL) {
            self.id = id
            self.name = name
            self.size = size
            self.sha256 = sha256
            self.url = url
        }
    }

    /// A language's files, downloaded together.
    public struct Download: Sendable {
        public let id: String
        public let files: [File]

        public var size: Int { files.reduce(0) { $0 + $1.size } }

        public init(id: String, files: [File]) {
            self.id = id
            self.files = files
        }
    }

    /// The manifest's files, by language.
    public static let downloads: [String: Download] = {
        struct Manifest: Decodable { let files: [File] }
        guard let url = Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "Languages"),
            let data = try? Data(contentsOf: url),  // file: bundled manifest
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return [:] }
        return Dictionary(grouping: manifest.files, by: \.id).mapValues { Download(id: $0[0].id, files: $0) }
    }()

    public static var folder: URL? {
        AppGroup.library?.appending(path: "Languages", directoryHint: .isDirectory)
    }

    /// Where a language's words are.
    public static func url(of id: String, in folder: URL? = folder) -> URL? {
        folder?.appending(path: "\(id).lexicon")
    }

    private static func stamp(of name: String, in folder: URL?) -> URL? {
        folder?.appending(path: "\(name).sha256")
    }

    /// Whether a language's words are here, so the keyboard can type it.
    public static func has(_ id: String, in folder: URL? = folder) -> Bool {
        url(of: id, in: folder).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// The SHA-256 of the manifest entries the language's files here came from, nil when its words aren't here, so
    /// it changes when any of them does.
    public static func installed(_ id: String, in folder: URL? = folder) -> String? {
        guard has(id, in: folder) else { return nil }
        return ["lexicon", "network"].map { stamped("\(id).\($0)", in: folder) ?? "" }.joined(separator: " ")
    }

    private static func stamped(_ name: String, in folder: URL?) -> String? {
        guard let file = folder?.appending(path: name), FileManager.default.fileExists(atPath: file.path),
            let stamp = stamp(of: name, in: folder)
        else { return nil }
        return try? String(contentsOf: stamp, encoding: .utf8)  // file: language stamp
    }

    /// Whether the file here is the one `file` names, rather than one an older build downloaded.
    public static func isCurrent(_ file: File, in folder: URL? = folder) -> Bool {
        stamped(file.name, in: folder) == file.sha256
    }

    /// Whether every one of the language's files here is the one the manifest names.
    public static func isCurrent(_ download: Download, in folder: URL? = folder) -> Bool {
        download.files.allSatisfy { isCurrent($0, in: folder) }
    }

    /// The words the keyboard types for `id`: English's for English, a downloaded language's read in place, or nil when
    /// it isn't here or isn't a lexicon.
    public static func lexicon(_ id: String) -> Lexicon? {
        if id == "en" { return .english }
        guard let url = url(of: id), let bytes = Bytes.mapped(url) else { return nil }
        return Lexicon(bytes: bytes)
    }

    /// What a downloaded language expects to come next, read in place, or nil when it isn't here or isn't a network.
    /// English's is `Network.current`.
    public static func network(_ id: String) -> Network? {
        guard let url = folder?.appending(path: "\(id).network"), let bytes = Bytes.mapped(url) else { return nil }
        return Network(bytes: bytes)
    }

    /// Puts a downloaded, checked file in place in one move, so the keyboard never maps half a file, then stamps it
    /// with the manifest entry it came from.
    public static func install(_ downloaded: URL, as file: File, in folder: URL? = folder) throws {
        guard let folder, let stamp = stamp(of: file.name, in: folder) else { throw CocoaError(.fileNoSuchFile) }
        var url = folder.appending(path: file.name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: downloaded)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        try Data(file.sha256.utf8).write(to: stamp, options: .atomic)  // file: language stamp
    }

    /// Removes every file of the language here, and their stamps.
    public static func remove(_ id: String, in folder: URL? = folder) {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix("\(id).") {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }
}
