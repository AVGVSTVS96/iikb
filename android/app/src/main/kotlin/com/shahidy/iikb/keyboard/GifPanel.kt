package com.shahidy.iikb.keyboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.staggeredgrid.LazyHorizontalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.items
import androidx.compose.foundation.lazy.staggeredgrid.rememberLazyStaggeredGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.ImageLoader
import coil3.compose.AsyncImage
import coil3.gif.AnimatedImageDecoder
import kotlin.math.floor

/** The GIF feed, where the build has KLIPY's key. */
val LocalGifs = staticCompositionLocalOf<Gifs?> { null }

/** One image loader for the keyboard's process, which animates GIFs and WebPs. */
private var loader: ImageLoader? = null

@Composable
private fun loader(): ImageLoader {
    val context = LocalContext.current.applicationContext
    return loader ?: ImageLoader.Builder(context).components { add(AnimatedImageDecoder.Factory()) }.build()
        .also { loader = it }
}

/**
 * GIFs in rows of a fixed height, each at its own aspect ratio, scrolling sideways (docs/design.md, "GIF"): only the
 * tiles on screen are made, so only they animate. A tap copies the GIF; near the end the next page comes.
 */
@Composable
private fun GifRows(gifs: Gifs, rows: Int, height: Dp, query: String) {
    val look = LocalColors.current
    val actions = LocalActions.current
    val loader = loader()
    val shown = gifs.shown
    when {
        shown.state == "failed" -> return Empty("Couldn't reach KLIPY.")
        shown.state == "gifs" && shown.gifs.isEmpty() ->
            return Empty(if (gifs.recents) "GIFs you send show up here." else "No GIFs for “${query.trim()}”")
    }
    val grid = rememberLazyStaggeredGridState()
    val nearEnd by remember {
        derivedStateOf {
            val last = grid.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            last >= grid.layoutInfo.totalItemsCount - 10
        }
    }
    LaunchedEffect(nearEnd, shown.gifs.size) { if (nearEnd) gifs.more() }
    LazyHorizontalStaggeredGrid(
        StaggeredGridCells.Fixed(rows), Modifier.fillMaxWidth().height(height * rows + 6.dp * (rows - 1)), grid,
        horizontalItemSpacing = 6.dp, verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        items(shown.gifs, key = { it.id }) { gif ->
            val width = height * (gif.preview.width.toFloat() / gif.preview.height.coerceAtLeast(1))
            AsyncImage(
                gif.preview.url, gif.title, loader, contentScale = ContentScale.Crop,
                modifier = Modifier.width(width).height(height).clip(RoundedCornerShape(8.dp)).background(look.key)
                    .clickable { actions.copyGif(gif, query) },
            )
        }
    }
}

/** The GIFs' shelf in the menu: KLIPY's trending GIFs in one row. */
@Composable
fun GifShelf(height: Dp) {
    val gifs = LocalGifs.current ?: return
    GifRows(gifs, 1, height, "")
}

/**
 * The GIF panel: GIFs in rows of 65 over its search row, "Search KLIPY" (KLIPY's terms ask for that placeholder),
 * with the clock for your recent GIFs. Opened from the menu it fills the keys' place with as many rows as fit.
 */
@Composable
fun GifPanel(state: Overlay.State) {
    val look = LocalColors.current
    val actions = LocalActions.current
    val gifs = LocalGifs.current ?: return
    Column(
        Modifier.fillMaxSize().background(look.card)
            .padding(start = state.minX.dp, end = state.endInset.dp, top = 3.dp, bottom = if (state.keysUp) 0.dp else 11.dp),
    ) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val rows = floor((maxHeight.value + 6) / (ROW + 6)).toInt().coerceAtLeast(1)
            GifRows(gifs, rows, ROW.dp, state.query)
        }
        Spacer(Modifier.height(6.dp))
        SearchRow(
            state, { GifMark(look.secondary) }, "Search KLIPY", gifs.notice,
            trailing = {
                Box(
                    Modifier.padding(start = 4.dp).size(36.dp, state.field.dp).clickable {
                        gifs.recents = !gifs.recents
                        gifs.notice = null
                        actions.clearSearch()
                    },
                    contentAlignment = Alignment.Center,
                ) { Glyph("clock", if (gifs.recents) look.accent else look.secondary, 20.dp) }
            },
        )
    }
}

private const val ROW = 65f

/** The field's GIF glyph: the word in a rounded frame, as SF Symbols draws it. */
@Composable
private fun GifMark(color: androidx.compose.ui.graphics.Color) {
    Box(
        Modifier.size(22.dp, 16.dp).clip(RoundedCornerShape(4.dp))
            .background(color.copy(alpha = 0.18f)),
        contentAlignment = Alignment.Center,
    ) { Text("GIF", color = color, fontSize = 9.sp, fontWeight = FontWeight.Bold) }
}
