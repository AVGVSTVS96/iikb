package com.shahidy.iikb.keyboard

import android.content.Context
import android.graphics.Paint
import android.os.Bundle
import android.view.View
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner

/**
 * What the keyboard shows in the keys' place (the menu, a panel opened from it) or in the bar's (that panel with the
 * keys up), drawn with Compose over [KeyboardView], which keeps drawing the bar and keys around it. Sizes are dp, and
 * text is dp too, as the keys' is, whatever the phone's font size.
 */
class Overlay(context: Context, private val actions: Actions, private val gifs: Gifs?, private val chats: Chats) {
    interface Actions {
        fun paste(text: String)
        /** An image clip picked, by its file (`Clips.Row.image`). */
        fun pasteImage(image: String)
        fun open(panel: String)
        fun back()
        fun raiseKeys()
        fun clearSearch()
        /** The app's Appearance page, from the names of the menu's Theme and Stop Animation rows. */
        fun appearance()
        /** A GIF tapped, found by `search`: it goes on the clipboard. */
        fun copyGif(gif: Gif, search: String)
        /** A held GIF moved: it lifts out of the keyboard to drop into the app's field as the GIF itself. */
        fun dragGif(gif: Gif, search: String)
        /** A chat picked on the menu's shelf: it opens, with its line in place of the app's field. */
        fun openChat(id: String)
        /** A chat's tab tapped, or picked from the tabs' menu, by its place in the list. */
        fun chat(index: Int)
        /** The chat's own More, beside its tabs: it closes the chat. */
        fun more()
        /** The chat's messages tapped with the keys up: they go down, so there's room to read. */
        fun browse()
        /** The message box's send: what's in the chat's line goes. */
        fun send()
        /** The message box's mic: a dictation into the chat's line starts or stops. */
        fun mic()
        /** A link in a message tapped, or Open Link picked: the phone opens it in its app for links. */
        fun openLink(url: String)
        /** Copy Link picked on a held link: it goes on the clipboard as text. */
        fun copyLink(url: String)
        /** Copy picked on a held photo in a chat: the file itself goes on the clipboard. */
        fun copyPhoto(url: String, type: String?)
    }

    /** An open chat's message line, which the keys type into, and its caret. */
    @kotlinx.serialization.Serializable
    data class Line(val text: String, val caret: Int)

    /** What's shown: the menu, or a panel by its KeyboardCore name, with its search and whether the keys are up. */
    data class State(
        val colors: Colors, val minX: Float, val maxX: Float, val panel: String?, val query: String, val keysUp: Boolean,
        val field: Float, val width: Float, val line: Line? = null,
        /** The menu has a Chats shelf: an extension is added, and the keyboard is a phone's width or more. */
        val chats: Boolean = false,
        /** The dictation's phase, `OFF`, `LISTENING` or `WRITING`, which a chat's own mic shows. */
        val mic: String = "OFF",
        /** The system's bar under the keyboard, which a held item's dimming stops at. */
        val bottom: Float = 0f,
        /** The bar's layout, where an open chat's tabs and More sit. */
        val toolbar: Bar? = null,
        /** The chats with something newer than this keyboard last showed, by their place in the list (`ChatSeen`). */
        val fresh: Set<Int> = emptySet(),
        /** The bar is compact (a short screen, landscape): a panel over the keys shows one row of results, as iOS's. */
        val compact: Boolean = false,
    ) {
        /** The space from the keys block's right edge to the keyboard's, which a panel keeps clear as on the left. */
        val endInset get() = width - maxX

        /**
         * Around a panel's results and search row: iOS's `PanelView.inset` above and below in the keys' place, or the
         * toolbar's top over results in the bar's.
         */
        val panelPadding get() = PaddingValues(
            start = minX.dp, end = endInset.dp, top = if (keysUp) 3.dp else 8.dp, bottom = if (keysUp) 0.dp else 8.dp,
        )
    }

    var state by mutableStateOf<State?>(null)

    /** What's held, shown over the whole keyboard by [peek] (`Peek`), until a tap puts it away or the keyboard goes. */
    var held: Held?
        get() = holding
        set(value) {
            holding = value
            (peek.parent as? View)?.let { root -> peek.layoutParams = peek.layoutParams.apply { height = root.height } }
            peek.visibility = if (value == null) View.GONE else View.VISIBLE
        }
    private var holding by mutableStateOf<Held?>(null)

