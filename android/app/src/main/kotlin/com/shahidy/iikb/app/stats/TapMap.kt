package com.shahidy.iikb.app.stats

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.app.Palette
import com.shahidy.iikb.app.design.Format
import com.shahidy.iikb.app.design.Tints
import com.shahidy.iikb.app.design.isDark
import com.shahidy.iikb.app.palette
import com.shahidy.iikb.keyboard.Glyphs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.sin

enum class TapMode(val title: String) { HEAT("Heat"), AIM("Aim"), ACCURACY("Accuracy") }

/** A keycap's fill on the Taps backdrop, every key's alike, as the keyboard's own theme draws them (iOS's `TapMapView`). */
fun keyFill(palette: Palette) = if (palette.isDark) Color(0xFF3D3D40) else Color.White

/**
 * The keyboard at its size, or smaller where the card is narrower, with what the touch model learned drawn over it, as
 * iOS's `TapMapView` draws it: how densely taps land (Heat), where each key's taps land (Aim), or how many land on the
 * key meant (Accuracy). A tap picks a key, and again lets it go.
 */
@Composable
fun TapMap(board: TapBoard, mode: TapMode, heat: ImageBitmap?, selected: Int?, onSelect: (Int?) -> Unit) {
    val palette = palette()
    val measurer = rememberTextMeasurer()
    val accent = Tints.blue(palette)
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val width = min(maxWidth.value, board.width.toFloat())
        val scale = width / board.width.toFloat()
        val shape = RoundedCornerShape(26.dp)
        Canvas(
            Modifier.width(width.dp).height((board.height * scale).dp).clip(shape)
                .border(BorderStroke(1.dp, palette.edge), shape)
                .pointerInput(board, selected) {
                    detectTapGestures { offset ->
                        val factor = density * scale
                        val key = board.key(offset.x / factor.toDouble(), offset.y / factor.toDouble())
                        val learns = board.aims.any { it.key == key }
                        onSelect(if (!learns || key == selected) null else key)
                    }
                },
        ) {
            drawRect(Tints.backdrop(palette))
            val factor = density * scale
            val text = min(1 / scale, 1.5f)
            scale(factor, factor, Offset.Zero) {
                val picked = board.aims.firstOrNull { it.key == selected }
                board.keys.forEach { key ->
                    drawRoundRect(
                        keyFill(palette), Offset(key.x.toFloat(), key.y.toFloat()),
                        Size(key.width.toFloat(), key.height.toFloat()), CornerRadius(8.5f),
                    )
                }
                when (mode) {
                    TapMode.HEAT -> heat(board, heat, picked, measurer, palette, accent, text)
                    TapMode.AIM -> aim(board, picked, measurer, palette, accent, text)
                    TapMode.ACCURACY ->
                        if (picked == null) {
                            shares(board, board.aims.map { it.key to it.onTarget }, null, measurer, palette, accent, text)
                        } else {
                            shares(board, picked.landing.map { it.key to it.share }, picked.key, measurer, palette, accent, text)
                        }
                }
            }
        }
    }
}

/** Text drawn centered at a point in the keyboard's dp, at `size` sp before the map's scale. */
private fun DrawScope.label(measurer: TextMeasurer, text: String, style: TextStyle, x: Double, y: Double, top: Boolean = false) {
    val layout = measurer.measure(text, style, density = androidx.compose.ui.unit.Density(1f))
    drawText(layout, topLeft = Offset(x.toFloat() - layout.size.width / 2f, if (top) y.toFloat() else y.toFloat() - layout.size.height / 2f))
}

private fun DrawScope.heat(
    board: TapBoard, heat: ImageBitmap?, picked: TapBoard.Aim?, measurer: TextMeasurer, palette: Palette, accent: Color,
    text: Float,
) {
    if (heat != null) {
        drawImage(
            heat, srcSize = IntSize(heat.width, heat.height),
            dstSize = IntSize(board.width.toInt(), board.height.toInt()),
        )
    }
    val halo = if (palette.isDark) Color.Black.copy(alpha = 0.7f) else keyFill(palette)
    board.keys.forEach { key ->
        if (!key.learns) return@forEach face(measurer, key, palette, text)
        val space = key.name == "space"
        val style = TextStyle(
            color = palette.label.copy(alpha = if (palette.isDark) 0.9f else 0.62f),
            fontSize = ((if (space) 13 else 17) * text).sp, fontWeight = FontWeight.Medium,
            shadow = Shadow(halo, blurRadius = if (palette.isDark) 4f else 3f),
        )
        if (space) {
            val layout = measurer.measure(key.name, style, density = androidx.compose.ui.unit.Density(1f))
            drawText(layout, topLeft = Offset(key.midX.toFloat() - layout.size.width / 2f, (key.y + key.height).toFloat() - layout.size.height - 4))
        } else {
            label(measurer, key.name, style, key.midX, key.midY)
        }
    }
    picked?.let { outline(board.box(it), accent) }
}

