import Foundation
import KeyboardCore

/// `VoiceText <en.lexicon> <vocabulary.json> <typing-memory.json|-> <style> <editing> <lists> <auto-capitalization on|off>`: for each
/// `{id, heard, field?, content?, before?, languages?}` line on stdin, what iikb types for what the voice model wrote
/// (`heard`), as the iPhone does it: the language it was said in, of the line's `languages` (ids, in the order picked,
/// English alone by default) and English (`Language.of`), the app's writing and Dictionary in it (`VoiceModel.write` in
/// App/Voice), then the keyboard's reading of a field of that kind and content type (`InputKind`'s and `InputContent`'s
/// names, text and other by default) after `before` (`TypingEngine`'s `.dictated`),
/// with the words the keyboard has seen typed (the keyboard's saved memory, as scripts/gate reads it) and the lexicon
/// it types with, the first of `languages`.
/// A language other than English reads `<id>.lexicon` in the folder `$LANGUAGES` names, as scripts/eval sets it.
/// A line's own `memory`, `vocabulary` and `settings` (the four above) stand in for the arguments, so scripts/voiceloop
/// replays each dictation with what the iPhone had then.
/// Writes `{id, typed, language}` lines; scripts/voiceloop runs it here on Linux, on a package of KeyboardCore alone.
struct Clip: Decodable {
    let id, heard: String
    let field, content, before, memory, vocabulary: String?
    let settings, languages: [String]?
}
struct Row: Encodable { let id, typed, language: String }
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
var lexicons = [Language.english: Lexicon(bytes: Bytes([UInt8](FileManager.default.contents(atPath: arguments[1])!)))!]

@MainActor func lexicon(_ language: Language) -> Lexicon {
    if let kept = lexicons[language] { return kept }
    guard let folder = ProcessInfo.processInfo.environment["LANGUAGES"],
        let bytes = FileManager.default.contents(atPath: "\(folder)/\(language.id).lexicon"),
        let read = Lexicon(bytes: Bytes([UInt8](bytes)))
    else {
        fatalError(
            "no \(language.id).lexicon in $LANGUAGES (\(ProcessInfo.processInfo.environment["LANGUAGES"] ?? "unset"))")
    }
    lexicons[language] = read
    return read
}

func language(_ id: String) -> Language {
    guard let language = Language.all.first(where: { $0.id == id }) else { fatalError("no language \(id)") }
    return language
}

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

func corrector(_ path: String, _ lexicon: Lexicon) throws -> Corrector {
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
    var settings = settings(clip.settings ?? Array(arguments[4...7]))
    settings.languages = (clip.languages ?? ["en"]).map(language)
    let dictionary = clip.vocabulary ?? arguments[2]
    let memory = clip.memory ?? arguments[3]
    let typing = settings.languages[0]
    if vocabularies[dictionary] == nil { vocabularies[dictionary] = try vocabulary(dictionary) }
    if correctors["\(typing.id) \(memory)"] == nil {
        correctors["\(typing.id) \(memory)"] = try corrector(memory, lexicon(typing))
    }
    let vocabulary = vocabularies[dictionary]!
    let said = Language.of(clip.heard, among: settings.dictationLanguages.map { ($0, lexicon($0)) })
    var writing = settings.dictation(in: nil)
    writing.language = said
    var engine = TypingEngine(
        traits: InputTraits(
            kind: clip.field.flatMap(InputKind.init) ?? .text,
            content: clip.content.flatMap(InputContent.init) ?? .other))
    engine.settings = settings
    engine.corrector = correctors["\(typing.id) \(memory)"]
    let field = Field(clip.before ?? "")
    engine.handle(
        .dictated(
            vocabulary.corrected(writing.written(clip.heard), lexicon: lexicon(said)),
            plain: vocabulary.corrected(clip.heard, lexicon: lexicon(said)), language: said), in: field)
    let kept = zip(clip.before ?? "", field.before).prefix { $0 == $1 }.count
    lines.append(
        String(
            decoding: try JSONEncoder().encode(
                Row(id: clip.id, typed: String(field.before.dropFirst(kept)), language: said.id)),
            as: UTF8.self))
}
print(lines.joined(separator: "\n"))
