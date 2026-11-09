package com.shahidy.iikb.app.stats

import com.shahidy.iikb.app.Hues
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import com.shahidy.iikb.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.Settings
import com.shahidy.iikb.app.LocalResumes
import com.shahidy.iikb.app.design.Caption
import com.shahidy.iikb.app.design.isDark
import com.shahidy.iikb.app.design.Empty
import com.shahidy.iikb.app.design.Figure
import com.shahidy.iikb.app.design.Figures
import com.shahidy.iikb.app.design.FirstThatFits
import com.shahidy.iikb.app.design.Format
import com.shahidy.iikb.app.design.Glyphs
import com.shahidy.iikb.app.design.Hairline
import com.shahidy.iikb.app.design.Tints
import com.shahidy.iikb.app.design.LeadNumber
import com.shahidy.iikb.app.design.SectionPills
import com.shahidy.iikb.app.design.SegmentedBar
import com.shahidy.iikb.app.design.StatCard
import com.shahidy.iikb.app.design.TrendChip
import com.shahidy.iikb.app.design.card
import com.shahidy.iikb.app.design.display
import com.shahidy.iikb.app.Symbols
import com.shahidy.iikb.app.glyph
import com.shahidy.iikb.app.palette
import com.shahidy.iikb.folds
import com.shahidy.iikb.keyboard.Native
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Stats' Taps: what the keyboard learned of where you tap, one screen at a time: your numbers, the keyboard drawn with it
 * (Heat, Aim, Accuracy), a picked key up close, how each half pulls, and the keys you miss most.
 */
@Composable
fun Taps() {
    val context = LocalContext.current
    val resumes = LocalResumes.current
    val dark = palette().isDark
    var signature by remember { mutableStateOf<String?>(null) }
    var board by remember { mutableStateOf<TapBoard?>(null) }
    var heat by remember { mutableStateOf<ImageBitmap?>(null) }
    var mode by remember { mutableStateOf(TapMode.HEAT) }
    var selected by remember { mutableStateOf<Int?>(null) }
    LaunchedEffect(resumes, signature) {
        board = withContext(Dispatchers.Default) {
            val metrics = context.resources.displayMetrics
            val memory = File(context.filesDir, "typing-memory.json").takeIf { it.exists() }?.readBytes()
            TapBoard.parse(
                Native.taps(
                    memory, Settings(context).lines().encodeToByteArray(), signature?.encodeToByteArray(),
                    metrics.widthPixels / metrics.density.toDouble(), metrics.heightPixels / metrics.density.toDouble(),
                    context.folds(),
                ),
            )
        }
        if (board?.aims?.none { it.key == selected } != false) selected = null
    }
    LaunchedEffect(board, dark) { heat = withContext(Dispatchers.Default) { board?.let { TapHeat.image(it, dark) } } }
    val shown = board?.takeIf { it.signature != null && it.aims.any { aim -> aim.taps > 0 } }
    if (shown == null) {
        return Empty(Glyphs.TAP, "No Taps Yet", "Type with the keyboard anywhere. Your taps show up here each time it closes.")
    }
    val summary = remember(shown) { TapSummary(shown) }
    Numbers(summary, shown.screens.size > 1)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        val pills = @Composable { SectionPills(TapMode.entries, mode, { it.title }) { mode = it } }
        if (shown.screens.size > 1) {
            val row = @Composable { named: Boolean ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    pills()
                    Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
                    Screens(shown, named) { signature = it }
                }
            }
            FirstThatFits({ row(true) }, { row(false) })
        } else {
            pills()
        }
        TapMap(shown, mode, heat, selected) { selected = it }
        Legend(mode, selected != null)
    }
    shown.aims.firstOrNull { it.key == selected }?.let { KeyDetail(shown, it) { selected = null } }
    Thumbs(shown, summary)
    Misses(shown, summary, selected) { selected = it }
}

