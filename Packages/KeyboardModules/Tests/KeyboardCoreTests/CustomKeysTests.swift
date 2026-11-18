import Testing

@testable import KeyboardCore

/// Raycast's Custom Keys (docs/design.md, "Custom Keys"): what each setting does to the keys on the Duo's four
/// screens, and that iikb as it was is what you get until you turn one on.
struct CustomKeysTests {
    private func keys(
        _ settings: KeyboardSettings, on screen: Duo.Screen = .foldedPortrait, layer: KeyboardLayer = .letters,
        kind: InputKind = .text
    ) -> KeyboardGeometry {
        KeyboardGeometry(
            LayoutContext(
                device: .phone, layer: layer, kind: kind, showsGlobe: true, screen: screen.size, settings: settings),
            screen: screen.size, style: .ios27)
    }

    private func bottom(_ geometry: KeyboardGeometry) -> [KeyAction] {
        (geometry.grid.rows.last ?? []).map(\.key.action)
    }

    private var actionRow: KeyboardSettings {
        var settings = KeyboardSettings.initial
        settings.actionRow = true
        return settings
    }

    @Test func untouchedSettingsLayOutTheKeysAsBefore() {
        let settings = KeyboardSettings.initial
        for screen in Duo.Screen.allCases {
            let grid = keys(settings, on: screen).grid
            #expect(!grid.rows.joined().contains { $0.key.isTool }, "\(screen.name)")
            #expect(keys(settings, on: screen).layout.shortRows == 0)
        }
        #expect(bottom(keys(settings)) == [.globeSpacer, .layer(.numbers), .emoji, .space, .return])
        #expect(settings.actionPlace(phone: true, landscape: false) == .none)
    }

