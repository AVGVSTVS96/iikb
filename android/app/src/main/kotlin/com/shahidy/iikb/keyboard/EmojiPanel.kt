package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.VelocityTracker
import android.widget.OverScroller
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

/**
 * The emoji panel in the bar's place (docs/design.md, "Emoji"): ten square cells across the keys block (more where it's
 * wider than ten of 44), what you pick most first, then every emoji, or what its search finds; the keys type into the
 * search row under it. The rows run past the bottom as iOS's grid's do, the next one showing in part, so it reads as
 * scrolling. One row that scrolls sideways where height is short. Drawn and touched in dp, from the top of the keyboard.
 */
class EmojiPanel(private val view: KeyboardView, private val scroller: OverScroller) {
    var results: List<String> = emptyList()
        set(value) {
            if (value != field) offset = 0f
            field = value
        }
    var query = ""

    private var offset = 0f
    private val text = Paint(Paint.ANTI_ALIAS_FLAG)
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private var velocity: VelocityTracker? = null
    private var down: Pair<Float, Float>? = null
    private var dragging = false
    private var pressed = -1
    var holding = -1
        private set

    private class Geometry(val area: RectF, val columns: Int, val cell: Float, val compact: Boolean, val field: RectF, val back: RectF) {
        val rowHeight get() = if (compact) area.height() else cell
    }

    private fun geometry(bar: Bar): Geometry {
        val minX = bar.blockMinX.toFloat()
        val maxX = bar.blockMaxX.toFloat()
        val top = bar.top.toFloat()
        val area = RectF(minX, top, maxX, top + bar.results.toFloat())
        val columns = maxOf(10, floor((maxX - minX) / 44).toInt())
        val cell = (maxX - minX) / columns
        val fieldTop = area.bottom + 6
        val back = RectF(minX, fieldTop, minX + 36, fieldTop + bar.field.toFloat())
        val field = RectF(back.right + 4, fieldTop, maxX, fieldTop + bar.field.toFloat())
        return Geometry(area, columns, cell, bar.compact, field, back)
    }

    private fun extent(g: Geometry): Float = if (g.compact) {
        (results.size * g.cell - g.area.width()).coerceAtLeast(0f)
    } else {
        (ceil(results.size / g.columns.toFloat()) * g.rowHeight - g.area.height()).coerceAtLeast(0f)
    }

    fun scroll() {
        if (scroller.computeScrollOffset()) {
            offset = scroller.currX.toFloat() / SCALE
            view.postInvalidateOnAnimation()
        }
    }

    fun draw(canvas: Canvas, frame: Frame, typeface: android.graphics.Typeface) {
        val bar = frame.toolbar
        val theme = frame.theme
        val g = geometry(bar)
        canvas.save()
        canvas.clipRect(0f, g.area.top, frame.width.toFloat(), g.area.bottom)
        text.textSize = g.cell * (if (g.compact) 26f else 30f) / DUO_CELL
        text.typeface = typeface
        text.color = theme.label
        val metrics = text.fontMetrics
        if (results.isEmpty() && query.isNotBlank()) {
            text.textSize = 15f
            text.color = theme.candidate
            val message = "No emoji for “${query.trim()}”"
            canvas.drawText(message, g.area.centerX() - text.measureText(message) / 2, g.area.centerY(), text)
        }
        for ((index, emoji) in results.withIndex()) {
            val place = place(g, index) ?: continue
            if (index == pressed || index == holding) {
                fill.color = theme.candidatePill
                canvas.drawRoundRect(place, 8f, 8f, fill)
            }
            val width = text.measureText(emoji)
            canvas.drawText(emoji, place.centerX() - width / 2, place.centerY() - (metrics.ascent + metrics.descent) / 2, text)
        }
        canvas.restore()
        drawSearch(canvas, frame, g, typeface)
    }

    private fun place(g: Geometry, index: Int): RectF? {
        val (x, y) = if (g.compact) {
            g.area.left + index * g.cell - offset to g.area.top
        } else {
            g.area.left + (index % g.columns) * g.cell to g.area.top + (index / g.columns) * g.rowHeight - offset
        }
        if (x + g.cell < g.area.left - g.cell || x > g.area.right + g.cell) return null
        if (y + g.rowHeight < g.area.top || y > g.area.bottom) return null
        return RectF(x, y, x + g.cell, y + g.rowHeight)
    }

