import Foundation

/// Links into iikb's app.
public enum AppLink {
    /// Opens Settings › Apps › iikb, where Full Access (under Keyboards) and Paste from Other Apps are.
    public static let settings = URL(string: "iikb://settings")!
    /// Opens iikb's app on its keyboard settings.
    public static let keyboard = URL(string: "iikb://keyboard")!
    /// Opens iikb with its microphone on, from Control Center's iikb Mic.
    public static let mic = URL(string: "iikb://mic")!
}
