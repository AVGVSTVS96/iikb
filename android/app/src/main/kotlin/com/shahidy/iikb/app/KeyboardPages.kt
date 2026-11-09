package com.shahidy.iikb.app

import android.content.Intent
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.shahidy.iikb.folds
import com.shahidy.iikb.keyboard.Feedback
import com.shahidy.iikb.keyboard.Frame
import com.shahidy.iikb.keyboard.KeyboardView
import com.shahidy.iikb.keyboard.Keycaps
import com.shahidy.iikb.keyboard.Native
import kotlin.math.roundToInt

/** iikb as it will look, over a pill that brings up the real keyboard in a field, so a change can be tried at once. */
@Composable
fun TryPreview() {
    val palette = palette()
    var trying by remember { mutableStateOf(false) }
    AnimatedContent(trying, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "try") { field ->
        if (field) {
            var text by remember { mutableStateOf("") }
            val focus = remember { FocusRequester() }
            var focused by remember { mutableStateOf(false) }
            LaunchedEffect(Unit) { focus.requestFocus() }
            BasicTextField(
                text, { text = it },
                textStyle = TextStyle(color = palette.label, fontSize = Type.title3),
                cursorBrush = SolidColor(palette.accent), minLines = 3, maxLines = 6,
                modifier = Modifier.fillMaxWidth().card().padding(18.dp).focusRequester(focus).onFocusChanged {
                    if (focused && !it.isFocused) trying = false
                    focused = it.isFocused
                },
                decorationBox = { inner ->
                    if (text.isEmpty()) Text("Type to try iikb", color = palette.secondary, fontSize = Type.title3)
                    inner()
                },
            )
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                KeyboardPreview { trying = true }
                Text(
                    "Tap to try", color = palette.label, fontSize = Type.subheadline, fontWeight = FontWeight.Medium,
                    modifier = Modifier.clip(CircleShape).background(palette.card).border(BorderStroke(1.dp, palette.edge), CircleShape)
                        .cardPress { trying = true }.padding(horizontal = 18.dp, vertical = 9.dp),
                )
            }
        }
    }
}

/**
 * iikb drawn as its settings make it, by the keyboard's own view, from a keyboard of its own with an empty field
 * (`Core.preview`), redrawn as a setting changes, inset in its card as iOS's preview is.
 */
@Composable
private fun KeyboardPreview(onTap: () -> Unit) {
    val context = LocalContext.current
    val store = LocalStore.current
    val palette = palette()
    val dark = isSystemInDarkTheme()
    val handle = remember { Core.preview(context) }
    DisposableEffect(handle) { onDispose { Native.destroy(handle) } }
    val shape = RoundedCornerShape(26.dp)
    val metrics = context.resources.displayMetrics
    val screen = metrics.widthPixels / metrics.density.toDouble() to metrics.heightPixels / metrics.density.toDouble()
    val lines = store.lines()
    val frame = remember(lines, dark) {
        Native.configure(handle, lines.encodeToByteArray())
        Native.place(handle, screen.first, screen.first, screen.second, context.folds(), 0.0, dark, false)
        Native.suggestionJob(handle).takeIf { it != 0L }?.let { job ->
            Native.runJob(job)
            Native.finishJob(handle, job)
        }
        Frame.parse(Native.frame(handle))
    }
    Box(
        Modifier.fillMaxWidth().clip(shape).background(Color(frame.theme.card)).border(BorderStroke(1.dp, palette.edge), shape)
            .padding(start = 8.dp, end = 8.dp, top = 4.dp, bottom = 10.dp),
    ) {
        Scaled(screen.first.toFloat()) { AndroidView({ KeyboardView(it, Still) }, update = { it.frame = frame }) }
        Box(Modifier.matchParentSize().clickable(remember { MutableInteractionSource() }, null, onClick = onTap))
    }
}

/**
 * `content` laid out `width` dp wide, as the keyboard is across the screen, and drawn scaled down to the width it's
 * given, as iOS's `KeyboardPreviewView` draws the keys, so the preview's keys sit as the keyboard's do.
 */
