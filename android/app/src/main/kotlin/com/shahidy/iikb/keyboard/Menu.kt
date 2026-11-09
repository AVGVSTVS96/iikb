package com.shahidy.iikb.keyboard

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.floor

/**
 * The keyboard's menu, in the keys' place while the bar's More button is on (docs/design.md, "The menu"): a shelf for
 * each history, its name over its newest items in one row, a tap typing one and the name opening its panel. Layouts
 * and iikb Settings stay on holding 123, where you type.
 */
@Composable
fun Menu(state: Overlay.State) {
    val look = LocalColors.current
    val actions = LocalActions.current
    val gifs = LocalGifs.current
    val shelves = Shelf.entries.filter { it != Shelf.GIFS || gifs != null }
    BoxWithConstraints(Modifier.fillMaxSize().background(look.card)) {
        val count = shelves.size
        val room = maxHeight.value - HEAD - GAP * (count + 1) - (HEAD + HEAD_GAP) * count
        val row = floor((room / count).coerceIn(COMPACT_ROW, 96f)).dp
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(start = state.minX.dp, end = (maxWidth.value - state.maxX).dp, top = GAP.dp),
        ) {
            for (shelf in shelves) {
                ShelfHead(shelf.title, shelf.glyph, shelf.color) { actions.open(shelf.panel) }
                Spacer(Modifier.height(HEAD_GAP.dp))
                Box(Modifier.fillMaxWidth().height(row)) {
                    when (shelf) {
                        Shelf.CLIPBOARD -> ClipShelf(row)
                        Shelf.TRANSCRIPTS -> TranscriptShelf()
                        Shelf.GIFS -> GifShelf(row)
                    }
                }
                Spacer(Modifier.height(GAP.dp))
            }
            ShelfHead("Theme", "paintpalette.fill", Color(0xFF30B0C7)) { actions.appearance() }
            Spacer(Modifier.height(HEAD_GAP.dp))
            ThemeRow(look.dark)
            Spacer(Modifier.height(GAP.dp))
            ShelfHead("Stop Animation", "stop.fill", Color(0xFFFF3B30)) { actions.appearance() }
            Spacer(Modifier.height(HEAD_GAP.dp))
            StopRow()
            Spacer(Modifier.height(GAP.dp))
        }
    }
}

private const val GAP = 10f
private const val HEAD = 28f
private const val HEAD_GAP = 6f
/** Where the screen is short (landscape), each shelf keeps a compact panel's one row, and the menu scrolls. */
private const val COMPACT_ROW = 46f

/** The menu's shelves, each with the color Home's card for it has. */
enum class Shelf(val title: String, val panel: String, val glyph: String, val color: Color) {
    CLIPBOARD("Clipboard", "clipboard", "doc.on.clipboard", Color(0xFFFF9500)),
    TRANSCRIPTS("Transcripts", "transcripts", "text.bubble", Color(0xFFFF2D55)),
    GIFS("GIFs", "gif", "photo", Color(0xFFAF52DE)),
}

/** A shelf's name: its glyph on a colored tile, then the name and a chevron; a tap opens its panel. */
@Composable
fun ShelfHead(title: String, glyph: String, color: Color, onClick: () -> Unit) {
    val look = LocalColors.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Row(
        Modifier.height(HEAD.dp).alpha(if (pressed) 0.5f else 1f)
            .clickable(interaction, indication = null, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(24.dp).background(color, RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) {
            Glyph(glyph, Color.White, 14.dp)
        }
        Spacer(Modifier.width(8.dp))
        Text(title, color = look.label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.width(6.dp))
        Glyph("chevron.right", look.secondary, 11.dp)
    }
}

/** A capsule or card in the key fill, darker while pressed; a hold, where there is one, shows all of it. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun Pressable(
    modifier: Modifier, radius: Dp, onClick: () -> Unit, onHold: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val look = LocalColors.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(
        modifier.background(if (pressed) look.pill else look.key, RoundedCornerShape(radius))
            .combinedClickable(interaction, indication = null, onClick = onClick, onLongClick = onHold),
        contentAlignment = Alignment.CenterStart,
    ) { content() }
}

/** The space between cards or badges in a row. */
val ITEM_GAP = 6.dp
