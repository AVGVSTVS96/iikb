package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import androidx.core.graphics.ColorUtils
import com.shahidy.iikb.voice.Dictation
import kotlin.math.max
import kotlin.math.min

/**
 * The recording as iOS's `Waveform` draws it: the time so far, then bars that trace your voice, newest on the right,
 * each as bright as it was loud, the older ones fading out to the left. Each level enters at the right edge and the
 * bars glide left one place in the time the microphone took to hear it, so they move at the recording's speed. While
 * dictations wait for the model it counts them at its right. When you stop, the bars hold still where they were, and a
 * stop animation can rush them into the mic. In dp, over the bar's recording span, masked to what holds it.
 */
class Waveform {
    private class Bar(val level: Float, val born: Long)

    private var phase = Dictation.Phase.OFF
    private var recorded = 0.0
    private var lastRecorded = 0.0
    private val bars = ArrayDeque<Bar>()
    private var fits = 0
    private var refill = true
    private var saved = 0
    private var savedText = ""

    private val alpha = Moving(0f)
    private val savedShown = Moving(0f)
    /** How far right of its place the strip still is while it glides the newest level in. */
    private val lag = Moving(0f)
    /** How far the stopped bars have rushed, in track widths. */
    private val rushed = Moving(0f)
    /** When Drain started sinking the bars, 0 if it hasn't. */
    private var sunk = 0L

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        fontFeatureSettings = "tnum"
        textSize = 15f
        typeface = Typeface.create(Typeface.DEFAULT, 500, false)
    }

    /** A new recording starts from quiet bars and fades in as the capsule uncovers it; a stopped one holds still and goes. */
    fun show(phase: Dictation.Phase, recorded: Double, saved: Int, now: Long) {
        val listening = phase == Dictation.Phase.LISTENING
        val started = listening && this.phase != Dictation.Phase.LISTENING
        val stopped = !listening && this.phase == Dictation.Phase.LISTENING
        if (stopped) lag.jump(lag.at(now))
        this.phase = phase
        this.recorded = recorded
        val counted = saved > 0 && listening
        if (saved > 0) savedText = "$saved saved"
        this.saved = saved
        if (started) {
            refill = true
            sunk = 0L
            rushed.jump(0f)
            lag.jump(0f)
            alpha.jump(0f)
            alpha.go(1f, Curve.easeOut(0.25f), delay = 0.05f, now = now)
            savedShown.jump(if (counted) 1f else 0f)
        } else {
            if (stopped) alpha.go(0f, Curve.easeOut(0.15f), now = now)
            savedShown.go(if (counted) 1f else 0f, Curve.settle, now = now)
        }
    }

    fun hear(level: Float, recorded: Double, now: Long) {
        if (phase != Dictation.Phase.LISTENING || fits == 0) return
        val interval = (recorded - lastRecorded).coerceIn(0.03, 0.25).toFloat()
        this.recorded = recorded
        lastRecorded = recorded
        val loud = MicBar.loudness(level)
        val last = bars.lastOrNull()?.level ?: 0f
        bars.addLast(Bar(last + (loud - last) * (if (loud > last) 0.7f else 0.35f), now))
        while (bars.size > fits + 2) bars.removeFirst()
        lag.jump(lag.at(now) + PITCH)
        lag.go(0f, Curve.linear(interval), now = now)
    }

    /** Squeeze: the stopped bars rush into the stop as the capsule springs after them; Drain's ride its red in, slower. */
    fun rush(direction: Float, duration: Float, now: Long) {
        rushed.go(direction * 0.7f, Curve.easeIn(duration), now = now)
        alpha.go(0f, Curve.easeIn(duration), now = now, again = true)
    }

    /** Drain toward the Record Key: the bars sink to dots and run down out of the bar, the ones nearest the key first. */
    fun sink(now: Long) {
        sunk = now
        alpha.go(0f, Curve.easeIn(0.5f), now = now, again = true)
    }

    /** Gone at once, as the cancelled recording turns to dust. */
    fun hide() = alpha.jump(0f)

    fun reveal() = alpha.jump(1f)

    fun busy(now: Long) = phase == Dictation.Phase.LISTENING || alpha.moving(now) || savedShown.moving(now)

    /**
     * Over `span`, its time `leading` in from the left and its bars ending `trailing` short of the right, masked to
     * `mask`, in `tint`.
     */
    fun draw(canvas: Canvas, span: RectF, leading: Float, trailing: Float, mask: Path?, tint: Int, now: Long, opacity: Float = 1f) {
        val shown = alpha.at(now) * opacity
        val counting = savedShown.at(now)
        val end = span.right - trailing
        val count = if (counting > 0) (text.measureText(savedText) + 10) * counting else 0f
        val start = span.left + leading + 48
        val width = max(end - count - start, 0f)
        fits = (width / PITCH).toInt()
        if (refill && fits > 0) {
            refill = false
            bars.clear()
            repeat(fits + 1) { bars.addLast(Bar(0f, 0L)) }
            lastRecorded = recorded
        }
        if (shown <= 0.001f) return
        canvas.save()
        mask?.let { canvas.clipPath(it) }
        text.textAlign = Paint.Align.LEFT
        text.color = ColorUtils.setAlphaComponent(tint, (0.9f * 255 * shown).toInt())
        val baseline = span.centerY() + text.textSize * 0.35f
        canvas.drawText(MicBar.clock(recorded.toInt()), span.left + leading, baseline, text)
        if (counting > 0) {
            text.textAlign = Paint.Align.RIGHT
            text.color = ColorUtils.setAlphaComponent(tint, (0.9f * 255 * shown * counting).toInt())
            canvas.drawText(savedText, end, baseline, text)
        }
        val tallest = max(min(span.height() - 12, 18f), BAR)
        val strip = lag.at(now) + rushed.at(now) * width
        val far = max(1 - 4 / max(width, 1f), 0.9f)
        for ((index, bar) in bars.withIndex()) {
            val left = start + width - BAR - (bars.size - 1 - index) * PITCH + strip
            val along = (left + BAR / 2 - start) / max(width, 1f)
            val faded = when {
                along <= 0 || along >= 1 -> 0f
                along < 0.35f -> along / 0.35f
                along > far -> (1 - along) / (1 - far)
                else -> 1f
            }
            if (faded <= 0) continue
            val grown = if (bar.born == 0L) 1f else 0.2f + 0.8f * Curve.follow.progress((now - bar.born) / 1000f)
            val place = (index - (bars.size - fits - 1)).coerceAtLeast(0)
            val sinking = if (sunk == 0L) 0f else SINKING.progress((now - sunk) / 1000f - 0.22f * place / (fits + 1))
            val height = (BAR + (tallest - BAR) * bar.level) * grown * (1 - 0.85f * sinking)
            val drop = 9 * sinking
            fill.color = ColorUtils.setAlphaComponent(tint, (255 * (0.5f + 0.5f * bar.level) * faded * shown).toInt())
            val middle = span.centerY() + drop
            canvas.drawRoundRect(left, middle - height / 2, left + BAR, middle + height / 2, BAR / 2, BAR / 2, fill)
        }
        canvas.restore()
    }

    private companion object {
        const val PITCH = 5f
        const val BAR = 2.5f
        val SINKING = Curve.easeIn(0.28f)
    }
}
