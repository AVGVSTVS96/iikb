import Foundation
import Testing

@testable import VoiceCore

struct TranscriberTests {
    @Test func halfADownloadIsntADownload() throws {
        let parent = URL.temporaryDirectory.appending(path: "transcriber-\(UUID().uuidString)")
        let folder = parent.appending(path: "parakeet-tdt-0.6b-v3-coreml")
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(!Transcriber.isDownloaded(.v3, in: folder))
        try FileManager.default.createDirectory(
            at: folder.appending(path: "Preprocessor.mlmodelc"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appending(path: "parakeet_vocab.json"))
        try Data().write(to: folder.appending(path: "Encoder.mlmodelc.partial"))
        #expect(!Transcriber.isDownloaded(.v3, in: folder))
        #expect(!Transcriber.isDownloaded(.apple, in: folder))
    }
}
