package com.shahidy.iikb.keyboard

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Row
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

val LocalChats = staticCompositionLocalOf<Chats> { error("no chats") }

/**
 * The chats panel (docs/extensions.md): the open chat's messages, yours on the right, over the message box the keys and
 * the bar's mic type into. With the keys down it fills a keyboard grown for it, the chats as pills in the bar; a tap on
 * the box brings the keys up under it, and a tap on the messages puts them away.
 */
@Composable
fun ChatPanel(state: Overlay.State, line: Overlay.Line) {
    val look = LocalColors.current
    val chats = LocalChats.current
    val actions = LocalActions.current
    val empty = chats.messages.isEmpty()
    val quiet = when {
        !chats.listed -> "Loading chats…"
        chats.list.isEmpty() -> "No chats yet."
        chats.loaded && empty -> "No messages yet."
        else -> null
    }
    Column(
        Modifier.fillMaxSize().background(look.card)
            .padding(start = state.minX.dp, end = state.endInset.dp, top = 8.dp, bottom = if (state.keysUp) 0.dp else 8.dp),
    ) {
        val title = chats.open?.name
        if (state.keysUp && title != null) {
            Text(
                title, color = look.secondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
                overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().height(20.dp),
            )
        }
        Box(
            Modifier.weight(1f).fillMaxWidth()
                .clickable(remember { MutableInteractionSource() }, indication = null) { if (state.keysUp) actions.browse() },
        ) {
            if (empty) {
                (chats.problem ?: quiet)?.let { Notice(it) }
            } else {
                Thread(chats.messages.takeLast(SHOWN), chats.problem)
            }
        }
        Spacer(Modifier.size(6.dp))
        MessageBox(line, title?.let { "Message $it" } ?: "Message", caret = state.keysUp, mic = state.mic)
    }
}

@Composable
private fun Notice(text: String) {
    Box(Modifier.fillMaxSize().padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
        Text(text, color = LocalColors.current.secondary, fontSize = 15.sp, textAlign = TextAlign.Center)
    }
}

/** The messages from the newest up, the newest at the bottom, going soft where they scroll past either end. */
@Composable
private fun Thread(messages: List<Chats.Message>, problem: String?) {
    val look = LocalColors.current
    val list = rememberLazyListState()
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val widest = minOf(maxWidth * 0.75f, 520.dp)
        LazyColumn(
            Modifier.fillMaxSize().fadeBothEnds(),
            state = list, reverseLayout = true,
        ) {
            problem?.let {
                item {
                    Text(
                        it, color = look.secondary, fontSize = 13.sp, textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    )
                }
            }
            val newest = messages.asReversed()
            itemsIndexed(newest) { index, message ->
                val above = newest.getOrNull(index + 1)?.mine == message.mine
                val below = newest.getOrNull(index - 1)?.mine == message.mine
                val gap = if (index == newest.lastIndex) 0.dp else if (above) 2.dp else 10.dp
                Box(
                    Modifier.fillMaxWidth().padding(top = gap),
                    contentAlignment = if (message.mine) Alignment.CenterEnd else Alignment.CenterStart,
                ) { Bubble(message, above, below, widest) }
            }
        }
    }
}

/** 14 dp at the top and bottom fade out, so a message scrolled past the top or under the box goes soft rather than cut. */
private fun Modifier.fadeBothEnds() = graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen).drawWithContent {
    drawContent()
    val fade = (14.dp.toPx() / size.height).coerceAtMost(0.5f)
    drawRect(
        Brush.verticalGradient(0f to Color.Transparent, fade to Color.Black, 1 - fade to Color.Black, 1f to Color.Transparent),
        blendMode = BlendMode.DstIn,
    )
}

/**
 * One message as Messages draws it: yours on the accent color, theirs on a key's with its shadow, 17 on 22 lines,
 * hugging its text; the corners toward a message from the same side tighten. Markdown's bold, italics and code drawn.
 */
