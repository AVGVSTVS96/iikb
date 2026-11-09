package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Paint
import android.os.SystemClock
import android.view.View
import androidx.core.graphics.ColorUtils

/**
 * The line a swipe leaves behind the finger, as iOS's `TrailView`: thin, each stretch fading as it ages, and gone a
 * moment after the finger lifts.
 */
class Trail(private val view: View) {
    private class Point(val x: Float, val y: Float, val time: Long)

    private val points = ArrayDeque<Point>()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeWidth = WIDTH
    }

    fun begin(samples: List<KeyboardView.SwipePoint>) {
        points.clear()
        samples.forEach { add(it.x, it.y) }
    }

    fun add(x: Float, y: Float) {
        points.addLast(Point(x, y, SystemClock.uptimeMillis()))
        view.postInvalidateOnAnimation()
    }

    fun draw(canvas: Canvas, color: Int) {
        val now = SystemClock.uptimeMillis()
        while (points.isNotEmpty() && now - points.first().time > LIFETIME) points.removeFirst()
        if (points.isEmpty()) return
        view.postInvalidateOnAnimation()
        for (index in 1 until points.size) {
            val from = points[index - 1]
            val to = points[index]
            val fade = (1 - (now - to.time) / LIFETIME.toFloat()).coerceAtLeast(0f)
            paint.color = ColorUtils.setAlphaComponent(color, (255 * fade * 0.9f).toInt())
            canvas.drawLine(from.x, from.y, to.x, to.y, paint)
        }
    }

    private companion object {
        const val LIFETIME = 400L
        const val WIDTH = 3f
    }
}
