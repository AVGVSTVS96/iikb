package com.shahidy.iikb

import android.content.Context
import android.content.SharedPreferences
import com.shahidy.iikb.app.Core

/**
 * iikb's settings, kept under the names iOS's `SettingsStore` uses, with iikb's defaults where nothing is kept
 * (KeyboardSettings.initial). The app writes them and the keyboard, in the same process, hears each change.
 */
class Settings(context: Context) {
    val preferences: SharedPreferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    init {
        // Text Mode, a setting of its own until the style took its words, becomes the style it typed as, or stays
        // beside the style where none types the same.
        preferences.getString(TEXT_MODE, null)?.let { words ->
            val style = Core.style(lines() + "\n$TEXT_MODE=$words")
            if (style.isNotEmpty()) preferences.edit().putString("writingStyle", style).remove(TEXT_MODE).apply()
        }
    }

    fun bool(name: String) = preferences.getBoolean(name, DEFAULTS[name] == "true")

    fun string(name: String) = preferences.getString(name, null) ?: DEFAULTS[name] ?: ""

    fun set(name: String, value: Boolean) = preferences.edit().putBoolean(name, value).apply()

    /** A default style picked ends a Text Mode kept beside the one before. */
    fun set(name: String, value: String) {
        val edit = preferences.edit().putString(name, value)
        if (name == "writingStyle") edit.remove(TEXT_MODE)
        edit.apply()
    }

    /** The style each app has of its own, by package, kept as `package:style,…`; one not listed follows the default. */
    fun appStyles(): Map<String, String> = string(APP_STYLES).split(',').mapNotNull { pair ->
        pair.split(':', limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] }
    }.toMap()

    /** `style` for `app`, or null to have it follow the default again. */
    fun setAppStyle(app: String, style: String?) {
        val styles = appStyles().toMutableMap()
        if (style == null) styles.remove(app) else styles[app] = style
        set(APP_STYLES, styles.entries.joinToString(",") { "${it.key}:${it.value}" })
    }

    /** Every setting as `name=value` lines, as the engine reads them, with a Text Mode kept beside the style. */
    fun lines(): String = (DEFAULTS.keys.map { name ->
        val value = preferences.all[name]?.toString() ?: DEFAULTS.getValue(name)
        "$name=$value"
    } + listOfNotNull(preferences.getString(TEXT_MODE, null)?.let { "$TEXT_MODE=$it" })).joinToString("\n")

    companion object {
        private const val TEXT_MODE = "textMode"
        private const val APP_STYLES = "appWritingStyles"
        val DEFAULTS = mapOf(
            "autoCapitalization" to "false",
            "autoCorrection" to "false",
            "capsLock" to "true",
            "smartPunctuation" to "true",
            "periodShortcut" to "true",
            "predictiveText" to "true",
            "slideToType" to "true",
            "sound" to "true",
            "emojiKey" to "true",
            "micKey" to "false",
            "numberRow" to "false",
            "compactPanels" to "false",
            "theme" to "standard",
            "themeAppearance" to "automatic",
            "stopAnimation" to "squeeze",
            "characterPreviewStyle" to "attached",
            "hapticFeedback" to "standard",
            "keySpacing" to "standard",
            "keyRoundness" to "standard",
            "keyboardMenu" to "both",
            "clipboardLength" to "characters",
            "globe" to "spacer",
            "split" to "false",
            "oneHanded" to "off",
            "skinTone" to "",
            "writingStyle" to "casual",
            "dictationEditing" to "asSaid",
            "spokenLists" to "numbered",
            APP_STYLES to "",
            "micOn" to "true",
        )
    }
}
