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
/// kept as a `Recording` as it's heard. The web view is one for the keyboard's process, its page loaded as the keyboard
/// shows (`prepare`), and hearing starts as a finger lands on the mic (`arm`), so the first word isn't lost waiting for
/// WebKit. Once you stop, the picked model writes it down here (VoiceCore's `Transcriber`, or Apple's; Ultra, which takes
/// minutes to load, writes as v3), in the Writing Style picked for the app, with your Vocabulary (`VocabularyFeed`).
/// Clean's language model needs more memory than a keyboard gets, so Clean uses its rules. Every dictation, written or
/// not, is left with its sound for the app to keep in Transcripts (`Dictation.Made`).
/// WebKit records in its own process in call mode, whatever the keyboard's audio session says, so the page asks for
/// echo cancellation: Apple's voice processing, which hears through several microphones, cuts the room's noise and sets
/// the level, where without it one unaimed microphone heard the voice 20 dB lower and barely over a loud room. Call mode
/// pauses what's playing, and WebKit never says it may play again, so the keyboard does (`resumeOthers`). The microphone
/// picked in Settings › Microphone is the one asked for, else the built-in one.
@MainActor
final class LocalDictation {
    /// Your voice's loudness and the seconds recorded so far, as the app publishes its own.
    var onLevel: (Float, Double) -> Void = { _, _ in }
    /// A dictation written down, to type: as your style has it, as the model wrote it, and its transcript's id.
    var onWritten: (_ text: String, _ plain: String, _ id: UUID) -> Void = { _, _, _ in }
    /// The keyboard can't hear or write this tap (no microphone permission yet, the model not on the iPhone, too little
    /// memory left, a capture that won't start), so it opens the app instead.
    var onStartFailure: () -> Void = {}
    /// Something to tell you about a dictation.
    var onNotice: (String) -> Void = { _ in }
    /// What the mic shows changed.
    var onChange: () -> Void = {}

    /// Recording from a tap on the mic; a finger still on it records unseen (`arm`).
    var isRecording: Bool { take.map { !$0.armed } ?? false }
    /// How long each dictation still being written down is, in seconds, oldest first.
    var writing: [Double] { pending.map(\.seconds) }
    /// What those wait for while Parakeet loads, in a few words; nil once it's loaded.
    var waiting: String? { Self.loading ? "Model loading…" : nil }

    private final class Take {
        let id = UUID()
        let started = Date()
        let app: String?
        let field: String?
        let style: DictationWriting
        let sound: URL
        var armed: Bool
        var mic: String?
        var file: Recording.File?
        var converter: AVAudioConverter?
        var frames = 0
        /// When the page last sent sound, or the start was asked for: what `watch` measures a stall from.
        var heard = Date()
        var watch: Task<Void, Never>?
        var typed = true
        /// The keyboard went away before it was typed: the next keyboard in its field types it (`Held`).
        var held = false
        var left = false

        var seconds: Double { Double(frames) / Recording.format.sampleRate }

        init(app: String?, field: String?, style: DictationWriting, armed: Bool) {
            self.app = app
            self.field = field
            self.style = style
            self.armed = armed
            sound = Self.folder.appending(path: "\(id.uuidString).wav")
            Self.live.insert(id)
        }

        /// Where the keyboard keeps a dictation's sound until the app has it.
        static let folder = URL.temporaryDirectory.appending(path: "dictations")
        /// The takes this keyboard is recording or writing, whose sounds aren't left behind.
        static var live: Set<UUID> = []
    }

    /// A dictation written down after its keyboard went away, typed by the next keyboard in its field within `heldFor`.
    private struct Held: Codable {
        var id: UUID
        var text: String
        var plain: String
        var field: String
        var at: Date
    }

    private let host: UIView
    /// The field the keyboard is in, which each dictation keeps (`Take.field`).
    private var field: String?
    private var take: Take?
    private var pending: [Take] = []
    private var tail: Task<Void, Never>?

