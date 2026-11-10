package com.shahidy.iikb.keyboard

import android.graphics.BitmapFactory
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import com.shahidy.iikb.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.foundation.Canvas
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import java.io.File
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * A held clip, transcript or GIF, as iOS's context menu shows one (docs/design.md, "The menu"): all of it on a card
 * over the whole keyboard, dimmed behind it, with its actions in a menu under it.
 */
class Held(
    /** What was held, in the window's pixels: the card is centered on it where there's room, and it hides meanwhile. */
    val source: Rect,
    val shows: Shows,
    val actions: List<Action> = emptyList(),
    /** A tap on the card, a GIF's copy, as iOS's preview action; without one the tap puts it away. */
    val tapped: (() -> Unit)? = null,
    /** The actions a row each, as UIKit lists a menu's, not side by side at its medium element size. */
    val listed: Boolean = false,
) {
    sealed interface Shows {
        /** Nothing but the menu, under what was held, as UIKit's menu for a view held without a preview. */
        data object Menu : Shows

        /** What was held itself, as `layer` drew it, lifted a little larger with the menu under it, as UIKit lifts a view held without a preview. */
        data class Lifted(val layer: GraphicsLayer) : Shows

        /** Text in full; a link's `row` heads it with its site, as the clip's badge names it. */
        data class Text(val text: String, val link: Clips.Row? = null) : Shows

        /**
         * An image at its own aspect ratio, `width` by `height`: a file, or a GIF's address. A `photo` grows to the
         * keyboard's width less its sides and half its height, as iOS's chat photo preview.
         */
        data class Image(val model: Any, val width: Int, val height: Int, val photo: Boolean = false) : Shows {
            companion object {
                fun of(file: File): Image {
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(file.path, bounds)
                    return Image(file, bounds.outWidth.coerceAtLeast(1), bounds.outHeight.coerceAtLeast(1))
                }
            }
        }
    }

    class Action(val glyph: String, val title: String, val destructive: Boolean = false, val run: () -> Unit)
}

/**
 * What's held over the keyboard, from its top down to the system's bar under it (`bottom`), as UIKit fits a context
 * menu in a keyboard's window: the card where the held item was, moved up so its menu fits under it, or, where the
 * keyboard is too short for both, at the top, shortened so the whole menu shows. A tap anywhere else puts it away.
 */
