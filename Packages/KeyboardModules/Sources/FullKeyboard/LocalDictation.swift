import AVFAudio
import Foundation
import KeyboardCore
import KeyboardStore
import OSLog
import UIKit
import VoiceCore
import WebKit

/// Dictation in the keyboard itself, for a tap on the mic while the app's microphone is off, so the app never comes to
/// the front. iOS won't record in a keyboard extension (audiomxd turns it away, an extension having no entitlement to
/// record), so a hidden web view captures through `getUserMedia` instead, as Hex's keyboard does: the recording happens
/// in WebKit's media process, under the microphone permission the app was given, and comes back here as chunks of PCM,
/// kept as a `Recording` as it's heard. Once you stop, the picked model writes it down here (VoiceCore's `Transcriber`,
/// or Apple's; Ultra, which takes minutes to load, writes as v3), in the Writing Style picked for the app, with your
/// Vocabulary (`VocabularyFeed`). Clean's language model needs more memory than a keyboard gets, so Clean uses its
/// rules. Every dictation, written or not, is left with its sound for the app to keep in Transcripts (`Dictation.Made`).
/// The built-in microphone is always the one heard, so what's playing keeps playing.
@MainActor
final class LocalDictation {
    /// Your voice's loudness and the seconds recorded so far, as the app publishes its own.
    var onLevel: (Float, Double) -> Void = { _, _ in }
    /// A dictation written down, to type: as your style has it, as the model wrote it, and its transcript's id.
    var onWritten: (_ text: String, _ plain: String, _ id: UUID) -> Void = { _, _, _ in }
    /// The keyboard can't hear or write this tap (no microphone permission yet, the model not on the iPhone, a capture
    /// that won't start), so it opens the app instead.
    var onStartFailure: () -> Void = {}
    /// Something to tell you about a dictation.
    var onNotice: (String) -> Void = { _ in }
    /// What the mic shows changed.
    var onChange: () -> Void = {}

    var isRecording: Bool { take != nil }
    /// How long each dictation still being written down is, in seconds, oldest first.
    var writing: [Double] { pending.map(\.seconds) }
    /// What those wait for while Parakeet loads, in a few words; nil once it's loaded.
    private(set) var waiting: String?

    private final class Take {
        let id = UUID()
        let started = Date()
        let app: String?
        let style: DictationWriting
        let sound: URL
        var mic: String?
        var file: Recording.File?
        var converter: AVAudioConverter?
        var frames = 0
        var typed = true
        var left = false

        var seconds: Double { Double(frames) / Recording.format.sampleRate }

        init(app: String?, style: DictationWriting) {
            self.app = app
            self.style = style
            sound = Self.folder.appending(path: "\(id.uuidString).wav")
            Self.live.insert(id)
        }

        /// Where the keyboard keeps a dictation's sound until the app has it.
        static let folder = URL.temporaryDirectory.appending(path: "dictations")
        /// The takes this keyboard is recording or writing, whose sounds aren't left behind.
        static var live: Set<UUID> = []
    }

    private let host: UIView
    private var capture: WebCapture?
    private var take: Take?
    private var pending: [Take] = []
    private var tail: Task<Void, Never>?
    private static var transcriber: Task<Transcriber, any Error>?
    private static var transcriberLoaded = false
    private static let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

    init(host: UIView) {
        self.host = host
        Self.leaveLeftovers()
    }