private fun DrawScope.outline(key: TapBoard.Box, color: Color) = drawRoundRect(
    color, Offset(key.x.toFloat() - 1, key.y.toFloat() - 1), Size(key.width.toFloat() + 2, key.height.toFloat() + 2),
    CornerRadius(9f), style = Stroke(2f),
)

/** Each key's recent taps as dots, the ellipse that holds half its taps, and a line from its center to their center. */
private fun DrawScope.aim(
    board: TapBoard, picked: TapBoard.Aim?, measurer: TextMeasurer, palette: Palette, accent: Color, text: Float,
) {
    board.keys.forEach { key -> if (key.learns) plain(measurer, key, palette, text) else face(measurer, key, palette, text) }
    for (aim in board.aims) {
        val alpha = picked?.let { if (it.key == aim.key) 1f else 0.25f } ?: 1f
        val box = board.box(aim)
        val center = Offset(aim.center.x.toFloat(), aim.center.y.toFloat())
        val origin = Offset(box.midX.toFloat(), box.midY.toFloat())
        aim.recent.forEach { drawCircle(accent.copy(alpha = 0.45f * alpha), 2 * text, Offset(it.x.toFloat(), it.y.toFloat())) }
        ellipse(aim, center, accent, alpha, if (picked?.key == aim.key) 2f * text else 1.25f * text, 0.12f, 0.9f)
        drawLine(accent.copy(alpha = 0.9f * alpha), origin, center, 1.5f * text, StrokeCap.Round)
        val cross = palette.secondary.copy(alpha = alpha)
        drawLine(cross, origin - Offset(3f, 0f), origin + Offset(3f, 0f), 1f)
        drawLine(cross, origin - Offset(0f, 3f), origin + Offset(0f, 3f), 1f)
        val r = 3 * text
        drawCircle(keyFill(palette).copy(alpha = alpha), r + 1.5f * text, center)
        drawCircle(accent.copy(alpha = alpha), r, center)
    }
}

private fun DrawScope.ellipse(
    aim: TapBoard.Aim, center: Offset, color: Color, alpha: Float, line: Float, fill: Float, stroke: Float,
    scale: Float = 1f,
) {
    val (major, minor, angle) = TapBoard.axes(aim.spread)
    val a = (major * TapBoard.half).toFloat() * scale
    val b = (minor * TapBoard.half).toFloat() * scale
    translate(center.x, center.y) {
        rotateRad(angle.toFloat(), Offset.Zero) {
            drawOval(color.copy(alpha = fill * alpha), Offset(-a, -b), Size(2 * a, 2 * b))
            drawOval(color.copy(alpha = stroke * alpha), Offset(-a, -b), Size(2 * a, 2 * b), style = Stroke(line))
        }
    }
}

/** A key that doesn't learn, with the face the keyboard gives it: its glyph, or its word as 123 has. */
private fun DrawScope.face(measurer: TextMeasurer, key: TapBoard.Box, palette: Palette, text: Float) = when (key.face) {
    "symbol" -> drawIntoCanvas {
        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = palette.label.toArgb() }
        Glyphs.draw(it.nativeCanvas, key.label, key.midX.toFloat(), key.midY.toFloat(), 20 * text, paint)
    }
    "text", "smallText" -> label(
        measurer, key.label, TextStyle(color = palette.label, fontSize = ((if (key.face == "text") 16 else 13) * text).sp),
        key.midX, key.midY,
    )
    else -> plain(measurer, key, palette, text)
}

/** A key's name, faint, as the map shows a key with nothing drawn on it. */
private fun DrawScope.plain(measurer: TextMeasurer, key: TapBoard.Box, palette: Palette, text: Float) {
    val letter = key.name.length == 1
    label(
        measurer, key.name, TextStyle(color = palette.label.copy(alpha = 0.3f), fontSize = ((if (letter) 20 else 13) * text).sp),
        key.midX, key.midY,
    )
}

/**
 * With no key picked, each key tinted by the share of its taps that land elsewhere, that share under its name once it's
 * 1% or more; with one picked, the share of its taps on each key, the key itself in the accent color.
 */
