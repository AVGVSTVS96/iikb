package com.shahidy.iikb.keyboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

/**
 * The clipboard's shelf in the menu (docs/design.md, "Clipboard", compact): links as badges, a column of them for the
 * newest, then up to three cards in view, scrolling sideways. A tap types the clip.
 */
@Composable
fun ClipShelf(height: Dp) {
    val rows = rememberClips("")
    val actions = LocalActions.current
    var shown by remember { mutableStateOf<Clips.Row?>(null) }
    if (rows.isEmpty()) return Empty("Things you copy show up here.")
    val links = rows.filter { it.kind == "link" }
    val perColumn = floor(height.value / 26f).toInt().coerceAtLeast(1)
    val columns = links.chunked(perColumn).take(2)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val card = (maxWidth - ITEM_GAP * 2) / 3
        LazyRow(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(ITEM_GAP)) {
            items(columns) { column ->
                val badge = minOf(36.dp, (height - ITEM_GAP * (column.size - 1)) / column.size)
                Column(
                    Modifier.fillMaxHeight(),
                    verticalArrangement = if (column.size == 1) Arrangement.Center else Arrangement.SpaceBetween,
                ) {
                    column.forEach { Badge(it, badge, onHold = { shown = it }) { actions.paste(it.text) } }
                }
            }
            items(rows.filter { it.kind != "link" }) { row ->
                Pressable(Modifier.width(card).fillMaxHeight(), 10.dp, { actions.paste(row.text) }, { shown = row }) {
                    Card(row)
                }
            }
        }
    }
    shown?.let { ClipPreview(it) { shown = null } }
}

@Composable
fun Card(row: Clips.Row) {
    val look = LocalColors.current
    Column(Modifier.fillMaxSize().padding(horizontal = 10.dp, vertical = 8.dp)) {
        Row(Modifier.weight(1f)) {
            KindMark(row, 14.dp)
            Text(
                if (row.kind == "email") row.text.replace("@", "@​") else row.text,
                color = look.label, fontSize = 14.sp, lineHeight = 18.sp, overflow = TextOverflow.Ellipsis,
                style = textStyle(row),
            )
        }
        Text(detail(row), color = look.secondary, fontSize = 11.sp, maxLines = 1, style = DIGITS)
    }
}

/** A color shows in monospaced capitals, as its swatch's name. */
private fun textStyle(row: Clips.Row) =
    if (row.kind == "color") TextStyle(fontFamily = FontFamily.Monospace) else TextStyle.Default

private val DIGITS = TextStyle(fontFeatureSettings = "tnum")

private fun detail(row: Clips.Row) = listOfNotNull(row.length, row.age).joinToString(" · ")

/** An address, a number or a color leads with its own glyph or swatch, on its text's first line. */
@Composable
private fun KindMark(row: Clips.Row, size: Dp) {
    val look = LocalColors.current
    val glyph = when (row.kind) {
        "email" -> "envelope"
        "phone" -> "phone"
        else -> null
    }
    when {
        glyph != null -> Glyph(glyph, look.secondary, size, Modifier.padding(top = 2.dp, end = 6.dp))
        row.color != null -> Box(
            Modifier.padding(top = 2.dp, end = 6.dp).size(size).background(Color(row.color), RoundedCornerShape(4.dp))
                .border(0.5.dp, look.secondary.copy(alpha = 0.4f), RoundedCornerShape(4.dp)),
        )
    }
}

