package com.shahidy.iikb.keyboard

import android.content.Context
import android.util.Patterns
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.network.NetworkHeaders
import coil3.network.httpHeaders
import coil3.request.ImageRequest
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.shahidy.iikb.Text
import com.shahidy.iikb.app.glass
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.min
import kotlinx.coroutines.withTimeoutOrNull

val LocalChats = staticCompositionLocalOf<Chats> { error("no chats") }

/**
 * The chats panel (docs/extensions.md), as iOS's `ChatPanel`: the open chat's messages, yours on the right, over the
 * message box the keys and the bar's mic type into. Opened from the menu it fills a keyboard grown for it, the chats as
 * tabs in the bar's row beside More, so you read and dictate with the keys down; a tap on the box brings the keys up
 * under it, the bar's suggestions on them, and a tap on the messages puts them away. The tabs and More stay where they
 * are as the keys come and go, on glass over the messages scrolling under them. With the keys down the bar's row is
 * left clear here but for them, so the bar's mic, drawn under it, shows and takes its taps.
 */
@Composable
fun ChatPanel(state: Overlay.State, line: Overlay.Line) {
    val look = LocalColors.current
    val chats = LocalChats.current
    val actions = LocalActions.current
    val bar = state.toolbar ?: return
    val keysUp = state.keysUp
    val empty = chats.messages.isEmpty()
    val quiet = when {
        !chats.listed -> "Loading chats…"
        chats.list.isEmpty() -> "No chats yet."
        chats.loaded && empty -> "No messages yet."
        else -> null
    }
    val backdrop = rememberLayerBackdrop()
    var photo by remember { mutableStateOf<Opened?>(null) }
    LaunchedEffect(chats.open) { photo = null }
    val row = bar.height.toFloat()
    Box(Modifier.fillMaxSize()) {
        Column(
            Modifier.fillMaxSize().padding(top = if (keysUp) 0.dp else row.dp)
                .padding(
                    start = state.minX.dp, end = state.endInset.dp, top = if (keysUp) (row - 6).dp else 0.dp,
                    bottom = if (keysUp) 0.dp else 8.dp,
                ),
        ) {
            Box(
                Modifier.weight(1f).fillMaxWidth()
                    .clickable(remember { MutableInteractionSource() }, indication = null) { if (keysUp) actions.browse() },
            ) {
                Box(Modifier.fillMaxSize().layerBackdrop(backdrop)) {
                    if (empty) (chats.problem ?: quiet)?.let { Notice(it) }
                    else Thread(chats.messages.takeLast(SHOWN), chats.problem) { photo = it }
                }
                photo?.let { PhotoView(it) { photo = null } }
            }
            Spacer(Modifier.size(6.dp))
            MessageBox(line, chats.open?.name?.let { "Message $it" } ?: "Message", caret = keysUp, backdrop)
        }
        // More's glass starts where the keys and the messages do, and the tabs a key's gap after it, as iOS's.
        val top = (bar.top + (bar.bar - TABS_HEIGHT) / 2).toFloat()
        val tabsX = bar.keysMinX.toFloat() + TABS_HEIGHT + 6
        if (!keysUp || chats.list.isNotEmpty()) GlassMore(bar.keysMinX.toFloat(), top, bar.glyph.toFloat(), backdrop)
        if (chats.list.isNotEmpty()) {
            val recording = !keysUp && (state.mic == "LISTENING" || state.mic == "WRITING")
            val end = if (recording) bar.cancel.x - 8 else bar.maxX
            ChatTabs(
                chats.list.map { it.name }, chats.list.indexOf(chats.open).takeIf { it >= 0 }, state.fresh, backdrop,
                (end.toFloat() - tabsX).coerceAtLeast(0f).dp, actions::chat, Modifier.offset(tabsX.dp, top.dp),
            )
        }
    }
}

/** More beside the tabs, on a circle of the bar's glass (tinted toward the label) as tall as their capsule, at `x`, `y`: it closes the chat. */
@Composable
private fun GlassMore(x: Float, y: Float, glyph: Float, backdrop: com.kyant.backdrop.Backdrop) {
    val look = LocalColors.current
    val actions = LocalActions.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(
        Modifier.offset(x.dp, y.dp)
            .size(TABS_HEIGHT.dp).glass(CircleShape, backdrop, look.dark).clip(CircleShape)
            .background(look.label.copy(alpha = if (look.dark) 0.12f else 0.08f))
            .clickable(interaction, indication = null, onClick = actions::more),
        contentAlignment = Alignment.Center,
    ) { Glyph("more", look.label.copy(alpha = if (pressed) 0.55f else 1f), glyph.dp) }
}

