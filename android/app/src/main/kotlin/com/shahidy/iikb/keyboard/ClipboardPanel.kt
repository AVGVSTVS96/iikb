package com.shahidy.iikb.keyboard

import androidx.compose.foundation.background
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import com.shahidy.iikb.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.decode.BitmapFactoryDecoder
import coil3.request.ImageRequest
import com.shahidy.iikb.Settings
import kotlin.math.floor

/** The clips holding `query`, kept current as the history changes. */
@Composable
fun rememberClips(query: String): List<Clips.Row> {
    val context = LocalContext.current
    val clips = remember { Clips.of(context) }
    val words = remember { Settings(context).string("clipboardLength") == "words" }
    var revision by remember { mutableIntStateOf(0) }
    DisposableEffect(clips) {
        val listener: () -> Unit = { revision++ }
        clips.listen(listener)
        onDispose { clips.stopListening(listener) }
    }
    return remember(query, revision) { clips.rows(query, words) }
}

/** A clip picked: its text typed, or its image put in the field. */
private fun Overlay.Actions.pick(row: Clips.Row) = row.image?.let(::pasteImage) ?: paste(row.text)

/**
 * The clipboard's shelf in the menu (docs/design.md, "Clipboard", compact), as iOS's compact panel lays it out: its
 * newest links as one-line badges in up to two columns, each column as wide as its widest badge, then the rest as cards,
 * three in view, scrolling sideways. A tap types the clip, or puts its image in the field.
 */
@Composable
fun ClipShelf(height: Dp) {
    val rows = rememberClips("")
    val actions = LocalActions.current
    val hold = rememberClipHold()
    if (rows.isEmpty()) return Empty("Things you copy show up here.")
    val stacked = floor((height.value + GAP) / (26f + GAP)).toInt().coerceAtLeast(1)
    val badge = minOf(floor((height.value - GAP * (stacked - 1)) / stacked), 36f)
    val stackGap = if (stacked > 1) (height.value - stacked * badge) / (stacked - 1) else GAP
    val columns = rows.filter { it.kind == "link" }.take(2 * stacked).chunked(stacked)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val card = floor((maxWidth.value - GAP * 2) / 3).dp
        val row = rememberLazyListState()
        LazyRow(Modifier.fillMaxSize(), state = row, horizontalArrangement = Arrangement.spacedBy(ITEM_GAP)) {
            items(columns) { column ->
                Column(
                    Modifier.width(IntrinsicSize.Max).fillMaxHeight(),
                    verticalArrangement = Arrangement.spacedBy(stackGap.dp),
                ) {
                    column.forEach { row ->
                        Badge(row, true, Modifier.fillMaxWidth().height(badge.dp), { hold(row, it) }) { actions.pick(row) }
                    }
                }
            }
            items(rows.filter { it.kind != "link" }) { row ->
                Pressable(Modifier.width(card).fillMaxHeight(), 10.dp, { actions.pick(row) }, { hold(row, it) }) {
                    Card(row)
                }
            }
        }
    }
}

/**
 * A clip as iOS's compact row draws it, a card: its text in two lines at most, centered in the room over its length
 * and age, or a square of its image; its pin in the corner.
 */
