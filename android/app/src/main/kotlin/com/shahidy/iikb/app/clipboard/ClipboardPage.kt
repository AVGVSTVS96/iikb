package com.shahidy.iikb.app.clipboard

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.Settings
import com.shahidy.iikb.app.Divider
import com.shahidy.iikb.app.ListPage
import com.shahidy.iikb.app.MicSwitch
import com.shahidy.iikb.app.LocalResumes
import com.shahidy.iikb.app.design.Empty
import com.shahidy.iikb.app.design.Glyphs
import com.shahidy.iikb.app.design.Tints
import com.shahidy.iikb.app.design.Rows
import com.shahidy.iikb.app.design.SearchField
import com.shahidy.iikb.app.design.SectionPills
import com.shahidy.iikb.app.glyph
import com.shahidy.iikb.app.palette
import com.shahidy.iikb.app.transcripts.share
import com.shahidy.iikb.app.transcripts.title
import com.shahidy.iikb.keyboard.ClipImage
import com.shahidy.iikb.keyboard.Clips
import com.shahidy.iikb.keyboard.SiteIcon
import com.shahidy.iikb.keyboard.IikbService
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * What you copied, the same history the keyboard's clipboard panel keeps (`Clips`): links on top as one-line badges, then
 * the rest pinned first, then by day, newest first, under a search field, with All and Links pills. A tap copies an item
 * again; holding it opens, shares, pins or deletes it.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ClipboardPage() {
    val context = LocalContext.current
    val clips = remember { Clips.of(context) }
    val settings = remember { Settings(context) }
    val resumes = LocalResumes.current
    var changes by remember { mutableIntStateOf(0) }
    var query by rememberSaveable { mutableStateOf("") }
    var linksOnly by rememberSaveable { mutableStateOf(false) }
    var copied by remember { mutableStateOf<String?>(null) }
    DisposableEffect(clips) {
        val listener = { changes++; Unit }
        clips.listen(listener)
        onDispose { clips.stopListening(listener) }
    }
    LaunchedEffect(resumes) { copied = null }
    val words = settings.string("clipboardLength") == "words"
    val all = remember(changes, resumes, words) { clips.rows(words = words) }
    val found = remember(changes, resumes, words, query) { if (query.isBlank()) all else clips.rows(query.trim(), words) }
    val links = found.filter { it.kind == "link" }.let { if (linksOnly) it else it.take(6) }
    val rest = if (linksOnly) emptyList() else found.filter { it.kind != "link" }
    val groups = rest.groupBy { if (it.pinned) "Pinned" else title(it.time().toLocalDate()) }.toList()
    val copy = { row: Clips.Row ->
        put(context, clips, row)
        copied = row.id
    }
    ListPage(
        "Clipboard",
        pinned = if (all.isEmpty()) null else ({ SectionPills(listOf(false, true), linksOnly, { if (it) "Links" else "All" }) { linksOnly = it } }),
        actions = { MicSwitch() },
    ) {
        if (all.isEmpty()) {
            item {
                Empty(
                    Glyphs.CLIPBOARD, "Nothing Copied Yet",
                    "Everything you copy shows up here and in the keyboard’s clipboard, kept on this phone.",
                )
            }
            return@ListPage
        }
        item { Box(Modifier.padding(top = 4.dp, bottom = 24.dp)) { SearchField(query, "Search") { query = it } } }
        if (links.isEmpty() && rest.isEmpty()) {
            item {
                if (linksOnly && query.isBlank()) {
                    Empty(Glyphs.LINK, "No Links Yet", "Links you copy show up here.")
                } else {
                    Empty(Glyphs.SEARCH, "No Results", "Check the spelling or try a new search.")
                }
            }
        }
        if (links.isNotEmpty()) {
            item {
                Column(Modifier.padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "Links", color = palette().secondary, fontSize = 15.sp, fontWeight = FontWeight.Medium,
                        modifier = Modifier.padding(horizontal = 20.dp),
                    )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        links.forEach { Badge(it, copied == it.id, clips, copy) }
                    }
                }
            }
        }
        groups.forEach { (title, rows) ->
            item(key = title) {
                Box(Modifier.padding(bottom = 24.dp)) {
                    Rows(title) {
                        rows.forEachIndexed { index, row ->
                            if (index > 0) Divider()
                            ClipRow(row, copied == row.id, clips, copy)
                        }
                    }
                }
            }
        }
    }
}

private fun Clips.Row.time() = Instant.ofEpochMilli((found * 1000).toLong()).atZone(ZoneId.systemDefault()).toLocalDateTime()

private val Clips.Row.id get() = image ?: text

/**
 * Puts a clip back on the clipboard, marked as seen so the keyboard doesn't keep it again as something new.
 */
private fun put(context: Context, clips: Clips, row: Clips.Row) {
    val clipboard = context.getSystemService(ClipboardManager::class.java)
    clipboard.setPrimaryClip(row.image?.let(clips::clip) ?: ClipData.newPlainText("iikb", row.text))
    clipboard.primaryClipDescription?.timestamp?.let { Settings(context).preferences.edit().putLong(IikbService.SEEN_CLIP, it).apply() }
}

/**
 * Keeps what's on the clipboard when iikb comes forward, as the keyboard does, once the keyboard has started the history:
 * Android lets an app read the clipboard only while it's in front. What an app marks sensitive is never kept.
 */