/** The screen whose taps show, at the end of the map's pills, by name where it fits. */
@Composable
private fun Screens(board: TapBoard, named: Boolean, pick: (String) -> Unit) {
    val palette = palette()
    var open by remember { mutableStateOf(false) }
    Box {
        PillMenuLabel(
            "rectangle.on.rectangle",
            if (named) board.screens.firstOrNull { it.signature == board.signature }?.title ?: "Screen" else null,
            Modifier.clip(CircleShape).clickable { open = true },
        )
        DropdownMenu(open, { open = false }, containerColor = palette.card) {
            board.screens.forEach { screen ->
                DropdownMenuItem(
                    text = {
                        Column {
                            Text(screen.title, color = palette.label)
                            Text("${Format.count(screen.taps)} taps", color = palette.secondary, fontSize = 13.sp)
                        }
                    },
                    onClick = {
                        open = false
                        pick(screen.signature)
                    },
                )
            }
        }
    }
}

/** How often your letters land on the key meant, large, over a meter of it, then how many taps and how far off center. */
@Composable
private fun Numbers(summary: TapSummary, perScreen: Boolean) {
    val palette = palette()
    val trend = summary.lately?.let { ((it.first - summary.onTarget) * 100).roundToInt().takeIf { points -> points != 0 } }
    StatCard("scope", Hues.blue.on(palette), "On target") {
        LeadNumber(Format.percent(summary.onTarget), 52f, trend?.let { { TrendChip(it) } })
        Meter(summary.onTarget)
        val share = "Letter taps that land on the key you meant."
        Caption(summary.lately?.let { "$share Your last ${Format.count(it.second)}: ${Format.percent(it.first)}." } ?: share)
        Hairline()
        Figures(
            listOf(
                Figure(
                    Format.count(summary.taps),
                    if (perScreen) "taps on this screen" else if (summary.taps == 1) "tap learned" else "taps learned",
                ),
                Figure("%.1f dp".format(summary.offCenter), "aim off center"),
            ),
        )
    }
}

/** A share as a thin bar, the part on target in blue and the rest in orange. */
@Composable
private fun Meter(share: Double) {
    val palette = palette()
    BoxWithConstraints(Modifier.fillMaxWidth().padding(top = 6.dp).height(8.dp)) {
        val total = maxWidth
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            val blue = Modifier.height(8.dp).clip(CircleShape).background(Tints.gradient(Hues.blue.on(palette)))
            if (share >= 0.995) {
                Box(blue.fillMaxWidth())
            } else {
                Box(blue.width(maxOf(total * share.toFloat() - 1.dp, 4.dp)))
                Box(Modifier.weight(1f).height(8.dp).clip(CircleShape).background(Tints.miss(palette).copy(alpha = 0.85f)))
            }
        }
    }
}

/** What the map's marks mean, for the mode it's in. */
@Composable
private fun Legend(mode: TapMode, selected: Boolean) {
    val palette = palette()
    val accent = Hues.blue.on(palette)
    Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when (mode) {
            TapMode.HEAT -> Scale("Fewer taps", "More", (0 until 24).map { TapHeat.color(sqrt(it / 23.0), palette.isDark) })
            TapMode.AIM -> Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Mark("Recent taps") { drawCircle(accent.copy(alpha = 0.85f), 3.5f * density, center) }
                Mark("Half land inside") { memory(0, center, accent, density) }
                Mark("Where you aim") {
                    drawCircle(keyFill(palette), 6 * density, center)
                    drawCircle(accent, 4.5f * density, center)
                }
            }
            TapMode.ACCURACY -> Scale("1% missed", "25%", (0 until 8).map { Tints.miss(palette).copy(alpha = 0.12f + it / 7f * 0.73f) })
        }
        val about = when (mode) {
            TapMode.HEAT -> "Where your thumbs land most."
            TapMode.AIM -> "Each key’s last taps, and where you aim for it."
            TapMode.ACCURACY -> if (selected) "Where the picked key’s taps land." else "How often each key’s taps land on another."
        }
        Caption(if (selected) about else "$about Tap a key to see it up close.")
    }
}

@Composable
private fun Scale(start: String, end: String, colors: List<Color>) {
    val palette = palette()
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(start, color = palette.secondary, fontSize = 12.sp, maxLines = 1)
        Box(
            Modifier.weight(1f).height(6.dp).clip(CircleShape).background(Tints.backdrop(palette))
                .background(Brush.horizontalGradient(colors)),
        )
        Text(end, color = palette.secondary, fontSize = 12.sp, maxLines = 1)
    }
}

