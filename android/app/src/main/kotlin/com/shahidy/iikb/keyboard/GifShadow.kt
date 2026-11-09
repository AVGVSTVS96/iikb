package com.shahidy.iikb.keyboard

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Point
import android.graphics.RectF
import android.view.View

/** A dragged GIF under the finger: its first frame, 120 dp on its long side, rounded as the panel's tiles are. */
class GifShadow(private val frame: Bitmap, density: Float) : View.DragShadowBuilder() {
    private val scale = 120 * density / maxOf(frame.width, frame.height)
    private val width = (frame.width * scale).toInt().coerceAtLeast(1)
    private val height = (frame.height * scale).toInt().coerceAtLeast(1)
    private val radius = 8 * density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    override fun onProvideShadowMetrics(size: Point, touch: Point) {
        size.set(width, height)
        touch.set(width / 2, height / 2)
    }

    override fun onDrawShadow(canvas: Canvas) {
        val bounds = RectF(0f, 0f, width.toFloat(), height.toFloat())
        canvas.clipPath(Path().apply { addRoundRect(bounds, radius, radius, Path.Direction.CW) })
        canvas.drawBitmap(frame, null, bounds, paint)
    }
}
