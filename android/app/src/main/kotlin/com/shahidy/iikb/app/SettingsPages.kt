package com.shahidy.iikb.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.Transcripts
import com.shahidy.iikb.Vocabulary
import com.shahidy.iikb.keyboard.Clips
import com.shahidy.iikb.voice.VoiceModel
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Every settings page, by the name the app and the keyboard open it with, under the Settings list's three sections. */
enum class SettingsPage(val title: String, val symbol: String, val hue: Color) {
    APPEARANCE("Appearance", "paintpalette.fill", Hues.purple),
    TYPING("Typing", "character.cursor.ibeam", Hues.cyan),
    FEEDBACK("Sound & Haptics", "hand.tap.fill", Hues.pink),
    VOICE("Voice", "waveform", Hues.red),
    WRITING("Writing Style", "textformat", Hues.orange),
    DICTIONARY("Dictionary", "character.book.closed.fill", Hues.brown),
    ACCESS("Keyboard Access", "switch.2", Hues.indigo),
    PRIVACY("Privacy & Data", "hand.raised.fill", Hues.blue),
    CHANGELOG("Changelog", "clock.arrow.circlepath", Hues.orange),
    ABOUT("About iikb", "info", Hues.gray);

    val id get() = name.lowercase()

    /** What the page is set to, beside it in the list and on Home's card for it. */
    @Composable
    fun value(): String? {
        val store = LocalStore.current
        return when (this) {
            APPEARANCE -> store.title("theme", THEMES)
            TYPING -> if (store.bool("autoCorrection")) "Auto-Correction On" else "Auto-Correction Off"
            FEEDBACK -> if (store.bool("haptics.on")) store.title("haptics.strength", HAPTICS) else "Off"
            VOICE -> VoiceModel.of(LocalContext.current).pickedShown.title
            WRITING -> store.title("writingStyle", STYLES)
            DICTIONARY -> Vocabulary.terms().size.let { if (it == 1) "1 word" else "$it words" }
            ACCESS -> if (LocalAccess.current.setup.done) "All Set" else "Needs Setup"
            PRIVACY, CHANGELOG -> null
            ABOUT -> version(LocalContext.current)
        }
    }

    companion object {
        val sections = listOf(
            "Keyboard" to listOf(APPEARANCE, TYPING, FEEDBACK),
            "Voice Typing" to listOf(VOICE, WRITING, DICTIONARY),
            "iikb" to listOf(ACCESS, PRIVACY, CHANGELOG, ABOUT),
        )

        fun of(id: String) = entries.firstOrNull { it.id == id }
    }
}

/** "Version 0.1.900 (900)", as iOS shows its version and build. */
private fun version(context: Context): String {
    val info = context.packageManager.getPackageInfo(context.packageName, 0)
    return "Version ${info.versionName} (${info.longVersionCode})"
}

/** Android's setup as MainActivity last read it, and the screens that change it. */
class Access(val setup: Setup, val enable: () -> Unit, val pick: () -> Unit, val microphone: () -> Unit)

val LocalAccess = compositionLocalOf<Access> { error("no access") }

/** One list, as iOS Settings and Raycast's settings are: each row a glyph, a title and what it's set to. */
@Composable
fun SettingsList(open: (String) -> Unit) {
    Page("Settings") {
        for ((header, pages) in SettingsPage.sections) {
            Section(header) {
                pages.forEachIndexed { index, page ->
                    if (index > 0) Divider()
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { open(page.id) }
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Glyph(page.symbol, page.hue)
                        Text(page.title, color = palette().label, fontSize = Type.body, modifier = Modifier.weight(1f), maxLines = 1)
                        page.value()?.let { Text(it, color = palette().secondary, fontSize = Type.body, maxLines = 1) }
                        Trailing("chevron.right")
                    }
                }
            }
        }
    }
}

/** A settings page on its own, the keyboard's each over iikb drawn as it will look. */
@Composable
fun SettingsPage(id: String, back: () -> Unit) {
    val page = SettingsPage.of(id) ?: SettingsPage.APPEARANCE
    Page(page.title, back) {
        if (page in SettingsPage.sections.first().second) TryPreview()
        when (page) {
            SettingsPage.APPEARANCE -> Appearance()
            SettingsPage.TYPING -> Typing()
            SettingsPage.FEEDBACK -> Feedback()
            SettingsPage.VOICE -> Voice()
            SettingsPage.WRITING -> WritingStyle()
            SettingsPage.DICTIONARY -> Dictionary()
            SettingsPage.ACCESS -> KeyboardAccess()
            SettingsPage.PRIVACY -> Privacy()
            SettingsPage.CHANGELOG -> Changelog()
            SettingsPage.ABOUT -> About()
        }
    }
}