/** A link as a one-line badge: its site's mark on a white tile, the site's name, and how long ago. */
@Composable
private fun Badge(row: Clips.Row, height: Dp, onHold: () -> Unit, onClick: () -> Unit) {
    val look = LocalColors.current
    Pressable(Modifier.height(height), height / 2, onClick, onHold) {
        Row(Modifier.padding(start = 5.dp, end = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(minOf(20.dp, height - 8.dp)).background(Color.White, RoundedCornerShape(5.dp))
                    .border(0.5.dp, Color(0x22000000), RoundedCornerShape(5.dp)),
                contentAlignment = Alignment.Center,
            ) { Glyph("globe", Color(0xFF8E8E93), 14.dp) }
            Spacer(Modifier.width(6.dp))
            Text(row.name ?: row.site ?: "", color = look.label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Text(" · ${row.age}", color = look.secondary, fontSize = 13.sp, maxLines = 1, style = DIGITS)
            if (row.pinned) Glyph("pin.fill", look.secondary, 11.dp, Modifier.padding(start = 4.dp))
        }
    }
}

@Composable
fun Empty(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text, color = LocalColors.current.secondary, fontSize = 15.sp)
    }
}

/**
 * The clipboard panel (docs/design.md, "Clipboard"): its links in a line, then rows of clips, newest first, three in
 * view, over its search row. Opened from the menu it fills the keys' place; a tap on its search brings the keys up
 * under it, typing into the search.
 */
@Composable
fun ClipboardPanel(state: Overlay.State) {
    val look = LocalColors.current
    val actions = LocalActions.current
    var linksOnly by remember { mutableStateOf(false) }
    var shown by remember { mutableStateOf<Clips.Row?>(null) }
    val rows = rememberClips(state.query)
    val links = rows.filter { it.kind == "link" }
    Column(
        Modifier.fillMaxSize().background(look.card)
            .padding(start = state.minX.dp, end = state.endInset.dp, top = 3.dp, bottom = if (state.keysUp) 0.dp else 11.dp),
    ) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            when {
                rows.isEmpty() && state.query.isBlank() -> Empty("Things you copy show up here.")
                rows.isEmpty() -> Empty("No clips for “${state.query.trim()}”")
                else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (links.isNotEmpty() && !linksOnly) {
                        item {
                            LazyRow(Modifier.height(32.dp), horizontalArrangement = Arrangement.spacedBy(ITEM_GAP)) {
                                items(links) { Badge(it, 30.dp, { shown = it }) { actions.paste(it.text) } }
                            }
                        }
                    }
                    items(if (linksOnly) links else rows.filter { it.kind != "link" }) { row ->
                        if (linksOnly) {
                            Badge(row, 30.dp, { shown = row }) { actions.paste(row.text) }
                        } else {
                            ClipRow(row, { actions.paste(row.text) }) { shown = row }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        SearchRow(
            state, { Glyph("doc.on.clipboard", look.secondary, 18.dp) }, if (linksOnly) "Search links" else "Search clipboard",
            trailing = {
                Box(
                    Modifier.padding(start = 4.dp).size(36.dp, state.field.dp).clickable { linksOnly = !linksOnly },
                    contentAlignment = Alignment.Center,
                ) { Glyph("link", if (linksOnly) look.accent else look.secondary, 20.dp) }
            },
        )
    }
    shown?.let { ClipPreview(it) { shown = null } }
}

@Composable
fun ClipRow(row: Clips.Row, onClick: () -> Unit, onHold: () -> Unit) {
    val look = LocalColors.current
    Pressable(Modifier.fillMaxWidth().height(44.dp), 10.dp, onClick, onHold) {
        Row(Modifier.fillMaxWidth().padding(end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) {
                if (row.pinned) Glyph("pin.fill", look.secondary, 13.dp)
            }
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                KindMark(row, 16.dp)
                Text(
                    row.text.replace('\n', ' '), color = look.label, fontSize = 16.sp, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, style = textStyle(row),
                )
            }
            Text(detail(row), color = look.secondary, fontSize = 13.sp, maxLines = 1, style = DIGITS,
                modifier = Modifier.padding(start = 8.dp))
        }
    }
}

/**
 * A panel's search row: back, then the field with its glyph and the search, which the keys type into once they're up;
 * a tap on it brings them up.
 */
@Composable
fun SearchRow(
    state: Overlay.State, leading: @Composable () -> Unit, placeholder: String, notice: String? = null,
    trailing: @Composable () -> Unit = {},
) {
    val look = LocalColors.current
    val actions = LocalActions.current
    val height = state.field.dp
    Row(Modifier.fillMaxWidth().height(height), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(36.dp, height).clickable { actions.back() }, contentAlignment = Alignment.Center) {
            Glyph("chevron.left", look.label, 22.dp)
        }
        Spacer(Modifier.width(4.dp))
        Row(
            Modifier.weight(1f).height(height)
                .then(if (look.dark) Modifier else Modifier.drawBehind {
                    drawRoundRect(look.shadow, Offset(0f, 1.dp.toPx()), size, CornerRadius(size.height / 2))
                })
                .background(look.field, CircleShape)
                .clickable(remember { MutableInteractionSource() }, indication = null) { actions.raiseKeys() }
                .padding(start = 14.dp, end = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            leading()
            Spacer(Modifier.width(8.dp))
            val caret = @Composable { if (state.keysUp) Box(Modifier.width(2.dp).height(22.dp).background(look.accent)) }
            if (notice != null) {
                Text(notice, color = look.secondary, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f))
            } else if (state.query.isEmpty()) {
                caret()
                Text(placeholder, color = look.secondary, fontSize = 17.sp, maxLines = 1, modifier = Modifier.weight(1f))
            } else {
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        state.query, color = look.label, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    caret()
                }
            }
            if (state.query.isNotEmpty() && notice == null) {
                Box(
                    Modifier.size(20.dp).background(look.secondary, CircleShape).clickable { actions.clearSearch() },
                    contentAlignment = Alignment.Center,
                ) { Glyph("xmark", look.field, 11.dp) }
            }
        }
        trailing()
    }
}

