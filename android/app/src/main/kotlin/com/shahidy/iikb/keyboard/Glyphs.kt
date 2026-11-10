package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import kotlin.math.sqrt
import androidx.core.graphics.PathParser

/**
 * The glyphs iikb's keys and bar draw, by the SF Symbol names KeyboardCore gives them. SF Symbols are Apple's alone,
 * so off Apple's platforms iikb draws its own, measured against Apple's: on a 24-unit square that a symbol of point
 * size p fills at `square(p)`, its lines as thick as SF's at the weight asked for.
 */
object Glyphs {
    const val LIGHT = 1.3f
    const val REGULAR = 1.75f
    const val MEDIUM = 2.15f
    const val SEMIBOLD = 2.5f
    const val BOLD = 2.95f

    /** The side of the square a glyph is drawn on to match an SF Symbol of `points` point size. */
    fun square(points: Float) = points * 1.15f

    /**
     * Lines are stroked with round ends; cut lines with square ends, where SF cuts a line off at a gap; a solid is filled
     * with its outline stroked around it, so its corners round as SF's do; a shape is filled as it is.
     */
    private enum class Ink { LINES, CUT, SOLID, SHAPE }

    private class Part(val path: Path, val ink: Ink, val thickness: Float)

    private class Glyph(val parts: List<Part>) {
        operator fun plus(other: Glyph) = Glyph(parts + other.parts)
    }

    private fun glyph(data: String, ink: Ink, thickness: Float = 1f): Glyph {
        val path = PathParser.createPathFromPathData(data)
        if (ink == Ink.SHAPE) path.fillType = Path.FillType.EVEN_ODD
        return Glyph(listOf(Part(path, ink, thickness)))
    }

    /** `thickness` is a share of the weight's line, for a symbol whose inner lines SF draws thinner than its outline. */
    private fun lines(data: String, thickness: Float = 1f) = glyph(data, Ink.LINES, thickness)

    private fun cut(data: String) = glyph(data, Ink.CUT)

    private fun solid(data: String) = glyph(data, Ink.SOLID)

    private fun shape(data: String) = glyph(data, Ink.SHAPE)

    /**
     * A filled symbol as SF fills one: `body` filled with its outline stroked round it at the regular weight, `lines`
     * (`weight` of the regular line, round ended) and `holes` cut out of it, and `over` laid on top with a `gap` cut
     * round it, as a clipboard's clip sits on its board.
     */
    private fun carved(body: String, lines: String = "", weight: Float = 1f, holes: String = "", over: String = "", gap: Float = 0f): Glyph {
        val pen = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        fun parsed(data: String) = PathParser.createPathFromPathData(data).apply { fillType = Path.FillType.EVEN_ODD }
        fun stroked(data: String, width: Float) = Path().also { out ->
            val path = parsed(data)
            pen.strokeWidth = width
            pen.getFillPath(path, out)
            out.op(path, Path.Op.UNION)
        }
        val ink = stroked(body, REGULAR)
        if (lines.isNotEmpty()) {
            pen.style = Paint.Style.STROKE
            val cut = Path().also { pen.strokeWidth = REGULAR * weight; pen.getFillPath(parsed(lines), it) }
            ink.op(cut, Path.Op.DIFFERENCE)
        }
        if (holes.isNotEmpty()) ink.op(parsed(holes), Path.Op.DIFFERENCE)
        if (over.isNotEmpty()) {
            ink.op(stroked(over, gap * 2), Path.Op.DIFFERENCE)
            ink.op(parsed(over), Path.Op.UNION)
        }
        return Glyph(listOf(Part(ink, Ink.SHAPE, 1f)))
    }