@Composable
fun Peek(held: Held, bottom: Dp, behind: Behind?, close: () -> Unit) {
    val look = LocalColors.current
    val appear = remember(held) { Animatable(0f) }
    LaunchedEffect(held) { appear.animateTo(1f, tween(220)) }
    var origin by remember { mutableStateOf(Offset.Zero) }
    BoxWithConstraints(Modifier.fillMaxSize().onGloballyPositioned { origin = it.positionInWindow() }) {
        val density = androidx.compose.ui.platform.LocalDensity.current.density
        val source = held.source.translate(-origin.x, -origin.y).let {
            Rect(it.left / density, it.top / density, it.right / density, it.bottom / density)
        }
        val width = maxWidth.value
        val height = (maxHeight - bottom).value
        val menu = when {
            held.actions.isEmpty() -> 0f
            held.listed -> LIST_PAD * 2 + LIST_ROW * held.actions.size
            else -> MENU_ROW
        }
        Box(
            Modifier.fillMaxWidth().height(height.dp).graphicsLayer { alpha = appear.value }
                .background(Color.Black.copy(alpha = if (look.dark) 0.47f else 0.2f))
                .clickable(remember { MutableInteractionSource() }, indication = null, onClick = close),
        )
        Layout(
            content = {
                Card(held, close)
                if (menu > 0) if (held.listed) ListMenu(held.actions, behind, close) else Menu(held.actions, behind, close)
            },
            modifier = Modifier.fillMaxSize().graphicsLayer {
                alpha = appear.value
                val scale = 0.94f + 0.06f * appear.value
                scaleX = scale
                scaleY = scale
            },
        ) { measurables, constraints ->
            val px = { dp: Float -> (dp * density).roundToInt() }
            val sides = width - SIDE * 2
            val natural = min(measurables[0].maxIntrinsicHeight(px(sides)) / density, height / 2)
            // Where the card and its whole menu don't fit, the top margin tightens, then the gap, and then the card
            // gives way, its text scrolling, so the menu's every action stays in view.
            val short = if (menu == 0f) 0f else TOP + min(natural, MAX_TEXT) + GAP + menu - (height - MENU_FLOOR)
            val top = TOP - short.coerceIn(0f, TOP - TIGHT_TOP)
            val gap = GAP - (short - (TOP - TIGHT_TOP)).coerceIn(0f, GAP - TIGHT_GAP)
            val floor = if (menu > 0) height - MENU_FLOOR else height - BOTTOM
            val room = Rect(SIDE, top, width - SIDE, floor)
            val cardRoom = maxOf(CARD_FLOOR, room.height - if (menu > 0) gap + menu else 0f).let { if (menu > 0) min(it, height / 2) else it }
            val card = when (val shows = held.shows) {
                is Held.Shows.Image -> {
                    val tall = if (menu == 0f) height - IMAGE_MARGIN * 2 else cardRoom
                    val fits = min(min(if (shows.photo) width - PHOTO_SIDE * 2 else IMAGE_WIDTH, sides), tall * shows.width / shows.height)
                    measurables[0].measure(Constraints.fixedWidth(px(fits)))
                }
                is Held.Shows.Text -> measurables[0].measure(Constraints(maxWidth = px(sides), maxHeight = px(min(cardRoom, MAX_TEXT))))
                Held.Shows.Menu -> measurables[0].measure(Constraints.fixed(0, 0))
                is Held.Shows.Lifted -> measurables[0].measure(Constraints.fixed(px(source.width * LIFT), px(source.height * LIFT)))
            }
            val cardHeight = card.height / density
            val cardWidth = card.width / density
            val wanted = cardHeight + if (menu > 0) gap + menu else 0f
            // A preview alone (a GIF) is centered in the keyboard, as UIKit centers one it shrinks to fit.
            val alone = menu == 0f && held.shows is Held.Shows.Image
            val under = held.shows == Held.Shows.Menu
            val lifted = held.shows is Held.Shows.Lifted
            val cardTop = when {
                alone -> (height - cardHeight) / 2
                under -> source.bottom + MENU_UNDER - gap
                lifted -> (source.center.y - cardHeight / 2).coerceAtLeast(LIFTED_TOP)
                else -> (source.center.y - cardHeight / 2).coerceAtMost(room.bottom - wanted).coerceAtLeast(room.top)
            }
            val left = when {
                alone -> (width - cardWidth) / 2
                under -> source.left.coerceIn(room.left, room.right - MENU_WIDTH)
                lifted -> source.center.x - cardWidth / 2
                else -> (source.center.x - cardWidth / 2).coerceIn(room.left, room.right - cardWidth)
            }
            val menuTop = cardTop + cardHeight + gap
            val placed = measurables.getOrNull(1)?.measure(
                Constraints.fixed(px(MENU_WIDTH), px(min(menu, room.bottom - menuTop).coerceAtLeast(0f))),
            )
            val menuLeft = when {
                under || lifted -> left.coerceIn(room.left, room.right - MENU_WIDTH)
                left <= room.left -> room.left
                left + cardWidth >= room.right -> room.right - MENU_WIDTH
                else -> (left + cardWidth / 2 - MENU_WIDTH / 2).coerceIn(room.left, room.right - MENU_WIDTH)
            }
            layout(constraints.maxWidth, constraints.maxHeight) {
                card.place(px(left), px(cardTop))
                placed?.place(px(menuLeft), px(menuTop))
            }
        }
    }
}

/** Hides what's held while its card shows, as UIKit lifts a context menu's view out of its place. */
@Composable
fun Modifier.heldAway(bounds: Rect): Modifier {
    val held = LocalHeld.current
    return graphicsLayer { alpha = if (held?.source == bounds) 0f else 1f }
}

/** All of what's held: text on the card iOS's previews use, scrolling where it's long, or the image, a GIF playing. */
@Composable
private fun Card(held: Held, close: () -> Unit) {
    val look = LocalColors.current
    val shape = RoundedCornerShape(CORNER.dp)
    val tap = Modifier.clickable(remember { MutableInteractionSource() }, indication = null) {
        held.tapped?.invoke()
        close()
    }
    when (val shows = held.shows) {
        is Held.Shows.Text -> Box(
            Modifier.widthIn(max = TEXT_WIDTH.dp).fillMaxWidth().clip(shape).background(look.preview).then(tap)
                .verticalScroll(rememberScrollState()).padding(horizontal = 17.dp, vertical = 14.dp),
        ) {
            val link = shows.link
            if (link != null) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(19.dp)) { SiteIcon(link.site, look.previewSecondary) }
                        Spacer(Modifier.width(8.5.dp))
                        Text(link.site ?: "", color = look.label, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        shows.text.trim().replace("/", "/\u200B"), color = look.previewSecondary,
                        style = TextStyle(fontSize = 15.sp, lineHeight = 18.sp, lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None)),
                        pushOut = false,
                    )
                }
            } else {
                Text(shows.text, color = look.label, fontSize = 17.sp, lineHeight = 20.sp, pushOut = false)
            }
        }
        Held.Shows.Menu -> Box(Modifier)
        is Held.Shows.Lifted -> Canvas(
            Modifier.shadow(24.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f)),
        ) { scale(LIFT, LIFT, Offset.Zero) { drawLayer(shows.layer) } }
        is Held.Shows.Image -> {
            // UIKit previews a photo with rounder corners on a soft shadow.
            val corners = if (shows.photo) RoundedCornerShape(PHOTO_CORNER.dp) else shape
            AsyncImage(
                shows.model, "Image", imageLoader(), contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxWidth().aspectRatio(shows.width.toFloat() / shows.height)
                    .then(if (shows.photo) Modifier.shadow(24.dp, corners, ambientColor = Color.Black.copy(alpha = 0.2f), spotColor = Color.Black.copy(alpha = 0.2f)) else Modifier)
                    .clip(corners).background(Color.Black).then(tap),
            )
        }
    }
}

