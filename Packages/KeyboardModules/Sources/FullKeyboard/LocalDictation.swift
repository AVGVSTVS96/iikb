import AVFAudio
import FluidAudio
import Foundation
import KeyboardStore
import OSLog
import UIKit
import WebKit

/// Dictation recorded and written down in the keyboard itself, for a tap on the mic while the app's microphone
/// is off: the app never comes to the front, and nothing is recorded until you tap, or after you tap again to
/// stop. iOS won't record in a keyboard extension (audiomxd turns it away, an extension having no entitlement
/// to record), so a hidden web view in the keyboard captures through `getUserMedia` instead: the recording
/// happens in WebKit's media process, under the microphone permission the app was given, and the sound comes
/// back here as chunks of PCM, kept in a file only until Parakeet has written them down in the keyboard. The app's own dictation (the Parakeets, Clean, Transcripts) is untouched: this is the cold
/// start only, and what it can't do — the app not yet given the microphone, a capture that won't start — falls
/// back to opening the app, as the mic's tap did before. The built-in microphone is always the one heard, as
/// in the app until another is picked in Settings › Microphone, so what's playing keeps playing.
@MainActor
final class LocalDictation {
    enum Phase {
        case idle
        case recording
        case transcribing
    }

    private(set) var phase = Phase.idle
    var isRecording: Bool { phase == .recording }
    var isTranscribing: Bool { phase == .transcribing }
    var isActive: Bool { phase != .idle }
    /// How long the dictation being written down ran, which the bar shows as it shows the app's.
    private(set) var recordedSeconds: Double = 0

    /// Your voice's loudness (a chunk's RMS) and the seconds recorded so far, as the app publishes its own.
    var onLevel: (Float, Double) -> Void = { _, _ in }
    /// What you said, written down: typed as the app's dictations are typed.
    var onTranscript: (String) -> Void = { _ in }
    /// The capture couldn't start, so the tap falls back to opening the app.
    var onStartFailure: () -> Void = {}
    /// A dictation was lost after it started; the words stand until tapped away.
    var onFailure: (String) -> Void = { _ in }
    /// The phase changed, so the mic's face is drawn again.
    var onChange: () -> Void = {}

    private let host: UIView
    private var capture: WebCapture?
    private var sound: SoundFile?
    /// The web view is hearing: its page said so, so a stop from here is a dictation, not a tap that missed.
    private var hearing = false
    private var startedAt = Date()
    private var writing: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

    init(host: UIView) {
        self.host = host
    }

    func start() {
        guard phase == .idle else { return }
        guard AVAudioApplication.shared.recordPermission == .granted else { return onStartFailure() }
        guard LocalParakeet.isReady else { return onStartFailure() }
        phase = .recording
        startedAt = Date()
        recordedSeconds = 0
        hearing = false
        sound = nil
        let capture = capture ?? WebCapture(host: host)
        self.capture = capture
        capture.onEvent = { [weak self] event in self?.heard(event) }
        Self.preferBuiltInMicrophone()
        capture.start()
        onChange()
    }

    /// Stops hearing you and writes down what was said. A tap that lands before the web view is hearing undoes
    /// the tap instead, there being nothing yet to write down.
    func stop() {
        guard phase == .recording else { return }
        guard hearing else { return cancel() }
        capture?.stop()
    }

    /// Throws the dictation away: nothing is typed, and nothing is kept.
    func cancel() {
        let wasActive = phase != .idle
        writing?.cancel()
        writing = nil
        capture?.onEvent = nil
        capture?.detach()
        capture = nil
        if let sound { try? FileManager.default.removeItem(at: sound.url) }
        sound = nil
        hearing = false
        phase = .idle
        Self.releaseAudioSession()
        if wasActive { onChange() }
    }

    private func heard(_ event: WebCapture.Event) {
        switch event {
        case .started(let rate, let device):
            hearing = true
            let kind =
                device.range(of: "iphone|ipad|built-in", options: [.regularExpression, .caseInsensitive]) != nil
                ? "built-in" : "other"
            Self.log.notice("local capture hearing at \(Int(rate)) Hz from the \(kind, privacy: .public) microphone")
            do {
                let url = FileManager.default.temporaryDirectory.appending(
                    path: "local-dictation-\(UUID().uuidString).wav")
                sound = try SoundFile(url: url, sampleRate: rate)
            } catch {
                fail("Dictation couldn't be recorded", detail: Self.describe(error))
            }
        case .samples(let data, let level):
            sound?.append(data)
            recordedSeconds = Date().timeIntervalSince(startedAt)
            onLevel(level, recordedSeconds)
        case .stopped:
            finish()
        case .failed(let message):
            if hearing {
                fail("Dictation stopped before it was written down", detail: message)
            } else {
                startFailed(message)
            }
        case .processTerminated:
            capture?.detach()
            capture = nil
            fail("Dictation stopped before it was written down")
        }
    }