    /// The keyboard's one web view, kept between keyboards and moved into whichever shows.
    private static var capture: WebCapture?
    /// The keyboard showing, which a dictation written after its own keyboard went away is typed in, if in its field.
    private static weak var shown: LocalDictation?
    private static var transcriber: Task<Transcriber, any Error>?
    private static var loading = false
    private static var ready = false
    /// WebKit's capture paused another app's audio, which `released` asks to play again.
    private static var othersPaused = false
    private static let heldFile = StoredFile<[Held]>(
        URL.applicationSupportDirectory.appending(path: "dictation-held.json"))
    static let heldFor: TimeInterval = 30
    /// Memory left that a first dictation needs to start, in MB: the web view, its page and WebKit's first use, with
    /// margin (Hex's keyboard, measured in the simulator); later ones reuse the loaded page.
    private static let startRoom = 32.0
    private static let restartRoom = 24.0
    /// Seconds without sound from the page after which a recording ends with what it heard, and a start that never got
    /// the microphone is given up: iOS can suspend WebKit's capture for an alert or a call without a word.
    private static let stall: TimeInterval = 6
    /// Seconds a dictation may take to be written down before it's left for the app to write.
    private static let writingLimit: TimeInterval = 120
    nonisolated private static let audio = DispatchQueue(label: "com.shahidy.iikb.keyboard.audio", qos: .userInitiated)
    nonisolated private static let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

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
            let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
            if let id, Take.live.contains(id) { continue }
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

    /// The picked model can write here: Apple's, or a Parakeet once the app has downloaded v3.
    private static var canWrite: Bool {
        SpeechModel.picked == .apple
            || SpeechModel.v3.folder.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
                == true
    }

    /// The keyboard's process keeps the permission it read as it started, so one started before the app was given the
    /// microphone reads it as not given: the app's own reading counts too.
    private static var micAllowed: Bool {
        AVAudioApplication.shared.recordPermission == .granted || Dictation.micAllowed
    }

    /// iOS ends a keyboard past its memory limit, so a dictation starts only with room for it.
    private static var hasRoom: Bool { KeyboardMemory.fits(capture == nil ? startRoom : restartRoom) }

    private static var canStart: Bool { micAllowed && canWrite && hasRoom }

    /// The keyboard shows in `field`: a dictation written after the last keyboard went away is typed here if it was said
    /// here.
    func appeared(in field: String?) {
        self.field = field
        Self.shown = self
        typeHeld()
    }

    /// Makes the web view and loads its page before the first tap, so a tap has only the microphone left to open.
    /// Nothing here touches the microphone, so iOS shows no orange dot until you dictate.
    func prepare() {
        guard take == nil, Self.canStart else { return }
        let capture = Self.capture ?? WebCapture()
        Self.capture = capture
        capture.onReleased = { Self.released() }
        capture.attach(to: host)
        Self.allowHaptics()
    }

    /// A finger came down on the mic: hearing starts now, unseen, so the first word isn't lost while the touch becomes
    /// a tap (`start` keeps it) or leaves (`disarm`).
    func arm(for app: String?, style: DictationWriting) {
        guard take == nil, Self.canStart else { return }
        begin(for: app, style: style, armed: true)
    }

    /// The finger left the mic without a tap: what it heard goes, with nothing written.
    func disarm() {
        guard let take, take.armed else { return }
        drop(take)
    }

    func start(for app: String?, style: DictationWriting) {
        if let take, take.armed {
            take.armed = false
            return onChange()
        }
        guard take == nil else { return }
        guard Self.canStart else { return onStartFailure() }
        begin(for: app, style: style, armed: false)
    }