@Composable
fun Card(row: Clips.Row) {
    val look = LocalColors.current
    val secondary = look.onKeySecondary
    Box(Modifier.fillMaxSize().padding(horizontal = 10.dp, vertical = 6.dp)) {
        Column(Modifier.fillMaxSize()) {
            Box(
                Modifier.weight(1f).fillMaxWidth().padding(end = if (row.pinned) 16.dp else 0.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (row.image != null) {
                    ClipImage(row.image, Modifier.align(Alignment.TopStart).fillMaxHeight().aspectRatio(1f), 6.dp)
                } else {
                    val (text, inline) = clipTitle(row, 14f, look.label, secondary)
                    Text(
                        text, color = look.label, fontSize = 14.sp, lineHeight = 17.sp, maxLines = 2,
                        overflow = TextOverflow.Ellipsis, inlineContent = inline,
                    )
                }
            }
            Text(
                detail(row), color = secondary, fontSize = 11.sp, lineHeight = 13.sp, maxLines = 1, style = DIGITS,
                modifier = Modifier.height(13.dp),
            )
        }
        if (row.pinned) Box(Modifier.align(Alignment.TopEnd).size(14.dp), contentAlignment = Alignment.Center) {
            Glyph("pin.fill", secondary, Glyphs.square(13f).dp)
        }
    }
}

/** A copied image cut to its square, decoded at the size it shows, its first frame only, as iOS's thumbnails are. */
@Composable
fun ClipImage(image: String, modifier: Modifier, corner: Dp) {
    val context = LocalContext.current
    val request = remember(image) {
        ImageRequest.Builder(context).data(Clips.of(context).file(image)).decoderFactory(BitmapFactoryDecoder.Factory()).build()
    }
    AsyncImage(
        request, "Image", imageLoader(), modifier.clip(RoundedCornerShape(corner)),
        contentScale = ContentScale.Crop,
    )
}

private val DIGITS = TextStyle(fontFeatureSettings = "tnum")

private fun detail(row: Clips.Row) = listOfNotNull(row.length, row.age).joinToString(" · ")

/** Secondary text on the key fill, a card's or a badge's: the label at 62%, as iOS's `onKeySecondary`. */
val Colors.onKeySecondary get() = label.copy(alpha = 0.62f)

/**
 * How a clip is written, as iOS's `ClipTitle`: plain text as it is, an address or a phone number after its glyph, a
 * color in capitals after a round swatch of it, each mark on the text's first line and an address wrapping after its @.
 */
@Composable
private fun clipTitle(row: Clips.Row, size: Float, label: Color, secondary: Color): Pair<AnnotatedString, Map<String, InlineTextContent>> {
    val text = row.text.trim()
    val mark = Math.round(size * 1.1f).toFloat()
    val glyph = when (row.kind) {
        "email" -> "envelope"
        "phone" -> "phone"
        else -> null
    }
    if (glyph == null && row.color == null) return AnnotatedString(text.replace('\n', ' ')) to emptyMap()
    val title = buildAnnotatedString {
        appendInlineContent("mark")
        append(" ⁠")
        when {
            row.kind == "email" -> append(text.replace("@", "@​"))
            row.color != null -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append(text.uppercase()) }
            else -> append(text)
        }
    }
    val inline = InlineTextContent(Placeholder(mark.sp, mark.sp, PlaceholderVerticalAlign.TextCenter)) {
        if (glyph != null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Glyph(glyph, secondary, Glyphs.square(size * 0.8f).dp, weight = Glyphs.MEDIUM) }
        } else {
            Box(
                Modifier.fillMaxSize().clip(CircleShape).background(Color(row.color!!))
                    .border(1.dp, secondary.copy(alpha = 0.4f), CircleShape),
            )
        }
    }
    return title to mapOf("mark" to inline)
}

/**
 * A link as iOS's badge writes it on one line: its site's icon, the site's name and how long ago, `github · 5m`, with a
 * pin when pinned, on a capsule of the key fill as wide as its words up to 200.
 */
@Composable
private fun Badge(row: Clips.Row, compact: Boolean, modifier: Modifier, onHold: (Rect) -> Unit, onClick: () -> Unit) {
    val look = LocalColors.current
    val size = if (compact) 13f else 14f
    val icon = Math.round(size * 1.3f).toFloat()
    val secondary = look.onKeySecondary
    val title = buildAnnotatedString {
        appendInlineContent("icon")
        append(" ⁠")
        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(row.name ?: row.site ?: "") }
        withStyle(SpanStyle(color = secondary, fontFeatureSettings = "tnum")) { append(" · ${row.age}") }
        if (row.pinned) {
            append(" ")
            appendInlineContent("pin")
        }
    }
    val inline = mapOf(
        "icon" to InlineTextContent(Placeholder(icon.sp, icon.sp, PlaceholderVerticalAlign.TextCenter)) {
            SiteIcon(row.site, secondary)
        },
        "pin" to InlineTextContent(Placeholder((size * 0.75f).sp, (size * 0.75f).sp, PlaceholderVerticalAlign.TextCenter)) {
            Glyph("pin.fill", secondary, Glyphs.square(size * 0.75f).dp)
        },
    )
    Pressable(modifier.widthIn(max = 200.dp), 100.dp, onClick, onHold) {
        Text(
            title, color = look.label, fontSize = size.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
            inlineContent = inline, modifier = Modifier.padding(horizontal = BADGE_PADDING.dp),
        )
    }
}

@Composable
fun Empty(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text, color = LocalColors.current.secondary, fontSize = 15.sp)
    }
}

