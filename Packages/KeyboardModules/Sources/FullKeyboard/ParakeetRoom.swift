import VoiceCore

/// Whether Parakeet fits beside the keyboard, from its memory limit and what's left of it in bytes (`KeyboardMemory`),
/// 0 where iOS doesn't say. The Neural Engine's copy of the model is outside what iOS counts; what counts, measured in
/// Hex's keyboard on an iPhone 17 Pro under a 177 MB limit (its `KeyboardParakeetBudget`, Nov 22):
/// - a keyboard with Parakeet loaded records at up to 91 MB;
/// - a transcription rises 16 MB over the recording, and FluidAudio holds the whole recording, 0.42 MB a second;
/// - a first load, compiling, rises 42 MB.
/// So Parakeet takes a limit of 131 MB (91 and 16, with 24 to spare), 60 MB left to load (42, Silero's 2 beside it, and
/// 16 to spare), and 24 MB with 0.5 MB a second of sound to write. Our load also writes a second of silence to see the
/// encoder is on the Neural Engine, a transcription's rise, which comes after the load's and fits in the same room.
nonisolated struct ParakeetRoom: Equatable {
    var limit: Int
    var available: Int

    static let megabyte = 1_048_576
    static let limitNeeded = 131
    static let toLoad = 60.0

    static func toWrite(_ seconds: Double) -> Double { 24 + seconds / 2 }

    static var now: ParakeetRoom { ParakeetRoom(limit: KeyboardMemory.limit, available: KeyboardMemory.available) }

    var fitsKeyboard: Bool { limit == 0 || limit >= Self.limitNeeded * Self.megabyte }

    func fits(_ megabytes: Double) -> Bool { available == 0 || Double(available) >= megabytes * Double(Self.megabyte) }

    var loads: Bool { fitsKeyboard && fits(Self.toLoad) }

    func writes(_ seconds: Double) -> Bool { fitsKeyboard && fits(Self.toWrite(seconds)) }

    var described: String { "\(available >> 20) MB left of \(limit >> 20)" }

    /// The model `seconds` of sound is written with: Parakeet v3 for a Parakeet picked, unless this keyboard set it aside
    /// (its encoder ran on the CPU), or it isn't loaded and can't be (no room, or a memory warning since the keyboard
    /// last showed), or there's no room to write; else Apple's, whose model iOS runs outside the keyboard's memory.
    func model(picked: SpeechModel, seconds: Double, loaded: Bool, setAside: Bool, warned: Bool) -> SpeechModel {
        guard picked != .apple, !setAside, loaded || !warned && loads, writes(seconds) else { return .apple }
        return .v3
    }
}
