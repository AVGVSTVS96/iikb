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
        #expect(Language.all.map(\.name) == ["English", "Español", "Français", "Deutsch", "Português", "Italiano", "Svenska"])
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
}
