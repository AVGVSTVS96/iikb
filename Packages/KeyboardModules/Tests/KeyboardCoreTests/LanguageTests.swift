import Testing

@testable import KeyboardCore

struct LanguageTests {
    /// With nothing picked, iikb types English on QWERTY, and its touch models keep the names they had before languages.
    @Test func theDefaultsAreEnglishOnQwerty() {
        let settings = KeyboardSettings()
        #expect(settings.language == "en" && settings.layout == nil && settings.letters == .qwerty)
        let context = LayoutContext(
            device: .phone, layer: .letters, screen: Size(width: 466, height: 678), settings: settings)
        #expect(context.language == .english && context.letters == .qwerty)
        #expect(context.signature == "phone-portrait-letters")
    }

    /// A language's own layout comes first, and a layout it doesn't offer falls back to it.
    @Test func aLanguageOffersApplesLayoutsItsOwnFirst() {
        var settings = KeyboardSettings()
        settings.language = "de"
        #expect(settings.letters == .german)
        settings.layout = "qwerty"
        #expect(settings.letters == .qwerty)
        settings.language = "sv"
        #expect(settings.letters == .swedish)
        settings.language = "xx"
        #expect(Language.named(settings.language) == .english)
        #expect(
            Language.all.map(\.name) == [
                "English", "Español", "Français", "Deutsch", "Português", "Italiano", "Svenska",
            ])
    }

    /// Taps learned on one layout's letters stay with it: a QWERTZ z never takes a QWERTY z's aim.
    @Test func eachLayoutsLettersLearnApart() {
        var settings = KeyboardSettings()
        settings.language = "de"
        let context = { (layer: KeyboardLayer) in
            LayoutContext(device: .phone, layer: layer, screen: Size(width: 402, height: 874), settings: settings)
        }
        #expect(context(.letters).signature == "phone-portrait-letters-german")
        #expect(context(.numbers).signature == "phone-portrait-numbers")
        let kept = LayoutContext(signature: context(.letters).signature)
        #expect(kept?.letters == .german && kept?.language == .german)
        #expect(LayoutContext(signature: "phone-portrait-letters")?.letters == .qwerty)
    }

    private func letters(_ layout: KeyboardLayout) -> [String] {
        layout.rows.dropLast().map { row in
            row.compactMap { item -> String? in
                guard case .key(let key) = item, case .character(let value) = key.action else { return nil }
                return value
            }.joined()
        }
    }

    private func context(_ language: String, _ layout: String? = nil, screen: Size = Size(width: 402, height: 874))
        -> LayoutContext
    {
        var settings = KeyboardSettings()
        settings.language = language
        settings.layout = layout
        return LayoutContext(device: .phone, layer: .letters, screen: screen, settings: settings)
    }

    /// Each language's own letters on an iPhone, as Apple's keyboard sets them out.
    @Test func eachLanguagesLettersAreApples() {
        #expect(letters(Layouts.layout(for: context("es"))) == ["qwertyuiop", "asdfghjklñ", "zxcvbnm"])
        #expect(letters(Layouts.layout(for: context("de"))) == ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"])
        #expect(letters(Layouts.layout(for: context("fr"))) == ["azertyuiop", "qsdfghjklm", "wxcvbn'"])
        #expect(letters(Layouts.layout(for: context("sv"))) == ["qwertyuiopå", "asdfghjklöä", "zxcvbnm"])
        #expect(letters(Layouts.layout(for: context("it"))) == letters(Layouts.layout(for: context("en"))))
    }

    /// Swedish's eleven keys a row narrow every letter to fit, while shift, delete and the bottom row keep their width.
    @Test func elevenKeysNarrowTheLettersAndNothingElse() {
        let grid = { (language: String) in
            KeyboardGeometry(context(language), screen: Size(width: 402, height: 874), style: .ios27).grid
        }
        let english = grid("en")
        let swedish = grid("sv")
        let q = (english.frame(of: "q")!, swedish.frame(of: "q")!)
        #expect(abs(q.1.width + 6 - (q.0.width + 6) * 10 / 11) < 0.01)
        #expect(
            abs(
                swedish.frame(of: "å")!.x + swedish.frame(of: "å")!.width
                    - (english.frame(of: "p")!.x + english.frame(of: "p")!.width)) < 0.01)
        let bottom = { (grid: KeyGrid) in grid.rows.last!.map(\.frame) }
        #expect(bottom(english) == bottom(swedish))
        let shift = { (grid: KeyGrid) in grid.rows[2].first!.frame }
        #expect(abs(shift(english).width - shift(swedish).width) < 0.01)
    }

    /// The open Duo's split halves each row, the key between the hands on both halves where a row is odd.
    @Test func theSplitHalvesEachLanguagesRows() {
        var settings = KeyboardSettings()
        settings.split = true
        settings.language = "sv"
        let open = LayoutContext(
            device: .phone, layer: .letters, screen: Duo.Screen.openLandscape.size, settings: settings)
        #expect(open.isSplit)
        #expect(letters(Layouts.layout(for: open)) == ["qwertyyuiopå", "asdfghhjklöä", "zxcvvbnm"])
        settings.language = "es"
        let spanish = LayoutContext(
            device: .phone, layer: .letters, screen: Duo.Screen.openLandscape.size, settings: settings)
        #expect(letters(Layouts.layout(for: spanish)) == ["qwertyuiop", "asdfghjklñ", "zxcvvbnm"])
        settings.language = "en"
        let english = LayoutContext(
            device: .phone, layer: .letters, screen: Duo.Screen.openLandscape.size, settings: settings)
        #expect(letters(Layouts.layout(for: english)) == ["qwertyuiop", "asdfgghjkl", "zxcvvbnm"])
    }

    private func alternates(_ character: String, _ language: String, layer: KeyboardLayer = .letters) -> [String] {
        var settings = KeyboardSettings()
        settings.language = language
        let context = LayoutContext(
            device: .phone, layer: layer, screen: Size(width: 402, height: 874), settings: settings)
        for row in Layouts.layout(for: context).rows {
            for case .key(let key) in row where key.action == .character(character) { return key.alternates }
        }
        return []
    }

    /// A long press opens on the key's own letter with the language's likeliest beside it, toward the middle, and
    /// leaves out letters the language has a key for.
    @Test func eachLanguageLongPressesAsApplesDoes() {
        #expect(alternates("a", "es") == ["a", "á", "ª", "à", "ä", "â", "ã", "å", "ą", "æ", "ā"])
        #expect(alternates("a", "de") == ["a", "à", "á", "â", "æ", "ã", "å", "ā"])
        #expect(alternates("o", "fr") == ["ō", "ø", "õ", "ó", "ò", "ö", "º", "œ", "ô", "o"])
        #expect(alternates("ä", "sv") == ["æ", "ä"])
        #expect(alternates("a", "en") == Alternates.for("a"))
        #expect(alternates("\"", "de", layer: .numbers) == ["»", "«", "”", "“", "„", "\""])
    }

    /// Each language's own currency on the numbers layer, where English has its dollar.
    @Test func eachLanguageHasItsCurrency() {
        let currency = { (language: String) -> Bool in
            var settings = KeyboardSettings()
            settings.language = language
            let context = LayoutContext(
                device: .phone, layer: .numbers, screen: Size(width: 402, height: 874), settings: settings)
            return Layouts.layout(for: context).rows.joined().contains {
                if case .key(let key) = $0 {
                    key.action == .character(Language.named(language).currency)
                } else {
                    false
                }
            }
        }
        #expect(["en", "es", "fr", "de", "pt", "it", "sv"].allSatisfy(currency))
    }
}
