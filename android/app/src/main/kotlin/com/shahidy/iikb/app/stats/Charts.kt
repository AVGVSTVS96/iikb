package com.shahidy.iikb.app.stats

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.inset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.app.design.Format
import com.shahidy.iikb.app.palette
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.pow

/** A label under a chart's column: centered on it, or starting at its leading edge. */
class Tick(val index: Int, val text: String, val centered: Boolean = false)

/**
 * Round values from 0 to `top` for an axis, about `count` of them, a step of 1, 2 or 5 times a power of ten, as Swift
 * Charts' automatic marks pick them.
 */
fun niceMarks(top: Double, count: Int): List<Double> {
    if (top <= 0) return listOf(0.0)
    val rough = top / count
    val power = 10.0.pow(floor(log10(rough)))
    val step = listOf(1.0, 2.0, 5.0, 10.0).map { it * power }.minBy { abs(ln(it / rough)) }
    return (0..(top / step + 1e-9).toInt()).map { it * step }
}

/** A dashed line across a chart at `value`, with a note over its trailing end, or its leading one. */
class Rule(val value: Double, val note: String? = null, val leading: Boolean = false, val weight: FontWeight = FontWeight.Normal)

/**
 * Columns, each a stack of `values` (one per series, bottom first, painted by `fills`, a gradient spanning each piece as
 * Swift Charts paints a mark), or with `lines` the same values as a line per series through the days that have one. The
 * y axis reads `marks` (0, half and `top`, on dashed lines, unless given) at the trailing edge (`yLabel`), or nothing
 * without one. A tap picks a column and a horizontal drag moves the pick; a tap on the picked one lets it go.
 */