/**
 * Android's steps for a keyboard, where iOS keeps three switches: turned on in its keyboard settings, picked as the
 * keyboard, and the microphone allowed. An Android keyboard reads the clipboard and goes online on its own, so there's
 * no Full Access or Paste from Other Apps.
 */
@Composable
fun SetupSteps() {
    val access = LocalAccess.current
    SetupStep(
        access.setup.enabled, "Turn on iikb",
        if (access.setup.enabled) "iikb is one of your keyboards." else "Turn it on in Android’s keyboard settings.",
        access.enable,
    )
    Divider()
    SetupStep(access.setup.picked, "Switch to iikb", "Pick iikb as the keyboard you type with.", access.pick)
    Divider()
    SetupStep(access.setup.microphone, "Allow the Microphone", "For voice typing, right in the keyboard.", access.microphone)
}

@Composable
private fun SetupStep(done: Boolean, title: String, detail: String, open: () -> Unit) {
    val palette = palette()
    Row(
        Modifier.clickable(onClick = open).row(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(
            Symbols[if (done) "checkmark.circle.fill" else "circle"], null,
            tint = if (done) palette.green else palette.secondary, modifier = Modifier.size(26.dp),
        )
        RowText(title, detail, Modifier.weight(1f))
        Trailing("arrow.up.forward")
    }
}

@Composable
private fun KeyboardAccess() {
    val access = LocalAccess.current
    Section(
        footer = "Android keeps these in Settings › System › Keyboard. iikb checks each one off as you come back to it.",
    ) { SetupSteps() }
    Section { ActionRow("Open Keyboard Settings", "arrow.up.forward", onClick = access.enable) }
}

@Composable
private fun Privacy() {
    val context = LocalContext.current
    val store = LocalStore.current
    val clips = remember { Clips.of(context) }
    var unpinned by remember { mutableIntStateOf(clips.rows().count { !it.pinned }) }
    var transcripts by remember { mutableIntStateOf(Transcripts.list().size) }
    DisposableEffect(clips) {
        val listener = { unpinned = clips.rows().count { !it.pinned } }
        clips.listen(listener)
        val stop = Transcripts.listen { transcripts = Transcripts.list().size }
        onDispose {
            clips.stopListening(listener)
            stop()
        }
    }
    var asking by remember { mutableStateOf<Ask?>(null) }
    Section("What Leaves This Phone") {
        Fact(
            "iphone",
            "Learned words, app-specific language and emoji choices, dictations and clipboard history stay here.",
        )
        Divider()
        Fact(
            "network",
            "iikb goes online to search GIFs and to download Parakeet once from Hugging Face. Android’s recognizer, if you pick it in Voice, may send your voice to Google.",
        )
    }
    Section(
        footer = "iikb forgets the words it learned across apps and within each app, and where your thumbs land on each key. Your Dictionary stays.",
    ) {
        ActionRow("Reset Learned Words and Taps", destructive = true) {
            asking = Ask("iikb will forget the words it learned and everything it learned about your taps.", "Reset") {
                store.resetMemory()
            }
        }
    }
    Section(
        footer = if (transcripts == 0) {
            "You haven’t dictated anything yet."
        } else {
            "Deletes all $transcripts transcripts from this phone."
        },
    ) {
        ActionRow("Delete All Transcripts", destructive = true, enabled = transcripts > 0) {
            asking = Ask("Delete all $transcripts transcripts from this phone?", "Delete All") { Transcripts.deleteAll() }
        }
    }
    Section(
        footer = when (unpinned) {
            0 -> "Your clipboard history has nothing to clear."
            1 -> "Deletes 1 item from your clipboard history. Pinned items stay."
            else -> "Deletes $unpinned items from your clipboard history. Pinned items stay."
        },
    ) {
        ActionRow("Clear Clipboard History", destructive = true, enabled = unpinned > 0) {
            asking = Ask("Clear your clipboard history?", "Clear History") { clips.clearUnpinned() }
        }
    }
    asking?.let { ask -> Confirm(ask) { asking = null } }
}

/** A question before something that can't be undone, and the button that does it. */
private class Ask(val question: String, val action: String, val run: () -> Unit)

@Composable
private fun Confirm(ask: Ask, dismiss: () -> Unit) {
    val palette = palette()
    AlertDialog(
        onDismissRequest = dismiss,
        containerColor = palette.card,
        text = { Text(ask.question, color = palette.label, fontSize = Type.body) },
        confirmButton = {
            TextButton({
                ask.run()
                dismiss()
            }) { Text(ask.action, color = palette.red, fontSize = Type.body) }
        },
        dismissButton = { TextButton(dismiss) { Text("Cancel", color = palette.accent, fontSize = Type.body) } },
    )
}

/** A label whose icon takes a fixed width, so the text of labels stacked in one card starts at the same place. */
@Composable
private fun Fact(symbol: String, text: String) {
    Row(Modifier.row(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.width(24.dp).padding(top = 1.dp), contentAlignment = Alignment.TopCenter) {
            Icon(Symbols[symbol], null, tint = palette().accent, modifier = Modifier.size(20.dp))
        }
        Text(text, color = palette().label, fontSize = Type.body, lineHeight = 22.sp)
    }
}

/** What changed in each build, a box per day, newest first, from the `changelog.json` each build writes (build.gradle.kts). */
@Composable
private fun Changelog() {
    val context = LocalContext.current
    val days = remember {
        val rows = runCatching {
            Json.decodeFromString<List<Change>>(context.assets.open("changelog.json").use { it.readBytes() }.decodeToString())
        }.getOrDefault(emptyList())
        rows.groupBy { it.date }.toSortedMap(compareByDescending { it }).toList()
    }
    if (days.isEmpty()) Section { RowText("No changes listed in this build.", modifier = Modifier.row()) }
    for ((date, changes) in days) {
        Section(dayTitle(date)) {
            changes.forEachIndexed { index, change ->
                if (index > 0) Divider()
                Row(Modifier.row(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    RowText(change.change, modifier = Modifier.weight(1f))
                    Text(change.build.toString(), color = palette().secondary, fontSize = Type.body)
                }
            }
        }
    }
}

@Serializable
private data class Change(val build: Int, val date: String, val change: String)

/** Today, Yesterday, or the day as "Nov 8". */
private fun dayTitle(date: String): String {
    val day = runCatching { java.time.LocalDate.parse(date) }.getOrNull() ?: return date
    val today = java.time.LocalDate.now()
    return when (day) {
        today -> "Today"
        today.minusDays(1) -> "Yesterday"
        else -> day.format(java.time.format.DateTimeFormatter.ofPattern("MMM d", java.util.Locale.US))
    }
}

@Composable
private fun About() {
    val context = LocalContext.current
    val palette = palette()
    val open = { url: String -> context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Mark(64)
        Column(Modifier.padding(start = 16.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("iikb", color = palette.label, fontSize = 28.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.045).em)
            Text(version(context), color = palette.secondary, fontSize = Type.body)
        }
    }
    Section(
        footer = "iikb types like Apple’s keyboard and learns where your thumbs land. It’s open source, under the MIT license.",
    ) { Line("Source Code", onClick = { open("https://github.com/AVGVSTVS96/iikb") }) { Trailing("arrow.up.forward") } }
    Section {
        Line(
            "Swipe typing powered by FUTO Swipe",
            onClick = {
                open("https://github.com/AVGVSTVS96/iikb/blob/main/Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/SWIPE-LICENSE")
            },
        ) { Trailing("arrow.up.forward") }
    }
}

/** The app icon's mark: iikb flush left on the bottom margin of a black square, as brand/logo/gen.ts draws it. */
@Composable
fun Mark(size: Int) {
    val shape = RoundedCornerShape((size * 0.225f).dp)
    Box(
        Modifier.size(size.dp).background(Color.Black, shape).border(BorderStroke(0.5.dp, Color.White.copy(alpha = 0.12f)), shape)
            .padding((size * 0.13f).dp),
        contentAlignment = Alignment.BottomStart,
    ) {
        Text(
            "iikb", color = Color.White, fontSize = (size * 0.37f).sp, fontWeight = FontWeight.Bold,
            letterSpacing = (-0.045).em, lineHeight = (size * 0.37f).sp,
        )
    }
}
