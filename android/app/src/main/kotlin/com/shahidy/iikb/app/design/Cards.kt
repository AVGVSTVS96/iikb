package com.shahidy.iikb.app.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
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
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.app.Palette
import com.shahidy.iikb.app.glyph
import com.shahidy.iikb.app.palette
import java.text.NumberFormat
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt

val Palette.isDark get() = this == Palette.dark

/** iOS's system colors as they change with the page's appearance, for the charts and figures on cards. */
object Tints {
    fun blue(p: Palette) = if (p.isDark) Color(0xFF0A84FF) else Color(0xFF007AFF)
    fun pink(p: Palette) = if (p.isDark) Color(0xFFFF375F) else Color(0xFFFF2D55)
    fun indigo(p: Palette) = if (p.isDark) Color(0xFF5E5CE6) else Color(0xFF5856D6)
    fun orange(p: Palette) = if (p.isDark) Color(0xFFFF9F0A) else Color(0xFFFF9500)
    fun teal(p: Palette) = if (p.isDark) Color(0xFF40CBE0) else Color(0xFF30B0C7)
    fun green(p: Palette) = if (p.isDark) Color(0xFF30D158) else Color(0xFF34C759)
    fun purple(p: Palette) = if (p.isDark) Color(0xFFBF5AF2) else Color(0xFFAF52DE)
    fun yellow(p: Palette) = if (p.isDark) Color(0xFFFFD60A) else Color(0xFFFFCC00)
    fun cyan(p: Palette) = if (p.isDark) Color(0xFF64D2FF) else Color(0xFF32ADE6)
    fun gray(p: Palette) = Color(0xFF8E8E93)

    /** Taps' misses (TapMapPalette.miss). */
    fun miss(p: Palette) = if (p.isDark) Color(0xFFD95926) else Color(0xFFEB6834)

    /** The keys' backdrop in Taps (TapMapPalette.backdrop). */
    fun backdrop(p: Palette) = if (p.isDark) Color(0xFF202020) else Color(0xFFE2E3E8)

    /** SwiftUI's `.gradient` on a color: a touch lighter at the top. */
    fun gradient(color: Color) = Brush.verticalGradient(listOf(lighter(color), color))

    private fun lighter(color: Color) = Color(
        color.red + (1 - color.red) * 0.18f, color.green + (1 - color.green) * 0.18f,
        color.blue + (1 - color.blue) * 0.18f, color.alpha,
    )
}

/** Big numbers, tracked tight, as iOS's Helvetica Neue Bold figures are. */
fun display(size: Float) = TextStyle(
    fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Bold, fontSize = size.sp, letterSpacing = (-0.03).em,
)

