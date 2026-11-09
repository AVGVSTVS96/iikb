package com.shahidy.iikb

import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.takeOrElse
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.text
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.takeOrElse
import kotlin.math.roundToInt
import androidx.compose.material3.Text as MaterialText

/**
 * Text as UIKit sets San Francisco: tracked for its size as SF Pro is, and with no word left alone on a paragraph's
 * last line, which UIKit's standard line-break strategy (`.pushOut`) avoids by moving the line before's last word down.
 * Text with inline content, or that can be selected (`Selectable`), is Material's, and only takes the tracking.
 */
@Composable
fun Text(
    text: String, modifier: Modifier = Modifier, color: Color = Color.Unspecified, fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null, fontWeight: FontWeight? = null, fontFamily: FontFamily? = null,
    letterSpacing: TextUnit = TextUnit.Unspecified, textDecoration: TextDecoration? = null, textAlign: TextAlign? = null,
    lineHeight: TextUnit = TextUnit.Unspecified, overflow: TextOverflow = TextOverflow.Clip, softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE, minLines: Int = 1, onTextLayout: ((TextLayoutResult) -> Unit)? = null,
    style: TextStyle = LocalTextStyle.current,
) = Text(
    AnnotatedString(text), modifier, color, fontSize, fontStyle, fontWeight, fontFamily, letterSpacing, textDecoration,
    textAlign, lineHeight, overflow, softWrap, maxLines, minLines, emptyMap(), onTextLayout, style,
)

@Composable
fun Text(
    text: AnnotatedString, modifier: Modifier = Modifier, color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified, fontStyle: FontStyle? = null, fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null, letterSpacing: TextUnit = TextUnit.Unspecified,
    textDecoration: TextDecoration? = null, textAlign: TextAlign? = null, lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip, softWrap: Boolean = true, maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1, inlineContent: Map<String, InlineTextContent> = emptyMap(),
    onTextLayout: ((TextLayoutResult) -> Unit)? = null, style: TextStyle = LocalTextStyle.current,
) {
    val size = fontSize.takeOrElse { style.fontSize }.takeOrElse { 14.sp }
    val tracking = letterSpacing.takeOrElse {
        style.letterSpacing.takeIf { it.isSpecified && it != Tracking.base } ?: Tracking.at(size.value)
    }
    if (inlineContent.isNotEmpty() || maxLines == 1 || !softWrap || LocalSelectable.current) {
        return MaterialText(
            text, modifier, color = color, fontSize = fontSize, fontStyle = fontStyle, fontWeight = fontWeight,
            fontFamily = fontFamily, letterSpacing = tracking, textDecoration = textDecoration, textAlign = textAlign,
            lineHeight = lineHeight, overflow = overflow, softWrap = softWrap, maxLines = maxLines, minLines = minLines,
            inlineContent = inlineContent, onTextLayout = onTextLayout ?: {}, style = style,
        )
    }
    val resolved = style.merge(
        color = color.takeOrElse { style.color.takeOrElse { LocalContentColor.current } }, fontSize = fontSize,
        fontWeight = fontWeight, textAlign = textAlign ?: TextAlign.Unspecified, lineHeight = lineHeight,
        fontFamily = fontFamily, textDecoration = textDecoration, fontStyle = fontStyle, letterSpacing = tracking,
    )
    val measurer = rememberTextMeasurer()
    val drawn = remember { arrayOfNulls<TextLayoutResult>(1) }
    val clip = overflow != TextOverflow.Visible
    Layout(
        modifier.semantics { this.text = text }.let { if (clip) it.clipToBounds() else it }
            .drawBehind { drawn[0]?.let { drawText(it) } },
    ) { _, constraints ->
        val layout = pushOut(measurer, text, resolved, overflow, maxLines, constraints)
        drawn[0] = layout
        onTextLayout?.invoke(layout)
        val least = if (minLines > 1) {
            measurer.measure("\n".repeat(minLines - 1), resolved, constraints = constraints).size.height
        } else 0
        val baselines = mapOf<AlignmentLine, Int>(FirstBaseline to layout.firstBaseline.roundToInt(), LastBaseline to layout.lastBaseline.roundToInt())
        layout(layout.size.width, constraints.constrainHeight(maxOf(layout.size.height, least)), baselines) {}
    }
}

private val LocalSelectable = staticCompositionLocalOf { false }

/** Text that can be selected, which only Material's `Text` lays out for `SelectionContainer`. */
@Composable
fun Selectable(content: @Composable () -> Unit) = SelectionContainer {
    CompositionLocalProvider(LocalSelectable provides true, content = content)
}

/** SF Pro's tracking, as Apple's type tables give it in points at each size, set off Roboto's width at 17. */
object Tracking {
    /** What `Type.typography` tracks by: Roboto at 17 as wide as SF Pro there. */
    val base = 0.01.em

    private val points = mapOf(11 to 0.06f, 12 to 0f, 13 to -0.08f, 14 to -0.15f, 15 to -0.23f, 16 to -0.31f, 17 to -0.43f, 18 to -0.44f, 19 to -0.45f)

    fun at(size: Float): TextUnit {
        if (size > 19) return base
        val clamped = size.coerceAtLeast(11f)
        val low = clamped.toInt()
        val high = minOf(low + 1, 19)
        val fraction = clamped - low
        val track = { at: Int -> points.getValue(at) / at }
        val sf = track(low) * (1 - fraction) + track(high) * fraction
        return (base.value + sf - track(17)).em
    }
}

private fun pushOut(
    measurer: TextMeasurer, text: AnnotatedString, style: TextStyle, overflow: TextOverflow, maxLines: Int,
    constraints: Constraints,
): TextLayoutResult {
    val first = measurer.measure(text, style, overflow, softWrap = true, maxLines = maxLines, constraints = constraints)
    if (first.lineCount < 2 || first.hasVisualOverflow) return first
    val raw = text.text
    val breaks = (1 until first.lineCount).mapNotNull { line ->
        val start = first.getLineStart(line)
        val end = first.getLineEnd(line)
        val ends = end == raw.length || raw[end - 1] == '\n'
        val previousStart = first.getLineStart(line - 1)
        val joined = raw[start - 1] != '\n'
        val alone = raw.substring(start, end).trim().none { it.isWhitespace() }
        if (!ends || !joined || !alone) return@mapNotNull null
        raw.lastIndexOf(' ', start - 2).takeIf { it > previousStart }
    }
    if (breaks.isEmpty()) return first
    val moved = buildAnnotatedString {
        var from = 0
        breaks.forEach { at ->
            append(text.subSequence(from, at))
            append('\n')
            from = at + 1
        }
        append(text.subSequence(from, text.length))
    }
    val fixed = Constraints.fixedWidth(first.size.width).copy(maxHeight = constraints.maxHeight)
    val second = measurer.measure(moved, style, overflow, softWrap = true, maxLines = maxLines, constraints = fixed)
    return if (second.lineCount == first.lineCount && !second.hasVisualOverflow) second else first
}