@Composable
private fun Mark(title: String, draw: androidx.compose.ui.graphics.drawscope.DrawScope.() -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Canvas(Modifier.size(14.dp)) { draw() }
        Text(title, color = palette().secondary, fontSize = 12.sp, maxLines = 1)
    }
}

/** A key's name on a small keycap. */
@Composable
private fun Keycap(name: String, size: Float, alpha: Float = 1f) {
    val palette = palette()
    Box(
        Modifier.width((size * if (name.length == 1) 0.9f else 1.5f).dp).height(size.dp)
            .clip(RoundedCornerShape((size * 0.22f).dp)).background(palette.pressed.copy(alpha = alpha)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            name, color = palette.label.copy(alpha = alpha), fontSize = (if (name.length == 1) size * 0.5f else size * 0.3f).sp,
            fontWeight = FontWeight.Medium, maxLines = 1,
        )
    }
}

/** One key up close: how often it lands, where you aim, its last taps around it, where they land, what its aim follows. */
@Composable
private fun KeyDetail(board: TapBoard, aim: TapBoard.Aim, close: () -> Unit) {
    val palette = palette()
    val name = board.box(aim).name
    Column(Modifier.fillMaxWidth().card(palette).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            Keycap(name, 56f)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(Format.percent(aim.onTarget), style = display(30f), color = palette.label)
                Text("on target", color = palette.secondary, fontSize = 13.sp)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(Format.count(aim.taps), style = display(30f), color = palette.label)
                Text(if (aim.taps == 1) "tap" else "taps", color = palette.secondary, fontSize = 13.sp)
            }
            Spacer(Modifier.weight(1f))
            Box(
                Modifier.size(30.dp).clip(CircleShape).background(palette.pressed).clickable(onClick = close),
                contentAlignment = Alignment.Center,
            ) {
                Icon(glyph(Glyphs.XMARK, 2.6f), "Close", tint = palette.secondary, modifier = Modifier.size(13.dp))
            }
        }
        val drift = TapSummary.describe(board.drift(aim))
        Text(
            if (drift == "On center") "You aim at its center." else "You aim $drift of its center.",
            color = palette.secondary, fontSize = 15.sp,
        )
        CloseUp(board, aim)
        if (aim.recent.isNotEmpty()) {
            val hits = aim.recent.count { it.landed == aim.key }
            val strays = aim.recent.mapNotNull { it.landed?.takeIf { key -> key != aim.key } }.groupingBy { it }.eachCount()
                .entries.sortedByDescending { it.value }.joinToString(", ") { "${board.keys[it.key].name} ${it.value}" }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Dot(Hues.blue.on(palette), "$hits of the last ${aim.recent.size} on $name")
                if (strays.isNotEmpty()) Dot(Tints.miss(palette), strays)
            }
        }
        Section("Where its taps land") {
            val misses = aim.landing.filter { it.key != aim.key }.take(3).filter { it.share >= 0.005 }
            val parts = listOf(Triple(name, aim.onTarget, Hues.blue.on(palette))) +
                misses.map { Triple(board.keys[it.key].name, it.share, Tints.miss(palette)) }
            val rest = 1 - parts.sumOf { it.second }
            SegmentedBar(if (rest >= 0.005) parts + Triple("other", rest, palette.secondary.copy(alpha = 0.45f)) else parts)
        }
        Section("Its aim follows") { MemoryBar(aim.memories.map { it.weight }) }
    }
}

@Composable
private fun Dot(color: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(7.dp).background(color.copy(alpha = 0.85f), CircleShape))
        Text(text, color = palette().secondary, fontSize = 13.sp)
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, color = palette().label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        content()
    }
}

/** How much a key's aim leans on all its taps, about its last 30 and about its last 3, in one thin bar. */
@Composable
private fun MemoryBar(weights: List<Double>) {
    val palette = palette()
    val names = listOf("All taps", "Last 30", "Last 3")
    val strengths = listOf(0.9f, 0.5f, 0.22f)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(8.dp)) {
            val width = maxWidth - 2.dp * (weights.size - 1)
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                weights.forEachIndexed { index, weight ->
                    Box(
                        Modifier.width(maxOf(width * weight.toFloat(), 4.dp)).height(8.dp).clip(CircleShape)
                            .background(palette.label.copy(alpha = strengths[index])),
                    )
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            weights.forEachIndexed { index, weight ->
                Mark("${names[index]} ${Format.percent(weight)}") { memory(index, center, palette.label, density) }
            }
        }
    }
}

