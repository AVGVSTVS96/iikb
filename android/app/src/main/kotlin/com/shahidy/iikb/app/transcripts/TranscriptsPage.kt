package com.shahidy.iikb.app.transcripts

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.Transcript
import com.shahidy.iikb.Transcripts
import com.shahidy.iikb.app.Divider
import com.shahidy.iikb.app.Line
import com.shahidy.iikb.app.ListPage
import com.shahidy.iikb.app.MicSwitch
import com.shahidy.iikb.app.Page
import com.shahidy.iikb.app.design.Empty
import com.shahidy.iikb.app.design.Figure
import com.shahidy.iikb.app.design.Figures
import com.shahidy.iikb.app.design.Format
import com.shahidy.iikb.app.design.GlyphTile
import com.shahidy.iikb.app.design.Glyphs
import com.shahidy.iikb.app.design.Hairline
import com.shahidy.iikb.app.design.LeadNumber
import com.shahidy.iikb.app.design.Rows
import com.shahidy.iikb.app.design.SearchField
import com.shahidy.iikb.app.design.Tints
import com.shahidy.iikb.app.design.TrendChip
import com.shahidy.iikb.app.design.card
import com.shahidy.iikb.app.glyph
import com.shahidy.iikb.app.palette
import com.shahidy.iikb.app.stats.AppNames
import com.shahidy.iikb.app.stats.ColumnChart
import com.shahidy.iikb.app.stats.Rule
import com.shahidy.iikb.app.stats.Tick
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/** The phone's transcripts, read again each time one is added or deleted. */
@Composable
fun transcripts(): List<Transcript> {
    var all by remember { mutableStateOf(Transcripts.list()) }
    DisposableEffect(Unit) {
        val stop = Transcripts.listen { all = Transcripts.list() }
        onDispose { stop() }
    }
    return all
}

private fun Transcript.time(): LocalDateTime =
    Instant.ofEpochMilli((date * 1000).toLong()).atZone(ZoneId.systemDefault()).toLocalDateTime()

/** The text, or, when the model wrote nothing, what it heard that your editing left out, else that it heard nothing. */
private val Transcript.shown get() = text.ifEmpty { heard?.let { "Left out: $it" } ?: "Nothing heard" }

/**
 * Every dictation, newest first by day, under a search field and how much and how fast you talk, which opens Stats ›
 * Dictation; a transcript opens on its own page.
 */
@Composable
fun TranscriptsPage(openStats: () -> Unit) {
    val all = transcripts()
    var opened by rememberSaveable { mutableStateOf<String?>(null) }
    val transcript = all.firstOrNull { it.id == opened }
    BackHandler(enabled = transcript != null) { opened = null }
    if (transcript != null) return TranscriptDetail(transcript) { opened = null }
    var query by rememberSaveable { mutableStateOf("") }
    val context = LocalContext.current
    val names = remember { AppNames(context) }
    val shown = query.trim().let { q -> if (q.isEmpty()) all else all.filter { it.text.contains(q, ignoreCase = true) } }
    val days = shown.groupBy { it.time().toLocalDate() }.toList()
    ListPage("Transcripts", actions = { MicSwitch() }) {
        if (all.isEmpty()) {
            item {
                Empty(
                    Glyphs.WAVEFORM, "No Transcripts",
                    "Tap the mic at the right end of the keyboard’s suggestions and talk. Everything you dictate is kept here, on this phone.",
                )
            }
            return@ListPage
        }
        item { Box(Modifier.padding(top = 4.dp, bottom = 24.dp)) { SearchField(query, "Search") { query = it } } }
        if (query.isEmpty()) item { Box(Modifier.padding(bottom = 24.dp)) { Summary(all, openStats) } }
        if (shown.isEmpty()) item { Empty(Glyphs.SEARCH, "No Results", "Check the spelling or try a new search.") }
        days.forEach { (day, transcripts) ->
            item(key = day.toString()) {
                Box(Modifier.padding(bottom = 24.dp)) {
                    Rows(title(day)) {
                        transcripts.forEachIndexed { index, transcript ->
                            if (index > 0) Divider()
                            TranscriptRow(transcript, names) { opened = transcript.id }
                        }
                    }
                }
            }
        }
    }
}

