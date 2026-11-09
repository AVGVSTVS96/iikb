package com.shahidy.iikb.app.stats

import com.shahidy.iikb.app.Hues
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.Transcript
import com.shahidy.iikb.app.design.Caption
import com.shahidy.iikb.app.design.Empty
import com.shahidy.iikb.app.design.Figure
import com.shahidy.iikb.app.design.Figures
import com.shahidy.iikb.app.design.Format
import com.shahidy.iikb.app.design.Glyphs
import com.shahidy.iikb.app.design.Hairline
import com.shahidy.iikb.app.design.Tints
import com.shahidy.iikb.app.design.LeadNumber
import com.shahidy.iikb.app.design.SegmentedBar
import com.shahidy.iikb.app.design.Stat
import com.shahidy.iikb.app.design.StatCard
import com.shahidy.iikb.app.design.StatGrid
import com.shahidy.iikb.app.design.TrendChip
import com.shahidy.iikb.app.palette
import java.time.LocalDate
import kotlin.math.roundToInt

/**
 * The phone's typing or talking, in its color: how fast, large, with how lately compares, then words or speed a day, the
 * hours you do it in, how fast you type, where your typed words came from or your dictations, the apps your words went
 * into, and the past year.
 */
@Composable
fun DeviceStats(kind: Kind, activity: Activity, transcripts: List<Transcript>, computer: String?) {
    if (activity.isEmpty(kind)) {
        val noun = if (kind == Kind.TYPED) "typing" else "dictation"
        return Empty(
            if (kind == Kind.TYPED) Glyphs.KEYBOARD else Glyphs.WAVEFORM, if (kind == Kind.TYPED) "No Typing Yet" else "No Dictation Yet",
            when {
                computer != null -> "Keystroke hasn’t counted any $noun on $computer yet."
                kind == Kind.TYPED -> "Type with the keyboard anywhere. Your typing shows up here each time it closes."
                else -> "Tap the mic at the right end of the keyboard’s suggestions and talk."
            },
        )
    }
    Speed(kind, activity, computer)
    History(activity, listOf(kind))
    Rhythm(activity, listOf(kind))
    if (kind == Kind.TYPED && activity.speeds.isNotEmpty()) Speeds(activity.speeds)
    if (computer == null) {
        if (kind == Kind.TYPED) WordSources(activity.total(Kind.TYPED)) else Dictations(transcripts)
    }
    activity.apps[kind]?.takeIf { it.isNotEmpty() }?.let { Apps(kind, it) }
    Year(activity, listOf(kind))
}

/** How fast you type or talk, large, with a chip for how the last week compares, then how much and for how long. */
@Composable
private fun Speed(kind: Kind, activity: Activity, computer: String?) {
    val palette = palette()
    val asOf = computer?.let { Computers.of(LocalContext.current).asOf[it] }
    val all = activity.total(kind)
    val today = LocalDate.now()
    val trend = all.speed?.let { speed ->
        activity.total(kind, today.minusDays(6)).speed?.let { lately -> (lately - speed).roundToInt().takeIf { it != 0 } }
    }
    val fastest = activity.days.mapNotNull { (date, day) ->
        day[kind].takeIf { it.seconds >= 120 }?.speed?.let { date to it }
    }.maxByOrNull { it.second }
    val lines = mutableListOf(
        when {
            kind == Kind.TYPED -> "Words of five letters a minute while you type, pauses over 4 seconds left out."
            computer != null -> "Words of five letters a minute, over the dictations Keystroke timed."
            else -> "Words a minute while you talk."
        },
    )
    val typed = activity.total(Kind.TYPED).speed
    if (kind == Kind.SAID && all.speed != null && typed != null && typed > 0) {
        lines += "%.1f× as fast as you type.".format(all.speed!! / typed)
    }
    fastest?.let { lines += "Fastest day: ${it.second.roundToInt()}\u00A0wpm, ${Format.day(it.first)}." }
    val noun = if (kind == Kind.TYPED) "typed" else "said"
    StatCard(
        if (kind == Kind.TYPED) "speedometer" else "waveform", kind.color(palette),
        if (kind == Kind.TYPED) "Typing speed" else "Talking speed",
    ) {
        LeadNumber(all.speed?.let { "${it.roundToInt()} wpm" } ?: "–", 52f, trend?.let { { TrendChip(it) } })
        Caption(lines.joinToString(" "), lines = 3)
        Hairline()
        Figures(
            listOf(
                Figure(Format.count(all.words), if (all.words == 1) "word $noun" else "words $noun"),
                Figure(if (all.seconds < 60) "<1m" else Format.time(all.seconds), if (kind == Kind.TYPED) "typing" else "talking"),
                if (kind == Kind.SAID && all.dictations > 0) {
                    Figure(Format.count(all.dictations), if (all.dictations == 1) "dictation" else "dictations")
                } else {
                    Figure(Format.count(activity.channel(kind, today).words), "today")
                },
            ),
        )
        if (computer != null) Caption("From Keystroke on $computer${asOf?.let { ", as of ${Format.moment(it)}" }.orEmpty()}.")
    }
}