/** Every key's pull as an arrow, then where each half of the keyboard and the space bar aim, each on a small target. */
@Composable
private fun Thumbs(board: TapBoard, summary: TapSummary) {
    val palette = palette()
    StatCard("arrow.up.and.down.and.arrow.left.and.right", Hues.blue.on(palette), "How your thumbs pull") {
        Pull(board)
        val targets = summary.halves + listOfNotNull(summary.space?.let { "Space bar" to it })
        val reach = maxOf(2.5, targets.maxOfOrNull { hypot(it.second.x, it.second.y) } ?: 0.0)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            targets.forEach { (name, drift) ->
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Target(drift, reach)
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            TapSummary.describe(drift, "\n"), color = palette.label, fontSize = 15.sp,
                            fontWeight = FontWeight.Medium, maxLines = 2,
                        )
                        Text(name, color = palette.secondary, fontSize = 13.sp, maxLines = 1)
                    }
                }
            }
        }
        Caption("Each arrow runs from a key’s center to where you aim for it, drawn ${MAGNIFY.toInt()}× as long.")
    }
}

/** The share of each letter's taps that land on another key, most missed first, and where the worst three go. */
@Composable
private fun Misses(board: TapBoard, summary: TapSummary, selected: Int?, pick: (Int) -> Unit) {
    val palette = palette()
    val shown = summary.misses.filter { it.share >= 0.005 }
    if (shown.isEmpty()) return
    val typical = 1 - summary.onTarget
    val miss = Tints.miss(palette)
    StatCard("xmark.circle.fill", Hues.orange.on(palette), "Misses by key") {
        val top = maxOf(shown.first().share, 0.05, typical * 1.4)
        ColumnChart(
            shown.map { listOf(it.share) }, listOf(Tints.gradient(miss.copy(alpha = 0.9f))),
            top, 132.dp,
            shown.mapIndexed { index, it -> Tick(index, board.keys[it.key].name, true) }, ratio = 0.62f,
            yLabel = { Format.percent(it) }, marks = niceMarks(top, 3), dim = { selected != null && shown[it].key != selected },
            rule = Rule(typical, "all letters ${Format.percent(typical)}", weight = FontWeight.Medium),
            onPick = { index -> index?.let { pick(shown[it].key) } },
        )
        Column {
            shown.take(3).forEachIndexed { index, it ->
                if (index > 0) Hairline()
                Row(
                    Modifier.fillMaxWidth().clickable { pick(it.key) }.padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Keycap(board.keys[it.key].name, 34f)
                    it.onto?.let { onto ->
                        Icon(Symbols["arrow.right"], null, tint = palette.secondary, modifier = Modifier.size(17.7.dp))
                        Keycap(board.keys[onto].name, 34f, 0.75f)
                    }
                    Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
                    Text(Format.percent(it.share), style = display(20f), color = palette.label)
                    Text("missed", color = palette.secondary, fontSize = 13.sp)
                }
            }
        }
        Caption("Each letter’s taps that land on another key, most missed first.")
    }
}

/** A menu at the end of a row of pills, in their unpicked look: its glyph, what it's set to, and the up-down chevron (iOS's `PillMenuLabel`). */
@Composable
fun PillMenuLabel(symbol: String, title: String?, modifier: Modifier = Modifier) {
    val palette = palette()
    Row(
        modifier.height(36.dp).padding(horizontal = 13.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(Symbols[symbol], null, tint = palette.secondary, modifier = Modifier.size(23.2.dp))
        if (title != null) Text(title, color = palette.secondary, fontSize = 16.sp, fontWeight = FontWeight.Medium, maxLines = 1)
        Icon(Symbols["chevron.up.chevron.down"], null, tint = palette.secondary, modifier = Modifier.size(16.4.dp))
    }
}