    /// Hands the app what a keyboard iOS ended mid-dictation left, as not typed, for it to write down: the sound is
    /// written as it's heard, so it's all there up to the end.
    private static func leaveLeftovers() {
        let files =
            (try? FileManager.default.contentsOfDirectory(at: Take.folder, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !Take.live.contains(id),
                let samples = try? Recording.read(file), !samples.isEmpty
            else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            let date = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
            Dictation.leave(
                Dictation.Made(
                    id: id, date: date, seconds: Double(samples.count) / Recording.format.sampleRate, typed: false,
                    written: nil, app: nil, mic: nil),
                sound: file)
        }
    }

    /// The picked model can write here: Apple's, or a Parakeet once the app has downloaded v3.
    private static var canWrite: Bool {
        SpeechModel.picked == .apple
            || SpeechModel.v3.folder.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
                == true
    }

    func start(for app: String?, style: DictationWriting) {
        guard take == nil else { return }
        guard AVAudioApplication.shared.recordPermission == .granted, Self.canWrite else { return onStartFailure() }
        let take = Take(app: app, style: style)
        self.take = take
        let capture = capture ?? WebCapture(host: host)
        self.capture = capture
        capture.onEvent = { [weak self] event in self?.heard(event, in: take) }
        Self.preferBuiltInMicrophone()
        capture.start()
        onChange()
    }

    /// Stops hearing you and has what was said written down and typed. A tap before the web view hears anything
    /// undoes the tap, there being nothing to write down.
    func stop() {
        guard let take else { return }
        guard take.file != nil else { return drop(take) }
        capture?.stop()
    }

    /// The bar's cancel: types nothing of the dictation being recorded, which the app keeps in Transcripts.
    func cancel() {
        guard let take else { return }
        take.typed = false
        end(take)
    }

    /// The keyboard went away: types nothing of the dictation being recorded or any still being written, and leaves
    /// them for the app now, since iOS may end the keyboard before they're written.
    func cancelAll() {
        let kept = take != nil || !pending.isEmpty
        cancel()
        for take in pending {
            take.typed = false
            leave(take, nil)
        }
        pending = []
        if kept { onNotice("Not typed here: it’s in iikb › Transcripts") }
        onChange()
    }

    private func heard(_ event: WebCapture.Event, in take: Take) {
        guard take === self.take else { return }
        switch event {
        case .started(let rate, let device):
            let kind =
                device.range(of: "iphone|ipad|built-in", options: [.regularExpression, .caseInsensitive]) != nil
                ? "built-in" : "other"
            Self.log.notice("the keyboard hears at \(Int(rate)) Hz from the \(kind, privacy: .public) microphone")
            take.mic = device
            take.file = Recording.File(take.sound)
            take.converter = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true
            ).flatMap { AVAudioConverter(from: $0, to: Recording.format) }
            if take.file == nil || take.converter == nil { startFailed("the recording's file or converter") }
        case .samples(let data, let level):
            append(data, to: take)
            onLevel(level, take.seconds)
        case .stopped:
            end(take)
        case .processTerminated:
            end(take)
        case .failed(let message):
            if take.file == nil { startFailed(message) } else { end(take) }
        }
    }

