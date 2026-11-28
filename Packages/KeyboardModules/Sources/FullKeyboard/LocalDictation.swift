import AVFAudio
import Foundation
import KeyboardCore
import KeyboardStore
import OSLog
import UIKit
import VoiceCore
import WebKit

@MainActor
final class LocalDictation {
    var onLevel: (Float, Double) -> Void = { _, _ in }
    var onWritten: (_ text: String, _ plain: String, _ id: UUID) -> Void = { _, _, _ in }
    var onStartFailure: () -> Void = {}
    var onNotice: (String) -> Void = { _ in }
    var onChange: () -> Void = {}

    var isRecording: Bool { Self.state.isRecording(in: id) }
    var hears: Bool { Self.state.hears(in: id) }
    var writing: [Double] { Self.state.writing(in: id) }
    var waiting: String? {
        if case .loading = Self.state.parakeet { return "Model loading…" }
        return nil
    }

    private final class Take {
        let id = UUID()
        let started = Date()
        let app: String?
        let style: DictationWriting
        let sound: URL
        var microphone: String?
        var mic: String?
        var file: Recording.File?
        var converter: AVAudioConverter?
        var frames = 0
        var written: Written?

        var seconds: Double { Double(frames) / Recording.format.sampleRate }

        init(app: String?, style: DictationWriting) {
            self.app = app
            self.style = style
            sound = Self.folder.appending(path: "\(id.uuidString).wav")
        }

        static let folder = URL.temporaryDirectory.appending(path: "dictations")
    }

    private struct Held: Codable {
        var id: UUID
        var text: String
        var plain: String
        var field: String
        var at: Date
    }

    private struct Keyboard {
        weak var dictation: LocalDictation?
    }

    private let host: UIView
    private let id: KeyboardDictation.Keyboard
    private var field: String?

    private static var state = KeyboardDictation()
    private static var keyboards: [KeyboardDictation.Keyboard: Keyboard] = [:]
    private static var count = 0
    private static var takes: [KeyboardDictation.Take: Take] = [:]
    private static var capture: WebCapture?
    private static var transcriber: Task<Transcriber, any Error>?
    private static let heldFile = StoredFile<[Held]>(
        URL.applicationSupportDirectory.appending(path: "dictation-held.json"))
    private static let writingLimit: TimeInterval = 120
    nonisolated private static let audio = DispatchQueue(label: "com.shahidy.iikb.keyboard.audio", qos: .userInitiated)
    nonisolated private static let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

    nonisolated private static func note(_ line: String, failed: Bool = false) {
        if failed { log.error("\(line, privacy: .public)") } else { log.notice("\(line, privacy: .public)") }
        KeyboardVoiceLog.write(line)
    }

    private static var now: Double { Date.now.timeIntervalSinceReferenceDate }

    init(host: UIView) {
        self.host = host
        Self.count += 1
        id = Self.count
        Self.keyboards = Self.keyboards.filter { $0.value.dictation != nil }
        Self.keyboards[id] = Keyboard(dictation: self)
        Self.leaveLeftovers()
    }

    private static func keyboard(_ id: KeyboardDictation.Keyboard) -> LocalDictation? { keyboards[id]?.dictation }

