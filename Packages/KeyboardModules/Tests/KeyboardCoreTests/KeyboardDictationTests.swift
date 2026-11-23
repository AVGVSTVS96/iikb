import Testing

@testable import KeyboardCore

struct KeyboardDictationTests {
    typealias Effect = KeyboardDictation.Effect

    static let megabyte = 1_048_576
    static let a = 1
    static let b = 2

    static func room(limit: Int, left: Int) -> KeyboardDictation.Room {
        KeyboardDictation.Room(limit: limit * megabyte, available: left * megabyte)
    }

    static let roomy = room(limit: 177, left: 100)

    static func recording(in keyboard: KeyboardDictation.Keyboard = a, seconds: Double = 2) -> KeyboardDictation {
        var dictation = KeyboardDictation()
        dictation.appeared(keyboard, in: "field")
        _ = dictation.start(keyboard, in: "field", at: 0, canStart: true)
        let take = dictation.recording!.take
        _ = dictation.audioRead(take, othersPlaying: false)
        dictation.opened(take, at: 0.5)
        _ = dictation.sound(take, seconds: seconds, at: 1)
        return dictation
    }

    @Test func aTouchDownHearsUnseenAndATapKeepsIt() {
        var dictation = KeyboardDictation()
        let armed = dictation.arm(Self.a, in: "field", at: 0, canStart: true)
        let take = dictation.recording!.take
        #expect(armed == [.attach(Self.a), .readAudio(take), .watch(take)])
        #expect(dictation.recording?.phase == .armed)
        #expect(!dictation.isRecording(in: Self.a))
        #expect(dictation.start(Self.a, in: "field", at: 0.2, canStart: true) == [.changed(Self.a)])
        #expect(dictation.recording?.phase == .starting)
        #expect(dictation.isRecording(in: Self.a))
        #expect(dictation.recording?.take == take)
    }

    @Test func aFingerThatLeavesOrRestsThrowsWhatItHeardAway() {
        var dictation = KeyboardDictation()
        _ = dictation.arm(Self.a, in: "field", at: 0, canStart: true)
        let take = dictation.recording!.take
        #expect(dictation.disarm(Self.a) == [.stopCapture, .discard(take), .changed(Self.a)])
        #expect(dictation.recording == nil)

        _ = dictation.arm(Self.a, in: "field", at: 10, canStart: true)
        let resting = dictation.recording!.take
        _ = dictation.audioRead(resting, othersPlaying: false)
        dictation.opened(resting, at: 10.5)
        _ = dictation.sound(resting, seconds: 1, at: 11)
        #expect(dictation.deadline(resting) == 13)
        #expect(dictation.due(resting, at: 12.9).isEmpty)
        #expect(dictation.due(resting, at: 13) == [.stopCapture, .discard(resting), .changed(Self.a)])
    }

    @Test func theMicShowsStartingUntilTheFirstSound() {
        var dictation = KeyboardDictation()
        _ = dictation.start(Self.a, in: "field", at: 0, canStart: true)
        let take = dictation.recording!.take
        _ = dictation.audioRead(take, othersPlaying: false)
        dictation.opened(take, at: 0.4)
        #expect(!dictation.hears(in: Self.a))
        #expect(dictation.recording?.phase == .starting)
        #expect(dictation.sound(take, seconds: 0.25, at: 0.6) == [.changed(Self.a)])
        #expect(dictation.hears(in: Self.a))
        #expect(dictation.recording?.phase == .recording)
        #expect(dictation.sound(take, seconds: 0.5, at: 0.8).isEmpty)
    }

