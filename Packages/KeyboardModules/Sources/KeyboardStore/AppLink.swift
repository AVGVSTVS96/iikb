import Foundation

/// Links into iikb's app.
public enum AppLink {
    /// Opens Settings › Apps › iikb, where Full Access (under Keyboards) and Paste from Other Apps are.
    public static let settings = URL(string: "iikb://settings")!
    /// Opens iikb's app on its keyboard settings.
    public static let keyboard = URL(string: "iikb://keyboard")!
    /// Opens iikb's app on its Appearance settings, from the keyboard menu's Theme and Stop Animation.
    public static let appearance = URL(string: "iikb://keyboard/appearance")!
    /// Opens iikb with its microphone on, from Control Center's iikb Mic.
    public static let mic = URL(string: "iikb://mic")!

    /// Opens iikb to ask iOS for access to your photos, which the keyboard's Chats shares, then reopens `back`, the app
    /// you were typing in.
    public struct Photos: Equatable, Sendable {
        public var back: String?

        public init(back: String?) {
            self.back = back
        }

        public init?(_ link: URL) {
            guard link.scheme == "iikb", link.host() == "photos" else { return nil }
            back =
                URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "back" }?.value
        }

        public var url: URL {
            let link = URL(string: "iikb://photos")!
            return back.map { link.appending(queryItems: [URLQueryItem(name: "back", value: $0)]) } ?? link
        }
    }
}
