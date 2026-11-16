import AudioToolbox
import KeyboardUI
import UIKit

/// Apple's key sounds, a sound for each kind of key (`KeyHaptics.Kind.sound`), while Keyboard Feedback › Sound is on
/// in iOS Settings, as Apple's keyboard plays them. Like Apple's, the system sounds stay quiet with the ring switch off.
struct KeyClicks {
    /// iOS's setting, nil when iOS keeps its sound settings from the keyboard: then UIKit's one click, which follows the
    /// setting by itself, plays for every key.
    private var systemSetting: Bool?

    /// Read as the keyboard appears, since the setting changes only in Settings, away from the keyboard.
    mutating func refresh() {
        let domain = "com.apple.preferences.sounds" as CFString
        let keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
        systemSetting =
            keys?.isEmpty == false
            ? CFPreferencesCopyAppValue("keyboard-audio" as CFString, domain) as? Bool ?? true : nil
    }

    @MainActor func play(_ kind: KeyHaptics.Kind) {
        switch systemSetting {
        case true?: AudioServicesPlaySystemSound(kind.sound)
        case false?: break
        case nil: UIDevice.current.playInputClick()
        }
    }
}
