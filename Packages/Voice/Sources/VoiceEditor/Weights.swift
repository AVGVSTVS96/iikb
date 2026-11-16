import Foundation

/// The weights Clean runs and all iikb knows of them: where they come from and how they're asked. Swapping the model is
/// a change to `shipped` alone, and `scripts/clean` then holds the new weights to its rows.
///
/// What any weights must be, which `Editor` holds them to:
/// - a GGUF chat model llama.cpp loads, run on the CPU;
/// - asked with `before`, the transcript, then `after`, the frame's special tokens read as tokens and the
///   transcript's never. The frame is written out here, not rendered from the GGUF's chat template, since llama.cpp's
///   C API renders only the templates it knows by name and has no switch for Qwen3's thinking;
/// - answering with the edited text alone, then its end-of-generation token. Its control and added tokens (Qwen3's
///   `</think>`) are markup, never text, so a reply drops them;
/// - read greedily, so a transcript gets the same reply here, in the bench and on the iPhone.
public struct Weights: Sendable {
    /// As a transcript names it after the voice model, "Parakeet v3 + Clean 1".
    public let name: String
    public let bytes: Int
    /// A release asset on iikb's repo, so the file behind it never changes.
    public let url: URL
    public let sha256: String
    /// The longest transcript they edit, in tokens: none they were trained on is longer, and `Editor` makes room for
    /// that and its reply alone. A longer one gets no reply (`Editor.Failure.tooLong`), so Clean types it by its rules.
    public let longest: Int
    /// What `Editor` holds in memory beside the mapped file, in bytes: its KV cache, at the context `longest` makes,
    /// and llama.cpp's working memory, as llama.cpp's log gives them (VoiceEditor/AGENTS.md).
    public let memory: Int
    let before: String
    let after: String

    /// iikb's own fine-tune of Qwen3-0.6B on public data, at 4 bits. Its user turn is the transcript alone, with no
    /// system line, and the empty think block is what Qwen3's template writes with thinking off.
    public static let shipped = Weights(
        name: "Clean 1", bytes: 396_704_640,
        url: URL(string: "https://github.com/AVGVSTVS96/iikb/releases/download/clean-20261115/clean-1-q4_k_m.gguf")!,
        sha256: "348c813eac45101c6976e93fdae74b0413729c18367503d714c78e78509fc7fe", longest: 400,
        memory: 190 << 20, before: "<|im_start|>user\n",
        after: "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
}