    private const val ARROW = "M11.9 3.2 1.9 13.2q-.5.85.7.85h4.8v5.2a1.5 1.5 0 0 0 1.5 1.5h6a1.5 1.5 0 0 0 1.5-1.5v-5.2h4.8q1.2 0 .7-.85Z"
    private const val CAPS = "M11.95 2.1 2.6 10.5q-.5.95.7.95h4.3v4h8.7v-4h4.3q1.2 0 .7-.95Z M8.05 18.9h7.8a.6.6 0 0 1 .6.6v1.85a.6.6 0 0 1-.6.6h-7.8a.6.6 0 0 1-.6-.6V19.5a.6.6 0 0 1 .6-.6Z"
    /** `pin`'s cap and waist over its dome, and its needle, tapering to a point. */
    private const val PIN = "M9.73 10.4V4.3L5.95 .85h12.1L14.27 4.3v6.1 M4.62 15.5C4.62 12 8 10.3 12 10.3s7.38 1.7 7.38 5.2Z"
    private const val NEEDLE = "M11.25 15.9h1.5l-.4 7.5q-.35.7-.7 0Z"
    /** `text.bubble`'s outline: a rounded box with its tail down from the left. */
    private const val BUBBLE =
        "M4.91 2.35h14.18a3.22 3.22 0 0 1 3.22 3.22v8.95a3.22 3.22 0 0 1-3.22 3.22h-7.92l-4.34 3.91v-3.91H4.91a3.22 3.22 0 0 1-3.22-3.22V5.57a3.22 3.22 0 0 1 3.22-3.22Z"
    private const val KEYBOARD = "M1.9 4.7h20.2a1.9 1.9 0 0 1 1.9 1.9v10.85a1.9 1.9 0 0 1-1.9 1.9H1.9A1.9 1.9 0 0 1 0 17.45V6.6a1.9 1.9 0 0 1 1.9-1.9Z"