/** A white glyph on a colored rounded square, as Raycast draws its commands. */
@Composable
fun GlyphTile(path: String, color: Color, size: Dp = 26.dp) {
    Box(
        Modifier.size(size).clip(RoundedCornerShape(size * 0.26f)).background(Tints.gradient(color)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(glyph(path, 2.2f), null, tint = Color.White, modifier = Modifier.size(size * 0.58f))
    }
}

/** A card with a hairline edge, as every Stats card is. */
fun Modifier.card(palette: Palette) = clip(RoundedCornerShape(22.dp)).background(palette.card)
    .border(BorderStroke(1.dp, palette.edge), RoundedCornerShape(22.dp))

/** A Stats card: a colored glyph, a title and a gray line on what it shows at its top, then what it shows. */
@Composable
fun StatCard(
    glyph: String, color: Color, title: String, subtitle: String? = null,
    accessory: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit,
) {
    val palette = palette()
    Column(
        Modifier.fillMaxWidth().card(palette).padding(18.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        val heading = @Composable {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GlyphTile(glyph, color)
                Column {
                    Text(title, color = palette.label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    if (subtitle != null) Text(subtitle, color = palette.secondary, fontSize = 13.sp)
                }
            }
        }
        if (accessory == null) {
            heading()
        } else {
            FirstThatFits(
                { Row(Modifier.fillMaxWidth()) { heading(); Spacer(Modifier.weight(1f).widthIn(min = 8.dp)); accessory() } },
                { Column(verticalArrangement = Arrangement.spacedBy(12.dp)) { heading(); accessory() } },
            )
        }
        content()
    }
}

/** A card's note on what it shows, in gray. */
@Composable
fun Caption(text: String) = Text(text, color = palette().secondary, fontSize = 13.sp, lineHeight = 17.sp)

@Composable
fun Hairline() = Box(Modifier.fillMaxWidth().height(1.dp).background(palette().divider))

/** The first of `options` whose natural width fits, else the last, as SwiftUI's `ViewThatFits`. */
@Composable
fun FirstThatFits(vararg options: @Composable () -> Unit) {
    SubcomposeLayout { constraints ->
        val loose = constraints.copy(minWidth = 0)
        var chosen = options.lastIndex
        for (index in 0 until options.lastIndex) {
            val natural = subcompose("measure$index", options[index]).maxOfOrNull { it.maxIntrinsicWidth(Constraints.Infinity) } ?: 0
            if (natural <= constraints.maxWidth) {
                chosen = index
                break
            }
        }
        val placeables = subcompose(chosen, options[chosen]).map { it.measure(loose) }
        val width = placeables.maxOfOrNull { it.width } ?: 0
        val height = placeables.maxOfOrNull { it.height } ?: 0
        layout(width.coerceIn(constraints.minWidth, constraints.maxWidth), height) {
            placeables.forEach { it.place(0, 0) }
        }
    }
}

/** Raycast's pills for a page's own tabs: the picked one on a filled capsule. */
@Composable
fun <T> SectionPills(values: List<T>, picked: T, title: (T) -> String, onPick: (T) -> Unit) {
    val palette = palette()
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        values.forEach { value ->
            val on = value == picked
            val fill by animateColorAsState(if (on) palette.selected else Color.Transparent, label = "pill")
            Text(
                title(value), color = if (on) palette.selectedLabel else palette.secondary, fontSize = 16.sp,
                fontWeight = FontWeight.Medium, maxLines = 1,
                modifier = Modifier.clip(CircleShape).background(fill).clickable { onPick(value) }
                    .padding(horizontal = 13.dp, vertical = 8.dp),
            )
        }
    }
}

/** Small pills for a card's own choices, on a gray capsule, the picked one filled. */
@Composable
fun <T> ChoicePills(values: List<T>, picked: T, title: (T) -> String, onPick: (T) -> Unit) {
    val palette = palette()
    Row(Modifier.clip(CircleShape).background(palette.pressed).padding(2.dp)) {
        values.forEach { value ->
            val on = value == picked
            val fill by animateColorAsState(if (on) palette.selected else Color.Transparent, label = "choice")
            Text(
                title(value), color = if (on) palette.selectedLabel else palette.secondary, fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold, maxLines = 1,
                modifier = Modifier.clip(CircleShape).background(fill).clickable { onPick(value) }
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            )
        }
    }
}

/** A dot and a name, for a chart's legend. */
@Composable
fun LegendDot(color: Color, name: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Box(Modifier.size(7.dp).background(color, CircleShape))
        Text(name, color = palette().secondary, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1)
    }
}

