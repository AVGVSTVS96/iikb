import KeyboardCore
import KeyboardStore
import KeyboardUI
import SwiftUI
import UIKit

enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    private static func integer(_ key: String) -> Int? {
        defaults.string(forKey: key).flatMap { Int($0) }
    }

    static var focus: Bool { defaults.bool(forKey: "iikbFocus") }
    /// `-iikbDictation listening`, `writing`, `loading` or `failed` shows the tab bar's `DictationBar` in that state, for
    /// screenshots, since a simulator's microphone can't be relied on to record.
    static var dictation: DictationBar.State? {
        switch defaults.string(forKey: "iikbDictation") {
        case "listening": .listening
        case "writing": .writing(waiting: nil)
        case "loading": .writing(waiting: "Model loading…")
        case "failed":
            .failed(
                title: "Couldn’t listen", reason: "iikb needs the microphone. Turn it on in Settings › Apps › iikb.")
        default: nil
        }
    }

    /// Seven seconds of a voice into the bar's waveform, for the listening screenshot.
    @MainActor static func speak(into bar: DictationBar) {
        bar.layoutIfNeeded()
        for step in 0..<82 {
            let wave = abs(sin(Double(step) * 0.55)) * (0.6 + 0.4 * abs(sin(Double(step) * 0.13)))
            bar.hear(Float(0.002 + 0.08 * wave * wave), recorded: Double(step + 1) * 0.085)
        }
    }
    /// `-iikbScrollToEnd YES` opens every page scrolled to its end, for screenshots of what sits above the tab bar.
    static var scrollsToEnd: Bool { defaults.bool(forKey: "iikbScrollToEnd") }
    /// The tab and page the app opens on: `-iikbTab transcripts`, `-iikbTaps YES` for Stats' Taps, `-iikbStats dictation`
    /// for another of its pills, `-iikbSettings typing` for a settings page (`YES` for the list), as `SettingsPage.Page`
    /// names them.
    static func route() {
        let router = Router.shared
        if let section = statsSection { return router.show(section) }
        if let page = defaults.string(forKey: "iikbSettings") {
            return router.show(.settings, settings: SettingsPage.Page(rawValue: page))
        }
        router.show(defaults.string(forKey: "iikbTab").flatMap(Router.Destination.init) ?? .home)
    }

    /// `-iikbTranscript YES` opens the newest transcript on its own page where it doesn't sit beside the list.
    static var opensTranscript: Bool { defaults.bool(forKey: "iikbTranscript") }

    static var statsSection: StatsPage.Section? {
        defaults.bool(forKey: "iikbTaps") ? .taps : defaults.string(forKey: "iikbStats").flatMap(StatsPage.Section.init)
    }
    /// `-iikbStatsComputer Mac` shows the computer you added by that name.
    static var statsComputer: String? { defaults.string(forKey: "iikbStatsComputer") }
    /// `-iikbAddComputer YES` opens Stats' Add Computer.
    static var addsComputer: Bool { defaults.bool(forKey: "iikbAddComputer") }

    static var tapsMode: TapMapView.Mode? {
        switch defaults.string(forKey: "iikbTapsMode") {
        case "heat": .heat
        case "aim": .aim
        case "accuracy": .accuracy
        default: nil
        }
    }
    static var tapsScroll: String? { defaults.string(forKey: "iikbTapsScroll") }
    static var tapsKey: String? { defaults.string(forKey: "iikbTapsKey") }
    static var orientation: UIInterfaceOrientationMask? {
        switch defaults.string(forKey: "iikbOrientation") {
        case "landscape": .landscapeRight
        case "portrait": .portrait
        default: nil
        }
    }

    /// `-iikbResetSettings YES` puts back Apple's keyboard settings, which the UI tests are written against, and forgets
    /// what iikb learned.
    static func resetSettingsIfAsked() {
        guard defaults.bool(forKey: "iikbResetSettings") else { return }
        SettingsStore.reset(to: KeyboardSettings())
        MemoryStore.reset()
    }

    /// `-iikbOneHanded left` and `-iikbCompactPanels YES`, `-iikbAutoCapitalization YES`, `-iikbAutoCorrection YES`,
    /// `-iikbMicKey YES` or `-iikbPredictiveText NO` set those settings for a test.
    static func applySettings() {
        if let hand = defaults.string(forKey: "iikbOneHanded").flatMap(OneHanded.init) { SettingsStore.set(hand) }
        let toggles: [(String, WritableKeyPath<KeyboardSettings, Bool>)] = [
            ("iikbCompactPanels", \.compactPanels), ("iikbAutoCapitalization", \.autoCapitalization),
            ("iikbAutoCorrection", \.autoCorrection), ("iikbMicKey", \.micKey),
            ("iikbPredictiveText", \.predictiveText),
        ]
        for (key, path) in toggles where defaults.object(forKey: key) != nil {
            SettingsStore.set(defaults.bool(forKey: key), for: path)
        }
    }

    /// `-iikbTheme mechanical -iikbThemeAppearance dark -iikbCharacterPreview detached -iikbNumberRow YES -iikbSkinTone medium
    /// -iikbKeySpacing tighter -iikbKeyRoundness rounder -iikbStopAnimation drain` set the keyboard's look for screenshots.
    static func applyLook() {
        var settings = SettingsStore.load()
        if let theme = defaults.string(forKey: "iikbTheme").flatMap(ThemeName.init) { settings.theme = theme }
        if let appearance = defaults.string(forKey: "iikbThemeAppearance").flatMap(ThemeAppearance.init) {
            settings.themeAppearance = appearance
        }
        if let stop = defaults.string(forKey: "iikbStopAnimation").flatMap(StopAnimation.init) {
            settings.stopAnimation = stop
        }
        if let preview = defaults.string(forKey: "iikbCharacterPreview").flatMap(CharacterPreview.init) {
            settings.characterPreview = preview
        }
        if defaults.object(forKey: "iikbNumberRow") != nil {
            settings.numberRow = defaults.bool(forKey: "iikbNumberRow")
        }
        if let tone = defaults.string(forKey: "iikbSkinTone") { settings.skinTone = SkinTone(rawValue: tone) }
        if let spacing = defaults.string(forKey: "iikbKeySpacing").flatMap(KeySpacing.init) {
            settings.keySpacing = spacing
        }
        if let roundness = defaults.string(forKey: "iikbKeyRoundness").flatMap(KeyRoundness.init) {
            settings.keyRoundness = roundness
        }
        if settings != SettingsStore.load() { SettingsStore.save(settings) }
    }

    static func configure(_ field: UITextView) {
        if let value = integer("FullKeyboardType").flatMap(UIKeyboardType.init) { field.keyboardType = value }
        if let value = integer("iikbReturnKey").flatMap(UIReturnKeyType.init) { field.returnKeyType = value }
        if let text = defaults.string(forKey: "iikbText") { field.text = text }
        if defaults.bool(forKey: "iikbSends") { sends(field) }
    }

    /// `-iikbSends YES`: return sends, emptying the field wherever the caret is, as a messaging app does, for
    /// scripts/edittest.
    private static func sends(_ field: UITextView) {
        field.returnKeyType = .send
        field.delegate = sender
    }

    @MainActor private static let sender = Sender()

    private final class Sender: NSObject, UITextViewDelegate {
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            textView.text = ""
            return false
        }
    }
}
