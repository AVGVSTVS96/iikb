import Foundation
import KeyboardStore
import OSLog
import Observation
import VoiceEditor

nonisolated private let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

/// The language model Clean edits with (`Weights.shipped`, run by `Editor`): its download, when it's in memory, and
/// what Settings shows of it. Nothing is downloaded or loaded unless Clean is picked.
///
/// A dictation never waits for the download: until the weights are on the iPhone, or when they fail, `edit` answers
/// nil at once and Clean types as it does without a model. It follows real events only: Clean picked, the app
/// started, the microphone turned on or off, a dictation to edit. A failed download goes on at the next of those, or
/// on Try Again.
@Observable public final class CleanModel {
    public static let shared = CleanModel()
    /// The weights' name, as a transcript shows it after the voice model's.
    public static let name = Weights.shipped.name

    /// Nil while Clean isn't picked, and `ready` once the weights are on the iPhone, in memory or not: they load in
    /// half a second, which is never shown.
    public private(set) var state: ModelState?

    /// Named by their checksum, so the file being there is the whole record that it came and was checked, since
    /// `Download` only puts a checked file in place. Any other file beside it is an older build's weights.
    private static let folder = URL.applicationSupportDirectory.appending(path: "Clean", directoryHint: .isDirectory)
    private static let file = folder.appending(path: "\(Weights.shipped.sha256).gguf")

    @ObservationIgnored private var download: Task<Void, Never>?
    @ObservationIgnored private var resumeData: Data?
    @ObservationIgnored private var editor: Task<Editor, any Error>?
    @ObservationIgnored private var edits = 0
    /// Set with `VoiceModel.micIsOn`, so the weights are in memory while the Parakeet is, ready for the next dictation.
    @ObservationIgnored var micIsOn = false { didSet { if micIsOn { prepare() } else { letGoIfIdle() } } }

    private init() {}

    /// Brings the model to where the settings and the microphone want it: nothing while Clean isn't picked, the
    /// download while the weights aren't here, and in memory while the microphone is on or a dictation is being
    /// edited. Safe to call on any event, any number of times.
    public func prepare() {
        guard SettingsStore.load().dictationEditing.asksModel else {
            state = nil
            editor = nil
            return
        }
        guard FileManager.default.fileExists(atPath: Self.file.path(percentEncoded: false)) else { return fetch() }
        state = .ready
        guard editor == nil, micIsOn || edits > 0 else { return }
        editor = Task { try await Editor(.shipped, at: Self.file) }
    }

    /// The model's reply to what was `heard`, for `DictationWriting.written(_:edited:)` to check and type. Nil when
    /// Clean isn't picked, the weights aren't here, or the model failed or ran on. It waits for nothing but the half
    /// second of loading, and logs a dictation's length, never its words.
    public func edit(_ heard: String) async -> String? {
        edits += 1
        defer {
            edits -= 1
            letGoIfIdle()
        }
        prepare()
        guard let editor else { return nil }
        let began = ContinuousClock.now
        do {
            let edited = try await editor.value.edit(heard)
            let took = (ContinuousClock.now - began) / .milliseconds(1)
            log.notice("Clean edited \(heard.count) characters in \(took, format: .fixed(precision: 0)) ms")
            return edited
        } catch Editor.Failure.unreadable {
            if self.editor == editor { self.editor = nil }
            state = .failed("Its file couldn’t be loaded.")
            log.error("Clean's weights couldn't be loaded")
        } catch {
            let why = String(describing: error)
            log.error("Clean gave no reply to \(heard.count) characters: \(why, privacy: .public)")
        }
        return nil
    }

    /// Downloads the weights unless that's under way, going on from where the last download broke off, then removes
    /// any older weights.
    private func fetch() {
        guard download == nil else { return }
        state = .downloading(0)
        let weights = Weights.shipped
        download = Task {
            defer { download = nil }
            do throws(Download.Failure) {
                try await Download(url: weights.url, size: weights.bytes, sha256: weights.sha256).fetch(
                    to: Self.file, resumingFrom: resumeData
                ) { done in
                    Task { @MainActor in
                        if case .downloading = self.state { self.state = .downloading(done) }
                    }
                }
            } catch {
                resumeData = error.resumeData
                state = .failed(error.reason)
                log.error("Clean's weights didn't download: \(error.reason, privacy: .public)")
                return
            }
            resumeData = nil
            let kept = Self.file.lastPathComponent
            for old in (try? FileManager.default.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false)))
                ?? [] where old != kept
            {
                try? FileManager.default.removeItem(at: Self.folder.appending(path: old))
            }
            prepare()
        }
    }

    /// Lets the weights go while nothing needs them: they map back in from the file in half a second.
    private func letGoIfIdle() {
        guard !micIsOn, edits == 0 else { return }
        editor = nil
    }
}