    private static func leaveLeftovers() {
        let files =
            (try? FileManager.default.contentsOfDirectory(at: Take.folder, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
            if let id, takes.values.contains(where: { $0.id == id }) { continue }
            guard let id, let samples = try? Recording.read(file), !samples.isEmpty
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

    private static var canWrite: Bool {
        picked == .apple || Transcriber.isDownloaded(.v3)
    }

    private static var picked: KeyboardDictation.Model {
        SpeechModel.picked == .apple ? .apple : .parakeet
    }

    private static var micAllowed: Bool {
        AVAudioApplication.shared.recordPermission == .granted || Dictation.micAllowed
    }

    private static var canStart: Bool {
        state.canStart(micAllowed: micAllowed, canWrite: canWrite, room: .now)
    }

    func appeared(in field: String?) {
        self.field = field
        Self.state.appeared(id, in: field)
        typeHeld()
    }

    func prepare() {
        Self.run(Self.state.prepare(id, canStart: Self.canStart))
        Self.preload()
    }

    private static let dictatedKey = "dictatedInKeyboard"

    private static func preload() {
        run(
            state.preload(
                picked: picked, downloaded: Transcriber.isDownloaded(.v3),
                dictatedBefore: UserDefaults.standard.bool(forKey: dictatedKey), room: .now))
    }

    private static func load(_ load: Int) {
        let began = Date.now
        note("the keyboard loads Parakeet ahead: \(KeyboardDictation.Room.now.described)")
        let task = Task {
            try await Transcriber.load(SpeechModel.v3, in: .keyboard(neuralMemory: { KeyboardMemory.neural }))
        }
        transcriber = task
        Task {
            do {
                _ = try await task.value
                guard state.finishedLoading(load) else {
                    if transcriber == task { transcriber = nil }
                    return
                }
                note(
                    "Parakeet loaded in the keyboard in \(since(began)): \(KeyboardDictation.Room.now.described)")
            } catch is Transcriber.OffNeuralEngine {
                state.failedLoading(load, onCPU: true)
                if transcriber == task { transcriber = nil }
                note(
                    "Parakeet's encoder ran on the CPU, so the keyboard sets it aside: \(KeyboardDictation.Room.now.described)"
                )
            } catch {
                state.failedLoading(load, onCPU: false)
                if transcriber == task { transcriber = nil }
                note("Parakeet didn't load in the keyboard: \(error.localizedDescription)", failed: true)
            }
        }
    }

    func arm(for app: String?, style: DictationWriting) {
        let effects = Self.state.arm(id, in: field, at: Self.now, canStart: Self.canStart)
        Self.begun(app: app, style: style)
        Self.run(effects)
    }

    func disarm() {
        Self.run(Self.state.disarm(id))
    }

    func start(for app: String?, style: DictationWriting) {
        let effects = Self.state.start(id, in: field, at: Self.now, canStart: Self.canStart)
        Self.begun(app: app, style: style)
        Self.run(effects)
    }

    private static func begun(app: String?, style: DictationWriting) {
        guard let take = state.recording?.take, takes[take] == nil else { return }
        takes[take] = Take(app: app, style: style)
    }

    func stop() {
        Self.run(Self.state.stop(id, at: Self.now))
    }

    func cancel() {
        Self.run(Self.state.cancel(id))
    }

    func keyboardWillHide() {
        Self.run(Self.state.hidden(id))
    }

    func memoryWarning() {
        Self.note("the keyboard is warned of memory: \(KeyboardMemory.available >> 20) MB left")
        Self.run(Self.state.memoryWarning())
    }

    private static func run(_ effects: [KeyboardDictation.Effect]) {
        for effect in effects { run(effect) }
    }

    private static func run(_ effect: KeyboardDictation.Effect) {
        switch effect {
        case .attach(let id):
            let capture = capture ?? WebCapture()
            self.capture = capture
            capture.onReleased = { run(state.released()) }
            if let host = keyboard(id)?.host { capture.attach(to: host) }
            allowHaptics()
        case .detach(let id):
            if let host = keyboard(id)?.host { capture?.detach(from: host) }
        case .readAudio(let take):
            readAudio(take)
        case .startCapture(let take):
            capture?.start(microphone: takes[take]?.microphone)
        case .stopCapture:
            capture?.stop()
        case .watch(let take):
            watch(take)
        case .discard(let take):
            guard let dropped = takes.removeValue(forKey: take) else { return }
            dropped.file?.close()
            try? FileManager.default.removeItem(at: dropped.sound)
        case .write(let take):
            guard let ended = takes[take] else { return }
            ended.file?.close()
            UserDefaults.standard.set(true, forKey: dictatedKey)
            note("the keyboard's capture ended with \(String(format: "%.1f", ended.seconds)) s of sound")
            write(ended, take)
        case .leave(let take, let typed):
            guard let left = takes.removeValue(forKey: take) else { return }
            left.file?.close()
            Dictation.leave(
                Dictation.Made(
                    id: left.id, date: left.started, seconds: left.seconds, typed: typed, written: left.written?.made,
                    app: left.app, mic: left.mic),
                sound: left.sound)
        case .type(let take, let id):
            guard let written = takes[take]?.written, let uuid = takes[take]?.id else { return }
            keyboard(id)?.onWritten(written.made.text, written.plain, uuid)
        case .hold(let take, let field):
            guard let held = takes[take], let written = held.written else { return }
            heldFile.save(
                (heldFile.read().value ?? [])
                    + [Held(id: held.id, text: written.made.text, plain: written.plain, field: field, at: .now)])
        case .notice(let notice, let id):
            keyboard(id)?.onNotice(text(of: notice))
        case .openApp(let id):
            keyboard(id)?.onStartFailure()
        case .letGoOfCapture:
            capture?.tearDown()
            capture = nil
        case .loadParakeet(let number):
            load(number)
        case .letGoOfParakeet:
            transcriber = nil
        case .resumeOthers:
            resumeOthers()
        case .changed(let id):
            keyboard(id)?.onChange()
        }
    }

    private static func text(of notice: KeyboardDictation.Notice) -> String {
        switch notice {
        case .micDidntStart: "The mic didn't start"
        case .notWritten: "Not written: saved to Transcripts for iikb to write"
        case .noSound: "Mic gave no sound"
        case .noWords: "Heard no words"
        case .longest: "Stopped at 90 s"
        }
    }

    private static func readAudio(_ take: KeyboardDictation.Take) {
        let picked = SettingsStore.microphone?.name
        capture?.onEvent = { event in heard(event, in: take) }
        note("the keyboard starts a capture\(state.recording?.kept == false ? " on touch-down" : "")")
        audio.async {
            _ = hapticsAllowed
            let session = AVAudioSession.sharedInstance()
            let othersPlaying = session.isOtherAudioPlaying
            let microphone = picked ?? automaticMicrophone(in: session)
            Task { @MainActor in
                takes[take]?.microphone = microphone
                if picked == nil, microphone != nil { note("the keyboard asks for a wired or USB microphone") }
                run(state.audioRead(take, othersPlaying: othersPlaying))
            }
        }
    }

    private static func watch(_ take: KeyboardDictation.Take) {
        Task {
            while let deadline = state.deadline(take) {
                let wait = deadline - now
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))  // timer: a stalled dictation, or a lost touch-up
                    continue
                }
                if let recording = state.recording {
                    note(
                        !recording.kept
                            ? "the keyboard dropped a touch-down capture no tap kept"
                            : "the keyboard's capture \(recording.interruptedSince == nil ? "went quiet" : "stayed interrupted")",
                        failed: recording.kept)
                }
                run(state.due(take, at: now))
            }
        }
    }