    @Test func aTapWhileStartingUndoesTheStart() {
        var dictation = KeyboardDictation()
        _ = dictation.start(Self.a, in: "field", at: 0, canStart: true)
        let take = dictation.recording!.take
        #expect(dictation.stop(Self.a) == [.stopCapture, .discard(take), .changed(Self.a)])
        #expect(dictation.recording == nil)
        #expect(dictation.writing.isEmpty)

        _ = dictation.start(Self.a, in: "field", at: 1, canStart: true)
        let opened = dictation.recording!.take
        dictation.opened(opened, at: 1.2)
        #expect(dictation.stop(Self.a) == [.stopCapture, .changed(Self.a)])
        #expect(dictation.recording?.phase == .stopping)
        #expect(dictation.ended(opened) == [.stopCapture, .discard(opened), .changed(Self.a)])
        #expect(dictation.writing.isEmpty)
    }

    @Test func aStopWritesWhatWasHeardAndTypesIt() {
        var dictation = Self.recording()
        let take = dictation.recording!.take
        _ = dictation.stop(Self.a)
        #expect(dictation.ended(take) == [.stopCapture, .write(take), .changed(Self.a)])
        #expect(dictation.writing(in: Self.a) == [2])
        #expect(dictation.isLive(take))
        #expect(dictation.written(take, .words) == [.type(take, in: Self.a), .leave(take, typed: true), .changed(Self.a)])
        #expect(!dictation.isLive(take))
    }

