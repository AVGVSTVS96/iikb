import KeyboardCore
import KeyboardEnglish
import KeyboardStore
import VoiceModels

extension VoiceModel {
    struct Written {
        /// As your style and vocabulary have it (`DictationWriting`).
        var text: String
        /// As the model wrote it.
        var heard: String
        /// As the model wrote it, with your vocabulary and no style or lists: what a field of addresses or digits reads.
        var plain: String
        var model: String
    }

    /// A finished recording written down by the picked model, once it's ready: a dictation, Transcribe Again, and a
    /// recording an ended app left all go through here, in the style picked for `app`, the one it was said for.
    func write(_ recording: [Float], for app: String?) async throws -> Written {
        let (heard, model) = try await write(recording)
        return Written(
            text: DictationWriting.typed(heard, in: app), heard: heard, plain: DictationWriting.plain(heard),
            model: model)
    }
}

extension DictationWriting {
    /// What iikb types for what the voice model wrote: as Settings › Voice writes it for `app` (its bundle ID), then with
    /// your vocabulary's words and the made-up words that sound like them, so a term keeps its own spelling. The keyboard
    /// sets its capitals.
    static func typed(_ heard: String, in app: String?) -> String {
        VoiceVocabulary.shared.vocabulary.corrected(
            SettingsStore.load().dictation(in: app).written(heard), lexicon: .english)
    }

    /// What the voice model wrote, with your vocabulary's words and nothing of the style or lists.
    static func plain(_ heard: String) -> String {
        VoiceVocabulary.shared.vocabulary.corrected(heard, lexicon: .english)
    }
}

extension DictationEditing {
    var title: String {
        switch self {
        case .asSaid: "As Said"
        case .light: "No Um or Uh"
        case .clean: "Clean"
        }
    }
}

extension DictationLists {
    var title: String {
        switch self {
        case .numbered: "Numbered"
        case .bulleted: "Bulleted"
        case .off: "Off"
        }
    }
}
