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
    /// one; else leaves iOS's own pick in `.default` mode and throws `Unaimed`.
    @MainActor static func aim(_ session: AVAudioSession) throws -> Capture {
        let port = session.availableInputs?.first { $0.portType == .builtInMic }
        let ownHears =
            (SettingsStore.microphone.map { $0.kind == .iPhone } ?? true)
            && session.currentRoute.inputs.allSatisfy { $0.portType == .builtInMic }
        let sources = port?.dataSources?.filter { $0.supportedPolarPatterns?.contains(.cardioid) == true } ?? []
        guard ownHears, let port, let source = sources.first(where: { $0.orientation == .front }) ?? sources.first
        else {
            try session.setMode(.default)
            throw Unaimed(session: session, port: port)
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

/// The session as it was when the iPhone's microphones couldn't be aimed: what heard, and the iPhone's microphones with
/// the patterns each offered, kept in the transcript (`scripts/voicehealth.py`).
public nonisolated struct Unaimed: Error, CustomStringConvertible {
    public let description: String

    @MainActor init(session: AVAudioSession, port: AVAudioSessionPortDescription?) {
        let heard = session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: " ")
        let sources = port?.dataSources?.map { source in
            "\(source.dataSourceName) \((source.supportedPolarPatterns ?? []).map(\.rawValue).joined(separator: " "))"
        }
        description =
            "heard by \(heard.isEmpty ? "nothing" : heard); "
            + (sources.map { "built-in \($0.joined(separator: ", "))" } ?? "no built-in microphone")
            + (SettingsStore.microphone.map { "; picked \($0.kind)" } ?? "")
    }
}
