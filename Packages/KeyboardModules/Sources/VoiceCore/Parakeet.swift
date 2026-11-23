import FluidAudio
import Foundation
import KeyboardStore
import OSLog

nonisolated private let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

/// A loaded Parakeet, hearing 16 kHz sound in English.
public nonisolated protocol Parakeet: Sendable {
    func hear(_ samples: [Float]) async throws -> ASRResult
}

extension AsrManager: Parakeet {
    /// Held to the Latin alphabet, which v3 otherwise leaves for Cyrillic on short or unclear English.
    public func hear(_ samples: [Float]) async throws -> ASRResult {
        var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
        return try await transcribe(samples, decoderState: &state, language: .english)
    }

    /// Whether the encoder runs on the Neural Engine, from how long it takes over a second of silence, which it pads to
    /// its 15-second window: on the iPhone Duo about 0.1 s there, and 1.5 s on the CPU.
    func onNeuralEngine() async throws -> Bool {
        let began = ContinuousClock.now
        _ = try await hear([Float](repeating: 0, count: ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)))
        return ContinuousClock.now - began < .seconds(0.5)
    }
}

nonisolated extension ASRConfig {
    /// FluidAudio's, re-hearing a pause Parakeet wrote nothing in only once it's 1.5 s or more. From 0.18.2 it re-hears
    /// every pause from 0.5 s and the start before the first word (#1061, #1056, measured on Italian and German oral
    /// history and earnings calls), which in his English dictations heard words in breaths and room sound ("Mm",
    /// "Right.", "mint", "to enjoy") and nothing he'd said; from 1.5 s it still finds what 0.18.0 dropped (Nov 8,
    /// scripts/voiceloop: real 1.87% of words wrong to 1.85%, loud 41.01% to 40.99%, 0.18.0 1.85% and 41.17%).
    public static let dictation = ASRConfig(seamGapRepairMinGapSeconds: 1.5)

    /// `dictation` one window at a time, as Hex's keyboard writes: FluidAudio's four at once hold four windows' work in
    /// memory together, which a keyboard's limit has no room for.
    public static let keyboard = ASRConfig(parallelChunkConcurrency: 1, seamGapRepairMinGapSeconds: 1.5)
}

