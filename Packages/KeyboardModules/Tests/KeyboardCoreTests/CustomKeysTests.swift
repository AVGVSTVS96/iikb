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

    @Test func untouchedSettingsLayOutTheKeysAsBefore() {
        let settings = KeyboardSettings.initial
        for screen in Duo.Screen.allCases {
            #expect(keys(settings, on: screen).layout.shortRows == 0, "\(screen.name)")
        }
        #expect(bottom(keys(settings)) == [.globeSpacer, .layer(.numbers), .emoji, .space, .return])
        #expect(!settings.showsActions)
    }

    /// Your actions are the bar's buttons, never a row of keys: the keys stay as tall as without them on every screen.
    @Test func theActionsSitInTheBarAndTakeNoRow() {
        var settings = KeyboardSettings.initial
        settings.actionsInBar = true
        #expect(settings.showsActions)
        for screen in Duo.Screen.allCases {
            let (with, without) = (keys(settings, on: screen), keys(.initial, on: screen))
            #expect(with.height == without.height && with.grid.rows[0].first?.key.action == .character("q"))
        }
        settings.actionsInBar = false
        settings.predictiveText = false
        #expect(settings.showsActions, "with Predictive Text off, they take the suggestions' room")
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
                #expect(kept.count == min((emoji ? 1 : 0) + (period && layer == .letters ? 2 : 0), 2))
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
