import KeyboardStore
import SwiftUI
import UIKit

/// What iOS keeps for iikb in Settings › Apps › iikb, read again whenever iikb comes forward, as it does when you come back
/// from Settings.
@Observable final class AppStatus {
    static let shared = AppStatus()

    private(set) var isAdded = false
    private(set) var fullAccess = false
    private(set) var pasteAllowed = false

    var isSetUp: Bool { isAdded && fullAccess && pasteAllowed }

    #if !APP_STORE
        private let clipboard = ClipboardStore()
    #endif

    private init() {
        #if !APP_STORE
            clipboard.onChange = { [weak self] in self?.readPaste() }
        #endif
        refresh()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppStatus.shared.refresh() }
        }
    }

    func refresh() {
        isAdded = (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] ?? []).contains(
            "com.shahidy.iikb.keyboard")
        #if APP_STORE
            // TCC isn't API: the keyboard can write the shared clipboard history only with Full Access.
            fullAccess = ClipboardStore().started
            pasteAllowed = fullAccess
        #else
            fullAccess = Self.allowed("kTCCServiceKeyboardNetwork")
            readPaste()
            clipboard.reload()
        #endif
    }

    #if !APP_STORE
        /// TCC grants the app Paste from Other Apps at Ask as at Allow, since the app itself can ask; the keyboard can't,
        /// so at Ask iOS refuses its reads, which the clipboard history keeps (`ClipboardStore.refused`).
        private func readPaste() {
            pasteAllowed = Self.allowed("kTCCServicePasteboard") && !clipboard.refused
        }

        /// Asks TCC, where iOS keeps privacy switches, through its private `TCCAccessPreflight`. iOS files the keyboard's Full
        /// Access under the app.
        private static func allowed(_ service: String) -> Bool {
            typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
            guard let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY),
                let preflight = dlsym(tcc, "TCCAccessPreflight")
            else { return false }
            return unsafeBitCast(preflight, to: Preflight.self)(service as CFString, nil) == 0
        }
    #endif

    static func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }

    /// iOS lists Paste from Other Apps under Settings › Apps › iikb only once the app itself has asked to paste; the
    /// keyboard's reads are refused without asking, so a fresh install never shows it. Reading the clipboard here asks.
    static func openPasteSetting() {
        #if APP_STORE
            if !shared.pasteAllowed { _ = UIPasteboard.general.string }
        #else
            if !allowed("kTCCServicePasteboard") { _ = UIPasteboard.general.string }
        #endif
        openSettings()
    }
}