    private func begin(for app: String?, style: DictationWriting, armed: Bool) {
        let take = Take(app: app, field: field, style: style, armed: armed)
        self.take = take
        let capture = Self.capture ?? WebCapture()
        Self.capture = capture
        capture.onReleased = { Self.released() }
        capture.attach(to: host)
        capture.onEvent = { [weak self] event in self?.heard(event, in: take) }
        capture.start(microphone: SettingsStore.microphone?.name)
        Self.allowHaptics()
        Self.audio.async {
            guard AVAudioSession.sharedInstance().isOtherAudioPlaying else { return }
            Task { @MainActor in Self.othersPaused = true }
        }
        take.watch = Task { [weak self] in
            while true {
                let wait = Self.stall - Date.now.timeIntervalSince(take.heard)
                if wait <= 0 { break }
                try? await Task.sleep(for: .seconds(wait))  // timer: a stalled dictation
                guard !Task.isCancelled else { return }
            }
            guard let self, self.take === take else { return }
            stalled(take)
        }
        if !armed { onChange() }
    }

    /// Stops hearing you and has what was said written down and typed. A tap before the web view hears anything
    /// undoes the tap, there being nothing to write down.
    func stop() {
        guard let take, !take.armed else { return }
        guard take.file != nil else { return drop(take) }
        Self.capture?.stop()
    }

    /// The bar's cancel: types nothing of the dictation being recorded, which the app keeps in Transcripts.
    func cancel() {
        guard let take, !take.armed else { return }
        take.typed = false
        end(take)
    }

    /// The keyboard went away, or its app left the front: a finger still on the mic records nothing, and the dictation
    /// being recorded stops there and is written down with those already being written. Each is typed if a keyboard
    /// comes back to its field within `heldFor` (`appeared`), and kept in Transcripts as every dictation is.
    func keyboardWillHide() {
        if Self.shown === self { Self.shown = nil }
        if let take {
            if take.armed {
                drop(take)
            } else {
                take.held = true
                end(take)
            }
        }
        for take in pending { take.held = true }
        Self.capture?.detach()
    }

    /// iOS is short of memory: with nothing being recorded or written, the web view and Parakeet go, and load again
    /// when next needed.
    func memoryWarning() {
        guard take == nil, pending.isEmpty, !Self.loading else { return }
        Self.transcriber = nil
        Self.ready = false
        Self.capture?.tearDown()
        Self.capture = nil
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
            take.heard = .now
            take.file = Recording.File(take.sound)
            take.converter = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true
            ).flatMap { AVAudioConverter(from: $0, to: Recording.format) }
            if take.file == nil || take.converter == nil { startFailed("the recording's file or converter") }
        case .samples(let data, let level):
            append(data, to: take)
            take.heard = .now
            if !take.armed { onLevel(level, take.seconds) }
        case .stopped, .processTerminated:
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

    /// No sound came for `stall` seconds: a recording ends with what it heard, and a start that never got the
    /// microphone, or a finger resting on the mic, is given up.
    private func stalled(_ take: Take) {
        Self.log.error("the keyboard's capture went quiet for \(Int(Self.stall)) s")
        if take.armed { return drop(take) }
        guard take.file == nil else { return end(take) }
        drop(take)
        onNotice("The mic didn't start")
    }

    /// The recording is over: what was heard is written down and typed, in the order said, unless it was canceled,
    /// which the app writes down instead.
    private func end(_ take: Take) {
        self.take = nil
        take.watch?.cancel()
        Self.capture?.onEvent = nil
        Self.capture?.stop()
        take.file?.close()
        guard !take.armed, take.frames > 0 else { return drop(take) }
        guard take.typed else {
            Self.leave(take, nil, typed: false)
            return onChange()
        }
        pending.append(take)
        onChange()
        let before = tail
        tail = Task { [weak self] in
            let written = await Self.write(take, within: Self.writingLimit)
            await before?.value
            Self.deliver(take, written, to: self)
        }
    }