/** Today, Yesterday, a weekday this week, else the date. */
fun title(day: LocalDate): String {
    val today = LocalDate.now()
    val ago = ChronoUnit.DAYS.between(day, today)
    return when {
        ago == 0L -> "Today"
        ago == 1L -> "Yesterday"
        ago in 2..6 -> day.format(DateTimeFormatter.ofPattern("EEEE"))
        day.year == today.year -> day.format(DateTimeFormatter.ofPattern("EEEE, MMMM d"))
        else -> day.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG))
    }
}

private fun length(seconds: Double) = seconds.roundToInt().let { "%d:%02d".format(it / 60, it % 60) }

private val clock = DateTimeFormatter.ofPattern("h:mm a")

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TranscriptRow(transcript: Transcript, names: AppNames, open: () -> Unit) {
    val palette = palette()
    val context = LocalContext.current
    var menu by remember { mutableStateOf(false) }
    Box {
        Column(
            Modifier.fillMaxWidth().heightIn(min = 56.dp).combinedClickable(onLongClick = { menu = true }, onClick = open)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Text(
                transcript.shown, color = if (transcript.text.isEmpty()) palette.secondary else palette.label,
                fontSize = 17.sp, lineHeight = 22.sp, maxLines = 3, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            )
            val parts = listOfNotNull(
                transcript.time().format(clock), length(transcript.seconds),
                if (transcript.typed) transcript.app?.let(names::of) else "Not typed",
            )
            Text(parts.joinToString(" · "), color = palette.secondary, fontSize = 13.sp, maxLines = 1)
        }
        DropdownMenu(menu, { menu = false }, containerColor = palette.card) {
            DropdownMenuItem({ Text("Copy", color = palette.label) }, {
                menu = false
                copy(context, transcript.text)
            })
            DropdownMenuItem({ Text("Share Text", color = palette.label) }, {
                menu = false
                share(context, transcript.text)
            })
            DropdownMenuItem({ Text("Delete", color = palette.red) }, {
                menu = false
                Transcripts.delete(setOf(transcript.id))
            })
        }
    }
}

fun copy(context: Context, text: String) {
    context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("iikb", text))
}

fun share(context: Context, text: String) {
    context.startActivity(
        Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
}

/**
 * How much you've dictated, in dictation's pink: every word said, how this week compares with the one before, words a
 * day for two weeks with the best day marked, then time talking, pace and today. A tap opens Stats › Dictation.
 */
@Composable
private fun Summary(transcripts: List<Transcript>, openStats: () -> Unit) {
    val palette = palette()
    val pink = Tints.pink(palette)
    val words = transcripts.sumOf { it.words }
    val seconds = transcripts.filter { it.text.isNotEmpty() }.sumOf { it.seconds }
    val today = LocalDate.now()
    val byDay = transcripts.groupBy { it.time().toLocalDate() }.mapValues { (_, list) -> list.sumOf { it.words } }
    val days = (13 downTo 0).map { today.minusDays(it.toLong()) }.map { it to (byDay[it] ?: 0) }
    val before = days.take(7).sumOf { it.second }
    val lately = days.takeLast(7).sumOf { it.second }
    val trend = if (before > 0 && lately > 0) ((lately - before).toDouble() / before * 100).roundToInt().takeIf { it != 0 } else null
    Column(
        Modifier.fillMaxWidth().card(palette).clickable(onClick = openStats).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            GlyphTile(Glyphs.WAVEFORM, pink)
            Text("Dictation", color = palette.secondary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            Spacer(Modifier.weight(1f))
            Text("Stats", color = palette.secondary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            Icon(glyph(Glyphs.CHEVRON, 2.4f), null, tint = palette.secondary, modifier = Modifier.size(13.dp))
        }
        LeadNumber(Format.count(words), 44f) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(if (words == 1) "word said" else "words said", color = palette.secondary, fontSize = 15.sp, maxLines = 1)
                when {
                    trend == null || trend >= 1900 -> {}
                    trend >= 900 -> TrendChip(trend / 100 + 1, "× last week")
                    else -> TrendChip(trend, "% this week")
                }
            }
        }
        Fortnight(days)
        Hairline()
        Figures(
            listOf(
                Figure(Format.time(seconds), "talking"),
                Figure(if (seconds >= 1) "${(words / seconds * 60).roundToInt()} wpm" else "–", "pace"),
                Figure(Format.count(days.last().second), "today"),
            ),
            22f,
        )
    }
}