    private fun drawSearch(canvas: Canvas, frame: Frame, g: Geometry, typeface: android.graphics.Typeface) {
        val theme = frame.theme
        fill.color = theme.label
        Glyphs.draw(canvas, "chevron.left", g.back.centerX(), g.back.centerY(), Glyphs.square(22f), fill)
        val radius = g.field.height() / 2
        fill.color = theme.searchField
        canvas.drawRoundRect(g.field, radius, radius, fill)
        fill.color = theme.candidate
        Glyphs.draw(canvas, "magnifyingglass", g.field.left + 14 + 10, g.field.centerY(), Glyphs.square(17f), fill)
        text.typeface = typeface
        text.textSize = 17f
        val metrics = text.fontMetrics
        val baseline = g.field.centerY() - (metrics.ascent + metrics.descent) / 2
        val start = g.field.left + 14 + 20 + 6
        if (query.isEmpty()) {
            text.color = theme.candidate
            canvas.drawText("Search emoji", start, baseline, text)
            fill.color = theme.prominent
            canvas.drawRect(start - 3, g.field.centerY() - 11, start - 1, g.field.centerY() + 11, fill)
        } else {
            text.color = theme.label
            canvas.drawText(query, start, baseline, text)
            val caret = start + text.measureText(query) + 1
            fill.color = theme.prominent
            canvas.drawRect(caret - 1, g.field.centerY() - 11, caret + 1, g.field.centerY() + 11, fill)
            fill.color = theme.candidate
            canvas.drawCircle(g.field.right - 12 - 14, g.field.centerY(), 10f, fill)
            fill.color = theme.searchField
            Glyphs.draw(canvas, "xmark", g.field.right - 12 - 14, g.field.centerY(), Glyphs.square(11f), fill, Glyphs.BOLD)
        }
    }

    /** A touch above the keys while the panel is open. True while the panel keeps it. */
    fun touch(event: MotionEvent, x: Float, y: Float, frame: Frame, actions: KeyboardView.Actions): Boolean {
        val g = geometry(frame.toolbar)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                scroller.forceFinished(true)
                down = x to y
                dragging = false
                velocity = VelocityTracker.obtain().also { it.addMovement(event) }
                pressed = if (g.area.contains(x, y)) index(g, x, y) else -1
                if (pressed >= 0) view.holdEmoji(pressed)
            }

            MotionEvent.ACTION_MOVE -> {
                val start = down ?: return false
                velocity?.addMovement(event)
                if (holding >= 0) return true
                val moved = if (g.compact) start.first - x else start.second - y
                if (!dragging && abs(moved) > SLOP) {
                    dragging = true
                    pressed = -1
                    view.cancelEmojiHold()
                }
                if (dragging) {
                    offset = (offset + moved).coerceIn(0f, extent(g))
                    down = x to y
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                view.cancelEmojiHold()
                val start = down
                down = null
                if (holding >= 0) {
                    holding = -1
                    return true
                }
                if (dragging) {
                    velocity?.let { tracker ->
                        tracker.computeCurrentVelocity(1000)
                        val speed = -(if (g.compact) tracker.xVelocity else tracker.yVelocity) / view.resources.displayMetrics.density
                        val max = (extent(g) * SCALE).toInt()
                        scroller.fling((offset * SCALE).toInt(), 0, (speed * SCALE).toInt(), 0, 0, max, 0, 0)
                        view.postInvalidateOnAnimation()
                    }
                } else if (start != null) {
                    when {
                        pressed >= 0 -> results.getOrNull(pressed)?.let { actions.pickEmoji(it, null) }
                        g.back.contains(x, y) -> actions.closePanel()
                        query.isNotEmpty() && x > g.field.right - 44 && g.field.contains(x, y) -> actions.clearSearch()
                    }
                }
                pressed = -1
                velocity?.recycle()
                velocity = null
            }

            MotionEvent.ACTION_CANCEL -> {
                view.cancelEmojiHold()
                pressed = -1
                holding = -1
                down = null
            }
        }
        return true
    }

    fun startHold(index: Int) {
        holding = index
        pressed = -1
    }

    /** Where the held emoji sits, for its tones. */
    fun frameOf(index: Int, frame: Frame): RectF? = place(geometry(frame.toolbar), index)

    private fun index(g: Geometry, x: Float, y: Float): Int {
        val index = if (g.compact) {
            floor((x - g.area.left + offset) / g.cell).toInt()
        } else {
            floor((y - g.area.top + offset) / g.rowHeight).toInt() * g.columns + floor((x - g.area.left) / g.cell).toInt()
        }
        return if (index in results.indices) index else -1
    }

    private companion object {
        /** The cell the spec's emoji sizes are set in, on the Duo's cover screen. */
        const val DUO_CELL = 45.3f
        const val SLOP = 8f
        /** The scroller works in whole numbers; offsets are kept in hundredths of a dp. */
        const val SCALE = 100f
    }
}
