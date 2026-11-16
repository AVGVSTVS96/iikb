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
        /// The language it was said in, of the ones you type and English (`Language.of`).
        var language: Language
    }

    /// A finished recording written down by the picked model, once it's ready: a dictation, Transcribe Again, and a
    /// recording an ended app left all go through here, in the style picked for `app`, the one it was said for, and in
    /// the language it was said in. Your vocabulary's words and the made-up words that sound like them then keep their
    /// own spelling, against that language's words. The keyboard sets its capitals.
    func write(_ recording: [Float], for app: String?) async throws -> Written {
        let settings = SettingsStore.load()
        let (heard, model) = try await write(recording, in: settings.languages.map(\.id))
        let candidates = settings.dictationLanguages.compactMap { language in
            LanguageFiles.lexicon(language.id).map { (language: language, lexicon: $0) }
        }
        let language = Language.of(heard, among: candidates)
        let lexicon = candidates.first { $0.language == language }?.lexicon ?? .english
        var writing = settings.dictation(in: app)
        writing.language = language
        let vocabulary = VoiceVocabulary.shared.vocabulary
        return Written(
            text: vocabulary.corrected(writing.written(heard), lexicon: lexicon), heard: heard,
            plain: vocabulary.corrected(heard, lexicon: lexicon), model: model, language: language)
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