@Composable
private fun Scaled(width: Float, content: @Composable () -> Unit) {
    Layout(content) { measurables, constraints ->
        val scale = constraints.maxWidth / (width * density)
        val child = measurables.first().measure(Constraints.fixedWidth((width * density).roundToInt()))
        layout(constraints.maxWidth, (child.height * scale).roundToInt()) {
            child.placeWithLayer(0, 0) {
                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(0f, 0f)
            }
        }
    }
}

/** The preview only draws: its touches go to the box over it. */
private object Still : KeyboardView.Actions {
    override fun down(index: Int, taps: Int) {}
    override fun up(index: Int) {}
    override fun type(index: Int, text: String, x: Double, y: Double) {}
    override fun trigger(index: Int) {}
    override fun slide(text: String) {}
    override fun swipe(path: List<KeyboardView.SwipePoint>) {}
    override fun cursor(step: Int) {}
    override fun advance(step: Int) = 1f
    override fun menu(item: Int) {}
    override fun select(slot: Int) {}
    override fun acceptEmoji(emoji: String) {}
    override fun more() {}
    override fun mic() {}
    override fun chat(index: Int) {}
    override fun expand() {}
    override fun cancelDictation() {}
    override fun dismissHint() {}
    override fun repeatDelete(words: Boolean) {}
    override fun feedback(kind: Feedback.Kind) {}
    override fun pickEmoji(emoji: String, base: String?) {}
    override fun closePanel() {}
    override fun clearSearch() {}
    override fun edit(name: String) {}
    override fun emojiResults() = emptyList<String>()
    override fun tones(emoji: String) = emptyList<String>()
}

/** Everything about how the keyboard looks, on one page: its theme, what a pressed key shows, and how its keys are laid out. */
@Composable
fun Appearance() {
    val context = LocalContext.current
    val here = remember { Core.keysHere(context) }
    ThemeSettings()
    if (here.characterPreview) CharacterPreviewPicker()
    Section("Stop Animation", "How the recording goes back into the mic when you stop dictating.") {
        Choices(
            "stopAnimation", STOP_ANIMATIONS,
            mapOf(
                "squeeze" to "The bars rush into the mic, which circles while it writes.",
                "drain" to "The red drains into the mic, which glows while it writes.",
                "card" to "The recording folds into a card and lifts away.",
            ),
        )
    }
    LayoutSettings(here)
}

@Composable
private fun ThemeSettings() {
    val store = LocalStore.current
    val dark = isSystemInDarkTheme()
    val theme = store.string("theme")
    val hasAppearance = theme in setOf("physical", "mechanical")
    Section("Theme", if (hasAppearance) "Automatic follows the app you’re typing in, light or dark." else null) {
        THEMES.forEachIndexed { index, (name, title) ->
            if (index > 0) Divider()
            ChoiceRow(title, THEME_DETAILS[name], theme == name) { store.set("theme", name) }
            if (theme == name && hasAppearance) {
                Row(Modifier.fillMaxWidth().padding(vertical = 16.dp, horizontal = 8.dp)) {
                    for ((appearance, label) in APPEARANCES) {
                        Column(
                            Modifier.weight(1f).clickable(remember { MutableInteractionSource() }, null) {
                                store.set("themeAppearance", appearance)
                            },
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Box(Modifier.size(100.dp, 54.dp)) { Keycaps(name, appearance, dark) }
                            Text(label, color = palette().label, fontSize = Type.subheadline)
                            Radio(store.string("themeAppearance") == appearance)
                        }
                    }
                }
            }
        }
    }
}

/** What shows above a key as you press it, each choice drawn. */
@Composable
private fun CharacterPreviewPicker() {
    val store = LocalStore.current
    Section("Character Preview") {
        Row(Modifier.fillMaxWidth().padding(vertical = 18.dp, horizontal = 8.dp), verticalAlignment = Alignment.Bottom) {
            for ((preview, title) in CHARACTER_PREVIEWS) {
                Column(
                    Modifier.weight(1f).clickable(remember { MutableInteractionSource() }, null) {
                        store.set("characterPreviewStyle", preview)
                    },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    PreviewDrawing(preview)
                    Text(title, color = palette().label, fontSize = Type.subheadline)
                    Radio(store.string("characterPreviewStyle") == preview)
                }
            }
        }
    }
}

