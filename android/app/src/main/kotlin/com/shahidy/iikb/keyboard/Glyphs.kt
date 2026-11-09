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
        "more" to fill(
            "M5.41 3.36h3.22a2.05 2.05 0 0 1 2.05 2.05v3.22a2.05 2.05 0 0 1 -2.05 2.05h-3.22a2.05 2.05 0 0 1 -2.05 -2.05v-3.22a2.05 2.05 0 0 1 2.05 -2.05Z M15.37 3.36h3.22a2.05 2.05 0 0 1 2.05 2.05v3.22a2.05 2.05 0 0 1 -2.05 2.05h-3.22a2.05 2.05 0 0 1 -2.05 -2.05v-3.22a2.05 2.05 0 0 1 2.05 -2.05Z M5.41 13.32h3.22a2.05 2.05 0 0 1 2.05 2.05v3.22a2.05 2.05 0 0 1 -2.05 2.05h-3.22a2.05 2.05 0 0 1 -2.05 -2.05v-3.22a2.05 2.05 0 0 1 2.05 -2.05Z M15.37 13.32h3.22a2.05 2.05 0 0 1 2.05 2.05v3.22a2.05 2.05 0 0 1 -2.05 2.05h-3.22a2.05 2.05 0 0 1 -2.05 -2.05v-3.22a2.05 2.05 0 0 1 2.05 -2.05Z",
        ),
        "gearshape" to stroke(
            "M19.25 10.53 L21.53 10.85 L21.53 13.15 L19.25 13.47 L18.17 16.09 L19.55 17.93 L17.93 19.55 L16.09 18.17 L13.47 19.25 L13.15 21.53 L10.85 21.53 L10.53 19.25 L7.91 18.17 L6.07 19.55 L4.45 17.93 L5.83 16.09 L4.75 13.47 L2.47 13.15 L2.47 10.85 L4.75 10.53 L5.83 7.91 L4.45 6.07 L6.07 4.45 L7.91 5.83 L10.53 4.75 L10.85 2.47 L13.15 2.47 L13.47 4.75 L16.09 5.83 L17.93 4.45 L19.55 6.07 L18.17 7.91Z M15.2 12a3.2 3.2 0 1 1-6.4 0a3.2 3.2 0 1 1 6.4 0Z",
        ),
        "keyboard" to stroke(
            "M4.5 6h15a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-15a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2Z " +
                "M6 9.5h0M9 9.5h0M12 9.5h0M15 9.5h0M18 9.5h0M7.5 12.2h0M10.5 12.2h0M13.5 12.2h0M16.5 12.2h0M8 15h8",
        ),
        "keyboard.onehanded.left" to stroke(
            "M3.5 6h11a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2Z " +
                "M4.8 9.5h0M7.3 9.5h0M9.8 9.5h0M12.3 9.5h0M6 12.2h0M8.5 12.2h0M11 12.2h0M6.5 15h5.5 M21.5 9.5 18.8 12l2.7 2.5Z",
        ),
        "keyboard.onehanded.right" to stroke(
            "M9.5 6h11a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2Z " +
                "M10.8 9.5h0M13.3 9.5h0M15.8 9.5h0M18.3 9.5h0M12 12.2h0M14.5 12.2h0M17 12.2h0M12.5 15h5.5 M2.5 9.5 5.2 12l-2.7 2.5Z",
        ),
        "rectangle.split.2x1" to stroke(
            "M4.5 5h15a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-15a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z M12 5v14",
        ),
        "doc.on.clipboard" to stroke(
            "M10 20H5.5a2 2 0 0 1-2-2V6.5a2 2 0 0 1 2-2H7 M12.5 4.5H14a2 2 0 0 1 2 2v2 M7.5 3h4.5v3H7.5Z " +
                "M11.5 8.5h5.5l3.5 3.5v8a1.5 1.5 0 0 1-1.5 1.5h-7.5A1.5 1.5 0 0 1 10 20V10a1.5 1.5 0 0 1 1.5-1.5Z M17 8.5V12h3.5",
        ),
        "list.clipboard" to stroke(
            "M8 4.5H6.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-13a2 2 0 0 0-2-2H16 M9 3h6v3H9Z M8.5 10.5h7M8.5 14h7M8.5 17.5h4.5",
        ),
        "text.bubble" to stroke(
            "M5 4h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-8l-4.5 3.5V17H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z M7.5 8.5h9M7.5 12h6",
        ),
        "bubble.left.and.bubble.right" to stroke(
            "M4 8h9a2 2 0 0 1 2 2v5.5a2 2 0 0 1-2 2H8l-3.5 3v-3H4a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2Z M9 8V5a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v5.5a2 2 0 0 1-2 2h-.5v3l-3.5-3H15",
        ),
        "clock" to stroke("M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0Z M12 7v5l3 2"),
        "drop.fill" to fill("M12 2.8c3.6 4.6 6.3 8.4 6.3 11.6a6.3 6.3 0 0 1-12.6 0c0-3.2 2.7-7 6.3-11.6Z"),
        "rectangle.arrowtriangle.2.inward" to stroke(
            "M5 6.5h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2Z M6.5 9.5l3 2.5-3 2.5Z M17.5 9.5l-3 2.5 3 2.5Z",
        ),
        "rectangle.fill.on.rectangle.angled.fill" to fill(
            "M8.6 3.2l10.8 2.9a1.8 1.8 0 0 1 1.3 2.2l-1.9 7-1.1-.3.7-2.5V9.6a3 3 0 0 0-3-3H7.3l-.9.1.6-2.3a1.8 1.8 0 0 1 1.6-1.2Z M5 8.6h9.6a2 2 0 0 1 2 2v7.6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7.6a2 2 0 0 1 2-2Z",
        ),
        "paintpalette.fill" to stroke(
            "M12 3a9 9 0 0 0 0 18c1.2 0 1.8-.8 1.8-1.7 0-1.2-1-1.5-1-2.6 0-.9.7-1.6 1.6-1.6H16a5 5 0 0 0 5-5C21 6.3 17 3 12 3Z M7.5 11.2a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z M10.6 7.6a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z M15.2 8.4a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z",
        ),
        "trash" to stroke(
            "M4 6.5h16 M9.5 6.5V4.8A1.3 1.3 0 0 1 10.8 3.5h2.4a1.3 1.3 0 0 1 1.3 1.3v1.7 M6 6.5l1 12.6a1.8 1.8 0 0 0 1.8 1.6h6.4a1.8 1.8 0 0 0 1.8-1.6L18 6.5 M10 10.5v6.5M14 10.5v6.5",
        ),
        "photo" to stroke(
            "M5 4.5h14a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-11a2 2 0 0 1 2-2Z M3 16l5-5 4 4 3-3 6 6 M16.5 9a1.5 1.5 0 1 1-3 0a1.5 1.5 0 1 1 3 0Z",
        ),
        "scissors" to stroke(
            "M9.5 6.5a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z M9.5 17.5a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z M8.6 8.6 20.5 18 M8.6 15.4 20.5 6",
        ),
        "square.on.square" to stroke(
            "M10 8h9a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2Z M16 5V4.8A1.8 1.8 0 0 0 14.2 3H5a2 2 0 0 0-2 2v9.2A1.8 1.8 0 0 0 4.8 16H5",
        ),
        "pin.fill" to fill("M8 3h8l-1.2 6.5L18 13v1.5h-5.2V21h-1.6v-6.5H6V13l3.2-3.5Z"),
        "envelope" to stroke("M4.5 5.5h15a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-15a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2Z M3 7l9 6.5L21 7"),
        "phone" to stroke(
            "M7.2 3.5h-2a1.8 1.8 0 0 0-1.8 2A15.5 15.5 0 0 0 18.5 20.6a1.8 1.8 0 0 0 2-1.8v-2l-4-1.6-2 2a12 12 0 0 1-6.2-6.2l2-2Z",
        ),
        "link" to stroke(
            "M10.5 13.5a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1 M13.5 10.5a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1",
        ),
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