@Composable
fun ColumnChart(
    values: List<List<Double?>>,
    fills: List<Brush>,
    top: Double,
    height: Dp,
    ticks: List<Tick>,
    ratio: Float = 0.7f,
    radius: Dp = 3.dp,
    yLabel: ((Double) -> String)? = { Format.short(it.toInt()) },
    marks: List<Double>? = null,
    lines: Boolean = false,
    lineColors: List<Color> = emptyList(),
    dim: (Int) -> Boolean = { false },
    rule: Rule? = null,
    picked: Int? = null,
    onPick: ((Int?) -> Unit)? = null,
    annotate: (Int) -> Pair<String, Color>? = { null },
    tickStyle: TextStyle? = null,
) {
    val palette = palette()
    val measurer = rememberTextMeasurer()
    val label = TextStyle(color = palette.axis, fontSize = 11.sp)
    val tickLabel = tickStyle?.let(label::merge) ?: label
    val count = values.size.coerceAtLeast(1)
    val shownMarks = marks ?: listOf(0.0, top / 2, top)
    val gap = with(LocalDensity.current) { 6.dp.toPx() }
    val axis = yLabel?.let { name -> shownMarks.maxOf { measurer.measure(name(it), label).size.width } + gap } ?: 0f
    var modifier = Modifier.fillMaxWidth().height(height)
    if (onPick != null) {
        modifier = modifier
            .pointerInput(count, picked, axis) {
                detectTapGestures { offset ->
                    val index = column(offset.x, size.width - axis, count)
                    onPick(if (index == picked) null else index)
                }
            }
            .pointerInput(count, axis) {
                detectHorizontalDragGestures { change, _ ->
                    onPick(column(change.position.x, size.width - axis, count))
                }
            }
    }
    Canvas(modifier) {
        val bottom = size.height - 18.dp.toPx()
        val plot = size.width - axis
        val step = plot / count
        val y = { value: Double -> (bottom - (value / top).coerceIn(0.0, 1.0) * bottom).toFloat() }
        val dash = if (marks == null) PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 3.dp.toPx())) else null
        if (yLabel != null) {
            for (mark in shownMarks) {
                drawLine(palette.divider, Offset(0f, y(mark)), Offset(plot, y(mark)), 1.dp.toPx(), pathEffect = dash)
                text(measurer, yLabel(mark), label, Offset(plot + 6.dp.toPx(), y(mark)), centerY = true)
            }
        }
        if (lines) {
            values.firstOrNull()?.indices?.forEach { series ->
                val color = lineColors.getOrElse(series) { palette.accent }
                val points = values.mapIndexedNotNull { index, column ->
                    column[series]?.let { Offset(step * (index + 0.5f), y(it)) }
                }
                val path = Path()
                points.forEachIndexed { index, point -> if (index == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y) }
                drawPath(path, color, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round))
                val dot = if (count > 30) 1.8.dp.toPx() else 2.6.dp.toPx()
                points.forEach { drawCircle(color, dot, it) }
            }
        } else {
            val width = step * ratio
            val corner = radius.toPx()
            values.forEachIndexed { index, column ->
                val alpha = if ((picked != null && picked != index) || dim(index)) 0.35f else 1f
                var base = 0.0
                val x = step * index + (step - width) / 2
                val stack = column.withIndex().filter { (it.value ?: 0.0) > 0 }
                stack.forEachIndexed { position, (series, value) ->
                    val low = y(base)
                    base += value!!
                    val high = y(base)
                    val rect = RoundRect(
                        0f, 0f, width, low - high,
                        topLeftCornerRadius = if (position == stack.lastIndex) CornerRadius(corner) else CornerRadius.Zero,
                        topRightCornerRadius = if (position == stack.lastIndex) CornerRadius(corner) else CornerRadius.Zero,
                    )
                    inset(x, high, size.width - x - width, size.height - low) {
                        drawPath(Path().apply { addRoundRect(rect) }, fills[series % fills.size], alpha = alpha)
                    }
                }
            }
        }
        values.indices.forEach { index ->
            val (note, color) = annotate(index) ?: return@forEach
            val top = y(values[index].sumOf { it ?: 0.0 })
            val layout = measurer.measure(note, label.copy(color = color, fontSize = 11.sp, fontWeight = FontWeight.SemiBold))
            drawText(layout, topLeft = Offset(step * (index + 0.5f) - layout.size.width / 2, top - layout.size.height - 2.dp.toPx()))
        }
        if (picked != null) {
            val x = step * (picked + 0.5f)
            drawLine(palette.secondary.copy(alpha = 0.4f), Offset(x, 0f), Offset(x, bottom), 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())))
        }
        if (rule != null) {
            val at = y(rule.value)
            drawLine(palette.secondary.copy(alpha = 0.7f), Offset(0f, at), Offset(plot, at), 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())))
            rule.note?.let {
                val note = measurer.measure(it, label.copy(color = palette.secondary, fontWeight = rule.weight))
                drawText(note, topLeft = Offset(if (rule.leading) 0f else plot - note.size.width, at - note.size.height - 2.dp.toPx()))
            }
        }
        for (tick in ticks) {
            val x = if (tick.centered) step * (tick.index + 0.5f) else step * tick.index + (step - step * ratio) / 2
            text(measurer, tick.text, tickLabel, Offset(x, bottom + 4.dp.toPx()), centerX = tick.centered, fit = size.width)
        }
    }
}

private fun column(x: Float, plot: Float, count: Int) = (x / (plot / count)).toInt().coerceIn(0, count - 1)

/** Draws `text` at `at`, centered on it where asked, and kept from running past `fit`, as Swift Charts' labels may run
 * out on the leading side. */
fun DrawScope.text(
    measurer: TextMeasurer, text: String, style: TextStyle, at: Offset, centerX: Boolean = false,
    centerY: Boolean = false, fit: Float = Float.MAX_VALUE,
) {
    val layout = measurer.measure(text, style)
    var x = if (centerX) at.x - layout.size.width / 2 else at.x
    x = x.coerceAtMost(fit - layout.size.width)
    val y = if (centerY) at.y - layout.size.height / 2 else at.y
    drawText(layout, topLeft = Offset(x, y))
}

/** A rounded square for the year's grid. */
fun DrawScope.square(color: Color, at: Offset, side: Float, corner: Float) =
    drawRoundRect(color, at, Size(side, side), CornerRadius(corner))