/** A key and what pressing it shows above it, drawn small, as Raycast's picker draws them. */
@Composable
private fun PreviewDrawing(preview: String) {
    val palette = palette()
    val key = palette.secondary.copy(alpha = 0.45f)
    val bubble = palette.secondary.copy(alpha = 0.7f)
    val letter = @Composable { size: Int -> Text("q", color = palette.label, fontSize = size.sp) }
    Box(Modifier.height(90.dp), contentAlignment = Alignment.BottomCenter) {
        when (preview) {
            "none" -> Box(Modifier.size(38.dp, 40.dp).background(key, RoundedCornerShape(7.dp)), Alignment.Center) { letter(17) }
            "detached" -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Box(Modifier.size(52.dp, 42.dp).background(bubble, RoundedCornerShape(9.dp)), Alignment.Center) { letter(20) }
                Box(Modifier.size(38.dp, 40.dp).background(key, RoundedCornerShape(7.dp)), Alignment.Center) { letter(17) }
            }
            else -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier.size(52.dp, 48.dp).background(bubble, RoundedCornerShape(topStart = 9.dp, topEnd = 9.dp)),
                    Alignment.TopCenter,
                ) { Box(Modifier.padding(top = 10.dp)) { letter(20) } }
                Box(
                    Modifier.size(38.dp, 40.dp).background(bubble, RoundedCornerShape(bottomStart = 7.dp, bottomEnd = 7.dp)),
                )
            }
        }
    }
}

@Composable
private fun LayoutSettings(here: Core.KeysHere) {
    Section("Size and Shape", "Less space between the keys makes them bigger. The keyboard stays the same size.") {
        Stops("Space Between Keys", "keySpacing", SPACING, "Bigger Keys", "More Space")
        Divider()
        Stops("Corners", "keyRoundness", ROUNDNESS, "Sharper", "Rounder")
    }
    if (here.numberRow || here.emojiKey || here.recordKey) {
        Section("Keys") {
            val rows = buildList<@Composable () -> Unit> {
                if (here.numberRow) add { Toggle("Number Row", "numberRow", "1 to 0 above the letters. The keyboard grows upward.") }
                if (here.emojiKey) {
                    add {
                        Toggle(
                            "Emoji Key", "emojiKey",
                            "Every emoji, from beside the space bar. Without it, a word’s emoji still show in the suggestions.",
                        )
                    }
                }
                if (here.recordKey) {
                    add {
                        Toggle(
                            "Record Key", "micKey",
                            "The record button left of 123, instead of at the right of the bar.",
                        )
                    }
                }
            }
            rows.forEachIndexed { index, row ->
                if (index > 0) Divider()
                row()
            }
        }
    }
    Section("Emoji, GIFs and Clipboard") {
        MenuRow("Skin Tone", "skinTone", SKIN_TONES)
        if (here.largePanels) {
            Divider()
            Toggle(
                "Compact Emoji & GIFs", "compactPanels",
                "One row that scrolls sideways, as in landscape, so the keyboard stays short in portrait too.",
            )
        }
        Divider()
        MenuRow("Clipboard Length", "clipboardLength", listOf("characters" to "Characters", "words" to "Words"))
    }
    if (here.split || here.oneHanded) {
        Section(
            "Split and One-Handed",
            if (here.split) {
                "Split puts half the keys under each thumb on an open foldable in landscape. One-Handed moves them toward one thumb in portrait. The keyboard’s menu has both too."
            } else {
                "One-Handed moves the keys toward one thumb in portrait. The keyboard’s menu has it too."
            },
        ) {
            if (here.split) {
                Toggle("Split Keyboard", "split")
                Divider()
            }
            MenuRow("One-Handed Keyboard", "oneHanded", listOf("off" to "Off", "left" to "Left", "right" to "Right"))
        }
    }
    if (here.keyboardMenu) {
        val store = LocalStore.current
        val hold = store.string("keyboardMenu") == "hold"
        Section(
            "Keyboard Menu",
            "Layouts and iikb Settings open from holding 123 or emoji and sliding. The menu button above the keys opens your clipboard, transcripts, GIFs and chats.",
        ) {
            ChoiceRow("Hold 123 and Menu Button", picked = !hold) { store.set("keyboardMenu", "both") }
            Divider()
            ChoiceRow("Hold 123", picked = hold) { store.set("keyboardMenu", "hold") }
        }
    }
}

