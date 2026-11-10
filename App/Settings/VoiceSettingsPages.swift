import KeyboardCore
import KeyboardEnglish
import KeyboardStore
import KeyboardUI
import SwiftUI
import VoiceCapture
import VoiceModels

/// How iikb hears you, on one page: the model that writes it down, how long the mic stays on, and which microphone.
struct VoiceSettings: View {
    var body: some View {
        ModelSettings()
        MicSettings()
        MicrophoneSettings()
    }
}

/// Which model writes what you say, with its download or why it couldn't get ready.
private struct ModelSettings: View {
    private let voice = VoiceModel.shared

    var body: some View {
        Box(
            header: "Voice Model",
            footer:
                "Everything you say is written down on this \(ThisDevice.name) and never leaves it. What you dictate while a Parakeet gets ready is written once it’s ready, in the order you said it."
        ) {
            ForEach([VoiceModel.Model.v3, .ultra, .apple], id: \.self) { choice in
                ChoiceRow(title: choice.title, detail: choice.detail, picked: choice == voice.model) {
                    voice.pick(choice)
                } extra: {
                    if choice == voice.model, voice.state != .ready { progress }
                }
            }
        }
    }

    @ViewBuilder private var progress: some View {
        switch voice.state {
        case .downloading(let done):
            ProgressView(value: done) {
                Text("Downloading, \(done.formatted(.percent.precision(.fractionLength(0))))")
            }
            .font(.footnote)
            .foregroundStyle(Color.appSecondary)
            .padding(.top, 8)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Getting ready")
            }
            .font(.footnote)
            .foregroundStyle(Color.appSecondary)
            .padding(.top, 8)
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn’t get it ready: \(reason)")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Try Again") { voice.prepare() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.top, 8)
        case .ready:
            EmptyView()
        }
    }
}

/// How iikb writes what you say, as two things: the style, how it reads, which each app can have its own of and the
/// keyboard's bar picks for the app you're in; and the cleanup, what it leaves out of what you said, the same everywhere.
/// A preview on top shows what you'd say typed as picked, with the words that show off what you last changed.
struct WritingSettings: View {
    private enum Sample {
        case style, cleanup, lists

        var said: String {
            switch self {
            case .style: "Hey, by the way, are you free tonight. The food there is amazing, for real."
            case .cleanup: "Um, so I think the the plan is, like, dinner at two, I mean three."
            case .lists: "For tonight we need one, eggs, two, milk, three, bread."
            }
        }
    }

    private static let rambled = "Um, I think the the plan is, like, two, I mean three."
    private let model = SettingsModel.shared
    @State private var sample = Sample.style
    /// Whose style the list sets: an app's, by its bundle ID, or nil for the default.
    @State private var app: String?

    private func typed(_ said: String, _ change: (inout DictationWriting) -> Void = { _ in }) -> String {
        var writing = model.settings.dictation(in: app)
        change(&writing)
        return writing.typed(said, lexicon: .english)
    }

    private func quoted(_ said: String, _ change: (inout DictationWriting) -> Void) -> String {
        "“" + typed(said, change) + "”"
    }

    private func update(_ sample: Sample, _ change: @escaping (inout KeyboardSettings) -> Void) {
        withAnimation(.snappy(duration: 0.25)) {
            self.sample = sample
            model.update(change)
        }
    }

    /// The apps you've dictated into, most dictated first, then any other with a style of its own.
    private var apps: [String] {
        var counts: [String: Int] = [:]
        for case let app? in Transcripts.shared.all.map(\.app) where app != Bundle.main.bundleIdentifier {
            counts[app, default: 0] += 1
        }
        for app in model.settings.appDictationStyles.keys where counts[app] == nil { counts[app] = 0 }
        return counts.sorted { ($0.value, AppName.of($1.key)) > ($1.value, AppName.of($0.key)) }.map(\.key)
    }

    /// The style picked for `app`, nil where it follows the default; the default's where `app` is nil.
    private var picked: DictationStyle? {
        guard let app else { return model.settings.dictationStyle }
        return model.settings.appDictationStyles[app]
    }

    private func pick(_ style: DictationStyle?) {
        update(.style) { settings in
            if let app {
                settings.appDictationStyles[app] = style
            } else if let style {
                settings.dictationStyle = style
            }
        }
    }

