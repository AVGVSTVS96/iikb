package com.shahidy.iikb.keyboard

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.Text
import com.shahidy.iikb.app.Hue
import com.shahidy.iikb.app.Hues
import com.shahidy.iikb.app.Palette
import com.shahidy.iikb.app.glass
import com.shahidy.iikb.app.glassSurface
import kotlin.math.floor

/**
 * The keyboard's menu, in the keys' place while the bar's More button is on (docs/design.md, "The menu"): a shelf for
 * each history, its name beside its newest items in one row, a tap typing one and the name opening its panel. Layouts
 * and iikb Settings stay on holding 123, where you type. Under the shelves, a scroll away with the Theme shelf's top
 * showing, the keyboard's theme and stop animation, picked in place.
 */
@Composable
fun Menu(state: Overlay.State) {
    val look = LocalColors.current
    val actions = LocalActions.current
    val gifs = LocalGifs.current
    val shelves = Shelf.entries.filter { (it != Shelf.GIFS || gifs != null) && (it != Shelf.CHATS || state.chats) }
    BoxWithConstraints(Modifier.fillMaxSize().fadeTop()) {
        val count = shelves.size
        val room = maxHeight.value - GAP - PEEK - (CHROME + GAP) * count
        val row = floor((room / count).coerceIn(COMPACT_ROW, TALLEST)).dp
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(start = state.minX.dp, end = (maxWidth.value - state.maxX).dp, top = GAP.dp),
            verticalArrangement = Arrangement.spacedBy(GAP.dp),
        ) {
            for (shelf in shelves) {
                Platter(shelf.title, shelf.glyph, shelf.hue, row, {
                    if (shelf == Shelf.CHATS) actions.openChat("") else actions.open(shelf.panel)
                }) {
                    when (shelf) {
                        Shelf.CLIPBOARD -> ClipShelf(row)
                        Shelf.TRANSCRIPTS -> TranscriptShelf()
                        Shelf.GIFS -> GifShelf(row)
                        Shelf.CHATS -> ChatShelf()
                    }
                }
            }
            Platter("Theme", "paintpalette.fill", Hues.teal, THEME_ROW.dp, actions::appearance, fitted = false) {
                ThemeRow(look.dark)
            }
            Platter("Stop Animation", "stop.fill", Hues.red, STOP_ROW.dp, actions::appearance, fitted = false) {
                StopRow()
            }
            Spacer(Modifier.height(0.dp))
        }
    }
}

/** Between shelves, and over the first. */
private const val GAP = 8f
/** A shelf's glass: its corners, the room around its row, and the column down its side for its name. */
private const val RADIUS = 22f
private const val INSET = 6f
private const val SIDE = 66f
private const val CHROME = 2 * INSET
/** The corners of a card on a shelf, concentric with the shelf's glass. */
val CARD_RADIUS = (RADIUS - INSET).dp
/** How much of the Theme shelf shows under the histories, enough for its tile to say there's more. */
private const val PEEK = 40f
private const val TALLEST = 104f
private const val THEME_ROW = 78f
private const val STOP_ROW = 62f
/** Where the screen is short (landscape), each shelf keeps a compact panel's one row, and the menu scrolls. */
private const val COMPACT_ROW = 46f

private fun Hue.of(dark: Boolean) = on(if (dark) Palette.dark else Palette.light)

/**
 * How iOS draws a system color inside its glass, as a shelf's tile is: vibrant, a white fill under a color matrix of
 * that color's (Core Animation's `vibrantColorMatrix`, read from the layer tree in the iOS 27 simulator) that takes the
 * glass behind it, so the tile comes out lighter than the color in dark and a shade deeper in light. Android can't put
 * the window's blur through a matrix, so it takes the shelf's glass over the keyboard's card. Each row is red, green,
 * blue: their weights on the glass's red, green and blue, then what's added.
 */
private class Vibrant(private val light: FloatArray, private val dark: FloatArray) {
    fun on(glass: Color, dark: Boolean): Color {
        val m = if (dark) this.dark else light
        fun row(i: Int) = (m[4 * i] * glass.red + m[4 * i + 1] * glass.green + m[4 * i + 2] * glass.blue + m[4 * i + 3]).coerceIn(0f, 1f)
        return Color(row(0), row(1), row(2))
    }

