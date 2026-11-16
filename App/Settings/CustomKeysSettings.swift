import KeyboardCore
import KeyboardUI
import SwiftUI

/// Raycast's Mode and Custom Keys on one page: whether iikb is the keyboard you type with, and the keys and buttons
/// around the letters (docs/design.md, "Custom Keys").
struct CustomKeysSettings: View {
    private let model = SettingsModel.shared

    private var settings: KeyboardSettings { model.settings }
    private var secondary: Bool { settings.mode == .secondary }

    var body: some View {
        let here = KeysHere()
        Box(header: "Mode") {
            ChoiceRow(
                title: KeyboardMode.primary.title, detail: "iikb is the keyboard you type with.", picked: !secondary
            ) { withAnimation(.snappy) { model.update { $0.mode = .primary } } }
            ChoiceRow(
                title: KeyboardMode.secondary.title,
                detail:
                    "Keep your other keyboard for typing. iikb opens on its menu: your clipboard, GIFs, transcripts and chats. They need Allow Full Access.",
                picked: secondary
            ) { withAnimation(.snappy) { model.update { $0.mode = .secondary } } }
            if secondary {
                ToggleRow(
                    title: "Switch Keyboard on Close",
                    detail: "Back to your other keyboard once you paste or pick something.",
                    isOn: model.binding(\.switchOnClose))
            }
        }
        Box(
            header: "Top Row",
            footer: here.leadingButton && !secondary
                ? "Hidden gives the menu button’s room to the suggestions. Your actions still open the clipboard, transcripts and GIFs: show the action row, or turn off Predictive Text."
                : nil
        ) {
            if here.leadingButton && !secondary {
                MenuRow(
                    title: "Leading Button", selection: model.binding(\.leadingButton), choices: LeadingButton.allCases
                ) { $0.title }
            }
            ToggleRow(title: "Dictation Button", isOn: model.binding(\.dictationButton))
        }
        if !secondary {
            ActionSettings(phone: here.actionRow)
            BottomRowSettings(here: here)
        }
    }
}

private struct ActionSettings: View {
    let phone: Bool
    private let model = SettingsModel.shared

    var body: some View {
        if phone {
            Box(header: "Action Row") {
                ToggleRow(
                    title: "Show Action Row", detail: "Your actions on short keys above the letters.",
                    isOn: model.binding(\.actionRow))
                if model.settings.actionRow {
                    ToggleRow(
                        title: "Always Show in Landscape",
                        detail: "Sideways, the actions sit at the bar’s left unless this is on.",
                        isOn: model.binding(\.actionRowInLandscape))
                }
            }
        }
        Box(
            header: "Actions",
            footer: "\(place) Drag a chosen action to reorder it."
        ) {
            OrderRows(items: listed, moves: model.settings.actions.contains) { panel in
                Toggle(isOn: chosen(panel)) {
                    HStack(spacing: 14) {
                        ToolGlyph(panel: panel)
                        Text(panel.title).foregroundStyle(.primary)
                    }
                }
                .tint(.blue)
            }
        }
    }

    /// Where the actions show, as `KeyboardSettings.actionPlace` puts them.
    private var place: String {
        let settings = model.settings
        guard phone, settings.actionRow else {
            return "Your actions are buttons at the bar’s left when Predictive Text is off."
        }
        return settings.actionRowInLandscape
            ? "Your actions are the action row’s keys."
            : "Your actions are the action row’s keys, and buttons at the bar’s left with the phone sideways."
    }

    /// The chosen actions in their order, then the rest as Customize Actions lists them.
    private var listed: Binding<[Panel]> {
        Binding {
            let actions = model.settings.actions
            return actions + Panel.tools.filter { !actions.contains($0) }
        } set: { order in
            model.update { settings in settings.actions = order.filter(settings.actions.contains) }
        }
    }

    private func chosen(_ panel: Panel) -> Binding<Bool> {
        Binding {
            model.settings.actions.contains(panel)
        } set: { on in
            withAnimation(.snappy) {
                model.update { settings in
                    settings.actions.removeAll { $0 == panel }
                    if on { settings.actions.append(panel) }
                }
            }
        }
    }
}

private struct BottomRowSettings: View {
    let here: KeysHere
    private let model = SettingsModel.shared

    var body: some View {
        let settings = model.settings
        if here.arrangesBottomRow {
            Box(
                header: "Bottom Row",
                footer:
                    "Hold Period for more punctuation. Drag to set the keys around the space bar in any order."
            ) {
                OrderRows(items: arranged) { key in
                    if let shown = shown(key) {
                        Toggle(isOn: shown) { Text(Self.title(of: key)).foregroundStyle(.primary) }.tint(.blue)
                    } else {
                        Text(Self.title(of: key)).foregroundStyle(.primary).frame(
                            maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if here.emojiKey {
            Box {
                ToggleRow(
                    title: "Emoji Key",
                    detail:
                        "Every emoji, from beside the space bar. Without it, a word’s emoji still show in the suggestions.",
                    isOn: model.binding(\.emojiKey))
            }
        }
        if here.recordKey && settings.dictationButton {
            Box {
                ToggleRow(
                    title: "Record Key",
                    detail:
                        "The record button left of 123, in the globe’s place, instead of at the right of the bar. The globe goes to the keyboard’s menu.",
                    isOn: model.binding(\.micKey))
            }
        }
        if here.globeKey {
            Box(
                header: "Globe Key",
                footer:
                    "At the far left of the bottom row, on iPhones with no globe under the keyboard, like the Duo. As a spacer it keeps 123 away from the corner and does nothing when tapped. As a spacer or hidden, Next Keyboard is in the keyboard’s menu."
            ) {
                ForEach(GlobeKey.allCases, id: \.self) { globe in
                    ChoiceRow(title: globe.title, picked: settings.globeKey == globe) {
                        model.update { $0.globeKey = globe }
                    }
                }
            }
        }
    }

    private var arranged: Binding<[BottomKey]> {
        Binding {
            BottomKey.arranged(model.settings.aroundSpace)
        } set: { order in
            model.update { $0.aroundSpace = order }
        }
    }

    private func shown(_ key: BottomKey) -> Binding<Bool>? {
        switch key {
        case .emoji: model.binding(\.emojiKey)
        case .period: model.binding(\.periodKey)
        case .space: nil
        }
    }

    static func title(of key: BottomKey) -> String {
        switch key {
        case .emoji: "Emoji Key"
        case .space: "Space Bar"
        case .period: "Period Key"
        }
    }
}

/// An action's glyph on its colored square, in its shelf's color in the menu, 28 tall so its row is as tall as the
/// page's others.
private struct ToolGlyph: View {
    let panel: Panel

    var body: some View {
        Glyph(
            image: panel.icon(15).map(Image.init(uiImage:)) ?? Image(systemName: "square"),
            color: Color(uiColor: panel.color), size: 28)
    }
}
