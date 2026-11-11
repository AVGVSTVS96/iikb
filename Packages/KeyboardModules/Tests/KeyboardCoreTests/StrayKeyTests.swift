import Testing

@testable import KeyboardCore

/// A key that's no part of a word, hit where a space belonged ("great@day"), on the screens whose fields put keys of
/// their own by the space bar: the space after the run reads the tap as the space when it fits where space taps land
/// better than the key it hit (`Corrector.spaced`).
struct StrayKeyTests {
    struct Screen: CustomTestStringConvertible, Sendable {
        var testDescription: String
        var size: Size
        var split = false
        var hand = OneHanded.off

        func grid(_ kind: InputKind = .twitter) -> KeyGrid {
            var settings = KeyboardSettings()
            settings.split = split
            settings.oneHanded = hand
            let context = LayoutContext(
                device: .phone, layer: .letters, kind: kind, showsGlobe: true, screen: size, settings: settings)
            return KeyboardGeometry(context, screen: size, style: .ios27).grid
        }
    }

    static let whole =
        [Screen(testDescription: "iPhone", size: Size(width: 402, height: 874))]
        + [Screen(testDescription: "iPhone, left hand", size: Size(width: 402, height: 874), hand: .left)]
        + Duo.Screen.allCases.map { Screen(testDescription: "Duo \($0.name)", size: $0.size) }
    static let split = Screen(testDescription: "Duo split", size: Duo.Screen.openLandscape.size, split: true)

    /// Someone typing on a screen's Instagram keys, each key tapped at its center, who has typed fifty known words.
    struct Typist {
        var engine = TypingEngine(traits: InputTraits(kind: .twitter, autocapitalization: .none))
        let corrector = Corrector(
            source: Lexicon(
                counts: [
                    ("great", 300), ("day", 400), ("the", 1000), ("thanks", 200), ("hey", 200), ("john", 100),
                    ("gmail", 50), ("com", 50), ("ok", 100),
                ].map { (word: $0.0, count: Double($0.1)) }))
        let grid: KeyGrid
        let document = TestDocument()

        init(_ screen: Screen) {
            grid = screen.grid()
            for _ in 0..<50 { corrector.record("the", after: nil) }
            engine.corrector = corrector
            engine.use(grid)
            engine.documentChanged(document)
        }

        mutating func type(_ text: String) {
            for character in text {
                guard let frame = grid.frame(of: String(character)) else {
                    engine.perform(.character(String(character)), in: document)
                    continue
                }
                let key = grid.key(atX: frame.midX, y: frame.midY)!
                engine.handle(.type(key, Tap(x: frame.midX, y: frame.midY, key: String(character))), in: document)
            }
        }
    }

    @Test(arguments: whole) func aKeyHitForTheSpaceBecomesTheSpace(on screen: Screen) {
        for key in ["@", "#"] {
            var typist = Typist(screen)
            typist.type("great\(key)day ")
            #expect(typist.document.text == "great day ", "\(key)")
        }
    }

    @Test func eachWordIsReadAsIfTheSpaceHadBeenTyped() {
        var typist = Typist(Self.whole[0])
        typist.type("grat@day#ok ")
        #expect(typist.document.text == "great day ok ")
    }

    @Test(arguments: whole + [split]) func theSpaceBarIsMeasuredAsItIsInEveryField(on screen: Screen) {
        let plain = screen.grid(.text)
        for kind in [InputKind.twitter, .email] {
            let grid = screen.grid(kind)
            for bar in grid.rows.last!.map(\.frame) where grid.key(atX: bar.midX, y: bar.midY)?.action == .space {
                let cell = grid.cell(of: bar)
                #expect(
                    plain.rows.last!.map { plain.cell(of: $0.frame) }.contains {
                        abs($0.x - cell.x) < 0.01 && abs($0.width - cell.width) < 0.01 && $0.y == cell.y
                    })
            }
        }
    }

    /// The split keyboard's @ sits between the hands, a key's width from where a thumb that knows its space bar lands.
    @Test func aKeyMeantOnTheSplitKeyboardStays() {
        var typist = Typist(Self.split)
        let bars = typist.grid.rows.last!.map(\.frame).filter {
            typist.grid.key(atX: $0.midX, y: $0.midY)?.action == .space
        }
        typist.corrector.learn(
            bars.flatMap { bar in
                (0..<20).map { TapSample(tap: Tap(x: bar.midX + Double($0 % 5), y: bar.midY, key: " "), intended: " ") }
            })
        typist.type("great@day ")
        #expect(typist.document.text == "great@day ")
    }

    @Test(arguments: whole) func onlyAKeyTouchingTheSpaceBarCanBeTheSpace(on screen: Screen) {
        let grid = screen.grid()
        let near = grid.rows.joined().compactMap { $0.key.text(shifted: false) }.filter { grid.touches($0, " ") }
        #expect(near == ["x", "c", "v", "b", "n", "m", "@", "#"])
    }

    @Test func anAddressAHandleAndAMentionStay() {
        for text in ["john@gmail.com ", "thanks@qzxv ", "hey @day ", "great@ day "] {
            var typist = Typist(Self.whole[0])
            typist.type(text)
            #expect(typist.document.text == text)
        }
    }

    @Test func theTapIsLearnedAsASpace() {
        var typist = Typist(Self.whole[0])
        typist.type("great@day ok ")
        #expect(typist.corrector.memory.touches.taps(for: " ", on: typist.grid) == 2)
        #expect(typist.corrector.memory.touches.taps(for: "@", on: typist.grid) == 0)
    }

    @Test func takenBackItStaysAsTyped() throws {
        var typist = Typist(Self.whole[0])
        typist.type("great@day ")
        typist.engine.perform(.delete, in: typist.document)
        let revert = try #require(typist.engine.suggestions.first { $0.kind == .revert })
        #expect(revert.text == "great@day")
        typist.engine.accept(revert, in: typist.document)
        typist.type("great@day ")
        #expect(typist.document.text == "great@day great@day ")
        #expect(typist.corrector.memory.touches.taps(for: "@", on: typist.grid) == 1)
    }

    @Test func deletingTheKeyGoesBackToTheWord() {
        var typist = Typist(Self.whole[0])
        typist.type("great@")
        typist.engine.perform(.delete, in: typist.document)
        #expect(typist.engine.typing.letters.count == 5 && typist.engine.typing.before.isEmpty)
        typist.type(" day@")
        typist.engine.perform(.delete, in: typist.document)
        typist.type("@ok ")
        #expect(typist.document.text == "great day ok ")
    }
}
