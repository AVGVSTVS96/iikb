import CJNI
import KeyboardCore

/// A theme's A and B keys as the menu's Theme row and the app's Appearance page show each choice (`KeycapSwatchView`):
/// painted as the theme paints them, A light and B dark for Physical and Mechanical on Automatic.
struct Swatch: Encodable {
    var themes: [Theme]
    var look: Look
}

@_cdecl("Java_com_shahidy_iikb_keyboard_Native_swatch")
public func swatch(env: Env, _: jclass, name: jbyteArray?, appearance: jbyteArray?, dark: jboolean) -> jbyteArray? {
    let theme = ThemeName(rawValue: env.string(name) ?? "") ?? .standard
    let appearance = ThemeAppearance(rawValue: env.string(appearance) ?? "") ?? .automatic
    let split = theme.hasAppearance && appearance == .automatic
    let themes = [false, true].map { second in
        let darkKey = split ? second : dark != 0
        return KeyboardTheme.named(
            theme, appearance: split ? (darkKey ? .dark : .light) : appearance, dark: darkKey, style: .ios27)
    }
    var metrics = KeyboardMetrics.phone(width: 390, style: .ios27)
    if let shape = themes[0].keyShape { metrics.cornerRadius = shape.cornerRadius(letterWidth: 44) }
    return env.array(Json.encode(Swatch(themes: themes.map(Theme.init), look: Look(metrics, shape: themes[0].keyShape, style: .ios27))))
}
