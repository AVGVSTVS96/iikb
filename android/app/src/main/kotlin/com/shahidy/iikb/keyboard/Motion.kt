package com.shahidy.iikb.keyboard

import android.animation.ValueAnimator
import android.os.Build
import android.os.SystemClock
import android.view.animation.PathInterpolator
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * How a value moves to where it's sent, from 0 to 1 over `seconds`: a spring as SwiftUI's `spring(duration:bounce:)`
 * springs, which overshoots with bounce, or one of UIKit's timed curves. The bar's motion runs on these so it moves
 * as iOS's KeyboardUI does (Motion.swift).
 */
class Curve private constructor(val seconds: Float, private val shape: (Float) -> Float) {
    fun progress(t: Float) = if (t >= seconds) 1f else if (t <= 0) 0f else shape(t)

    companion object {
        fun spring(duration: Float, bounce: Float = 0f): Curve {
            val omega = 2 * PI.toFloat() / duration
            if (bounce <= 0) return Curve(9.3f / omega) { t -> 1 - (1 + omega * t) * exp(-omega * t) }
            val damping = 1 - bounce
            val root = sqrt(1 - damping * damping)
            val damped = omega * root
            return Curve(ln(1000 / root) / (damping * omega)) { t ->
                1 - exp(-damping * omega * t) * (cos(damped * t) + damping * omega / damped * sin(damped * t))
            }
        }

        private fun timed(seconds: Float, x1: Float, y1: Float, x2: Float, y2: Float): Curve {
            val curve = PathInterpolator(x1, y1, x2, y2)
            return Curve(seconds) { t -> curve.getInterpolation(t / seconds) }
        }

        fun linear(seconds: Float) = Curve(seconds) { t -> t / seconds }
        fun easeIn(seconds: Float) = timed(seconds, 0.42f, 0f, 1f, 1f)
        fun easeOut(seconds: Float) = timed(seconds, 0f, 0f, 0.58f, 1f)
        fun easeInOut(seconds: Float) = timed(seconds, 0.42f, 0f, 0.58f, 1f)
        fun bezier(seconds: Float, x1: Float, y1: Float, x2: Float, y2: Float) = timed(seconds, x1, y1, x2, y2)

        /** Motion that follows your voice: a quick spring with no bounce. */
        val follow = spring(0.18f)
        /** A change of state, slower than following your voice. */
        val settle = spring(0.35f)

        /** The mic growing into the recording with a little give, or shrinking back without. */
        fun morph(growing: Boolean) = if (growing) spring(0.45f, 0.12f) else spring(0.35f)

        /** Whether Android's animations are on; with "Remove animations" iikb fades rather than moves, as iOS does with Reduce Motion. */
        val moves get() = ValueAnimator.areAnimatorsEnabled()

        /**
         * The clock motion runs on: uptime in ms, slowed by Android's animator duration scale (Developer options) as
         * Android's own animations are, and all at once with animations removed.
         */
        fun now(): Long {
            val scale = if (Build.VERSION.SDK_INT >= 33) ValueAnimator.getDurationScale() else 1f
            return (SystemClock.uptimeMillis() / max(scale, 0.001f)).toLong()
        }
    }
}

/** A value moving on a `Curve` from where it was to where it was last sent, read at a moment (`Curve.now`). */
class Moving(value: Float) {
    private var from = value
    var target = value
        private set
    private var start = 0L
    private var curve: Curve? = null

    fun at(now: Long): Float {
        val curve = curve ?: return target
        val t = (now - start) / 1000f
        if (t >= curve.seconds) {
            this.curve = null
            return target
        }
        return from + (target - from) * curve.progress(t)
    }

    /** From wherever it is now to `to`, after `delay` seconds, unless it's already headed there and not sent `again`. */
    fun go(to: Float, curve: Curve, delay: Float = 0f, now: Long = Curve.now(), again: Boolean = false) {
        if (to == target && !again) return
        from = at(now)
        target = to
        start = now + (delay * 1000).toLong()
        this.curve = curve
    }

    fun jump(to: Float) {
        from = to
        target = to
        curve = null
    }

    fun moving(now: Long): Boolean {
        at(now)
        return curve != null
    }
}
