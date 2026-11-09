package com.shahidy.iikb.app

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.shahidy.iikb.Settings

val LocalStore = staticCompositionLocalOf<Store> { error("no store") }

/**
 * The settings as Compose reads them: each change redraws the pages that show it, whether the app made it or the
 * keyboard's menu did, as the open iPhone Duo shows the menu's picks beside the keys.
 */
class Store(val settings: Settings) {
    private var revision by mutableIntStateOf(0)

    /**
     * Hears each change until the returned stop runs. SharedPreferences holds its listeners weakly, so the stop, kept
     * by the caller, is what keeps this one alive; a field read only in `init` is one R8 removes.
     */
    fun listen(): () -> Unit {
        val changed = SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> revision++ }
        settings.preferences.registerOnSharedPreferenceChangeListener(changed)
        return { settings.preferences.unregisterOnSharedPreferenceChangeListener(changed) }
    }

    fun bool(name: String): Boolean {
        revision
        return when (name) {
            "haptics.on" -> settings.string("hapticFeedback") != "off"
            else -> settings.bool(name)
        }
    }

    fun string(name: String): String {
        revision
        return when (name) {
            "haptics.strength" -> settings.preferences.getString("hapticStrength", null) ?: "standard"
            else -> settings.string(name)
        }
    }

    /** What `read` gives from the settings' file, read again after each change to it. */
    fun <T> watch(read: () -> T): T {
        revision
        return read()
    }

    /** Every setting as the engine reads them, read again after each change. */
    fun lines(): String {
        revision
        return settings.lines()
    }

    fun set(name: String, value: Boolean) {
        when (name) {
            "haptics.on" -> settings.set("hapticFeedback", if (value) string("haptics.strength") else "off")
            else -> settings.set(name, value)
        }
    }

    /** Haptic Feedback keeps its strength while it's off, as iOS's Strength slider does. */
    fun set(name: String, value: String) {
        when (name) {
            "haptics.strength" -> {
                settings.set("hapticStrength", value)
                settings.set("hapticFeedback", value)
            }
            else -> settings.set(name, value)
        }
    }

    fun title(name: String, choices: List<Pair<String, String>>) =
        choices.firstOrNull { it.first == string(name) }?.second ?: choices.first().second

    /** The keyboard reads the token and starts over from nothing. */
    fun resetMemory() {
        settings.set("memoryResets", (settings.preferences.getString("memoryResets", "0")!!.toInt() + 1).toString())
    }
}
