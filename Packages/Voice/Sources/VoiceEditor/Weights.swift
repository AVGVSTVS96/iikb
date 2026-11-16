import Foundation

/// The weights Clean runs and all iikb knows of them: where they come from and how they're asked. Swapping the model is
/// a change to `shipped` alone, and `scripts/clean` then holds the new weights to its rows.
///
/// What any weights must be, which `Editor` holds them to:
/// - a GGUF chat model llama.cpp loads, run on the CPU;
/// - asked with `before`, the transcript, then `after`, the frame's special tokens read as tokens and the
///   transcript's never. The frame is written out here, not rendered from the GGUF's chat template, since llama.cpp's
///   C API renders only the templates it knows by name and has no switch for Qwen3's thinking;
/// - answering with the edited text alone, then its end-of-generation token;
/// - read greedily, so a transcript gets the same reply here, in the bench and on the iPhone.
public struct Weights: Sendable {
    /// As a transcript names it after the voice model, "Parakeet v3 + own-1000".
    public let name: String
    public let bytes: Int
    /// A release asset on iikb's repo, so the file behind it never changes.
    public let url: URL
    public let sha256: String
    let before: String
    let after: String

    /// iikb's own fine-tune of Qwen3-0.6B on public data, at 4 bits. Its user turn is the transcript alone, with no
    /// system line, and the empty think block is what Qwen3's template writes with thinking off.
    public static let shipped = Weights(
        name: "own-1000", bytes: 396_704_800,
        url: URL(string: "https://github.com/AVGVSTVS96/iikb/releases/download/clean-own-1000/own-1000-q4_k_m.gguf")!,
        sha256: "fe914294e745e593d5c7418def3a7c6a1d702cdc15b5ef70b5b2f88d609cd06f",
        before: "<|im_start|>user\n", after: "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
}
