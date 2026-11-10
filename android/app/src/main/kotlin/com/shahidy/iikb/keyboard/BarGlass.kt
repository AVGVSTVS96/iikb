package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.core.graphics.ColorUtils
import com.shahidy.iikb.app.lift

/**
 * The bar's glass, iOS's `UIGlassEffect.bar`: iOS's regular glass tinted toward the label, 8% in light and 12% in dark,
 * so it stands off the keyboard's own glass, under More, the tools and the mic. Drawn on the keys' canvas as `app/Glass`
 * draws glass over a plain page, since the keyboard's glass under it has nothing to bend: its tint (in dark, `app/Glass`'s
 * lift of the keyboard's color), a lit rim on a hairline edge, and a soft shadow. `red` tints it toward record red, as
 * the mic's glass while it listens, its rim fading at the sides and its edge darkening as they do on iOS's red glass.
 */
class BarGlass {
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val shadow = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shape = Path()
    private val inner = RectF()

    fun draw(canvas: Canvas, box: RectF, theme: Theme, red: Float = 0f, opacity: Float = 1f) {
        val dark = Color.red(theme.label) > 128
        val radius = minOf(box.width(), box.height()) / 2
        shape.reset()
        shape.addRoundRect(box, radius, radius, Path.Direction.CW)

        canvas.save()
        canvas.clipOutPath(shape)
        shadow.setShadowLayer(SHADOW, 0f, SHADOW_Y, faded(Color.argb(if (dark) 77 else 8, 0, 0, 0), opacity))
        canvas.drawPath(shape, shadow)
        canvas.restore()

        val glass = if (dark) lift(ComposeColor(theme.card)).toArgb() else Color.argb(184, 255, 255, 255)
        val tinted = ColorUtils.compositeColors(ColorUtils.setAlphaComponent(theme.label, if (dark) 31 else 20), glass)
        fill.color = faded(ColorUtils.blendARGB(tinted, theme.record, red), opacity)
        canvas.drawPath(shape, fill)

        rim.strokeWidth = LIT
        val lit = faded(Color.argb(lerp(if (dark) 40 else 230, RED_LIT, red), 255, 255, 255), opacity)
        rim.color = lit
        if (red > 0f) {
            val sides = ColorUtils.setAlphaComponent(lit, lerp(Color.alpha(lit), 0, red))
            rim.shader = LinearGradient(
                0f, box.top, 0f, box.bottom, intArrayOf(lit, sides, sides, lit), floatArrayOf(0f, RED_FADE, 1 - RED_FADE, 1f), Shader.TileMode.CLAMP,
            )
        }
        inner.set(box)
        inner.inset(LIT / 2 + EDGE, LIT / 2 + EDGE)
        canvas.drawRoundRect(inner, radius - LIT / 2 - EDGE, radius - LIT / 2 - EDGE, rim)
        rim.shader = null
        rim.strokeWidth = EDGE
        rim.color = faded(if (dark) Color.argb(lerp(20, 0, red), 255, 255, 255) else Color.argb(lerp(41, RED_EDGE, red), 0, 0, 0), opacity)
        inner.set(box)
        inner.inset(EDGE / 2, EDGE / 2)
        canvas.drawRoundRect(inner, radius - EDGE / 2, radius - EDGE / 2, rim)
    }

    private fun lerp(from: Int, to: Int, by: Float) = (from + (to - from) * by.coerceIn(0f, 1f)).toInt()

    private fun faded(color: Int, opacity: Float) =
        if (opacity >= 1f) color else ColorUtils.setAlphaComponent(color, (Color.alpha(color) * opacity).toInt())

    private companion object {
        /** `app/Glass`'s shadow, its lit rim and its hairline edge, in dp. */
        const val SHADOW = 8f
        const val SHADOW_Y = 4f
        const val LIT = 0.75f
        const val EDGE = 0.5f
        /**
         * The lit rim's and light edge's alpha on red glass, measured on iOS's recording capsule, whose rim is lit only
         * along its top and bottom, fading out this far down and up its height, and whose edge is a darker red.
         */
        const val RED_LIT = 46
        const val RED_EDGE = 34
        const val RED_FADE = 0.3f
    }
}
