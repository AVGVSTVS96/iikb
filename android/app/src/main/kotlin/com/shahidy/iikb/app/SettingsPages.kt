package com.shahidy.iikb.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.Settings

@Composable
fun SettingsList(open: (String) -> Unit) {
    Page("Settings") {
        Section("Keyboard") {
            Link("Appearance", value = LocalStore.current.themeTitle()) { open("appearance") }
            Divider()
            Link("Typing") { open("typing") }
            Divider()
            Link("Sound & Haptics") { open("feel") }
        }
        Section("Voice Typing") {
            Link("Writing Style") { open("style") }
        }
        Section("iikb") {
            Link("Privacy & Data") { open("privacy") }
            Divider()
            Link("About iikb") { open("about") }
        }
    }
}

@Composable
fun SettingsPage(page: String, back: () -> Unit) {
    when (page) {
        "appearance" -> Page("Appearance", back) { Appearance() }
        "typing" -> Page("Typing", back) { Typing() }
        "feel" -> Page("Sound & Haptics", back) { Feel() }
        "style" -> Page("Writing Style", back) { Style() }
        "privacy" -> Page("Privacy & Data", back) { Privacy() }
        else -> Page("About iikb", back) { About() }
    }
}

@Composable
private fun Appearance() {
    val store = LocalStore.current
    Section("Theme") {
        Choices(
            "theme", THEMES,
            mapOf(
                "standard" to "iikb’s own keys, flat.",
                "clear" to "Only the letters, no keys around them.",
                "physical" to "Solid keys, dark or light.",
                "mechanical" to "Raised keycaps you can almost press.",
                "classic" to "The glossy keyboard of 2011.",
            ),
        )
    }
    if (store.string("theme") in setOf("physical", "mechanical")) {
        Section("Keys") {
            Choices("themeAppearance", listOf("automatic" to "Automatic", "dark" to "Dark", "light" to "Light"))
        }
    }
    Section("Character Preview") {
        Choices("characterPreviewStyle", listOf("none" to "None", "detached" to "Detached", "attached" to "Attached"))
    }
    Section("Size and Shape") {
        Stops("Key Spacing", "keySpacing", SPACING, "Bigger Keys", "More Space")
        Divider()
        Stops("Key Roundness", "keyRoundness", ROUNDNESS, "Sharper", "Rounder")
    }
    Section("Keys") {
        Toggle("Number Row", "numberRow")
        Divider()
        Toggle("Emoji Key", "emojiKey")
    }
    Section("One-Handed Keyboard") {
        Choices("oneHanded", listOf("off" to "Off", "left" to "Left", "right" to "Right"))
    }
    Section("Skin Tone") {
        Choices(
            "skinTone",
            listOf(
                "" to "👋 None", "light" to "👋🏻 Light", "mediumLight" to "👋🏼 Medium Light", "medium" to "👋🏽 Medium",
                "mediumDark" to "👋🏾 Medium Dark", "dark" to "👋🏿 Dark",
            ),
        )
    }
    Section("Keyboard Menu", "Where the menu of layouts and iikb Settings opens.") {
        Choices("keyboardMenu", listOf("both" to "Both", "hold" to "Hold 123", "button" to "Menu Button"))
    }
}

@Composable
private fun Typing() {
    Section {
        Toggle("Auto-Capitalization", "autoCapitalization")
        Divider()
        Toggle("Auto-Correction", "autoCorrection")
        Divider()
        Toggle("Predictive Text", "predictiveText")
        Divider()
        Toggle("Slide to Type", "slideToType")
    }
    Section {
        Toggle("Smart Punctuation", "smartPunctuation")
        Divider()
        Toggle("Enable Caps Lock", "capsLock")
        Divider()
        Toggle("\".\" Shortcut", "periodShortcut", "Double-tap the space bar for a period")
    }
}

@Composable
private fun Feel() {
    val store = LocalStore.current
    Section {
        Toggle("Key Haptics", "haptics.on")
        if (store.bool("haptics.on")) {
            Divider()
            Stops("Strength", "haptics.strength", HAPTICS, "Lightest", "Strongest")
        }
    }
    Section {
        Toggle("Sound", "sound")
    }
}

@Composable
private fun Style() {
    Section("Style") {
        Choices(
            "writingStyle",
            listOf("formal" to "Formal.", "casual" to "Casual", "veryCasual" to "very casual", "excited" to "Excited!"),
            mapOf(
                "formal" to "Every comma, every period",
                "casual" to "No period at the end",
                "veryCasual" to "Casual, in lowercase",
                "excited" to "Formal, ending with !",
            ),
        )
    }
    Section("Editing") {
        Choices(
            "dictationEditing", listOf("asSaid" to "As Said", "light" to "Light", "clean" to "Clean"),
            mapOf(
                "asSaid" to "Every word you say",
                "light" to "Leaves out um and uh",
                "clean" to "Also what you take back and repeat",
            ),
        )
    }
    Section("Lists") {
        Choices("spokenLists", listOf("numbered" to "Numbered", "bulleted" to "Bulleted", "off" to "Off"))
    }
    Section("Text Mode") {
        Choices(
            "textMode",
            listOf("spelledOut" to "Spelled Out", "abbreviated" to "Abbreviated", "texting" to "Texting", "genZ" to "Gen Z"),
        )
    }
}

@Composable
private fun Privacy() {
    val store = LocalStore.current
    var reset by remember { mutableStateOf(false) }
    Section(footer = "Everything iikb learns stays on this phone. Voice typing uses Android's speech recognizer, on the phone where it can.") {
        Line(
            if (reset) "Learned words and taps reset" else "Reset Learned Words and Taps",
            onClick = {
                store.resetMemory()
                reset = true
            },
        )
    }
}

@Composable
private fun About() {
    val palette = palette()
    Section {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("iikb", color = palette.label, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Text(
                "The keyboard iikb builds for iPhone, on Android: the same typing engine, autocorrect, predictions, " +
                    "swipe and emoji search. Open source under MIT.",
                color = palette.secondary, fontSize = 15.sp,
            )
            Text("github.com/AVGVSTVS96/iikb", color = palette.accent, fontSize = 15.sp)
        }
    }
}

val THEMES = listOf(
    "standard" to "Default", "clear" to "Clear", "physical" to "Physical", "mechanical" to "Mechanical",
    "classic" to "iOS 5",
)
val SPACING = listOf("tighter", "tight", "standard", "roomy", "roomier")
val ROUNDNESS = listOf("sharper", "sharp", "standard", "round", "rounder")
val HAPTICS = listOf("lightest", "lighter", "light", "standard", "strong", "stronger", "strongest")