    /// Types a dictation written down, or holds it for the next keyboard in its field when its own went away, and
    /// leaves it for the app either way. `owner` is the keyboard it was said in, nil once that's gone.
    private static func deliver(_ take: Take, _ written: Written?, to owner: LocalDictation?) {
        guard !take.left else { return }
        owner?.pending.removeAll { $0 === take }
        defer { owner?.onChange() }
        guard let written else {
            leave(take, nil, typed: false)
            owner?.onNotice("Saved to Transcripts")
            return
        }
        guard written.sounded else {
            leave(take, written.made, typed: false)
            capture?.tearDown()
            capture = nil
            owner?.onNotice("Mic gave no sound")
            return
        }
        var typed = !written.made.text.isEmpty
        if typed {
            if let owner, !take.held {
                owner.onWritten(written.made.text, written.plain, take.id)
            } else if let field = take.field {
                typed = hold(
                    Held(id: take.id, text: written.made.text, plain: written.plain, field: field, at: .now))
            } else {
                typed = false
            }
        }
        leave(take, written.made, typed: typed)
    }

    /// Types `held` in the keyboard showing if it's in its field, true then; else keeps it for `appeared`.
    private static func hold(_ held: Held) -> Bool {
        if let shown, shown.field == held.field {
            shown.onWritten(held.text, held.plain, held.id)
            return true
        }
        heldFile.save((heldFile.read().value ?? []) + [held])
        return false
    }

    /// Types what was held for this field, keeps what was held for another until `heldFor` passes, and says when one
    /// passed untyped, which Transcripts has.
    private func typeHeld() {
        guard let all = Self.heldFile.read().value, !all.isEmpty else { return }
        let fresh = all.filter { Date.now.timeIntervalSince($0.at) <= Self.heldFor }
        let here = fresh.filter { $0.field == field }
        let kept = fresh.filter { $0.field != field }
        if kept.isEmpty { Self.heldFile.remove() } else { Self.heldFile.save(kept) }
        for held in here { onWritten(held.text, held.plain, held.id) }
        if fresh.count < all.count { onNotice("Saved to Transcripts") }
    }

    private struct Written: Sendable {
        var made: Dictation.Made.Written
        /// As the voice model wrote it, with your vocabulary and no style or lists.
        var plain: String
        /// Some sample was past 100/32767, as the app checks its own recordings: none means the microphone was deaf.
        var sounded: Bool
    }