@Composable
private fun Notice(text: String) {
    Box(Modifier.fillMaxSize().padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
        Text(text, color = LocalColors.current.secondary, fontSize = 15.sp, textAlign = TextAlign.Center)
    }
}

/** One bubble of a message, as iOS's `ChatThread` splits one: its photos, then its other files, then its text. */
private sealed interface Item {
    val mine: Boolean
    val pending: Boolean

    data class Words(val message: Chats.Message) : Item {
        override val mine get() = message.mine
        override val pending get() = message.pending == true
    }

    data class Photo(val file: Chats.Message.File, val url: String, override val mine: Boolean, override val pending: Boolean) : Item
    data class Document(val file: Chats.Message.File, override val mine: Boolean, override val pending: Boolean) : Item
}

private fun items(messages: List<Chats.Message>, url: (Chats.Message.File) -> String?) = messages.flatMap { message ->
    val files = message.files.orEmpty()
    val pending = message.pending == true
    files.filter { it.isImage }.mapNotNull { file -> url(file)?.let { Item.Photo(file, it, message.mine, pending) } } +
        files.filterNot { it.isImage }.map { Item.Document(it, message.mine, pending) } +
        if (message.text.isNotEmpty() || files.isEmpty()) listOf(Item.Words(message)) else emptyList()
}

/** A photo opened large over the messages. */
private class Opened(val file: Chats.Message.File, val url: String, val request: ImageRequest, val width: Int, val height: Int)

/**
 * The messages as Messages lays them out, the newest at the bottom and kept there as they come: a turn's bubbles 2
 * apart and turns 10, fading out over a line and a bit as they scroll up under the tabs and over less into the box.
 */
@Composable
private fun Thread(messages: List<Chats.Message>, problem: String?, open: (Opened) -> Unit) {
    val look = LocalColors.current
    val chats = LocalChats.current
    val list = rememberLazyListState()
    val shown = remember(messages, chats.open) { items(messages) { chats.url(it) } }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val widest = minOf((maxWidth - TAIL.dp * 2) * 0.75f, 520.dp)
        LazyColumn(
            Modifier.fillMaxSize().fadeEnds(),
            state = list, reverseLayout = true,
            contentPadding = PaddingValues(top = (TOP_FADE - 12).dp, bottom = 14.dp),
        ) {
            problem?.let {
                item {
                    Text(
                        it, color = look.secondary, fontSize = 13.sp, textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    )
                }
            }
            val newest = shown.asReversed()
            itemsIndexed(newest) { index, item ->
                val above = newest.getOrNull(index + 1)?.mine == item.mine
                val below = newest.getOrNull(index - 1)?.mine == item.mine
                val gap = if (index == newest.lastIndex) 0.dp else if (above) 2.dp else 10.dp
                Box(
                    Modifier.fillMaxWidth().padding(top = gap, start = TAIL.dp, end = TAIL.dp),
                    contentAlignment = if (item.mine) Alignment.CenterEnd else Alignment.CenterStart,
                ) {
                    val shape = BubbleShape(item.mine, above, below, tail = !below)
                    when (item) {
                        is Item.Words -> Bubble(item.message, shape, widest)
                        is Item.Document -> FileBubble(item, shape, widest)
                        is Item.Photo -> PhotoBubble(item, BubbleShape(item.mine, above, below), widest, open)
                    }
                }
            }
        }
    }
}

/** The messages fade out over `TOP_FADE` at the top and `BOTTOM_FADE` at the bottom. */
private fun Modifier.fadeEnds() = graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen).drawWithContent {
    drawContent()
    val top = (TOP_FADE.dp.toPx() / size.height).coerceAtMost(0.5f)
    val bottom = (BOTTOM_FADE.dp.toPx() / size.height).coerceAtMost(0.5f)
    drawRect(
        Brush.verticalGradient(0f to Color.Transparent, top to Color.Black, 1 - bottom to Color.Black, 1f to Color.Transparent),
        blendMode = BlendMode.DstIn,
    )
}