/** A small number over its label, in a card's grid of facts. */
@Composable
fun Stat(label: String, value: String, unit: String? = null, detail: String? = null, detailColor: Color? = null) {
    val palette = palette()
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(label, color = palette.secondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(value, style = display(22f), color = palette.label, maxLines = 1)
            if (unit != null) {
                Text(
                    unit, color = palette.secondary, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1,
                    modifier = Modifier.padding(bottom = 2.dp),
                )
            }
        }
        if (detail != null) {
            Text(
                detail, color = detailColor ?: palette.secondary, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** Facts all in one row where each gets 118 wide, else in rows of `columns`. */
@Composable
fun StatGrid(columns: Int = 2, facts: List<@Composable () -> Unit>) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val across = if (maxWidth >= 118.dp * facts.size) facts.size else columns
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            facts.chunked(across).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { Box(Modifier.weight(1f)) { it() } }
                    repeat(across - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

/** A big number over its label, at the size its `Figures` gives it. */
class Figure(val value: String, val label: String)

/**
 * Figures side by side in columns of one width, all at `size` while every one fits, then all at 80% together, else one
 * under another, so they never shrink apart or run out of their card.
 */
@Composable
fun Figures(figures: List<Figure>, size: Float = 24f) {
    val small = (size * 0.8f).roundToInt().toFloat()
    FirstThatFits(
        { EqualColumns { figures.forEach { FigureView(it, size) } } },
        { EqualColumns { figures.forEach { FigureView(it, small) } } },
        { Column(verticalArrangement = Arrangement.spacedBy(12.dp)) { figures.forEach { FigureView(it, small) } } },
    )
}

@Composable
private fun FigureView(figure: Figure, size: Float) {
    val palette = palette()
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(figure.value, style = display(size), color = palette.label, maxLines = 1, softWrap = false)
        Text(figure.label, color = palette.secondary, fontSize = 13.sp, maxLines = 1, softWrap = false)
    }
}

/** Columns of one width, each as wide as the widest needs, so `FirstThatFits` knows when one won't fit. */
@Composable
fun EqualColumns(spacing: Dp = 12.dp, content: @Composable () -> Unit) {
    Layout(content) { measurables, constraints ->
        val gap = spacing.roundToPx()
        val gaps = gap * (measurables.size - 1).coerceAtLeast(0)
        val count = measurables.size.coerceAtLeast(1)
        val width = if (constraints.hasBoundedWidth) {
            constraints.maxWidth
        } else {
            (measurables.maxOfOrNull { it.maxIntrinsicWidth(Constraints.Infinity) } ?: 0) * count + gaps
        }
        val column = ((width - gaps) / count).coerceAtLeast(0)
        val placeables = measurables.map { it.measure(Constraints(0, column, 0, constraints.maxHeight)) }
        layout(width, placeables.maxOfOrNull { it.height } ?: 0) {
            placeables.forEachIndexed { index, it -> it.place(index * (column + gap), 0) }
        }
    }
}

/** A card's big number and what goes beside it, on one line while it all fits, else what goes beside it under it. */
@Composable
fun LeadNumber(value: String, size: Float, beside: (@Composable () -> Unit)? = null) {
    val number = @Composable { Text(value, style = display(size), color = palette().label, maxLines = 1, softWrap = false) }
    if (beside == null) return number()
    FirstThatFits(
        { Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) { number(); beside() } },
        { Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { number(); beside() } },
    )
}

/** How lately compares: green and up when better, orange and down when worse. */
@Composable
fun TrendChip(points: Int, unit: String = " lately") {
    val palette = palette()
    val up = points > 0
    val color = if (up) Tints.green(palette) else Tints.miss(palette)
    Text(
        "${if (up) "+" else "−"}${abs(points)}$unit", color = color, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
        maxLines = 1, softWrap = false,
        modifier = Modifier.clip(CircleShape).background(color.copy(alpha = 0.14f)).padding(horizontal = 9.dp, vertical = 4.dp),
    )
}

/** A whole split into colored capsules with a gap between them, on an empty track while there's nothing. */
@Composable
fun Split(parts: List<Pair<Color, Double>>, height: Dp = 8.dp, modifier: Modifier = Modifier.fillMaxWidth()) {
    val track = palette().pressed
    Canvas(modifier.height(height)) {
        val radius = CornerRadius(size.height / 2)
        drawRoundRect(track, cornerRadius = radius)
        val total = parts.sumOf { it.second }
        if (total <= 0) return@Canvas
        val shown = parts.filter { it.second > 0 }
        val gap = if (shown.size > 1) 2.dp.toPx() else 0f
        val width = size.width - gap * (shown.size - 1)
        var x = 0f
        shown.forEach { (color, value) ->
            val w = maxOf(width * (value / total).toFloat(), size.height)
            drawRoundRect(Tints.gradient(color), Offset(x, 0f), Size(w, size.height), radius)
            x += w + gap
        }
    }
}

/** One whole split into parts, each its own block with its share on it where it fits, and their names under it. */
@Composable
fun SegmentedBar(parts: List<Triple<String, Double, Color>>) {
    val palette = palette()
    val shown = parts.filter { it.second >= 0.005 }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(28.dp)) {
            val gap = 2.dp
            val width = maxWidth - gap * (shown.size - 1).coerceAtLeast(0)
            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                shown.forEach { (_, share, color) ->
                    val w = maxOf(width * share.toFloat(), 3.dp)
                    Box(
                        Modifier.width(w).height(28.dp).clip(RoundedCornerShape(4.dp)).background(color),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        if (w >= 48.dp) {
                            Text(
                                Format.percent(share), color = Color.White, fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 8.dp),
                            )
                        }
                    }
                }
            }
        }
        val legend = @Composable {
            shown.forEach { (name, share, color) ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Box(Modifier.size(8.dp).clip(RoundedCornerShape(2.dp)).background(color))
                    Text("$name ${Format.percent(share)}", color = palette.secondary, fontSize = 13.sp, maxLines = 1, softWrap = false)
                }
            }
        }
        FirstThatFits(
            { Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) { legend() } },
            { Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { legend() } },
        )
    }
}

