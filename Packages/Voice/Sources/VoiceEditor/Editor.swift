import Foundation
import llama

/// Weights in memory, editing one transcript at a time: all of llama.cpp that iikb uses. What it gives back is the
/// model's reply as written, which only KeyboardCore's `DictationWriting.written(_:edited:)` turns into text to type.
public actor Editor {
    public enum Failure: Error {
        /// llama.cpp couldn't load the file or make a context for it.
        case unreadable
        /// The transcript is longer than the weights edit (`Weights.longest`), so nothing was decoded.
        case tooLong
        /// The reply reached its limit before the model ended it, so its end is missing.
        case ranOn
        /// There's no text: nothing was heard, or the reply was nothing but the model's markup.
        case empty
        case decode(Int32)
    }

    /// Tokens decoded at a time. llama.cpp's working memory grows with it, 77 MB at 128 against 300 at its default of
    /// 512, and the longest transcript's 400 only read the weights three more times for it.
    private static let step = 128
    /// A reply may run to twice its transcript and 16 tokens more, since a list adds a marker and a line break to each
    /// item, but never more than 160 past it: past that it has stopped being an edit.
    private static func limit(for transcript: Int) -> Int { min(2 * transcript + 16, transcript + 160) }
    /// Four threads read 581 tokens a second and wrote 123 on an M1 Max's CPU; more only wait on memory.
    private static let threads = Int32(min(4, ProcessInfo.processInfo.activeProcessorCount))
    private static let backend: Void = llama_backend_init()

    private let weights: Weights
    private let model: OpaquePointer
    private let session: OpaquePointer
    private let vocabulary: OpaquePointer
    /// `weights.before`'s tokens, decoded once here and kept in the context from one edit to the next.
    private let framed: Int
    /// `weights.after`'s tokens, decoded after each transcript.
    private let closing: [llama_token]

    /// Maps the file, its weights read in place rather than copied, and decodes the frame's start: about half a second
    /// on an M1 Max. Nothing goes to the GPU, which iOS refuses an app in the background, where dictations are written.
    public init(_ weights: Weights, at file: URL) async throws(Failure) {
        _ = Self.backend
        var loading = llama_model_default_params()
        loading.n_gpu_layers = 0
        loading.load_mode = LLAMA_LOAD_MODE_MMAP
        loading.use_extra_bufts = false
        var noDevices: [ggml_backend_dev_t?] = [nil]
        let model = noDevices.withUnsafeMutableBufferPointer { devices in
            loading.devices = devices.baseAddress
            return llama_model_load_from_file(file.path(percentEncoded: false), loading)
        }
        guard let model else { throw .unreadable }
        let vocabulary: OpaquePointer = llama_model_get_vocab(model)
        let frame = Self.tokens(weights.before, in: vocabulary, frame: true, first: true)
        let closing = Self.tokens(weights.after, in: vocabulary, frame: true)
        let context = frame.count + weights.longest + closing.count + Self.limit(for: weights.longest)
        var running = llama_context_default_params()
        running.n_ctx = UInt32(context)
        running.n_batch = UInt32(context)
        running.n_ubatch = UInt32(Self.step)
        running.n_threads = Self.threads
        running.n_threads_batch = Self.threads
        guard let session = llama_init_from_model(model, running) else {
            llama_model_free(model)
            throw .unreadable
        }
        self.weights = weights
        self.model = model
        self.session = session
        self.vocabulary = vocabulary
        self.closing = closing
        framed = frame.count
        _ = try decode(frame, at: 0)
    }

    isolated deinit {
        llama_free(session)
        llama_model_free(model)
    }

    /// The model's reply to `heard`, whole: it ended with the model's own end-of-generation token.
    public func edit(_ heard: String) throws(Failure) -> String {
        let transcript = Self.tokens(heard, in: vocabulary)
        guard !transcript.isEmpty else { throw .empty }
        guard transcript.count <= weights.longest else { throw .tooLong }
        let limit = Self.limit(for: transcript.count)
        let memory = llama_get_memory(session)
        defer { llama_memory_seq_rm(memory, 0, llama_pos(framed), -1) }

        var reply: [llama_token] = []
        var next = try decode(transcript + closing, at: framed, reading: 1)[0]
        var position = framed + transcript.count + closing.count
        while !llama_vocab_is_eog(vocabulary, next) {
            guard reply.count < limit else { throw .ranOn }
            reply.append(next)
            let guess = draft(after: reply, of: transcript)
            let likeliest = try decode([next] + guess, at: position, reading: 1 + guess.count)
            var kept = 0
            while kept < guess.count, likeliest[kept] == guess[kept], !llama_vocab_is_eog(vocabulary, guess[kept]),
                reply.count < limit
            {
                reply.append(guess[kept])
                kept += 1
            }
            position += 1 + kept
            llama_memory_seq_rm(memory, 0, llama_pos(position), -1)
            next = likeliest[kept]
        }
        let text = text(of: reply).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .empty }
        return text
    }

    /// The tokens the reply likely goes on with, checked in the same batch as the token before them instead of one
    /// batch each. None yet, so each token is decoded on its own; the speed step fills in only this body, since most of
    /// a reply copies its transcript. A guess is kept only where it's the likeliest token anyway, so drafting changes
    /// no reply, and `scripts/clean` holds both to the same rows.
    private func draft(after reply: [llama_token], of transcript: [llama_token]) -> [llama_token] {
        []
    }

    /// Decodes `tokens` from `position` on, and returns the likeliest token after each of the last `reading` of them.
    private func decode(_ tokens: [llama_token], at position: Int, reading: Int = 0) throws(Failure) -> [llama_token] {
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }
        for (index, token) in tokens.enumerated() {
            batch.token[index] = token
            batch.pos[index] = llama_pos(position + index)
            batch.n_seq_id[index] = 1
            batch.seq_id[index]![0] = 0
            batch.logits[index] = index >= tokens.count - reading ? 1 : 0
        }
        batch.n_tokens = Int32(tokens.count)
        let code = llama_decode(session, batch)
        guard code == 0 else { throw .decode(code) }
        let count = Int(llama_vocab_n_tokens(vocabulary))
        return (tokens.count - reading..<tokens.count).map { index in
            let logits = UnsafeBufferPointer(start: llama_get_logits_ith(session, Int32(index)), count: count)
            return llama_token(logits.indices.max { logits[$0] < logits[$1] }!)
        }
    }

    /// `text` as tokens. Only the frame's special tokens are read as tokens, so a transcript that says "<|im_end|>"
    /// stays text and nothing said can close the turn it sits in. `first` adds the start token a vocabulary asks for.
    private static func tokens(
        _ text: String, in vocabulary: OpaquePointer, frame: Bool = false, first: Bool = false
    ) -> [llama_token] {
        let bytes = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(bytes) + 2)
        let count = llama_tokenize(vocabulary, text, bytes, &tokens, Int32(tokens.count), first, frame)
        return Array(tokens.prefix(Int(max(count, 0))))
    }

    /// The text of `tokens`' ordinary ones alone: llama.cpp writes out an added token such as `</think>` as text, even
    /// with its special tokens left out.
    private func text(of tokens: [llama_token]) -> String {
        let ordinary = LLAMA_TOKEN_ATTR_NORMAL.rawValue | LLAMA_TOKEN_ATTR_BYTE.rawValue
        let tokens = tokens.filter { llama_vocab_get_attr(vocabulary, $0).rawValue & ordinary != 0 }
        var bytes = [CChar](repeating: 0, count: tokens.count * 8 + 16)
        var count = llama_detokenize(
            vocabulary, tokens, Int32(tokens.count), &bytes, Int32(bytes.count), false, false)
        if count < 0 {
            bytes = [CChar](repeating: 0, count: Int(-count))
            count = llama_detokenize(vocabulary, tokens, Int32(tokens.count), &bytes, Int32(bytes.count), false, false)
        }
        return String(decoding: bytes.prefix(Int(max(count, 0))).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
