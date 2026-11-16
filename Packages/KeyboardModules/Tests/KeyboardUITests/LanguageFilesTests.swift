import CryptoKit
import Foundation
import KeyboardCore
import KeyboardStore
import Testing

struct LanguageFilesTests {
    let folder = URL.temporaryDirectory.appending(path: "LanguageFiles \(UUID().uuidString)/Languages")

    /// A list of `words`, as a manifest names it, downloaded from a file here.
    private func list(_ words: String) throws -> Download {
        let file = URL.temporaryDirectory.appending(path: "list \(UUID().uuidString)")
        try Data(words.utf8).write(to: file)
        let digest = SHA256.hash(data: Data(words.utf8)).map { String(format: "%02x", $0) }.joined()
        return Download(url: file, size: words.utf8.count, sha256: digest)
    }

    private func words() throws -> String {
        try String(contentsOf: try #require(LanguageFiles.url(of: "de", in: folder)), encoding: .utf8)
    }

    @Test func aListFromAnOlderManifestIsOutOfDateUntilTheNewOneIsIn() async throws {
        let old = try list("ein")
        let new = try list("zwei")
        #expect(!LanguageFiles.isCurrent("de", as: old, in: folder))
        try await LanguageFiles.install("de", from: old, in: folder)
        #expect(LanguageFiles.isCurrent("de", as: old, in: folder))
        #expect(!LanguageFiles.isCurrent("de", as: new, in: folder), "the build's manifest names a newer list")
        #expect(LanguageFiles.has("de", in: folder), "the old list stays for the keyboard meanwhile")

        try await LanguageFiles.install("de", from: new, in: folder)
        #expect(LanguageFiles.isCurrent("de", as: new, in: folder))
        #expect(try words() == "zwei")
        #expect(LanguageFiles.installed("de", in: folder) == new.sha256)
    }

    @Test func aDamagedDownloadLeavesTheListItWouldReplace() async throws {
        let old = try list("ein")
        try await LanguageFiles.install("de", from: old, in: folder)
        let damaged = Download(url: try list("zwei").url, size: 4, sha256: old.sha256)
        await #expect(throws: Download.Failure.self) {
            try await LanguageFiles.install("de", from: damaged, in: folder)
        }
        #expect(try words() == "ein")
        #expect(LanguageFiles.isCurrent("de", as: old, in: folder))
    }

    @Test func aFileFromBeforeStampsIsOutOfDate() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("ein".utf8).write(to: try #require(LanguageFiles.url(of: "de", in: folder)))
        #expect(LanguageFiles.has("de", in: folder))
        #expect(LanguageFiles.installed("de", in: folder) == nil)
        #expect(!LanguageFiles.isCurrent("de", as: try list("ein"), in: folder))
    }

    private func keep(_ words: [String], as id: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lexicon = Lexicon(counts: words.map { (word: $0, count: 1) })
        try Data(lexicon.bytes).write(to: try #require(LanguageFiles.url(of: id, in: folder)))
    }

    @Test func severalLanguagesKeepTheirWordsInOneFile() throws {
        try keep(["über", "hand"], as: "de")
        try keep(["hej", "hand"], as: "sv")
        #expect(LanguageFiles.merge(["sv", "de"], in: folder))
        let both = try #require(LanguageFiles.lexicon(LanguageFiles.together(["sv", "de"]), in: folder))
        #expect(["über", "hej", "hand"].allSatisfy(both.isWord))
        #expect(!LanguageFiles.merge(["de", "sv"], in: folder), "made of the same lists, the file stays")

        try keep(["über", "hand", "heute"], as: "de")
        #expect(LanguageFiles.merge(["de", "sv"], in: folder), "a list changed")
        #expect(LanguageFiles.lexicon("de+sv", in: folder)?.isWord("heute") == true)

        #expect(!LanguageFiles.merge(["de"], in: folder))
        #expect(!LanguageFiles.has("de+sv", in: folder), "one language has no use for it")
    }

    @Test func removingTakesTheStampToo() async throws {
        let new = try list("ein")
        try await LanguageFiles.install("de", from: new, in: folder)
        LanguageFiles.remove("de", in: folder)
        #expect(!LanguageFiles.has("de", in: folder))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("ein".utf8).write(to: try #require(LanguageFiles.url(of: "de", in: folder)))
        #expect(
            !LanguageFiles.isCurrent("de", as: new, in: folder), "a stamp left behind would vouch for the wrong file")
    }
}
