import KeyboardCore
import KeyboardStore
import SwiftUI

/// The languages iikb types, all of them at once, and the layout of their letters where there's more than one, under
/// the preview, which changes with a pick at once. A tap checks a language or unchecks it, and one always stays.
/// English is part of iikb; every other language's words download here and are read offline.
struct LanguageSettings: View {
    private let model = SettingsModel.shared
    private let downloads = LanguageDownloads.shared
    private let status = AppStatus.shared

    @State private var shown = Self.order(picked: SettingsModel.shared.settings.languages)

    private var languages: [Language] { model.settings.languages }

    var body: some View {
        Box(footer: footer) {
            ForEach(shown) { language in
                DownloadRow(
                    title: language.name, detail: detail(of: language), phase: phase(of: language),
                    picked: languages.contains(language)
                ) {
                    if languages.contains(language) {
                        drop(language)
                    } else if language == .english || LanguageFiles.has(language.id) {
                        add(language)
                    } else {
                        downloads.download(language.id, thenPick: true)
                    }
                } download: {
                    downloads.download(language.id)
                } cancel: {
                    downloads.cancel(language.id)
                } remove: {
                    downloads.remove(language.id)
                }
            }
            if !status.fullAccess {
                ActionRow(title: "Allow Full Access", symbol: "arrow.up.forward") { AppStatus.openSettings() }
            }
        }
        .onAppear {
            downloads.reload()
            downloads.picked = { add(.named($0)) }
        }
        if model.settings.layouts.count > 1 {
            Box {
                MenuRow(
                    title: "Keyboard Layout",
                    selection: Binding {
                        model.settings.letters
                    } set: { layout in
                        withAnimation(.snappy) { model.update { $0.layout = layout.id } }
                    },
                    choices: model.settings.layouts, label: \.name)
            }
        }
    }

    /// The picked languages first, so they're in view under the preview, then the rest; set as the page opens, so no
    /// row moves while it's open.
    private static func order(picked: [Language]) -> [Language] {
        picked + Language.all.filter { !picked.contains($0) }
    }

    private var footer: String {
        let downloaded =
            status.fullAccess ? "Downloaded languages work offline." : "Downloaded languages need Allow Full Access."
        return "Type in every language you check, with no switching. \(downloaded)"
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

    /// Another language types on the layout that's up, and adds its own to those to pick from.
    private func add(_ language: Language) {
        withAnimation(.snappy) { model.update { $0.languages.append(language) } }
    }

    /// A layout only the language let go offered goes with it.
    private func drop(_ language: Language) {
        guard languages.count > 1 else { return }
        withAnimation(.snappy) {
            model.update { settings in
                settings.languages.removeAll { $0 == language }
                if !settings.layouts.contains(where: { $0.id == settings.layout }) { settings.layout = nil }
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