    private val glyphs: Map<String, Glyph> = mapOf(
        "shift" to lines(ARROW),
        "shift.fill" to solid(ARROW),
        "capslock" to lines(CAPS),
        "capslock.fill" to solid(CAPS),
        "delete.left" to lines(
            "M9.8 3.5h9.6a2.5 2.5 0 0 1 2.5 2.5v12.1a2.5 2.5 0 0 1-2.5 2.5H9.8q-.9 0-1.5-.6L1.5 12.05 8.3 4.1q.6-.6 1.5-.6Z " +
                "M10.1 8.55l6.9 6.9m0-6.9-6.9 6.9",
        ),
        "return.left" to lines("M13.6 3.6h6.1a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H2.1 M8.1 8.6l-6 6 6 6"),
        "arrow.right" to lines("M3.4 12h17.15m-6.9-6.9 6.9 6.9-6.9 6.9"),
        "arrow.up" to lines("M12 20.9V3.2m-6.95 6.95L12 3.2l6.95 6.95"),
        "magnifyingglass" to lines("M17.5 10.1a7.35 7.35 0 1 1-14.7 0a7.35 7.35 0 1 1 14.7 0Z") +
            shape("M15.86 14.14l5.8 5.8a1.215 1.215 0 0 1-1.72 1.72l-5.8-5.8Z"),
        "checkmark" to lines("M4 12.75l5.75 7.1L19.85 4.05"),
        "chevron.right" to lines("M9.2 4.1l7.95 7.95L9.2 20"),
        "chevron.left" to lines("M14.8 4.1 6.85 12.05 14.8 20"),
        "arrow.right.to.line" to lines("M3.5 12h13m-5-5 5 5-5 5M20.5 5v14"),
        "globe" to lines(
            "M21.33 12.1a9.43 9.43 0 1 1-18.86 0a9.43 9.43 0 1 1 18.86 0Z",
        ) + lines(
            "M16.1 12.1a4.2 9.43 0 1 1-8.4 0a4.2 9.43 0 1 1 8.4 0Z M11.9 2.67v18.86M2.47 12.1h18.86 " +
                "M5.2 5.7q6.7 3.7 13.4 0M5.2 18.5q6.7-3.7 13.4 0",
            0.76f,
        ),
        "face.smiling" to lines(
            "M21.33 12.1a9.43 9.43 0 1 1-18.86 0a9.43 9.43 0 1 1 18.86 0Z M8.6 14.75c.7 1.45 1.7 1.71 3.3 1.71s2.6-.26 3.3-1.71",
        ) + shape("M7.92 9.8a1 1.38 0 1 0 2 0a1 1.38 0 1 0-2 0Z M13.9 9.8a1 1.38 0 1 0 2 0a1 1.38 0 1 0-2 0Z"),
        "keyboard.chevron.compact.down" to lines(
            "M4.5 3.5h15a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-15a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2Z M6.5 7.5h1m3 0h1m3 0h1m3 0h0M8 11.5h8 M9 18.5l3 2.5 3-2.5",
        ),
        "arrow.uturn.backward" to lines("M9 14 4 9l5-5 M4 9h10.5a5.5 5.5 0 0 1 0 11H11"),
        "arrow.uturn.forward" to lines("M15 14l5-5-5-5 M20 9H9.5a5.5 5.5 0 0 0 0 11H13"),
        "waveform" to shape(
            "M2.08 10.2a0.96 0.96 0 0 1 1.93 0v3.76a0.96 0.96 0 0 1-1.93 0Z M5.63 5.92a0.96 0.96 0 0 1 1.93 0v12.31a0.96 0.96 0 0 1-1.93 0Z M9.23 2.11a0.96 0.96 0 0 1 1.93 0v19.93a0.96 0.96 0 0 1-1.93 0Z M12.79 7.33a0.96 0.96 0 0 1 1.93 0v9.54a0.96 0.96 0 0 1-1.93 0Z M16.34 4.36a0.96 0.96 0 0 1 1.93 0v15.45a0.96 0.96 0 0 1-1.93 0Z M19.93 9.27a0.96 0.96 0 0 1 1.93 0v5.68a0.96 0.96 0 0 1-1.93 0Z",
        ),
        "xmark" to lines("M4.75 4.8l14.35 14.35m0-14.35L4.75 19.15"),
        "stop.fill" to solid("M6.1 4.65h11.7a1.5 1.5 0 0 1 1.5 1.5v11.75a1.5 1.5 0 0 1-1.5 1.5H6.1a1.5 1.5 0 0 1-1.5-1.5V6.15a1.5 1.5 0 0 1 1.5-1.5Z"),
        "more" to shape(
            "M5.41 3.36h3.22a2.05 2.05 0 0 1 2.05 2.05v3.22a2.05 2.05 0 0 1 -2.05 2.05h-3.22a2.05 2.05 0 0 1 -2.05 -2.05v-3.22a2.05 2.05 0 0 1 2.05 -2.05Z M15.37 3.36h3.22a2.05 2.05 0 0 1 2.05 2.05v3.22a2.05 2.05 0 0 1 -2.05 2.05h-3.22a2.05 2.05 0 0 1 -2.05 -2.05v-3.22a2.05 2.05 0 0 1 2.05 -2.05Z M5.41 13.32h3.22a2.05 2.05 0 0 1 2.05 2.05v3.22a2.05 2.05 0 0 1 -2.05 2.05h-3.22a2.05 2.05 0 0 1 -2.05 -2.05v-3.22a2.05 2.05 0 0 1 2.05 -2.05Z M15.37 13.32h3.22a2.05 2.05 0 0 1 2.05 2.05v3.22a2.05 2.05 0 0 1 -2.05 2.05h-3.22a2.05 2.05 0 0 1 -2.05 -2.05v-3.22a2.05 2.05 0 0 1 2.05 -2.05Z",
        ),
        "gearshape" to lines(
            "M9.85 4.44 10.43 1.86 13.47 1.86 14.05 4.44 15.82 5.17 18.05 3.76 20.19 5.9 18.78 8.13 19.51 9.9 22.09 10.48 " +
                "22.09 13.52 19.51 14.1 18.78 15.87 20.19 18.1 18.05 20.24 15.82 18.83 14.05 19.56 13.47 22.14 10.43 22.14 9.85 19.56 " +
                "8.08 18.83 5.85 20.24 3.71 18.1 5.12 15.87 4.39 14.1 1.81 13.52 1.81 10.48 4.39 9.9 5.12 8.13 3.71 5.9 " +
                "5.85 3.76 8.08 5.17Z M15 12a3.05 3.05 0 1 1-6.1 0a3.05 3.05 0 1 1 6.1 0Z",
        ),
        "keyboard" to lines(KEYBOARD) + shape(
            "M2.86 7.89h1.83v1.67h-1.83Z M6.12 7.89h1.83v1.67h-1.83Z M9.41 7.89h1.83v1.67h-1.83Z M12.7 7.89h1.83v1.67h-1.83Z M15.96 7.89h1.83v1.67h-1.83Z M19.26 7.89h1.83v1.67h-1.83Z M2.86 11.16h1.83v1.67h-1.83Z M6.12 11.16h1.83v1.67h-1.83Z M9.41 11.16h1.83v1.67h-1.83Z M12.7 11.16h1.83v1.67h-1.83Z M15.96 11.16h1.83v1.67h-1.83Z M19.26 11.16h1.83v1.67h-1.83Z M2.86 14.5h1.83v1.67h-1.83Z M19.26 14.5h1.83v1.67h-1.83Z M6.16 14.4h11.58v1.88h-11.58Z",
        ),
        "keyboard.onehanded.left" to lines(KEYBOARD) + shape(
            "M2.87 7.89h1.36v1.67h-1.36Z M5.11 7.89h1.36v1.67h-1.36Z M7.35 7.89h1.36v1.67h-1.36Z M9.6 7.89h1.36v1.67h-1.36Z M11.82 7.89h1.36v1.67h-1.36Z M14.06 7.89h1.36v1.67h-1.36Z M2.87 11.16h1.36v1.67h-1.36Z M5.11 11.16h1.36v1.67h-1.36Z M7.35 11.16h1.36v1.67h-1.36Z M9.6 11.16h1.36v1.67h-1.36Z M11.82 11.16h1.36v1.67h-1.36Z M14.06 11.16h1.36v1.67h-1.36Z M2.87 14.5h1.36v1.67h-1.36Z M14.06 14.5h1.36v1.67h-1.36Z M5.11 14.4h8.04v1.88h-8.04Z",
        ) + solid("M17.75 12 20.2 9.55v4.9Z"),
        "keyboard.onehanded.right" to lines(KEYBOARD) + shape(
            "M8.38 7.89h1.36v1.67h-1.36Z M10.62 7.89h1.36v1.67h-1.36Z M12.86 7.89h1.36v1.67h-1.36Z M15.11 7.89h1.36v1.67h-1.36Z M17.33 7.89h1.36v1.67h-1.36Z M19.57 7.89h1.36v1.67h-1.36Z M8.38 11.16h1.36v1.67h-1.36Z M10.62 11.16h1.36v1.67h-1.36Z M12.86 11.16h1.36v1.67h-1.36Z M15.11 11.16h1.36v1.67h-1.36Z M17.33 11.16h1.36v1.67h-1.36Z M19.57 11.16h1.36v1.67h-1.36Z M8.38 14.5h1.36v1.67h-1.36Z M19.57 14.5h1.36v1.67h-1.36Z M10.62 14.4h8.04v1.88h-8.04Z",
        ) + solid("M6.05 12 3.6 9.55v4.9Z"),
        "rectangle.split.2x1" to lines(
            "M2.7 3.5h18.55a1.9 1.9 0 0 1 1.9 1.9v13.3a1.9 1.9 0 0 1-1.9 1.9H2.7A1.9 1.9 0 0 1 .8 18.7V5.4a1.9 1.9 0 0 1 1.9-1.9Z M11.92 3.5v17.1",
        ),
        "doc.on.clipboard" to lines(
            "M8.9 5.4H4.6a2.2 2.2 0 0 0-2.2 2.2v14.2a2.2 2.2 0 0 0 2.2 2.2h9.5a2.2 2.2 0 0 0 2.2-2.2v-9Z M8.9 5.4v6.4a1.4 1.4 0 0 0 1.4 1.4h6",
        ) + shape(
            "M9.2-.9h10.5a2.8 2.8 0 0 1 2.8 2.8v15.1a2.8 2.8 0 0 1-2.8 2.8h-2.3v-7.4L9.6 4.3H6.4V1.9a2.8 2.8 0 0 1 2.8-2.8Z " +
                "M12.15 1.2h4.7a.75.75 0 0 1 0 1.5h-4.7a.75.75 0 0 1 0-1.5Z",
        ),
        "list.clipboard" to lines(
            "M5.55 3.95a1.4 1.4 0 0 0-1.4 1.4v16.83a2 2 0 0 0 2 2h11.52a2 2 0 0 0 2-2V5.35a1.4 1.4 0 0 0-1.4-1.4",
        ) + lines("M7.5 10.54h8.9M7.5 14.14h8.9M7.5 17.95h4.4", 0.72f) + shape(
            "M8.68 2.71h6.54a.75.75 0 0 1 .75.75v1.27a.75.75 0 0 1-.75.75H8.68a.75.75 0 0 1-.75-.75V3.46a.75.75 0 0 1 .75-.75Z " +
                "M9.65 2.71a2.3 2.3 0 0 1 4.6 0Z M11.07 2.45a.88.88 0 1 0 1.76 0a.88.88 0 1 0-1.76 0Z",
        ),
        "list.clipboard.fill" to carved(
            "M5.55 3.95h12.8a1.4 1.4 0 0 1 1.4 1.4v16.83a2 2 0 0 1-2 2H6.15a2 2 0 0 1-2-2V5.35a1.4 1.4 0 0 1 1.4-1.4Z",
            lines = "M7.5 10.54h8.9M7.5 14.14h8.9M7.5 17.95h4.4", weight = 0.85f,
            over = "M8.68 2.71h6.54a.75.75 0 0 1 .75.75v1.27a.75.75 0 0 1-.75.75H8.68a.75.75 0 0 1-.75-.75V3.46a.75.75 0 0 1 .75-.75Z " +
                "M9.65 2.71a2.3 2.3 0 0 1 4.6 0Z",
            gap = 0.9f,
        ),
        "text.bubble.fill" to carved(BUBBLE, lines = "M6.78 7.83H17.04M6.78 12.26H13.74", weight = 0.75f),
        "face.smiling.inverse" to carved(
            "M21.33 12.1a9.43 9.43 0 1 1-18.86 0a9.43 9.43 0 1 1 18.86 0Z",
            lines = "M8.6 14.75c.7 1.45 1.7 1.71 3.3 1.71s2.6-.26 3.3-1.71",
            holes = "M7.92 9.8a1 1.38 0 1 0 2 0a1 1.38 0 1 0-2 0Z M13.9 9.8a1 1.38 0 1 0 2 0a1 1.38 0 1 0-2 0Z",
        ),
        "text.bubble" to lines(BUBBLE, 0.94f) + lines("M7.04 7.91H16.78M7.04 12.26H13.57", 0.75f),
        "bubble.left.and.bubble.right.fill" to shape(
            "M4.17 2.73H14.34A3.6 3.6 0 0 1 17.94 6.33V6.15H12.09A3.87 3.87 0 0 0 8.22 10.02V17.67H8.31C7.59 18.66 6.51 19.56 5.25 19.92C4.8 20.01 4.44 19.83 4.44 19.47V17.67H4.08A4.05 4.05 0 0 1 .03 13.62V6.78A4.05 4.05 0 0 1 4.17 2.73Z " +
                "M12.09 7.05H21A2.97 2.97 0 0 1 23.97 10.02V14.88C23.97 16.41 22.44 17.85 20.37 17.85V20.64C20.37 21.09 19.92 21.27 19.56 21L14.97 17.85H12.09A2.97 2.97 0 0 1 9.12 14.88V10.02A2.97 2.97 0 0 1 12.09 7.05Z",
        ),
        "bubble.left.and.bubble.right" to lines(
            "M4 8h9a2 2 0 0 1 2 2v5.5a2 2 0 0 1-2 2H8l-3.5 3v-3H4a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2Z M9 8V5a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v5.5a2 2 0 0 1-2 2h-.5v3l-3.5-3H15",
        ),
        "clock" to lines("M21.33 12.1a9.43 9.43 0 1 1-18.86 0a9.43 9.43 0 1 1 18.86 0Z M11.9 5.75v6.65H6.8"),
        "drop.fill" to shape("M11.97 1.72C13.5 4.5 19.2 9.5 19.2 15.3a7.23 7.23 0 0 1-14.46 0C4.75 9.5 10.45 4.5 11.97 1.72Z"),
        "rectangle.arrowtriangle.2.inward" to lines(
            "M5.65 6.26h12.55a2.5 2.5 0 0 1 2.5 2.5v6.58a2.5 2.5 0 0 1-2.5 2.5H5.65a2.5 2.5 0 0 1-2.5-2.5V8.76a2.5 2.5 0 0 1 2.5-2.5Z",
        ) + solid("M10.1-.15h3.65L11.92 2.9Z M10.1 24.25h3.65L11.92 21.2Z"),
        "rectangle.fill.on.rectangle.angled.fill" to solid(
            "M7.6 7.1h14.4a2 2 0 0 1 2 2v10.15a2 2 0 0 1-2 2H7.6a2 2 0 0 1-2-2V9.1a2 2 0 0 1 2-2Z " +
                "M.1 7.9 1.2 15.9q.3 1.8.85 1.8V8.6q0-5.05 5.05-5.05h11.2l-.45-1.95L1.3 4.3Q-.15 4.6.1 6Z",
        ),
        "paintpalette.fill" to shape(
            "M-.7 12C-.7 5.4 5.2 1.55 12.5 1.55c7.1 0 12 2.75 12 6.85 0 3-3.6 3.6-5.1 4.7-1.2.9-.2 2.1.4 2.9.8 1 .8 2.3.5 3.1-.8 2.2-3.7 3.5-7.7 3.5C5 22.6-.7 18.7-.7 12Z " +
                "M10.37 7.75a2.1 2.1 0 1 0-4.2 0a2.1 2.1 0 1 0 4.2 0Z M15.63 6.5a1.75 1.75 0 1 0-3.5 0a1.75 1.75 0 1 0 3.5 0Z M20.28 7.67a1.42 1.42 0 1 0-2.84 0a1.42 1.42 0 1 0 2.84 0Z M5.93 11.85a1.7 1.7 0 1 0-3.4 0a1.7 1.7 0 1 0 3.4 0Z M15.6 15.7a2.9 2.9 0 1 0-5.8 0a2.9 2.9 0 1 0 5.8 0Z",
        ),
        "trash" to lines(
            "M2.96 5.35H21.04 M8.35 5.35V2.87a1.39 1.39 0 0 1 1.39-1.39h4.52a1.39 1.39 0 0 1 1.39 1.39V5.35 " +
                "M4.87 5.35l.76 15.26a1.91 1.91 0 0 0 1.91 1.96h8.89a1.91 1.91 0 0 0 1.91-1.96L19.13 5.35",
            0.9f,
        ) + lines("M8.7 8.43V19.3M12 8.43V19.3M15.22 8.43V19.3", 0.7f),
        "photo" to lines(
            "M5 4.5h14a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-11a2 2 0 0 1 2-2Z M3 16l5-5 4 4 3-3 6 6 M16.5 9a1.5 1.5 0 1 1-3 0a1.5 1.5 0 1 1 3 0Z",
        ),
        "scissors" to lines(
            "M6.9 7.4a2.35 2.35 0 1 1-4.7 0a2.35 2.35 0 1 1 4.7 0Z M6.9 16.6a2.35 2.35 0 1 1-4.7 0a2.35 2.35 0 1 1 4.7 0Z " +
                "M6.5 8.9 10.6 11.4 M6.5 15.1 22.4 6.9",
        ) + shape("M10.6 10.3 22.6 16.6q.6.5-.1.7L9.9 13.9Q9.2 13.5 9.6 12.1Q10 10.6 10.6 10.3Z M11.4 12.3a.65.65 0 1 0-1.3 0a.65.65 0 1 0 1.3 0Z"),
        "square.on.square" to lines(
            "M9.52 6.83h9.91a2.52 2.52 0 0 1 2.52 2.52v10a2.52 2.52 0 0 1-2.52 2.52H9.52A2.52 2.52 0 0 1 7 19.35v-10a2.52 2.52 0 0 1 2.52-2.52Z " +
                "M17 6.83V4.65a2.52 2.52 0 0 0-2.52-2.52H4.57a2.52 2.52 0 0 0-2.52 2.52v10a2.52 2.52 0 0 0 2.52 2.52H7",
            0.92f,
        ),
        "doc" to lines("M7 2.5h7.2L19 7.3V19.5a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-15a2 2 0 0 1 2-2Z M14 2.7V6a1.3 1.3 0 0 0 1.3 1.3h3.5"),
        "doc.on.doc" to lines(
            "M5 5.48h5l6.65 6.65v9.26A2.61 2.61 0 0 1 14.04 24H5a2.61 2.61 0 0 1-2.61-2.61V8.09A2.61 2.61 0 0 1 5 5.48Z " +
                "M7.35 5.48V2.61A2.61 2.61 0 0 1 9.96 0h5.08l6.57 6.57v9.73A2.61 2.61 0 0 1 19 18.91h-2.35",
            0.9f,
        ) + lines("M8.91 5.48v6.26a1.22 1.22 0 0 0 1.22 1.22h6.52 M15 0v5.83a1.22 1.22 0 0 0 1.22 1.22h5.39", 0.83f),
        "safari" to lines("M21.5 12a9.5 9.5 0 1 1-19 0a9.5 9.5 0 1 1 19 0Z") + shape(
            "M16.6 7.4 13.4 13.4 7.4 16.6 10.6 10.6Z M12 13.1a1.1 1.1 0 1 0 0-2.2a1.1 1.1 0 1 0 0 2.2Z",
        ),
        "pin.fill" to shape(
            "M6.3.25h11.4q.99 0 .99.95v.3q0 1-1.79 1.8-1.7.7-1.75 1.9L15.05 9c.55 1.2 4.87 1.9 4.87 5.6v.2q0 1.2-1.22 1.2h-6l-.28 7.3q-.42.7-.84 0L11.3 16h-6q-1.22 0-1.22-1.2v-.2c0-3.7 4.32-4.4 4.87-5.6l-.1-3.8q-.05-1.2-1.75-1.9-1.79-.8-1.79-1.8v-.3q0-.95.99-.95Z",
        ),
        "pin" to lines(PIN, 0.85f) + shape(NEEDLE),
        "pin.slash" to lines("$PIN M3.5 3.5l17 17", 0.85f) + shape(NEEDLE),
        // Drawn as iOS's clip titles draw it, SF's envelope stretched to a square (ClipTitle.swift), so its lines are thinner.
        "envelope" to lines(
            "M2.5.85h19a1.65 1.65 0 0 1 1.65 1.65v19a1.65 1.65 0 0 1-1.65 1.65h-19A1.65 1.65 0 0 1 .85 21.5v-19A1.65 1.65 0 0 1 2.5.85Z " +
                "M2 2.2l7.7 10.9q2.3 3.2 4.6 0L22 2.2 M2 21.8l4.8-8.9 M22 21.8l-4.8-8.9",
            0.9f,
        ),
        "phone" to lines(
            "M7.2 3.5h-2a1.8 1.8 0 0 0-1.8 2A15.5 15.5 0 0 0 18.5 20.6a1.8 1.8 0 0 0 2-1.8v-2l-4-1.6-2 2a12 12 0 0 1-6.2-6.2l2-2Z",
        ),
        "link" to cut(
            "M17.78 13.54l2.52-2.52A5.18 5.18 0 0 0 12.98 3.7L9.67 7.01a5.18 5.18 0 0 0 2.58 8.73 " +
                "M6.22 10.46 3.7 12.98a5.18 5.18 0 0 0 7.32 7.32l3.31-3.31a5.18 5.18 0 0 0-2.58-8.73",
        ),
    )