/** What typing does to your text. */
@Composable
fun Typing() {
    Section(
        footer = "Predictive Text shows three suggestions above the keys, and the next word before you type it. Slide to Type types a word as you swipe across its letters.",
    ) {
        Toggle("Auto-Capitalization", "autoCapitalization")
        Divider()
        Toggle("Auto-Correction", "autoCorrection")
        Divider()
        Toggle("Predictive Text", "predictiveText")
        Divider()
        Toggle("Slide to Type", "slideToType")
    }
    Section(footer = "Smart Punctuation curls quotes and turns two hyphens into a dash.") {
        Toggle("Smart Punctuation", "smartPunctuation")
        Divider()
        Toggle("Enable Caps Lock", "capsLock", "Double-tap shift.")
        Divider()
        Toggle("“.” Shortcut", "periodShortcut", "Double-tap space for a period and a space.")
    }
    TextReplacements()
}

/**
 * Android keeps text replacements as shortcuts in its personal dictionary, which iikb reads as each field opens, as
 * iOS's keyboard reads General › Keyboard › Text Replacement. Shown where the phone has the page to add them.
 */
@Composable
private fun TextReplacements() {
    val context = LocalContext.current
    val open = remember { Intent(android.provider.Settings.ACTION_USER_DICTIONARY_SETTINGS) }
    if (open.resolveActivity(context.packageManager) == null) return
    Section("Text Replacements") {
        Line(
            "Open Personal Dictionary",
            "iikb types each word you give a shortcut there, and keeps the others as your own words.",
            onClick = { context.startActivity(open) },
        ) { Trailing("arrow.up.forward") }
    }
}

/** How a press feels: Key Haptics with its strength, kept while haptics are off, then Sound. */
@Composable
fun Feedback() {
    val store = LocalStore.current
    val context = LocalContext.current
    val view = LocalView.current
    val haptics = remember { Feedback(context, view).apply { sound = false } }
    Section("Haptics", "Standard is the keyboard’s own tap. Each step taps as you pick it.") {
        Toggle("Key Haptics", "haptics.on")
        if (store.bool("haptics.on")) {
            Divider()
            Stops("Strength", "haptics.strength", HAPTICS, "Lighter", "Stronger") { picked ->
                haptics.strength = picked
                haptics.play(Feedback.Kind.INPUT)
            }
        }
    }
    Section {
        Toggle("Sound", "sound", "The key click, while the phone isn’t on silent or vibrate.")
    }
}

val THEMES = listOf(
    "standard" to "Default", "clear" to "Clear", "physical" to "Physical", "mechanical" to "Mechanical",
    "classic" to "iOS 5",
)
private val THEME_DETAILS = mapOf(
    "standard" to "iikb’s own keys, flat, as iOS 27 draws them.",
    "clear" to "Only the letters, no keys around them.",
    "physical" to "Solid keys, dark or light.",
    "mechanical" to "Raised keycaps you can almost press.",
    "classic" to "The glossy keyboard of 2011.",
)
private val APPEARANCES = listOf("automatic" to "Automatic", "dark" to "Dark", "light" to "Light")
private val CHARACTER_PREVIEWS = listOf("none" to "None", "detached" to "Detached", "attached" to "Attached")
private val STOP_ANIMATIONS = listOf("squeeze" to "Squeeze", "drain" to "Drain", "card" to "Card")
val SPACING = listOf("tighter" to "Tighter", "tight" to "Tight", "standard" to "Standard", "roomy" to "Roomy", "roomier" to "Roomier")
val ROUNDNESS = listOf("sharper" to "Sharper", "sharp" to "Sharp", "standard" to "Standard", "round" to "Round", "rounder" to "Rounder")
val HAPTICS = listOf(
    "lightest" to "Lightest", "lighter" to "Lighter", "light" to "Light", "standard" to "Standard", "strong" to "Strong",
    "stronger" to "Stronger", "strongest" to "Strongest",
)
private val SKIN_TONES = listOf(
    "" to "✋ Default", "light" to "✋🏻 Light", "mediumLight" to "✋🏼 Medium Light", "medium" to "✋🏽 Medium",
    "mediumDark" to "✋🏾 Medium Dark", "dark" to "✋🏿 Dark",
)
