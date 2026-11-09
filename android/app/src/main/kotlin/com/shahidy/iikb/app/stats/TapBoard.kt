package com.shahidy.iikb.app.stats

import android.graphics.Bitmap
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.Color
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.math.atan2
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sqrt

/**
 * What the touch model learned on one screen, laid out by KeyboardCore as the keyboard lays it out
 * (android/Sources/KeyboardAndroid/Stats.swift): the screens with taps, the keys, and each learning key's aim. Points
 * are the keyboard's dp; keys are their place in `keys`.
 */
@Serializable
data class TapBoard(
    val screens: List<Screen>,
    val signature: String? = null,
    val width: Double,
    val height: Double,
    val keys: List<Box>,
    val aims: List<Aim>,
) {
    @Serializable
    data class Screen(val signature: String, val title: String, val taps: Int)

    @Serializable
    data class Box(val name: String, val x: Double, val y: Double, val width: Double, val height: Double, val learns: Boolean) {
        val midX get() = x + width / 2
        val midY get() = y + height / 2
        fun contains(px: Double, py: Double) = px >= x && px < x + width && py >= y && py < y + height
    }

    @Serializable
    data class Point(val x: Double, val y: Double)

    @Serializable
    data class Tap(val x: Double, val y: Double, val landed: Int? = null)

    @Serializable
    data class Memory(val x: Double, val y: Double, val weight: Double)

    @Serializable
    data class Share(val key: Int, val share: Double)

    /** How one key's taps land (KeyboardCore's `Aim`): where they center, how they spread, which keys they hit. */
    @Serializable
    data class Aim(
        val key: Int,
        val taps: Int,
        val center: Point,
        /** The covariance of one tap around `center`, xx, xy and yy, in square dp. */
        val spread: List<Double>,
        val recent: List<Tap>,
        val memories: List<Memory>,
        val landing: List<Share>,
    ) {
        val onTarget get() = landing.firstOrNull { it.key == key }?.share ?: 0.0
    }

    fun box(aim: Aim) = keys[aim.key]

    /** How far the center of a key's taps sits from the center of the key. */
    fun drift(aim: Aim) = Point(aim.center.x - box(aim).midX, aim.center.y - box(aim).midY)

    fun isSpace(aim: Aim) = box(aim).name == "space"

    /** The key under a point, as a tap there would read. */
    fun key(x: Double, y: Double) = keys.indexOfFirst { it.contains(x, y) }.takeIf { it >= 0 }

    companion object {
        private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

        fun parse(bytes: ByteArray): TapBoard = json.decodeFromString(serializer(), bytes.decodeToString())

        /** The radius scale of the ellipse that holds half of a Gaussian's taps. */
        val half = sqrt(2 * ln(2.0))

        /** A spread's axes: the major and minor standard deviations and the major's angle in radians. */
        fun axes(spread: List<Double>): Triple<Double, Double, Double> {
            val (xx, xy, yy) = spread
            val mid = (xx + yy) / 2
            val radius = sqrt(((xx - yy) / 2) * ((xx - yy) / 2) + xy * xy)
            return Triple(sqrt(mid + radius), sqrt(max(mid - radius, 0.0)), atan2(2 * xy, xx - yy) / 2)
        }
    }
}

/** The numbers Taps shows, worked out once per board (iOS's `TapSummary`). */
class TapSummary(board: TapBoard) {
    class Miss(val key: Int, val share: Double, val onto: Int?)

    val taps: Int
    val onTarget: Double
    val lately: Pair<Double, Int>?
    val offCenter: Double
    val halves: List<Pair<String, TapBoard.Point>>
    val space: TapBoard.Point?
    val misses: List<Miss>

    init {
        val letters = board.aims.filter { !board.isSpace(it) }
        val weight = max(letters.sumOf { it.taps }, 1).toDouble()
        taps = board.aims.sumOf { it.taps }
        onTarget = letters.sumOf { it.taps * it.onTarget } / weight
        offCenter = letters.sumOf { board.drift(it).let { d -> it.taps * hypot(d.x, d.y) } } / weight
        val recent = letters.flatMap { aim -> aim.recent.map { it.landed == aim.key } }
        lately = if (recent.isEmpty()) null else recent.count { it }.toDouble() / recent.size to recent.size
        val typed = letters.filter { it.taps > 0 }
        val xs = typed.map { board.box(it).midX }
        val middle = ((xs.maxOrNull() ?: 0.0) + (xs.minOrNull() ?: 0.0)) / 2
        halves = listOf(
            "Left half" to typed.filter { board.box(it).midX < middle },
            "Right half" to typed.filter { board.box(it).midX >= middle },
        ).map { (name, aims) ->
            val taps = max(aims.sumOf { it.taps }, 1).toDouble()
            name to TapBoard.Point(
                aims.sumOf { it.taps * board.drift(it).x } / taps, aims.sumOf { it.taps * board.drift(it).y } / taps,
            )
        }
        space = board.aims.firstOrNull { board.isSpace(it) && it.taps >= 10 }?.let { board.drift(it) }
        misses = letters.filter { it.taps >= 10 }
            .map { aim -> Miss(aim.key, 1 - aim.onTarget, aim.landing.firstOrNull { it.key != aim.key }?.key) }
            .sortedByDescending { it.share }
    }

