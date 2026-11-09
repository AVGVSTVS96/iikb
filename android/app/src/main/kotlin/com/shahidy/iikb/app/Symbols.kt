package com.shahidy.iikb.app

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

/**
 * The app's glyphs, by the SF Symbol names the iOS app uses, on a 24-unit square. SF Symbols are Apple's alone, so off
 * Apple's platforms iikb draws its own, as the keyboard does (`keyboard.Glyphs`).
 */
object Symbols {
    private class Shape(val data: String, val filled: Boolean, val width: Float = 0f)

    private val shapes = mapOf(
        "paintpalette.fill" to filled(
            "M12 2.6a9.4 9.4 0 0 0 0 18.8c1.3 0 2-.9 2-1.9 0-1.3-1.1-1.6-1.1-2.7 0-1 .8-1.7 1.8-1.7h2a5.6 5.6 0 0 0 5.6-5.6C22.3 5.9 17.9 2.6 12 2.6Z" +
                "M7.3 12.2a1.7 1.7 0 1 0 0-3.4 1.7 1.7 0 0 0 0 3.4Z M10.4 8.3a1.7 1.7 0 1 0 0-3.4 1.7 1.7 0 0 0 0 3.4Z" +
                "M15.4 8.6a1.7 1.7 0 1 0 0-3.4 1.7 1.7 0 0 0 0 3.4Z",
        ),
        "character.cursor.ibeam" to stroked("M2.5 18.5 7.2 5.5h.6l4.7 13 M4.2 14h7.6 M16 4.5h5 M18.5 4.5v15 M16 19.5h5"),
        "hand.tap.fill" to filled(
            "M9.2 4.6a1.7 1.7 0 0 1 3.4 0v6.2l.4-.1a1.6 1.6 0 0 1 2 .9l.1.3a1.6 1.6 0 0 1 2.2.8 1.6 1.6 0 0 1 2.3 1.4v3" +
                "a6.2 6.2 0 0 1-6.2 6.2h-1.6a5.4 5.4 0 0 1-4.3-2.2l-3.2-4.3a1.6 1.6 0 0 1 2.4-2.1l2.5 2Z",
        ),
        "waveform" to stroked("M3 10.5v3M7 7v10M11 4v16M15 8v8M19 10.5v3", 2.2f),
        "textformat" to stroked("M2 18.5 6.6 6h.8l4.6 12.5 M3.7 14h7.6 M21.5 11v7.5 M21.5 14.8a3.3 3.3 0 1 1-6.6 0a3.3 3.3 0 1 1 6.6 0Z", 2f),
        "character.book.closed.fill" to filled(
            "M6.5 2.5h12a1.5 1.5 0 0 1 1.5 1.5v13H7a1.5 1.5 0 0 0 0 3h13v1.5H7a3 3 0 0 1-3-3V5a2.5 2.5 0 0 1 2.5-2.5Z" +
                "M12 5.4 8.9 13.5h1.8l.6-1.8h2.4l.6 1.8h1.8L13 5.4Z M11.8 10.3l.7-2.1.7 2.1Z",
        ),
        "switch.2" to stroked(
            "M7.5 4.5h9a3 3 0 0 1 0 6h-9a3 3 0 0 1 0-6Z M7.5 13.5h9a3 3 0 0 1 0 6h-9a3 3 0 0 1 0-6Z" +
                "M18 7.5a1.5 1.5 0 1 1-3 0a1.5 1.5 0 1 1 3 0Z M9 16.5a1.5 1.5 0 1 1-3 0a1.5 1.5 0 1 1 3 0Z",
            2f,
        ),
        "hand.raised.fill" to filled(
            "M8.6 4.4a1.5 1.5 0 0 1 3 0V11h.6V3.3a1.5 1.5 0 0 1 3 0V11h.6V5a1.5 1.5 0 0 1 3 0v8.5l.3-1.7a1.5 1.5 0 0 1 2.9.6" +
                "l-1 5A6.9 6.9 0 0 1 13.2 22h-.9a6.6 6.6 0 0 1-5.4-2.8L3.7 14.6a1.5 1.5 0 0 1 2.4-1.8l2.5 2.6Z",
        ),
        "clock.arrow.circlepath" to stroked("M4.2 12a7.8 7.8 0 1 0 2.3-5.5 M3.8 3.8v4h4 M12 7.8v4.6l3 1.9", 2f),
        "info" to stroked("M12 10.5V18 M12 6.2v.3", 2.8f),
        "text.bubble.fill" to filled(
            "M5 3.5h14A2.5 2.5 0 0 1 21.5 6v9a2.5 2.5 0 0 1-2.5 2.5h-7.6L7 21v-3.5H5A2.5 2.5 0 0 1 2.5 15V6A2.5 2.5 0 0 1 5 3.5Z" +
                "M7.5 8a.9.9 0 0 0 0 1.8h9a.9.9 0 0 0 0-1.8Z M7.5 11.5a.9.9 0 0 0 0 1.8h5.5a.9.9 0 0 0 0-1.8Z",
        ),
        "list.clipboard.fill" to filled(
            "M9 2.5h6a1 1 0 0 1 1 1V4h1.5A2.5 2.5 0 0 1 20 6.5v13a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-13A2.5 2.5 0 0 1 6.5 4H8v-.5a1 1 0 0 1 1-1Z" +
                "M8.5 9.5a.9.9 0 0 0 0 1.8h7a.9.9 0 0 0 0-1.8Z M8.5 13a.9.9 0 0 0 0 1.8h7a.9.9 0 0 0 0-1.8Z M8.5 16.5a.9.9 0 0 0 0 1.8h4a.9.9 0 0 0 0-1.8Z",
        ),
        "bubble.left.and.bubble.right.fill" to filled(
            "M3.5 3h10A2.5 2.5 0 0 1 16 5.5v6a2.5 2.5 0 0 1-2.5 2.5H8l-3.5 3v-3h-1A2.5 2.5 0 0 1 1 11.5v-6A2.5 2.5 0 0 1 3.5 3Z" +
                "M17.5 8h3A2.5 2.5 0 0 1 23 10.5v6a2.5 2.5 0 0 1-2.5 2.5h-1v3L16 19h-4.5A2.5 2.5 0 0 1 9 16.5V15.5h4.5a4 4 0 0 0 4-4Z",
        ),
        "mic" to stroked("M12 3a3 3 0 0 1 3 3v5.5a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3Z M5.5 11a6.5 6.5 0 0 0 13 0 M12 17.5V21 M9 21h6"),
        "mic.slash" to stroked("M12 3a3 3 0 0 1 3 3v5.5a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3Z M5.5 11a6.5 6.5 0 0 0 13 0 M12 17.5V21 M9 21h6 M4 3.5l16 17"),
        "plus" to stroked("M12 5v14M5 12h14", 2f),
        "arrow.up.forward" to stroked("M7 17 17 7 M8.5 7H17v8.5", 2f),
        "chevron.right" to stroked("M9 4.5l7.5 7.5L9 19.5", 2.2f),
        "chevron.left" to stroked("M15 4.5 7.5 12l7.5 7.5", 2.2f),
        "chevron.up.chevron.down" to stroked("M8 9l4-4 4 4 M8 15l4 4 4-4", 2.2f),
        "checkmark" to stroked("M5 12.5l4.5 4.5L19 7.5", 2.6f),
        "circle" to stroked("M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0Z"),
        "checkmark.circle.fill" to filled("M12 2.5a9.5 9.5 0 1 1 0 19 9.5 9.5 0 0 1 0-19Z M10.4 16.3l6.5-6.5-1.3-1.3-5.2 5.2-2.4-2.4-1.3 1.3Z"),
        "iphone" to stroked("M8 2.5h8a2 2 0 0 1 2 2v15a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2v-15a2 2 0 0 1 2-2Z M10.5 5h3"),
        "network" to stroked("M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0Z M16 12a4 9 0 1 1-8 0a4 9 0 1 1 8 0Z M3 12h18"),
    )

    private fun stroked(data: String, width: Float = 1.8f) = Shape(data, false, width)

    private fun filled(data: String) = Shape(data, true)

    private val built = mutableMapOf<String, ImageVector>()

    operator fun get(name: String): ImageVector = built.getOrPut(name) {
        val shape = shapes[name] ?: error("no symbol $name")
        ImageVector.Builder(defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .addPath(
                pathData = PathParser().parsePathString(shape.data).toNodes(),
                pathFillType = PathFillType.EvenOdd,
                fill = if (shape.filled) SolidColor(Color.Black) else null,
                stroke = if (shape.filled) null else SolidColor(Color.Black),
                strokeLineWidth = shape.width,
                strokeLineCap = StrokeCap.Round,
                strokeLineJoin = StrokeJoin.Round,
            ).build()
    }
}
