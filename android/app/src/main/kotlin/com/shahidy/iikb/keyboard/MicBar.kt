package com.shahidy.iikb.keyboard

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import androidx.core.graphics.ColorUtils
import com.shahidy.iikb.voice.Dictation
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * The bar's mic as docs/design.md ("The mic") draws it, as iOS's `SuggestionBar`, `MicButton` and `CancelButton` do.
 * While you talk it turns record red and grows on a spring into a capsule over the suggestions, with the recording
 * (`Waveform`) inside, a white stop where the mic was, a soft red halo that swells as you talk, and a cancel button
 * before it. Stopping plays the stop animation Settings › Appearance picks (`stopAnimation`): Squeeze (the bars rush
 * into the mic as it shrinks, a ring and a check while it writes), Drain (the red pours into the mic, which glows
 * while it writes) or Card (the recording folds into a card that lifts off the keyboard's top). Cancelling turns the
 * recording to dust (`Dust`). The dictations waiting for the model stack as cards in the recording's place
 * (`PendingStack`). In dp.
 */
class MicBar(private val view: View) {
    var stopAnimation = "squeeze"
    var phase = Dictation.Phase.OFF
        private set
    private var frame: Frame? = null
    /** How long the recording ran, for Card's card. */
    private var heard = 0.0
    private val waveform = Waveform()
    private val stack = PendingStack()

    /** The capsule's growth, which the cancel button rides out and back on. */
    private val growth = Moving(0f)
    /** The face's red, the stop and the halo. */
    private val red = Moving(0f)
    /** The mic's own glyph, shown while it's idle. */
    private val idle = Moving(1f)
    /** Squeeze's ring, while it writes. */
    private val ring = Moving(0f)
    /** The spinner Drain and Card show while it writes. */
    private val spinner = Moving(0f)
    private val voice = Moving(0f)
    private val micAlpha = Moving(1f)
    private val micScale = Moving(1f)
    private val micPress = Moving(0f)
    private val cancelPress = Moving(0f)
    private var pressed: String? = null
    /** The suggestions' opacity, which only a cancel fades back in. */
    private val under = Moving(1f)

    /** Whether the cancel button is out or riding back in. */
    private var cancelShown = false
    /** When Drain's glow started, while it writes. */
    private var glowing = 0L
    /** When Squeeze's check started, once a dictation is written; it holds the glyph back until it's gone. */
    private var checking = 0L
    /** Drain's red or Card's card, from the bar as it was when you stopped. */
    private var played: Played? = null
    /** The cancel button fading where it was as Drain or Card starts. */
    private var ghost: Ghost? = null
    private var dust: Dust? = null
    /** The recording just cancelled, gone to dust, so the mic comes back in its place instead of shrinking out of it. */
    private var dissolving = false

    /** The Record Key's own answer to a stop: it gives and springs back, or its red runs down out of it. */
    private var gave: Give? = null
    private var sank = 0L
    private val keyPress = Moving(0f)

    private class Played(val card: Boolean, val start: Long, val capsule: RectF, val circle: RectF?, val length: String)
    private class Give(val x: Float, val y: Float, val start: Long)
    private class Ghost(val x: Float, val y: Float, val scale: Float, val start: Long)

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        fontFeatureSettings = "tnum"
        textSize = 15f
        typeface = Typeface.create(Typeface.DEFAULT, 500, false)
    }
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val mask = Path()
    private val liquid = Path()
    private val oval = RectF()

    /** The capsule, the cards, a stop animation or the dust stand over the suggestions, which hide meanwhile. */
    val covers get() = phase != Dictation.Phase.OFF || growth.at(now()) > 0.01f || stack.covers

    /** How much of the suggestions shows, faded out under a cancelled recording until the mic is back. */
    val suggestions get() = under.at(now())

    fun show(phase: Dictation.Phase, recorded: Double, saved: List<Double>, waitingFor: String?) {
        val now = now()
        val old = this.phase
        val listening = phase == Dictation.Phase.LISTENING
        val grows = listening != (old == Dictation.Phase.LISTENING)
        val shown = frame?.let { if (inBar(it)) capsule(it, growth.at(now)) else recordingBox(it) }
        if (listening) {
            heard = recorded
            cancelShown = true
        }
        this.phase = phase
        face(old, now)
        waveform.show(phase, recorded, if (waitingFor == null) 0 else saved.size, now)
        stack.show(phase, saved, waitingFor, now)
        view.postInvalidateOnAnimation()
        if (!grows) return
        if (listening) endStop()
        val frame = frame
        if (frame == null || shown == null) {
            growth.jump(if (listening) 1f else 0f)
            cancelShown = listening
            return
        }
        if (dissolving && !listening) return reappear(now)
        if (!listening) {
            val bar = inBar(frame)
            when (stopAnimation) {
                "drain" -> if (bar) return drain(frame, shown, now) else waveform.sink(now)
                "card" -> return lift(frame, shown, now)
                else -> waveform.rush(if (bar) 1f else -1f, 0.3f, now)
            }
        }
        growth.go(if (listening) 1f else 0f, Curve.morph(listening), now = now)
    }

    /** A level the microphone heard, its root mean square: it enters the waveform and swells the halo. */
    fun hear(level: Float, recorded: Double) {
        if (phase != Dictation.Phase.LISTENING) return
        val now = now()
        heard = recorded
        waveform.hear(level, recorded, now)
        voice.go(loudness(level), SWELL, now = now)
        view.postInvalidateOnAnimation()
    }

    fun hitsCancel(frame: Frame, x: Float, y: Float): Boolean {
        if (phase != Dictation.Phase.LISTENING || !cancelShown || dissolving) return false
        val cancel = frame.toolbar.cancel
        return abs(cancel.midX - x) <= frame.toolbar.bar / 2 && y < frame.toolbar.height
    }

    /**
     * The cancelled recording, its cancel button and capsule, breaks into dust from the cancel button across, and the
     * mic comes back in its place once the dictation has stopped.
     */
    fun dissolve(frame: Frame, density: Float) {
        val now = now()
        val mic = micBox(frame)
        val capsule = if (mic != null) capsule(frame, growth.at(now)) else track(frame)
        val cancel = cancelPlace(frame, mic, now)
        val area = RectF(capsule).apply {
            union(cancel.first - cancel.third, cancel.second - cancel.third, cancel.first + cancel.third, cancel.second + cancel.third)
            inset(-2f, -2f)
        }
        val width = ceil(area.width() * density).toInt()
        val height = ceil(area.height() * density).toInt()
        if (width <= 0 || height <= 0) return
        val picture = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        Canvas(picture).apply {
            scale(density, density)
            translate(-area.left, -area.top)
            drawParts(this, frame, mic, capsule, now)
        }
        val direction = if (view.layoutDirection == View.LAYOUT_DIRECTION_RTL) -1f else 1f
        dust = Dust(picture, area, cancel.first, direction, density, now)
        dissolving = true
        cancelShown = false
        micAlpha.jump(0f)
        waveform.hide()
        view.postInvalidateOnAnimation()
    }

    /** Pressed, the mic gives by 3 dp whatever its width, and the cancel button's face by a tenth, as iOS's do. */
    private fun press(target: String?, now: Long) {
        if (target == pressed) return
        for ((name, moving) in listOf("mic" to micPress, "cancel" to cancelPress)) {
            val down = target == name
            if (down || pressed == name) moving.go(if (down) 1f else 0f, if (down) PRESS else RELEASE, now = now)
        }
        pressed = target
    }

    fun draw(canvas: Canvas, frame: Frame, pressedBar: String?) {
        this.frame = frame
        val mic = micBox(frame)
        val now = now()
        press(pressedBar, now)
        if (checking != 0L && now - checking >= CHECK_MS) {
            checking = 0
            if (phase == Dictation.Phase.OFF) idle.go(1f, Curve.settle, now = now)
        }
        val bar = frame.toolbar
        val recording = bar.recording
        val waits = mic?.let { it.left - 6 } ?: (recording.x + recording.width).toFloat()
        stack.draw(canvas, frame, RectF(recording.x.toFloat(), bar.top.toFloat(), waits, bar.height.toFloat()), now)
        val capsule = if (mic != null) capsule(frame, growth.at(now)) else track(frame)
        val played = played
        drawParts(canvas, frame, mic, capsule, now)
        if (played != null && !played.card) drawRipple(canvas, frame, played, now)
        if (played != null && played.card) drawCard(canvas, frame, played, now)
        ghost?.let { drawGhost(canvas, frame, it, now) }
        if (played != null && (now - played.start) / 1000f >= if (played.card) CARD_END else DRAIN_END) endStop()
        dust?.let { if (!it.draw(canvas, now)) dusted() }
        if (busy(now)) view.postInvalidateOnAnimation()
    }

    private fun busy(now: Long) = phase != Dictation.Phase.OFF || played != null || ghost != null || dust != null ||
        checking != 0L || gave != null || sank != 0L || waveform.busy(now) || stack.busy(now) ||
        listOf(growth, red, idle, ring, spinner, voice, micAlpha, micScale, micPress, cancelPress, keyPress, under).any { it.moving(now) }

    /** The cancel button, the mic and the recording in it, as they are at `now`. */
    private fun drawParts(canvas: Canvas, frame: Frame, mic: RectF?, capsule: RectF, now: Long) {
        drawCancel(canvas, frame, mic, now)
        if (mic == null) {
            val tint = frame.theme.label
            return waveform.draw(canvas, capsule, leading = 0f, trailing = 0f, mask = null, tint = tint, now = now)
        }
        drawMic(canvas, frame, mic, capsule, now)
        played?.let { if (!it.card) drawDrain(canvas, frame, it, now) }
        val clip = if (played?.card == false) liquid else mask.apply {
            reset()
            addRoundRect(capsule, capsule.height() / 2, capsule.height() / 2, Path.Direction.CW)
        }
        val span = frame.toolbar.recording.let { RectF(it.x.toFloat(), mic.top, mic.right, mic.bottom) }
        waveform.draw(canvas, span, leading = 12f, trailing = span.height(), mask = clip, tint = Color.WHITE, now = now)
    }

    /** The face's color, glyphs, ring and spinner for the phase, as iOS's `MicButton.show` sets them. */
    private fun face(old: Dictation.Phase, now: Long) {
        val listening = phase == Dictation.Phase.LISTENING
        val writing = phase == Dictation.Phase.WRITING
        val curve = if (listening != (old == Dictation.Phase.LISTENING)) Curve.morph(listening) else Curve.settle
        if (!listening) voice.jump(0f)
        if (old == Dictation.Phase.WRITING && phase == Dictation.Phase.OFF && stopAnimation == "squeeze") checking = now
        if (listening) {
            sank = 0L
            gave = null
        }
        if (old == Dictation.Phase.LISTENING && !listening && frame?.let(::inBar) == false) {
            when (stopAnimation) {
                "drain" -> sank = now
                "card" -> gave = Give(0.9f, 0.9f, now)
                else -> gave = Give(0.8f, 0.9f, now)
            }
        }
        glowing = if (writing && stopAnimation == "drain") glowing.takeIf { it != 0L } ?: now else 0L
        red.go(if (listening) 1f else 0f, curve, now = now)
        idle.go(if (phase == Dictation.Phase.OFF && checking == 0L) 1f else 0f, curve, now = now)
        ring.go(if (writing && stopAnimation == "squeeze") 1f else 0f, curve, now = now)
        spinner.go(if (writing && stopAnimation != "squeeze") 1f else 0f, curve, now = now)
    }

    /**
     * The gray circle with an `xmark`, tucked at half its size behind the mic until the capsule lets it out; beside the
     * Record Key, fading in and out in its place.
     */
    private fun drawCancel(canvas: Canvas, frame: Frame, mic: RectF?, now: Long) {
        if (!cancelShown) return
        if (phase != Dictation.Phase.LISTENING && !growth.moving(now)) {
            cancelShown = false
            return
        }
        val (x, y, radius) = cancelPlace(frame, mic, now)
        val opacity = if (mic == null) growth.at(now).coerceIn(0f, 1f) else 1f
        drawCancelFace(canvas, frame, x, y, radius * (1 - 0.1f * cancelPress.at(now)), opacity)
    }

    private fun drawCancelFace(canvas: Canvas, frame: Frame, x: Float, y: Float, radius: Float, opacity: Float) {
        val theme = frame.theme
        fill.color = ColorUtils.setAlphaComponent(theme.candidatePill, (Color.alpha(theme.candidatePill) * opacity).toInt())
        canvas.drawCircle(x, y, radius, fill)
        fill.color = ColorUtils.setAlphaComponent(theme.label, (Color.alpha(theme.label) * opacity).toInt())
        Glyphs.draw(canvas, "xmark", x, y, radius * 2 * 0.39f * 24 / 12, fill)
    }

    /** Where the cancel button is: its center and radius, riding the capsule's growth out of the mic, or in its place. */
    private fun cancelPlace(frame: Frame, mic: RectF?, now: Long): Triple<Float, Float, Float> {
        val cancel = frame.toolbar.cancel
        val out = growth.at(now)
        if (mic == null) return Triple(cancel.midX.toFloat(), cancel.midY.toFloat(), cancel.width.toFloat() / 2 * (0.9f + 0.1f * out))
        val x = mic.centerX() + (cancel.midX.toFloat() - mic.centerX()) * out
        val y = mic.centerY() + (cancel.midY.toFloat() - mic.centerY()) * out
        return Triple(x, y, cancel.width.toFloat() / 2 * (0.5f + 0.5f * out))
    }

    private fun drawMic(canvas: Canvas, frame: Frame, mic: RectF, capsule: RectF, now: Long) {
        val alpha = micAlpha.at(now).coerceIn(0f, 1f)
        if (alpha <= 0.001f) return
        val theme = frame.theme
        val reddened = red.at(now).coerceIn(0f, 1f)
        val radius = capsule.height() / 2
        val scale = micScale.at(now) * (1 - 6 / max(capsule.width(), 1f) * micPress.at(now))
        val layered = alpha < 0.999f
        if (layered) canvas.saveLayerAlpha(capsule.left - 20, capsule.top - 20, capsule.right + 20, capsule.bottom + 20, (255 * alpha).toInt())
        else canvas.save()
        canvas.scale(scale, scale, capsule.centerX(), capsule.centerY())
        if (reddened > 0.001f) {
            val out = (1 + 3 * voice.at(now)) * reddened
            fill.color = ColorUtils.setAlphaComponent(theme.record, (0.2f * 255 * reddened).toInt())
            canvas.drawRoundRect(capsule.left - out, capsule.top - out, capsule.right + out, capsule.bottom + out, radius + out, radius + out, fill)
        }
        fill.color = ColorUtils.blendARGB(theme.mic, theme.record, reddened)
        glow(theme, now)
        canvas.drawRoundRect(capsule, radius, radius, fill)
        fill.clearShadowLayer()

        val cx = mic.centerX()
        val cy = mic.centerY()
        val glyph = idle.at(now)
        if (glyph > 0.001f) {
            fill.color = ColorUtils.setAlphaComponent(theme.micGlyph, (Color.alpha(theme.micGlyph) * glyph.coerceIn(0f, 1f)).toInt())
            Glyphs.draw(canvas, "waveform", cx, cy, mic.width() * 0.6f * (0.5f + 0.5f * glyph), fill)
        }
        if (reddened > 0.001f) {
            fill.color = ColorUtils.setAlphaComponent(Color.WHITE, (255 * reddened).toInt())
            Glyphs.draw(canvas, "stop.fill", cx, cy, mic.width() * 0.74f * (0.5f + 0.5f * reddened), fill)
        }
        val ringing = ring.at(now).coerceIn(0f, 1f)
        if (ringing > 0.001f) {
            line.color = ColorUtils.setAlphaComponent(theme.micGlyph, (Color.alpha(theme.micGlyph) * ringing).toInt())
            line.strokeWidth = 2.5f
            val inset = mic.width() * 0.22f
            oval.set(mic.left + inset, mic.top + inset, mic.right - inset, mic.bottom - inset)
            canvas.drawArc(oval, (now % 900) / 900f * 360f, 108f, false, line)
        }
        val spinning = spinner.at(now).coerceIn(0f, 1f)
        if (spinning > 0.001f) drawSpinner(canvas, cx, cy, 20f * (0.5f + 0.25f * spinning), theme.micGlyph, spinning, now)
        if (checking != 0L) drawCheck(canvas, theme.micGlyph, cx, cy, mic.width() * 0.69f, (now - checking) / 1000f)
        canvas.restore()
    }

    /**
     * The Record Key in its place in the bottom row, as iOS's `MicButton` with a key's corners: the mic's face and
     * glyph, record red with a stop that swells as you talk while it listens, what the stop animation shows while it
     * writes, and its answer to the bar's stop (Squeeze squeezes it, Drain runs its red down out of it, Card lets it give).
     */
    fun drawKey(canvas: Canvas, cap: Cap, frame: Frame, pressed: Boolean) {
        val now = now()
        if (pressed != (keyPress.target == 1f)) keyPress.go(if (pressed) 1f else 0f, if (pressed) PRESS else RELEASE, now = now)
        val theme = frame.theme
        val key = RectF(cap.x.toFloat(), cap.y.toFloat(), cap.right.toFloat(), cap.bottom.toFloat())
        val corner = frame.look.cornerRadius.toFloat()
        val side = min(key.width(), key.height())
        val press = 1 - 6 / max(key.width(), 1f) * keyPress.at(now)
        var sx = press
        var sy = press
        gave?.let { give ->
            val t = (now - give.start) / 1000f
            if (t >= SQUEEZE.seconds + BACK.seconds) gave = null
            val squeezed = SQUEEZE.progress(t)
            val back = BACK.progress(t - SQUEEZE.seconds)
            sx *= 1 + (give.x - 1) * squeezed * (1 - back)
            sy *= 1 + (give.y - 1) * squeezed * (1 - back)
        }
        canvas.save()
        canvas.scale(sx, sy, key.centerX(), key.centerY())
        val reddened = red.at(now).coerceIn(0f, 1f)
        fill.color = ColorUtils.blendARGB(theme.mic, theme.record, reddened)
        glow(theme, now)
        canvas.drawRoundRect(key, corner, corner, fill)
        fill.clearShadowLayer()
        if (sank != 0L) drawSink(canvas, theme, key, corner, (now - sank) / 1000f)
        val cx = key.centerX()
        val cy = key.centerY()
        val glyph = idle.at(now)
        if (glyph > 0.001f) {
            fill.color = ColorUtils.setAlphaComponent(theme.micGlyph, (Color.alpha(theme.micGlyph) * glyph.coerceIn(0f, 1f)).toInt())
            Glyphs.draw(canvas, "waveform", cx, cy, min(side * 0.6f, 26f) * (0.5f + 0.5f * glyph), fill)
        }
        if (reddened > 0.001f) {
            fill.color = ColorUtils.setAlphaComponent(Color.WHITE, (255 * reddened).toInt())
            val swell = 1 + 0.4f * voice.at(now)
            Glyphs.draw(canvas, "stop.fill", cx, cy, min(side * 0.74f, 22f) * (0.5f + 0.5f * reddened) * swell, fill)
        }
        val ringing = ring.at(now).coerceIn(0f, 1f)
        if (ringing > 0.001f) {
            line.color = ColorUtils.setAlphaComponent(theme.micGlyph, (Color.alpha(theme.micGlyph) * ringing).toInt())
            line.strokeWidth = 2.5f
            val inset = side * 0.22f
            oval.set(cx - side / 2 + inset, cy - side / 2 + inset, cx + side / 2 - inset, cy + side / 2 - inset)
            canvas.drawArc(oval, (now % 900) / 900f * 360f, 108f, false, line)
        }
        val spinning = spinner.at(now).coerceIn(0f, 1f)
        if (spinning > 0.001f) drawSpinner(canvas, cx, cy, 20f * (0.5f + 0.25f * spinning), theme.micGlyph, spinning, now)
        if (checking != 0L) drawCheck(canvas, theme.micGlyph, cx, cy, min(side * 0.69f, 21f), (now - checking) / 1000f)
        canvas.restore()
        if (sank != 0L) drawKeyRipple(canvas, theme, key, corner, (now - sank) / 1000f - SINK)
        if (busy(now)) view.postInvalidateOnAnimation()
    }

    /** Drain's red in the Record Key, over its face and under its glyphs, running down out of it, its surface dipping in the middle as water over a drain. */
    private fun drawSink(canvas: Canvas, theme: Theme, key: RectF, corner: Float, t: Float) {
        if (t >= SINK) return
        val u = t / SINK
        val level = u * u
        val dip = key.height() * 0.16f
        val top = key.top - dip + (key.height() + dip) * level
        mask.reset()
        mask.addRoundRect(key, corner, corner, Path.Direction.CW)
        liquid.reset()
        liquid.moveTo(key.left, top)
        liquid.quadTo(key.centerX(), top + 2 * dip, key.right, top)
        liquid.lineTo(key.right, key.bottom + 2 * dip)
        liquid.lineTo(key.left, key.bottom + 2 * dip)
        liquid.close()
        canvas.save()
        canvas.clipPath(mask)
        fill.color = theme.record
        canvas.drawPath(liquid, fill)
        canvas.restore()
    }

    /** The ripple out from the Record Key's edge once its red has run out. */
    private fun drawKeyRipple(canvas: Canvas, theme: Theme, key: RectF, corner: Float, t: Float) {
        if (t < 0) return
        if (t >= RIPPLE.seconds) {
            sank = 0L
            return
        }
        val spread = RIPPLE.progress(t)
        line.color = ColorUtils.setAlphaComponent(theme.record, (0.6f * 255 * (1 - spread)).toInt())
        line.strokeWidth = 2f
        canvas.save()
        canvas.scale(1 + 12 / key.width() * spread, 1 + 12 / key.height() * spread, key.centerX(), key.centerY())
        canvas.drawRoundRect(key, corner, corner, line)
        canvas.restore()
    }

    /** Drain's mic glows softly in and out while it writes. */
    private fun glow(theme: Theme, now: Long) {
        if (glowing == 0L) return
        val cycle = (now - glowing) / 550f
        val half = cycle - floor(cycle)
        val pulse = PULSE.progress(if (floor(cycle).toInt() % 2 == 0) half else 1 - half)
        val glow = 0.25f + 0.65f * pulse
        fill.setShadowLayer(GLOW, 0f, 0f, ColorUtils.setAlphaComponent(theme.mic, (Color.alpha(theme.mic) * glow).toInt()))
    }

    /** iOS's medium activity indicator: eight spokes, the brightest stepping round once a second. */
    private fun drawSpinner(canvas: Canvas, cx: Float, cy: Float, side: Float, color: Int, opacity: Float, now: Long) {
        val head = ((now / 125) % 8).toInt()
        line.strokeWidth = side * 0.11f
        for (spoke in 0 until 8) {
            val behind = (head - spoke + 8) % 8
            val angle = (spoke / 8.0 * 2 * PI - PI / 2).toFloat()
            line.color = ColorUtils.setAlphaComponent(color, (Color.alpha(color) * opacity * (1 - 0.75f * behind / 7f)).toInt())
            canvas.drawLine(
                cx + cos(angle) * side * 0.24f, cy + sin(angle) * side * 0.24f,
                cx + cos(angle) * side * 0.46f, cy + sin(angle) * side * 0.46f, line,
            )
        }
    }

    /** Squeeze's check once a dictation is written: it springs in, holds, and shrinks away before the mic's glyph comes back. */
    private fun drawCheck(canvas: Canvas, color: Int, cx: Float, cy: Float, size: Float, t: Float) {
        val came = CHECK_IN.progress(min(t, 0.5f))
        val shown = if (t < 0.5f) came else came * (1 - CHECK_OUT.progress(t - 0.5f))
        fill.color = ColorUtils.setAlphaComponent(color, (Color.alpha(color) * shown.coerceIn(0f, 1f)).toInt())
        Glyphs.draw(canvas, "checkmark", cx, cy, size * (0.5f + 0.5f * shown), fill)
    }

    /** Drain: the red pours into the mic, its tail thinning, the bars riding in inside it, and fades as the mic comes back. */
    private fun drawDrain(canvas: Canvas, frame: Frame, played: Played, now: Long) {
        val t = (now - played.start) / 1000f
        val u = min(t / POUR, 1f)
        val along = if (u < 0.5f) 4 * u * u * u else 1 - (-2 * u + 2).pow(3) / 2
        val thinning = min(u / 0.65f, 1f).pow(3)
        val circle = played.circle ?: return
        liquid(played.capsule.left + (circle.left - played.capsule.left) * along, circle, 1 - 0.78f * thinning)
        val fading = if (t < POUR) 1f else 1 - LAND.progress(t - POUR)
        if (fading > 0) {
            fill.color = ColorUtils.setAlphaComponent(frame.theme.record, (255 * fading).toInt())
            canvas.drawPath(liquid, fill)
        }
    }

    /** Drain's ripple out from the mic's edge as the red lands. */
    private fun drawRipple(canvas: Canvas, frame: Frame, played: Played, now: Long) {
        val t = (now - played.start) / 1000f
        if (t < POUR) return
        val circle = played.circle ?: return
        val spread = RIPPLE.progress(t - POUR)
        line.color = ColorUtils.setAlphaComponent(frame.theme.record, (0.6f * 255 * (1 - spread)).toInt())
        line.strokeWidth = 2f
        canvas.save()
        canvas.scale(1 + 12 / circle.width() * spread, 1 + 12 / circle.height() * spread, circle.centerX(), circle.centerY())
        canvas.drawCircle(circle.centerX(), circle.centerY(), circle.width() / 2 - 1, line)
        canvas.restore()
    }

    /**
     * Drain's liquid, as iOS's `liquid` draws it: the capsule from its left end `left` to the mic's circle, its tail
     * thinned to `neck` of its height, as if pulled into the mic through a straw. One outline, the mic's round end its head.
     */
    private fun liquid(left: Float, mic: RectF, neck: Float) {
        val radius = mic.height() / 2
        val middle = mic.centerY()
        val head = mic.left
        val tail = max(head - left, 0f)
        val thin = radius * neck
        liquid.reset()
        liquid.moveTo(head + radius, mic.top)
        liquid.cubicTo(head - tail * 0.25f, mic.top, head - tail * 0.45f, middle - thin, left + thin, middle - thin)
        liquid.arcTo(left, middle - thin, left + 2 * thin, middle + thin, -90f, -180f, false)
        liquid.cubicTo(head - tail * 0.45f, middle + thin, head - tail * 0.25f, mic.bottom, head + radius, mic.bottom)
        liquid.arcTo(head, mic.top, head + 2 * radius, mic.bottom, 90f, -180f, false)
        liquid.close()
    }

    /**
     * Card: the recording folds into a card with its length and a little waveform, its time 12 in from its left end,
     * beside the mic or where the waveform began beside the Record Key; then it lifts off the bar as the mic comes back.
     * In the bar it stays the recording's red; beside the Record Key, whose red is the key's, it's a gray pill.
     */
    private fun drawCard(canvas: Canvas, frame: Frame, played: Played, now: Long) {
        val t = (now - played.start) / 1000f
        text.textSize = 15f
        text.textAlign = Paint.Align.LEFT
        val wave = 18f
        val width = text.measureText(played.length) + 6 + wave * 16 / 24 + 2 * 12
        val circle = played.circle
        val from = if (circle != null) played.capsule else RectF(played.capsule).apply { offset(-12f, 0f) }
        val rest = if (circle != null) circle.left - 8 - width else from.left
        val folded = FOLD.progress(t)
        val left = from.left + (rest - from.left) * folded
        val right = from.right + (rest + width - from.right) * folded
        val lifted = if (t < 0.5f) 0f else LIFT.progress(t - 0.5f)
        val card = RectF(left, from.top, right, from.bottom)
        canvas.save()
        canvas.translate(0f, -14 * lifted)
        canvas.scale(1 + 0.08f * lifted, 1 + 0.08f * lifted, card.centerX(), card.centerY())
        val opacity = (1 - lifted) * if (circle != null) 1f else folded.coerceIn(0f, 1f)
        val theme = frame.theme
        val face = if (circle != null) theme.record else theme.candidatePill
        val tint = if (circle != null) Color.WHITE else theme.label
        fill.color = ColorUtils.setAlphaComponent(face, (Color.alpha(face) * opacity).toInt())
        canvas.drawRoundRect(card, card.height() / 2, card.height() / 2, fill)
        text.color = ColorUtils.setAlphaComponent(tint, (0.9f * 255 * opacity).toInt())
        val x = card.left + 12
        canvas.drawText(played.length, x, card.centerY() + text.textSize * 0.35f, text)
        fill.color = ColorUtils.setAlphaComponent(tint, (0.85f * 255 * opacity).toInt())
        Glyphs.draw(canvas, "waveform", x + text.measureText(played.length) + 6 + wave * 16 / 24 / 2, card.centerY(), wave, fill)
        canvas.restore()
    }

    private fun drawGhost(canvas: Canvas, frame: Frame, ghost: Ghost, now: Long) {
        val t = (now - ghost.start) / 1000f
        if (t >= GHOST.seconds) {
            this.ghost = null
            return
        }
        val gone = GHOST.progress(t)
        val radius = frame.toolbar.cancel.width.toFloat() / 2 * ghost.scale * (1 - 0.4f * gone)
        drawCancelFace(canvas, frame, ghost.x, ghost.y, radius, 1 - gone)
    }

    /** Drain and Card start from the bar as it is once stopped, the mic hidden in its place until the recording has left. */
    private fun settleUnder(frame: Frame, now: Long) {
        endStop()
        val (x, y, radius) = cancelPlace(frame, micBox(frame), now)
        ghost = Ghost(x, y, radius / (frame.toolbar.cancel.width.toFloat() / 2), now)
        growth.jump(0f)
        cancelShown = false
        micAlpha.jump(0f)
    }

    private fun drain(frame: Frame, shown: RectF, now: Long) {
        settleUnder(frame, now)
        val circle = micBox(frame) ?: return
        played = Played(card = false, start = now, capsule = shown, circle = circle, length = "")
        liquid(shown.left, circle, 1f)
        waveform.rush(1f, POUR, now)
        micAlpha.go(1f, LAND, delay = POUR, now = now)
    }

    private fun lift(frame: Frame, shown: RectF, now: Long) {
        settleUnder(frame, now)
        val circle = micBox(frame)
        played = Played(card = true, start = now, capsule = shown, circle = circle, length = clock(heard.toInt()))
        if (circle == null) return
        micScale.jump(0.4f)
        micScale.go(1f, RETURN, delay = 0.25f, now = now)
        micAlpha.go(1f, RETURN, delay = 0.25f, now = now)
    }

    /** A stop animation's leftovers go, and the mic is whole again, whether it finished or a new recording cut it short. */
    private fun endStop() {
        played = null
        micAlpha.jump(1f)
        micScale.jump(1f)
    }

    /** After the dust, the mic grows back in its place and the suggestions fade in under it. */
    private fun reappear(now: Long) {
        dissolving = false
        growth.jump(0f)
        cancelShown = false
        under.jump(0f)
        under.go(1f, Curve.easeOut(0.3f), delay = 0.35f, now = now)
        micScale.jump(0.4f)
        micScale.go(1f, RETURN, delay = 0.3f, now = now)
        micAlpha.go(1f, RETURN, delay = 0.3f, now = now)
    }

    /** The dust has settled; if it still listens, the recording shows again. */
    private fun dusted() {
        dust = null
        if (!dissolving || phase != Dictation.Phase.LISTENING) return
        dissolving = false
        cancelShown = true
        micAlpha.jump(1f)
        waveform.reveal()
    }

    private fun micBox(frame: Frame) = frame.toolbar.mic?.let {
        RectF(it.x.toFloat(), it.y.toFloat(), (it.x + it.width).toFloat(), (it.y + it.height).toFloat())
    }

    private fun inBar(frame: Frame) = frame.toolbar.mic != null

    /** Beside the Record Key, the recording runs across the bar's row in the recording's span. */
    private fun track(frame: Frame) = frame.toolbar.let { bar ->
        RectF(bar.recording.x.toFloat(), bar.top.toFloat(), (bar.recording.x + bar.recording.width).toFloat(), bar.height.toFloat())
    }

    private fun recordingBox(frame: Frame) = frame.toolbar.recording.let {
        RectF(it.x.toFloat(), it.y.toFloat(), (it.x + it.width).toFloat(), (it.y + it.height).toFloat())
    }

    /** The mic grown `growth` of the way from its circle to the recording's left end. */
    private fun capsule(frame: Frame, growth: Float): RectF {
        val mic = micBox(frame) ?: return RectF()
        return RectF(mic.left + (frame.toolbar.recording.x.toFloat() - mic.left) * growth, mic.top, mic.right, mic.bottom)
    }

    private fun now() = Curve.now()

    companion object {
        private val SWELL = Curve.spring(0.32f)
        private val PRESS = Curve.spring(0.16f)
        private val RELEASE = Curve.spring(0.3f)
        private val RETURN = Curve.spring(0.45f, 0.25f)
        private val FOLD = Curve.spring(0.4f, 0.15f)
        private val LIFT = Curve.easeIn(0.28f)
        private val LAND = Curve.easeOut(0.22f)
        private val RIPPLE = Curve.easeOut(0.5f)
        private val GHOST = Curve.easeOut(0.2f)
        private val SQUEEZE = Curve.easeOut(0.12f)
        private val BACK = Curve.spring(0.5f, 0.45f)
        private const val SINK = 0.45f
        private val PULSE = Curve.easeInOut(1f)
        private val CHECK_IN = Curve.spring(0.3f, 0.3f)
        private val CHECK_OUT = Curve.easeIn(0.2f)
        private const val CHECK_MS = 700L
        private const val POUR = 0.5f
        private const val DRAIN_END = 1f
        private const val CARD_END = 0.78f
        private const val GLOW = 10f

        fun clock(seconds: Int) = "%d:%02d".format(seconds / 60, seconds % 60)

        /** As iOS's `loudness`: -55 dBFS is silence and -15 full. */
        fun loudness(level: Float) = ((20 * log10(max(level, 1e-6f)) + 55) / 40).coerceIn(0f, 1f)
    }
}