/**
 * A bubble's outline, as iOS's `UIBezierPath(bubble:)`: corners of 18, tightened to 6 on its side toward a neighbor
 * from the same side, as Messages'. With `tail`, the last of a run, its bottom corner on its side sweeps out into a
 * tail `TAIL` past its bounds.
 */
private class BubbleShape(val mine: Boolean, val above: Boolean, val below: Boolean, val tail: Boolean = false) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val unit = density.density
        val round = 18 * unit
        val near = { joined: Boolean -> CornerRadius(if (joined) 6 * unit else round) }
        val far = CornerRadius(round)
        val bottom = if (tail) CornerRadius.Zero else near(below)
        val rect = RoundRect(
            Rect(Offset.Zero, size),
            topLeft = if (mine) far else near(above), topRight = if (mine) near(above) else far,
            bottomRight = if (mine) bottom else far, bottomLeft = if (mine) far else bottom,
        )
        val path = Path().apply { addRoundRect(rect) }
        if (!tail) return Outline.Generic(path)
        val x = if (mine) size.width else 0f
        val away = if (mine) unit else -unit
        val y = size.height
        val tip = Path().apply {
            moveTo(x, y - round)
            cubicTo(x, y - 6 * unit, x + away * TAIL * 0.5f, y - unit, x + away * TAIL, y)
            cubicTo(x + away * TAIL * 0.2f, y + 0.5f * unit, x - away * 6, y - 0.5f * unit, x - away * 12, y - 3 * unit)
            lineTo(x - away * 18, y - round)
            close()
        }
        return Outline.Generic(Path.combine(PathOperation.Union, path, tip))
    }
}

/** A bubble's flat fill, as Messages draws one: yours on the accent color, the other side's on Messages' gray. */
@Composable
private fun Modifier.fill(mine: Boolean, pending: Boolean, shape: Shape): Modifier {
    val look = LocalColors.current
    return alpha(if (pending) 0.6f else 1f).background(if (mine) look.accent else look.chatBubble, shape)
}

/**
 * One message, 17 on 22 lines, hugging its text. Markdown's bold, italics and code drawn, and its links and web
 * addresses underlined in the text's color. Its text is iOS's non-editable UITextView: held, it selects with the
 * system's handles and Copy; a link tapped opens, and held offers Open Link and Copy Link.
 */
@Composable
private fun Bubble(message: Chats.Message, shape: Shape, widest: Dp) {
    val look = LocalColors.current
    Box(Modifier.widthIn(max = widest).fill(message.mine, message.pending == true, shape).padding(horizontal = 12.dp, vertical = 7.dp)) {
        val actions = LocalActions.current
        val hold = LocalHold.current
        val text = remember { arrayOfNulls<TextLayoutResult>(1) }
        val written = remember(message.text) { markdown(message.text, actions::openLink) }
        var bounds by remember { mutableStateOf(Rect.Zero) }
        SelectionContainer {
            BasicText(
                written,
                style = LINES.copy(color = if (message.mine) look.accentLabel else look.label),
                onTextLayout = { text[0] = it },
                modifier = Modifier.onGloballyPositioned { bounds = it.boundsInWindow() }
                    .heldLink({ position -> text[0]?.let { written.link(it, position) } }) { url ->
                        hold(
                            Held(
                                bounds, Held.Shows.Text(url), listed = true,
                                actions = listOf(
                                    Held.Action("safari", "Open Link") { actions.openLink(url) },
                                    Held.Action("doc.on.doc", "Copy Link") { actions.copyLink(url) },
                                ),
                            ),
                        )
                    }
                    .hugLines { text[0] },
            )
        }
    }
}

/** As wide as the text's longest line, as UILabel's `sizeThatFits` gives a wrapped label, not the whole width allowed. */
private fun Modifier.hugLines(lines: () -> TextLayoutResult?) = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    val laid = lines()
    val width = if (laid == null) placeable.width else
        (0 until laid.lineCount).maxOf { ceil(laid.getLineRight(it) - laid.getLineLeft(it)).toInt() }
    layout(width.coerceIn(constraints.minWidth, placeable.width), placeable.height) { placeable.place(0, 0) }
}