private fun DrawScope.shares(
    board: TapBoard, shares: List<Pair<Int, Double>>, target: Int?, measurer: TextMeasurer, palette: Palette,
    accent: Color, text: Float,
) {
    val byKey = shares.toMap()
    board.keys.forEachIndexed { index, key ->
        val share = byKey[index]
        val isTarget = index == target
        val miss = when {
            share == null -> 0.0
            target == null -> 1 - share
            isTarget -> 0.0
            else -> share
        }
        val shown = if (target == null) miss else share ?: 0.0
        if (share == null || !(isTarget || shown >= if (target == null) 0.01 else 0.005)) return@forEachIndexed plain(measurer, key, palette, text)
        val color = if (isTarget) accent.copy(alpha = 0.3f) else Tints.miss(palette).copy(alpha = (0.12 + min(miss / 0.25, 1.0) * 0.73).toFloat())
        drawRoundRect(color, Offset(key.x.toFloat(), key.y.toFloat()), Size(key.width.toFloat(), key.height.toFloat()), CornerRadius(8f))
        val name = measurer.measure(key.name, TextStyle(color = palette.secondary, fontSize = (11 * text).sp), density = androidx.compose.ui.unit.Density(1f))
        drawText(name, topLeft = Offset(key.x.toFloat() + 5 * text, key.y.toFloat() + 3 * text))
        val number = measurer.measure(
            Format.percent(shown),
            TextStyle(color = palette.label, fontSize = (13 * text).sp, fontWeight = if (miss >= 0.125) FontWeight.SemiBold else FontWeight.Medium),
            density = androidx.compose.ui.unit.Density(1f),
        )
        drawText(number, topLeft = Offset(key.midX.toFloat() - number.size.width / 2f, (key.y + key.height).toFloat() - number.size.height - 4 * text))
    }
}

/**
 * One key and its neighbors, enlarged: its last taps (blue where the grid reads them as the key, orange where it reads
 * another), the ellipse holding half its taps, where each of its three memories centers, and its aim.
 */
@Composable
fun CloseUp(board: TapBoard, aim: TapBoard.Aim) {
    val palette = palette()
    val measurer = rememberTextMeasurer()
    val accent = Tints.blue(palette)
    val miss = Tints.miss(palette)
    Canvas(Modifier.fillMaxWidth().height(220.dp).clip(RoundedCornerShape(16.dp))) {
        drawRect(Tints.backdrop(palette))
        val frame = board.box(aim)
        val across = min(frame.width, 44.0) * 0.7
        val down = frame.height * 0.35
        val region = aim.recent.fold(
            Rect(
                (frame.x - across).toFloat(), (frame.y - down).toFloat(), (frame.x + frame.width + across).toFloat(),
                (frame.y + frame.height + down).toFloat(),
            ),
        ) { region, tap ->
            Rect(
                min(region.left, tap.x.toFloat() - 4), min(region.top, tap.y.toFloat() - 4),
                maxOf(region.right, tap.x.toFloat() + 4), maxOf(region.bottom, tap.y.toFloat() + 4),
            )
        }.intersect(Rect(-4f, -4f, board.width.toFloat() + 4, board.height.toFloat() + 4))
        val dp = density
        val scale = min(min(size.width / region.width, size.height / region.height), 4f * dp)
        val origin = Offset(size.width / 2 - region.center.x * scale, size.height / 2 - region.center.y * scale)
        fun map(x: Double, y: Double) = Offset(origin.x + x.toFloat() * scale, origin.y + y.toFloat() * scale)
        val corner = min(8.5f * scale, 18 * dp)
        board.keys.forEachIndexed { index, key ->
            val topLeft = map(key.x, key.y)
            val rect = Size(key.width.toFloat() * scale, key.height.toFloat() * scale)
            if (topLeft.x > size.width || topLeft.y > size.height || topLeft.x + rect.width < 0 || topLeft.y + rect.height < 0) return@forEachIndexed
            drawRoundRect(keyFill(palette), topLeft, rect, CornerRadius(corner))
            val isTarget = index == aim.key
            val name = measurer.measure(
                key.name,
                TextStyle(
                    color = if (isTarget) palette.label else palette.secondary, fontSize = if (isTarget) 17.sp else 15.sp,
                    fontWeight = if (isTarget) FontWeight.SemiBold else FontWeight.Normal,
                ),
            )
            drawText(name, topLeft = Offset(maxOf(topLeft.x, 0f) + 9 * dp, maxOf(topLeft.y, 0f) + 6 * dp))
        }
        val targetTopLeft = map(frame.x, frame.y)
        drawRoundRect(accent, targetTopLeft, Size(frame.width.toFloat() * scale, frame.height.toFloat() * scale), CornerRadius(corner), style = Stroke(2 * dp))
        val center = map(aim.center.x, aim.center.y)
        ellipse(aim, center, accent, 1f, 1.25f * dp, 0.1f, 0.55f, scale)
        val middle = map(frame.midX, frame.midY)
        drawLine(palette.secondary, middle - Offset(5 * dp, 0f), middle + Offset(5 * dp, 0f), dp)
        drawLine(palette.secondary, middle - Offset(0f, 5 * dp), middle + Offset(0f, 5 * dp), dp)
        aim.recent.forEach { tap ->
            val point = map(tap.x, tap.y)
            drawCircle((if (tap.landed == aim.key) accent else miss).copy(alpha = 0.85f), 3.5f * dp, point)
            drawCircle(keyFill(palette).copy(alpha = 0.9f), 3.5f * dp, point, style = Stroke(dp))
        }
        drawCircle(keyFill(palette), 6 * dp, center)
        drawCircle(accent, 4.5f * dp, center)
        val points = aim.memories.map { map(it.x, it.y) }
        val trail = Path()
        points.forEachIndexed { index, point -> if (index == 0) trail.moveTo(point.x, point.y) else trail.lineTo(point.x, point.y) }
        drawPath(trail, palette.label.copy(alpha = 0.55f), style = Stroke(1.25f * dp, cap = StrokeCap.Round))
        points.forEachIndexed { index, point -> memory(index, point, palette.label, dp) }
    }
}