/** Words a day for two weeks, today and the best day full, the best day's count over it, a dashed line at the average. */
@Composable
private fun Fortnight(days: List<Pair<LocalDate, Int>>) {
    val palette = palette()
    val pink = Tints.pink(palette)
    val active = days.filter { it.second > 0 }
    val average = if (active.isEmpty()) 0 else active.sumOf { it.second } / active.size
    val best = days.maxByOrNull { it.second }?.takeIf { it.second > 0 }
    val today = days.last().first
    val marked = { day: LocalDate -> day == today || day == best?.first }
    ColumnChart(
        days.map { (day, words) -> if (marked(day)) listOf(words.toDouble(), null) else listOf(null, words.toDouble()) },
        listOf(Brush.verticalGradient(listOf(pink, Tints.purple(palette))), Brush.verticalGradient(listOf(pink.copy(alpha = 0.8f), pink.copy(alpha = 0.8f)))),
        (best?.second ?: 1) * 1.25, 112.dp, listOf(0, 7).map { Tick(it, Format.day(days[it].first), true) },
        ratio = 0.64f, radius = 4.dp, yLabel = null,
        rule = if (active.size > 1) Rule(average.toDouble(), "avg ${Format.compact(average)}", leading = true) else null,
        annotate = { index -> if (days[index].first == best?.first) Format.compact(days[index].second) to pink else null },
    )
}

/** One dictation on its own: when, its text, Copy and Share, its facts, and Delete. */
@Composable
private fun TranscriptDetail(transcript: Transcript, back: () -> Unit) {
    val palette = palette()
    val context = LocalContext.current
    val names = remember { AppNames(context) }
    var confirms by remember { mutableStateOf(false) }
    Page("Transcript", back, actions = { MicSwitch() }) {
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text(
                transcript.time().format(DateTimeFormatter.ofPattern("EEEE, MMM d, h:mm a")), color = palette.secondary,
                fontSize = 15.sp, fontWeight = FontWeight.Medium, modifier = Modifier.padding(horizontal = 4.dp),
            )
            SelectionContainer {
                Text(
                    transcript.shown, color = if (transcript.text.isEmpty()) palette.secondary else palette.label,
                    fontSize = 20.sp, lineHeight = 27.sp, modifier = Modifier.fillMaxWidth().card(palette).padding(20.dp),
                )
            }
            if (transcript.text.isNotEmpty()) {
                Rows {
                    CopyRow(transcript.text)
                    Divider()
                    ActionRow("Share Text", "M12 3v12 M8 7l4-4 4 4 M5 12v8h14v-8", palette.accent) { share(context, transcript.text) }
                }
            }
            Rows {
                Line("Length", value = length(transcript.seconds))
                Divider()
                Line("Words", value = Format.count(transcript.words))
                if (transcript.seconds >= 1) {
                    Divider()
                    Line("Pace", value = "${(transcript.words / transcript.seconds * 60).roundToInt()} wpm")
                }
                Divider()
                Line("Typed", value = if (transcript.typed) transcript.app?.let { "In ${names.of(it)}" } ?: "Yes" else "No")
                transcript.model?.let {
                    Divider()
                    Line("Written by", value = it)
                }
            }
            Rows {
                Line("Delete Transcript", onClick = { confirms = true }, color = palette.red)
            }
        }
    }
    if (confirms) {
        AlertDialog(
            onDismissRequest = { confirms = false },
            containerColor = palette.card,
            title = { Text("Delete this transcript?", color = palette.label) },
            confirmButton = {
                TextButton({
                    confirms = false
                    Transcripts.delete(setOf(transcript.id))
                    back()
                }) { Text("Delete", color = palette.red) }
            },
            dismissButton = { TextButton({ confirms = false }) { Text("Cancel", color = palette.accent) } },
        )
    }
}

/** Copy as a row that says Copied for a moment once it's done, as iOS's `CopyRow`. */
@Composable
private fun CopyRow(text: String) {
    val palette = palette()
    val context = LocalContext.current
    var copies by remember { mutableIntStateOf(0) }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copies) {
        if (copies == 0) return@LaunchedEffect
        copied = true
        delay(1500)
        copied = false
    }
    if (copied) {
        ActionRow("Copied", "M6.5 12.5l4 4L18 8", palette.green) {}
    } else {
        ActionRow("Copy", "M9 9h10v11H9Z M5 15V4h10", palette.accent) {
            copy(context, text)
            copies++
        }
    }
}

/** A row that acts, its title and glyph in its color. */
@Composable
private fun ActionRow(title: String, path: String, color: Color, onClick: () -> Unit) =
    Line(title, onClick = onClick, color = color) {
        Icon(glyph(path, 1.9f), null, tint = color, modifier = Modifier.size(20.dp))
    }