/** A file that isn't a photo, as its name after a document glyph. */
@Composable
private fun FileBubble(item: Item.Document, shape: Shape, widest: Dp) {
    val look = LocalColors.current
    val color = if (item.mine) look.accentLabel else look.label
    Row(
        Modifier.widthIn(max = widest).fill(item.mine, item.pending, shape).padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Glyph("doc", color, DOC_GLYPH.dp)
        Text(" " + item.file.name, color = color, style = LINES, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A photo as its extension serves it, with the extension's token. */
private fun photo(context: Context, url: String, token: String?) = ImageRequest.Builder(context).data(url).apply {
    token?.let { httpHeaders(NetworkHeaders.Builder().set("Authorization", "Bearer $it").build()) }
}.build()

/**
 * A photo, as Messages shows one: the picture itself, rounded as a bubble, up to 240 wide and 320 tall, in its shape
 * before it comes when the file says its size. A tap opens it large; held, it shows larger above Copy.
 */
@Composable
private fun PhotoBubble(item: Item.Photo, shape: Shape, widest: Dp, open: (Opened) -> Unit) {
    val look = LocalColors.current
    val context = LocalContext.current
    val chats = LocalChats.current
    val request = remember(item.url) { photo(context, item.url, chats.token) }
    val told = item.file.width?.let { width -> item.file.height?.let { width to it } }
    var size by remember(item.url) { mutableStateOf(told) }
    var loaded by remember(item.url) { mutableStateOf(false) }
    val (width, height) = size?.takeIf { it.first > 0 && it.second > 0 } ?: (4.0 to 3.0)
    val wide = minOf(widest.value, PHOTO_WIDTH)
    val scale = min(wide / width, PHOTO_HEIGHT / height)
    val opened = { Opened(item.file, item.url, request, width.toInt().coerceAtLeast(1), height.toInt().coerceAtLeast(1)) }
    var bounds by remember { mutableStateOf(Rect.Zero) }
    Box(
        Modifier.size((width * scale).toFloat().dp, (height * scale).toFloat().dp).alpha(if (item.pending) 0.6f else 1f)
            .clip(shape).background(look.key).onGloballyPositioned { bounds = it.boundsInWindow() }.heldAway(bounds)
            .held(loaded, { bounds }, opened, { if (loaded) open(opened()) }),
    ) {
        AsyncImage(
            request, item.file.name, imageLoader(), contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize(),
            onSuccess = {
                loaded = true
                size = it.result.image.width.toDouble() to it.result.image.height.toDouble()
            },
        )
    }
}

/** A tap does `tapped`; a hold, once the photo has come, shows it larger above Copy, which copies the original file. */
@Composable
private fun Modifier.held(loaded: Boolean, bounds: () -> Rect, photo: () -> Opened, tapped: () -> Unit): Modifier {
    val hold = LocalHold.current
    val actions = LocalActions.current
    return pointerInput(loaded) {
        detectTapGestures(
            onTap = { tapped() },
            onLongPress = {
                if (!loaded) return@detectTapGestures
                val shown = photo()
                hold(
                    Held(
                        bounds(), Held.Shows.Image(shown.request, shown.width, shown.height, photo = true), listed = true,
                        actions = listOf(Held.Action("doc.on.doc", "Copy") { actions.copyPhoto(shown.url, shown.file.type) }),
                    ),
                )
            },
        )
    }
}

/** A photo opened from its bubble, as large as the messages, over them until a tap closes it; held, it's the bubble's. */
@Composable
private fun PhotoView(photo: Opened, close: () -> Unit) {
    val look = LocalColors.current
    var bounds by remember { mutableStateOf(Rect.Zero) }
    Box(
        Modifier.fillMaxSize().background(look.card).onGloballyPositioned { bounds = it.boundsInWindow() }
            .held(true, { bounds }, { photo }, close).padding(8.dp),
    ) {
        AsyncImage(photo.request, photo.file.name, imageLoader(), contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
    }
}

/** The link under `position` in text laid out as `layout`, if any. */
private fun AnnotatedString.link(layout: TextLayoutResult, position: Offset): String? {
    val line = layout.getLineForVerticalPosition(position.y)
    if (position.x < layout.getLineLeft(line) || position.x > layout.getLineRight(line)) return null
    val at = layout.getOffsetForPosition(position)
    return getLinkAnnotations(at, at + 1).firstNotNullOfOrNull { (it.item as? LinkAnnotation.Url)?.url }
}

/** A long press on a link, taken before selection sees it, as UIKit gives a held link its own menu. */
private fun Modifier.heldLink(linkAt: (Offset) -> String?, held: (String) -> Unit) = pointerInput(Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        val url = linkAt(down.position) ?: return@awaitEachGesture
        val lifted = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
            waitForUpOrCancellation(PointerEventPass.Initial)
        }
        if (lifted != null) return@awaitEachGesture
        held(url)
        do {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            event.changes.forEach { it.consume() }
        } while (event.changes.any { it.pressed })
    }
}

/**
 * Markdown's inline marks, as iOS's `AttributedString(markdown:)` reads them: `**bold**`, `*italic*`, `` `code` `` and
 * `[links](…)`, with bare web addresses made links too, as a UITextView's link detector makes them. A link `opens`.
 */
fun markdown(text: String, opens: ((String) -> Unit)? = null): AnnotatedString = buildAnnotatedString {
    val link = { url: String, shown: String ->
        val styles = TextLinkStyles(SpanStyle(textDecoration = TextDecoration.Underline))
        withLink(LinkAnnotation.Url(url, styles) { opens?.invoke(url) }) { append(shown) }
    }
    val plain = { part: String ->
        var from = 0
        for (address in Patterns.WEB_URL.toRegex().findAll(part)) {
            append(part.substring(from, address.range.first))
            link(address.value, address.value)
            from = address.range.last + 1
        }
        append(part.substring(from))
    }
    var at = 0
    val marks = Regex("""\[(.+?)\]\((\S+?)\)|\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`""")
    for (found in marks.findAll(text)) {
        plain(text.substring(at, found.range.first))
        val (label, url, bold, under, italic, slanted, code) = found.destructured
        when {
            url.isNotEmpty() -> link(url, label)
            bold.isNotEmpty() || under.isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(bold + under) }
            italic.isNotEmpty() || slanted.isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(italic + slanted) }
            else -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 15.sp)) { append(code) }
        }
        at = found.range.last + 1
    }
    plain(text.substring(at))
}