    /// `write`, or nil once `seconds` pass without it: Apple's assets and Core ML can hang, and nothing after this
    /// dictation may wait on it for good.
    private static func write(_ take: Take, within seconds: TimeInterval) async -> Written? {
        let race = Race()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            Task { race.finish(await write(take)) }
            Task {
                try? await Task.sleep(for: .seconds(seconds))  // timer: a stalled dictation
                if race.finish(nil) { log.error("the keyboard gave up writing a dictation after \(Int(seconds)) s") }
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
        do {
            let samples = try Recording.read(take.sound)
            let model = model(for: take.seconds)
            let heard = model == .apple ? try await AppleSpeech.write(samples) : try await loaded().write(samples)
            let vocabulary = VocabularyFeed.read()
            return Written(
                made: Dictation.Made.Written(
                    text: take.style.typed(heard, edited: nil, vocabulary: vocabulary), heard: heard,
                    model: model.title),
                plain: DictationWriting.plain(heard, vocabulary: vocabulary),
                sounded: take.seconds < 1 || samples.contains { abs($0) > 100 / 32767 })
        } catch {
            log.error("the keyboard couldn't write a dictation down: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The model a dictation of `seconds` is written with: Parakeet v3 for a Parakeet picked, while it fits beside the
    /// keyboard, else Apple's, whose model iOS runs outside the keyboard's memory. A keyboard with Parakeet loaded
    /// records at up to 91 MB and FluidAudio holds the whole recording, 0.42 MB a second (Hex's keyboard, iPhone 17
    /// Pro), so Parakeet takes a limit of 131 MB or more, and 24 MB left with 0.5 MB a second of sound.
    private static func model(for seconds: Double) -> SpeechModel {
        guard SpeechModel.picked != .apple else { return .apple }
        let limit = KeyboardMemory.limit
        guard limit == 0 || limit >= 131 * KeyboardMemory.megabyte, KeyboardMemory.fits(24 + seconds / 2) else {
            log.notice(
                "the keyboard writes with Apple's model: \(KeyboardMemory.available >> 20) MB left of \(limit >> 20)")
            return .apple
        }
        return .v3
    }

    /// Parakeet v3, loaded once for as long as the keyboard runs, until iOS is short of memory: its first load after an
    /// install of a new build compiles it for the Neural Engine, here as in the app.
    private static func loaded() async throws -> Transcriber {
        let load = transcriber ?? Task { try await Transcriber.load(SpeechModel.v3) }
        transcriber = load
        if !ready {
            loading = true
            shown?.onChange()
        }
        defer {
            if loading {
                loading = false
                shown?.onChange()
            }
        }
        do {
            let loaded = try await load.value
            ready = true
            return loaded
        } catch {
            transcriber = nil
            throw error
        }
    }

    /// Hands a dictation to the app, once, with its sound: written, or for the app to write.
    private static func leave(_ take: Take, _ written: Dictation.Made.Written?, typed: Bool) {
        guard !take.left else { return }
        take.left = true
        Take.live.remove(take.id)
        Dictation.leave(
            Dictation.Made(
                id: take.id, date: take.started, seconds: take.seconds, typed: typed, written: written, app: take.app,
                mic: take.mic),
            sound: take.sound)
    }

    /// Nothing was heard, or a finger left the mic: there's nothing to keep. The page throws away a start still waiting
    /// for the microphone.
    private func drop(_ take: Take) {
        if self.take === take { self.take = nil }
        take.watch?.cancel()
        Self.capture?.stop()
        take.file?.close()
        Take.live.remove(take.id)
        try? FileManager.default.removeItem(at: take.sound)
        onChange()
    }

    /// The capture never began, so nothing was lost: a tap goes on to open the app, and a finger still on the mic
    /// tries again as it lifts.
    private func startFailed(_ message: String) {
        Self.log.error("the keyboard's capture couldn't start: \(message, privacy: .public)")
        guard let take else { return }
        drop(take)
        if !take.armed { onStartFailure() }
    }

    /// iOS turns haptics off while a process's audio session records, which WebKit's capture makes this keyboard's.
    nonisolated private static let hapticsAllowed: Void = {
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
    }()

    /// The audio session's calls wait on the audio server, which held every key on the main thread.
    private static func allowHaptics() {
        audio.async { _ = hapticsAllowed }
    }

    /// WebKit let the microphone go: audio its capture paused is asked to play again, unless another capture began.
    private static func released() {
        guard othersPaused, capture?.isCapturing != true else { return }
        othersPaused = false
        resumeOthers()
    }

    /// WebKit's capture session doesn't mix, pausing other apps' video and music, and ends without telling them they
    /// may play again. With nothing else playing, the keyboard's own session goes active and off again with
    /// `notifyOthersOnDeactivation`, for players that resume on `shouldResume` (Hex's `InterruptedAudio`).
    nonisolated private static func resumeOthers() {
        audio.async {
            let session = AVAudioSession.sharedInstance()
            guard !session.isOtherAudioPlaying else { return }
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                log.error(
                    "the keyboard couldn't ask paused audio to play: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
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

    func detach() {
        webView.removeFromSuperview()
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
            capture.ctx.onstatechange = () => {
              const state = capture.ctx.state;
              if (!stale() && state !== "running" && state !== "closed") capture.ctx.resume().catch(() => {});
            };
            await capture.ctx.resume();
            if (stale()) return release();
            capture.source = capture.ctx.createMediaStreamSource(capture.stream);
            capture.node = capture.ctx.createScriptProcessor(4096, 1, 1);
            capture.node.onaudioprocess = (event) => {
              if (stale()) return;
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
