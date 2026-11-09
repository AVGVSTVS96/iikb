package com.shahidy.iikb

import android.content.Context
import android.content.SharedPreferences

/**
 * iikb's settings, kept under the names iOS's `SettingsStore` uses, with iikb's defaults where nothing is kept
 * (KeyboardSettings.initial). The app writes them and the keyboard, in the same process, hears each change.
 */
class Settings(context: Context) {
    val preferences: SharedPreferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    fun bool(name: String) = preferences.getBoolean(name, DEFAULTS[name] == "true")

    fun string(name: String) = preferences.getString(name, null) ?: DEFAULTS[name] ?: ""

    fun set(name: String, value: Boolean) = preferences.edit().putBoolean(name, value).apply()

    fun set(name: String, value: String) = preferences.edit().putString(name, value).apply()

    /** Every setting as `name=value` lines, as the engine reads them. */
    fun lines(): String = DEFAULTS.keys.joinToString("\n") { name ->
        val value = preferences.all[name]?.toString() ?: DEFAULTS.getValue(name)
        "$name=$value"
    }

    companion object {
        val DEFAULTS = mapOf(
            "autoCapitalization" to "false",
            "autoCorrection" to "false",
            "capsLock" to "true",
            "smartPunctuation" to "true",
            "periodShortcut" to "true",
            "predictiveText" to "true",
            "slideToType" to "true",
            "sound" to "false",
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
            "textMode" to "spelledOut",
        )
    }
}