/// A Parakeet, and Silero's voice-activity model (FluidAudio's `VadManager`), which hears whether anyone talks: what
/// writes a dictation down in the app and in the keyboard alike.
public nonisolated struct Transcriber: Sendable {
    let parakeet: any Parakeet
    let talking: VadManager?

    #if targetEnvironment(simulator)
        /// The simulator has no Neural Engine, so a Parakeet would compile on the Mac's CPU, and its UI tests stand in for
        /// the app's voice (`scripts/voiceapp.py`).
        public static let hasNeuralEngine = false
    #else
        public static let hasNeuralEngine = true
    #endif

    /// Loads Silero's model beside `parakeet`, downloading it once (2 MB) into the App Group's FluidAudio folder, where
    /// the keyboard finds it too; without it, as when that first download can't reach Hugging Face, every recording is
    /// written as Parakeet hears it, until the next load.
    public init(_ parakeet: any Parakeet) async {
        self.parakeet = parakeet
        if let folder = AsrModelVersion.shared {
            talking = try? await VadManager(modelDirectory: folder)
        } else {
            talking = try? await VadManager()
        }
    }

    /// The process a Parakeet loads in: the app's, or a keyboard's, whose memory limit has no room for the encoder's
    /// CPU copy (about 425 MB of weights) or for four windows written at once.
    public enum Process: Sendable { case app, keyboard }

    /// The keyboard's Parakeet wasn't loaded: its encoder ran on the CPU, so it was let go.
    public struct OffNeuralEngine: Error {}

    /// The picked Parakeet from where the app downloaded it, with Silero; it fails until it's downloaded.
    public static func load(_ model: SpeechModel, in process: Process = .app) async throws -> Transcriber {
        guard let version = model.version else { throw CocoaError(.featureUnsupported) }
        return try await load(version, from: version.folder, in: process)
    }

    /// The Parakeet in `folder`, with Silero. iOS sometimes kills its Neural Engine compiler for memory while it compiles
    /// the encoder, and Core ML then runs the encoder on the CPU, ten times slower, until it's loaded again: so the app
    /// loads it again, up to three times, and a keyboard lets it go and throws `OffNeuralEngine`.
    public static func load(_ version: AsrModelVersion, from folder: URL, in process: Process = .app) async throws
        -> Transcriber
    {
        var load = 1
        while true {
            let parakeet = AsrManager(config: process == .keyboard ? .keyboard : .dictation)
            try await parakeet.loadModels(try await AsrModels.load(from: folder, version: version))
            guard hasNeuralEngine, process == .keyboard || load < 3, try await !parakeet.onNeuralEngine() else {
                return await Transcriber(parakeet)
            }
            log.error(
                "\(version.folder.lastPathComponent, privacy: .public)'s encoder ran on the CPU after load \(load)")
            if process == .keyboard {
                await parakeet.cleanup()
                throw OffNeuralEngine()
            }
            load += 1
        }
    }

    /// Whether the app has finished downloading this Parakeet: FluidAudio downloads into its folder file by file, so a
    /// folder there may still be half a download, which loading would finish from Hugging Face.
    public static func isDownloaded(_ model: SpeechModel) -> Bool {
        guard let version = model.version else { return false }
        return AsrModels.modelsExist(at: version.folder, version: version)
    }

    /// The recording leveled (`Recording.leveled`), a tap with next to nothing said padded up to the shortest sound
    /// Parakeet takes, and nothing at all when Silero hears no one talking in it and Parakeet wrote only a stock phrase
    /// it's unsure of. Where no one talks Parakeet writes "Yeah.", "Okay.", "It is" or "Thank you.", four pieces at most
    /// with the first at 0.2 to 0.35, where Silero hears talking under 0.5 (Nov 8: 10 of his taps). Silero also misses
    /// quiet talking in a loud room, and the first piece of a real "Yeah. Yeah." there, six pieces, came to 0.52 on the
    /// Mac and under 0.5 on the Duo, which typed nothing for it. On the Neural Engine a minute of talking is written in
    /// well under a second.
    public func write(_ recording: [Float]) async throws -> String {
        var samples = Recording.leveled(recording)
        let shortest = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if samples.count < shortest { samples += repeatElement(0, count: shortest - samples.count) }
        let heard = try await parakeet.hear(samples)
        if let talking, let pieces = heard.tokenTimings, pieces.count <= 4, let first = pieces.first,
            first.confidence < 0.5, try await talking.process(samples).allSatisfy({ $0.probability < 0.5 })
        {
            return ""
        }
        return heard.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated extension AsrModelVersion {
    /// Where this Parakeet's files live: the App Group's container, whose path outlives an install, where the app's own
    /// container gets a new one with each, and Core ML keys what it compiles by the path a model loads from
    /// (VoiceModels/AGENTS.md). The keyboard reads them there too.
    public var folder: URL {
        Self.clearCompiled
        let own = AsrModels.defaultCacheDirectory(for: self)
        return Self.shared?.appending(path: "Models").appending(path: own.lastPathComponent) ?? own
    }

    /// Core ML's compiles, `<bundle ID>/com.apple.e5rt.e5bundlecache/<OS build>/…` in this process's own caches, emptied
    /// the first time a new install or iOS reaches for a Parakeet, before any is loaded. Each install compiles them again
    /// beside the last's, which nothing else removes: 1.3 GB on the Duo and 15 GB in a simulator by Nov 5.
    private static let clearCompiled: Void = {
        let install = "\(Bundle.main.bundlePath) \(ProcessInfo.processInfo.operatingSystemVersionString)"
        guard UserDefaults.standard.string(forKey: "compiledFor") != install else { return }
        try? FileManager.default.removeItem(
            at: URL.cachesDirectory.appending(
                path: "\(Bundle.main.bundleIdentifier ?? "")/com.apple.e5rt.e5bundlecache"))
        UserDefaults.standard.set(install, forKey: "compiledFor")
    }()

    /// The App Group's FluidAudio folder. The app's own is moved there the first time, a rename.
    static let shared: URL? = {
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
