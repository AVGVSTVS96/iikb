package com.shahidy.iikb.app.design

import com.shahidy.iikb.app.Hues
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
import com.shahidy.iikb.Text
import com.shahidy.iikb.app.Type
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.app.Glyph
import com.shahidy.iikb.app.Palette
import com.shahidy.iikb.app.glyph
import com.shahidy.iikb.app.palette
import java.text.NumberFormat
import android.text.format.DateUtils
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt

val Palette.isDark get() = this == Palette.dark

/** The app's own colors beside iOS's system ones (`Hues`), as they change with the page's appearance. */
object Tints {
    /** A field's placeholder, iOS's `placeholderText`. */
    fun placeholder(p: Palette) = if (p.isDark) Color(0x4DEBEBF5) else Color(0x4D3C3C43)

    /** Taps' misses (TapMapPalette.miss). */
    fun miss(p: Palette) = Hues.miss.on(p)

    /** The keys' backdrop in Taps (TapMapPalette.backdrop). */
    fun backdrop(p: Palette) = if (p.isDark) Color(0xFF202020) else Color(0xFFE2E3E8)

    /** SwiftUI's `.gradient` on a color (`Hues.gradient`). */
    fun gradient(color: Color) = Hues.gradient(color)
}

/** Big numbers, tracked tight, as iOS's Helvetica Neue Bold figures are. */
fun display(size: Float) = TextStyle(
    fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Bold, fontSize = size.sp, letterSpacing = (-0.03).em,
)

/** A card with a hairline edge, as every Stats card is. */
fun Modifier.card(palette: Palette) = clip(RoundedCornerShape(22.dp)).background(palette.card)
    .border(BorderStroke(1.dp, palette.edge), RoundedCornerShape(22.dp))