    private func finish() {
        guard phase == .recording, let sound else {
            phase = .idle
            return onChange()
        }
        self.sound = nil
        hearing = false
        Self.releaseAudioSession()
        let url = sound.url
        guard sound.close() > 0 else {
            try? FileManager.default.removeItem(at: url)
            phase = .idle
            return onChange()
        }
        phase = .transcribing
        onChange()
        writing = Task { [weak self] in
            let heard: String?
            do {
                heard = try await LocalParakeet.transcribe(url)
            } catch {
                Self.log.error("local transcription failed: \(Self.describe(error), privacy: .public)")
                try? FileManager.default.removeItem(at: url)
                guard let self, !Task.isCancelled else { return }
                writing = nil
                phase = .idle
                onChange()
                return onFailure(
                    (error as? LocalParakeet.Failure)?.errorDescription ?? "Dictation couldn't be written down")
            }
            try? FileManager.default.removeItem(at: url)
            guard let self, !Task.isCancelled else { return }
            writing = nil
            phase = .idle
            onChange()
            if let heard { onTranscript(heard) }
        }
    }

    /// The capture never began, so nothing was lost: the tap goes on to open the app, which can ask for the
    /// microphone and record there.
    private func startFailed(_ message: String) {
        Self.log.error("local capture couldn't start: \(message, privacy: .public)")
        capture?.onEvent = nil
        sound = nil
        hearing = false
        phase = .idle
        Self.releaseAudioSession()
        onChange()
        onStartFailure()
    }

    /// A dictation was lost after it started: `message` is what the keyboard shows; `detail` (a raw error
    /// from WebKit or the file) goes to the log only, never into the notice you'd read.
    private func fail(_ message: String, detail: String? = nil) {
        Self.log.error("\(message, privacy: .public)")
        if let detail { Self.log.error("\(detail, privacy: .public)") }
        capture?.onEvent = nil
        capture?.stop()
        if let sound { try? FileManager.default.removeItem(at: sound.url) }
        sound = nil
        hearing = false
        phase = .idle
        Self.releaseAudioSession()
        onChange()
        onFailure(message)
    }

    /// The iPhone's own microphone, in `playAndRecord` mixing with other audio, so a car or headphones keep
    /// playing instead of the route dropping into call audio, which pauses them and stalls the start.
    private static func preferBuiltInMicrophone() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord, mode: .measurement,
                options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try session.setPreferredInput(builtIn)
            }
        } catch {
            log.error("built-in microphone preference failed: \(describe(error), privacy: .public)")
        }
    }

    /// Lets what the capture paused (music, navigation) go on.
    private static func releaseAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func describe(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code) \(error.localizedDescription)"
    }
}

/// The dictation's sound as it comes from the page: 16-bit mono PCM written as a WAV, deleted once written down.
@MainActor
private final class SoundFile {
    let url: URL
    private var file: AVAudioFile?
    private let format: AVAudioFormat
    private var frames: AVAudioFramePosition = 0

    init(url: URL, sampleRate: Double) throws {
        self.url = url
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)
        else { throw CocoaError(.featureUnsupported) }
        self.format = format
        // file: the dictation's sound, kept only until it's written down
        file = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
    }

    func append(_ data: Data) {
        let count = data.count / 2
        guard count > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, let target = buffer.int16ChannelData?[0] else { return }
            memcpy(target, base, count * 2)
        }
        try? file?.write(from: buffer)
        frames += AVAudioFramePosition(count)
    }

    /// Closes the file and says how much sound it holds, in frames.
    func close() -> AVAudioFramePosition {
        file = nil
        return frames
    }
}

