import Foundation

@testable import KeyboardCore

enum SessionReplay {
    struct Differs: Error, CustomStringConvertible {
        var step: Int
        var description: String
    }

    static let lexicon = Lexicon(bytes: resource("en.lexicon"))!
    static let network = Network(bytes: resource("en.network"))!
    static let catalog = EmojiCatalog(text: text("emoji.txt"), search: EmojiSearch(text: text("emoji-search.txt")))

    private static func text(_ name: String) -> String {
        String(decoding: resource(name), as: UTF8.self)
    }

    static func read(_ data: Data) throws -> SessionLog {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let defaults =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(KeyboardSettings())) as! [String: Any]
        var log = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        log["steps"] = (log["steps"] as? [[String: Any]])?.map { step in
            guard var setup = step["setup"] as? [String: Any], let settings = setup["settings"] as? [String: Any]
            else { return step }
            setup["settings"] = defaults.merging(settings) { _, logged in logged }
            return step.merging(["setup": setup]) { _, filled in filled }
        }
        return try decoder.decode(SessionLog.self, from: JSONSerialization.data(withJSONObject: log))
    }

    static func write(_ log: SessionLog, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        return try encoder.encode(log)
    }

    final class Field: TextDocument {
        var reads: [SessionLog.Window] = []
        var shown = SessionLog.Window(before: nil, selected: nil, after: nil)

        var textBeforeInput: String? {
            if !reads.isEmpty { shown = reads.removeFirst() }
            return shown.before
        }
        var textAfterInput: String? { shown.after }
        var selectedText: String? { shown.selected }
        func insert(_ text: String) {}
        func deleteBackward(_ count: Int) {}
        func moveCursor(by offset: Int) {}
    }

    struct Player {
        var engine = TypingEngine()
        let field = Field()
        let personal: Network?

        init(personal: Network? = nil, build: String = "") {
            self.personal = personal
            engine.log = SessionLog(build: build)
        }

        mutating func prepare(_ step: SessionLog.Step) throws {
            if let setup = step.setup { use(setup) }
            if let words = step.words { engine.corrector = try corrector(words) }
            if step.setup != nil || step.words != nil { engine.suggestionsChanged() }
        }

        mutating func play(_ step: SessionLog.Step) throws {
            try prepare(step)
            field.reads = step.reads ?? []
            switch step.input {
            case .event(let event): engine.handle(event, in: field)
            case .action(let action, let tap): engine.perform(action, in: field, tap: tap)
            case .deleteWord: engine.deleteWord(in: field)
            case .pick(let suggestion): engine.accept(suggestion, in: field)
            case .pickEmoji(let emoji): engine.accept(emoji: emoji, in: field)
            case .host: engine.documentChanged(field)
            case .grid(let grid): engine.use(grid)
            case .traits(let traits): engine.update(traits)
            case .app(let app): engine.changeApp(app)
            case .endSession: engine.endSession()
            case .finishWord: engine.finishWord(in: field)
            case .leaveField: engine.leaveField()
            case .ranked:
                engine.suggestionsChanged()
                if var job = engine.suggestionJob() {
                    job.run()
                    engine.finish(job)
                }
            }
        }

        private mutating func use(_ setup: SessionLog.Setup) {
            engine.settings = setup.settings
            engine.region = setup.region
            engine.snippets = setup.snippets
            var emoji = setup.emoji
            emoji.app = setup.emojiApp
            emoji.skinTone = setup.skinTone
            engine.emojiHistory = emoji
            engine.emojiCatalog = setup.catalog ? SessionReplay.catalog : nil
            engine.swipeModel = setup.swipe.map { $0 ? swipe : swipe.withoutDecoder }
            engine.defersSuggestions = setup.defers
        }

        private func corrector(_ words: SessionLog.Words) throws -> Corrector {
            let lexicon = SessionReplay.lexicon
            if let typed = words.lexicon, typed.size != lexicon.bytes.count {
                throw Differs(
                    step: 0,
                    description:
                        "typed on a lexicon of \(typed.size) bytes, not English's \(lexicon.bytes.count): only English replays"
                )
            }
            let network = words.network.map { $0.personal ? personal : SessionReplay.network } ?? nil
            if let typed = words.network, typed.size != network?.bytes.count {
                throw Differs(
                    step: 0,
                    description: typed.personal
                        ? "typed with the personal network: set REPLAY_NETWORK to its file"
                        : "typed with a network of \(typed.size) bytes, not this checkout's \(network?.bytes.count ?? 0)"
                )
            }
            let corrector = Corrector(source: lexicon, network: network)
            corrector.changeMemory { $0 = words.memory }
            corrector.names = words.names
            corrector.replacements = words.replacements
            corrector.app = words.app
            corrector.grid = words.grid
            return corrector
        }
    }

    @discardableResult
    static func replay(_ log: SessionLog, personal: Network? = nil) throws -> SessionLog {
        var player = Player(personal: personal)
        for (index, step) in log.steps.enumerated() {
            do { try player.play(step) } catch var differs as Differs {
                differs.step = index
                throw differs
            }
            let played = player.engine.log!.steps[index]
            let problems = [
                (played.edits ?? []) == (step.edits ?? [])
                    ? nil : "wrote \(describe(played.edits)), the log says \(describe(step.edits))",
                played.reads?.count == step.reads?.count
                    ? nil : "read the field \(played.reads?.count ?? 0) times, the log says \(step.reads?.count ?? 0)",
                played.bar == step.bar ? nil : "offered \(describe(played.bar)), the log says \(describe(step.bar))",
            ].compactMap { $0 }
            guard problems.isEmpty else {
                throw Differs(step: index, description: report(index, of: log, played: player.engine, problems))
            }
        }
        return player.engine.log!
    }

    static func regression(_ log: SessionLog, from start: Int, to end: Int) throws -> SessionLog {
        var before = Player()
        for step in log.steps[..<start] { try before.play(step) }
        try before.prepare(log.steps[start])
        let engine = before.engine
        var player = Player(build: log.build)
        let opening = SessionLog.Step(
            .host, setup: engine.setup, words: engine.words.map(unlearned),
            reads: [
                SessionLog.Window(
                    before: engine.text.before, selected: engine.text.selected, after: engine.text.after)
            ])
        try player.play(opening)
        for index in start...min(end, log.steps.count - 1) {
            var step = log.steps[index]
            step.setup = index == start ? nil : step.setup
            step.words = index == start ? nil : step.words.map(unlearned)
            try player.play(step)
        }
        return player.engine.log!
    }

    private static func unlearned(_ words: SessionLog.Words) -> SessionLog.Words {
        var words = words
        words.memory = TypingMemory()
        words.names = [:]
        words.replacements = [:]
        return words
    }

    private static func report(_ index: Int, of log: SessionLog, played engine: TypingEngine, _ problems: [String])
        -> String
    {
        var lines = ["differs at step \(index) of \(log.steps.count): \(describe(log.steps[index].input))"]
        lines += problems.map { "  \($0)" }
        lines.append("  the field now: \(field(engine.text.before, engine.text.selected, engine.text.after))")
        lines.append("  the steps before it:")
        for earlier in max(index - 8, 0)..<index {
            let step = log.steps[earlier]
            var line = "    \(earlier) \(describe(step.input))"
            if let edits = step.edits { line += " wrote \(describe(edits))" }
            if let read = step.reads?.last { line += " saw \(field(read.before, read.selected, read.after))" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func field(_ before: String?, _ selected: String?, _ after: String?) -> String {
        let selected = (selected ?? "").isEmpty ? "|" : "[\(selected!)]"
        return "\"\(String((before ?? "?").suffix(40)))\(selected)\(String((after ?? "?").prefix(20)))\""
    }

    static func describe(_ input: SessionLog.Input) -> String {
        switch input {
        case .event(.type(let key, let tap)) where key.action == .space:
            "space at (\(points(tap.x)), \(points(tap.y)))"
        case .event(.type(_, let tap)): "tap \"\(tap.key)\" at (\(points(tap.x)), \(points(tap.y)))"
        case .event(let event): "\(event)"
        case .action(let action, nil): "\(action)"
        case .action(let action, let tap?): "\(action) at (\(points(tap.x)), \(points(tap.y)))"
        case .pick(let suggestion): "pick \"\(suggestion.text)\" (\(suggestion.kind))"
        case .pickEmoji(let emoji): "pick \(emoji)"
        case .host: "the host's report"
        case .grid(let grid): "keys \(grid.signature), \(points(grid.width)) wide"
        case .traits(let traits): "field \(traits.kind) \(traits.content)"
        case .app(let app): "app \(app ?? "unknown")"
        default: "\(input)"
        }
    }

    static func describe(_ edits: [SessionLog.Edit]?) -> String {
        guard let edits, !edits.isEmpty else { return "nothing" }
        return edits.map {
            switch $0 {
            case .delete(let count): "delete \(count)"
            case .insert(let text): "insert \"\(text)\""
            case .move(let offset): "move \(offset)"
            }
        }.joined(separator: ", ")
    }

    static func describe(_ bar: SessionLog.Bar?) -> String {
        guard let bar else { return "the bar as it was" }
        return "[" + (bar.words.map { "\"\($0.text)\"" } + bar.emoji).joined(separator: " ") + "]"
    }

    private static func points(_ value: Double) -> String {
        String((value * 10).rounded() / 10)
    }
}
