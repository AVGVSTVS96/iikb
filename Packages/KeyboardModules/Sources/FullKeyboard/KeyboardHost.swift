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
        static func returns(to app: String?) -> Bool { true }
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
            if !probed {
                probed = true
                DispatchQueue.global(qos: .utility).async { probeExtensions() }
            }
        }

        private static var probed = false

        /// Whether iOS's extension registry answers a keyboard, logged once per keyboard, to learn whether it can tell
        /// a third-party app from its share sheet, which LaunchServices hides from a keyboard alike.
        nonisolated private static func probeExtensions() {
            let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")
            func value(_ object: NSObject, _ key: String) -> Any? {
                object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
            }
            let ids = [
                "ph.telegra.Telegraph.Share", "ph.telegra.Telegraph", "com.shahidy.iikb.keyboard", "com.shahidy.iikb",
                "me.proton.pass.ios.autofill", "com.apple.MobileSMS.MessagesNotificationExtension", "com.example.none",
            ]
            for id in ids {
                var found = "registry n/a"
                let lookup = NSSelectorFromString("extensionWithIdentifier:error:")
                if let type = NSClassFromString("NSExtension") as? NSObject.Type, type.responds(to: lookup) {
                    typealias Lookup = @convention(c) (AnyObject, Selector, NSString, NSErrorPointer) -> AnyObject?
                    var error: NSError?
                    let made = unsafeBitCast(type.method(for: lookup), to: Lookup.self)(
                        type, lookup, id as NSString, &error)
                    found =
                        "registry \(made.map { String(describing: Swift.type(of: $0)) } ?? "none") \(error?.code ?? 0)"
                }
                let plugin = NSSelectorFromString("pluginKitProxyForIdentifier:")
                let proxy = (NSClassFromString("LSPlugInKitProxy") as AnyObject?).flatMap {
                    $0.responds(to: plugin) ? $0.perform(plugin, with: id)?.takeUnretainedValue() as? NSObject : nil
                }
                let pluginFound =
                    proxy.map {
                        "plugin \(String(describing: value($0, "bundleIdentifier"))) in \(String(describing: value($0, "containingBundle").map { ($0 as? NSObject).flatMap { value($0, "bundleIdentifier") } }))"
                    } ?? "plugin none"
                log.notice(
                    "probe \(id, privacy: .public): \(found, privacy: .public), \(pluginFound, privacy: .public)")
            }
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
        /// LaunchServices tells the two apart only for Apple's: a keyboard sees Apple's apps installed and every
        /// other app, iikb's own included, not (measured on the Duo, Nov 8). None of it is API.
        static func returns(to app: String?) -> Bool {
            guard let app, app.hasPrefix("com.apple.") else { return true }
            if let known = reopenable[app] { return known }
            let answer = installed(app) ?? true
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
}