/// The hidden web view that hears you. It sits in the keyboard at 2 by 2 points, all but invisible, its page
/// asking `getUserMedia` for the microphone: WebKit's media process does the recording, which iOS allows,
/// where the extension itself is refused. The page sends the sound as chunks of 16-bit PCM, base64 in a
/// message, each with its loudness; a fake HTTPS origin (`keyboard.iikb.local`, never fetched) is what makes
/// the page a secure context `getUserMedia` will answer in.
@MainActor
private final class WebCapture: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    enum Event {
        case started(sampleRate: Double, device: String)
        case samples(Data, level: Float)
        case stopped
        case failed(String)
        case processTerminated
    }

    var onEvent: ((Event) -> Void)?
    private let webView: WKWebView
    private var loaded = false
    private var startWhenLoaded = false

    init(host: UIView) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakMessageHandler(self), name: "iikb")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isUserInteractionEnabled = false
        webView.alpha = 0.02
        host.addSubview(webView)
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://keyboard.iikb.local/"))
    }

    func start() {
        guard loaded else {
            startWhenLoaded = true
            return
        }
        webView.evaluateJavaScript("startCapture()")
    }

    func stop() {
        startWhenLoaded = false
        webView.evaluateJavaScript("stopCapture()")
    }

    /// Stops the page and takes the web view out of the keyboard, for a capture being thrown away: a start
    /// still landing in it (its `getUserMedia` unresolved) must not go on hearing with no one listening.
    func detach() {
        stop()
        webView.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        if startWhenLoaded {
            startWhenLoaded = false
            start()
        }
    }

    /// The page's ask for the microphone is the keyboard's own, under the permission the app was given: grant
    /// the microphone, nothing else.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        onEvent?(.processTerminated)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "started":
            onEvent?(
                .started(
                    sampleRate: (body["rate"] as? Double) ?? 48_000,
                    device: (body["device"] as? String) ?? "unknown"))
        case "pcm":
            guard let encoded = body["data"] as? String, let data = Data(base64Encoded: encoded) else { return }
            onEvent?(.samples(data, level: Float((body["level"] as? Double) ?? 0)))
        case "stopped":
            onEvent?(.stopped)
        case "error":
            onEvent?(.failed((body["message"] as? String) ?? "unknown"))
        default:
            break
        }
    }

    private static let page = """
        <!doctype html><meta charset="utf-8"><script>
        let ctx, stream, source, node, running = false;
        const post = (m) => webkit.messageHandlers.iikb.postMessage(m);
        const base = { channelCount: 1, echoCancellation: false, noiseSuppression: false, autoGainControl: false };
        async function builtInMicrophone() {
          const inputs = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === "audioinput");
          const found = inputs.find((d) => /iphone|ipad|built-in/i.test(d.label));
          return found ? found.deviceId : null;
        }
        async function startCapture() {
          if (running) return;
          running = true;
          try {
            let id = await builtInMicrophone();
            stream = await navigator.mediaDevices.getUserMedia({ audio: id ? { ...base, deviceId: { exact: id } } : base });
            if (!id) {
              id = await builtInMicrophone();
              if (id && stream.getAudioTracks()[0].getSettings().deviceId !== id) {
                stream.getTracks().forEach((t) => t.stop());
                stream = await navigator.mediaDevices.getUserMedia({ audio: { ...base, deviceId: { exact: id } } });
              }
            }
            ctx = new AudioContext();
            await ctx.resume();
            source = ctx.createMediaStreamSource(stream);
            node = ctx.createScriptProcessor(4096, 1, 1);
            node.onaudioprocess = (event) => {
              if (!running) return;
              const input = event.inputBuffer.getChannelData(0);
              const pcm = new Int16Array(input.length);
              let sum = 0;
              for (let i = 0; i < input.length; i++) {
                const s = Math.max(-1, Math.min(1, input[i]));
                sum += s * s;
                pcm[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
              }
              const bytes = new Uint8Array(pcm.buffer);
              let binary = "";
              for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
              post({ type: "pcm", data: btoa(binary), level: Math.sqrt(sum / input.length) });
            };
            source.connect(node);
            node.connect(ctx.destination);
            post({ type: "started", rate: ctx.sampleRate, device: stream.getAudioTracks()[0].label });
          } catch (error) {
            running = false;
            post({ type: "error", message: (error && (error.name + ": " + error.message)) || String(error) });
          }
        }
        async function stopCapture() {
          const wasRunning = running;
          running = false;
          try { node && node.disconnect(); source && source.disconnect(); } catch (e) {}
          if (stream) stream.getTracks().forEach((t) => t.stop());
          if (ctx) { try { await ctx.close(); } catch (e) {} }
          ctx = stream = source = node = null;
          if (wasRunning) post({ type: "stopped" });
        }
        </script>
        """
}

/// The page's handler, held weakly: the web view's configuration holds its handlers and the web view is
/// `WebCapture`'s, so a strong hold would keep the two of them alive together for good.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Parakeet writing a dictation down in the keyboard: the same model the app runs, loaded from the App
/// Group's copy of its files, and hearing the recording as the app hears its own — leveled, and padded
/// up to the shortest sound Parakeet takes. The model is loaded once and kept, loading being the slow
/// part. Nothing here downloads: the files arrive with the app's dictations, and until they have, a tap
/// opens the app instead (`isReady`).
private enum LocalParakeet {
    enum Failure: LocalizedError {
        case missing
        case unreadable

        var errorDescription: String? {
            switch self {
            case .missing: "Parakeet v3 isn't downloaded yet. Open iikb and pick it as the Voice Model."
            case .unreadable: "Dictation couldn't be written down: tap the mic again"
            }
        }
    }