    fun has(name: String) = name in glyphs

    private val ink = RectF()
    private val part = RectF()

    /** The ink of `name` on its 24 square, its lines' width included. */
    private fun ink(glyph: Glyph) {
        ink.setEmpty()
        for (each in glyph.parts) {
            each.path.computeBounds(part, true)
            if (each.ink != Ink.SHAPE) part.inset(-REGULAR * each.thickness / 2, -REGULAR * each.thickness / 2)
            ink.union(part)
        }
    }

    /** How much `drawFitted` scales a glyph's 24 square for a `side` glyph. */
    private fun fitted(side: Float) = minOf(0.8f * side / sqrt(ink.width() * ink.height()), 0.8f * side / ink.height(), side / ink.width())

    /** How wide `drawFitted` draws `name`'s ink for a `side` glyph. */
    fun fittedWidth(name: String, side: Float): Float {
        ink(glyphs[name] ?: return 0f)
        return ink.width() * fitted(side)
    }

    /**
     * Draws `name` as iOS's bar draws a tool's symbol for a `side` glyph: its ink, not its square, covering as much as a
     * square 0.8 of `side` and no taller than that square, so a tall one and a wide one read as one size, centered on
     * (`x`, `y`).
     */
    fun drawFitted(canvas: Canvas, name: String, x: Float, y: Float, side: Float, paint: Paint) {
        val glyph = glyphs[name] ?: return
        ink(glyph)
        val scale = fitted(side)
        val size = 24 * scale
        draw(canvas, name, x + (12 - ink.centerX()) * scale, y + (12 - ink.centerY()) * scale, size, paint)
    }