    companion object {
        fun describe(drift: TapBoard.Point, separator: String = ", "): String {
            val parts = listOfNotNull(
                if (kotlin.math.abs(drift.x) >= 0.5) "%.1f dp %s".format(kotlin.math.abs(drift.x), if (drift.x < 0) "left" else "right") else null,
                if (kotlin.math.abs(drift.y) >= 0.5) "%.1f dp %s".format(kotlin.math.abs(drift.y), if (drift.y < 0) "high" else "low") else null,
            )
            return if (parts.isEmpty()) "On center" else parts.joinToString(separator)
        }
    }
}

/**
 * How densely taps land (iOS's `TapHeat`): each key's learned Gaussian, weighted by its taps, summed, on a ramp from
 * indigo through blue to cyan (near white in dark, deepening to navy in light), on a square-root scale, full at the
 * densest 0.5%, so the space bar's narrow, crowded spot doesn't leave every letter faint.
 */
object TapHeat {
    private const val PIXELS = 2.0
    private val dark = listOf(Triple(52.0, 40.0, 170.0), Triple(10.0, 110.0, 255.0), Triple(64.0, 200.0, 255.0), Triple(226.0, 246.0, 255.0))
    private val light = listOf(Triple(150.0, 200.0, 255.0), Triple(10.0, 122.0, 255.0), Triple(36.0, 64.0, 214.0), Triple(24.0, 22.0, 120.0))

    private fun rgba(value: Double, isDark: Boolean): DoubleArray {
        val v = value.coerceIn(0.0, 1.0)
        val stops = if (isDark) dark else light
        val position = v * (stops.size - 1)
        val index = minOf(position.toInt(), stops.size - 2)
        val t = position - index
        val (low, high) = stops[index] to stops[index + 1]
        fun mix(a: Double, b: Double) = (a + (b - a) * t) / 255
        return doubleArrayOf(mix(low.first, high.first), mix(low.second, high.second), mix(low.third, high.third), minOf(1.0, v * 1.8) * 0.95)
    }

    fun color(value: Double, isDark: Boolean): Color = rgba(value, isDark).let { Color(it[0].toFloat(), it[1].toFloat(), it[2].toFloat(), it[3].toFloat()) }

    fun image(board: TapBoard, isDark: Boolean): ImageBitmap? {
        val width = (board.width * PIXELS).toInt()
        val height = (board.height * PIXELS).toInt()
        if (width <= 0 || height <= 0) return null
        val density = DoubleArray(width * height)
        for (aim in board.aims) {
            if (aim.taps <= 0) continue
            val (xx, xy, yy) = aim.spread
            val determinant = xx * yy - xy * xy
            if (determinant <= 0) continue
            val weight = aim.taps / (2 * Math.PI * sqrt(determinant))
            val reachX = 4 * sqrt(xx)
            val reachY = 4 * sqrt(yy)
            val columns = max(0, ((aim.center.x - reachX) * PIXELS).toInt())..minOf(width - 1, ((aim.center.x + reachX) * PIXELS).toInt())
            val rows = max(0, ((aim.center.y - reachY) * PIXELS).toInt())..minOf(height - 1, ((aim.center.y + reachY) * PIXELS).toInt())
            for (row in rows) {
                val dy = (row + 0.5) / PIXELS - aim.center.y
                for (column in columns) {
                    val dx = (column + 0.5) / PIXELS - aim.center.x
                    val distance = (yy * dx * dx - 2 * xy * dx * dy + xx * dy * dy) / determinant
                    if (distance < 16) density[row * width + column] += weight * exp(-distance / 2)
                }
            }
        }
        val lit = density.filter { it > 0 }.sorted()
        if (lit.isEmpty()) return null
        val peak = lit[((lit.size - 1) * 0.995).toInt()]
        val pixels = IntArray(width * height)
        for (index in density.indices) {
            if (density[index] <= 0) continue
            val (r, g, b, a) = rgba(sqrt(minOf(density[index] / peak, 1.0)), isDark).toList()
            pixels[index] = ((a * 255).toInt() shl 24) or ((r * 255).toInt() shl 16) or ((g * 255).toInt() shl 8) or (b * 255).toInt()
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888).asImageBitmap()
    }
}
