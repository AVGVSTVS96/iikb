import KeyboardArbiter
import OSLog
import UIKit

/// The app the keyboard is typing in, for sources, learning, suggestions and voice typing. iOS stopped telling keyboards since
/// 26.4, but the view controller still holds its host's process ID, and UIKit's keyboard arbiter, once switched on
/// (`KeyboardArbiter`), names the app it is serving with that app's process ID, sometimes an app you already left. So
/// each name is kept under its process ID, only until the keyboard next appears, when the host can change, and the host
/// is the name kept under the host's ID or none. Dictus found and measured this (getdictus/dictus-ios#538, MIT). None of
/// it is API: a missing step answers nil, and the App Store build (`APP_STORE`, ci_scripts/) leaves it all out.
enum KeyboardHost {
    #if APP_STORE
        static func appeared() {}
        static func harvest() {}
        static func app(of keyboard: UIInputViewController) -> String? { nil }
        static func returns(to app: String?, apps: [String]) -> Bool { true }
    #else
        private static var names: [Int: String] = [:]

        static func appeared() {
            names = [:]
            iikbEnableKeyboardArbiter()
            if let client, value(client, "connection") == nil,
                client.responds(to: NSSelectorFromString("startConnection"))
            {
                client.perform(NSSelectorFromString("startConnection"))
            }
            harvest()
        }

        /// Keeps the app the arbiter names now.
        static func harvest() {
            guard let state = client.flatMap({ value($0, "currentClientState") }) as? NSObject,
                let name = value(state, "sourceBundleIdentifier") as? String, !name.isEmpty,
                let id = (value(state, "processIdentifier") as? NSNumber)?.intValue, id > 0
            else { return }
            names[id] = name
        }

        static func app(of keyboard: UIInputViewController) -> String? {
            harvest()
            let id = (value(keyboard, "_hostProcessIdentifier") as? NSNumber)?.intValue ?? 0
            return names[id]
        }

        /// Whether iikb, opened to start the microphone, can bring you back to `app` as you left it. Only an app
        /// iOS can open comes back. A share sheet, a notification's reply, Spotlight, the screenshot editor or
        /// Photos' markup closes once you leave it, taking what you'd written or drawn, and nothing reopens it.
        /// A keyboard sees Apple's apps installed in LaunchServices and every other app, iikb's own included, not
        /// (measured on the Duo, Nov 8), so LaunchServices settles Apple's hosts, and a third-party one is an app
        /// unless it extends one of the `apps` you've typed in. None of it is API.
        static func returns(to app: String?, apps: [String]) -> Bool {
            guard let app else { return true }
            if let known = reopenable[app] { return known }
            let answer = app.hasPrefix("com.apple.") ? installed(app) ?? true : !isExtension(app, ofAny: apps)
            reopenable[app] = answer
            log.notice("\(app, privacy: .public) \(answer ? "can" : "can't", privacy: .public) be reopened")
            return answer
        }

        private static var reopenable: [String: Bool] = [:]
        private static let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

        private static func installed(_ id: String) -> Bool? {
            let selector = NSSelectorFromString("applicationProxyForIdentifier:")
            guard let type = NSClassFromString("LSApplicationProxy") as AnyObject?, type.responds(to: selector),
                let proxy = type.perform(selector, with: id)?.takeUnretainedValue() as? NSObject
            else { return nil }
            return value(proxy, "isInstalled") as? Bool
        }

        private static var client: NSObject? {
            let shared = NSSelectorFromString("automaticSharedArbiterClient")
            guard let type = NSClassFromString("_UIKeyboardArbiterClient") as AnyObject?, type.responds(to: shared)
            else { return nil }
            return type.perform(shared)?.takeUnretainedValue() as? NSObject
        }

        private static func value(_ object: NSObject, _ key: String) -> Any? {
            object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
        }
    #endif

    /// Apple has an extension's bundle ID start with its app's and a dot, so a host that extends one of `apps` is that
    /// app's share sheet or another of its extensions.
    static func isExtension(_ host: String, ofAny apps: [String]) -> Bool {
        apps.contains { host.hasPrefix($0 + ".") }
    }
}