    companion object {
        private val all = mapOf(
            Hues.orange to Vibrant(
                floatArrayOf(.0784f, .1242f, .2342f, .5632f, 0f, .1748f, .1818f, .1963f, 0f, .0718f, .2139f, -.1288f),
                floatArrayOf(.3919f, .1705f, .056f, 1f, .2977f, .2646f, .056f, .5725f, .2977f, .1705f, .1502f, .1882f),
            ),
            Hues.pink to Vibrant(
                floatArrayOf(.0882f, .1812f, .1467f, .5838f, 0f, .1948f, .0863f, -.1047f, 0f, .1208f, .186f, .0265f),
                floatArrayOf(.4387f, .0714f, .1233f, 1f, .3308f, .1792f, .1233f, .2157f, .3308f, .0714f, .2311f, .3725f),
            ),
            Hues.purple to Vibrant(
                floatArrayOf(.1675f, .2402f, .036f, .3524f, .0399f, .2661f, .0238f, -.1416f, .0631f, .2512f, .1448f, .4193f),
                floatArrayOf(.3081f, .0477f, .2218f, .8588f, .2007f, .1551f, .2218f, .2039f, .2007f, .0477f, .3292f, .949f),
            ),
            Hues.indigo to Vibrant(
                floatArrayOf(.2744f, .1086f, .0064f, -.0091f, .0975f, .2784f, .0062f, -.0487f, .1434f, .1543f, .1825f, .4805f),
                floatArrayOf(.3f, .0981f, .2017f, .4275f, .0862f, .3118f, .2017f, .4863f, .0862f, .0981f, .4154f, 1f),
            ),
            Hues.teal to Vibrant(
                floatArrayOf(.1377f, .0324f, .0254f, -.1955f, .243f, .0572f, .0448f, .4197f, .25f, .0588f, .0461f, .4608f),
                floatArrayOf(0f, .284f, .3029f, 0f, 0f, .284f, .3029f, .8235f, 0f, .284f, .3029f, .8784f),
            ),
            Hues.red to Vibrant(
                floatArrayOf(.1098f, .153f, .15f, .5872f, 0f, .2031f, .0915f, -.075f, 0f, .0945f, .2024f, -.0617f),
                floatArrayOf(.4544f, .0841f, .0879f, 1f, .325f, .2135f, .0879f, .2588f, .325f, .0841f, .2174f, .2706f),
            ),
        )

        fun of(hue: Hue) = all.getValue(hue)
    }
}

/** The menu's shelves, each with the color Home's card for it has. */
enum class Shelf(val title: String, val panel: String, val glyph: String, val hue: Hue) {
    CLIPBOARD("Clipboard", "clipboard", "list.clipboard.fill", Hues.orange),
    TRANSCRIPTS("Transcripts", "transcripts", "text.bubble.fill", Hues.pink),
    GIFS("GIFs", "gif", "gif", Hues.purple),
    CHATS("Chats", "chats", "bubble.left.and.bubble.right.fill", Hues.indigo),
}

/** The shelves fade out under the bar as they scroll up, rather than being cut off. */
private fun Modifier.fadeTop() = graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
    .drawWithContent {
        drawContent()
        val fade = GAP.dp.toPx() / size.height
        drawRect(Brush.verticalGradient(0f to Color.Transparent, fade to Color.Black), blendMode = BlendMode.DstIn)
    }

/**
 * One shelf: its name down its side, then what it holds in one row, on a platter of iOS's Liquid Glass tinted faintly
 * with its tile's color. The name stays put as the row scrolls past it, and the row gets the shelf's whole height,
 * ending in rounded corners concentric with the platter's.
 */
@Composable
private fun Platter(
    title: String, glyph: String, hue: Hue, row: Dp, onOpen: () -> Unit, fitted: Boolean = true,
    content: @Composable () -> Unit,
) {
    val look = LocalColors.current
    val dark = look.dark
    val tint = hue.of(dark).copy(alpha = if (dark) 0.12f else 0.08f)
    Row(
        Modifier.fillMaxWidth().height(row + CHROME.dp)
            .glass(RoundedCornerShape(RADIUS.dp), dark = dark, color = tint, under = look.card)
            .padding(INSET.dp),
    ) {
        val tile = Vibrant.of(hue).on(glassSurface(look.card, dark, tint), dark)
        ShelfHead(title, glyph, fitted, tile, Modifier.width(SIDE.dp).fillMaxHeight(), onOpen)
        Box(Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(CARD_RADIUS))) { content() }
    }
}