/**
 * The clipboard panel (docs/design.md, "Clipboard"): its links as badges on one line, as many as fit, then rows of
 * clips, newest first, over its search row with the link button in it, which shows only the links. Opened from the
 * menu it fills the keys' place; a tap on its search brings the keys up under it, typing into the search.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ClipboardPanel(state: Overlay.State) {
    val look = LocalColors.current
    val actions = LocalActions.current
    var linksOnly by remember { mutableStateOf(false) }
    val hold = rememberClipHold()
    val rows = rememberClips(state.query)
    val links = rows.filter { it.kind == "link" }
    val clips = if (linksOnly) emptyList() else rows.filter { it.kind != "link" }
    Column(
        Modifier.fillMaxSize().background(look.card)
            .padding(state.panelPadding),
    ) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when {
                links.isEmpty() && clips.isEmpty() && state.query.isBlank() ->
                    Empty(if (linksOnly) "Links you copy show up here." else "Things you copy show up here.")
                links.isEmpty() && clips.isEmpty() -> Empty("Nothing copied with “${state.query.trim()}”")
                else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (links.isNotEmpty()) {
                        item {
                            val badge = @Composable { row: Clips.Row ->
                                Badge(row, false, Modifier.height(32.dp), { hold(row, it) }) { actions.pick(row) }
                            }
                            Box(Modifier.padding(bottom = if (clips.isEmpty()) 0.dp else 6.dp)) {
                                if (linksOnly) {
                                    FlowRow(
                                        horizontalArrangement = Arrangement.spacedBy(ITEM_GAP),
                                        verticalArrangement = Arrangement.spacedBy(ITEM_GAP),
                                    ) { links.forEach { badge(it) } }
                                } else {
                                    FittingRow { links.forEach { badge(it) } }
                                }
                            }
                        }
                    }
                    items(clips) { row -> ClipRow(row, { actions.pick(row) }) { hold(row, it) } }
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        SearchRow(
            state, { Glyph("list.clipboard", look.secondary, LEADING) }, if (linksOnly) "Search links" else "Search clipboard",
            accessories = {
                Accessory("link", linksOnly) {
                    linksOnly = !linksOnly
                }
            },
        )
    }
}

/** A line of badges from its start, as many as fit (at least one), as iOS's `fittingBadges` shows them. */
@Composable
private fun FittingRow(content: @Composable () -> Unit) = Layout(content) { measurables, constraints ->
    val gap = ITEM_GAP.roundToPx()
    val placeables = measurables.map { it.measure(constraints.copy(minWidth = 0)) }
    var used = -gap
    var count = placeables.size
    for ((index, placeable) in placeables.withIndex()) {
        used += placeable.width + gap
        if (used > constraints.maxWidth) {
            count = maxOf(index, 1)
            break
        }
    }
    val shown = placeables.take(count)
    layout(constraints.maxWidth, shown.maxOfOrNull { it.height } ?: 0) {
        var x = 0
        shown.forEach {
            it.place(x, 0)
            x += it.width + gap
        }
    }
}

/**
 * A clip as iOS's full panel's row draws it, with no fill until pressed: its pin at the left, then its text on one
 * line or its image, and its length and age at the right.
 */
@Composable
fun ClipRow(row: Clips.Row, onClick: () -> Unit, onHold: (Rect) -> Unit) {
    val look = LocalColors.current
    Pressable(
        Modifier.fillMaxWidth().height(44.dp), 10.dp, onClick, onHold,
        fill = Color.Transparent, pressedFill = look.label.copy(alpha = 0.12f),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) {
                if (row.pinned) Glyph("pin.fill", look.secondary, Glyphs.square(13f).dp)
            }
            Spacer(Modifier.width(6.dp))
            Box(Modifier.weight(1f)) {
                if (row.image != null) {
                    ClipImage(row.image, Modifier.size(32.dp), 6.dp)
                } else {
                    val (text, inline) = clipTitle(row, 16f, look.label, look.secondary)
                    Text(
                        text, color = look.label, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        inlineContent = inline,
                    )
                }
            }
            Spacer(Modifier.width(12.dp))
            Text(
                detail(row), color = look.secondary, fontSize = 13.sp, maxLines = 1, style = DIGITS,
                textAlign = TextAlign.End, modifier = Modifier.widthIn(min = 28.dp),
            )
        }
    }
}

