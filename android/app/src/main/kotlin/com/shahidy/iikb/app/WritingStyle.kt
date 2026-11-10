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
 * How iikb writes what you say, as two things: the style, how it reads, which each app can have its own of and the
 * keyboard's bar picks for the app you're in; and the cleanup, what it leaves out of what you said, the same everywhere.
 * A card on top shows what you'd say typed as picked, with the words that show off what you last changed.
 */
@Composable
fun WritingStyle() {
    val context = LocalContext.current
    val store = LocalStore.current
    val names = remember { AppNames(context) }
    var sample by remember { mutableStateOf(Sample.STYLE) }
    /** Whose style the list sets: an app's, by its package, or the default's. */
    var app by remember { mutableStateOf(DEFAULT) }
    val styles = store.appStyles()
    val default = store.string("writingStyle")
    val title = Core.styles.firstOrNull { it.value == default }?.title
    /** The default style with Text Mode's words kept from before, as Excited! · Abbreviated, which no style types. */
    val kept = TEXT_MODES[store.string("textMode")]?.let { words -> "$title · $words" }
    /** The style picked for [app], null where it follows the default; the default's, unless it keeps Text Mode's words. */
    val picked = if (app == DEFAULT) default.takeIf { kept == null } else styles[app]
    /** `said` as typed with `changed` set; a style of its own, an app's or a row's, types without the kept words. */
    fun typed(said: String, vararg changed: Pair<String, String>): String {
        val set = mapOf("writingStyle" to (picked ?: default)) + changed
        val words = changed.none { it.first == "writingStyle" } && (app == DEFAULT || picked == null)
        val lines = store.lines().lines().filter { words || !it.startsWith("textMode=") }.joinToString("\n") { line ->
            set.entries.firstOrNull { line.startsWith("${it.key}=") }?.let { "${it.key}=${it.value}" } ?: line
        }
        return Core.typed(context, said, lines)
    }
    fun quoted(said: String, vararg changed: Pair<String, String>) = "“" + typed(said, *changed) + "”"
    fun pick(style: String?) {
        sample = Sample.STYLE
        if (app != DEFAULT) store.settings.setAppStyle(app, style) else if (style != null) store.set("writingStyle", style)
    }

    WritingPreview(sample.said, typed(sample.said))
    Section(
        "Style",
        "A style sets the capitals, the punctuation and the words. Each app can have its own, also picked in the keyboard’s bar where it has room. Where a style keeps capitals, they follow Auto-Capitalization in Keyboard › Typing.",
    ) {
        val apps = dictatedApps(styles.keys)
        if (apps.isNotEmpty()) {
            MenuRow("For", app, listOf(DEFAULT to "Default") + apps.map { it to names.of(it) }) { app = it }
            Divider()
        }
        if (app != DEFAULT) {
            ChoiceRow("Default", kept ?: title, picked == null) { pick(null) }
            Divider()
        } else if (kept != null) {
            ChoiceRow(kept, quoted(Sample.STYLE.said), true) {}
            Divider()
        }
        Core.styles.forEachIndexed { index, style ->
            if (index > 0) Divider()
            ChoiceRow(style.title, quoted(Sample.STYLE.said, "writingStyle" to style.value), picked == style.value) { pick(style.value) }
        }
    }
    Section("Cleanup", "Clean also takes back what you cancel with “scratch that”. Cleanup is the same in every app.") {
        EDITING.forEachIndexed { index, (value, title) ->
            if (index > 0) Divider()
            ChoiceRow(title, quoted(RAMBLED, "dictationEditing" to value), store.string("dictationEditing") == value) {
                sample = Sample.CLEANUP
                store.set("dictationEditing", value)
            }
        }
        Divider()
        MenuRow("Spoken Lists", store.string("spokenLists"), LISTS) {
            sample = Sample.LISTS
            store.set("spokenLists", it)
        }
    }
}

/** What the card on top says, picked by what you changed last. */
private enum class Sample(val said: String) {
    STYLE("Hey, by the way, are you free tonight. The food there is amazing, for real."),
    CLEANUP("Um, so I think the the plan is, like, dinner at two, I mean three."),
    LISTS("For tonight we need one, eggs, two, milk, three, bread."),
}

/** The apps you've dictated into, most dictated first, then any other in `styled`, the apps with a style of their own. */
@Composable
private fun dictatedApps(styled: Set<String>): List<String> {
    val context = LocalContext.current
    val names = remember { AppNames(context) }
    var transcripts by remember { mutableStateOf(Transcripts.list()) }
    DisposableEffect(Unit) { onDispose(Transcripts.listen { transcripts = Transcripts.list() }) }
    val counts = transcripts.mapNotNull { it.app }.filter { it != context.packageName }.groupingBy { it }.eachCount()
        .toMutableMap()
    styled.forEach { counts.putIfAbsent(it, 0) }
    return counts.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { names.of(it.key) })
        .map { it.key }
}

private const val DEFAULT = ""

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

private const val RAMBLED = "Um, I think the the plan is, like, two, I mean three."

/** Text Mode's names, from when it was a setting of its own, kept beside the style where none types its words. */
private val TEXT_MODES =
    mapOf("spelledOut" to "Spelled Out", "abbreviated" to "Abbreviated", "texting" to "Texting", "genZ" to "Gen Z")
private val EDITING = listOf("asSaid" to "As Said", "light" to "No Um or Uh", "clean" to "Clean")
private val LISTS = listOf("numbered" to "Numbered", "bulleted" to "Bulleted", "off" to "Off")