    /** iOS's filled GIF glyph is this share of a glyph's side wide, so its solid block weighs what a filled symbol does. */
    const val GIF_FILLED = 0.76f
    private val gif = Path()
    private val gifLetters = Path()
    private val gifText = Paint(Paint.ANTI_ALIAS_FLAG)

    /**
     * GIF has no symbol: as iOS's filled `Panel.gifGlyph`, a solid rounded block `GIF_FILLED` of a `side` glyph wide,
     * "GIF" in bold `labels` cut out of it, centered on (`x`, `y`).
     */
    fun drawGif(canvas: Canvas, x: Float, y: Float, side: Float, paint: Paint, labels: Typeface) {
        val unit = GIF_FILLED * side / 18.4f
        val box = RectF(x - 9.2f * unit, y - 7.2f * unit, x + 9.2f * unit, y + 7.2f * unit)
        val size = 8 * unit
        gifText.typeface = Typeface.create(labels, 700, false)
        gifText.textSize = GIF_LAYOUT
        gifText.letterSpacing = 0f
        gifText.letterSpacing = (sfGifWidth(size) - gifText.measureText("GIF") / GIF_LAYOUT) / 3
        gifText.getTextPath("GIF", 0, 3, -gifText.measureText("GIF") / 2, GIF_LAYOUT * 0.35f, gifLetters)
        matrix.setScale(size / GIF_LAYOUT, size / GIF_LAYOUT)
        matrix.postTranslate(x, y)
        gifLetters.transform(matrix)
        gif.reset()
        gif.addRoundRect(box, 3.6f * unit, 3.6f * unit, Path.Direction.CW)
        gif.op(gifLetters, Path.Op.DIFFERENCE)
        canvas.drawPath(gif, paint)
    }

