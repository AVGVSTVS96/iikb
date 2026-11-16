import Foundation
import Testing

@testable import KeyboardCore

/// scripts/formats: what a dictation types for what Parakeet writes (scripts/formats.txt), through the app's writing
/// and Dictionary and then the keyboard's reading, over the shipped lexicon.
struct FormatTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private static let fields: [String: InputTraits] = [
        "email": InputTraits(kind: .email), "url": InputTraits(kind: .url), "search": InputTraits(kind: .webSearch),
        "decimal": InputTraits(kind: .decimal),
    ]

    @Test func dictationTypesEachFormatAsWritten() throws {
        try check("formats.txt", label: "FORMAT", Self.said(DictationWriting()))
    }

    /// scripts/cleanup.txt with Clean, as Wispr Flow and Aqua Voice clean by default.
    @Test func dictationCleansAsWritten() throws {
        try check("cleanup.txt", label: "CLEANUP", Self.said(DictationWriting(editing: .clean)))
    }

    /// scripts/edits.txt: a language model's replies, written by hand, as Clean reads them (`DictationEdit`).
    @Test func dictationTypesARepliesEdit() throws {
        try check("edits.txt", label: "EDITS") { parts in
            var writing = DictationWriting(editing: .clean)
            for setting in parts.count == 4 ? parts[0].split(separator: " ").map(String.init) : [] {
                if let style = DictationStyle(rawValue: setting) { writing.style = style }
                if let lists = DictationLists(rawValue: setting) { writing.lists = lists }
            }
            return Case(field: nil, writing: writing, heard: parts[parts.count - 3], reply: parts[parts.count - 2])
        }
    }

    /// A line's dictation, before what it types: the field it goes in, how it's written, what Parakeet heard and a
    /// language model's reply to it.
    private struct Case {
        var field: String?
        var writing: DictationWriting
        var heard: String
        var reply: String?
    }

    /// `field | heard | typed` or `heard | typed`, written as `writing` writes.
    private static func said(_ writing: DictationWriting) -> ([String]) -> Case {
        { parts in Case(field: parts.count == 3 ? parts[0] : nil, writing: writing, heard: parts[parts.count - 2]) }
    }

    private func check(_ file: String, label: String, _ read: ([String]) -> Case) throws {
        let lexicon = Lexicon(
            bytes: Bytes(
                [UInt8](
                    FileManager.default.contents(
                        atPath: Self.root.appending(
                            path: "Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/en.lexicon"
                        ).path)!)))!
        let vocabulary = Vocabulary([Vocabulary.Term("kestrel.run"), Vocabulary.Term("tamsin", heardAs: ["tamsen"])])
        let corrector = Corrector(source: lexicon)
        corrector.changeMemory { memory in
            let typed = [
                ("Opus", "with", 6), ("Corvina", "to", 8), ("iikb", "on", 10), ("Niri", "on", 5), ("Autofork", "on", 5),
                ("Also", "", 3), ("also", "it", 20), ("Sure", "", 5), ("Thanks", "", 6), ("Nice", "", 5),
                ("Same", "", 5), ("quillon", "a", 2),
            ]
            for (word, previous, times) in typed {
                for _ in 0..<times { memory.record(word, after: previous) }
            }
        }
        let cases = try String(contentsOf: Self.root.appending(path: "scripts/\(file)"), encoding: .utf8)
            .split(separator: "\n").filter { !$0.hasPrefix("#") }
        var failed: [String] = []
        for line in cases {
            let parts = line.components(separatedBy: " | ")
            let test = read(parts.map { $0.replacingOccurrences(of: "\\n", with: "\n") })
            let wanted = parts[parts.count - 1].replacingOccurrences(of: "\\n", with: "\n")
            let written = test.field.flatMap { $0.hasPrefix("> ") ? String($0.dropFirst(2)) + " " : nil } ?? ""
            var engine = TypingEngine(
                traits: test.field.flatMap { Self.fields[$0] } ?? InputTraits(autocapitalization: .sentences))
            engine.settings.dictationStyle = test.writing.style
            engine.corrector = corrector
            let document = TestDocument(written)
            engine.handle(
                .dictated(
                    vocabulary.corrected(test.writing.written(test.heard, edited: test.reply), lexicon: lexicon),
                    plain: vocabulary.corrected(test.heard, lexicon: lexicon)), in: document)
            if document.text != wanted {
                failed.append("\(label) FAIL \"\(test.heard)\" typed \"\(document.text)\", wants \"\(wanted)\"")
            }
        }
        print((["\(label): \(cases.count - failed.count)/\(cases.count) pass"] + failed).joined(separator: "\n"))
        #expect(failed.count == 0)
    }
}
