package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.TextUtils
import android.text.TextPaint
import androidx.core.graphics.ColorUtils
import com.shahidy.iikb.voice.Dictation
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Once you stop, the dictations recorded while the model gets ready, as a stack of cards beside what it's doing, as
 * iOS's `PendingStack` stacks them: the next to be typed in front with its length, up to three more tucked behind it
 * and peeking out 6 to its right, each a little smaller and a solid shade further back. A new one slides in behind
 * from the mic's side; the front one lifts away as it's typed, and the next steps forward into its place. In dp.
 */
class PendingStack {
    private class Card {
        var length = ""
        var placed = false
        val x = Moving(0f)
        val width = Moving(0f)
        val height = Moving(0f)
        val alpha = Moving(0f)
        val shade = Moving(0f)
        val label = Moving(0f)
        /** 1 while it's still where a new card starts, nudged toward the mic and a little smaller. */
        val enter = Moving(0f)
    }

    /** A typed card lifting away from where it was. */
    private class Gone(val card: Card, val start: Long)

    private var cards = listOf<Card>()
    private val gone = mutableListOf<Gone>()
    private var lengths = listOf<Double>()
    private var waitingFor: String? = null
    private var words = ""
    private var shows = false
    /** Whether the next draw places everything, and whether it moves there. */
    private var placing: Boolean? = true
    private var room = RectF()