    private static func heard(_ event: WebCapture.Event, in id: KeyboardDictation.Take) {
        guard let take = takes[id], let recording = state.recording, recording.take == id else { return }
        switch event {
        case .started(let rate, let device):
            let kind =
                device.range(of: "iphone|ipad|built-in", options: [.regularExpression, .caseInsensitive]) != nil
                ? "built-in" : "other"
            note(
                "the keyboard hears at \(Int(rate)) Hz from the \(kind) microphone, \(since(take.started)) after the touch"
            )
            take.mic = device
            take.file = Recording.File(take.sound)
            take.converter = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true
            ).flatMap { AVAudioConverter(from: $0, to: Recording.format) }
            guard take.file != nil, take.converter != nil else {
                note("the keyboard's capture couldn't start: no file or converter for the recording", failed: true)
                return run(state.failed(id))
            }
            state.opened(id, at: now)
        case .samples(let data, let level):
            if take.frames == 0 { note("the keyboard's first sound came \(since(take.started)) after the touch") }
            append(data, to: take)
            run(state.sound(id, seconds: take.seconds, level: level, at: now))
            if recording.kept, !recording.stopping { keyboard(recording.keyboard)?.onLevel(level, take.seconds) }
        case .interrupted(let interrupted, let described):
            note("the keyboard's capture \(interrupted ? "is interrupted" : "is back"): \(described)")
            state.interrupted(id, interrupted, at: now)
        case .stopped, .processTerminated:
            run(state.ended(id))
        case .failed(let message):
            if !recording.opened { note("the keyboard's capture couldn't start: \(message)", failed: true) }
            run(state.failed(id))
        }
    }

    private static func append(_ data: Data, to take: Take) {
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

    private func typeHeld() {
        guard let all = Self.heldFile.read().value, !all.isEmpty else { return }
        let next = KeyboardDictation.held(
            all.map { (field: $0.field, at: $0.at.timeIntervalSinceReferenceDate) }, in: field, at: Self.now)
        let kept = next.kept.map { all[$0] }
        if kept.isEmpty { Self.heldFile.remove() } else { Self.heldFile.save(kept) }
        for held in next.here.map({ all[$0] }) { onWritten(held.text, held.plain, held.id) }
        if next.expired { onNotice("Saved to Transcripts") }
    }

    private struct Written: Sendable {
        var made: Dictation.Made.Written
        var plain: String
        var sounded: Bool
    }

    private static func write(_ take: Take, _ id: KeyboardDictation.Take) {
        Task {
            let written = await write(take, within: writingLimit)
            take.written = written
            let outcome: KeyboardDictation.Outcome =
                if let written {
                    !written.made.text.isEmpty ? .words : written.sounded ? .noWords : .silent
                } else {
                    .unwritten
                }
            let owners = Set(state.writing.map(\.keyboard) + [state.shown?.keyboard].compactMap { $0 })
            for gone in owners where keyboard(gone) == nil { run(state.hidden(gone)) }
            run(state.written(id, outcome))
            preload()
        }
    }

    private static func write(_ take: Take, within seconds: TimeInterval) async -> Written? {
        let race = Race()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            Task { race.finish(await write(take)) }
            Task {
                try? await Task.sleep(for: .seconds(seconds))  // timer: a stalled dictation
                if race.finish(nil) {
                    note("the keyboard gave up writing a dictation after \(Int(seconds)) s", failed: true)
                }
            }
        }
    }

    @MainActor private final class Race {
        var continuation: CheckedContinuation<Written?, Never>?

        @discardableResult func finish(_ written: Written?) -> Bool {
            guard let continuation else { return false }
            self.continuation = nil
            continuation.resume(returning: written)
            return true
        }
    }

    private static func write(_ take: Take) async -> Written? {
        let samples: [Float]
        do {
            samples = try Recording.read(take.sound)
        } catch {
            note("the keyboard couldn't read a dictation: \(error.localizedDescription)", failed: true)
            return nil
        }
        let vocabulary = VocabularyFeed.read()
        let written: (heard: String, model: SpeechModel)
        let room = KeyboardDictation.Room.now
        switch state.writer(picked: picked, seconds: take.seconds, room: room) {
        case .apple:
            do {
                written = (
                    try await AppleSpeech.write(samples, vocabulary: vocabulary.terms.map(\.term), installs: false),
                    .apple
                )
            } catch {
                let unavailable = AppleSpeech.transcriberAvailable ? "" : " (SpeechTranscriber isn't available)"
                note(
                    "Apple's model couldn't write in the keyboard: \(error.localizedDescription)\(unavailable)",
                    failed: true)
                return nil
            }
        case .parakeet:
            guard let parakeet = await parakeet(for: take.seconds) else { return nil }
            do {
                written = (try await parakeet.write(samples), .v3)
            } catch {
                note("Parakeet couldn't write in the keyboard: \(error.localizedDescription)", failed: true)
                return nil
            }
        case .app:
            note("Parakeet can't write here, so the keyboard leaves it for the app: \(room.described)")
            return nil
        }
        note("\(written.model.title) wrote \(String(format: "%.1f", take.seconds)) s in the keyboard")
        return Written(
            made: Dictation.Made.Written(
                text: take.style.typed(written.heard, edited: nil, vocabulary: vocabulary), heard: written.heard,
                model: written.model.title),
            plain: DictationWriting.plain(written.heard, vocabulary: vocabulary),
            sounded: KeyboardDictation.sounded(samples, sampleRate: Recording.format.sampleRate))
    }

    private static func parakeet(for seconds: Double) async -> Transcriber? {
        run(state.loadParakeet())
        changed()
        defer { changed() }
        guard let transcriber, let parakeet = try? await transcriber.value else {
            note("Parakeet didn't load, so the keyboard leaves it for the app")
            return nil
        }
        let room = KeyboardDictation.Room.now
        guard room.writes(seconds) else {
            note("Parakeet loaded without room to write, so the keyboard leaves it for the app: \(room.described)")
            return nil
        }
        return parakeet
    }

    private static func changed() {
        for id in Set(state.writing.map(\.keyboard)) { keyboard(id)?.onChange() }
    }

    nonisolated private static let hapticsAllowed: Void = {
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
    }()

    private static func allowHaptics() {
        audio.async { _ = hapticsAllowed }
    }

    private static func since(_ start: Date) -> String { "\(Int(Date.now.timeIntervalSince(start) * 1000)) ms" }

    nonisolated private static func automaticMicrophone(in session: AVAudioSession) -> String? {
        if session.category != .playAndRecord { try? session.setCategory(.playAndRecord, options: [.mixWithOthers]) }
        return automaticMicrophone(of: (session.availableInputs ?? []).map { (port: $0.portType, name: $0.portName) })
    }

    nonisolated static func automaticMicrophone(of inputs: [(port: AVAudioSession.Port, name: String)]) -> String? {
        [AVAudioSession.Port.headsetMic, .usbAudio].lazy.compactMap { port in inputs.first { $0.port == port }?.name }
            .first
    }

    nonisolated private static func resumeOthers() {
        audio.async {
            let session = AVAudioSession.sharedInstance()
            guard !session.isOtherAudioPlaying else { return }
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                note("the keyboard couldn't ask paused audio to play: \(error.localizedDescription)", failed: true)
            }
        }
    }
}

