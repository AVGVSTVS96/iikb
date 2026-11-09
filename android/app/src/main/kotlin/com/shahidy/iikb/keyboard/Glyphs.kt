package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import androidx.core.graphics.PathParser

/**
 * The glyphs iikb's keys and bar draw, by the SF Symbol names KeyboardCore gives them, drawn on a 24-unit square as
 * the web demo draws them: SF Symbols are Apple's alone, so off Apple's platforms iikb draws its own.
 */
object Glyphs {
    private class Glyph(val path: Path, val filled: Boolean)

    private const val ARROW = "M12 2.8 2.4 12.4h5.4v7.9h8.4v-7.9h5.4Z"
    private const val CAPS = "M12 2.8 3.4 11h4.9v4.6h7.4V11h4.9Z M8.3 18.2h7.4v2.4h-7.4Z"

    private val glyphs: Map<String, Glyph> = mapOf(
        "shift" to stroke(ARROW),
        "shift.fill" to fill(ARROW),
        "capslock.fill" to fill(CAPS),
        "delete.left" to stroke(
            "M8.2 4.8h11.4a2.4 2.4 0 0 1 2.4 2.4v9.6a2.4 2.4 0 0 1-2.4 2.4H8.2L1.8 12Z M11.2 8.9l6.2 6.2m0-6.2-6.2 6.2",
        ),
        "return.left" to stroke("M21 3.6v8.2a2.6 2.6 0 0 1-2.6 2.6H3.4 M8.2 9.6l-4.8 4.8 4.8 4.8"),
        "arrow.right" to stroke("M4 12h15.5m-6-6 6 6-6 6"),
        "arrow.up" to stroke("M12 20V4.5m-6 6 6-6 6 6"),
        "magnifyingglass" to stroke("M16.8 10.5a6.3 6.3 0 1 1-12.6 0a6.3 6.3 0 1 1 12.6 0Z M15.2 15.2l5.3 5.3"),
        "checkmark" to stroke("M4.5 12.8l4.8 4.8L19.5 6.5"),
        "chevron.right" to stroke("M9 4.5l7.5 7.5L9 19.5"),
        "chevron.left" to stroke("M15 4.5 7.5 12l7.5 7.5"),
        "arrow.right.to.line" to stroke("M3.5 12h13m-5-5 5 5-5 5M20.5 5v14"),
        "globe" to stroke(
            "M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0Z M16 12a4 9 0 1 1-8 0a4 9 0 1 1 8 0Z M3 12h18M4.6 7h14.8M4.6 17h14.8",
        ),
        "face.smiling" to stroke(
            "M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0Z M8 14.6a5 5 0 0 0 8 0 M9.1 9.2v1.3M14.9 9.2v1.3",
        ),
        "keyboard.chevron.compact.down" to stroke(
            "M4.5 3.5h15a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-15a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2Z M6.5 7.5h1m3 0h1m3 0h1m3 0h0M8 11.5h8 M9 18.5l3 2.5 3-2.5",
        ),
        "arrow.uturn.backward" to stroke("M9 14 4 9l5-5 M4 9h10.5a5.5 5.5 0 0 1 0 11H11"),
        "arrow.uturn.forward" to stroke("M15 14l5-5-5-5 M20 9H9.5a5.5 5.5 0 0 0 0 11H13"),
        "waveform" to stroke("M3 10.5v3M7 7v10M11 4v16M15 8v8M19 10.5v3"),
        "xmark" to stroke("M6 6l12 12M18 6 6 18"),
        "stop.fill" to fill("M7.5 5h9a2.5 2.5 0 0 1 2.5 2.5v9a2.5 2.5 0 0 1-2.5 2.5h-9A2.5 2.5 0 0 1 5 16.5v-9A2.5 2.5 0 0 1 7.5 5Z"),
        "more" to stroke(
            "M5.5 3.5h3.5a2 2 0 0 1 2 2V9a2 2 0 0 1-2 2H5.5a2 2 0 0 1-2-2V5.5a2 2 0 0 1 2-2Z " +
                "M15 3.5h3.5a2 2 0 0 1 2 2V9a2 2 0 0 1-2 2H15a2 2 0 0 1-2-2V5.5a2 2 0 0 1 2-2Z " +
                "M5.5 13h3.5a2 2 0 0 1 2 2v3.5a2 2 0 0 1-2 2H5.5a2 2 0 0 1-2-2V15a2 2 0 0 1 2-2Z " +
                "M15 13h3.5a2 2 0 0 1 2 2v3.5a2 2 0 0 1-2 2H15a2 2 0 0 1-2-2V15a2 2 0 0 1 2-2Z",
        ),
        "gearshape" to stroke(
            "M15 12a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z M12 2.5l1.6 2.4 2.8-.7.7 2.8 2.4 1.6-1.2 2.6 1.2 2.6-2.4 1.6-.7 2.8-2.8-.7L12 21.5l-1.6-2.4-2.8.7-.7-2.8-2.4-1.6L5.7 12 4.5 9.4l2.4-1.6.7-2.8 2.8.7Z",
        ),
        "keyboard" to stroke(
            "M4.5 6h15a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-15a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2Z M6.5 10h1m3 0h1m3 0h1m3 0h0M8 14h8",
        ),
        "keyboard.onehanded.left" to stroke(
            "M3.5 6h11a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2Z M5.5 10h1m2.5 0h1m2.5 0h0M6.5 14h6 M20 9v6",
        ),
        "keyboard.onehanded.right" to stroke(
            "M9.5 6h11a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2Z M11.5 10h1m2.5 0h1m2.5 0h0M12.5 14h6 M4 9v6",
        ),
        "rectangle.split.2x1" to stroke(
            "M4.5 5h15a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-15a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z M12 5v14",
        ),
        "doc.on.clipboard" to stroke(
            "M8 4.5h8a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2Z M9.5 3h5v3h-5Z",
        ),
        "text.bubble" to stroke(
            "M5 4h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-8l-4.5 3.5V17H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z M7.5 8.5h9M7.5 12h6",
        ),
        "clock" to stroke("M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0Z M12 7v5l3 2"),
    )

    private fun stroke(data: String) = Glyph(PathParser.createPathFromPathData(data), false)

    private fun fill(data: String) = Glyph(PathParser.createPathFromPathData(data), true)

    fun has(name: String) = name in glyphs

    private val matrix = Matrix()
    private val scaled = Path()

    /** Draws `name` as a square `size` on a side, centered on (`x`, `y`), in `paint`'s color. */
    fun draw(canvas: Canvas, name: String, x: Float, y: Float, size: Float, paint: Paint) {
        val glyph = glyphs[name] ?: return
        val scale = size / 24f
        matrix.setScale(scale, scale)
        matrix.postTranslate(x - size / 2, y - size / 2)
        glyph.path.transform(matrix, scaled)
        val style = paint.style
        val width = paint.strokeWidth
        paint.style = if (glyph.filled) Paint.Style.FILL else Paint.Style.STROKE
        paint.strokeWidth = 1.7f * scale
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeJoin = Paint.Join.ROUND
        canvas.drawPath(scaled, paint)
        paint.style = style
        paint.strokeWidth = width
    }
}
