package com.shahidy.iikb.app

import androidx.compose.animation.Crossfade
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import com.shahidy.iikb.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.Transcripts
import com.shahidy.iikb.app.stats.AppNames

/**
 * The words and punctuation iikb types for what you say: a card of the same words as picked, then each style, each
 * level of editing, each way of writing a list and each text mode shown by how it types them with everything else as
 * picked.
 */
@Composable
fun WritingStyle() {
    val context = LocalContext.current
    val store = LocalStore.current
    val lines = store.lines()
    fun typed(said: String, name: String? = null, value: String = "") =
        Core.typed(context, said, if (name == null) lines else store.settings.linesWith(name, value))
    fun quoted(said: String, name: String, value: String) = "“" + typed(said, name, value) + "”"

    WritingPreview(PREVIEW, typed(PREVIEW))
    Section(
        "Style",
        "A style sets all the punctuation. Formal keeps every mark; Casual drops the last period and the comma after “so” or “hey”; very casual also drops capitals and the comma before “and” or “but”; Excited! ends short sentences with “!”. Every style asks a question with “?”. Capitals follow Auto-Capitalization in Keyboard › Typing.",
    ) { Examples("writingStyle", STYLES) { quoted(SAID, "writingStyle", it) } }
    StyleInEachApp()
    Section("Editing", "Clean also takes back what you cancel with “scratch that”. Transcripts keep what the model wrote.") {
        Examples("dictationEditing", EDITING) { quoted(RAMBLED, "dictationEditing", it) }
    }
    Section("Lists", "A list you say with one, two or first, second is written on lines of its own.") {
        Examples("spokenLists", LISTS) { typed(LISTED, "spokenLists", it) }
    }
    Section("Text Mode", "Each step adds to the one before it. Transcripts keep what the model wrote.") {
        Examples("textMode", TEXT_MODES) { quoted(TEXTED, "textMode", it) }
    }
}

/** Each app you've dictated into, most dictated first, then any other with a style of its own, each on its menu of styles. */
@Composable
private fun StyleInEachApp() {
    val context = LocalContext.current
    val store = LocalStore.current
    val names = remember { AppNames(context) }
    var transcripts by remember { mutableStateOf(Transcripts.list()) }
    DisposableEffect(Unit) { onDispose(Transcripts.listen { transcripts = Transcripts.list() }) }
    val styles = store.appStyles()
    val counts = transcripts.mapNotNull { it.app }.filter { it != context.packageName }.groupingBy { it }.eachCount()
        .toMutableMap()
    styles.keys.forEach { counts.putIfAbsent(it, 0) }
    val apps = counts.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { names.of(it.key) })
        .map { it.key }
    if (apps.isEmpty()) return
    Section("Style in Each App", "An app on Default writes in the style above. Each app you dictate into shows here.") {
        apps.forEachIndexed { index, app ->
            if (index > 0) Divider()
            MenuRow(names.of(app), styles[app] ?: DEFAULT, listOf(DEFAULT to "Default") + STYLES) {
                store.setAppStyle(app, it.takeIf { it != DEFAULT })
            }
        }
    }
}

private const val DEFAULT = ""

@Composable
private fun Examples(name: String, choices: List<Pair<String, String>>, example: (String) -> String) {
    val store = LocalStore.current
    choices.forEachIndexed { index, (value, title) ->
        if (index > 0) Divider()
        ChoiceRow(title, example(value), store.string(name) == value) { store.set(name, value) }
    }
}

/** What you say over what iikb types for it, as picked, so a change shows at once. */
@Composable
private fun WritingPreview(said: String, typed: String) {
    val palette = palette()
    Column(Modifier.fillMaxWidth().card().padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("You say", color = palette.secondary, fontSize = Type.footnote, fontWeight = FontWeight.Medium)
            Text(said, color = palette.secondary, fontSize = Type.body, lineHeight = 22.sp)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(palette.divider))
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("iikb types", color = palette.secondary, fontSize = Type.footnote, fontWeight = FontWeight.Medium)
            Crossfade(typed, label = "typed") {
                Text(it, color = palette.label, fontSize = Type.title3, fontWeight = FontWeight.Medium, lineHeight = 25.sp)
            }
        }
    }
}

private const val SAID = "Hey, are you free tonight. Let's grab dinner, and then see the show."
private const val RAMBLED = "Um, I think the the plan is, like, two, I mean three."
private const val LISTED = "Buy one, eggs, two, milk, three, bread."
private const val TEXTED = "By the way, are you free tonight? The food there is really amazing, for real. Let me know."
private const val PREVIEW =
    "Um, so are you free tonight. Let's grab dinner at the the place on Main, and then see the show at two, I mean three."

val STYLES = listOf("formal" to "Formal.", "casual" to "Casual", "veryCasual" to "very casual", "excited" to "Excited!")
private val EDITING = listOf("asSaid" to "As Said", "light" to "Light", "clean" to "Clean")
private val LISTS = listOf("numbered" to "Numbered", "bulleted" to "Bulleted", "off" to "Off")
private val TEXT_MODES = listOf("spelledOut" to "Spelled Out", "abbreviated" to "Abbreviated", "texting" to "Texting", "genZ" to "Gen Z")
