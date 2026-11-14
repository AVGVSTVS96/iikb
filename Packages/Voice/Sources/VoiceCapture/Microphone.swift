import AVFoundation
import KeyboardStore
import OSLog
import Observation
import UIKit

nonisolated private let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

/// The microphone, recording a dictation as a `Recording`: 16 kHz, kept in memory and written to its file as
/// it's heard. It knows nothing of the models that write recordings down, so nothing about them can hold up a
/// recording.
@Observable @MainActor public final class Microphone {
    private var engine = AVAudioEngine()
    private let feed = Feed()
    /// How the iPhone's microphones are aimed now, nil when another microphone hears.
    private var aimed: Capture?
    /// How the recording being made is heard, nil when a restart changed it mid-recording.
    private var recordingAs: Capture?
    /// The engine couldn't be started again after a change under it.
    public var onLost: () -> Void = {}
    /// Another app took the microphone: a call answered, a voice message, Siri.
    public var onInterrupted: () -> Void = {}
    /// iOS says the app that took the microphone is done with it.
    public var onFreed: () -> Void = {}
    public var onLevel: (_ loudness: Float, _ recorded: Double) -> Void = { _, _ in }

    public init() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) {
            [weak self] note in
            let info = note.userInfo
            let began =
                info?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue
            let resume =
                (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map {
                    AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume)
                } ?? false
            Task { @MainActor in
                if began { self?.onInterrupted() } else if resume { self?.onFreed() }
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) {
            [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(
                AVAudioSession.RouteChangeReason.init)
            Task { @MainActor in
                guard let self, self.isOn, let reason else { return }
                if let picked = SettingsStore.microphone, picked.kind != .iPhone,
                    reason == .newDeviceAvailable || reason == .oldDeviceUnavailable
                {
                    self.restart()  // restart: a picked microphone came or went
                }
            }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isOn, !self.engine.isRunning else { return }
                self.restart()  // restart: iOS stopped it
            }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor in self?.restart(rebuilding: true) }  // restart: iOS stopped it
        }
    }

    public private(set) var isOn = false
    /// It went on or off.
    public var onChange: () -> Void = {}

    /// The input recording now, as iOS names it.
    public var input: String? { AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName }

    /// How the last recording was heard: the front cardioid, or nil for iOS's own pick, another microphone, or a restart
    /// that changed it mid-recording.
    public var heard: Capture? { recordingAs }

    /// By default it hears from the iPhone and never from a Bluetooth microphone, which would put a speaker or AirPods on
    /// a call (`.allowBluetoothHFP`), and music would drop to call quality or stop. A microphone picked in Settings is
    /// asked for by `PickedMicrophone.matches` and heard from instead: a Bluetooth one is the only pick that allows
    /// Bluetooth's microphone, at full quality where it records so (`.bluetoothHighQualityRecording`, recent AirPods),
    /// else on a call, and only while it's connected; away, the iPhone's hears and the category goes back, and a device
    /// coming or going (`routeChangeNotification`) starts the engine again onto the pick.
    ///
    /// It never runs Apple's voice processing, which takes sound from a Bluetooth speaker or AirPlay to the iPhone, pauses
    /// music apps and ducks the rest, and gave a dictation no sound at all on 19 of 436 (Nov 4 to 7, 3 of 381 without
    /// it). So it mixes with whatever else plays, wherever it plays, and nothing else hears a difference. iOS mutes
    /// every app's haptics while any app records unless the recording session allows them, and an incoming call that
    /// rings doesn't stop it, only one that's answered.
    public func open() throws {
        guard !isOn else { return }
        do {
            try beginOnAnyEngine()
        } catch {
            Self.rest()
            throw error
        }
        isOn = true
        onChange()
    }

    /// The session while nothing records: inactive, and playback, the category picture in picture needs (`MicTab`),
    /// mixing so it stops no one's sound.
    public static func rest() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
    }

    /// An engine left from before a media services reset can't start (-50), and a suspended iikb may not hear of the
    /// reset, so a failed start tries once more on a new engine.
    private func beginOnAnyEngine() throws {
        do {
            try begin()
        } catch {
            engine = AVAudioEngine()
            try begin()
        }
    }

    static let options: AVAudioSession.CategoryOptions = [
        .mixWithOthers, .allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker,
    ]

    private func begin() throws {
        let session = AVAudioSession.sharedInstance()
        let picked = SettingsStore.microphone
        let bluetooth: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .bluetoothHighQualityRecording]
        try session.setCategory(
            .playAndRecord, mode: .default,
            options: picked?.kind == .bluetooth ? Self.options.union(bluetooth) : Self.options)
        try? session.setPrefersNoInterruptionsFromSystemAlerts(true)
        try session.setActive(true)
        var input = picked.flatMap { picked in session.availableInputs?.first(where: picked.matches) }
        if picked?.kind == .bluetooth, input == nil {
            try session.setCategory(.playAndRecord, mode: .default, options: Self.options)
        }
        if picked != nil, input == nil { input = session.availableInputs?.first { $0.portType == .builtInMic } }
        try? session.setPreferredInput(input)
        do {
            aimed = try Capture.aim(session)
        } catch {
            log.error("couldn't aim the microphone: \(error.localizedDescription, privacy: .public)")
            aimed = nil
        }
        if feed.isRecording, aimed != recordingAs { recordingAs = nil }
        let node = engine.inputNode
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        let heard = node.outputFormat(forBus: 0)
        guard heard.sampleRate > 0, heard.channelCount > 0 else { throw Unrecordable(format: heard.description) }
        node.installTap(
            onBus: 0, bufferSize: 4096, format: nil,
            block: Self.tap(feed) { [weak self] level, recorded in
                Dictation.publish(level: level, recorded: recorded)
                Task { @MainActor in self?.onLevel(level, recorded) }
            })
        engine.prepare()
        do {
            try engine.start()
        } catch {
            node.removeTap(onBus: 0)
            throw error
        }
        let route = session.currentRoute.inputs.first
        let source = route?.selectedDataSource
        log.notice(
            "hearing \(self.aimed?.rawValue ?? "as iOS picks", privacy: .public), from \(route?.portType.rawValue ?? "nothing", privacy: .public) \(source?.dataSourceName ?? "", privacy: .public) \(source?.selectedPolarPattern?.rawValue ?? "", privacy: .public), other audio \(session.isOtherAudioPlaying ? "playing" : "silent", privacy: .public)"
        )
    }

    /// iOS stops the engine when the hardware's format or route changes under it, and every audio object is dead after
    /// the media services reset, the microphone on or off, and another microphone may be picked: starts again into the
    /// same recording, which converts whatever format comes next.
    public func restart(rebuilding: Bool = false) {
        if rebuilding {
            engine = AVAudioEngine()
        } else {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        guard isOn else { return }
        do {
            try beginOnAnyEngine()
        } catch {
            onLost()
        }
    }

    public func close() {
        guard isOn else { return }
        _ = feed.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        Self.rest()
        isOn = false
        onChange()
    }

    /// Records from the next sound on into `url`.
    public func record(to url: URL) {
        recordingAs = aimed
        feed.start(file: url)
        Dictation.publish(level: 0, recorded: 0)
    }

    /// Everything recorded since `record`, through your last word (`Feed.stopOnceQuiet`).
    public func stop() async -> [Float] {
        engine.isRunning ? await feed.stopOnceQuiet() : feed.stop()
    }

    /// Everything recorded since `record`, up to now.
    public func cut() -> [Float] {
        feed.stop()
    }

    /// Whether iikb is in front, the only time it stops and starts the microphone by choice: from the background iOS
    /// refuses the new start (Bassim's Duo, Nov 6: OSStatus 560557684 pointing it, then the engine's start failing twice).
    public static var inFront: Bool { UIApplication.shared.applicationState == .active }

    /// Runs on the audio thread: hands each buffer to the recording, if there is one, and says how loud it was and how
    /// long the recording is now.
    nonisolated private static func tap(_ feed: Feed, level: @escaping @Sendable (Float, Double) -> Void)
        -> AVAudioNodeTapBlock
    {
        return { buffer, time in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<frames { sum += samples[index] * samples[index] }
            let loudness = (sum / Float(frames)).squareRoot()
            if let recorded = feed.yield(buffer, at: time, loudness: loudness) { level(loudness, recorded) }
        }
    }
}