/** All of a clip, held: its whole text, scrolling where it's long, with Paste, Pin or Unpin, and Delete. */
@Composable
private fun ClipPreview(row: Clips.Row, close: () -> Unit) {
    val actions = LocalActions.current
    val clips = Clips.of(LocalContext.current)
    Preview(row, close) { button ->
        Action(button, "doc.on.clipboard", "Paste") {
            close()
            actions.paste(row.text)
        }
        Action(button, "pin.fill", if (row.pinned) "Unpin" else "Pin") {
            close()
            clips.pin(row.text, !row.pinned)
        }
        Action(button, "trash", "Delete", Color(0xFFFF3B30)) {
            close()
            clips.remove(row.text)
        }
    }
}

/** A held item's whole text over its actions, the card sized to the text; a tap elsewhere puts it away. */
@Composable
fun Preview(row: Clips.Row, close: () -> Unit, buttons: @Composable RowScope.(Modifier) -> Unit) {
    val look = LocalColors.current
    Column(
        Modifier.fillMaxSize().background(look.card)
            .clickable(remember { MutableInteractionSource() }, indication = null, onClick = close).padding(10.dp),
    ) {
        Box(
            Modifier.weight(1f, fill = false).fillMaxWidth().background(look.key, RoundedCornerShape(12.dp))
                .clickable(remember { MutableInteractionSource() }, indication = null, onClick = close)
                .padding(14.dp),
        ) {
            Text(
                row.text, color = look.label, fontSize = 16.sp, style = textStyle(row),
                modifier = Modifier.verticalScroll(rememberScrollState()),
            )
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth().height(40.dp), horizontalArrangement = Arrangement.spacedBy(ITEM_GAP)) {
            buttons(Modifier.weight(1f).fillMaxHeight())
        }
    }
}

@Composable
fun Action(modifier: Modifier, glyph: String, title: String, tint: Color? = null, onClick: () -> Unit) {
    val look = LocalColors.current
    Pressable(modifier, 20.dp, onClick) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Glyph(glyph, tint ?: look.keyLabel, 16.dp)
            Spacer(Modifier.width(6.dp))
            Text(title, color = tint ?: look.keyLabel, fontSize = 16.sp, fontWeight = FontWeight.Medium)
        }
    }
}
