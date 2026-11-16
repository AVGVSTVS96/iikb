import KeyboardCore
import KeyboardEnglish
import KeyboardStore
import VoiceModels

extension VoiceModel {
    struct Written {
        /// As your style and vocabulary have it (`DictationWriting`).
        var text: String
        /// As the voice model wrote it.
        var heard: String
        /// As the voice model wrote it, with your vocabulary and no style or lists: what a field of addresses or digits
        /// reads.
        var plain: String
        /// The models that wrote it: the voice model, and Clean's where its reply was typed.
        var model: String
    }

    /// A finished recording written down by the picked model, once it's ready: a dictation, Transcribe Again, and a
    /// recording an ended app left all go through here, in the style picked for `app`, the one it was said for.
    func write(_ recording: [Float], for app: String?) async throws -> Written {
        let (heard, model) = try await write(recording)
        let edited = await CleanModel.shared.edit(heard)
        let writing = SettingsStore.load().dictation(in: app)
        let taken = edited.map { writing.takes($0, of: heard) } ?? false
        return Written(
            text: writing.typed(heard, edited: edited), heard: heard, plain: DictationWriting.plain(heard),
            model: taken ? "\(model) + \(CleanModel.name)" : model)
    }
}

extension DictationWriting {
    /// What iikb types for what the voice model `heard`, given Clean's model's reply to it where there is one: as
    /// Settings › Voice writes it, then with your vocabulary's words and the made-up words that sound like them, so a
    /// term keeps its own spelling. The keyboard sets its capitals.
    func typed(_ heard: String, edited: String?) -> String {
        VoiceVocabulary.shared.vocabulary.corrected(written(heard, edited: edited), lexicon: .english)
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

extension DictationTextMode {
    /// Text Mode's names, from when it was a setting of its own (`KeyboardSettings.dictationWords`).
    var title: String {
        switch self {
        case .spelledOut: "Spelled Out"
        case .abbreviated: "Abbreviated"
        case .texting: "Texting"
        case .genZ: "Gen Z"
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
