import KeyboardCore
import KeyboardStore
import SwiftUI

/// The language iikb types and, where it has more than one, the layout of its letters, under the preview, which changes
/// with a pick at once. English is part of iikb; every other language's words download here and are read offline.
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
                    title: language.name, detail: detail(of: language), phase: phase(of: language),
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
            if !status.fullAccess {
                ActionRow(title: "Allow Full Access", symbol: "arrow.up.forward") { AppStatus.openSettings() }
            }
        }
        .onAppear {
            downloads.reload()
            downloads.picked = { pick($0) }
        }
        if language.layouts.count > 1 {
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
        }
    }

    /// The picked language first, so it's in view under the preview, then the rest; set as the page opens, so no row
    /// moves while it's open.
    private static func order(picked: String) -> [Language] {
        Language.all.filter { $0.id == picked } + Language.all.filter { $0.id != picked }
    }

    private var footer: String {
        "\(status.fullAccess ? "Downloaded languages work offline." : "Downloaded languages need Allow Full Access.") "
            + "Swipe typing is English only."
    }

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

    /// What VoiceOver adds to a language's name: German and 6.5 MB for Deutsch.
    private func detail(of language: Language) -> String {
        let name = Locale.current.localizedString(forLanguageCode: language.id).flatMap {
            $0 == language.name ? nil : $0
        }
        let size =
            language.id == Language.english.id
            ? "Built in" : (downloads.items[language.id]?.size ?? 0).formatted(.byteCount(style: .file))
        return [name, size].compactMap(\.self).joined(separator: ", ")
    }
}