    var body: some View {
        WritingPreview(said: sample.said, typed: typed(sample.said))
        Box(
            header: "Style",
            footer:
                "A style sets the capitals, the punctuation and the words. Each app can have its own, also picked in the keyboard’s bar where it has room. Where a style keeps capitals, they follow Auto-Capitalization in Keyboard › Typing."
        ) {
            if !apps.isEmpty {
                MenuRow(title: "For", selection: $app, choices: [nil] + apps) { $0.map(AppName.of) ?? "Default" }
            }
            if app != nil {
                ChoiceRow(
                    title: "Default", detail: model.settings.dictationStyle.title, picked: picked == nil
                ) { pick(nil) }
            }
            ForEach(DictationStyle.allCases, id: \.self) { style in
                ChoiceRow(
                    title: style.title, detail: quoted(Sample.style.said) { $0.style = style }, picked: picked == style
                ) { pick(style) }
            }
        }
        Box(
            header: "Cleanup",
            footer:
                "Clean also takes back what you cancel with “scratch that”. Cleanup is the same in every app."
        ) {
            ForEach(DictationEditing.allCases, id: \.self) { editing in
                ChoiceRow(
                    title: editing.title, detail: quoted(Self.rambled) { $0.editing = editing },
                    picked: model.settings.dictationEditing == editing
                ) { update(.cleanup) { $0.dictationEditing = editing } }
            }
            MenuRow(
                title: "Spoken Lists",
                selection: Binding {
                    model.settings.dictationLists
                } set: { lists in
                    update(.lists) { $0.dictationLists = lists }
                }, choices: DictationLists.allCases
            ) { $0.title }
        }
    }
}

/// What you say over what iikb types for it, as picked, so a change shows at once.
private struct WritingPreview: View {
    let said: String
    let typed: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            line("You say", said, primary: false)
            Rectangle().fill(Color.appDivider).frame(height: 1)
            line("iikb types", typed, primary: true)
                .contentTransition(.opacity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
        .accessibilityElement(children: .combine)
    }

    private func line(_ title: String, _ text: String, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.appSecondary)
            Text(text)
                .font(primary ? .title3.weight(.medium) : .body)
                .foregroundStyle(primary ? Color.primary : Color.appSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How long the mic stays on after a dictation.
private struct MicSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(
            header: "Keep Mic On",
            footer:
                "After you dictate, iikb keeps the mic on this long, so the mic beside the suggestions starts and stops without leaving your app. Hold it to turn the mic off."
        ) {
            ForEach(Dictation.micChoices, id: \.self) { seconds in
                ChoiceRow(title: Dictation.title(keepingMicOn: seconds), picked: model.keepMicOn == seconds) {
                    model.keepMicOn(seconds)
                }
            }
        }
    }
}

/// Which microphone iikb dictates with when there are several.
private struct MicrophoneSettings: View {
    private let choices = MicrophoneChoices.shared

    var body: some View {
        Box(
            header: "Microphone",
            footer:
                "Automatic uses the \(ThisDevice.name) or a wired headset, never Bluetooth, so music on AirPods keeps its full quality. A pick is used whenever it’s connected; a Bluetooth one may put its device on a call while the mic is on."
        ) {
            ChoiceRow(title: "Automatic", picked: choices.picked == nil) { pick(nil) }
            ForEach(choices.all, id: \.uid) { microphone in
                ChoiceRow(title: microphone.title, detail: detail(microphone), picked: choices.isPicked(microphone)) {
                    pick(microphone)
                }
            }
        }
        .onAppear { choices.reload() }
    }

    private func pick(_ microphone: PickedMicrophone?) {
        choices.pick(microphone)
        Listener.shared.microphoneChanged()
    }

    private func detail(_ microphone: PickedMicrophone) -> String? {
        switch (microphone.kind, choices.isAway(microphone)) {
        case (.iPhone, _): "Its microphones together, so your voice isn’t lost when one is covered."
        case (.bluetooth, true): "Not connected. Used when it is."
        case (.bluetooth, false): "Full quality on AirPods that record so, else call quality while the mic is on."
        case (.other, true): "Not connected. Used when it is."
        case (.other, false): nil
        }
    }
}
