package com.shahidy.iikb.keyboard

import android.content.ClipData
import android.content.ClipboardManager
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.shahidy.iikb.Transcripts

/** What you dictated holding `query`, newest first, as the clipboard's rows show them: words and how long ago. */
@Composable
private fun rememberTranscripts(query: String): List<Clips.Row> {
    var revision by remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) { onDispose(Transcripts.listen { revision++ }) }
    return remember(query, revision) {
        val now = System.currentTimeMillis() / 1000.0
        val search = query.lowercase()
        Transcripts.list().filter { search.isEmpty() || it.text.lowercase().contains(search) }.map {
            Clips.Row(
                it.text, "text", Native.length(it.text.encodeToByteArray(), true).decodeToString(),
                Native.age(it.date, now).decodeToString(), false,
            )
        }
    }
}

/** Transcripts' shelf in the menu (docs/design.md, "Transcripts"): the clipboard's cards, a tap typing one. */
@Composable
fun TranscriptShelf() {
    val rows = rememberTranscripts("")
    val actions = LocalActions.current
    var shown by remember { mutableStateOf<Clips.Row?>(null) }
    if (rows.isEmpty()) return Empty("What you dictate shows up here.")
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val card = (maxWidth - ITEM_GAP * 2) / 3
        LazyRow(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(ITEM_GAP)) {
            items(rows) { row ->
                Pressable(Modifier.width(card).fillMaxHeight(), 10.dp, { actions.paste(row.text) }, { shown = row }) {
                    Card(row)
                }
            }
        }
    }
    shown?.let { TranscriptPreview(it) { shown = null } }
}

/** The Transcripts panel: the clipboard's rows of what you dictated over its search row; a tap types one. */
@Composable
fun TranscriptsPanel(state: Overlay.State) {
    val look = LocalColors.current
    val actions = LocalActions.current
    var shown by remember { mutableStateOf<Clips.Row?>(null) }
    val rows = rememberTranscripts(state.query)
    Column(
        Modifier.fillMaxSize().background(look.card)
            .padding(start = state.minX.dp, end = state.endInset.dp, top = 3.dp, bottom = if (state.keysUp) 0.dp else 11.dp),
    ) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            when {
                rows.isEmpty() && state.query.isBlank() -> Empty("What you dictate shows up here.")
                rows.isEmpty() -> Empty("No transcripts for “${state.query.trim()}”")
                else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    items(rows) { row -> ClipRow(row, { actions.paste(row.text) }) { shown = row } }
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        SearchRow(state, { Glyph("text.bubble", look.secondary, 18.dp) }, "Search transcripts")
    }
    shown?.let { TranscriptPreview(it) { shown = null } }
}

/** A transcript held: all of it, with Paste and Copy. */
@Composable
private fun TranscriptPreview(row: Clips.Row, close: () -> Unit) {
    val actions = LocalActions.current
    val context = LocalContext.current
    Preview(row, close) { button ->
        Action(button, "doc.on.clipboard", "Paste") {
            close()
            actions.paste(row.text)
        }
        Action(button, "square.on.square", "Copy") {
            close()
            context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Transcript", row.text))
        }
    }
}