/**
 * The held item's actions, iOS's menu at its medium element size: one row of them, each its glyph over its title,
 * Delete in red, on glass over the dimmed keys.
 */
@Composable
private fun Menu(actions: List<Held.Action>, behind: Behind?, close: () -> Unit) {
    val look = LocalColors.current
    val shape = RoundedCornerShape(MENU_CORNER.dp)
    Row(
        Modifier.shadow(24.dp, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f))
            .frosted(behind, shape).padding(MENU_PAD.dp),
    ) {
        for (action in actions) {
            val interaction = remember { MutableInteractionSource() }
            val pressed by interaction.collectIsPressedAsState()
            val tint = if (action.destructive) look.destructive else look.label
            Column(
                Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(MENU_CELL_CORNER.dp))
                    .background(if (pressed) look.label.copy(alpha = 0.08f) else Color.Transparent)
                    .clickable(interaction, indication = null) {
                        close()
                        action.run()
                    },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Glyph(action.glyph, tint, Glyphs.square(MENU_GLYPH).dp)
                Spacer(Modifier.height(MENU_TITLE_GAP.dp))
                Text(action.title, color = tint, fontSize = MENU_TITLE.sp, fontWeight = FontWeight.Medium, maxLines = 1)
            }
        }
    }
}

/**
 * The held item's actions as UIKit lists a menu's: a glyph and a title a row, or, where the only glyph is a pick's
 * checkmark, the titles in nearer with the checkmark small before the one picked (measured on iOS's held chat tabs).
 */
@Composable
private fun ListMenu(actions: List<Held.Action>, behind: Behind?, close: () -> Unit) {
    val look = LocalColors.current
    // UIKit rounds a one-row menu into a capsule.
    val shape = if (actions.size == 1) CircleShape else RoundedCornerShape(LIST_CORNER.dp)
    val checks = actions.all { it.glyph == "" || it.glyph == "checkmark" }
    Column(
        Modifier.shadow(24.dp, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f))
            .frosted(behind, shape).padding(vertical = LIST_PAD.dp),
    ) {
        for (action in actions) {
            val interaction = remember { MutableInteractionSource() }
            val pressed by interaction.collectIsPressedAsState()
            val tint = if (action.destructive) look.destructive else look.label
            Row(
                Modifier.fillMaxWidth().height(LIST_ROW.dp)
                    .background(if (pressed) look.label.copy(alpha = 0.08f) else Color.Transparent)
                    .clickable(interaction, indication = null) {
                        close()
                        action.run()
                    },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (checks) {
                    Box(Modifier.padding(start = 20.dp).width(16.dp), contentAlignment = Alignment.Center) {
                        Glyph(action.glyph, tint, Glyphs.square(13f).dp, weight = Glyphs.SEMIBOLD)
                    }
                    Spacer(Modifier.width(7.dp))
                } else {
                    Box(Modifier.padding(start = 26.dp).width(26.dp), contentAlignment = Alignment.Center) {
                        Glyph(action.glyph, tint, Glyphs.square(17f).dp)
                    }
                    Spacer(Modifier.width(11.dp))
                }
                Text(action.title, color = tint, fontSize = 17.sp)
            }
        }
    }
}

/**
 * The keyboard as it showed when something was held (`Overlay.capture`): `image` is `scale` times smaller than the window,
 * its top left at `origin` in the window.
 */
class Behind(val image: ImageBitmap, val origin: Offset, val scale: Float)

/** How far down from the top, and up from the bottom, the lit rim fades out, as a share of the glass's height. */
private fun DrawScope.litFade() = (LIT_FADE.dp.toPx() / size.height).coerceAtMost(0.5f)

/**
 * iOS's menu glass in `shape`: the dimmed keyboard under it blurred to a frost, which the glass's tint lets through
 * faintly, a dark hairline just outside its edge, and a rim lit from above and below that fades into the glass, so the
 * sides show only the hairline. Until the keyboard's still comes (or where Android can't blur, before 12), the tint
 * alone, opaque, so the rows under it never show sharp through its titles.
 */
