import AVFoundation
import FluidAudio
import OSLog
import Observation
import UIKit
import VoiceCapture
import VoiceCore

nonisolated private let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

/// How far along a model is getting ready: a Parakeet, or Clean's (`CleanModel`).
public enum ModelState: Equatable, Sendable {
    case downloading(Double)
    case loading
    case ready
    case failed(String)
}

/// The speech model voice typing writes with, picked in Settings: one of NVIDIA's Parakeets, run on the Neural Engine by
/// FluidAudio and downloaded from Hugging Face once, or Apple's SpeechTranscriber. It only ever writes finished
/// recordings (`write`), so it never stands between you and the microphone: a dictation made while the picked Parakeet
/// gets ready is recorded as any other and written once it's ready. Either way the sound never leaves the iPhone.
@Observable public final class VoiceModel {
    public static let shared = VoiceModel()

    public private(set) var model = SpeechModel.picked
    public private(set) var state = ModelState.loading { didSet { if state != oldValue { onState?() } } }
    @ObservationIgnored public var onState: (() -> Void)?
    @ObservationIgnored private var parakeet: Task<Transcriber, any Error>?
    @ObservationIgnored private var writes = 0
    /// Whether iikb has its microphone on, which gets the Parakeet and Clean's model ready and keeps them for the next
    /// dictation.
    @ObservationIgnored public var micIsOn = false {
        didSet {
            CleanModel.shared.micIsOn = micIsOn
            if micIsOn { prepare() } else { letGoIfIdle() }
        }
    }

    private init() {}

    /// Lets go of the model in use, so only one is ever in memory, and gets the new one ready.
    public func pick(_ model: SpeechModel) {
        guard model != self.model else { return }
        SpeechModel.picked = model
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
    /// (once you're back in your app with the microphone off) and the compile with it.
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

extension SpeechModel {
    /// Loads the Parakeet, downloading it first if it isn't on the iPhone yet; nil for Apple's.
    fileprivate var loader: (@Sendable (@escaping ProgressHandler) async throws -> Transcriber)? {
        guard let version else { return nil }
        return { progress in
            try await Transcriber.load(
                version,
                from: try await AsrModels.download(to: version.folder, version: version, progressHandler: progress))
        }
    }
}
