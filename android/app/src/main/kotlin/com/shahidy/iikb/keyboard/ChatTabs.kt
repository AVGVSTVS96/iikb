package com.shahidy.iikb.keyboard

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kyant.backdrop.Backdrop
import com.shahidy.iikb.Text
import com.shahidy.iikb.Tracking
import com.shahidy.iikb.app.glass
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlin.math.ceil
import kotlin.math.PI

/**
 * The chats as tabs in one capsule, as iOS's `ChatTabs` holds them: each chat's name, the open one on a platter that
 * slides to the tab you pick on a spring, the capsule hugging the tabs, or scrolling with its cut ends faded when they
 * don't fit. The capsule is iOS's Liquid Glass (`glass`) over `backdrop`, what's under it. Holding it lists every chat in
 * a menu, the open one checked. A chat with something you haven't seen has a dot after its name, in its padding, so
 * marking it moves nothing.
 */
@Composable
fun ChatTabs(
    names: List<String>, open: Int?, fresh: Set<Int>, backdrop: Backdrop, within: Dp, onPick: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val look = LocalColors.current
    val hold = LocalHold.current
    val density = LocalDensity.current.density
    val measurer = rememberTextMeasurer()
    val style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, letterSpacing = Tracking.at(15f))
    val texts = remember(names) { names.map { ceil(measurer.measure(it, style).size.width / density) } }
    val widths = texts.map { minOf(it + 2 * PADDING, MAX_TAB) }
    val starts = widths.runningFold(INSET) { x, width -> x + width }
    val content = starts.last() + INSET
    val width = minOf(content, within.value)
    var shown by remember { mutableStateOf(open) }
    LaunchedEffect(open) { shown = open }
    var pressed by remember { mutableStateOf<Int?>(null) }
    var bounds by remember { mutableStateOf(Rect.Zero) }
    val scroll = rememberScrollState()
    val platter = remember { Animatable(0f) }
    val platterWidth = remember { Animatable(0f) }
    var placed by remember { mutableStateOf<Int?>(null) }
    val target = shown?.takeIf { it in names.indices }
    LaunchedEffect(target, widths) {
        target ?: return@LaunchedEffect
        val x = starts[target]
        val slides = placed != null && placed != target
        placed = target
        val view = (width - 2 * INSET).coerceAtLeast(0f)
        val offset = minOf(maxOf(scroll.value / density, x + widths[target] + 40 - view), x - 40).coerceIn(0f, maxOf(content - width, 0f))
        if (slides) {
            val motion = spring<Float>(dampingRatio = 1 - BOUNCE, stiffness = (2 * PI / SPRING).let { (it * it).toFloat() })
            coroutineScope {
                launch { platter.animateTo(x, motion) }
                launch { platterWidth.animateTo(widths[target], motion) }
                launch { scroll.animateScrollTo((offset * density).toInt()) }
            }
        } else {
            platter.snapTo(x)
            platterWidth.snapTo(widths[target])
            scroll.scrollTo((offset * density).toInt())
        }
    }
    val pick = { index: Int ->
        if (index != shown) {
            shown = index
            onPick(index)
        }
    }
    Box(
        modifier.width(width.dp).height(HEIGHT.dp).onGloballyPositioned { bounds = it.boundsInWindow() }
            .glass(CircleShape, backdrop, look.dark).clip(CircleShape)
            .fadeCutEnds(scroll.value > 0, scroll.value < scroll.maxValue),
    ) {
        Box(
            Modifier.fillMaxHeight().horizontalScroll(scroll).width(content.dp)
                .pointerInput(names, starts) {
                    val at = { x: Float -> starts.indices.lastOrNull { starts[it] <= x / density }?.takeIf { it in names.indices } }
                    detectTapGestures(
                        onPress = { position ->
                            pressed = at(position.x)
                            tryAwaitRelease()
                            pressed = null
                        },
                        onTap = { position -> at(position.x)?.let(pick) },
                        onLongPress = {
                            if (names.size < 2) return@detectTapGestures
                            hold(
                                Held(
                                    bounds, Held.Shows.Menu, listed = true,
                                    actions = names.mapIndexed { index, name ->
                                        Held.Action(if (index == shown) "checkmark" else "", name) { pick(index) }
                                    },
                                ),
                            )
                        },
                    )
                },
        ) {
            if (target != null) {
                Box(
                    Modifier.offset(x = platter.value.dp, y = INSET.dp).size(platterWidth.value.dp, (HEIGHT - 2 * INSET).dp)
                        .background(if (look.dark) Color.White.copy(alpha = 0.14f) else Color.Black.copy(alpha = 0.08f), CircleShape),
                )
            }
            names.forEachIndexed { index, name ->
                Box(
                    Modifier.offset(x = starts[index].dp).width(widths[index].dp).fillMaxHeight()
                        .alpha(if (pressed == index) 0.55f else 1f),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Text(
                        name, color = if (index == shown) look.label else look.secondary, style = style, maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.offset(x = PADDING.dp).width((widths[index] - 2 * PADDING).dp),
                    )
                    if (index in fresh && index != shown) {
                        Box(
                            Modifier.offset(x = (PADDING + minOf(texts[index], widths[index] - 2 * PADDING) + 3).dp)
                                .size(DOT.dp).background(look.accent, CircleShape),
                        )
                    }
                }
            }
        }
    }
}

/**
 * A cut end of the row fades out over the capsule's straight side, clear under its round cap, so a tab cut there fades
 * rather than meeting the cap, as iOS's `ChatTabs.showFade`.
 */
private fun Modifier.fadeCutEnds(start: Boolean, end: Boolean) = if (!start && !end) this else
    graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen).drawWithContent {
        drawContent()
        val cap = size.height / 2 / size.width
        val fade = cap + FADE.dp.toPx() / size.width
        drawRect(
            Brush.horizontalGradient(
                *(if (start) arrayOf(0f to Color.Transparent, cap to Color.Transparent, fade to Color.Black) else arrayOf(0f to Color.Black)),
                *(if (end) arrayOf(1 - fade to Color.Black, 1 - cap to Color.Transparent, 1f to Color.Transparent) else arrayOf(1f to Color.Black)),
            ),
            blendMode = BlendMode.DstIn,
        )
    }

/** As iOS's `ChatTabs`, in points. */
const val TABS_HEIGHT = 32f
private const val HEIGHT = TABS_HEIGHT
private const val INSET = 2f
private const val PADDING = 12f
private const val DOT = 6f
private const val MAX_TAB = 220f
private const val FADE = 28f
/** The platter's spring, as `UIView.animate(springDuration: 0.4, bounce: 0.18)`. */
private const val SPRING = 0.4f
private const val BOUNCE = 0.18f