    /** The letters are laid out this large and scaled down, since a few-pixel text size snaps its letters together. */
    private const val GIF_LAYOUT = 100f

    /** How wide SF Bold sets "GIF" at `size` points, in ems: its tracking opens up as it shrinks, to 6 points. */
    private fun sfGifWidth(size: Float) = 1.796f - 0.0213f * (size - 6).coerceAtLeast(0f)

    private val matrix = Matrix()
    private val scaled = Path()
    private val outline = Path()

    /** Draws `name` as a square `size` on a side, centered on (`x`, `y`), in `paint`'s color, its lines `weight` units thick. */
    fun draw(canvas: Canvas, name: String, x: Float, y: Float, size: Float, paint: Paint, weight: Float = REGULAR) {
        val glyph = glyphs[name] ?: return
        val scale = size / 24f
        matrix.setScale(scale, scale)
        matrix.postTranslate(x - size / 2, y - size / 2)
        val style = paint.style
        val width = paint.strokeWidth
        paint.strokeJoin = Paint.Join.ROUND
        for (part in glyph.parts) {
            paint.strokeWidth = weight * part.thickness * scale
            paint.strokeCap = if (part.ink == Ink.CUT) Paint.Cap.BUTT else Paint.Cap.ROUND
            part.path.transform(matrix, scaled)
            when (part.ink) {
                Ink.LINES, Ink.CUT -> paint.style = Paint.Style.STROKE
                Ink.SHAPE -> paint.style = Paint.Style.FILL
                Ink.SOLID -> {
                    paint.style = Paint.Style.STROKE
                    paint.getFillPath(scaled, outline)
                    outline.op(scaled, Path.Op.UNION)
                    scaled.set(outline)
                    paint.style = Paint.Style.FILL
                }
            }
            canvas.drawPath(scaled, paint)
        }
        paint.style = style
        paint.strokeWidth = width
    }
}
