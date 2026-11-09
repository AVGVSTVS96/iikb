package com.shahidy.iikb.app.stats

import android.net.Uri
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import com.shahidy.iikb.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.ThisDevice
import com.shahidy.iikb.Transcript
import com.shahidy.iikb.Transcripts
import com.shahidy.iikb.TypingStats
import com.shahidy.iikb.app.FormField
import com.shahidy.iikb.app.LocalResumes
import com.shahidy.iikb.app.MicSwitch
import com.shahidy.iikb.app.Page
import com.shahidy.iikb.app.Section
import com.shahidy.iikb.app.Sheet
import com.shahidy.iikb.app.row
import com.shahidy.iikb.app.design.isDark
import com.shahidy.iikb.app.Symbols
import com.shahidy.iikb.app.Type
import com.shahidy.iikb.app.design.SectionPills
import com.shahidy.iikb.app.glass
import com.shahidy.iikb.app.palette
import com.shahidy.iikb.app.transcripts.copy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

enum class StatsSection(val title: String) { OVERVIEW("Overview"), TYPING("Typing"), DICTATION("Dictation"), TAPS("Taps") }

/**
 * How you type and talk, and where your taps land, on this phone or on a computer you added (docs/computers.md), each
 * apart: Overview, Typing, Dictation and Taps as pills under the title, the device in a menu at the pills' end where it
 * fits (an open foldable, a tablet), else in the bar beside the mic switch. A computer shows once it has answered.
 */
@Composable
fun StatsPage(section: StatsSection, pick: (StatsSection) -> Unit, computer: String?, pickComputer: (String?) -> Unit) {
    val context = LocalContext.current
    val resumes = LocalResumes.current
    val computers = remember { Computers.of(context) }
    val (activity, transcripts) = phoneActivity()
    var adding by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(resumes) { computers.read() }
    val shown = computer?.takeIf { it in computers.activity }
    val sections = if (shown == null) StatsSection.entries else StatsSection.entries - StatsSection.TAPS
    val picked = section.takeIf { it in sections } ?: StatsSection.OVERVIEW
    val menu = @Composable { inRow: Boolean ->
        Devices(shown, computers, inRow, pickComputer, add = { adding = true }) {
            pickComputer(null)
            computers.remove(it)
        }
    }
    BoxWithConstraints {
        val inRow = pillsWidth(sections) + 150.dp <= maxWidth - 32.dp
        key(picked, shown) {
            Page(
                "Stats",
                pinned = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SectionPills(sections, picked, { it.title }, pick)
                        if (inRow) {
                            Spacer(Modifier.weight(1f))
                            menu(true)
                        }
                    }
                },
                actions = {
                    if (!inRow) {
                        menu(false)
                        Spacer(Modifier.width(8.dp))
                    }
                    MicSwitch()
                },
            ) {
                Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    val device = shown?.let { computers.activity.getValue(it) } ?: activity
                    when (picked) {
                        StatsSection.OVERVIEW -> Overview(device, shown)
                        StatsSection.TYPING -> DeviceStats(Kind.TYPED, device, transcripts, shown)
                        StatsSection.DICTATION -> DeviceStats(Kind.SAID, device, transcripts, shown)
                        StatsSection.TAPS -> Taps()
                    }
                }
            }
        }
    }
    if (adding) {
        AddComputer(close = { adding = false }) {
            adding = false
            pickComputer(it.name)
        }
    }
}

/** How wide the pills lie at their own size, as iOS measures them to tell whether the device menu fits beside them. */
@Composable
private fun pillsWidth(sections: List<StatsSection>): androidx.compose.ui.unit.Dp {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Medium)
    return with(density) { sections.sumOf { measurer.measure(it.title, style).size.width }.toDp() } +
        26.dp * sections.size + 2.dp * (sections.size - 1)
}

/**
 * The device Stats shows, picked from a menu: this phone and each computer, then Add Computer and, for a computer,
 * Forget. In the bar it's a glass circle of the device's glyph; at the pills' end, its glyph and name in their look.
 */
@Composable
private fun Devices(
    computer: String?, computers: Computers, inRow: Boolean, pick: (String?) -> Unit, add: () -> Unit, forget: (String) -> Unit,
) {
    val palette = palette()
    var open by remember { mutableStateOf(false) }
    val symbol = if (computer == null) "iphone" else "laptopcomputer"
    Box {
        if (inRow) {
            PillMenuLabel(symbol, computer ?: ThisDevice.NAME, Modifier.clip(CircleShape).clickable { open = true })
        } else {
            Box(
                Modifier.size(44.dp).glass(CircleShape).clip(CircleShape).clickable { open = true },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Symbols.hierarchical(symbol), computer ?: ThisDevice.NAME, tint = palette.label,
                    modifier = Modifier.size(if (computer == null) 33.dp else 30.7.dp),
                )
            }
        }
        DropdownMenu(
            open, { open = false }, Modifier.background(palette.card), shape = RoundedCornerShape(14.dp),
            containerColor = palette.card,
        ) {
            val item = @Composable { title: String, glyph: String, color: Color, checked: Boolean, onClick: () -> Unit ->
                DropdownMenuItem(
                    text = { Text(title, color = color, fontSize = Type.body) },
                    leadingIcon = {
                        Box(Modifier.width(18.dp)) {
                            if (checked) Icon(Symbols["checkmark"], null, tint = palette.label, modifier = Modifier.size(15.dp))
                        }
                    },
                    trailingIcon = { Icon(Symbols[glyph], null, tint = color, modifier = Modifier.size(22.dp)) },
                    onClick = {
                        open = false
                        onClick()
                    },
                )
            }
            item(ThisDevice.NAME, "iphone", palette.label, computer == null) { pick(null) }
            for (each in computers.all) item(each.name, "laptopcomputer", palette.label, computer == each.name) { pick(each.name) }
            HorizontalDivider(color = palette.divider)
            item("Add Computer…", "plus", palette.label, false, add)
            if (computer != null) item("Forget $computer", "trash", palette.red, false) { forget(computer) }
        }
    }
}

