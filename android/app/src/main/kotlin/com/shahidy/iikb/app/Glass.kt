package com.shahidy.iikb.app

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.backdrops.emptyBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import com.kyant.backdrop.effects.vibrancy
import com.kyant.backdrop.highlight.Highlight
import com.kyant.backdrop.shadow.Shadow
import com.shahidy.iikb.app.design.isDark

/**
 * iOS 26's regular glass in `shape`: what's behind it blurred and bent toward its rim, lightened in light and darkened
 * in dark, with a lit rim on a hairline edge and a soft shadow, as `.glassEffect(.regular)` and the tab bar draw it.
 * Over a plain page, with nothing behind to bend, it's the rim, the tint and the shadow. Android draws the blur from 12
 * and the bend from 13; before, the tint alone stands in. The keyboard, outside the app's palette, says if it's `dark`.
 */
@Composable
fun Modifier.glass(shape: Shape, backdrop: Backdrop = emptyBackdrop(), dark: Boolean = palette().isDark): Modifier {
    val tint = if (dark) Color(0xFF3B3B3D).copy(alpha = 0.65f) else Color.White.copy(alpha = 0.4f)
    val edge = if (dark) Color.White.copy(alpha = 0.08f) else Color.Black.copy(alpha = 0.1f)
    return drawBackdrop(
        backdrop, { shape },
        effects = {
            vibrancy()
            blur(5.dp.toPx())
            lens(14.dp.toPx(), 24.dp.toPx())
        },
        highlight = { Highlight.Default.copy(alpha = if (dark) 0.5f else 1f) },
        shadow = {
            Shadow(radius = 16.dp, offset = DpOffset(0.dp, 4.dp), color = Color.Black.copy(alpha = if (dark) 0.3f else 0.08f))
        },
        onDrawSurface = { drawRect(tint) },
        onDrawFront = { drawOutline(shape.createOutline(size, layoutDirection, this), edge, style = Stroke(0.5.dp.toPx())) },
    )
}