fun keepCopied(context: Context) {
    if (!File(context.filesDir, "clipboard.json").exists()) return
    val clipboard = context.getSystemService(ClipboardManager::class.java)
    val clip = runCatching { clipboard.primaryClip }.getOrNull() ?: return
    val preferences = Settings(context).preferences
    val time = clip.description.timestamp
    if (time <= preferences.getLong(IikbService.SEEN_CLIP, 0)) return
    preferences.edit().putLong(IikbService.SEEN_CLIP, time).apply()
    if (clip.description.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) == true) return
    Clips.of(context).keep(clip, time / 1000.0)
}

/** An image clip through the share sheet, readable by the app it goes to. */
private fun shareImage(context: Context, clips: Clips, image: String) {
    val send = Intent(Intent.ACTION_SEND).setType(Clips.type(image)).putExtra(Intent.EXTRA_STREAM, clips.uri(image))
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    send.clipData = clips.clip(image)
    context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

private val clock = DateTimeFormatter.ofPattern("h:mm a")
private val dated = DateTimeFormatter.ofPattern("MMM d, h:mm a")

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ClipRow(row: Clips.Row, copied: Boolean, clips: Clips, copy: (Clips.Row) -> Unit) {
    val palette = palette()
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 56.dp).combinedClickable(onLongClick = { menu = true }) { copy(row) }
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                if (row.image != null) ClipImage(row.image, Modifier.size(64.dp), 8.dp) else Title(row)
                if (copied) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(glyph("M6 12.5l4 4L18 8", 2.4f), null, tint = palette.secondary, modifier = Modifier.size(14.dp))
                        Text("Copied", color = palette.secondary, fontSize = 13.sp)
                    }
                } else {
                    val time = row.time().format(if (row.pinned) dated else clock)
                    Text(listOfNotNull(time, row.length).joinToString(" · "), color = palette.secondary, fontSize = 13.sp, maxLines = 1)
                }
            }
            if (row.pinned) Icon(glyph(Glyphs.PIN, 1.9f), "Pinned", tint = palette.secondary, modifier = Modifier.size(15.dp))
        }
        Actions(row, menu, { menu = false }, clips, copy)
    }
}

/** A row's text by its kind: an address or a phone number after its glyph, a color after a swatch of it, else up to four lines. */
@Composable
private fun Title(row: Clips.Row) {
    val palette = palette()
    val plain = row.text.take(300).trim()
    when (row.kind) {
        "email", "phone" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(
                glyph(if (row.kind == "email") Glyphs.ENVELOPE else Glyphs.PHONE, 1.8f), null, tint = palette.secondary,
                modifier = Modifier.size(20.dp),
            )
            Text(plain, color = palette.label, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        "color" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(
                Modifier.size(20.dp).background(Color(row.color ?: 0), CircleShape)
                    .border(BorderStroke(1.dp, palette.edge), CircleShape),
            )
            Text(plain.uppercase(), color = palette.label, fontSize = 17.sp, fontFamily = FontFamily.Monospace, maxLines = 1)
        }
        else -> Text(plain, color = palette.label, fontSize = 17.sp, lineHeight = 22.sp, maxLines = 4, overflow = TextOverflow.Ellipsis)
    }
}

/** A copied link in one line, as the keyboard's badge has it: the site's icon on a white tile, its name and how long ago. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Badge(row: Clips.Row, copied: Boolean, clips: Clips, copy: (Clips.Row) -> Unit) {
    val palette = palette()
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.height(34.dp).clip(CircleShape).background(palette.card).border(BorderStroke(1.dp, palette.edge), CircleShape)
                .combinedClickable(onLongClick = { menu = true }) { copy(row) }.padding(start = 8.dp, end = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(
                Modifier.size(20.dp).clip(RoundedCornerShape(5.dp)).background(Color.White)
                    .border(0.5.dp, Color(0x22000000), RoundedCornerShape(5.dp)),
                contentAlignment = Alignment.Center,
            ) { SiteIcon(row.site) }
            Text(row.name ?: row.site ?: "", color = palette.label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            if (copied) {
                Icon(glyph("M6 12.5l4 4L18 8", 2.4f), "Copied", tint = palette.secondary, modifier = Modifier.size(14.dp))
            } else {
                Text("· ${row.age}", color = palette.secondary, fontSize = 15.sp, maxLines = 1)
            }
            if (row.pinned) Icon(glyph(Glyphs.PIN, 1.9f), "Pinned", tint = palette.secondary, modifier = Modifier.size(12.dp))
        }
        Actions(row, menu, { menu = false }, clips, copy)
    }
}

/** What holding a clip offers: Copy, Open for a link, Share, Pin or Unpin, and Delete. */
@Composable
private fun Actions(row: Clips.Row, open: Boolean, close: () -> Unit, clips: Clips, copy: (Clips.Row) -> Unit) {
    val palette = palette()
    val context = LocalContext.current
    DropdownMenu(open, close, containerColor = palette.card) {
        val item = @Composable { title: String, color: Color, action: () -> Unit ->
            DropdownMenuItem({ Text(title, color = color) }, {
                close()
                action()
            })
        }
        item("Copy", palette.label) { copy(row) }
        if (row.kind == "link") {
            item("Open", palette.label) {
                runCatching {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(row.text.trim())).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
        }
        item("Share", palette.label) { row.image?.let { shareImage(context, clips, it) } ?: share(context, row.text) }
        item(if (row.pinned) "Unpin" else "Pin", palette.label) { clips.pin(row, !row.pinned) }
        item("Delete", palette.red) { clips.remove(row) }
    }
}