    val view = ComposeView(context).apply {
        setContent {
            val state = state ?: return@setContent
            CompositionLocalProvider(
                LocalDensity provides Density(resources.displayMetrics.density, 1f),
                LocalColors provides state.colors,
                LocalActions provides actions,
                LocalGifs provides gifs,
                LocalChats provides chats,
                LocalHold provides { held = it },
                LocalHeld provides holding,
            ) {
                if (state.line != null) return@CompositionLocalProvider ChatPanel(state, state.line)
                when (state.panel) {
                    null -> Menu(state)
                    "clipboard" -> ClipboardPanel(state)
                    "gif" -> GifPanel(state)
                    "transcripts" -> TranscriptsPanel(state)
                }
            }
        }
    }

    /** The layer over the whole keyboard, bar and keys too, that a held item shows on. */
    val peek = ComposeView(context).apply {
        visibility = View.GONE
        setContent {
            val held = holding ?: return@setContent
            val state = state ?: return@setContent
            CompositionLocalProvider(
                LocalDensity provides Density(resources.displayMetrics.density, 1f),
                LocalColors provides state.colors,
            ) { Peek(held, state.bottom.dp) { this@Overlay.held = null } }
        }
    }

    /** A Compose view outside an activity needs a lifecycle of its own: the keyboard's window is one. */
    fun attach(root: View) {
        root.setViewTreeLifecycleOwner(owner)
        root.setViewTreeSavedStateRegistryOwner(owner)
    }

    fun resume() = owner.move(Lifecycle.Event.ON_RESUME)
    fun pause() = owner.move(Lifecycle.Event.ON_PAUSE)
    fun destroy() = owner.move(Lifecycle.Event.ON_DESTROY)

    private val owner = Owner()

    private class Owner : LifecycleOwner, SavedStateRegistryOwner {
        private val registry = LifecycleRegistry(this)
        private val saved = SavedStateRegistryController.create(this)
        override val lifecycle: Lifecycle get() = registry
        override val savedStateRegistry: SavedStateRegistry get() = saved.savedStateRegistry

        init {
            saved.performRestore(Bundle())
            registry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        }

        fun move(event: Lifecycle.Event) = registry.handleLifecycleEvent(event)
    }
}

/** The theme's colors, as the overlay paints with them: cards, badges and tiles in the plain key fill, as iOS's are. */
data class Colors(
    val card: Color, val label: Color, val secondary: Color, val key: Color, val keyPressed: Color, val field: Color,
    val accent: Color, val accentLabel: Color, val mic: Color, val micGlyph: Color, val pill: Color, val shadow: Color, val record: Color, val dark: Boolean,
) {
    companion object {
        fun of(theme: Theme) = Colors(
            Color(theme.card), Color(theme.label), Color(theme.candidate), Color(theme.key),
            Color(theme.keyPressed), Color(theme.searchField), Color(theme.prominent), Color(theme.prominentLabel), Color(theme.mic), Color(theme.micGlyph), Color(theme.candidatePill),
            Color(theme.shadow), Color(theme.record), androidx.core.graphics.ColorUtils.calculateLuminance(theme.card) < 0.5,
        )
    }
}

val LocalColors = staticCompositionLocalOf<Colors> { error("no look") }
val LocalActions = staticCompositionLocalOf<Overlay.Actions> { error("no actions") }
/** Shows what's held over the whole keyboard (`Peek`), or, given nothing, puts it away. */
val LocalHold = staticCompositionLocalOf<(Held?) -> Unit> { error("no hold") }
/** What's held now, which hides where it was (`heldAway`). */
val LocalHeld = compositionLocalOf<Held?> { null }

/** One of the keyboard's glyphs (`Glyphs`), a square `size` on a side, at a weight of `Glyphs`'. */
@Composable
fun Glyph(name: String, color: Color, size: Dp, modifier: Modifier = Modifier, weight: Float = Glyphs.REGULAR) {
    val paint = remember { Paint(Paint.ANTI_ALIAS_FLAG) }
    Canvas(modifier.size(size)) {
        paint.color = color.toArgb()
        drawIntoCanvas { Glyphs.draw(it.nativeCanvas, name, center.x, center.y, this.size.minDimension, paint, weight) }
    }
}
