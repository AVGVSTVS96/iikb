import KeyboardCore
import KeyboardEnglish

extension DictationWriting {
    /// What iikb types for what the voice model `heard`, given Clean's model's reply to it where there is one: as
    /// Settings › Voice writes it, then with your vocabulary's words and the made-up words that sound like them, so a
    /// term keeps its own spelling. The keyboard sets its capitals.
    public func typed(_ heard: String, edited: String?, vocabulary: Vocabulary) -> String {
        vocabulary.corrected(written(heard, edited: edited), lexicon: .english)
    }

    /// What the voice model wrote, with your vocabulary's words and nothing of the style or lists.
    public static func plain(_ heard: String, vocabulary: Vocabulary) -> String {
        vocabulary.corrected(heard, lexicon: .english)
    }
}