extension KeyboardDictation.Room {
    static var now: Self { Self(limit: KeyboardMemory.limit, available: KeyboardMemory.available) }
}

/// The hidden web view that hears you. It sits in the keyboard at 2 by 2 points, all but invisible, its page
/// asking `getUserMedia` for the microphone: WebKit's media process does the recording, which iOS allows,
/// where the extension itself is refused. The page sends the sound as chunks of 16-bit samples, base64 in a
/// message, each with its loudness; a fake HTTPS origin (`keyboard.iikb.local`, never fetched) is what makes
/// the page a secure context `getUserMedia` will answer in.
@MainActor
private final class WebCapture: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    enum Event {
        case started(sampleRate: Double, device: String)
        case samples(Data, level: Float)
        /// iOS gave the audio session to another sound (a notification, an alarm, a call), or it's back, with what the
        /// page says of its context and track.
        case interrupted(Bool, String)
        case stopped
        case failed(String)
        case processTerminated
    }

    var onEvent: ((Event) -> Void)?
    /// WebKit let the microphone go after a stop.
    var onReleased: () -> Void = {}
    /// Asked to start and not yet stopped.
    private(set) var isCapturing = false
    private let webView: WKWebView
    private var loaded = false
    private var startWhenLoaded = false
    private var microphone: String?
    /// Each start's number, which the page sends back with everything it hears, so what a stopped capture still sends
    /// never reaches the next.
    private var session = 0
    private static let origin = URL(string: "https://keyboard.iikb.local/")

    override init() {
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
        webView.loadHTMLString(Self.page, baseURL: Self.origin)
    }

    func attach(to host: UIView) {
        if webView.superview !== host { host.addSubview(webView) }
    }

    /// Out of `host`, unless another keyboard has it now.
    func detach(from host: UIView) {
        if webView.superview === host { webView.removeFromSuperview() }
    }

    /// Hears from the input WebKit labels `microphone`, else the built-in one.
    func start(microphone: String?) {
        self.microphone = microphone
        isCapturing = true
        guard loaded else {
            startWhenLoaded = true
            return
        }
        session += 1
        let label =
            microphone.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        webView.evaluateJavaScript("startCapture(\(session), \(label))")
    }

    func stop() {
        startWhenLoaded = false
        isCapturing = false
        webView.evaluateJavaScript("stopCapture()")
    }

    /// Stops the page and lets the web view go, for one whose microphone gave no sound or that memory needs.
    func tearDown() {
        onEvent = nil
        stop()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "iikb")
        webView.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        if startWhenLoaded {
            startWhenLoaded = false
            start(microphone: microphone)
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
        isCapturing = false
        webView.loadHTMLString(Self.page, baseURL: Self.origin)
        onEvent?(.processTerminated)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "released" { return onReleased() }
        guard body["session"] as? Int == session else { return }
        switch type {
        case "started":
            onEvent?(
                .started(
                    sampleRate: (body["rate"] as? Double) ?? 48_000,
                    device: (body["device"] as? String) ?? "unknown"))
        case "pcm":
            guard let encoded = body["data"] as? String, let data = Data(base64Encoded: encoded) else { return }
            onEvent?(.samples(data, level: Float((body["level"] as? Double) ?? 0)))
        case "state":
            onEvent?(
                .interrupted(
                    (body["interrupted"] as? Bool) ?? false,
                    "context \((body["context"] as? String) ?? "?"), track \((body["track"] as? String) ?? "?")"))
        case "stopped":
            isCapturing = false
            onEvent?(.stopped)
        case "error":
            isCapturing = false
            onEvent?(.failed((body["message"] as? String) ?? "unknown"))
        default:
            break
        }
    }

    private static let page = """
        <!doctype html><meta charset="utf-8"><script>
        let live = null;
        const post = (m) => webkit.messageHandlers.iikb.postMessage(m);
        const track = (capture) => capture.stream && capture.stream.getAudioTracks()[0];
        function report(capture) {
          const t = track(capture);
          const state = !t || t.readyState === "ended" ? "ended" : t.muted ? "muted" : "live";
          const interrupted = capture.ctx.state !== "running" || state !== "live";
          if (interrupted === capture.interrupted) return;
          capture.interrupted = interrupted;
          post({ type: "state", session: capture.session, interrupted, context: capture.ctx.state, track: state });
        }
        function listen(capture, t) {
          const now = (f) => () => { if (t === track(capture)) f(); };
          t.onmute = now(() => { capture.mutedAt = Date.now(); report(capture); });
          t.onunmute = now(() => report(capture));
          t.onended = now(() => report(capture));
        }
        function heal(capture) {
          if (live !== capture) return;
          report(capture);
          if (capture.ctx.state !== "running") {
            if (capture.ctx.state !== "closed") capture.ctx.resume().catch(() => {});
            return;
          }
          const t = track(capture);
          const ended = !t || t.readyState === "ended";
          if (!ended && !(t.muted && Date.now() - capture.mutedAt >= 3000)) return;
          if (capture.reopening || Date.now() < capture.nextReopen) return;
          reopen(capture);
        }
        async function reopen(capture) {
          capture.reopening = true;
          try {
            const s = await navigator.mediaDevices.getUserMedia(capture.constraints);
            if (live !== capture) return s.getTracks().forEach((t) => t.stop());
            const old = capture.stream;
            try { capture.source.disconnect(); } catch (e) {}
            capture.stream = s;
            capture.source = capture.ctx.createMediaStreamSource(s);
            capture.source.connect(capture.node);
            listen(capture, track(capture));
            capture.mutedAt = Date.now();
            if (!track(capture).muted) capture.backoff = 1000;
            old.getTracks().forEach((t) => t.stop());
            report(capture);
          } catch (e) {
          } finally {
            capture.reopening = false;
            capture.nextReopen = Date.now() + capture.backoff;
            capture.backoff = Math.min(8000, capture.backoff * 2);
          }
        }
        const base = { channelCount: 1, echoCancellation: true };
        async function chosenMicrophone(label) {
          const inputs = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === "audioinput");
          const found = (label && inputs.find((d) => d.label === label)) || inputs.find((d) => /iphone|ipad|built-in/i.test(d.label));
          return found ? found.deviceId : null;
        }
        async function startCapture(session, label) {
          if (live) return;
          const capture = { session };
          live = capture;
          const stale = () => live !== capture;
          const release = () => {
            if (capture.stream) capture.stream.getTracks().forEach((t) => t.stop());
            if (capture.ctx) capture.ctx.close().catch(() => {});
          };
          try {
            let id = await chosenMicrophone(label);
            if (stale()) return;
            capture.stream = await navigator.mediaDevices.getUserMedia({ audio: id ? { ...base, deviceId: { exact: id } } : base });
            if (stale()) return release();
            if (!id) {
              id = await chosenMicrophone(label);
              if (stale()) return release();
              if (id && capture.stream.getAudioTracks()[0].getSettings().deviceId !== id) {
                capture.stream.getTracks().forEach((t) => t.stop());
                capture.stream = await navigator.mediaDevices.getUserMedia({ audio: { ...base, deviceId: { exact: id } } });
                if (stale()) return release();
              }
            }
            capture.ctx = new AudioContext();
            await capture.ctx.resume();
            if (stale()) return release();
            capture.source = capture.ctx.createMediaStreamSource(capture.stream);
            capture.node = capture.ctx.createScriptProcessor(4096, 1, 1);
            capture.node.onaudioprocess = (event) => {
              if (stale() && !capture.flushed) return;
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
              if (capture.flushed) capture.flushed();
            };
            capture.source.connect(capture.node);
            capture.node.connect(capture.ctx.destination);
            Object.assign(capture, { constraints: { audio: id ? { ...base, deviceId: { ideal: id } } : base }, interrupted: false, mutedAt: Date.now(), backoff: 1000, nextReopen: 0 });
            listen(capture, track(capture));
            capture.ctx.onstatechange = () => report(capture);
            capture.heal = setInterval(() => heal(capture), 250);
            post({ type: "started", session, rate: capture.ctx.sampleRate, device: capture.stream.getAudioTracks()[0].label });
          } catch (error) {
            if (stale()) return release();
            live = null;
            release();
            post({ type: "error", session, message: (error && (error.name + ": " + error.message)) || String(error) });
          }
        }
        async function stopCapture() {
          const capture = live;
          if (!capture) return;
          live = null;
          if (capture.heal) clearInterval(capture.heal);
          if (capture.node && capture.ctx && capture.ctx.state === "running") {
            await new Promise((resolve) => {
              const timer = setTimeout(() => capture.flushed && capture.flushed(), 250);
              capture.flushed = () => { clearTimeout(timer); capture.flushed = null; resolve(); };
            });
          }
          try { capture.node && capture.node.disconnect(); capture.source && capture.source.disconnect(); } catch (e) {}
          if (capture.stream) capture.stream.getTracks().forEach((t) => t.stop());
          post({ type: "stopped", session: capture.session });
          if (capture.ctx) { try { await capture.ctx.close(); } catch (e) {} }
          post({ type: "released", session: capture.session });
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
