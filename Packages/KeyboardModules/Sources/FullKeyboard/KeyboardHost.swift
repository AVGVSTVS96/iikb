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
            probeLaunchServices()
        }

        private static var probed = false

        /// What LaunchServices tells a keyboard about apps and the hosts that aren't apps, logged once per keyboard,
        /// to learn whether the keyboard can tell them apart before it leaves one to start the microphone.
        private static func probeLaunchServices() {
            guard !probed else { return }
            probed = true
            let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")
            let selector = NSSelectorFromString("applicationProxyForIdentifier:")
            guard let proxies = NSClassFromString("LSApplicationProxy") as AnyObject?, proxies.responds(to: selector)
            else {
                return log.notice("probe: no LSApplicationProxy")
            }
            for id in [
                "com.shahidy.iikb", "ph.telegra.Telegraph", "net.whatsapp.WhatsApp", "com.apple.MobileSMS",
                "com.apple.mobilesafari", "ph.telegra.Telegraph.Share",
                "com.apple.MobileSMS.MessagesNotificationExtension",
                "com.apple.mobilesms.compose", "com.apple.springboard", "com.apple.ScreenshotServicesService",
                "com.apple.PaperKit.MarkupPhotoEditingExtension", "com.apple.SafariViewService", "com.example.none",
            ] {
                guard let proxy = proxies.perform(selector, with: id)?.takeUnretainedValue() as? NSObject else {
                    log.notice("probe \(id, privacy: .public): no proxy")
                    continue
                }
                let keys = [
                    "isInstalled", "appTags", "isLaunchProhibited", "applicationType", "isPlaceholder", "bundleType",
                ]
                let found = keys.map { "\($0)=\(String(describing: value(proxy, $0)))" }.joined(separator: " ")
                let bundle = NSSelectorFromString("bundleProxyForIdentifier:")
                let kind =
                    (NSClassFromString("LSBundleProxy") as AnyObject?).flatMap {
                        $0.responds(to: bundle) ? $0.perform(bundle, with: id)?.takeUnretainedValue() : nil
                    }.map { String(describing: Swift.type(of: $0)) } ?? "none"
                log.notice(
                    "probe \(id, privacy: .public): \(Swift.type(of: proxy), privacy: .public) bundle \(kind, privacy: .public) \(found, privacy: .public)"
                )
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
