import Foundation

/// The pieces of the app's KeyboardStore that `Parakeet.swift` and `SpeechModel.swift` read, beside `Recording.swift`.
/// The bench has no App Group, so its Parakeets load from FluidAudio's own folder, and no settings, so nothing is picked.
public enum AppGroup {
    public static let library: URL? = nil
}

@MainActor public enum SettingsStore {
    public static var voiceModel: String?
}
