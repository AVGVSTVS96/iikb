package com.shahidy.iikb.keyboard

import androidx.compose.foundation.gestures.ScrollableState
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp

/**
 * A row of buttons that scrolls sideways fades out at an end where it's cut, as iOS's `ButtonScrollView.fadesEnds` does
 * for the Theme and Stop Animation strips alone; the panels' cards and GIFs end in a hard cut.
 */
fun Modifier.fadeEnds(state: ScrollableState) = graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
    .drawWithContent {
        drawContent()
        val fade = 16.dp.toPx() / size.width
        val start = if (state.canScrollBackward) Color.Transparent else Color.Black
        val end = if (state.canScrollForward) Color.Transparent else Color.Black
        drawRect(
            Brush.horizontalGradient(0f to start, fade to Color.Black, 1 - fade to Color.Black, 1f to end),
            blendMode = BlendMode.DstIn,
        )
    }