    private func append(_ data: Data, to take: Take) {
        guard let converter = take.converter, let file = take.file,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(data.count / 2))
        else { return }
        buffer.frameLength = buffer.frameCapacity
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, let target = buffer.int16ChannelData?[0] else { return }
            memcpy(target, base, Int(buffer.frameLength) * 2)
        }
        guard let converted = Recording.convert(buffer, with: converter),
            let channel = converted.floatChannelData?[0]
        else { return }
        file.append(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        take.frames += Int(converted.frameLength)
    }

    /// The recording is over: what was heard is written down and typed, in the order said, unless it was canceled,
    /// which the app writes down instead.
    private func end(_ take: Take) {
        self.take = nil
        capture?.onEvent = nil
        capture?.stop()
        Self.releaseAudioSession()
        take.file?.close()
        guard take.frames > 0 else { return drop(take) }
        guard take.typed else {
            leave(take, nil)
            return onChange()
        }
        pending.append(take)
        onChange()
        let before = tail
        tail = Task { [weak self] in
            let written = await self?.write(take)
            await before?.value
            self?.deliver(take, written)
        }
    }

    private func deliver(_ take: Take, _ written: Written?) {
        guard !take.left else { return }
        pending.removeAll { $0 === take }
        leave(take, written?.made)
        if let written {
            if !written.sounded {
                onNotice("The microphone gave no sound: tap the mic again")
            } else if written.made.text.isEmpty {
                onNotice("Nothing heard: the recording is in iikb › Transcripts")
            } else {
                onWritten(written.made.text, written.plain, take.id)
            }
        } else {
            onNotice("Couldn’t write it down here: it’ll be in iikb › Transcripts")
        }
        onChange()
    }

    private struct Written {
        var made: Dictation.Made.Written
        /// As the voice model wrote it, with your vocabulary and no style or lists.
        var plain: String
        /// Some sample was past 100/32767, as the app checks its own recordings: none means the microphone was deaf.
        var sounded: Bool
    }

    private func write(_ take: Take) async -> Written? {
        do {
            let samples = try Recording.read(take.sound)
            let model = SpeechModel.picked == .apple ? SpeechModel.apple : .v3
            let heard =
                model == .apple ? try await AppleSpeech.write(samples) : try await loaded().write(samples)
            let vocabulary = VocabularyFeed.read()
            return Written(
                made: Dictation.Made.Written(
                    text: take.style.typed(heard, edited: nil, vocabulary: vocabulary), heard: heard,
                    model: model.title),
                plain: DictationWriting.plain(heard, vocabulary: vocabulary),
                sounded: take.seconds < 1 || samples.contains { abs($0) > 100 / 32767 })
        } catch {
            Self.log.error(
                "the keyboard couldn't write a dictation down: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Parakeet v3, loaded once for as long as the keyboard runs: its first load after an install of a new build
    /// compiles it for the Neural Engine, here as in the app.
    private func loaded() async throws -> Transcriber {
        let loading =
            Self.transcriber
            ?? Task { try await Transcriber.load(SpeechModel.v3) }
        Self.transcriber = loading
        if !Self.transcriberLoaded {
            waiting = "Model loading…"
            onChange()
        }
        defer {
            if waiting != nil {
                waiting = nil
                onChange()
            }
        }
        do {
            let transcriber = try await loading.value
            Self.transcriberLoaded = true
            return transcriber
        } catch {
            Self.transcriber = nil
            throw error
        }
    }

    /// Hands a dictation to the app, once, with its sound: written, or for the app to write.
    private func leave(_ take: Take, _ written: Dictation.Made.Written?) {
        guard !take.left else { return }
        take.left = true
        Take.live.remove(take.id)
        Dictation.leave(
            Dictation.Made(
                id: take.id, date: take.started, seconds: take.seconds, typed: take.typed && written != nil,
                written: written, app: take.app, mic: take.mic),
            sound: take.sound)
    }

    /// Nothing was heard: there's nothing to keep, and the web view goes, so a start still landing in it doesn't go on
    /// hearing.
    private func drop(_ take: Take) {
        if self.take === take { self.take = nil }
        capture?.onEvent = nil
        capture?.detach()
        capture = nil
        Self.releaseAudioSession()
        take.file?.close()
        Take.live.remove(take.id)
        try? FileManager.default.removeItem(at: take.sound)
        onChange()
    }

    /// The capture never began, so nothing was lost: the tap goes on to open the app.
    private func startFailed(_ message: String) {
        Self.log.error("the keyboard's capture couldn't start: \(message, privacy: .public)")
        if let take { drop(take) }
        onStartFailure()
    }

    /// The iPhone's own microphone, in `playAndRecord` mixing with other audio, so a car or headphones keep playing
    /// instead of the route dropping into call audio, which pauses them and stalls the start.
    private static func preferBuiltInMicrophone() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord, mode: .measurement, options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try session.setPreferredInput(builtIn)
            }
        } catch {
            log.error("the built-in microphone couldn't be picked: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Lets what the capture paused (music, navigation) go on.
    private static func releaseAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
    /// Each start's number, which the page sends back with everything it hears, so what a stopped capture still sends
    /// never reaches the next.
    private var session = 0

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
        session += 1
        webView.evaluateJavaScript("startCapture(\(session))")
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

    /// WebKit ended the page's process: the page loads again for the next start.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://keyboard.iikb.local/"))
        onEvent?(.processTerminated)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String,
            body["session"] as? Int == session
        else { return }
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
        let live = null;
        const post = (m) => webkit.messageHandlers.iikb.postMessage(m);
        const base = { channelCount: 1, echoCancellation: false, noiseSuppression: false, autoGainControl: false };
        async function builtInMicrophone() {
          const inputs = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === "audioinput");
          const found = inputs.find((d) => /iphone|ipad|built-in/i.test(d.label));
          return found ? found.deviceId : null;
        }
        async function startCapture(session) {
          if (live) return;
          const capture = { session, running: true };
          live = capture;
          try {
            let id = await builtInMicrophone();
            capture.stream = await navigator.mediaDevices.getUserMedia({ audio: id ? { ...base, deviceId: { exact: id } } : base });
            if (!id) {
              id = await builtInMicrophone();
              if (id && capture.stream.getAudioTracks()[0].getSettings().deviceId !== id) {
                capture.stream.getTracks().forEach((t) => t.stop());
                capture.stream = await navigator.mediaDevices.getUserMedia({ audio: { ...base, deviceId: { exact: id } } });
              }
            }
            if (!capture.running) return capture.stream.getTracks().forEach((t) => t.stop());
            capture.ctx = new AudioContext();
            await capture.ctx.resume();
            capture.source = capture.ctx.createMediaStreamSource(capture.stream);
            capture.node = capture.ctx.createScriptProcessor(4096, 1, 1);
            capture.node.onaudioprocess = (event) => {
              if (!capture.running) return;
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
              post({ type: "pcm", session, data: btoa(binary), level: Math.sqrt(sum / input.length) });
            };
            capture.source.connect(capture.node);
            capture.node.connect(capture.ctx.destination);
            post({ type: "started", session, rate: capture.ctx.sampleRate, device: capture.stream.getAudioTracks()[0].label });
          } catch (error) {
            if (live === capture) live = null;
            post({ type: "error", session, message: (error && (error.name + ": " + error.message)) || String(error) });
          }
        }
        async function stopCapture() {
          const capture = live;
          if (!capture) return;
          live = null;
          capture.running = false;
          try { capture.node && capture.node.disconnect(); capture.source && capture.source.disconnect(); } catch (e) {}
          if (capture.stream) capture.stream.getTracks().forEach((t) => t.stop());
          post({ type: "stopped", session: capture.session });
          if (capture.ctx) { try { await capture.ctx.close(); } catch (e) {} }
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
