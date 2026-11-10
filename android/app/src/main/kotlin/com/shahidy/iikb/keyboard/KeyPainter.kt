package com.shahidy.iikb.keyboard

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import androidx.core.graphics.ColorUtils

/** Paints keys as `KeyView` does on iOS: the theme's face, rim, keycap sides and glow, shadow, and labels. In dp. */
class KeyPainter {
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.LEFT }
    private val glyph = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val bounds = Rect()

    val letters: Typeface = Typeface.create("sans-serif", Typeface.NORMAL)
    val labels: Typeface = Typeface.create("sans-serif", Typeface.NORMAL)
    val bold: Typeface = Typeface.create("sans-serif", Typeface.BOLD)

    fun draw(
        canvas: Canvas, cap: Cap, look: Look, theme: Theme, pressed: Boolean, showsLabel: Boolean, flicked: Boolean,
    ) {
        val paint = theme.paint(cap)
        val left = cap.x.toFloat()
        val top = cap.y.toFloat()
        val right = cap.right.toFloat()
        val bottom = cap.bottom.toFloat()
        val radius = look.cornerRadius.toFloat()
        val height = bottom - top

        val drop = paint.drop
        if (drop != null && (!pressed || paint.keycap == null)) {
            fill.shader = null
            fill.color = Color.TRANSPARENT
            fill.setShadowLayer(drop.blur.toFloat().coerceAtLeast(0.01f), 0f, drop.y.toFloat(), drop.color)
            rect.set(left + drop.blur.toFloat(), top, right - drop.blur.toFloat(), bottom)
            fill.color = drop.color
            canvas.drawRoundRect(rect, radius, radius, fill)
            fill.clearShadowLayer()
        }

        val keycap = paint.keycap
        var face = RectF(left, top, right, bottom)
        var faceRadius = radius
        if (keycap != null) {
            rect.set(left, top, right, bottom)
            fill.shader = LinearGradient(
                0f, top, 0f, bottom, keycap.sides.toIntArray(), keycap.at.map { it.toFloat() }.toFloatArray(),
                Shader.TileMode.CLAMP,
            )
            canvas.drawRoundRect(rect, radius, radius, fill)
            val reach = height * 0.93f
            fill.shader = RadialGradient(
                (left + right) / 2, top, reach, intArrayOf(keycap.glow, ColorUtils.setAlphaComponent(keycap.glow, 0)),
                null, Shader.TileMode.CLAMP,
            )
            canvas.save()
            canvas.clipRect(left, top, right, bottom)
            canvas.drawRoundRect(rect, radius, radius, fill)
            canvas.restore()
            face = RectF(left + height * 0.097f, top + height * 0.093f, right - height * 0.097f, bottom - height * 0.15f)
            faceRadius = radius * 0.65f
        }
        val from = if (pressed) paint.pressedTop else paint.top
        val to = if (pressed) paint.pressedBottom else paint.bottom
        fill.shader = if (from == to) null else LinearGradient(0f, face.top, 0f, face.bottom, from, to, Shader.TileMode.CLAMP)
        fill.color = from
        canvas.drawRoundRect(face, faceRadius, faceRadius, fill)
        fill.shader = null

        paint.rim?.let { rim ->
            val width = rim.width.toFloat()
            line.strokeWidth = width
            line.shader = LinearGradient(
                0f, top, 0f, top + height * rim.fade.toFloat(), rim.color, ColorUtils.setAlphaComponent(rim.color, 0),
                Shader.TileMode.CLAMP,
            )
            rect.set(left + width / 2, top + width / 2, right - width / 2, bottom - width / 2)
            canvas.drawRoundRect(rect, radius - width / 2, radius - width / 2, line)
            line.shader = null
        }

        if (!showsLabel) return
        val alpha = if (cap.dimmed) 0.35f else 1f
        val label = paint.label
        val shadow = paint.labelShadow
        fun colored(color: Int) = ColorUtils.setAlphaComponent(color, (Color.alpha(color) * alpha).toInt())
        text.color = colored(label)
        glyph.color = colored(label)
        if (shadow != null) {
            text.setShadowLayer(0.01f, 0f, shadow.y.toFloat(), shadow.color)
        } else {
            text.clearShadowLayer()
        }

        val midX = (left + right) / 2
        val midY = (top + bottom) / 2
        val isLetter = cap.face == "letter"
        val numberRow = look.numberRowHeight > 0 && height < look.keyHeight - 0.5
        val isPair = cap.secondary != null && !cap.secondaryDimmed
        val shownLabel = if (flicked && cap.secondary != null && isLetter) cap.secondary else cap.label
        when (cap.face) {
            "letter", "text", "smallText" -> {
                text.typeface = if (isLetter) letters else labels
                text.textSize = when {
                    isPair -> look.pairSize.toFloat()
                    isLetter && numberRow -> look.numberRowLetterSize.toFloat()
                    isLetter -> look.letterSize.toFloat()
                    cap.face == "smallText" -> look.smallLabelSize.toFloat()
                    else -> look.labelSize.toFloat()
                }
                val width = text.measureText(shownLabel)
                val metrics = text.fontMetrics
                if (cap.secondary != null && !flicked) {
                    val baseline = if (isPair) bottom - height * look.pairBaselineRatio.toFloat()
                    else bottom - look.letterBaselineInset.toFloat()
                    canvas.drawText(shownLabel, midX - width / 2, baseline, text)
                } else if (cap.align == "center") {
                    val offset = if (isLetter) {
                        (if (numberRow) look.numberRowLetterOffset else look.letterOffset).toFloat()
                    } else {
                        -look.labelLift.toFloat()
                    }
                    val baseline = midY + offset - (metrics.ascent + metrics.descent) / 2
                    if (shownLabel == BULLET) {
                        text.getTextBounds(BULLET, 0, 1, bounds)
                        canvas.drawCircle(midX, baseline + bounds.exactCenterY(), text.textSize * BULLET_RADIUS, text)
                    } else {
                        canvas.drawText(shownLabel, midX - width / 2, baseline, text)
                    }
                } else {
                    val leading = cap.align == "leading"
                    val x = if (leading) left + look.textInset.toFloat() else right - look.textInset.toFloat() - width
                    canvas.drawText(shownLabel, x, bottom - look.textBaselineInset.toFloat(), text)
                }
            }

            "symbol" -> {
                val size = Glyphs.square(look.symbolSize.toFloat())
                if (cap.align == "center") {
                    Glyphs.draw(canvas, cap.label, midX, midY, size, glyph)
                } else {
                    val leading = cap.align == "leading"
                    val x = if (leading) left + look.edgeInsetX.toFloat() + size / 2 else right - look.edgeInsetX.toFloat() - size / 2
                    Glyphs.draw(canvas, cap.label, x, bottom - look.edgeInsetY.toFloat() - size / 2, size, glyph)
                }
            }
        }

        val secondary = cap.secondary
        if (secondary != null && !flicked) {
            text.typeface = labels
            text.textSize = if (isPair) look.pairSize.toFloat() else look.secondarySize.toFloat()
            text.color = if (cap.secondaryDimmed) colored(theme.secondaryLabel) else colored(label)
            text.getTextBounds("H", 0, 1, bounds)
            val capTop = if (isPair) top + height * look.pairCapTopRatio.toFloat() else top + look.secondaryCapTop.toFloat()
            val width = text.measureText(secondary)
            canvas.drawText(secondary, midX - width / 2, capTop + bounds.height(), text)
        }

        val corner = cap.corner
        if (corner != null) {
            text.typeface = bold
            text.textSize = look.cornerSize.toFloat()
            text.color = ColorUtils.setAlphaComponent(
                label, (Color.alpha(label) * Color.alpha(theme.secondaryLabel) / 255f * alpha).toInt(),
            )
            text.getTextBounds("I", 0, 1, bounds)
            val width = text.measureText(corner)
            canvas.drawText(corner, right - radius - width, top + radius + bounds.height(), text)
        }
        text.clearShadowLayer()
    }

    private companion object {
        /** Roboto's bullet is about half SF Compact's, which is 8 across at a 25.5 letter: drawn as SF's. */
        const val BULLET = "•"
        const val BULLET_RADIUS = 4f / 25.5f
    }
}
