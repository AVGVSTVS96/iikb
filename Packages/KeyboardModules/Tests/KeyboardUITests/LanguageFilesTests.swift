import Foundation
import KeyboardStore
import Testing

struct LanguageFilesTests {
    let folder = URL.temporaryDirectory.appending(path: "LanguageFiles \(UUID().uuidString)/Languages")
    let old = LanguageFiles.Download(id: "de", size: 3, sha256: "old", url: URL(string: "https://example.com/de")!)
    let new = LanguageFiles.Download(id: "de", size: 3, sha256: "new", url: URL(string: "https://example.com/de")!)

    private func downloaded(_ words: String) throws -> URL {
        let file = URL.temporaryDirectory.appending(path: "download \(UUID().uuidString)")
        try Data(words.utf8).write(to: file)
        return file
    }

    private func words() throws -> String {
        try String(contentsOf: try #require(LanguageFiles.url(of: "de", in: folder)), encoding: .utf8)
    }

    @Test func aListFromAnOlderManifestIsOutOfDateUntilTheNewOneIsIn() throws {
        #expect(!LanguageFiles.isCurrent(old, in: folder))
        try LanguageFiles.install(downloaded("ein"), as: old, in: folder)
        #expect(LanguageFiles.isCurrent(old, in: folder))
        #expect(!LanguageFiles.isCurrent(new, in: folder), "the build's manifest names a newer list")
        #expect(LanguageFiles.has("de", in: folder), "the old list stays for the keyboard meanwhile")

        try LanguageFiles.install(downloaded("zwei"), as: new, in: folder)
        #expect(LanguageFiles.isCurrent(new, in: folder))
        #expect(try words() == "zwei")
        #expect(LanguageFiles.installed("de", in: folder) == "new")
    }

    @Test func aFileFromBeforeStampsIsOutOfDate() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("ein".utf8).write(to: try #require(LanguageFiles.url(of: "de", in: folder)))
        #expect(LanguageFiles.has("de", in: folder))
        #expect(LanguageFiles.installed("de", in: folder) == nil)
        #expect(!LanguageFiles.isCurrent(new, in: folder))
    }

    @Test func removingTakesTheStampToo() throws {
        try LanguageFiles.install(downloaded("ein"), as: new, in: folder)
        LanguageFiles.remove("de", in: folder)
        #expect(!LanguageFiles.has("de", in: folder))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("ein".utf8).write(to: try #require(LanguageFiles.url(of: "de", in: folder)))
        #expect(!LanguageFiles.isCurrent(new, in: folder), "a stamp left behind would vouch for the wrong file")
    }
}
