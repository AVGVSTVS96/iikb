package com.shahidy.iikb.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.BorderStroke
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.shahidy.iikb.Transcripts
import com.shahidy.iikb.app.stats.StatsSection
import com.shahidy.iikb.keyboard.Clips
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * iikb's home (docs/design.md, "The app"): the microphone's switch beside the title, a field to try iikb, what's left
 * to set up, a card of what iikb has gathered, each count opening its tab, and a card for each setting reached for
 * most, opening its page in Settings.
 */
@Composable
fun Home(open: (String) -> Unit, show: (Tab, StatsSection?) -> Unit) {
    val palette = palette()
    val access = LocalAccess.current
    val focus = LocalFocusManager.current
    var typing by remember { mutableStateOf(false) }
    Page(
        "iikb",
        actions = {
            if (typing) {
                Text(
                    "Done", color = palette.accent, fontSize = Type.body, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.cardPress { focus.clearFocus() }.padding(horizontal = 12.dp, vertical = 10.dp),
                )
            }
            MicSwitch()
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            TryField { typing = it }
            Box(Modifier.height(4.dp))
            Counts(show)
            if (!access.setup.done) Section("Set Up") { SetupSteps() }
            ShortcutCards(open)
        }
    }
}

/**
 * Whether voice typing may use the microphone, at the bar's trailing edge. On, the keyboard's mic records right where
 * you type; off, it can't hear you until you turn it on here, and what you're saying when you turn it off is written
 * down. Android's mic is on only while you talk, so there's nothing to keep on between dictations, as iOS's switch does.
 */
@Composable
private fun MicSwitch() {
    val store = LocalStore.current
    val access = LocalAccess.current
    val palette = palette()
    val on = store.bool(MIC_ON) && access.setup.microphone
    Row(
        Modifier.height(44.dp).clip(CircleShape).background(palette.card).border(BorderStroke(1.dp, palette.edge), CircleShape)
            .padding(start = 5.5.dp, end = 11.5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(38.dp), contentAlignment = Alignment.Center) {
            Icon(
                Symbols[if (on) "mic" else "mic.slash"], if (on) "Microphone on" else "Microphone off",
                tint = if (on) palette.green else palette.label, modifier = Modifier.size(22.dp),
            )
        }
        Box(Modifier.padding(start = 4.dp)) {
            Switch(on) {
                store.set(MIC_ON, it)
                if (it && !access.setup.microphone) access.microphone()
            }
        }
    }
}

/** The microphone's switch, kept for voice typing to read (`Settings`); on unless you turn it off. */
const val MIC_ON = "micOn"

/** The field to try iikb in; its keys put away by Done, a tap beside it or scrolling. */
@Composable
private fun TryField(typing: (Boolean) -> Unit) {
    val palette = palette()
    var text by rememberSaveable { mutableStateOf("") }
    BasicTextField(
        text, { text = it },
        textStyle = TextStyle(color = palette.label, fontSize = Type.title3),
        cursorBrush = SolidColor(palette.accent),
        modifier = Modifier.fillMaxWidth().heightIn(min = 150.dp).card().onFocusChanged { typing(it.isFocused) }
            .padding(horizontal = 19.dp, vertical = 16.dp),
        decorationBox = { inner ->
            if (text.isEmpty()) Text("Type something with iikb", color = palette.secondary, fontSize = Type.title3)
            inner()
        },
    )
}

/** One of Home's counts, opening the tab that keeps it. */
private class Count(
    val symbol: String, val color: Color, val value: Int, val label: String, val title: String, val tab: Tab,
    val section: StatsSection? = null,
)

/**
 * What iikb has gathered, in one card: words said today, what's in the clipboard and taps learned. Three across while
 * every count fits at full size, then smaller, then a row each, so a count never runs out of its card.
 */
@Composable
private fun Counts(show: (Tab, StatsSection?) -> Unit) {
    val context = LocalContext.current
    val palette = palette()
    val clips = remember { Clips.of(context) }
    var revision by remember { mutableIntStateOf(0) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(clips, lifecycle) {
        val changed: () -> Unit = { revision++ }
        clips.listen(changed)
        val stop = Transcripts.listen(changed)
        val resumed = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) changed() }
        lifecycle.addObserver(resumed)
        onDispose {
            clips.stopListening(changed)
            stop()
            lifecycle.removeObserver(resumed)
        }
    }
    val counts = remember(revision) {
        val today = LocalDate.now()
        val words = Transcripts.list().takeWhile {
            Instant.ofEpochMilli((it.date * 1000).toLong()).atZone(ZoneId.systemDefault()).toLocalDate() == today
        }.sumOf { it.words }
        val taps = Core.taps(context)
        listOf(
            Count("text.bubble.fill", Hues.pink, words, "said today", if (words == 1) "Word said today" else "Words said today", Tab.TRANSCRIPTS),
            Count("list.clipboard.fill", Hues.orange, clips.rows().size, "in clipboard", "In clipboard", Tab.CLIPBOARD),
            Count("hand.tap.fill", Hues.blue, taps, if (taps == 1) "tap learned" else "taps learned", if (taps == 1) "Tap learned" else "Taps learned", Tab.STATS, StatsSection.TAPS),
        )
    }
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val column = (maxWidth - 2.dp) / 3
        val fits = { size: Int ->
            counts.all { count ->
                val number = measurer.measure("%,d".format(count.value), TextStyle(fontSize = size.sp, fontWeight = FontWeight.Bold)).size.width
                val label = measurer.measure(count.label, TextStyle(fontSize = Type.subheadline)).size.width
                with(density) { maxOf(number, label).toDp() } + 36.dp <= column
            }
        }
        val size = listOf(28, 24).firstOrNull(fits)
        if (size != null) {
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).card()) {
                counts.forEachIndexed { index, count ->
                    if (index > 0) Box(Modifier.padding(vertical = 18.dp).width(1.dp).fillMaxHeight().background(palette.divider))
                    Column(
                        Modifier.weight(1f).cardPress { show(count.tab, count.section) }.padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Glyph(count.symbol, count.color, 34.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                "%,d".format(count.value), color = palette.label, fontSize = size.sp, fontWeight = FontWeight.Bold,
                                letterSpacing = (-0.02).em, maxLines = 1,
                            )
                            Text(count.label, color = palette.secondary, fontSize = Type.subheadline, maxLines = 1)
                        }
                    }
                }
            }
        } else {
            Section {
                counts.forEachIndexed { index, count ->
                    if (index > 0) Divider()
                    Row(
                        Modifier.cardPress { show(count.tab, count.section) }.row(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Glyph(count.symbol, count.color, 28.dp)
                        Text(count.title, color = palette.label, fontSize = Type.body, maxLines = 1, modifier = Modifier.weight(1f))
                        Text("%,d".format(count.value), color = palette.label, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

/** The settings pages Home links straight to, voice typing's first, each showing what it's set to, two across. */
@Composable
private fun ShortcutCards(open: (String) -> Unit) {
    val pages = listOf(
        SettingsPage.DICTIONARY, SettingsPage.WRITING, SettingsPage.VOICE, SettingsPage.APPEARANCE, SettingsPage.TYPING,
        SettingsPage.FEEDBACK,
    )
    for (row in pages.chunked(2)) {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            for (page in row) {
                Tile(
                    page.symbol, page.hue, page.title, page.value(),
                    Modifier.weight(1f).fillMaxHeight().cardPress { open(page.id) },
                )
            }
        }
    }
}
