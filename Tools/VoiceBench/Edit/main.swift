import Foundation
import VoiceEditor

/// `VoiceEdit <weights.gguf>`: for each `{id, heard}` line on stdin, `{id, heard, edited, ms}`, where `edited` is the
/// reply of the app's own `Editor` (Packages/Voice/Sources/VoiceEditor) with the weights the app ships
/// (`Weights.shipped`), and `ms` how long it took. Where the editor gave no reply, `edited` is missing and `failure`
/// says why, and iikb types the dictation without the model. Built by scripts/stages.py, on the Mac or here on Linux.
/// `VoiceEdit --weights` prints the shipped weights' name, URL, size and SHA-256, for scripts/stages.py to fetch them.
struct Clip: Decodable { let id, heard: String }
struct Row: Encodable {
    let id, heard: String
    var edited, failure: String?
    var ms = 0
}
struct Shipped: Encodable {
    let name, url, sha256: String
    let bytes: Int
}

let encoder = JSONEncoder()
encoder.outputFormatting = .withoutEscapingSlashes
func printed(_ value: some Encodable) throws { print(String(decoding: try encoder.encode(value), as: UTF8.self)) }

let weights = Weights.shipped
if CommandLine.arguments[1] == "--weights" {
    try printed(
        Shipped(name: weights.name, url: weights.url.absoluteString, sha256: weights.sha256, bytes: weights.bytes))
} else {
    let editor = try await Editor(weights, at: URL(filePath: CommandLine.arguments[1]))
    while let line = readLine() {
        let clip = try JSONDecoder().decode(Clip.self, from: Data(line.utf8))
        var row = Row(id: clip.id, heard: clip.heard)
        let began = ContinuousClock.now
        do { row.edited = try await editor.edit(clip.heard) } catch { row.failure = "\(error)" }
        row.ms = Int((ContinuousClock.now - began) / .milliseconds(1))
        try printed(row)
    }
}