    /// Where Parakeet v3's files live: the App Group's FluidAudio folder, as the app keeps them
    /// (VoiceModels' `AsrModelVersion.folder`). v3 is the pick that loads in a moment, so it is the
    /// one a keyboard can hold.
    static var folder: URL {
        let own = AsrModels.defaultCacheDirectory(for: .v3)
        guard let library = AppGroup.library else { return own }
        return library.appending(path: "Application Support/FluidAudio/Models")
            .appending(path: own.lastPathComponent)
    }

    /// The files are on the iPhone, so a tap here can write a dictation down.
    static var isReady: Bool {
        FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
    }

    private static var loaded: AsrManager?

    /// The loaded Parakeet, loading it first if this keyboard hasn't: as the app loads it, again if
    /// its encoder came up on the CPU instead of the Neural Engine, which runs ten times slower.
    private static func manager() async throws -> AsrManager {
        if let loaded { return loaded }
        let manager = AsrManager(config: ASRConfig(seamGapRepairMinGapSeconds: 1.5))
        var loads = 1
        while true {
            try await manager.loadModels(try await AsrModels.load(from: folder, version: .v3))
            guard hasNeuralEngine, loads < 3, try await !manager.onNeuralEngine() else { break }
            loads += 1
        }
        loaded = manager
        return manager
    }

    #if targetEnvironment(simulator)
        /// The simulator has no Neural Engine (VoiceModels' word for it), so a load there is never
        /// checked against one.
        private static let hasNeuralEngine = false
    #else
        private static let hasNeuralEngine = true
    #endif

    /// What was said, or nil when nothing was heard.
    static func transcribe(_ url: URL) async throws -> String? {
        guard isReady else { throw Failure.missing }
        var sound = try samples(url)
        sound = leveled(sound)
        let shortest = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if sound.count < shortest { sound += repeatElement(0, count: shortest - sound.count) }
        let heard = try await manager().hear(sound)
        let text = heard.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The recording as Parakeet hears sound: 16 kHz mono, as floats, converted from the web view's WAV.
    private static func samples(_ url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw Failure.unreadable
        }
        guard
            file.length > 0,
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: file.processingFormat, to: target),
            let input = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
            let output = AVAudioPCMBuffer(
                pcmFormat: target,
                frameCapacity: AVAudioFrameCount(
                    Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1_024)
        else { throw Failure.unreadable }
        do {
            try file.read(into: input)
        } catch {
            throw Failure.unreadable
        }
        var failure: NSError?
        var offered = false
        _ = converter.convert(to: output, error: &failure) { _, status in
            if offered {
                status.pointee = .noDataNow
                return nil
            }
            offered = true
            status.pointee = .haveData
            return input
        }
        guard failure == nil, let channel = output.floatChannelData else { throw Failure.unreadable }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }

    /// The app's leveling of a recording (VoiceCapture's `Recording.leveled`), so a quiet dictation is
    /// heard here as it is there: gain toward the speech's level, never past the peak.
    private static func leveled(_ samples: [Float]) -> [Float] {
        guard let (room, speech) = levels(samples) else { return samples }
        let peak = samples.reduce(0) { max($0, abs($1)) }
        guard speech > 0, peak > 0 else { return samples }
        let gain = min(0.1 / speech, room > 0 ? 0.001_78 / room : .infinity, 0.99 / peak)
        return gain > 1 ? samples.map { $0 * gain } : samples
    }

    /// The room and the speech: the quietest tenth and the loudest twentieth of the recording's 20 ms
    /// stretches, each the root mean square about its mean; nil when it's shorter than one.
    private static func levels(_ samples: [Float]) -> (room: Float, speech: Float)? {
        let frame = 320
        guard samples.count >= frame else { return nil }
        let all = stride(from: 0, to: samples.count - frame + 1, by: frame).map { start in
            let slice = samples[start..<start + frame]
            let mean = slice.reduce(0, +) / Float(frame)
            return (slice.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(frame)).squareRoot()
        }.sorted()
        return (all[all.count / 10], all[all.count * 95 / 100])
    }
}

extension AsrManager {
    /// Heard as the app hears (VoiceModels' `Parakeet`): held to the Latin alphabet, which v3 otherwise
    /// leaves for Cyrillic on short or unclear English.
    fileprivate func hear(_ samples: [Float]) async throws -> ASRResult {
        var state = TdtDecoderState.make(decoderLayers: decoderLayerCount)
        return try await transcribe(samples, decoderState: &state, language: .english)
    }

    /// Whether the encoder runs on the Neural Engine, from how long it takes over a second of silence,
    /// which it pads to its 15-second window: on the iPhone Duo about 0.1 s there, and 1.5 s on the CPU
    /// (VoiceModels' check, the same).
    fileprivate func onNeuralEngine() async throws -> Bool {
        let began = ContinuousClock.now
        _ = try await hear([Float](repeating: 0, count: ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)))
        return ContinuousClock.now - began < .seconds(0.5)
    }
}
