import AVFoundation
import KeyboardStore

/// How the iPhone's own microphones hear a dictation, kept in its transcript (`scripts/voicehealth.py`).
public nonisolated enum Capture: String {
    /// Apple's voice processing, as a call, which heard dictations until Nov 7 and gave 19 of 436 no sound at all.
    case voiceProcessing
    /// A cardioid, which iOS forms from more than one of the microphones, on the front one, toward the face looking at
    /// the screen, in `.measurement` mode, which leaves its signal as heard: on one microphone the folded iPhone Duo
    /// upright lost seconds of speech at a time.
    case cardioid

    public var title: String {
        switch self {
        case .voiceProcessing: "Voice Processing"
        case .cardioid: "Front Cardioid"
        }
    }

    /// Aims the iPhone's microphones at you, a cardioid on the front one, while they're what hears and the iPhone offers
    /// one; else leaves iOS's own pick in `.default` mode. Returns `.cardioid` when it aimed them.
    @MainActor static func aim(_ session: AVAudioSession) throws -> Capture? {
        let port = session.availableInputs?.first { $0.portType == .builtInMic }
        let ownHears =
            (SettingsStore.microphone.map { $0.kind == .iPhone } ?? true)
            && session.currentRoute.inputs.allSatisfy { $0.portType == .builtInMic }
        let sources = port?.dataSources?.filter { $0.supportedPolarPatterns?.contains(.cardioid) == true } ?? []
        guard ownHears, let port, let source = sources.first(where: { $0.orientation == .front }) ?? sources.first
        else {
            try session.setMode(.default)
            return nil
        }
        try session.setMode(.measurement)
        for other in port.dataSources ?? [] where other != source && other.preferredPolarPattern != nil {
            try? other.setPreferredPolarPattern(nil)
        }
        try source.setPreferredPolarPattern(.cardioid)
        try port.setPreferredDataSource(source)
        return .cardioid
    }
}
