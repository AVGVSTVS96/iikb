import Foundation
import KeyboardCore
import KeyboardEnglish
import Testing

/// The iPhone owner's own messages, typed by the keyboard as his iPhone had it when each window began: his typing
/// memory and personal network from then, the folded Duo's letters, and taps drawn from where his land on each key.
/// `scripts/owner.py` writes them from the backup into `OWNER_DATA`, which stays on the server, so each line prints
/// counts alone. Of the correct words autocorrect changed, it counts those that only gained an apostrophe ("im" → "i'm"),
/// those the lexicon has or he'd typed three times before, and new ones, which may be his own typos left as sent. dev's
/// changed words go to `dev/misses.txt` beside it; test's are never written, so no fix reads them. `OWNER_SPLIT` picks
/// one, so scripts/eval runs each in its own process.
@MainActor
extension Evaluation {
    private struct Saved: Decodable { var memory: TypingMemory }

    @Test(arguments: ["dev", "test"]) func owner(_ split: String) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let folder = environment["OWNER_DATA"], environment["OWNER_SPLIT"] ?? split == split else { return }
        let url = URL(fileURLWithPath: folder).appending(path: split)
        let screen = Duo.Screen.foldedPortrait.size
        let grid = KeyboardGeometry(
            LayoutContext(device: .phone, layer: .letters, screen: screen, settings: KeyboardSettings()),
            screen: screen, style: .ios27
        ).grid
        try #require(grid.signature == "phone-portrait-letters")
        let q = grid.frame(of: "q")!
        let pitch = (x: grid.frame(of: "w")!.midX - q.midX, y: grid.frame(of: "a")!.midY - q.midY)
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let memory = try decoder.decode(Saved.self, from: Data(contentsOf: url.appending(path: "memory.json"))).memory
        let network = try #require(
            Network(bytes: [UInt8](Data(contentsOf: url.appending(path: "en.network"))), personal: true))
        var taps: [String: [(Double, Double)]] = [:]
        for line in try String(contentsOf: url.appending(path: "taps.txt"), encoding: .utf8).split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            taps[String(parts[0])] = parts[1].split(separator: " ").map {
                let xy = $0.split(separator: ",").map { Double($0)! }
                return (xy[0], xy[1])
            }
        }
        var random = SplitMix64(seed: 2026)
        func tap(_ character: Character) -> (Double, Double) {
            let key = grid.key(holding: String(character))!
            let frame = grid.frame(of: key)!
            let drawn = taps[key].map { $0[Int(random.next() % UInt64($0.count))] } ?? (0, 0)
            return (frame.midX + drawn.0 * pitch.x, frame.midY + drawn.1 * pitch.y)
        }
        var session = Session(.learning, grid: grid)
        let corrector = Corrector(source: Lexicon.english, network: network)
        corrector.grid = grid
        corrector.changeMemory { $0 = memory }
        session.engine.corrector = corrector
        var sentences = 0
        for line in try String(contentsOf: url.appending(path: "text.txt"), encoding: .utf8).split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            corrector.app = parts[0].isEmpty ? nil : String(parts[0])
            session.startPhrase()
            for word in parts[1].split(separator: " ").map(String.init) {
                session.type(word, taps: word.filter { grid.key(holding: String($0)) != nil }.map(tap), space: nil)
            }
            sentences += 1
        }
        let score = session.score
        let changed = score.brokenWords.map {
            $0.split(separator: "→", omittingEmptySubsequences: false).map(String.init)
        }
        let apostrophe = changed.filter { $0[1].replacingOccurrences(of: "'", with: "") == $0[0] }.count
        let known = changed.filter {
            $0[1].replacingOccurrences(of: "'", with: "") != $0[0]
                && (Lexicon.english.logProbability(of: $0[0]) != nil || memory.counts[$0[0], default: 0] >= 3)
        }.count
        let share = { (count: Int) in String(format: "%.1f%%", 100.0 * Double(count) / Double(max(score.words, 1))) }
        print(
            "EVAL owner split=\(split) sentences=\(sentences) words=\(score.words) raw=\(share(score.raw)) autocorrect=\(share(score.corrected)) top3=\(share(score.topThree)) fixed=\(score.fixed) broken=\(score.broken): apostrophe=\(apostrophe) known=\(known) new=\(score.broken - apostrophe - known)"
        )
        if split == "dev" {
            try score.brokenWords.joined(separator: "\n").write(
                to: url.appending(path: "misses.txt"), atomically: true, encoding: .utf8)
        }
    }
}
