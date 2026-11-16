import Foundation
import KeyboardCore

/// `VoiceText <en.lexicon> <vocabulary.json> <typing-memory.json|-> <style> <editing> <lists> <auto-capitalization on|off>`: for each
/// `{id, heard, edited?, field?, content?, before?}` line on stdin, what iikb types for what the voice model wrote (`heard`)
/// and a language model's reply to it (`edited`), as the iPhone does it: the app's writing and Dictionary
/// (`DictationWriting.typed` and `.plain` in App/Voice), then the keyboard's
/// reading of a field of that kind and content type (`InputKind`'s and `InputContent`'s names, text and other by
/// default) after `before` (`TypingEngine`'s `.dictated`),
/// with the words the keyboard has seen typed (the keyboard's saved memory, as scripts/gate reads it).
/// A line's own `memory`, `vocabulary` and `settings` (the four above) stand in for the arguments, so scripts/voiceloop
/// replays each dictation with what the iPhone had then.
/// Writes `{id, typed, edited}` lines, `edited` saying the reply was what was typed, so a gate can tell the model's line
/// from the rules'; scripts/voiceloop runs it here on Linux, on a package of KeyboardCore alone.
struct Clip: Decodable {
    let id, heard: String
    let edited, field, content, before, memory, vocabulary: String?
    let settings: [String]?
}
struct Row: Encodable {
    let id, typed: String
    let edited: Bool
}
struct Saved: Decodable { var memory: TypingMemory }

final class Field: TextDocument {
    var before: String
    var after = ""
    init(_ before: String) { self.before = before }
    var textBeforeInput: String? { before }
    var textAfterInput: String? { after }
    func insert(_ text: String) { before += text }
    func deleteBackward(_ count: Int) { before.removeLast(min(count, before.count)) }
    func moveCursor(by offset: Int) {
        let moved = offset < 0 ? before.count - max(before.count + offset, 0) : min(offset, after.count)
        if offset < 0 {
            after = before.suffix(moved) + after
            before.removeLast(moved)
        } else {
            before += after.prefix(moved)
            after.removeFirst(moved)
        }
    }
}

let arguments = CommandLine.arguments
let lexicon = Lexicon(bytes: Bytes([UInt8](FileManager.default.contents(atPath: arguments[1])!)))!

func settings(_ knobs: [String]) -> KeyboardSettings {
    var settings = KeyboardSettings()
    settings.dictationStyle = DictationStyle(rawValue: knobs[0])!
    settings.dictationEditing = DictationEditing(rawValue: knobs[1])!
    settings.dictationLists = DictationLists(rawValue: knobs[2])!
    settings.autoCapitalization = knobs[3] == "on"
    return settings
}

func vocabulary(_ path: String) throws -> Vocabulary {
    try JSONDecoder().decode(Vocabulary.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

func corrector(_ path: String) throws -> Corrector {
    let corrector = Corrector(source: lexicon)
    if path != "-" {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let memory = try decoder.decode(Saved.self, from: Data(contentsOf: URL(fileURLWithPath: path))).memory
        corrector.changeMemory { $0 = memory }
    }
    return corrector
}

var vocabularies: [String: Vocabulary] = [:]
var correctors: [String: Corrector] = [:]
var lines: [String] = []
while let line = readLine() {
    let clip = try JSONDecoder().decode(Clip.self, from: Data(line.utf8))
    let settings = settings(clip.settings ?? Array(arguments[4...7]))
    let dictionary = clip.vocabulary ?? arguments[2]
    let memory = clip.memory ?? arguments[3]
    if vocabularies[dictionary] == nil { vocabularies[dictionary] = try vocabulary(dictionary) }
    if correctors[memory] == nil { correctors[memory] = try corrector(memory) }
    let vocabulary = vocabularies[dictionary]!
    var engine = TypingEngine(
        traits: InputTraits(
            kind: clip.field.flatMap(InputKind.init) ?? .text,
            content: clip.content.flatMap(InputContent.init) ?? .other))
    engine.settings = settings
    engine.corrector = correctors[memory]
    let field = Field(clip.before ?? "")
    let writing = settings.dictation(in: nil)
    engine.handle(
        .dictated(
            vocabulary.corrected(writing.written(clip.heard, edited: clip.edited), lexicon: lexicon),
            plain: vocabulary.corrected(clip.heard, lexicon: lexicon)), in: field)
    let kept = zip(clip.before ?? "", field.before).prefix { $0 == $1 }.count
    let row = Row(
        id: clip.id, typed: String(field.before.dropFirst(kept)),
        edited: clip.edited.map { writing.takes($0, of: clip.heard) } ?? false)
    lines.append(String(decoding: try JSONEncoder().encode(row), as: UTF8.self))
}
print(lines.joined(separator: "\n"))