/**
 * The message box, as iOS's `MessageField`: Liquid Glass, as the tabs, More and the mic around it are, holding what the
 * keys typed (or the placeholder), the caret while the keys are up, growing a line at a time to five, past which it
 * scrolls. Send, solid on the glass, grows in at its end once there's something to send and shrinks away when there
 * isn't. It has no mic of its own: the keyboard's one mic dictates into it as into any field. A tap brings the keys up.
 */
@Composable
private fun MessageBox(line: Overlay.Line, placeholder: String, caret: Boolean, backdrop: com.kyant.backdrop.Backdrop) {
    val look = LocalColors.current
    val actions = LocalActions.current
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val empty = line.text.isEmpty()
    val canSend = line.text.isNotBlank()
    val scroll = rememberScrollState()
    val shape = RoundedCornerShape(20.dp)
    Box(
        Modifier.fillMaxWidth().heightIn(min = 40.dp).glass(shape, backdrop, look.dark)
            .clickable(remember { MutableInteractionSource() }, indication = null) { if (!caret) actions.raiseKeys() },
    ) {
        Box(
            Modifier.heightIn(max = (22 * 5 + 18).dp).verticalScroll(scroll)
                .padding(start = 14.dp, end = (BUTTON + 2 * MARGIN).dp, top = 9.dp, bottom = 9.dp),
        ) {
            BasicText(
                if (empty) AnnotatedString(placeholder) else AnnotatedString(line.text),
                style = LINES.copy(color = if (empty) look.secondary else look.label),
                maxLines = if (empty) 1 else Int.MAX_VALUE, overflow = TextOverflow.Ellipsis,
                onTextLayout = { layout = it },
                modifier = Modifier.fillMaxWidth().drawWithContent {
                    drawContent()
                    val shown = layout ?: return@drawWithContent
                    if (!caret) return@drawWithContent
                    val at = if (empty) 0 else line.caret.coerceIn(0, line.text.length)
                    val rect = shown.getCursorRect(at)
                    val height = 22.dp.toPx()
                    drawRect(look.accent, Offset(rect.left, rect.center.y - height / 2), Size(2.dp.toPx(), height))
                },
            )
        }
        LaunchedEffect(line.text) { scroll.scrollTo(scroll.maxValue) }
        val motion = spring<Float>(dampingRatio = 1 - BUTTON_BOUNCE, stiffness = (2 * PI / BUTTON_SPRING).let { (it * it).toFloat() })
        val send by animateFloatAsState(if (canSend) 1f else 0f, motion, label = "send")
        Box(
            Modifier.align(Alignment.BottomEnd).padding(MARGIN.dp).size(BUTTON.dp).appear(send)
                .background(look.accent, CircleShape)
                .clickable(remember { MutableInteractionSource() }, indication = null, enabled = canSend) { actions.send() },
            contentAlignment = Alignment.Center,
        ) { Glyph("arrow.up", look.accentLabel, SEND_GLYPH.dp, weight = Glyphs.SEMIBOLD) }
    }
}

