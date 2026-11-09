package com.shahidy.iikb.keyboard

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Something thrown away, breaking into dust as iOS's `Dust` breaks it, and as a deleted message does in Telegram: a
 * picture of it cut into specks that blow off up and away, starting from `origin` (a point on the x axis) and
 * sweeping across. `picture` is `area` drawn at `density` pixels to the dp. With animations off it fades instead.
 */
class Dust(private val picture: Bitmap, private val area: RectF, origin: Float, direction: Float, density: Float, private val start: Long) {
    private class Speck(
        val source: Rect, val place: RectF, val dx: Float, val dy: Float, val shrink: Float, val seconds: Float, val delay: Float,
    )

    private val fades = !Curve.moves
    private val specks: List<Speck>
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val drawn = RectF()

    init {
        val width = picture.width
        val height = picture.height
        val pixels = IntArray(width * height)
        picture.getPixels(pixels, 0, width, 0, 0, width, height)
        val side = max(1.5f, sqrt(area.width() * area.height() / 2400))
        val reach = max(max(abs(origin - area.left), abs(area.right - origin)), 1f)
        val specks = mutableListOf<Speck>()
        var y = 0f
        while (y < area.height()) {
            var x = 0f
            while (x < area.width()) {
                val tile = RectF(x, y, min(x + side, area.width()), min(y + side, area.height()))
                val px = min((tile.centerX() * density).toInt(), width - 1)
                val py = min((tile.centerY() * density).toInt(), height - 1)
                if (pixels[py * width + px] ushr 24 > 24) {
                    val source = Rect(
                        floor(tile.left * density).toInt(), floor(tile.top * density).toInt(),
                        min(ceil(tile.right * density).toInt(), width), min(ceil(tile.bottom * density).toInt(), height),
                    )
                    specks += Speck(
                        source, RectF(tile).apply { offset(area.left, area.top) },
                        dx = direction * (2 + Random.nextFloat() * 28), dy = -(6 + Random.nextFloat() * 30),
                        shrink = 0.2f + Random.nextFloat() * 0.5f, seconds = 0.5f + Random.nextFloat() * 0.3f,
                        delay = abs(area.left + tile.centerX() - origin) / reach * 0.32f + Random.nextFloat() * 0.07f,
                    )
                }
                x += side
            }
            y += side
        }
        this.specks = specks
    }

    /** Draws it as it is at `now`; false once it's gone. */
    fun draw(canvas: Canvas, now: Long): Boolean {
        val t = (now - start) / 1000f
        if (fades) {
            if (t >= 0.25f) return false
            paint.alpha = (255 * (1 - t / 0.25f)).toInt()
            canvas.drawBitmap(picture, null, area, paint)
            return true
        }
        var left = false
        for (speck in specks) {
            val p = (t - speck.delay) / speck.seconds
            if (p >= 1) continue
            left = true
            val shown = p.coerceAtLeast(0f)
            val moved = MOVE.progress(shown)
            val bend = 2 * (1 - moved) * moved
            val x = bend * 0.35f * speck.dx + moved * moved * speck.dx
            val y = bend * 0.9f * speck.dy + moved * moved * speck.dy
            val scale = 1 + (speck.shrink - 1) * shown
            val w = speck.place.width() * scale / 2
            val h = speck.place.height() * scale / 2
            drawn.set(speck.place.centerX() + x - w, speck.place.centerY() + y - h, speck.place.centerX() + x + w, speck.place.centerY() + y + h)
            paint.alpha = (255 * (1 - FADE.progress(shown))).toInt()
            canvas.drawBitmap(picture, speck.source, drawn, paint)
        }
        return left
    }

    private companion object {
        val MOVE = Curve.bezier(1f, 0.2f, 0.6f, 0.35f, 1f)
        val FADE = Curve.easeIn(1f)
    }
}
