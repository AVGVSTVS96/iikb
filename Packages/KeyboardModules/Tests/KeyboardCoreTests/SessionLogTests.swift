import Foundation
import Testing

@testable import KeyboardCore

struct SessionLogTests {
    static let sessions = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Sessions")
    private static let environment = ProcessInfo.processInfo.environment

    struct Typist {
        var engine = TypingEngine()
        let host = ClippedDocument(window: 40)
        let grid = phoneGrid(.english, .qwerty)
        private var aim = 0

        init() {
            engine.log = SessionLog(build: "made up")
            engine.corrector = Corrector(source: SessionReplay.lexicon, network: SessionReplay.network)
            engine.emojiCatalog = SessionReplay.catalog
            engine.swipeModel = swipe
            engine.defersSuggestions = true
            engine.changeApp("com.example.chat")
            engine.update(InputTraits(returnKind: .send))
            report()
            engine.use(grid)
        }

        mutating func report() {
            engine.documentChanged(host)
            if var job = engine.suggestionJob() {
                job.run()
                engine.finish(job)
            }
        }

        mutating func type(_ text: String) {
            for character in text {
                let label = character == " " ? "space" : String(character)
                let key = grid.rows.joined().first {
                    character == " " ? $0.key.action == .space : $0.key.action == .character(label)
                }!
                let offsets = [(-3.0, 2.0), (2.5, -4.0), (4.0, 3.0), (-1.5, -2.5), (0.5, 5.0)]
                let (dx, dy) = offsets[aim % offsets.count]
                aim += 1
                let tap = Tap(x: key.frame.midX + dx, y: key.frame.midY + dy, key: character == " " ? " " : label)
                engine.handle(.type(key.key, tap), in: host)
                report()
            }
        }

        mutating func delete(_ count: Int = 1) {
            for _ in 0..<count {
                engine.handle(.down(Key(.delete), tapCount: 1), in: host)
                engine.handle(.up(Key(.delete)), in: host)
                report()
            }
        }

        mutating func pick(_ text: String) {
            engine.accept(engine.suggestions.first { $0.text == text }!, in: host)
            report()
        }
    }

    static func session() -> (log: SessionLog, typed: String) {
        var typist = Typist()
        typist.type("helo thsre ")
        typist.type("how was yuor dsy")
        typist.pick(typist.engine.suggestions.first { $0.kind != .literal }!.text)
        typist.type("  i")
        typist.delete(2)
        typist.type("good ")
        typist.host.cursor = 0
        typist.report()
        typist.type("so ")
        typist.engine.endSession()
        return (typist.engine.log!, typist.host.text)
    }

    @Test func aRecordedSessionReplaysAsItWasTyped() throws {
        let (log, typed) = Self.session()
        #expect(typed.hasPrefix("So "))
        #expect(log.steps.contains { if case .ranked = $0.input { true } else { false } })
        #expect(log.steps.contains { $0.bar != nil })
        #expect(log.steps.contains { $0.words != nil })
        #expect(!log.steps.contains { if case .action = $0.input { true } else { false } })
        let read = try SessionReplay.read(SessionReplay.write(log))
        let played = try SessionReplay.replay(read)
        #expect(played.steps.count == log.steps.count)
        #expect(played.steps.map(\.edits) == log.steps.map(\.edits))
    }

    @Test func aDoctoredLogFailsAtTheStepItChanged() throws {
        var log = Self.session().log
        let doctored = try #require(
            log.steps.indices.first { index in
                log.steps[index].edits?.contains { if case .insert("o") = $0 { true } else { false } } == true
            })
        log.steps[doctored].edits = [.insert("0")]
        #expect {
            try SessionReplay.replay(log)
        } throws: { error in
            let differs = error as? SessionReplay.Differs
            return differs?.step == doctored
                && differs?.description.contains("wrote insert \"o\", the log says insert \"0\"") == true
                && differs?.description.contains("the steps before it:") == true
        }
    }

    @Test func aCutOfASessionReplaysOnItsOwn() throws {
        let log = Self.session().log
        let start = try #require(
            log.steps.indices.first { log.steps[$0].reads?.last?.before?.hasSuffix("there ") == true })
        let cut = try SessionReplay.regression(log, from: start, to: start + 40)
        #expect(cut.steps.first?.words?.memory == TypingMemory())
        try SessionReplay.replay(SessionReplay.read(SessionReplay.write(cut)))
    }

    @Test func everyCaseReplays() throws {
        let cases = try FileManager.default.contentsOfDirectory(at: Self.sessions, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(!cases.isEmpty)
        for file in cases {
            do {
                try SessionReplay.replay(SessionReplay.read(Data(contentsOf: file)))
            } catch let differs as SessionReplay.Differs {
                Issue.record("\(file.lastPathComponent) \(differs)")
            }
        }
    }

    @Test(.enabled(if: environment["REPLAY"] != nil)) func replaysAnExportedSession() throws {
        let log = try SessionReplay.read(Data(contentsOf: URL(fileURLWithPath: Self.environment["REPLAY"]!)))
        let personal = Self.environment["REPLAY_NETWORK"].map {
            Network(bytes: [UInt8](FileManager.default.contents(atPath: $0)!), personal: true)!
        }
        if let name = Self.environment["REPLAY_CASE"] {
            let start = Int(Self.environment["REPLAY_FROM"] ?? "") ?? 0
            let end = Int(Self.environment["REPLAY_TO"] ?? "") ?? log.steps.count - 1
            let cut = try SessionReplay.regression(log, from: start, to: end)
            let file = Self.sessions.appending(path: "\(name).json")
            try SessionReplay.write(cut, pretty: true).write(to: file)
            return print(
                "REPLAY wrote steps \(start) to \(min(end, log.steps.count - 1)) as \(file.resolvingSymlinksInPath().path)"
            )
        }
        print("REPLAY build \(log.build), \(log.steps.count) steps\(log.isFull ? ", the most a log keeps" : "")")
        do {
            try SessionReplay.replay(log, personal: personal)
            print("REPLAY matches all \(log.steps.count) steps")
        } catch let differs as SessionReplay.Differs {
            print(differs.description.split(separator: "\n").map { "REPLAY \($0)" }.joined(separator: "\n"))
            Issue.record("the replay differs at step \(differs.step)")
        }
    }
}
