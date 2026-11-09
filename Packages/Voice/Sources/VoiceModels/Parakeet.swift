import FluidAudio
import Foundation
import KeyboardStore
import VoiceCapture

/// A loaded Parakeet, hearing 16 kHz sound in English.
nonisolated protocol Parakeet: Sendable {
    func hear(_ samples: [Float]) async throws -> ASRResult
}

extension AsrManager: Parakeet {
    /// Held to the Latin alphabet, which v3 otherwise leaves for Cyrillic on short or unclear English.
    func hear(_ samples: [Float]) async throws -> ASRResult {
        var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
        return try await transcribe(samples, decoderState: &state, language: .english)
    }
}

nonisolated extension ASRConfig {
    /// FluidAudio's, re-hearing a pause Parakeet wrote nothing in only once it's 1.5 s or more. From 0.18.2 it re-hears
    /// every pause from 0.5 s and the start before the first word (#1061, #1056, measured on Italian and German oral
    /// history and earnings calls), which in his English dictations heard words in breaths and room sound ("Mm",
    /// "Right.", "mint", "to enjoy") and nothing he'd said; from 1.5 s it still finds what 0.18.0 dropped (Nov 8,
    /// scripts/voiceloop: real 1.87% of words wrong to 1.85%, loud 41.01% to 40.99%, 0.18.0 1.85% and 41.17%).
    static let dictation = ASRConfig(seamGapRepairMinGapSeconds: 1.5)
}

/// A Parakeet, and Silero's voice-activity model (FluidAudio's `VadManager`), which hears whether anyone talks.
nonisolated struct Dictation: Sendable {
    let parakeet: any Parakeet
    let talking: VadManager?

    /// Loads Silero's model beside `parakeet`, downloading it once (2 MB); without it, as when that first download
    /// can't reach Hugging Face, every recording is written as Parakeet hears it, until the next load.
    init(_ parakeet: any Parakeet) async {
        self.parakeet = parakeet
        talking = try? await VadManager()
    }

    /// The recording leveled (`Recording.leveled`), a tap with next to nothing said padded up to the shortest sound
    /// Parakeet takes, and nothing at all when Silero hears no one talking in it and Parakeet is unsure of its first
    /// word. Where no one talks Parakeet writes "Yeah.", "Okay." or "Thank you.", its first piece at 0.1 to 0.35, where
    /// Silero hears talking under 0.5 (Nov 8: 8 of his taps); of 2,803 dictations, said and made, that blanks none with
    /// a word in it he said. On the Neural Engine a minute of talking is written in well under a second.
    func write(_ recording: [Float]) async throws -> String {
        var samples = Recording.leveled(recording)
        let shortest = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if samples.count < shortest { samples += repeatElement(0, count: shortest - samples.count) }
        let heard = try await parakeet.hear(samples)
        if let talking, let first = heard.tokenTimings?.first, first.confidence < 0.5,
            try await talking.process(samples).allSatisfy({ $0.probability < 0.5 })
        {
            return ""
        }
        return heard.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated extension AsrModelVersion {
    /// Where this Parakeet's files live: the App Group's container, whose path outlives an install, where the app's own
    /// container gets a new one with each, and Core ML keys what it compiles by the path a model loads from (App/Voice/AGENTS.md).
    var folder: URL {
        Self.clearCompiled
        let own = AsrModels.defaultCacheDirectory(for: self)
        return Self.shared?.appending(path: "Models").appending(path: own.lastPathComponent) ?? own
    }

    /// Core ML's compiles, `<bundle ID>/com.apple.e5rt.e5bundlecache/<OS build>/…` in the app's caches, emptied the first
    /// time a new install or iOS reaches for a Parakeet, before any is loaded. Each install compiles them again beside
    /// the last's, which nothing else removes: 1.3 GB on the Duo and 15 GB in a simulator by Nov 5.
    private static let clearCompiled: Void = {
        let install = "\(Bundle.main.bundlePath) \(ProcessInfo.processInfo.operatingSystemVersionString)"
        guard UserDefaults.standard.string(forKey: "compiledFor") != install else { return }
        try? FileManager.default.removeItem(
            at: URL.cachesDirectory.appending(
                path: "\(Bundle.main.bundleIdentifier ?? "")/com.apple.e5rt.e5bundlecache"))
        UserDefaults.standard.set(install, forKey: "compiledFor")
    }()

    /// The App Group's FluidAudio folder. The app's own is moved there the first time, a rename.
    private static let shared: URL? = {
        guard let library = AppGroup.library else { return nil }
        let own = URL.applicationSupportDirectory.appending(path: "FluidAudio")
        let shared = library.appending(path: "Application Support/FluidAudio")
        let files = FileManager.default
        guard files.fileExists(atPath: own.path(percentEncoded: false)),
            !files.fileExists(atPath: shared.path(percentEncoded: false))
        else { return shared }
        try? files.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? files.moveItem(at: own, to: shared)) != nil else { return nil }
        return shared
    }()
}
