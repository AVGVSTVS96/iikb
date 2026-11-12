import KeyboardCore
import KeyboardStore
import SwiftUI

/// The language iikb types and the layout of its letters, over the preview, which changes with a pick at once. English
/// is part of iikb; every other language's words download here, once, and are read offline.
struct LanguageSettings: View {
    private let model = SettingsModel.shared
    private let downloads = LanguageDownloads.shared
    private let status = AppStatus.shared

    @State private var shown = Self.order(picked: SettingsModel.shared.settings.language)

    private var language: Language { Language.named(model.settings.language) }

    var body: some View {
        Box(footer: footer) {
            ForEach(shown) { language in
                DownloadRow(
                    title: language.name, detail: Self.ownLanguage(language),
                    size: downloads.items[language.id]?.size ?? 0, phase: phase(of: language),
                    picked: language.id == model.settings.language
                ) {
                    if language.id == Language.english.id || LanguageFiles.has(language.id) {
                        pick(language.id)
                    } else {
                        downloads.download(language.id, thenPick: true)
                    }
                } download: {
                    downloads.download(language.id)
                } cancel: {
                    downloads.cancel(language.id)
                } remove: {
                    if model.settings.language == language.id { pick(Language.english.id) }
                    downloads.remove(language.id)
                }
            }
        }
        .onAppear {
            downloads.reload()
            downloads.picked = { pick($0) }
        }
        Box {
            MenuRow(
                title: "Keyboard Layout",
                selection: Binding {
                    model.settings.letters
                } set: { layout in
                    withAnimation(.snappy) { model.update { $0.layout = layout.id } }
                },
                choices: language.layouts, label: \.name)
        }
        if !status.fullAccess {
            Box(footer: "The keyboard needs Full Access to use a downloaded language.") {
                ActionRow(title: "Allow Full Access", symbol: "arrow.up.forward") { AppStatus.openSettings() }
            }
        }
    }

    /// The picked language first, so it's in view under the preview, then the rest; set as the page opens, so no row
    /// moves while it's open.
    private static func order(picked: String) -> [Language] {
        Language.all.filter { $0.id == picked } + Language.all.filter { $0.id != picked }
    }

    private let footer =
        "Downloaded languages work offline. Swipe typing and the next-word model are English only."

    private func phase(of language: Language) -> DownloadRow.Phase {
        guard language.id != Language.english.id else { return .builtIn }
        return switch downloads.state(of: language.id) {
        case .absent: .absent
        case .downloading(let done): LanguageFiles.has(language.id) ? .updating(done) : .downloading(done)
        case .failed(let reason): .failed(reason)
        case .ready: .ready
        }
    }

    /// A new language starts on its own layout, as Apple's keyboard does.
    private func pick(_ id: String) {
        withAnimation(.snappy) {
            model.update {
                $0.language = id
                $0.layout = nil
            }
        }
    }

    /// The language's name in the one this iPhone is set to, under its own: German under Deutsch.
    private static func ownLanguage(_ language: Language) -> String? {
        let name = Locale.current.localizedString(forLanguageCode: language.id)
        return name == language.name ? nil : name
    }
}
