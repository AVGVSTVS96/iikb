import FluidAudio
import Foundation
import KeyboardStore

/// The speech model voice typing writes with, picked in Settings: one of NVIDIA's Parakeets, run on the Neural Engine by
/// FluidAudio and downloaded from Hugging Face once, or Apple's SpeechTranscriber. The pick is kept in `SettingsStore`,
/// so the keyboard writes with it too.
public nonisolated enum SpeechModel: String, CaseIterable, Sendable {
    case ultra, v3, apple

    @MainActor public static var picked: SpeechModel {
        get { SettingsStore.voiceModel.flatMap(SpeechModel.init) ?? .v3 }
        set { SettingsStore.voiceModel = newValue.rawValue }
    }

    public var title: String {
        switch self {
        case .ultra: "Parakeet Ultra"
        case .v3: "Parakeet v3"
        case .apple: "Apple"
        }
    }

    public var detail: String {
        switch self {
        case .v3: "Fast and accurate. Downloads once, about 500 MB."
        case .ultra:
            "A little more accurate. Each time iikb opens, it takes minutes to get ready and runs warm. With the mic off, the keyboard uses v3 if it's downloaded."
        case .apple: "Built into iOS."
        }
    }

    /// Loads in a moment once this install has compiled it, so iikb lets go of it between dictations, and the keyboard
    /// can load it to write a dictation down itself; Ultra's encoder never caches, so iikb keeps it.
    public var reloadsQuickly: Bool { self == .v3 }

    /// Where this Parakeet's files are, in the App Group (`AsrModelVersion.folder`); nil for Apple's.
    public var folder: URL? { version?.folder }

    public var version: AsrModelVersion? {
        switch self {
        case .ultra: .ultra
        case .v3: .v3
        case .apple: nil
        }
    }
}