/** Where typed words came from: as typed, fixed by autocorrect, or picked from the bar; then fixes taken back, deletes, emoji. */
@Composable
private fun WordSources(channel: Channel) {
    val palette = palette()
    val words = channel.words.coerceAtLeast(1)
    val corrected = minOf(channel.corrected, words)
    val picked = minOf(channel.picked, words - corrected)
    fun share(part: Int, whole: Int) = Format.percent(part.toDouble() / whole)
    StatCard("character.cursor.ibeam", Hues.blue.on(palette), "Your typed words") {
        SegmentedBar(
            listOf(
                Triple("As typed", (words - corrected - picked).toDouble() / words, Hues.blue.on(palette)),
                Triple("Autocorrected", corrected.toDouble() / words, Tints.miss(palette)),
                Triple("From the bar", picked.toDouble() / words, palette.secondary.copy(alpha = 0.45f)),
            ),
        )
        Hairline()
        Figures(
            listOf(
                Figure(if (channel.corrected > 0) share(channel.undone, channel.corrected) else "–", "taken back"),
                Figure(if (channel.keys > 0) share(channel.deletes, channel.keys) else "–", "deleted"),
                Figure(Format.count(channel.emoji), "emoji"),
            ),
        )
        Caption("Taken back: autocorrect fixes you undid. Deleted: taps on delete.")
    }
}

/** The apps your words went into, most first, each with a bar of its share; past the fifth, the rest as one. */
@Composable
private fun Apps(kind: Kind, apps: List<Pair<String, Int>>) {
    val palette = palette()
    val rows = if (apps.size > 6) apps.take(5) + ("Other apps" to apps.drop(5).sumOf { it.second }) else apps
    val top = rows.maxOf { it.second }.coerceAtLeast(1)
    StatCard("square.grid.2x2.fill", Hues.purple.on(palette), if (kind == Kind.TYPED) "Where you type" else "Where you dictate") {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            rows.forEach { (name, words) ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row {
                        Text(name, color = palette.label, fontSize = 17.sp, maxLines = 1, modifier = Modifier.weight(1f))
                        Text(Format.count(words), color = palette.secondary, fontSize = 17.sp)
                    }
                    BoxWithConstraints(Modifier.fillMaxWidth()) {
                        androidx.compose.foundation.layout.Box(
                            Modifier.width(maxOf(maxWidth * (words.toFloat() / top), 4.dp)).height(6.dp).clip(CircleShape)
                                .background(Tints.gradient(kind.color(palette))),
                        )
                    }
                }
            }
        }
    }
}

/** The phone's dictations: how long they run, how many weren't typed, and what wrote most. */
@Composable
private fun Dictations(transcripts: List<Transcript>) {
    val palette = palette()
    val all = transcripts.filter { it.text.isNotEmpty() }
    val lengths = all.map { it.seconds }.sorted()
    if (lengths.isEmpty()) return
    val model = all.mapNotNull { it.model }.groupingBy { it }.eachCount().maxByOrNull { it.value }?.key
    StatCard("text.bubble.fill", Hues.pink.on(palette), "Your dictations") {
        StatGrid(
            facts = listOfNotNull(
                { Stat("Typical length", Format.clock(lengths[lengths.size / 2])) },
                { Stat("Longest", Format.clock(lengths.last())) },
                { Stat("Not typed", Format.count(all.count { !it.typed })) },
                model?.let { { Stat("Written most by", it) } },
            ),
        )
    }
}
