package com.shahidy.iikb.app

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.addOutline
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.isSpecified
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.backdrops.emptyBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import com.kyant.backdrop.effects.vibrancy
import com.kyant.backdrop.highlight.Highlight
import com.kyant.backdrop.highlight.HighlightStyle
import com.kyant.backdrop.shadow.Shadow
import com.shahidy.iikb.app.design.isDark

/**
 * iOS 26's regular glass in `shape`: what's behind it blurred and bent toward its rim, a rim lit from above and below,
 * and a soft shadow, as `.glassEffect(.regular)` and the tab bar draw it. In light it washes what's behind about 40%
 * toward white inside a gray hairline; in dark it lifts what's behind by a gray of 32 rather than covering it, so it
 * reads 0x20 on a black page and lighter on the keyboard's glass, as iOS's shots measure it. Over a plain page, with
 * nothing behind to bend, it's the rim, the tint and the shadow. Android draws the blur from 12 and the bend from 13;
 * before, the tint alone stands in. The keyboard, outside the app's palette, says if it's `dark` and gives the color
 * `under` it: what's behind there is another window's (its own glass), which a layer here can't add to, so in dark it
 * lifts by a white that brings `under` up by the same gray (`lift`). `color` tints it further, as
 * `UIGlassEffect.tintColor` does.
 */
@Composable
fun Modifier.glass(
    shape: Shape, backdrop: Backdrop = emptyBackdrop(), dark: Boolean = palette().isDark, color: Color = Color.Transparent,
    under: Color = Color.Unspecified,
): Modifier {
    val hairline = this.drawWithContent {
        drawContent()
        if (dark) return@drawWithContent
        val sides = Color.Black.copy(alpha = 0.3f)
        val lit = Color.Black.copy(alpha = 0.1f)
        val fade = (LIT_FADE.dp.toPx() / size.height).coerceAtMost(0.5f)
        val edge = Brush.verticalGradient(0f to lit, fade to sides, 1 - fade to sides, 1f to lit)
        val outline = shape.createOutline(size, layoutDirection, this)
        clipPath(Path().apply { addOutline(outline) }, ClipOp.Difference) { drawOutline(outline, edge, style = Stroke(EDGE.dp.toPx() * 2)) }
    }
    return hairline.drawBackdrop(
        backdrop, { shape },
        effects = {
            vibrancy()
            blur(2.dp.toPx())
            lens(14.dp.toPx(), 24.dp.toPx())
        },
        highlight = { Highlight.Default.copy(alpha = if (dark) 0.5f else 1f, style = HighlightStyle.Default(angle = 90f)) },
        shadow = {
            Shadow(radius = 16.dp, offset = DpOffset(0.dp, 4.dp), color = Color.Black.copy(alpha = if (dark) 0.3f else 0.03f))
        },
        onDrawSurface = {
            when {
                !dark -> drawRect(WASH)
                under.isSpecified -> drawRect(lift(under))
                else -> drawRect(LIFT, blendMode = BlendMode.Plus)
            }
            drawRect(color)
        },
    )
}

/** What `glass` reads as over an opaque `under`, before its blur and rim: its tint, then `color`. */
fun glassSurface(under: Color, dark: Boolean, color: Color = Color.Transparent): Color {
    val tinted = if (dark) {
        Color((under.red + LIFT.red).coerceAtMost(1f), (under.green + LIFT.green).coerceAtMost(1f), (under.blue + LIFT.blue).coerceAtMost(1f))
    } else {
        WASH.compositeOver(under)
    }
    return color.compositeOver(tinted)
}

/** The white that, laid over an opaque `under`, reads as `under` lifted by `LIFT`, as dark glass does. */
fun lift(under: Color): Color = Color.White.copy(alpha = (LIFT.red / (1 - maxOf(under.red, under.green, under.blue))).coerceIn(0f, 1f))

private val LIFT = Color(0xFF202020)
private val WASH = Color.White.copy(alpha = 0.4f)

/** The hairline's width outside the edge, and how far down from the top and up from the bottom it fades where lit. */
private const val EDGE = 0.5f
private const val LIT_FADE = 10f
