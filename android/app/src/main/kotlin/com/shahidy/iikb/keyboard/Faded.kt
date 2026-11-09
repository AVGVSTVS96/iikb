package com.shahidy.iikb.keyboard

import androidx.compose.foundation.gestures.ScrollableState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import coil3.compose.SubcomposeAsyncImage

/** A row that scrolls sideways fades out at an end where it's cut, as iOS's `ButtonScrollView.fadesEnds` does. */
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

/**
 * A site's icon for its link badge, from the site itself: its `apple-touch-icon.png`, else its `favicon.ico`, else the
 * globe. Only the site's name leaves the phone, never the link, and the image loader keeps what it fetched.
 */
@Composable
fun SiteIcon(site: String?) {
    val globe = @Composable { Glyph("globe", Color(0xFF8E8E93), 14.dp) }
    if (site == null) return globe()
    SubcomposeAsyncImage(
        "https://$site/apple-touch-icon.png", site, imageLoader(), Modifier.fillMaxSize(),
        error = {
            SubcomposeAsyncImage(
                "https://$site/favicon.ico", site, imageLoader(), Modifier.fillMaxSize(),
                error = { Box(Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.Center) { globe() } },
            )
        },
    )
}
