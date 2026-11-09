import AVFoundation
import FluidAudio
import OSLog
import Observation
import Speech
import UIKit
import VoiceCapture

nonisolated private let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

/// The speech model voice typing writes with, picked in Settings: one of NVIDIA's Parakeets, run on the Neural Engine by
/// FluidAudio and downloaded from Hugging Face once, or Apple's SpeechTranscriber. It only ever writes finished
/// recordings (`write`), so it never stands between you and the microphone: a dictation made while the picked Parakeet
/// gets ready is recorded as any other and written once it's ready. Either way the sound never leaves the iPhone.
@Observable public final class VoiceModel {
    public static let shared = VoiceModel()

    public nonisolated enum Model: String, CaseIterable, Sendable {
        case ultra, v3, apple

        public var title: String {
            switch self {
            case .ultra: "Parakeet Ultra"
            case .v3: "Parakeet v3"
            case .apple: "Apple"
            }
        }

        public var detail: String {
            switch self {
            case .v3: "Fast and accurate. Downloads once, about 500 MB."
            case .ultra: "A little more accurate. Takes minutes to get ready, and runs warm, each time iikb opens."
            case .apple: "Built into iOS."
            }
        }

        /// Loads in a moment once this install has compiled it, so iikb lets go of it between dictations; Ultra's
        /// encoder never caches, so iikb keeps it.
        var reloadsQuickly: Bool { self == .v3 }

        var version: AsrModelVersion? {
            switch self {
            case .ultra: .ultra
            case .v3: .v3
            case .apple: nil
            }
        }

        /// Loads the Parakeet, downloading it first if it isn't on the iPhone yet; nil for Apple's. iOS sometimes kills its
        /// Neural Engine compiler for memory while it compiles the encoder, and Core ML then runs the
        /// encoder on the CPU, ten times slower, until it's loaded again: so it's loaded again, up to three times.
        var loader: (@Sendable (@escaping ProgressHandler) async throws -> Dictation)? {
            guard let version else { return nil }
            let title = title
            return { progress in
                let folder = try await AsrModels.download(
                    to: version.folder, version: version, progressHandler: progress)
                var load = 1
                while true {
                    let parakeet = AsrManager(config: .dictation)
                    try await parakeet.loadModels(try await AsrModels.load(from: folder, version: version))
                    guard VoiceModel.hasNeuralEngine, load < 3, try await !parakeet.onNeuralEngine() else {
                        return await Dictation(parakeet)
                    }
                    log.error("\(title, privacy: .public)'s encoder ran on the CPU after load \(load)")
                    load += 1
                }
            }
        }
    }

    public enum State: Equatable {
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    private static let modelKey = "voiceModel"

    public private(set) var model = UserDefaults.standard.string(forKey: modelKey).flatMap(Model.init) ?? .v3
    public private(set) var state = State.loading { didSet { if state != oldValue { onState?() } } }
    @ObservationIgnored public var onState: (() -> Void)?
    @ObservationIgnored private var parakeet: Task<Dictation, any Error>?
    @ObservationIgnored private var writes = 0
    /// Whether iikb has its microphone on, which gets the Parakeet ready and keeps it for the next dictation.
    @ObservationIgnored public var micIsOn = false { didSet { if micIsOn { prepare() } else { letGoIfIdle() } } }

    #if targetEnvironment(simulator)
        /// The simulator has no Neural Engine, so a Parakeet would compile on the Mac's CPU, and its UI tests stand in for
        /// the app's voice (`scripts/voiceapp.py`).
        public nonisolated static let hasNeuralEngine = false
    #else
        public nonisolated static let hasNeuralEngine = true
    #endif

    private init() {}

    /// Lets go of the model in use, so only one is ever in memory, and gets the new one ready.
    public func pick(_ model: Model) {
        guard model != self.model else { return }
        UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey)
        self.model = model
        parakeet?.cancel()
        parakeet = nil
        prepare()
    }

    /// The picked model and how far along it is, in a few words.
    public var status: String {
        switch state {
        case .downloading(let done):
            "\(model.title), downloading \(done.formatted(.percent.precision(.fractionLength(0))))"
        case .loading: "\(model.title), getting ready"
        case .ready: "\(model.title), ready"
        case .failed: "\(model.title) couldn’t load"
        }
    }

    /// What dictations wait for while the model gets ready, in a few words for the keyboard's bar; nil once it's ready.
    public var waiting: String? {
        switch state {
        case .downloading(let done): "Model downloading, \(done.formatted(.percent.precision(.fractionLength(0))))"
        case .loading: "Model loading…"
        case .ready: nil
        case .failed: "Model couldn’t load"
        }
    }