@Composable
private fun Bubble(message: Chats.Message, above: Boolean, below: Boolean, widest: androidx.compose.ui.unit.Dp) {
    val look = LocalColors.current
    val round = 18.dp
    val tight = 6.dp
    val top = if (above) tight else round
    val bottom = if (below) tight else round
    val shape = if (message.mine) {
        RoundedCornerShape(topStart = round, topEnd = top, bottomStart = round, bottomEnd = bottom)
    } else {
        RoundedCornerShape(topStart = top, topEnd = round, bottomStart = bottom, bottomEnd = round)
    }
    val fill = if (message.mine) look.accent else look.key
    Box(
        Modifier.widthIn(max = widest).alpha(if (message.pending == true) 0.6f else 1f)
            .drawBehind {
                val outline = shape.createOutline(size, layoutDirection, this)
                if (!message.mine) {
                    translate(top = 1.dp.toPx()) { drawOutline(outline, look.shadow) }
                }
                drawOutline(outline, fill)
            }
            .padding(horizontal = 12.dp, vertical = 7.dp),
    ) {
        Text(
            markdown(message.text), color = if (message.mine) look.accentLabel else look.label,
            style = TextStyle(fontSize = 17.sp, lineHeight = 22.sp),
        )
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.translate(
    top: Float, block: androidx.compose.ui.graphics.drawscope.DrawScope.() -> Unit,
) = drawContext.transform.let {
    it.translate(0f, top)
    block()
    it.translate(0f, -top)
}

/** Markdown's inline marks, as iOS's `AttributedString(markdown:)` reads them: `**bold**`, `*italic*`, `` `code` ``. */
fun markdown(text: String): AnnotatedString = buildAnnotatedString {
    var at = 0
    val marks = Regex("""\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`""")
    for (found in marks.findAll(text)) {
        append(text.substring(at, found.range.first))
        val (bold, under, italic, slanted, code) = found.destructured
        when {
            bold.isNotEmpty() || under.isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(bold + under) }
            italic.isNotEmpty() || slanted.isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(italic + slanted) }
            else -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 15.sp)) { append(code) }
        }
        at = found.range.last + 1
    }
    append(text.substring(at))
}

/**
 * The message box: what the keys typed (or the placeholder), the caret while the keys are up, growing a line at a time
 * to five, past which it scrolls; its own mic and send, so a message can be said and sent with the keys down, send
 * dimmed until there's something to send. A tap brings the keys up.
 */
@Composable
private fun MessageBox(line: Overlay.Line, placeholder: String, caret: Boolean, mic: String) {
    val look = LocalColors.current
    val actions = LocalActions.current
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val empty = line.text.isEmpty()
    val canSend = line.text.isNotBlank()
    val scroll = rememberScrollState()
    Box(
        Modifier.fillMaxWidth().heightIn(min = 40.dp)
            .drawBehind {
                val outline = RoundedCornerShape(20.dp).createOutline(size, layoutDirection, this)
                if (!look.dark) translate(top = 1.dp.toPx()) { drawOutline(outline, look.shadow) }
                drawOutline(outline, look.field)
            }
            .clickable(remember { MutableInteractionSource() }, indication = null) { if (!caret) actions.raiseKeys() },
    ) {
        Box(Modifier.heightIn(max = (22 * 5 + 18).dp).verticalScroll(scroll).padding(start = 14.dp, end = (2 * 28 + 3 * 6).dp, top = 9.dp, bottom = 9.dp)) {
            BasicText(
                if (empty) AnnotatedString(placeholder) else AnnotatedString(line.text),
                style = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, color = if (empty) look.secondary else look.label),
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
        LaunchedScrollToEnd(scroll, line.text)
        val sendable by animateFloatAsState(if (canSend) 1f else 0.3f, spring(dampingRatio = 0.8f), label = "send")
        Row(Modifier.align(Alignment.BottomEnd).padding(6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            val listening = mic == "LISTENING"
            Box(
                Modifier.size(28.dp).alpha(if (mic == "WRITING") 0.5f else 1f)
                    .background(if (listening) look.record else look.mic, CircleShape)
                    .clickable(remember { MutableInteractionSource() }, indication = null) { actions.mic() },
                contentAlignment = Alignment.Center,
            ) {
                if (listening) Glyph("stop.fill", Color.White, 12.dp) else Glyph("waveform", look.micGlyph, 16.dp)
            }
            Box(
                Modifier.size(28.dp).alpha(sendable).background(look.accent, CircleShape)
                    .clickable(remember { MutableInteractionSource() }, indication = null, enabled = canSend) { actions.send() },
                contentAlignment = Alignment.Center,
            ) { Glyph("arrow.up", look.accentLabel, 15.dp) }
        }
    }
}

/** The box keeps its last line in view as you type past five. */
@Composable
private fun LaunchedScrollToEnd(scroll: androidx.compose.foundation.ScrollState, text: String) {
    androidx.compose.runtime.LaunchedEffect(text) { scroll.scrollTo(scroll.maxValue) }
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
                Pressable(Modifier.size(card, height), 10.dp, onClick = { actions.openChat(chat.id) }) {
                    Column(Modifier.fillMaxSize().padding(horizontal = 10.dp, vertical = 6.dp), verticalArrangement = Arrangement.Center) {
                        Text(chat.name, color = look.label, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val latest = chat.line?.let { markdown(it).text }
                        if (latest != null && height >= 42.dp) {
                            Text(latest, color = look.secondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

/** At most this many of a chat's latest messages are kept on show, as the extension sends them. */
private const val SHOWN = 40