@Composable
private fun Modifier.frosted(behind: Behind?, shape: Shape): Modifier {
    val look = LocalColors.current
    var at by remember { mutableStateOf(Offset.Zero) }
    val frost = rememberGraphicsLayer()
    return onGloballyPositioned { at = it.positionInWindow() }.drawBehind {
        val faint = look.glassEdge.copy(alpha = look.glassEdge.alpha * look.litEdge)
        val edge = Brush.verticalGradient(0f to faint, litFade() to look.glassEdge, 1 - litFade() to look.glassEdge, 1f to faint)
        drawOutline(shape.createOutline(size, layoutDirection, this), edge, style = Stroke(EDGE.dp.toPx() * 2))
    }.clip(shape).drawWithContent {
        drawRect(look.glass)
        if (behind != null) {
            frost.renderEffect = BlurEffect(FROST.dp.toPx(), FROST.dp.toPx(), TileMode.Clamp)
            frost.alpha = if (look.dark) 0.45f else 0.3f
            frost.record {
                withTransform({
                    translate(behind.origin.x - at.x, behind.origin.y - at.y)
                    scale(behind.scale, behind.scale, Offset.Zero)
                }) { drawImage(behind.image) }
                drawRect(Color.Black.copy(alpha = if (look.dark) 0.47f else 0.2f))
            }
            drawLayer(frost)
            drawRect(look.glass.copy(alpha = 0.35f))
        }
        drawContent()
        val outline = shape.createOutline(size, layoutDirection, this)
        val lit = Brush.verticalGradient(0f to Color.White, litFade() to Color.Transparent, 1 - litFade() to Color.Transparent, 1f to Color.White)
        for ((width, alpha) in look.litRim) drawOutline(outline, lit, alpha, Stroke(width.dp.toPx() * 2))
    }
}

/** iOS's `secondaryLabel`, a held link's address. */
private val Colors.previewSecondary get() = if (dark) Color(0x99EBEBF5) else Color(0x993C3C43)
/** iOS's preview card: secondarySystemBackground. */
private val Colors.preview get() = if (dark) Color(0xFF2C2C2E) else Color(0xFFF2F2F7)
/** iOS's menu glass as it reads over the dimmed keyboard, measured on its shots: the tint `frosted` lays over the frost. */
private val Colors.glass get() = if (dark) Color(0xFF323233) else Color(0xFFE8E8EB)
private val Colors.glassEdge get() = if (dark) Color(0xED000000) else Color(0x80000000)
/** How much of the hairline shows where the rim is lit. */
private val Colors.litEdge get() = if (dark) 0f else 0.4f
/** The lit rim inside its edge, as bands in from it, each a width in points and a white's alpha, laid one over the next. */
private val Colors.litRim get() = if (dark) listOf(0.35f to 0.12f, 0.7f to 0.12f, 1.3f to 0.12f) else listOf(0.35f to 0.7f, 0.7f to 0.375f, 1.3f to 0.2f)
/** The menu's red, as iOS's menu draws a destructive action over its glass, measured on its shots. */
private val Colors.destructive get() = if (dark) Color(0xFFFF6164) else Color(0xFFF12E33)

/** Measured on iOS's shots of a held clip, transcript and GIF (iPhone 17), in points. */
private const val SIDE = 16f
private const val TOP = 16f
private const val BOTTOM = 16f
/** The menu runs nearer the bottom than a card alone. */
private const val MENU_FLOOR = 2f
private const val GAP = 16.5f
private const val CORNER = 22f
private const val PHOTO_CORNER = 35f
private const val TEXT_WIDTH = 340f
private const val MAX_TEXT = 480f
private const val IMAGE_WIDTH = 300f
private const val PHOTO_SIDE = 16f
/** Above and below a GIF's preview, which grows to the keyboard's height less these. */
private const val IMAGE_MARGIN = 15f
/** Where the card and its menu don't fit, the top margin and gap tighten down to these, and the card keeps at least this. */
private const val TIGHT_TOP = 12f
private const val TIGHT_GAP = 10f
private const val CARD_FLOOR = 60f
private const val MENU_WIDTH = 250f
private const val MENU_ROW = 77f
private const val MENU_PAD = 4f
private const val MENU_CELL_CORNER = 20f
private const val MENU_GLYPH = 17f
private const val MENU_TITLE = 12f
private const val MENU_TITLE_GAP = 6f
private const val MENU_CORNER = 37f
private const val LIST_ROW = 42f
/** A view held without a preview lifts this much larger, its top at least this far down the keyboard (iOS's held chat tabs). */
private const val LIFT = 1.14f
private const val LIFTED_TOP = 13f
/** A menu alone sits this far under what was held. */
private const val MENU_UNDER = 8f
private const val LIST_PAD = 10f
private const val LIST_CORNER = 26f
/** How far the menu's glass blurs what's under it. */
private const val FROST = 4f
private const val EDGE = 0.5f
private const val LIT_FADE = 10f