/** A page's empty state, as iOS's `ContentUnavailableView`: a glyph, a title, what to do, and a button for it. */
@Composable
fun Empty(glyph: String, title: String, text: String, action: Pair<String, () -> Unit>? = null) {
    val palette = palette()
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 72.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(glyph(glyph, 1.6f), null, tint = palette.secondary, modifier = Modifier.size(44.dp))
        Text(title, color = palette.label, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Text(text, color = palette.secondary, fontSize = 15.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (action != null) {
            Text(
                action.first, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 6.dp).clip(CircleShape).background(palette.accent)
                    .clickable(remember { MutableInteractionSource() }, null) { action.second() }
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            )
        }
    }
}

/** Numbers, dates and times as the iOS app writes them. */
object Format {
    private val integer = NumberFormat.getIntegerInstance()

    fun count(value: Int): String = integer.format(value)

    /** 1,234 below ten thousand, 12.3k and 1.2M above. */
    fun short(value: Int) = if (value >= 10_000) compact(value) else count(value)

    /** 860, 8.6k, 21k: a chart's label, short at any size. */
    fun compact(value: Int): String = when {
        value >= 1_000_000 -> trim(value / 1_000_000.0) + "m"
        value >= 1_000 -> trim(value / 1_000.0) + "k"
        else -> value.toString()
    }

    private fun trim(value: Double): String {
        val rounded = (value * 10).roundToInt() / 10.0
        return if (rounded >= 100 || rounded == floor(rounded)) rounded.roundToInt().toString() else "%.1f".format(rounded)
    }

    /** The round number at or above `value` a chart's top reads: 1, 1.5, 2, 2.5, 3, 4, 5, 6 or 8 times a power of ten. */
    fun roundUp(value: Double): Double {
        if (value <= 0) return 1.0
        val power = 10.0.pow(floor(log10(value)))
        return (listOf(1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0).firstOrNull { it * power >= value } ?: 10.0) * power
    }

    fun speed(speed: Double?) = speed?.roundToInt()?.toString() ?: "–"

    /** 45s, 12m, 1h 5m. */
    fun time(seconds: Double): String {
        if (seconds < 60) return "${seconds.toInt()}s"
        val minutes = (seconds / 60).roundToInt()
        return if (minutes < 60) "${minutes}m" else "${minutes / 60}h" + (minutes % 60).let { if (it > 0) " ${it}m" else "" }
    }

    fun day(date: LocalDate): String = date.format(DateTimeFormatter.ofPattern("MMM d"))

    fun hour(hour: Int): String = LocalTime.of(hour, 0).format(DateTimeFormatter.ofPattern("h a"))

    /** <1% for a share under one percent, else a whole percent. */
    fun percent(share: Double) = if (share > 0 && share < 0.01) "<1%" else "${(share * 100).roundToInt()}%"

    /** How much `now` is above or below `before`, once there's a before. */
    fun change(now: Double, before: Double): Pair<String, Boolean>? {
        if (before <= 0) return null
        val share = now / before - 1
        if (abs(share) < 0.005) return null
        return "${if (share > 0) "↑" else "↓"} ${(abs(share) * 100).roundToInt()}% vs previous" to (share > 0)
    }
}
