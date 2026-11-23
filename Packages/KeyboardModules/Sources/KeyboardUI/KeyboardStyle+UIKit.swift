import KeyboardCore
import UIKit

extension KeyboardStyle {
    /// The system keyboard's look on this iOS, which sizes and colors follow.
    nonisolated public static var current: KeyboardStyle {
        if #available(iOS 27, *) { .ios27 } else { .ios26 }
    }
}

extension KeyboardTheme {
    package static let lightCurrent = KeyboardTheme.light(.current)
    static let darkCurrent = KeyboardTheme.dark(.current)

    static func current(for traits: UITraitCollection) -> KeyboardTheme {
        traits.userInterfaceStyle == .dark ? darkCurrent : lightCurrent
    }

    public static func current(for traits: UITraitCollection, settings: KeyboardSettings) -> KeyboardTheme {
        named(
            settings.theme, appearance: settings.themeAppearance, dark: traits.userInterfaceStyle == .dark,
            style: .current)
    }
}

extension RGBA {
    package var ui: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
}