nonisolated private struct Unrecordable: LocalizedError {
    let format: String
    var errorDescription: String? { "iikb can't record from this microphone (\(format))." }
}

/// Where the microphone's buffers go: into the `Recording` while one is being made, nowhere while the microphone is
/// only being kept on. The audio thread reads it and the main thread swaps it, under a lock.
nonisolated private final class Feed: @unchecked Sendable {
    private let lock = NSLock()
    private var recorder: AVAudioConverter?
    /// The format of the buffers coming in, to know when they change.
    private var heard: AVAudioFormat?
    /// Channel 0 of a multichannel buffer, the one signal the level meter and the recording share.
    private var mono: AVAudioPCMBuffer?
    /// What's been heard since `start`, nil while nothing is being recorded; kept even when its file can't be written.
    private var recording: [Float]?
    private var file: Recording.File?
    private var loudness: [Float] = []
    private var stopped: UInt64?
    private var ended: CheckedContinuation<[Float], Never>?

    var isRecording: Bool { lock.withLock { recording != nil } }

    func start(file url: URL) {
        lock.withLock {
            recorder = nil
            heard = nil
            recording = []
            file = Recording.File(url)
            loudness = []
        }
    }

    /// Everything heard since `start`.
    func stop() -> [Float] {
        let (recording, ended) = lock.withLock { take() }
        ended?.resume(returning: recording)
        return recording
    }

    /// Everything heard since `start`, through the moment of the stop by the clock the microphone stamps its sound with,
    /// and on until you're quiet, since a stop tapped as you finish speaking lands on your last word. A room that never
    /// gets quiet, or a microphone that stops sending, ends it a second after the stop.
    @MainActor func stopOnceQuiet() async -> [Float] {
        guard lock.withLock({ recording != nil }) else { return stop() }
        let stopped = mach_absolute_time()
        let loud = Task {
            guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }  // timer: stop waits for quiet
            _ = self.stop()
        }
        defer { loud.cancel() }
        return await withCheckedContinuation { ended in
            lock.withLock { (self.stopped, self.ended) = (stopped, ended) }
        }
    }

    /// How many seconds the recording holds with the buffer, nil when there's no recording to take it.
    func yield(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime, loudness level: Float) -> Double? {
        let (took, done) = lock.withLock { () -> (Double?, ([Float], CheckedContinuation<[Float], Never>?)?) in
            guard recording != nil else { return (nil, nil) }
            if heard != buffer.format {
                heard = buffer.format
                recorder = nil
                log.notice(
                    "recording from \(buffer.format.channelCount) channels at \(buffer.format.sampleRate, format: .fixed(precision: 0)) Hz"
                )
            }
            let source = channelZero(of: buffer)
            if recorder == nil, let source { recorder = AVAudioConverter(from: source.format, to: Recording.format) }
            if let source, let recorder, let converted = Self.convert(source, with: recorder),
                let channel = converted.floatChannelData?[0]
            {
                let samples = UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))
                recording?.append(contentsOf: samples)
                file?.append(samples)
            }
            loudness.append(level)
            let recorded = Double(recording?.count ?? 0) / Recording.format.sampleRate
            let length = AVAudioTime.hostTime(forSeconds: Double(buffer.frameLength) / buffer.format.sampleRate)
            guard let stopped, !time.isHostTimeValid || time.hostTime + length >= stopped && isQuiet(level) else {
                return (recorded, nil)
            }
            return (recorded, take())
        }
        if let (recording, ended) = done { ended?.resume(returning: recording) }
        return took
    }

    private func channelZero(of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        if format.channelCount == 1, !format.isInterleaved { return buffer }
        if mono?.format.sampleRate != format.sampleRate || mono?.frameCapacity ?? 0 < buffer.frameLength {
            mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1).flatMap {
                AVAudioPCMBuffer(pcmFormat: $0, frameCapacity: max(buffer.frameLength, 4096))
            }
        }
        guard let mono, let from = buffer.floatChannelData?[0], let to = mono.floatChannelData?[0] else { return nil }
        let stride = buffer.stride
        for index in 0..<Int(buffer.frameLength) { to[index] = from[index * stride] }
        mono.frameLength = buffer.frameLength
        return mono
    }

    private func take() -> ([Float], CheckedContinuation<[Float], Never>?) {
        file?.close()
        defer {
            file = nil
            recorder = nil
            heard = nil
            recording = nil
            loudness = []
            stopped = nil
            ended = nil
        }
        return (recording ?? [], ended)
    }

    /// Nearer the room than your voice, as this recording's quietest tenth and loudest twentieth of the sound have them.
    private func isQuiet(_ level: Float) -> Bool {
        let sorted = loudness.sorted()
        return level * level <= sorted[sorted.count / 10] * sorted[sorted.count * 19 / 20]
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let format = converter.outputFormat
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var fed = false
        converter.convert(to: converted, error: nil) { _, status in
            status.pointee = fed ? .noDataNow : .haveData
            defer { fed = true }
            return fed ? nil : buffer
        }
        return converted
    }
}