/** How to share a Mac's stats, and a field for the link it shows, for when the camera can't open its QR code. */
@Composable
private fun AddComputer(close: () -> Unit, added: (Computer) -> Unit) {
    val context = LocalContext.current
    val palette = palette()
    var link by rememberSaveable { mutableStateOf("") }
    val computer = Computer.of(Uri.parse(link.trim()))
    Sheet(
        "Add Computer", "Add", computer != null, close,
        confirm = {
            if (computer != null) {
                Computers.of(context).add(computer)
                added(computer)
            }
        },
    ) {
        Section(
            "On your Mac",
            "Run this in Terminal with Keystroke counting there. It shows a QR code: scan it with your phone’s camera. " +
                "With Tailscale on both, iikb reaches the Mac anywhere; without it, on the same Wi‑Fi.",
        ) {
            Row(Modifier.row(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    COMMAND.breakingAfterSlashes(), color = palette.label, fontSize = Type.footnote, fontFamily = Type.mono,
                    letterSpacing = 0.sp, modifier = Modifier.weight(1f),
                )
                CopyButton(COMMAND)
            }
        }
        Section(
            footer = if (link.isEmpty() || computer != null) {
                "Or paste the link it shows."
            } else {
                "That isn’t a computer’s link: it starts with iikb://computer."
            },
        ) {
            FormField(link, "iikb://computer?…", KeyboardOptions(KeyboardCapitalization.None, false, KeyboardType.Uri)) { link = it }
        }
    }
}

private const val COMMAND = "curl -fsSL https://raw.githubusercontent.com/AVGVSTVS96/iikb/main/mac/share | sh"

/** An address free to wrap after each slash, where iOS wraps one, as Android otherwise keeps it whole or breaks before them. */
private fun String.breakingAfterSlashes() = replace(Regex("/(?!/)"), "/\u200B")

/**
 * Copy as iOS's `CopyButton`: once it's copied the glyph shrinks away as a green check springs in on a green disc and
 * "Copied" slides out beside it, then it all settles back.
 */
@Composable
private fun CopyButton(text: String) {
    val palette = palette()
    val context = LocalContext.current
    var copies by remember { mutableIntStateOf(0) }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copies) {
        if (copies == 0) return@LaunchedEffect
        copied = true
        delay(1600)
        copied = false
    }
    val done by animateFloatAsState(if (copied) 1f else 0f, label = "copied")
    val green = if (palette.isDark) palette.green else Color(0xFF248A3D)
    Box(contentAlignment = Alignment.Center) {
        Box(
            Modifier.size(34.dp).clip(CircleShape).clickable {
                copy(context, text)
                copies++
            },
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(34.dp).scale(0.4f + 0.6f * done).clip(CircleShape).background(palette.green.copy(alpha = done)))
            Icon(
                Symbols["doc.on.doc"], "Copy", tint = palette.label.copy(alpha = 1 - done),
                modifier = Modifier.size(23.dp).scale(1 - 0.5f * done),
            )
            Icon(Symbols["checkmark"], null, tint = Color.White.copy(alpha = done), modifier = Modifier.size(17.dp).scale(0.3f + 0.7f * done))
        }
        Text(
            "Copied", color = green.copy(alpha = done), fontSize = Type.subheadline, fontWeight = FontWeight.SemiBold, maxLines = 1,
            modifier = Modifier.layout { measurable, _ ->
                val label = measurable.measure(Constraints())
                val x = -label.width - (17 + 8).dp.roundToPx() + (10.dp.toPx() * (1 - done)).toInt()
                layout(0, 0) { label.place(x, -label.height / 2) }
            },
        )
    }
}

/**
 * The phone's typing, from the hours the keyboard keeps as it closes, and its dictation, from Transcripts: read again
 * each time either changes and each time the app comes forward.
 */
@Composable
fun phoneActivity(): Pair<Activity, List<Transcript>> {
    val context = LocalContext.current
    val resumes = LocalResumes.current
    val names = remember { AppNames(context) }
    var changes by remember { mutableIntStateOf(0) }
    var shown by remember { mutableStateOf(Activity() to Transcripts.list()) }
    DisposableEffect(Unit) {
        val typing = TypingStats.listen { changes++ }
        val transcripts = Transcripts.listen { changes++ }
        onDispose {
            typing()
            transcripts()
        }
    }
    LaunchedEffect(resumes, changes) {
        val transcripts = Transcripts.list()
        shown = withContext(Dispatchers.Default) { Activity.of(TypingStats.hours(), transcripts, names::of) } to transcripts
    }
    return shown
}