    @Test func dictationsAreTypedInTheOrderSaid() {
        var dictation = Self.recording()
        let first = dictation.recording!.take
        _ = dictation.ended(first)
        _ = dictation.start(Self.a, in: "field", at: 5, canStart: true)
        let second = dictation.recording!.take
        dictation.opened(second, at: 5)
        _ = dictation.sound(second, seconds: 1, at: 6)
        _ = dictation.ended(second)
        #expect(dictation.written(second, .words).isEmpty)
        #expect(
            dictation.written(first, .words) == [
                .type(first, in: Self.a), .leave(first, typed: true), .changed(Self.a), .type(second, in: Self.a),
                .leave(second, typed: true), .changed(Self.a),
            ])
    }

    @Test func whatIsntTypedIsLeftForTheAppWithWhy() {
        for (outcome, notice) in [
            (KeyboardDictation.Outcome.unwritten, KeyboardDictation.Notice.notWritten), (.noWords, .noWords),
        ] {
            var dictation = Self.recording()
            let take = dictation.recording!.take
            _ = dictation.ended(take)
            #expect(
                dictation.written(take, outcome) == [.leave(take, typed: false), .notice(notice, Self.a), .changed(Self.a)])
        }
    }

    @Test func aDeafMicrophoneThrowsItsWebViewAway() {
        var dictation = Self.recording()
        let take = dictation.recording!.take
        _ = dictation.ended(take)
        #expect(
            dictation.written(take, .silent) == [
                .leave(take, typed: false), .letGoOfCapture, .notice(.noSound, Self.a), .changed(Self.a),
            ])
        #expect(!dictation.hasCapture)
        #expect(!dictation.canStart(micAllowed: true, canWrite: true, room: Self.room(limit: 177, left: 30)))
        #expect(dictation.canStart(micAllowed: true, canWrite: true, room: Self.room(limit: 177, left: 32)))
    }

    @Test func aCanceledDictationIsLeftForTheAppUntyped() {
        var dictation = Self.recording()
        let take = dictation.recording!.take
        #expect(dictation.cancel(Self.a) == [.stopCapture, .leave(take, typed: false), .changed(Self.a)])
        #expect(dictation.writing.isEmpty)
    }

    @Test func aTapTheKeyboardCantHearOpensTheApp() {
        var dictation = KeyboardDictation()
        #expect(dictation.start(Self.a, in: "field", at: 0, canStart: false) == [.openApp(Self.a)])
        #expect(dictation.arm(Self.a, in: "field", at: 0, canStart: false).isEmpty)
        _ = dictation.start(Self.a, in: "field", at: 0, canStart: true)
        let take = dictation.recording!.take
        #expect(dictation.failed(take) == [.stopCapture, .discard(take), .changed(Self.a), .openApp(Self.a)])

        _ = dictation.arm(Self.a, in: "field", at: 1, canStart: true)
        let armed = dictation.recording!.take
        #expect(dictation.failed(armed) == [.stopCapture, .discard(armed), .changed(Self.a)])
    }

    @Test func aStartNeedsMoreRoomUntilThePageIsLoaded() {
        var dictation = KeyboardDictation()
        let tight = Self.room(limit: 177, left: 28)
        #expect(!dictation.canStart(micAllowed: true, canWrite: true, room: tight))
        _ = dictation.prepare(Self.a, canStart: true)
        #expect(dictation.canStart(micAllowed: true, canWrite: true, room: tight))
        #expect(!dictation.canStart(micAllowed: false, canWrite: true, room: tight))
        #expect(!dictation.canStart(micAllowed: true, canWrite: false, room: tight))
        #expect(KeyboardDictation().canStart(micAllowed: true, canWrite: true, room: .init(limit: 0, available: 0)))
    }

    @Test func otherAudioIsReadBeforeThePageStarts() {
        var dictation = KeyboardDictation()
        let effects = dictation.start(Self.a, in: "field", at: 0, canStart: true)
        let take = dictation.recording!.take
        #expect(effects.contains(.readAudio(take)))
        #expect(!effects.contains(.startCapture(take)))
        #expect(dictation.audioRead(take, othersPlaying: true) == [.startCapture(take)])
        #expect(dictation.othersPaused)
        #expect(dictation.released().isEmpty)
        _ = dictation.stop(Self.a)
        _ = dictation.ended(take)
        #expect(dictation.released() == [.resumeOthers])
        #expect(dictation.released().isEmpty)
    }

    @Test func audioReadForAStaleTakeStartsNothing() {
        var dictation = KeyboardDictation()
        _ = dictation.arm(Self.a, in: "field", at: 0, canStart: true)
        let take = dictation.recording!.take
        _ = dictation.disarm(Self.a)
        #expect(dictation.audioRead(take, othersPlaying: true).isEmpty)
        #expect(!dictation.othersPaused)
    }

    @Test func nothingPlayingIsNeverAskedToResume() {
        var dictation = Self.recording()
        let take = dictation.recording!.take
        _ = dictation.ended(take)
        #expect(dictation.released().isEmpty)
    }

    @Test func quietEndsARecordingWithWhatItHeard() {
        var dictation = Self.recording()
        let take = dictation.recording!.take
        #expect(dictation.deadline(take) == 7)
        #expect(dictation.due(take, at: 6.9).isEmpty)
        #expect(dictation.due(take, at: 7) == [.stopCapture, .write(take), .changed(Self.a)])
    }

    @Test func aStartThatNeverGotTheMicrophoneSaysSo() {
        var dictation = KeyboardDictation()
        _ = dictation.start(Self.a, in: "field", at: 0, canStart: true)
        let take = dictation.recording!.take
        #expect(
            dictation.due(take, at: 6) == [.stopCapture, .discard(take), .changed(Self.a), .notice(.micDidntStart, Self.a)])
    }

    @Test func anInterruptionWaitsLongerThanQuiet() {
        var dictation = Self.recording()
        let take = dictation.recording!.take
        dictation.interrupted(take, true, at: 2)
        #expect(dictation.recording?.phase == .interrupted)
        dictation.interrupted(take, true, at: 3)
        #expect(dictation.deadline(take) == 17)
        #expect(dictation.due(take, at: 10).isEmpty)
        dictation.interrupted(take, false, at: 4)
        #expect(dictation.recording?.phase == .recording)
        #expect(dictation.deadline(take) == 10)
        dictation.interrupted(take, true, at: 5)
        #expect(dictation.due(take, at: 20) == [.stopCapture, .write(take), .changed(Self.a)])
    }

    @Test func aHiddenKeyboardTakesTheWebViewOnlyFromItself() {
        var dictation = KeyboardDictation()
        _ = dictation.prepare(Self.a, canStart: true)
        dictation.appeared(Self.b, in: "field")
        _ = dictation.prepare(Self.b, canStart: true)
        #expect(dictation.place == Self.b)
        #expect(dictation.hidden(Self.a).isEmpty)
        #expect(dictation.place == Self.b)
        #expect(dictation.hidden(Self.b) == [.detach(Self.b)])
        #expect(dictation.place == nil)
    }

    @Test func aMemoryWarningNeverStopsAnotherKeyboardsRecording() {
        var dictation = Self.recording(in: Self.b)
        dictation.appeared(Self.a, in: "other")
        #expect(dictation.memoryWarning().isEmpty)
        #expect(dictation.recording?.keyboard == Self.b)
        #expect(dictation.hasCapture)

        let take = dictation.recording!.take
        _ = dictation.ended(take)
        #expect(dictation.memoryWarning() == [.letGoOfCapture])
        #expect(!dictation.hasCapture)
    }

    @Test func aMemoryWarningWhileWritingLetsParakeetGoAndKeepsTheWriting() {
        var dictation = Self.recording()
        let take = dictation.recording!.take
        _ = dictation.ended(take)
        let load = dictation.loadParakeet()
        let kept = dictation.finishedLoading(load)
        #expect(kept)
        #expect(dictation.memoryWarning() == [.letGoOfCapture, .letGoOfParakeet])
        #expect(dictation.parakeet == .unloaded)
        #expect(dictation.writing(in: Self.a) == [2])
        #expect(dictation.written(take, .words).contains(.type(take, in: Self.a)))
        #expect(dictation.model(picked: true, seconds: 2, room: Self.roomy) == .apple)
        dictation.appeared(Self.a, in: "field")
        #expect(dictation.model(picked: true, seconds: 2, room: Self.roomy) == .parakeet)
    }

    @Test func aLoadAMemoryWarningOvertookIsntKept() {
        var dictation = KeyboardDictation()
        let load = dictation.loadParakeet()
        #expect(dictation.loadParakeet() == load)
        #expect(dictation.memoryWarning() == [.letGoOfParakeet])
        let kept = dictation.finishedLoading(load)
        #expect(!kept)
        #expect(dictation.parakeet == .unloaded)
    }

    @Test func parakeetLoadsOnlyWithRoomForItsFirstLoad() {
        #expect(Self.room(limit: 177, left: 60).loads)
        #expect(!Self.room(limit: 177, left: 59).loads)
        #expect(!Self.room(limit: 130, left: 100).loads)
        #expect(KeyboardDictation.Room(limit: 0, available: 0).loads)
    }

    @Test func writingTakesRoomForTheRecording() {
        #expect(Self.room(limit: 177, left: 34).writes(20))
        #expect(!Self.room(limit: 177, left: 33).writes(20))
    }

    @Test func appleWritesWhatParakeetCantLoadForOrWrite() {
        let dictation = KeyboardDictation()
        #expect(dictation.model(picked: true, seconds: 10, room: Self.room(limit: 177, left: 80)) == .parakeet)
        #expect(dictation.model(picked: false, seconds: 10, room: Self.roomy) == .apple)
        #expect(dictation.model(picked: true, seconds: 10, room: Self.room(limit: 177, left: 40)) == .apple)
        var loaded = KeyboardDictation()
        let load = loaded.loadParakeet()
        let kept = loaded.finishedLoading(load)
        #expect(kept)
        #expect(loaded.model(picked: true, seconds: 10, room: Self.room(limit: 177, left: 40)) == .parakeet)
        #expect(loaded.model(picked: true, seconds: 40, room: Self.room(limit: 177, left: 40)) == .apple)
        #expect(loaded.parakeetWontFit() == [.letGoOfParakeet])
        #expect(loaded.parakeet == .unloaded)
    }

    @Test func anEncoderOnTheCPUSetsParakeetAsideForGood() {
        var dictation = KeyboardDictation()
        let load = dictation.loadParakeet()
        dictation.failedLoading(load, onCPU: true)
        #expect(dictation.parakeet == .setAside)
        #expect(dictation.model(picked: true, seconds: 2, room: Self.roomy) == .apple)
        dictation.appeared(Self.a, in: "field")
        #expect(dictation.memoryWarning().isEmpty)
        #expect(dictation.model(picked: true, seconds: 2, room: Self.roomy) == .apple)

        var failed = KeyboardDictation()
        failed.failedLoading(failed.loadParakeet(), onCPU: false)
        #expect(failed.parakeet == .unloaded)
        #expect(failed.model(picked: true, seconds: 2, room: Self.roomy) == .parakeet)
    }

    @Test func aDictationOutlivingItsKeyboardIsTypedInTheNextInItsField() {
        var dictation = Self.recording()
        let take = dictation.recording!.take
        #expect(dictation.hidden(Self.a) == [.stopCapture, .write(take), .changed(Self.a), .detach(Self.a)])
        dictation.appeared(Self.b, in: "field")
        #expect(dictation.written(take, .words) == [.type(take, in: Self.b), .leave(take, typed: true), .changed(Self.a)])
    }

    @Test func aDictationOutlivingItsKeyboardIsHeldForItsField() {
        var dictation = Self.recording()
        let take = dictation.recording!.take
        _ = dictation.ended(take)
        _ = dictation.hidden(Self.a)
        dictation.appeared(Self.b, in: "elsewhere")
        #expect(dictation.written(take, .words) == [.hold(take, in: "field"), .leave(take, typed: false), .changed(Self.a)])
    }

    @Test func aFingerOnTheMicAsTheKeyboardHidesRecordsNothing() {
        var dictation = KeyboardDictation()
        _ = dictation.prepare(Self.a, canStart: true)
        _ = dictation.arm(Self.a, in: "field", at: 0, canStart: true)
        let take = dictation.recording!.take
        #expect(dictation.hidden(Self.a) == [.stopCapture, .discard(take), .changed(Self.a), .detach(Self.a)])
    }

    @Test func aStartInAnotherKeyboardEndsTheOneLeftRecording() {
        var dictation = Self.recording(in: Self.a)
        let left = dictation.recording!.take
        dictation.appeared(Self.b, in: "field")
        let effects = dictation.start(Self.b, in: "field", at: 5, canStart: true)
        let take = dictation.recording!.take
        #expect(
            effects == [
                .stopCapture, .write(left), .changed(Self.a), .attach(Self.b), .readAudio(take), .watch(take), .changed(Self.b),
            ])
        #expect(dictation.recording?.keyboard == Self.b)
        #expect(dictation.due(left, at: 100).isEmpty)
        #expect(dictation.written(left, .words) == [.type(left, in: Self.b), .leave(left, typed: true), .changed(Self.a)])
    }

    @Test func aCutOffTakeWaitsForItsFieldThenGoesToTranscripts() {
        let held = [(field: "a", at: 100.0), (field: "b", at: 100.0), (field: "a", at: 60.0)]
        let next = KeyboardDictation.held(held, in: "a", at: 125)
        #expect(next.here == [0])
        #expect(next.kept == [1])
        #expect(next.expired)
        let later = KeyboardDictation.held(held, in: "c", at: 131)
        #expect(later.here.isEmpty && later.kept.isEmpty && later.expired)
    }

    @Test func soundIsCheckedOnlyPastASecond() {
        #expect(KeyboardDictation.sounded([Float](repeating: 0, count: 8000), sampleRate: 16000))
        #expect(!KeyboardDictation.sounded([Float](repeating: 0.001, count: 16000), sampleRate: 16000))
        #expect(KeyboardDictation.sounded([Float](repeating: 0.01, count: 16000), sampleRate: 16000))
    }
}