    @Test func theActionRowSitsAboveTheLettersUprightInTheActionsOrder() {
        var settings = actionRow
        settings.actions = [.clipboard, .gif, .emoji]
        for screen in [Duo.Screen.foldedPortrait, .openPortrait] {
            let without = keys(.initial, on: screen)
            let with = keys(settings, on: screen)
            let row = with.grid.rows[0]
            #expect(row.map(\.key.action) == [.tool(.clipboard), .tool(.gif), .tool(.emoji)], "\(screen.name)")
            #expect(row.allSatisfy { $0.frame.height == with.metrics.numberRowHeight })
            #expect(with.height == without.height + with.metrics.numberRowHeight + with.metrics.rowGap)
            let (q, p) = (with.grid.frame(of: "q")!, with.grid.frame(of: "p")!)
            let pitch = with.grid.frame(of: "w")!.x - q.x
            #expect(
                row.allSatisfy { abs($0.frame.width - (1.6 * pitch - with.metrics.keyGap)) < 0.5 }, "Raycast's pills")
            #expect(
                abs(row[1].frame.x + row[1].frame.width / 2 - (q.x + p.x + p.width) / 2) < 1,
                "centered over the letters")
            #expect(with.grid.typingRow.first?.key.action == .character("q"))
            #expect(with.grid.barRow.map(\.frame) == with.grid.typingRow.map(\.frame), "the bar skips the action row")
        }
    }

    @Test func inLandscapeTheActionsGoToTheBarUnlessKeptInTheirRow() {
        var settings = actionRow
        for screen in [Duo.Screen.foldedLandscape, .openLandscape] {
            #expect(keys(settings, on: screen).layout.shortRows == 0, "\(screen.name)")
        }
        #expect(settings.actionPlace(phone: true, landscape: true) == .bar)
        settings.actionRowInLandscape = true
        for screen in [Duo.Screen.foldedLandscape, .openLandscape] {
            #expect(keys(settings, on: screen).grid.rows[0].allSatisfy { $0.key.isTool }, "\(screen.name)")
        }
        #expect(settings.actionPlace(phone: false, landscape: false) == .none, "an iPad has no action row")
        settings.predictiveText = false
        #expect(
            settings.actionPlace(phone: false, landscape: false) == .bar, "its bar has them with Predictive Text off")
    }

    @Test func theActionRowStaysOnEveryLayerAboveTheNumberRow() {
        var settings = actionRow
        settings.numberRow = true
        let letters = keys(settings)
        #expect(letters.layout.shortRows == 2 && letters.grid.rows[0].allSatisfy { $0.key.isTool })
        #expect(letters.grid.rows[1].first?.key.action == .character("1"))
        #expect(keys(settings, layer: .numbers).grid.rows[0].allSatisfy { $0.key.isTool })
    }

    @Test func theSplitKeysHaveHalfTheActionsOnEachSide() {
        var settings = actionRow
        settings.actionRowInLandscape = true
        settings.split = true
        settings.actions = [.emoji, .gif, .transcripts, .clipboard]
        let split = keys(settings, on: .openLandscape).grid
        let row = split.rows[0]
        #expect(row.count == 4)
        func middle(_ a: Rect, _ b: Rect) -> Double { (a.x + b.x + b.width) / 2 }
        let frame = { split.frame(of: $0)! }
        #expect(abs(middle(row[0].frame, row[1].frame) - middle(frame("q"), frame("t"))) < 1, "over q to t")
        #expect(abs(middle(row[2].frame, row[3].frame) - middle(frame("y"), frame("p"))) < 1, "over y to p")
    }

    @Test func aReachForTheTopLettersNeverOpensATool() {
        let grid = keys(actionRow).grid
        let q = grid.frame(of: "q")!
        let tool = grid.rows[0][0].frame
        #expect(grid.key(atX: q.x + 4, y: tool.y + tool.height + 1)?.action == .character("q"))
        #expect(grid.key(atX: q.x + 4, y: tool.y + tool.height - 1) == nil, "the margin beside the pills is empty")
        let (first, second) = (grid.rows[0][0].frame, grid.rows[0][1].frame)
        let between = (first.x + first.width + second.x) / 2
        #expect(grid.key(atX: between, y: tool.y + 1)?.isTool == true, "the gap between two pills takes a tap")
        #expect(grid.key(atX: first.x + 2, y: tool.y + tool.height - 1)?.isTool == true)
    }

    @Test func theKeysAroundSpaceGoWhereTheyWereArranged() {
        var settings = KeyboardSettings.initial
        settings.periodKey = true
        #expect(
            bottom(keys(settings)) == [.globeSpacer, .layer(.numbers), .emoji, .space, .character("."), .return])
        settings.aroundSpace = [.space, .period, .emoji]
        #expect(
            bottom(keys(settings)) == [.globeSpacer, .layer(.numbers), .space, .character("."), .emoji, .return])
        for screen in Duo.Screen.allCases {
            let row = keys(settings, on: screen).grid.rows.last!
            let space = row.first { $0.key.action == .space }!.frame
            #expect(space.width > row.first { $0.key.action == .return }!.frame.width, "\(screen.name)")
        }
    }

    @Test func everySplitSpaceBarStaysTwoKeysWideInEveryArrangement() {
        let orders: [[BottomKey]] = [
            [.emoji, .period, .space], [.emoji, .space, .period], [.period, .space, .emoji], [.space, .emoji, .period],
            [.space, .period, .emoji], [.period, .emoji, .space],
        ]
        for order in orders.flatMap({ [$0, [.snippet] + $0] }) {
            for (emoji, period, mic, layer, globe) in [true, false].flatMap({ a in
                [true, false].flatMap { b in
                    [true, false].flatMap { c in
                        [KeyboardLayer.letters, .numbers].flatMap { d in GlobeKey.allCases.map { (a, b, c, d, $0) } }
                    }
                }
            }) {
                var settings = KeyboardSettings.initial
                settings.split = true
                settings.aroundSpace = order
                settings.emojiKey = emoji
                settings.periodKey = period
                settings.snippetKey = period
                settings.micKey = mic
                settings.globeKey = globe
                let geometry = keys(settings, on: .openLandscape, layer: layer)
                let row = geometry.grid.rows.last!
                let pitch =
                    geometry.grid.frame(of: layer == .letters ? "w" : "2")!.x
                    - geometry.grid.frame(of: layer == .letters ? "q" : "1")!.x
                let spaces = row.filter { $0.key.action == .space }
                #expect(spaces.count == 2)
                for space in spaces {
                    #expect(
                        space.frame.width >= 2 * pitch - geometry.metrics.keyGap - 0.5,
                        "\(order) emoji \(emoji) period \(period) mic \(mic) \(layer) globe \(globe)")
                }
                let besideSpace: Set<KeyAction> = [.emoji, .character("."), .snippetPrefix("!")]
                let kept = row.map(\.key.action).filter(besideSpace.contains)
                let room = mic || globe != .hidden ? 2 : 3
                #expect(kept.count == min((emoji ? 1 : 0) + (period && layer == .letters ? 2 : 0), room))
                #expect(kept.contains(.emoji) == emoji, "the emoji key is the last left out")
            }
        }
    }

    @Test func thePeriodKeyIsAKeyOfItsOwnNotPartOfTheSpaceBar() {
        var settings = KeyboardSettings.initial
        settings.periodKey = true
        let grid = keys(settings).grid
        let row = grid.rows.last!
        let space = grid.cell(of: row.first { $0.key.action == .space }!.frame)
        let period = row.first { $0.key.action == .character(".") }!.frame
        #expect(space.x + space.width <= period.x)
    }

    @Test func thePeriodKeyHoldsPunctuationAndOnlyWhereTheFieldHasNoPeriod() {
        var settings = KeyboardSettings.initial
        settings.periodKey = true
        let period = keys(settings).grid.rows.last!.first { $0.key.action == .character(".") }!.key
        #expect(period.alternates.contains("&") && period.alternates.contains("%") && period.alternates.first == ".")
        for kind in [InputKind.email, .url, .webSearch] {
            #expect(bottom(keys(settings, kind: kind)).count { $0 == .character(".") } == 1, "\(kind)")
        }
        #expect(!bottom(keys(settings, kind: .twitter)).contains(.character(".")), "Instagram's @ and # have its room")
        #expect(!bottom(keys(settings, layer: .numbers)).contains(.character(".")))
    }

    @Test func theSplitBottomRowKeepsItsHalvesWithKeysAfterSpace() {
        var settings = KeyboardSettings.initial
        settings.split = true
        settings.periodKey = true
        let row = keys(settings, on: .openLandscape).grid.rows.last!
        #expect(row.map(\.key.action).suffix(3) == [.space, .character("."), .return])
        let spaces = row.filter { $0.key.action == .space }.map(\.frame)
        #expect(spaces.count == 2 && spaces[0].x + spaces[0].width < spaces[1].x)
    }

    @Test func theSnippetKeyIsAKeyOfItsOwnOnTheLetters() {
        var settings = KeyboardSettings.initial
        settings.snippetKey = true
        settings.snippetPrefix = ";"
        #expect(
            bottom(keys(settings)) == [.globeSpacer, .layer(.numbers), .emoji, .space, .snippetPrefix(";"), .return])
        #expect(bottom(keys(settings, kind: .email)).contains(.snippetPrefix(";")), "a keyword goes in any field")
        #expect(!bottom(keys(settings, layer: .numbers)).contains(.snippetPrefix(";")))
        let grid = keys(settings).grid
        let row = grid.rows.last!
        let space = grid.cell(of: row.first { $0.key.action == .space }!.frame)
        #expect(space.x + space.width <= row.first { $0.key.action == .snippetPrefix(";") }!.frame.x)
        settings.snippetPrefix = ""
        #expect(bottom(keys(settings)) == [.globeSpacer, .layer(.numbers), .emoji, .space, .return])
    }

    @Test func withoutTheDictationButtonThereIsNoRecordKey() {
        var settings = KeyboardSettings.initial
        settings.micKey = true
        #expect(bottom(keys(settings)).first == .dictate)
        settings.dictationButton = false
        #expect(!bottom(keys(settings)).contains(.dictate))
    }

    @Test func anArrangementKeepsEachKeyOnceWithSpace() {
        #expect(BottomKey.arranged([]) == BottomKey.standard)
        #expect(BottomKey.arranged([.period, .period, .space]) == [.emoji, .period, .snippet, .space])
        #expect(
            BottomKey.arranged([.space, .emoji, .period]) == [.space, .emoji, .period, .snippet],
            "an order kept before the snippet key gets it after the period")
    }
}