/** A Stats card: a colored glyph, a title and a gray line on what it shows at its top, then what it shows. */
@Composable
fun StatCard(
    symbol: String, color: Color, title: String, subtitle: String? = null,
    accessory: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit,
) {
    val palette = palette()
    Column(
        Modifier.fillMaxWidth().card(palette).padding(18.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        val heading = @Composable {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Glyph(symbol, color, 26.dp)
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

/** A card's note on what it shows, in gray, taking at least `lines` lines' room. */
@Composable
fun Caption(text: String, lines: Int = 1) =
    Text(text, color = palette().secondary, fontSize = 13.sp, lineHeight = 18.sp, minLines = lines)

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
                title(value), color = if (on) palette.selectedLabel else palette.secondary, fontSize = Type.body,
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
fun Stat(
    label: String, value: String, unit: String? = null, detail: String? = null, detailColor: Color? = null,
    trend: Format.Change? = null,
) {
    val palette = palette()
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(label, color = palette.secondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(value, style = display(22f), color = palette.label, maxLines = 1, modifier = Modifier.alignByBaseline())
            if (unit != null) {
                Text(
                    unit, color = palette.secondary, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1,
                    modifier = Modifier.alignByBaseline(),
                )
            }
        }
        if (detail != null) {
            Text(
                detail, color = detailColor ?: palette.secondary, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        if (trend != null) {
            val color = detailColor ?: palette.secondary
            Text(
                buildAnnotatedString {
                    appendInlineContent("arrow")
                    append(" ${trend.text}")
                },
                color = color, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis,
                inlineContent = mapOf("arrow" to Arrow.inline(trend.up, color)),
            )
        }
    }
}

/**
 * SF Pro's ↑ and ↓ as iOS draws them in a line of text, measured off SF at 12 pt medium: Roboto's arrows are hairlines
 * beside SF's, which match its digits' weight.
 */
private object Arrow {
    fun inline(up: Boolean, color: Color) = InlineTextContent(
        Placeholder(0.794.em, 0.73.em, PlaceholderVerticalAlign.AboveBaseline),
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val em = size.width / 0.794f
            val x = 0.397f * em
            val head = 0.2525f * em
            fun y(above: Float) = if (up) size.height - above * em else size.height - (0.716f - above) * em
            val tip = y(0.6825f)
            val arms = if (up) tip + head else tip - head
            val path = Path().apply {
                moveTo(x, y(0.034f))
                lineTo(x, tip)
                moveTo(x - head, arms)
                lineTo(x, tip)
                lineTo(x + head, arms)
            }
            drawPath(path, color, style = Stroke(0.093f * em, cap = StrokeCap.Round, join = StrokeJoin.Round))
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
    val number = @Composable { modifier: Modifier ->
        Text(value, style = display(size), color = palette().label, maxLines = 1, softWrap = false, modifier = modifier)
    }
    if (beside == null) return number(Modifier)
    FirstThatFits(
        {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                number(Modifier.alignByBaseline())
                Box(Modifier.alignByBaseline()) { beside() }
            }
        },
        { Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { number(Modifier); beside() } },
    )
}

/** How lately compares: green and up when better, orange and down when worse. */
@Composable
fun TrendChip(points: Int, unit: String = " lately") {
    val palette = palette()
    val up = points > 0
    val color = if (up) Hues.green.on(palette) else Tints.miss(palette)
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
    /**
     * The narrow space before AM or PM, as wide as SF Pro's U+202F: Roboto has no U+202F, and the font Android falls
     * back to draws it a full space wide, so it's Roboto's hair space, held to its neighbors by word joiners.
     */
    const val NARROW = "\u2060\u200A\u2060"

    private val integer = NumberFormat.getIntegerInstance()

    fun count(value: Int): String = integer.format(value)

    /** 1,234 below ten thousand, 12.3k and 1.2M above. */
    fun short(value: Int) = if (value >= 10_000) compact(value) else count(value)

    /** 860, 8.6k, 21k, 136.7k: a chart's label, short at any size, as iOS's compact name with up to one decimal. */
    fun compact(value: Int): String {
        val (scale, suffix) = listOf(1e9 to "b", 1e6 to "m", 1e3 to "k").firstOrNull { (scale, _) ->
            Math.rint(abs(value) / scale * 10) / 10 >= 1
        } ?: return value.toString()
        val rounded = Math.rint(value / scale * 10) / 10
        return (if (rounded == floor(rounded)) rounded.toLong().toString() else "%.1f".format(rounded)) + suffix
    }

    /** The round number at or above `value` a chart's top reads: 1, 1.5, 2, 2.5, 3, 4, 5, 6 or 8 times a power of ten. */
    fun roundUp(value: Double): Double {
        if (value <= 0) return 1.0
        val power = 10.0.pow(floor(log10(value)))
        return (listOf(1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0).firstOrNull { it * power >= value } ?: 10.0) * power
    }

    fun speed(speed: Double?) = speed?.roundToInt()?.toString() ?: "–"

    /** 45s, 12m, 1h 5m. */
    fun time(seconds: Double): String = if (seconds < 60) "${seconds.toInt()}s" else units(seconds, withSeconds = false)

    /**
     * A length in its two largest units, narrow, as iOS's `Duration` units style writes it: 2m 45s, 1h 5m. The last unit
     * shown takes the rest, rounded half to even; a unit at zero is left out.
     */
    fun units(length: Double, withSeconds: Boolean = true): String {
        val allowed = listOf(3600L to "h", 60L to "m", 1L to "s").let { if (withSeconds) it else it.dropLast(1) }
        val first = allowed.indexOfFirst { length >= it.first }.let { if (it < 0) allowed.lastIndex else it }
        val last = minOf(first + 1, allowed.lastIndex)
        var rest = Math.rint(length / allowed[last].first).toLong() * allowed[last].first
        val parts = allowed.take(last + 1).mapNotNull { (size, unit) ->
            (rest / size).also { rest %= size }.takeIf { it > 0 }?.let { "$it$unit" }
        }.take(2)
        return parts.joinToString(" ").ifEmpty { "0${allowed[last].second}" }
    }

    /** 0:05, 2:45: a recording's length, minutes and seconds, as iOS's `.time(pattern: .minuteSecond)`. */
    fun clock(seconds: Double): String = Math.rint(seconds).toLong().let { "%d:%02d".format(it / 60, it % 60) }

    fun day(date: LocalDate): String = date.format(DateTimeFormatter.ofPattern("MMM d"))

    /** A time, with its day unless it's today's: "2:23 PM", "Nov 8, 2:23 PM". */
    fun moment(time: Instant): String {
        val local = time.atZone(ZoneId.systemDefault())
        val today = local.toLocalDate() == LocalDate.now()
        return local.format(DateTimeFormatter.ofPattern(if (today) "h:mm'$NARROW'a" else "MMM d, h:mm'$NARROW'a"))
    }

    /** How long ago, as iOS's named relative dates say it: "now", "8 minutes ago", "yesterday". */
    fun ago(time: Instant): String {
        val now = System.currentTimeMillis()
        val then = time.toEpochMilli()
        return if (now - then < 60_000) "now" else DateUtils.getRelativeTimeSpanString(then, now, DateUtils.MINUTE_IN_MILLIS).toString()
    }

    fun hour(hour: Int): String = LocalTime.of(hour, 0).format(DateTimeFormatter.ofPattern("h'$NARROW'a"))

    /** <1% for a share under one percent, else a whole percent. */
    fun percent(share: Double) = if (share > 0 && share < 0.01) "<1%" else "${(share * 100).roundToInt()}%"

    /** How much `now` is above or below `before`, after the arrow `Stat` draws for it. */
    class Change(val text: String, val up: Boolean)

    /** How much `now` is above or below `before`, once there's a before. */
    fun change(now: Double, before: Double): Change? {
        if (before <= 0) return null
        val share = now / before - 1
        if (abs(share) < 0.005) return null
        return Change("${(abs(share) * 100).roundToInt()}% vs previous", share > 0)
    }
}

/** Raycast's search field: a magnifier and the query in a capsule card, with a clear button while there's a query. */
@Composable
fun SearchField(text: String, placeholder: String, onChange: (String) -> Unit) {
    val palette = palette()
    Row(
        Modifier.fillMaxWidth().height(44.dp).clip(CircleShape).background(palette.card)
            .border(BorderStroke(1.dp, palette.edge), CircleShape).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(glyph(Glyphs.SEARCH, 2f), null, tint = palette.secondary, modifier = Modifier.size(22.dp))
        androidx.compose.foundation.text.BasicTextField(
            text, onChange, Modifier.weight(1f), singleLine = true,
            textStyle = TextStyle(color = palette.label, fontSize = 17.sp),
            cursorBrush = androidx.compose.ui.graphics.SolidColor(palette.accent),
            decorationBox = { inner ->
                if (text.isEmpty()) Text(placeholder, color = Tints.placeholder(palette), fontSize = 17.sp, maxLines = 1)
                inner()
            },
        )
        if (text.isNotEmpty()) {
            Box(Modifier.size(28.dp).clip(CircleShape).clickable { onChange("") }, contentAlignment = Alignment.Center) {
                Icon(glyph(Glyphs.CLEAR, 2f), "Clear", tint = palette.secondary, modifier = Modifier.size(18.dp))
            }
        }
    }
}

/** A box of rows under a gray header, as a day's transcripts or clips sit. */
@Composable
fun Rows(header: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val palette = palette()
    Column(Modifier.fillMaxWidth()) {
        if (header != null) {
            Text(
                header, color = palette.secondary, fontSize = 15.sp, fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 8.dp),
            )
        }
        Column(Modifier.fillMaxWidth().card(palette), content = content)
    }
}