    private val alpha = Moving(0f)
    private val wordsAlpha = Moving(0f)
    private val wordsX = Moving(0f)

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        fontFeatureSettings = "tnum"
        textSize = 13f
        typeface = Typeface.create(Typeface.DEFAULT, 500, false)
        textAlign = Paint.Align.CENTER
    }
    private val wording = TextPaint(Paint.ANTI_ALIAS_FLAG)

    /** It shows while the model writes and keeps saved dictations waiting, and stays up as it takes them, until the last is typed. */
    fun show(phase: Dictation.Phase, saved: List<Double>, waitingFor: String?, now: Long) {
        val shown = shows
        shows = phase == Dictation.Phase.WRITING && saved.isNotEmpty() && (waitingFor != null || shows)
        val reworded = waitingFor != this.waitingFor
        this.waitingFor = waitingFor
        if (waitingFor != null) words = waitingFor
        val restacked = saved != lengths
        if (restacked) restack(saved, animated = shown, now)
        val moves = shown != shows || (shows && (restacked || reworded))
        placing = moves || placing == true
    }

    val covers get() = shows || alpha.target > 0

    fun busy(now: Long) = alpha.moving(now) || gone.isNotEmpty() || wordsAlpha.moving(now) ||
        cards.any { it.x.moving(now) || it.alpha.moving(now) || it.enter.moving(now) || it.width.moving(now) }

    /** The cards still waiting kept: the oldest typed lift away, and the newly saved join at the back. */
    private fun restack(saved: List<Double>, animated: Boolean, now: Long) {
        val typed = lengths.size - saved.size
        cards = when {
            typed > 0 && lengths.drop(typed) == saved -> {
                if (animated) cards.take(typed).forEach { gone.add(Gone(it, now)) }
                cards.drop(typed)
            }
            saved.size >= lengths.size && saved.take(lengths.size) == lengths -> cards + List(saved.size - lengths.size) { Card() }
            else -> List(saved.size) { Card() }
        }
        lengths = saved
        for ((index, card) in cards.withIndex()) card.length = MicBar.clock(max(saved[index].roundToInt(), 1))
    }

    /** Everything where the state puts it; hidden, the cards forget their places, so they come in afresh next time. */
    private fun place(animated: Boolean, now: Long) {
        fun Moving.to(value: Float) {
            if (animated) go(value, Curve.settle, now = now) else if (value != target) jump(value)
        }
        alpha.to(if (shows) 1f else 0f)
        if (!shows) {
            cards.forEach { it.placed = false }
            wordsAlpha.to(0f)
            return
        }
        val front = cards.firstOrNull() ?: return
        val height = min(room.height() - 12, 26f)
        val width = label.measureText(front.length) + 20
        val stack = width + min(cards.size - 1, SHADES.size - 1) * PEEK
        val wordsWidth = if (waitingFor == null) 0f else min(wording.apply { textSize = 15f }.measureText(words), room.width() * 0.6f)
        val minX = room.left + (room.width() - stack - if (wordsWidth > 0) wordsWidth + 10 else 0f) / 2
        for ((depth, card) in cards.withIndex()) {
            val place = min(depth, SHADES.size - 1)
            val shrink = 1 - 0.08f * place
            val center = minX + width + place * PEEK - width * shrink / 2
            if (!card.placed) {
                card.placed = true
                card.x.jump(center)
                card.width.jump(width * shrink)
                card.height.jump(height * shrink)
                card.alpha.jump(0f)
                card.shade.jump(SHADES[place])
                card.enter.jump(1f)
            }
            card.x.to(center)
            card.width.to(width * shrink)
            card.height.to(height * shrink)
            card.enter.to(0f)
            card.alpha.to(if (depth < SHADES.size) 1f else 0f)
            card.shade.to(SHADES[place])
            card.label.to(if (depth == 0) 1f else 0f)
        }
        if (wordsWidth <= 0) return wordsAlpha.to(0f)
        val x = minX + stack + 10
        if (wordsAlpha.at(now) == 0f) wordsX.jump(x) else wordsX.to(x)
        wordsAlpha.to(1f)
    }

    /** In `room`, the bar between the recording's left end and the mic. */
    fun draw(canvas: Canvas, frame: Frame, room: RectF, now: Long) {
        if (room != this.room) {
            this.room = RectF(room)
            placing = placing ?: false
        }
        placing?.let {
            placing = null
            place(it, now)
        }
        val shown = alpha.at(now)
        val theme = frame.theme
        gone.removeAll { (now - it.start) / 1000f >= GONE.seconds }
        if (shown <= 0.001f && gone.isEmpty()) return
        for (card in cards.asReversed()) drawCard(canvas, theme, card, shown, now, lift = 0f)
        for (lifting in gone) drawCard(canvas, theme, lifting.card, shown, now, GONE.progress((now - lifting.start) / 1000f))
        val wordsShown = wordsAlpha.at(now) * shown
        if (wordsShown <= 0.001f) return
        val space = room.width() * 0.6f
        wording.textSize = 15f
        val wide = wording.measureText(words)
        if (wide > space) wording.textSize = max(15f * space / wide, 15f * 0.7f)
        val line = TextUtils.ellipsize(words, wording, space, TextUtils.TruncateAt.END).toString()
        wording.color = ColorUtils.setAlphaComponent(theme.candidate, (android.graphics.Color.alpha(theme.candidate) * wordsShown).toInt())
        canvas.drawText(line, wordsX.at(now), room.centerY() + wording.textSize * 0.35f, wording)
    }

    private fun drawCard(canvas: Canvas, theme: Theme, card: Card, shown: Float, now: Long, lift: Float) {
        val opacity = card.alpha.at(now) * shown * (1 - lift)
        if (opacity <= 0.001f) return
        val enter = card.enter.at(now)
        val scale = (1 - 0.1f * enter) * (1 - 0.06f * lift)
        val w = card.width.at(now) * scale
        val h = card.height.at(now) * scale
        val x = card.x.at(now) + 12 * enter
        val y = room.centerY() - 8 * lift
        fill.color = ColorUtils.blendARGB(theme.candidatePill, theme.candidateDivider, card.shade.at(now))
        fill.alpha = (fill.alpha * opacity).toInt()
        canvas.drawRoundRect(x - w / 2, y - h / 2, x + w / 2, y + h / 2, h / 2, h / 2, fill)
        val labelShown = card.label.at(now) * opacity
        if (labelShown <= 0.001f) return
        label.color = ColorUtils.setAlphaComponent(theme.label, (android.graphics.Color.alpha(theme.label) * labelShown).toInt())
        canvas.save()
        canvas.scale(scale, scale, x, y)
        canvas.drawText(card.length, x, y + label.textSize * 0.35f, label)
        canvas.restore()
    }

    private companion object {
        const val PEEK = 6f
        val SHADES = floatArrayOf(0f, 0.45f, 0.7f, 0.9f)
        val GONE = Curve.easeOut(0.22f)
    }
}