/** The close-up's mark for one of a key's three memories: all taps, the last 30, the last 3. */
fun DrawScope.memory(index: Int, at: Offset, color: Color, dp: Float) = when (index) {
    0, 1 -> drawCircle(color, (if (index == 0) 6f else 4f) * dp, at, style = Stroke(1.75f * dp))
    else -> drawCircle(color, 2.5f * dp, at)
}

/**
 * Every key's aim as an arrow from its center, drawn four times as long as it is, so how each thumb pulls across the
 * keyboard shows; short arrows are faint, so the keys that pull stand out.
 */
@Composable
fun Pull(board: TapBoard) {
    val palette = palette()
    val accent = Tints.blue(palette)
    Canvas(Modifier.fillMaxWidth().aspectRatio((board.width / board.height).toFloat().coerceAtLeast(0.1f))) {
        val scale = size.width / board.width.toFloat()
        drawRoundRect(Tints.backdrop(palette), cornerRadius = CornerRadius(16 * density))
        board.keys.forEach { key ->
            drawRoundRect(
                keyFill(palette), Offset(key.x.toFloat() * scale, key.y.toFloat() * scale),
                Size(key.width.toFloat() * scale, key.height.toFloat() * scale), CornerRadius(6 * scale),
            )
        }
        for (aim in board.aims) {
            if (aim.taps < 10 || board.isSpace(aim)) continue
            val box = board.box(aim)
            val drift = board.drift(aim)
            val start = Offset(box.midX.toFloat() * scale, box.midY.toFloat() * scale)
            val end = start + Offset(drift.x.toFloat() * MAGNIFY * scale, drift.y.toFloat() * MAGNIFY * scale)
            drawCircle(palette.secondary, 1.75f * density, start)
            val length = hypot(end.x - start.x, end.y - start.y)
            if (length < 3 * density) continue
            val color = accent.copy(alpha = 0.4f + 0.6f * min(1f, length / (24 * density)))
            val angle = atan2(end.y - start.y, end.x - start.x)
            val head = min(6 * density, length * 0.45f)
            val arrow = Path().apply {
                moveTo(start.x, start.y)
                lineTo(end.x, end.y)
                for (side in listOf(Math.PI * 0.8, -Math.PI * 0.8)) {
                    moveTo(end.x, end.y)
                    lineTo(end.x + head * cos(angle + side).toFloat(), end.y + head * sin(angle + side).toFloat())
                }
            }
            drawPath(arrow, color, style = Stroke(2 * density, cap = StrokeCap.Round, join = androidx.compose.ui.graphics.StrokeJoin.Round))
        }
    }
}

const val MAGNIFY = 4f

/** Where a part of the keyboard aims against its keys' centers: a crosshair, a ring each half `reach`, and the aim. */
@Composable
fun Target(drift: TapBoard.Point, reach: Double) {
    val palette = palette()
    val accent = Tints.blue(palette)
    Canvas(Modifier.size(76.dp)) {
        val radius = size.minDimension / 2
        val center = Offset(radius, size.height / 2)
        val scale = (radius - 7 * density) / reach.toFloat()
        drawCircle(Tints.backdrop(palette), radius, center)
        for (ring in listOf(reach / 2, reach)) drawCircle(palette.secondary.copy(alpha = 0.22f), ring.toFloat() * scale, center, style = Stroke(density))
        val cross = palette.secondary.copy(alpha = 0.3f)
        drawLine(cross, center - Offset(radius, 0f), center + Offset(radius, 0f), density)
        drawLine(cross, center - Offset(0f, radius), center + Offset(0f, radius), density)
        val point = center + Offset(drift.x.toFloat() * scale, drift.y.toFloat() * scale)
        drawLine(accent, center, point, 2 * density, StrokeCap.Round)
        drawCircle(palette.card, 6 * density, point)
        drawCircle(accent, 4.5f * density, point)
    }
}
