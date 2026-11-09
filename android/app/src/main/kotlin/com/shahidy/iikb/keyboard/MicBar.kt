package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.os.SystemClock
import android.view.View
import androidx.core.graphics.ColorUtils
import com.shahidy.iikb.voice.Dictation
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The bar's mic as docs/design.md ("The mic") draws it, as iOS's `MicButton`, `Waveform` and `PendingStack` do. While
 * you talk it turns record red and grows on a spring into a capsule over the suggestions, with the time and a waveform
 * of your voice inside, a white stop where the mic was, a soft red halo that swells as you talk, and a cancel button
 * before it. Once you stop it shrinks back into the circle, which spins while the model writes, and the dictations
 * waiting for the model stack as cards in the recording's place beside what they wait for. In dp.
 */
class MicBar(private val view: View) {
    var phase = Dictation.Phase.OFF
        private set
    private var recorded = 0.0
    private var saved: List<Double> = emptyList()
    private var waitingFor: String? = null

    /** Each level heard, as loudness from 0 to 1, the newest last. */
    private val levels = ArrayDeque<Float>()
    private var voice = 0f
    private var shownVoice = 0f

    private var growth = 0f
    private var growFrom = 0f
    private var growTo = 0f
    private var growStart = 0L

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { fontFeatureSettings = "tnum" }
    private val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeWidth = 2.5f
    }
    private val clip = Path()

    /** The capsule or the cards stand over the suggestions, which hide meanwhile. */
    val covers get() = growth > 0.01f || cards

    private val cards get() = phase == Dictation.Phase.WRITING && saved.isNotEmpty() && waitingFor != null

    fun show(phase: Dictation.Phase, recorded: Double, saved: List<Double>, waitingFor: String?) {
        val listening = phase == Dictation.Phase.LISTENING
        if (listening != (this.phase == Dictation.Phase.LISTENING)) {
            growFrom = growth
            growTo = if (listening) 1f else 0f
            growStart = SystemClock.uptimeMillis()
            if (listening) levels.clear()
        }
        this.phase = phase
        this.recorded = recorded
        this.saved = saved
        this.waitingFor = waitingFor
        view.postInvalidateOnAnimation()
    }

    /** A level the microphone heard, its root mean square: it enters the waveform at the right. */
    fun hear(level: Float, recorded: Double) {
        this.recorded = recorded
        voice = loudness(level)
        levels.addLast(voice)
        while (levels.size > 80) levels.removeFirst()
        view.postInvalidateOnAnimation()
    }

    fun hitsCancel(frame: Frame, x: Float, y: Float): Boolean {
        if (phase != Dictation.Phase.LISTENING) return false
        val cancel = frame.toolbar.cancel
        return abs(cancel.midX - x) <= frame.toolbar.bar / 2 && y < frame.toolbar.height
    }

    fun draw(canvas: Canvas, frame: Frame) {
        val box = frame.toolbar.mic ?: return
        val theme = frame.theme
        val now = SystemClock.uptimeMillis()
        val elapsed = (now - growStart) / 1000f
        growth = if (elapsed >= SETTLED) growTo else growFrom + (growTo - growFrom) * spring(elapsed)
        shownVoice += (voice - shownVoice) * 0.12f
        val shown = growth.coerceIn(0f, 1f)
        val radius = (box.width / 2).toFloat()
        val mic = RectF(box.x.toFloat(), box.y.toFloat(), (box.x + box.width).toFloat(), (box.y + box.height).toFloat())
        val recording = frame.toolbar.recording
        val capsule = RectF(mic.left + (recording.x.toFloat() - mic.left) * growth, mic.top, mic.right, mic.bottom)
        val red = theme.record

        if (cards) drawCards(canvas, frame, RectF(recording.x.toFloat(), frame.toolbar.top.toFloat(), mic.left - 6, frame.toolbar.height.toFloat()))
        if (shown > 0) drawCancel(canvas, frame, mic, shown)
        if (shown > 0 && phase == Dictation.Phase.LISTENING) {
            val out = 1 + 3 * shownVoice
            fill.color = ColorUtils.setAlphaComponent(red, (0.2f * 255 * shown).toInt())
            val halo = RectF(capsule.left - out, capsule.top - out, capsule.right + out, capsule.bottom + out)
            canvas.drawRoundRect(halo, radius + out, radius + out, fill)
        }
        fill.color = ColorUtils.blendARGB(theme.mic, red, shown)
        canvas.drawRoundRect(capsule, radius, radius, fill)
        if (shown > 0) drawInside(canvas, capsule, mic, shown)

        val cx = mic.centerX()
        val cy = mic.centerY()
        val idle = 1 - shown
        if (phase == Dictation.Phase.WRITING && shown < 0.5f) {
            arc.color = theme.micGlyph
            val inset = mic.width() * 0.22f
            val turn = (now % 900) / 900f * 360f
            canvas.drawArc(RectF(mic.left + inset, mic.top + inset, mic.right - inset, mic.bottom - inset), turn, 108f, false, arc)
        } else if (idle > 0) {
            fill.color = ColorUtils.setAlphaComponent(theme.micGlyph, (Color.alpha(theme.micGlyph) * idle).toInt())
            Glyphs.draw(canvas, "waveform", cx, cy, mic.width() * 0.6f * (1 - 0.5f * shown), fill)
        }
        if (shown > 0) {
            fill.color = ColorUtils.setAlphaComponent(Color.WHITE, (255 * shown).toInt())
            Glyphs.draw(canvas, "stop.fill", cx, cy, mic.width() * 0.74f * (0.5f + 0.5f * shown), fill)
        }
        if (elapsed < SETTLED || phase != Dictation.Phase.OFF) view.postInvalidateOnAnimation()
    }

    /** The gray circle with an `xmark`, tucked at half its size behind the mic until the capsule lets it out. */
    private fun drawCancel(canvas: Canvas, frame: Frame, mic: RectF, shown: Float) {
        val cancel = frame.toolbar.cancel
        val x = mic.centerX() + (cancel.midX.toFloat() - mic.centerX()) * growth
        val y = cancel.midY.toFloat()
        fill.color = ColorUtils.setAlphaComponent(frame.theme.candidatePill, (Color.alpha(frame.theme.candidatePill) * shown).toInt())
        canvas.drawCircle(x, y, mic.width() / 2 * (0.5f + 0.5f * shown), fill)
        fill.color = ColorUtils.setAlphaComponent(frame.theme.label, (255 * shown).toInt())
        Glyphs.draw(canvas, "xmark", x, y, 22f * (0.5f + 0.5f * shown), fill)
    }

    /** The time 12 in from the left end and the waveform after it, masked to the capsule as it grows. */
    private fun drawInside(canvas: Canvas, capsule: RectF, mic: RectF, shown: Float) {
        val fade = ((shown - 0.4f) / 0.6f).coerceIn(0f, 1f)
        if (fade <= 0) return
        canvas.save()
        clip.reset()
        clip.addRoundRect(capsule, capsule.height() / 2, capsule.height() / 2, Path.Direction.CW)
        canvas.clipPath(clip)
        text.textSize = 15f
        text.typeface = Typeface.create(Typeface.DEFAULT, 500, false)
        text.color = ColorUtils.setAlphaComponent(Color.WHITE, (0.9f * 255 * fade).toInt())
        val seconds = recorded.toInt()
        val clock = clock(seconds)
        val textLeft = capsule.left + 12
        canvas.drawText(clock, textLeft, capsule.centerY() + text.textSize * 0.35f, text)
        val start = textLeft + text.measureText("0:00") + 8
        val end = capsule.right - mic.height()
        val count = ((end - start) / PITCH).toInt().coerceAtLeast(0)
        val heard = levels.toList().takeLast(count)
        for ((index, level) in heard.withIndex()) {
            val place = heard.size - 1 - index
            val x = end - place * PITCH - BAR / 2
            val height = max(BAR, level * 16f)
            val along = 1 - place / count.toFloat().coerceAtLeast(1f)
            fill.color = ColorUtils.setAlphaComponent(Color.WHITE, (255 * 0.9f * fade * along * (0.35f + 0.65f * level)).toInt())
            canvas.drawRoundRect(x - BAR / 2, capsule.centerY() - height / 2, x + BAR / 2, capsule.centerY() + height / 2, BAR / 2, BAR / 2, fill)
        }
        canvas.restore()
    }

    /** The waiting dictations' cards, the next in front with its length, the rest peeking out 6 to its right. */
    private fun drawCards(canvas: Canvas, frame: Frame, room: RectF) {
        val theme = frame.theme
        text.textSize = 13f
        text.typeface = Typeface.create(Typeface.DEFAULT, 500, false)
        val front = clock(max(saved.first().toInt(), 1))
        val width = text.measureText(front) + 20
        val height = min(room.height() - 12, 26f)
        val depth = min(saved.size, SHADES.size)
        val stack = width + (depth - 1) * PEEK
        val words = waitingFor.orEmpty()
        val small = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 15f; color = theme.candidate }
        val wordsWidth = min(small.measureText(words), room.width() * 0.6f)
        val left = room.left + (room.width() - stack - wordsWidth - 10) / 2
        for (place in depth - 1 downTo 0) {
            val shrink = 1 - 0.08f * place
            val w = width * shrink
            val h = height * shrink
            val right = left + width + place * PEEK
            fill.color = ColorUtils.blendARGB(theme.candidatePill, theme.candidateDivider, SHADES[place])
            canvas.drawRoundRect(right - w, room.centerY() - h / 2, right, room.centerY() + h / 2, h / 2, h / 2, fill)
        }
        text.color = theme.label
        canvas.drawText(front, left + 10, room.centerY() + text.textSize * 0.35f, text)
        canvas.drawText(words, left + stack + 10, room.centerY() + small.textSize * 0.35f, small)
    }

    /** SwiftUI's spring(duration: 0.45, bounce: 0.12), from 0 to 1, the curve the mic grows on. */
    private fun spring(t: Float): Float {
        val damping = 1 - 0.12
        val omega = 2 * PI / 0.45
        val damped = omega * sqrt(1 - damping * damping)
        val decay = exp(-damping * omega * t)
        return (1 - decay * (cos(damped * t) + damping * omega / damped * sin(damped * t))).toFloat()
    }

    companion object {
        private const val SETTLED = 0.7f
        private const val BAR = 2.5f
        private const val PITCH = 5f
        private const val PEEK = 6f
        private val SHADES = floatArrayOf(0f, 0.45f, 0.7f, 0.9f)

        fun clock(seconds: Int) = "%d:%02d".format(seconds / 60, seconds % 60)

        /** As iOS's `loudness`: -55 dBFS is silence and -15 full. */
        fun loudness(level: Float) = ((20 * log10(max(level, 1e-6f)) + 55) / 40).coerceIn(0f, 1f)
    }
}