/** A button in the search field before its clear button, as iOS's accessories sit: blue while it's on. */
@Composable
fun Accessory(glyph: String, on: Boolean, onClick: () -> Unit) {
    val look = LocalColors.current
    Box(
        Modifier.width(32.dp).fillMaxHeight().clickable(remember { MutableInteractionSource() }, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Glyph(glyph, if (on) look.accent else look.secondary, ACCESSORY) }
}

/**
 * A panel's search row, as iOS's `PanelView` lays it out: back, then the field with its glyph and the search, which
 * the keys type into once they're up, its `accessories` and, once there's text, its clear button at its right end. A
 * tap on it brings the keys up. A `notice` ("Copied") stands in the search's place with a check.
 */
@Composable
fun SearchRow(
    state: Overlay.State, leading: @Composable () -> Unit, placeholder: String, notice: String? = null,
    accessories: @Composable () -> Unit = {},
) {
    val look = LocalColors.current
    val actions = LocalActions.current
    val height = state.field.dp
    Row(Modifier.fillMaxWidth().height(height), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(36.dp, height).clickable { actions.back() }, contentAlignment = Alignment.Center) {
            Glyph("chevron.left", look.label, BACK)
        }
        Spacer(Modifier.width(4.dp))
        Row(
            Modifier.weight(1f).height(height).background(look.field, CircleShape)
                .clickable(remember { MutableInteractionSource() }, indication = null) { actions.raiseKeys() }
                .padding(start = 14.dp, end = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(20.dp), contentAlignment = Alignment.Center) {
                if (notice != null) Checked(look.secondary, look.field) else leading()
            }
            Spacer(Modifier.width(6.dp))
            val caret = @Composable { if (state.keysUp) Box(Modifier.width(2.dp).height(22.dp).background(look.accent)) }
            Row(Modifier.weight(1f).padding(end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                when {
                    notice != null -> Text(notice, color = look.label, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    state.query.isEmpty() -> {
                        caret()
                        Text(placeholder, color = look.secondary, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    else -> {
                        Text(
                            state.query, color = look.label, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false),
                        )
                        caret()
                    }
                }
            }
            accessories()
            if (state.query.isNotEmpty() && notice == null) {
                Box(Modifier.size(28.dp, height).clickable { actions.clearSearch() }, contentAlignment = Alignment.Center) {
                    Clear(look.secondary, look.field)
                }
            }
        }
    }
}

/** iOS's clear button: a bold x cut from a 20 circle. */
@Composable
private fun Clear(circle: Color, mark: Color) = Canvas(Modifier.size(20.dp)) {
    drawCircle(circle)
    val arm = 3.4.dp.toPx()
    val stroke = 2.1.dp.toPx()
    drawLine(mark, center - Offset(arm, arm), center + Offset(arm, arm), stroke, StrokeCap.Round)
    drawLine(mark, center + Offset(arm, -arm), center + Offset(-arm, arm), stroke, StrokeCap.Round)
}

/** `checkmark.circle.fill`, the field's glyph while it shows a notice. */
@Composable
private fun Checked(circle: Color, mark: Color) = Canvas(Modifier.size(19.dp)) {
    drawCircle(circle)
    val unit = size.width / 20
    val path = Path().apply {
        moveTo(5.8f * unit, 10.4f * unit)
        lineTo(8.8f * unit, 13.4f * unit)
        lineTo(14.4f * unit, 6.9f * unit)
    }
    drawPath(path, mark, style = Stroke(2f * unit, cap = StrokeCap.Round, join = StrokeJoin.Round))
}

/** The search row's glyphs, as iOS's symbols' point sizes: its leading glyph, the back chevron and an accessory. */
val LEADING = Glyphs.square(17f).dp
private val BACK = Glyphs.square(22f).dp
private val ACCESSORY = Glyphs.square(18f).dp
private const val GAP = 6f
private const val BADGE_PADDING = 10f

/** A clip held: all of it, a link under its site, with Paste, Pin or Unpin, and Delete, as iOS's context menu has it. */
@Composable
private fun rememberClipHold(): (Clips.Row, Rect) -> Unit {
    val hold = LocalHold.current
    val actions = LocalActions.current
    val clips = Clips.of(LocalContext.current)
    return { row, source ->
        val shows = when {
            row.image != null -> Held.Shows.Image.of(clips.file(row.image))
            row.kind == "link" -> Held.Shows.Text(row.text, row)
            else -> Held.Shows.Text(row.text)
        }
        hold(
            Held(
                source, shows,
                listOf(
                    Held.Action("doc.on.clipboard", "Paste") { actions.pick(row) },
                    Held.Action(if (row.pinned) "pin.slash" else "pin", if (row.pinned) "Unpin" else "Pin") {
                        clips.pin(row, !row.pinned)
                    },
                    Held.Action("trash", "Delete", destructive = true) { clips.remove(row) },
                ),
            ),
        )
    }
}
