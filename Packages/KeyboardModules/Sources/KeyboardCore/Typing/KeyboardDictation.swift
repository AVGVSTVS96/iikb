public struct KeyboardDictation: Sendable {
    public typealias Keyboard = Int
    public typealias Take = Int

    public enum Phase: Equatable, Sendable { case armed, starting, recording, interrupted, stopping }

    public struct Recording: Equatable, Sendable {
        public let take: Take
        public let keyboard: Keyboard
        public let field: String?
        public let began: Double
        public fileprivate(set) var kept: Bool
        public fileprivate(set) var opened = false
        public fileprivate(set) var seconds = 0.0
        public fileprivate(set) var heard: Double
        public fileprivate(set) var interruptedSince: Double?
        public fileprivate(set) var stopping = false
        public fileprivate(set) var canceled = false
        public fileprivate(set) var held = false

        public var phase: Phase {
            if !kept { return .armed }
            if stopping { return .stopping }
            if interruptedSince != nil { return .interrupted }
            return seconds > 0 ? .recording : .starting
        }
    }

    public struct Writing: Equatable, Sendable {
        public let take: Take
        public let keyboard: Keyboard
        public let field: String?
        public let seconds: Double
        public fileprivate(set) var held: Bool
        public fileprivate(set) var outcome: Outcome?
    }

    public enum Outcome: Equatable, Sendable { case unwritten, silent, noWords, words }

    public enum Notice: Equatable, Sendable { case micDidntStart, notWritten, noSound, noWords }

    public enum Parakeet: Equatable, Sendable {
        case unloaded
        case loading(Int)
        case loaded(Int)
        case setAside
    }

    public enum Model: Equatable, Sendable { case parakeet, apple }

    public enum Effect: Equatable, Sendable {
        case attach(Keyboard)
        case detach(Keyboard)
        case readAudio(Take)
        case startCapture(Take)
        case stopCapture
        case watch(Take)
        case discard(Take)
        case write(Take)
        case leave(Take, typed: Bool)
        case type(Take, in: Keyboard)
        case hold(Take, in: String)
        case notice(Notice, Keyboard)
        case openApp(Keyboard)
        case letGoOfCapture
        case loadParakeet(Int)
        case letGoOfParakeet
        case resumeOthers
        case changed(Keyboard)
    }

    public struct Room: Equatable, Sendable {
        public var limit: Int
        public var available: Int

        public init(limit: Int, available: Int) {
            self.limit = limit
            self.available = available
        }

        public static let megabyte = 1_048_576
        public static let limitNeeded = 131.0
        public static let toLoad = 60.0
        public static let toStart = 32.0
        public static let toRestart = 24.0

        public static func toWrite(_ seconds: Double) -> Double { 24 + seconds / 2 }

        public var fitsKeyboard: Bool { limit == 0 || Double(limit) >= Self.limitNeeded * Double(Self.megabyte) }

        public func fits(_ megabytes: Double) -> Bool {
            available == 0 || Double(available) >= megabytes * Double(Self.megabyte)
        }

        public var loads: Bool { fitsKeyboard && fits(Self.toLoad) }

        public func writes(_ seconds: Double) -> Bool { fitsKeyboard && fits(Self.toWrite(seconds)) }

        public var described: String { "\(available >> 20) MB left of \(limit >> 20)" }
    }

    public static let armedFor = 3.0
    public static let quiet = 6.0
    public static let interruption = 15.0
    public static let heldFor = 30.0

    public private(set) var recording: Recording?
    public private(set) var writing: [Writing] = []
    public private(set) var shown: (keyboard: Keyboard, field: String?)?
    public private(set) var place: Keyboard?
    public private(set) var hasCapture = false
    public private(set) var othersPaused = false
    public private(set) var parakeet = Parakeet.unloaded
    public private(set) var warned = false
    private var takes = 0
    private var loadCount = 0

    public init() {}

    public func isRecording(in keyboard: Keyboard) -> Bool {
        recording.map { $0.keyboard == keyboard && $0.kept } ?? false
    }

    public func hears(in keyboard: Keyboard) -> Bool {
        recording.map { $0.keyboard == keyboard && $0.kept && $0.seconds > 0 } ?? false
    }

    public func writing(in keyboard: Keyboard) -> [Double] {
        writing.filter { $0.keyboard == keyboard }.map(\.seconds)
    }

    public func isLive(_ take: Take) -> Bool {
        recording?.take == take || writing.contains { $0.take == take }
    }

    public func canStart(micAllowed: Bool, canWrite: Bool, room: Room) -> Bool {
        micAllowed && canWrite && room.fits(hasCapture ? Room.toRestart : Room.toStart)
    }

    public mutating func appeared(_ keyboard: Keyboard, in field: String?) {
        shown = (keyboard, field)
        warned = false
    }

    public mutating func prepare(_ keyboard: Keyboard, canStart: Bool) -> [Effect] {
        guard recording?.keyboard != keyboard, canStart else { return [] }
        hasCapture = true
        place = keyboard
        return [.attach(keyboard)]
    }

    public mutating func arm(_ keyboard: Keyboard, in field: String?, at now: Double, canStart: Bool) -> [Effect] {
        guard recording?.keyboard != keyboard, canStart else { return [] }
        return begin(keyboard, in: field, at: now, kept: false)
    }

    public mutating func start(_ keyboard: Keyboard, in field: String?, at now: Double, canStart: Bool) -> [Effect] {
        if let recording, recording.keyboard == keyboard {
            guard !recording.kept else { return [] }
            self.recording?.kept = true
            return [.changed(keyboard)]
        }
        guard canStart else { return [.openApp(keyboard)] }
        return begin(keyboard, in: field, at: now, kept: true)
    }

    private mutating func begin(_ keyboard: Keyboard, in field: String?, at now: Double, kept: Bool) -> [Effect] {
        var effects: [Effect] = []
        if let other = recording {
            recording?.held = true
            effects += end(other.take)
        }
        takes += 1
        recording = Recording(take: takes, keyboard: keyboard, field: field, began: now, kept: kept, heard: now)
        hasCapture = true
        place = keyboard
        effects += [.attach(keyboard), .readAudio(takes), .watch(takes)]
        if kept { effects.append(.changed(keyboard)) }
        return effects
    }

    public mutating func audioRead(_ take: Take, othersPlaying: Bool) -> [Effect] {
        guard recording?.take == take else { return [] }
        if othersPlaying { othersPaused = true }
        return [.startCapture(take)]
    }

    public mutating func disarm(_ keyboard: Keyboard) -> [Effect] {
        guard let recording, recording.keyboard == keyboard, !recording.kept else { return [] }
        return drop(recording.take)
    }

    public mutating func stop(_ keyboard: Keyboard) -> [Effect] {
        guard let recording, recording.keyboard == keyboard, recording.kept, !recording.stopping else { return [] }
        guard recording.opened else { return drop(recording.take) }
        self.recording?.stopping = true
        return [.stopCapture, .changed(keyboard)]
    }

    public mutating func cancel(_ keyboard: Keyboard) -> [Effect] {
        guard let recording, recording.keyboard == keyboard, recording.kept else { return [] }
        self.recording?.canceled = true
        return end(recording.take)
    }

    public mutating func hidden(_ keyboard: Keyboard) -> [Effect] {
        if shown?.keyboard == keyboard { shown = nil }
        var effects: [Effect] = []
        if let recording, recording.keyboard == keyboard {
            if recording.kept {
                self.recording?.held = true
                effects += end(recording.take)
            } else {
                effects += drop(recording.take)
            }
        }
        for index in writing.indices where writing[index].keyboard == keyboard { writing[index].held = true }
        if place == keyboard {
            place = nil
            effects.append(.detach(keyboard))
        }
        return effects
    }

    public mutating func opened(_ take: Take, at now: Double) {
        guard recording?.take == take else { return }
        recording?.opened = true
        recording?.heard = now
    }

    public mutating func sound(_ take: Take, seconds: Double, at now: Double) -> [Effect] {
        guard let recording, recording.take == take else { return [] }
        self.recording?.seconds = seconds
        self.recording?.heard = now
        return recording.seconds == 0 && recording.kept ? [.changed(recording.keyboard)] : []
    }

    public mutating func interrupted(_ take: Take, _ interrupted: Bool, at now: Double) {
        guard let recording, recording.take == take else { return }
        if interrupted {
            self.recording?.interruptedSince = recording.interruptedSince ?? now
        } else {
            self.recording?.interruptedSince = nil
            self.recording?.heard = now
        }
    }

    public mutating func ended(_ take: Take) -> [Effect] {
        guard recording?.take == take else { return [] }
        return end(take)
    }

    public mutating func failed(_ take: Take) -> [Effect] {
        guard let recording, recording.take == take else { return [] }
        guard !recording.opened else { return end(take) }
        return drop(take) + (recording.kept ? [.openApp(recording.keyboard)] : [])
    }

    public func deadline(_ take: Take) -> Double? {
        guard let recording, recording.take == take else { return nil }
        let quiet =
            recording.interruptedSince.map { $0 + Self.interruption } ?? recording.heard + Self.quiet
        return recording.kept ? quiet : min(quiet, recording.began + Self.armedFor)
    }

    public mutating func due(_ take: Take, at now: Double) -> [Effect] {
        guard let recording, recording.take == take, let deadline = deadline(take), now >= deadline else { return [] }
        if !recording.kept { return drop(take) }
        if recording.opened { return end(take) }
        return drop(take) + [.notice(.micDidntStart, recording.keyboard)]
    }

    private mutating func drop(_ take: Take) -> [Effect] {
        guard let recording, recording.take == take else { return [] }
        self.recording = nil
        return [.stopCapture, .discard(take), .changed(recording.keyboard)]
    }

    private mutating func end(_ take: Take) -> [Effect] {
        guard let recording, recording.take == take else { return [] }
        guard recording.kept, recording.seconds > 0 else { return drop(take) }
        self.recording = nil
        guard !recording.canceled else {
            return [.stopCapture, .leave(take, typed: false), .changed(recording.keyboard)]
        }
        writing.append(
            Writing(
                take: take, keyboard: recording.keyboard, field: recording.field, seconds: recording.seconds,
                held: recording.held))
        return [.stopCapture, .write(take), .changed(recording.keyboard)]
    }

    public mutating func written(_ take: Take, _ outcome: Outcome) -> [Effect] {
        guard let index = writing.firstIndex(where: { $0.take == take && $0.outcome == nil }) else { return [] }
        writing[index].outcome = outcome
        var effects: [Effect] = []
        while let first = writing.first, let outcome = first.outcome {
            writing.removeFirst()
            effects += deliver(first, outcome)
        }
        return effects
    }

    private mutating func deliver(_ take: Writing, _ outcome: Outcome) -> [Effect] {
        let changed = Effect.changed(take.keyboard)
        switch outcome {
        case .unwritten:
            return [.leave(take.take, typed: false), .notice(.notWritten, take.keyboard), changed]
        case .silent:
            return [.leave(take.take, typed: false)] + letGoOfCapture() + [.notice(.noSound, take.keyboard), changed]
        case .noWords:
            return [.leave(take.take, typed: false), .notice(.noWords, take.keyboard), changed]
        case .words:
            if !take.held { return [.type(take.take, in: take.keyboard), .leave(take.take, typed: true), changed] }
            guard let field = take.field else { return [.leave(take.take, typed: false), changed] }
            if let shown, shown.field == field {
                return [.type(take.take, in: shown.keyboard), .leave(take.take, typed: true), changed]
            }
            return [.hold(take.take, in: field), .leave(take.take, typed: false), changed]
        }
    }

    public mutating func letGoOfCapture() -> [Effect] {
        guard recording == nil, hasCapture else { return [] }
        hasCapture = false
        place = nil
        return [.letGoOfCapture]
    }

    public mutating func captureLost() {
        hasCapture = false
        place = nil
    }

    public mutating func released() -> [Effect] {
        guard othersPaused, recording == nil else { return [] }
        othersPaused = false
        return [.resumeOthers]
    }

    public mutating func memoryWarning() -> [Effect] {
        warned = true
        var effects = letGoOfCapture()
        switch parakeet {
        case .loading, .loaded:
            parakeet = .unloaded
            effects.append(.letGoOfParakeet)
        case .unloaded, .setAside:
            break
        }
        return effects
    }

    public var parakeetLoaded: Bool {
        if case .loaded = parakeet { return true }
        return false
    }

    public func model(picked parakeetPicked: Bool, seconds: Double, room: Room) -> Model {
        guard parakeetPicked, parakeetLoaded, room.writes(seconds) else { return .apple }
        return .parakeet
    }

    public mutating func preload(picked parakeetPicked: Bool, downloaded: Bool, dictatedBefore: Bool, room: Room)
        -> [Effect]
    {
        guard parakeetPicked, downloaded, dictatedBefore, parakeet == .unloaded, !warned, recording == nil,
            room.fitsKeyboard, room.fits(Room.toLoad + Room.toRestart)
        else { return [] }
        loadCount += 1
        parakeet = .loading(loadCount)
        return [.loadParakeet(loadCount)]
    }

    public mutating func finishedLoading(_ load: Int) -> Bool {
        guard parakeet == .loading(load) else { return false }
        parakeet = .loaded(load)
        return true
    }

    public mutating func failedLoading(_ load: Int, onCPU: Bool) {
        if onCPU {
            parakeet = .setAside
        } else if parakeet == .loading(load) {
            parakeet = .unloaded
        }
    }

    public static func held(_ fields: [(field: String, at: Double)], in field: String?, at now: Double)
        -> (here: [Int], kept: [Int], expired: Bool)
    {
        let fresh = fields.indices.filter { now - fields[$0].at <= heldFor }
        let here = fresh.filter { fields[$0].field == field }
        return (here, fresh.filter { fields[$0].field != field }, fresh.count < fields.count)
    }

    public static func sounded(_ samples: [Float], sampleRate: Double) -> Bool {
        Double(samples.count) < sampleRate || samples.contains { abs($0) > 100 / 32767 }
    }
}
