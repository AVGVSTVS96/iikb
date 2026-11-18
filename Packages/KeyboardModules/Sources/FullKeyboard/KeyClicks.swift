import AudioToolbox
import KeyboardUI
import UIKit

/// Apple's key sounds, a sound for each kind of key (`KeyHaptics.Kind.sound`), while Keyboard Feedback › Sound is on
/// in iOS Settings, as Apple's keyboard plays them. Like Apple's, the system sounds stay quiet with the ring switch off.
struct KeyClicks {
    private var isOn = true

    /// The setting read as UIKit's own `playInputClick` reads it in a keyboard (`IsSystemSoundEnabled` in UIKitCore):
    /// on unless set off. Read as the keyboard appears, since it changes only in Settings, away from the keyboard.
    mutating func refresh() {
        var isSet: DarwinBoolean = false
        let value = CFPreferencesGetAppBooleanValue(
            "keyboard-audio" as CFString, "com.apple.preferences.sounds" as CFString, &isSet)
        isOn = value || !isSet.boolValue
        TouchTrace.shared.mark("key sounds \(isSet.boolValue ? (value ? "on" : "off") : "unset")")
    }

    func play(_ kind: KeyHaptics.Kind) {
        if isOn { AudioServicesPlaySystemSound(kind.sound) }
    }
}