/**
 * A shelf's name: its glyph on a colored tile, as Home's cards have, over the name, which drops out where the row is
 * too short for both; a tap opens the full panel, or for the look's shelves, iikb's Appearance settings. A panel's
 * glyph is its bar tool's filled one, `fitted` as the bar fits them; the look's are 15 semibold.
 */
@Composable
private fun ShelfHead(title: String, glyph: String, fitted: Boolean, color: Color, modifier: Modifier, onClick: () -> Unit) {
    val look = LocalColors.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val shrink by animateFloatAsState(
        if (pressed) 0.9f else 1f, spring(stiffness = if (pressed) 1540f else 440f), label = "shelf head",
    )
    Layout(
        {
            Box(
                Modifier.scale(shrink).background(color, RoundedCornerShape(9.dp)),
                contentAlignment = Alignment.Center,
            ) {
                if (fitted) PanelGlyph(glyph, Color.White, 16.dp)
                else Glyph(glyph, Color.White, Glyphs.square(15f).dp, weight = Glyphs.SEMIBOLD)
            }
            Text(
                title, color = look.label, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center, maxLines = 2, modifier = Modifier.alpha(if (pressed) 0.5f else 1f),
            )
        },
        modifier.clickable(interaction, indication = null, onClick = onClick),
    ) { (tile, name), constraints ->
        val side = 32.dp.roundToPx()
        val gap = 4.dp.roundToPx()
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val tiled = tile.measure(Constraints.fixed(side, side))
        val named = name.measure(Constraints(minWidth = width, maxWidth = width))
        val shows = height >= side + gap + named.height
        val top = maxOf((height - side - if (shows) gap + named.height else 0) / 2, 0)
        layout(width, height) {
            tiled.place((width - side) / 2, top)
            if (shows) named.place(0, top + side + gap)
        }
    }
}

/** A panel's filled glyph as the bar draws its tool, `side` the glyph's size. */
@Composable
private fun PanelGlyph(name: String, color: Color, side: Dp) {
    val paint = remember { Paint(Paint.ANTI_ALIAS_FLAG) }
    Canvas(Modifier.size(side)) {
        paint.color = color.toArgb()
        val canvas = drawContext.canvas.nativeCanvas
        val (x, y) = center
        canvas.save()
        canvas.scale(density, density, x, y)
        if (name == "gif") Glyphs.drawGif(canvas, x, y, side.value, paint, Typeface.DEFAULT)
        else Glyphs.drawFitted(canvas, name, x, y, side.value, paint)
        canvas.restore()
    }
}

/** GIF has no symbol: the word in a rounded frame, as iOS's `Tools.gifGlyph` draws it, `side` wide. */
@Composable
fun GifBadge(color: Color, side: Dp = 14.dp) {
    val unit = side / 18.4f
    Box(
        Modifier.size(side, unit * 14.4f).border(unit * 1.7f, color, RoundedCornerShape(unit * 4.45f)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "GIF", color = color, fontSize = (8 * unit.value).sp, fontWeight = FontWeight.Black,
            lineHeight = (8 * unit.value).sp, style = TextStyle(platformStyle = PlatformTextStyle(includeFontPadding = false)),
        )
    }
}

/**
 * A capsule or card in a shelf's fill (`shelfCard`), the pressed key fill while pressed, as iOS's cards and
 * badges are; a hold, where there is one, shows all of it, given where this sits in the window.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun Pressable(
    modifier: Modifier, radius: Dp, onClick: () -> Unit, onHold: ((Rect) -> Unit)? = null,
    fill: Color = LocalColors.current.shelfCard, pressedFill: Color = LocalColors.current.keyPressed,
    content: @Composable () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    var bounds by remember { mutableStateOf(Rect.Zero) }
    Box(
        modifier.onGloballyPositioned { bounds = it.boundsInWindow() }.heldAway(bounds)
            .background(if (pressed) pressedFill else fill, RoundedCornerShape(radius))
            .combinedClickable(interaction, indication = null, onClick = onClick, onLongClick = onHold?.let { { it(bounds) } }),
        contentAlignment = Alignment.CenterStart,
    ) { content() }
}

/** The space between cards or badges in a row. */
val ITEM_GAP = 6.dp

/** A card's fill on a shelf's glass, and on the keyboard's glass in a panel, letting the glass's tint show through. */
val Colors.shelfCard get() = if (dark) Color.White.copy(alpha = 0.1f) else Color.White.copy(alpha = 0.7f)
