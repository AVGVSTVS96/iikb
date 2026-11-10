package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import androidx.core.graphics.ColorUtils

/**
 * The bar's glass, iOS's `UIGlassEffect.bar`: iOS's regular glass tinted toward the label, 8% in light and 12% in dark,
 * so it stands off the keyboard's own glass, under More, the tools and the mic. Drawn on the keys' canvas as `app/Glass`
 * draws glass over a plain page, since the keyboard's glass under it has nothing to bend: its tint, a lit rim on a
 * hairline edge, and a soft shadow. `red` tints it toward record red, as the mic's glass while it listens.
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

        val glass = if (dark) Color.argb(166, 0x3B, 0x3B, 0x3D) else Color.argb(184, 255, 255, 255)
        val tinted = ColorUtils.compositeColors(ColorUtils.setAlphaComponent(theme.label, if (dark) 31 else 20), glass)
        fill.color = faded(ColorUtils.blendARGB(tinted, theme.record, red), opacity)
        canvas.drawPath(shape, fill)

        rim.strokeWidth = LIT
        rim.color = faded(Color.argb(if (dark) 40 else 230, 255, 255, 255), opacity)
        inner.set(box)
        inner.inset(LIT / 2 + EDGE, LIT / 2 + EDGE)
        canvas.drawRoundRect(inner, radius - LIT / 2 - EDGE, radius - LIT / 2 - EDGE, rim)
        rim.strokeWidth = EDGE
        rim.color = faded(if (dark) Color.argb(20, 255, 255, 255) else Color.argb(41, 0, 0, 0), opacity)
        inner.set(box)
        inner.inset(EDGE / 2, EDGE / 2)
        canvas.drawRoundRect(inner, radius - EDGE / 2, radius - EDGE / 2, rim)
    }

    private fun faded(color: Int, opacity: Float) =
        if (opacity >= 1f) color else ColorUtils.setAlphaComponent(color, (Color.alpha(color) * opacity).toInt())

    private companion object {
        /** `app/Glass`'s shadow, its lit rim and its hairline edge, in dp. */
        const val SHADOW = 8f
        const val SHADOW_Y = 4f
        const val LIT = 0.75f
        const val EDGE = 0.5f
    }
}
