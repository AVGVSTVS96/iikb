package com.shahidy.iikb.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.shahidy.iikb.Settings

val LocalStore = staticCompositionLocalOf<Store> { error("no store") }

/** The settings as Compose reads them: each change redraws the pages that show it. */
class Store(private val settings: Settings) {
    private var revision by mutableIntStateOf(0)

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

    fun set(name: String, value: Boolean) {
        when (name) {
            "haptics.on" -> settings.set("hapticFeedback", if (value) string("haptics.strength") else "off")
            else -> settings.set(name, value)
        }
        revision++
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
        revision++
    }

    fun themeTitle() = THEMES.firstOrNull { it.first == string("theme") }?.second ?: "Default"

    /** The keyboard reads the token and starts over from nothing. */
    fun resetMemory() {
        settings.set("memoryResets", (settings.preferences.getString("memoryResets", "0")!!.toInt() + 1).toString())
    }
}
