package com.shahidy.iikb.keyboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import com.shahidy.iikb.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.ImageLoader
import coil3.compose.AsyncImage
import coil3.gif.AnimatedImageDecoder
import kotlin.math.round
import kotlin.math.roundToInt

/** The GIF feed, where the build has KLIPY's key. */
val LocalGifs = staticCompositionLocalOf<Gifs?> { null }

/** One image loader for the keyboard's process, which animates GIFs and WebPs. */
private var loader: ImageLoader? = null

@Composable
fun imageLoader(): ImageLoader {
    val context = LocalContext.current.applicationContext
    return loader ?: ImageLoader.Builder(context).components { add(AnimatedImageDecoder.Factory()) }.build()
        .also { loader = it }
}

/**
 * GIFs in rows of a fixed height, each at its own aspect ratio, scrolling sideways (docs/design.md, "GIF"): only the
 * tiles on screen are made, so only they animate. A tap copies the GIF; held, it plays bigger, a tap on it copying it;
 * moved once held, it lifts out to drop into the app, as iOS's tile has both. Near the end the next page comes.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun GifRows(gifs: Gifs, rows: Int, height: Dp, query: String) {
    val look = LocalColors.current
    val actions = LocalActions.current
    val hold = LocalHold.current
    val loader = imageLoader()
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
        StaggeredGridCells.Fixed(rows), Modifier.fillMaxWidth().height(height * rows + GIF_GAP.dp * (rows - 1)), grid,
        horizontalItemSpacing = GIF_GAP.dp, verticalArrangement = Arrangement.spacedBy(GIF_GAP.dp),
    ) {
        items(shown.gifs, key = { it.id }) { gif ->
            val width = (height * (gif.preview.width.toFloat() / gif.preview.height.coerceAtLeast(1)).coerceIn(0.5f, 2.5f)).value.roundToInt().dp
            var bounds by remember { mutableStateOf(Rect.Zero) }
            var held by remember { mutableStateOf(false) }
            AsyncImage(
                gif.preview.url, gif.title, loader, contentScale = ContentScale.Crop,
                modifier = Modifier.heldAway(bounds).width(width).height(height)
                    .clip(RoundedCornerShape(if (rows == 1) CARD_RADIUS else 8.dp)).background(look.shelfCard)
                    .onGloballyPositioned { bounds = it.boundsInWindow() }
                    .pointerInput(gif, query) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            held = false
                            while (true) {
                                val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                                if (!change.pressed) break
                                if (held && (change.position - down.position).getDistance() > viewConfiguration.touchSlop) {
                                    hold(null)
                                    actions.dragGif(gif, query)
                                    break
                                }
                            }
                        }
                    }
                    .combinedClickable(
                        onLongClick = {
                            held = true
                            val preview = Held.Shows.Image(gif.preview.url, gif.preview.width, gif.preview.height)
                            hold(Held(bounds, preview, tapped = { actions.copyGif(gif, query) }))
                        },
                    ) { actions.copyGif(gif, query) },
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
 * The GIF panel: GIFs in two rows (one where the bar is compact) stretched to the room over its search row, as iOS's
 * are, "Search KLIPY" (KLIPY's terms ask for that placeholder), with the clock in the field for your recent GIFs.
 */
@Composable
fun GifPanel(state: Overlay.State) {
    val look = LocalColors.current
    val actions = LocalActions.current
    val gifs = LocalGifs.current ?: return
    Column(
        Modifier.fillMaxSize()
            .padding(state.panelPadding),
    ) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val rows = if (state.compact) 1 else 2
            GifRows(gifs, rows, round((maxHeight.value - GIF_GAP * (rows - 1)) / rows).dp, state.query)
        }
        Spacer(Modifier.height(6.dp))
        SearchRow(
            state, { GifBadge(look.secondary, 18.4.dp) }, "Search KLIPY", gifs.notice,
            accessories = {
                Accessory("clock", gifs.recents) {
                    gifs.recents = !gifs.recents
                    gifs.notice = null
                    actions.clearSearch()
                }
            },
        )
    }
}

private const val GIF_GAP = 6f