/** Grown in from half its size and faded in as `shown` goes from 0 to 1. */
private fun Modifier.appear(shown: Float) = graphicsLayer {
    alpha = shown.coerceIn(0f, 1f)
    val scale = 0.5f + 0.5f * shown
    scaleX = scale
    scaleY = scale
}

/**
 * Chats' shelf in the menu: a card for each chat, pinned first, its name over its latest line, three to the width as
 * the clipboard's cards are; a tap opens that chat.
 */
@Composable
fun ChatShelf() {
    val chats = LocalChats.current
    val actions = LocalActions.current
    val look = LocalColors.current
    val notice = when {
        !chats.listed -> "Loading chats…"
        chats.list.isEmpty() -> chats.problem ?: "No chats yet."
        else -> null
    }
    if (notice != null) return Empty(notice)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val card = (maxWidth - ITEM_GAP * 2) / 3
        val height = maxHeight
        val row = rememberLazyListState()
        LazyRow(Modifier.fillMaxSize(), state = row, horizontalArrangement = Arrangement.spacedBy(ITEM_GAP)) {
            items(chats.list, key = { it.service.name + "/" + it.id }) { chat ->
                Pressable(Modifier.size(card, height), CARD_RADIUS, onClick = { actions.openChat(chat.id) }) {
                    val inner = height - 16.dp
                    val latest = chat.line?.let { markdown(it).text }?.takeIf { inner >= 30.dp }
                    val name = @Composable { modifier: Modifier ->
                        Text(
                            chat.name, color = look.label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
                            overflow = TextOverflow.Ellipsis, modifier = modifier,
                        )
                    }
                    Box(Modifier.fillMaxSize().padding(horizontal = 10.dp, vertical = 8.dp), contentAlignment = Alignment.CenterStart) {
                        if (latest == null) name(Modifier)
                        else Column(Modifier.fillMaxSize()) {
                            Box(Modifier.height(18.dp), contentAlignment = Alignment.CenterStart) { name(Modifier) }
                            Text(
                                latest, color = look.secondary, fontSize = 12.sp, lineHeight = 15.sp,
                                maxLines = maxOf(((inner.value - 20) / 15).toInt(), 1), overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.padding(top = 2.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Messages' 17 on 22 lines, each its full 22 as UIKit sets them, where Compose trims the first's top and last's bottom. */
private val LINES = TextStyle(
    fontSize = 17.sp, lineHeight = 22.sp,
    lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
)
/** How far the last bubble of a run's tail reaches past it, kept clear at both edges, as iOS's `ChatThread.tail`. */
private const val TAIL = 6f
/** The document and send glyphs drawn as large as SF's `doc` and `arrow.up` at 15 points, 14 × 17.4 and 15 × 17.7. */
private const val DOC_GLYPH = 22f
private const val SEND_GLYPH = 21.6f
/** At most this many of a chat's latest messages are kept on show, as the extension sends them. */
private const val SHOWN = 40
/** As iOS's `ChatThread`: messages fade out over a line and a bit under the tabs, and over less into the box. */
private const val TOP_FADE = 28f
private const val BOTTOM_FADE = 10f
/** As iOS's `ImageBubble`. */
private const val PHOTO_WIDTH = 240f
private const val PHOTO_HEIGHT = 320f
/** As iOS's `MessageField`: send's side and margin, and the spring it grows in on. */
private const val BUTTON = 28f
private const val MARGIN = 6f
private const val BUTTON_SPRING = 0.3f
private const val BUTTON_BOUNCE = 0.2f
