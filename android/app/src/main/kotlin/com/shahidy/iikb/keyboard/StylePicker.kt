package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import com.shahidy.iikb.Tracking
import kotlin.math.ceil

/**
 * The bar's writing style, as iOS's `StylePicker`: the style a dictation in this app is written in, its name on a
 * platter in a capsule of the bar's glass (`BarGlass`) in its place before the mic (`Bar.style`). A tap opens it
 * leftward over the suggestions, which fade under it, into every style with the platter still under the picked one;
 * picking slides the platter to the new one and folds it back around it. In dp.
 */
class StylePicker(private val view: View, labels: Typeface) {
    var isOpen = false
        private set
    private val openness = Moving(0f)
    /** The platter's slide from `from` to the picked style, while it's open. */
    private val slide = Moving(1f)
    private var from = 0
    /** A pick made here, shown until the frame says it's kept. */
    private var shown: Int? = null
    /** It folds once the platter has slid to a pick. */
    private var folding = false
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(labels, 600, false)
        textSize = FONT
        letterSpacing = Tracking.at(FONT).value
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)

    fun picked(writing: Writing) = shown ?: writing.picked

    /** The frame came: a pick it keeps is no longer only this one's. */
    fun update(writing: Writing?) {
        if (writing == null || writing.picked == shown) shown = null
    }

    /** How far it's open, 0 to 1, which the suggestions fade out by. */
    fun openness(now: Long = Curve.now()) = openness.at(now)

    fun open() {
        if (isOpen) return
        isOpen = true
        openness.go(1f, Curve.morph(true))
        view.postInvalidateOnAnimation()
    }

    /** Folds it, as typing, dictating and the menu do. */
    fun fold() {
        folding = false
        if (!isOpen) return
        isOpen = false
        openness.go(0f, Curve.morph(false))
        view.postInvalidateOnAnimation()
    }

    /** Gone from the bar: folded at once. */
    fun hide() {
        folding = false
        isOpen = false
        openness.jump(0f)
    }

    /** A tap at `x`: opens it, or picks the style there, which it returns, or folds it on the picked one. */
    fun tap(bar: Bar, writing: Writing, x: Float): Int? {
        if (!isOpen) {
            open()
            return null
        }
        val places = places(bar, writing)
        val index = places.indexOfFirst { x < it.right }.takeIf { it >= 0 } ?: places.lastIndex
        val picked = picked(writing)
        if (index == picked) {
            fold()
            return null
        }
        from = picked
        shown = index
        slide.jump(0f)
        slide.go(1f, Curve.spring(SLIDE, BOUNCE))
        folding = true
        view.postInvalidateOnAnimation()
        return index
    }

    /** The capsule where it is now, folded in its place or open over the suggestions. */
    fun track(bar: Bar, writing: Writing, now: Long = Curve.now()): RectF {
        val place = bar.style!!
        val t = openness.at(now)
        val open = minOf(openWidth(writing), (place.x + place.width - bar.minX).toFloat())
        val width = place.width.toFloat() + (open - place.width.toFloat()) * t
        val top = (place.midY - HEIGHT / 2).toFloat()
        val right = (place.x + place.width).toFloat()
        return RectF(right - width, top, right, top + HEIGHT)
    }

    fun draw(canvas: Canvas, bar: Bar, writing: Writing, theme: Theme, glass: BarGlass) {
        val now = Curve.now()
        if (folding && !slide.moving(now)) fold()
        val t = openness.at(now)
        val track = track(bar, writing, now)
        glass.draw(canvas, track, theme)
        val picked = picked(writing)
        val full = RectF(track).apply { inset(INSET, INSET) }
        val folded = foldedPlace(bar)
        val open = places(bar, writing)
        val platter = lerp(folded, lerp(open[from.coerceIn(open.indices)], open[picked], slide.at(now)), t)
        val dark = Color.red(theme.label) > 128
        fill.color = if (dark) Color.argb(36, 255, 255, 255) else Color.WHITE
        if (!dark) fill.setShadowLayer(3f, 0f, 1f, Color.argb(31, 0, 0, 0))
        val radius = platter.height() / 2
        canvas.drawRoundRect(platter, radius, radius, fill)
        fill.clearShadowLayer()
        canvas.save()
        canvas.clipRect(full)
        val foldedShift = folded.centerX() - open[picked].centerX()
        for ((index, style) in writing.styles.withIndex()) {
            val alpha = if (index == picked) 1f else t
            if (alpha <= 0f) continue
            val center = open[index].centerX() + foldedShift * (1 - t)
            val color = if (index == picked) theme.label else theme.candidate
            text.color = color
            text.alpha = (Color.alpha(color) * alpha).toInt()
            val width = text.measureText(style.title)
            canvas.drawText(style.title, center - width / 2, track.centerY() + text.textSize * 0.35f, text)
        }
        canvas.restore()
        if (openness.moving(now) || slide.moving(now) || folding) view.postInvalidateOnAnimation()
    }

    /** Open, each style's place side by side from the open capsule's left. */
    private fun places(bar: Bar, writing: Writing): List<RectF> {
        val place = bar.style!!
        val right = (place.x + place.width).toFloat()
        val left = right - minOf(openWidth(writing), (place.x + place.width - bar.minX).toFloat())
        val top = (place.midY - HEIGHT / 2).toFloat() + INSET
        var x = left + INSET
        return writing.styles.map {
            val width = labelWidth(it.title)
            RectF(x, top, x + width, top + HEIGHT - 2 * INSET).also { x += width }
        }
    }

    private fun foldedPlace(bar: Bar): RectF {
        val place = bar.style!!
        val top = (place.midY - HEIGHT / 2).toFloat()
        return RectF(place.x.toFloat() + INSET, top + INSET, (place.x + place.width).toFloat() - INSET, top + HEIGHT - INSET)
    }

    private fun openWidth(writing: Writing) = writing.styles.sumOf { labelWidth(it.title).toDouble() }.toFloat() + 2 * INSET

    private fun labelWidth(title: String) = ceil(text.measureText(title)) + 2 * PADDING

    private fun lerp(a: RectF, b: RectF, t: Float) = RectF(
        a.left + (b.left - a.left) * t, a.top + (b.top - a.top) * t, a.right + (b.right - a.right) * t, a.bottom + (b.bottom - a.bottom) * t,
    )

    private companion object {
        /** As iOS's `StylePicker`, in points: as tall as the chats' tabs. */
        const val HEIGHT = TABS_HEIGHT
        const val INSET = 2f
        const val PADDING = 12f
        const val FONT = 15f
        /** The platter's slide, as `UIView.animate(springDuration: 0.4, bounce: 0.18)`. */
        const val SLIDE = 0.4f
        const val BOUNCE = 0.18f
    }
}