    /// Downloads the picked Parakeet if it isn't on the iPhone yet, then loads it, unless it's loaded or on its way; one
    /// that failed is tried again. Its first load after an install of a new build or an iOS update compiles it for the
    /// Neural Engine; later ones read that from a cache. It asks iOS for time in the background to finish, since iOS suspends iikb there within seconds
    /// (after `scripts/phone` starts it, or once you're back in your app with the microphone off) and the compile with it.
    public func prepare() {
        guard let load = model.loader else {
            state = .ready
            return
        }
        guard parakeet == nil else { return }
        state = .loading
        let model = model
        let began = Date.now
        let parakeet = Task.detached {
            try await load { progress in
                Task { @MainActor in
                    guard VoiceModel.shared.model == model else { return }
                    if case .downloading = progress.phase {
                        VoiceModel.shared.state = .downloading(progress.fractionCompleted)
                    } else {
                        VoiceModel.shared.state = .loading
                    }
                }
            }
        }
        self.parakeet = parakeet
        nonisolated(unsafe) var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(background) }
        Task {
            defer { UIApplication.shared.endBackgroundTask(background) }
            do {
                _ = try await parakeet.value
                guard self.parakeet == parakeet else { return }
                state = .ready
                log.notice(
                    "\(model.title, privacy: .public) ready after \(Date.now.timeIntervalSince(began), format: .fixed(precision: 1))s, \(VoiceModel.written, format: .fixed(precision: 1)) MB written since iikb started"
                )
                letGoIfIdle()
            } catch {
                guard self.parakeet == parakeet else { return }
                self.parakeet = nil
                state = .failed(error.localizedDescription)
                log.error(
                    "\(model.title, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A finished recording written down by the picked model, once it's ready, with the model's name. Picking another
    /// model while it waits has that one write it.
    public func write(_ recording: [Float]) async throws -> (heard: String, model: String) {
        writes += 1
        defer {
            writes -= 1
            letGoIfIdle()
        }
        while true {
            prepare()
            let model = model
            do {
                if let parakeet {
                    return (try await parakeet.value.write(recording), model.title)
                }
                return (try await AppleSpeech.write(recording), model.title)
            } catch {
                guard self.model != model else { throw error }
            }
        }
    }
}

extension VoiceModel {
    /// The megabytes iikb has written to storage since it started, as iOS counts them against its disk-writes limit.
    public nonisolated static var written: Double {
        var usage = rusage_info_v4()
        return rusage(getpid(), RUSAGE_INFO_V4, &usage) == 0 ? Double(usage.ri_logical_writes) / 1_000_000 : 0
    }

    #if APP_STORE
        nonisolated private static func rusage(_ pid: pid_t, _ flavor: Int32, _ usage: UnsafeMutableRawPointer) -> Int32
        { -1 }
    #else
        /// libproc's `proc_pid_rusage`, in iOS's libSystem but not its SDK's headers.
        @_silgen_name("proc_pid_rusage")
        nonisolated private static func rusage(_ pid: pid_t, _ flavor: Int32, _ usage: UnsafeMutableRawPointer) -> Int32
    #endif
}

extension VoiceModel {
    /// Lets go of a Parakeet that loads again in a moment while nothing needs it: the microphone is off and nothing is
    /// being written, so it isn't held in memory between dictations.
    private func letGoIfIdle() {
        guard !micIsOn, writes == 0, model.reloadsQuickly, state == .ready, parakeet != nil else { return }
        parakeet = nil
    }
}

extension AsrManager {
    /// Whether the encoder runs on the Neural Engine, from how long it takes over a second of silence, which it pads to
    /// its 15-second window: on the iPhone Duo about 0.1 s there, and 1.5 s on the CPU.
    func onNeuralEngine() async throws -> Bool {
        let began = ContinuousClock.now
        _ = try await hear([Float](repeating: 0, count: ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)))
        return ContinuousClock.now - began < .seconds(0.5)
    }
}

/// Apple's SpeechTranscriber (the iOS 26 model, not the older one behind the system's dictation key), else the dictation
/// model with punctuation.
nonisolated enum AppleSpeech {
    static func write(_ recording: [Float]) async throws -> String {
        let (module, heard) = try await transcriber()
        defer { heard.cancel() }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw Unsupported()
        }
        guard let sound = Recording.converted(recording, to: format) else { throw Unconvertible() }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.start(inputSequence: stream)
        input.yield(AnalyzerInput(buffer: sound))
        input.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await heard.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func transcriber() async throws -> (any SpeechModule, Task<String, any Error>) {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            let module = SpeechTranscriber(locale: locale, preset: .transcription)
            return (
                module,
                Task {
                    var text = ""
                    for try await result in module.results where result.isFinal {
                        text += String(result.text.characters)
                    }
                    return text
                }
            )
        }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else {
            throw Unsupported()
        }
        let module = DictationTranscriber(
            locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [],
            attributeOptions: [])
        return (
            module,
            Task {
                var text = ""
                for try await result in module.results where result.isFinal { text += String(result.text.characters) }
                return text
            }
        )
    }

    private struct Unsupported: LocalizedError {
        var errorDescription: String? { "Voice typing doesn't support your language yet." }
    }

    private struct Unconvertible: LocalizedError {
        var errorDescription: String? { "This recording can't be read by Apple's model." }
    }
}
