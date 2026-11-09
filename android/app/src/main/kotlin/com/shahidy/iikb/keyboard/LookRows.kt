package com.shahidy.iikb.keyboard

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.Settings
import com.shahidy.iikb.app.THEMES
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** The menu's Theme row: each theme as its A and B keycaps, a tap picking it at once. */
@Composable
fun ThemeRow(dark: Boolean) {
    val settings = rememberSettings()
    var picked by remember { mutableStateOf(settings.string("theme")) }
    val appearance = settings.string("themeAppearance")
    LookRow(THEMES, picked, 78.dp, { settings.set("theme", it); picked = it }) { name ->
        Keycaps(name, if (name == picked) appearance else "automatic", dark)
    }
}

/** The menu's Stop Animation row: each as its glyph. */
@Composable
fun StopRow() {
    val settings = rememberSettings()
    var picked by remember { mutableStateOf(settings.string("stopAnimation")) }
    val look = LocalColors.current
    LookRow(STOPS, picked, 62.dp, { settings.set("stopAnimation", it); picked = it }) { name ->
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Glyph(STOP_GLYPHS.getValue(name), if (name == picked) look.record else look.label, 22.dp)
        }
    }
}

@Composable
private fun rememberSettings(): Settings {
    val context = LocalContext.current
    return remember { Settings(context) }
}

/**
 * A row of the keyboard's look, scrolling sideways where the choices don't fit: each its art over its name on a card in
 * the key fill, ringed in the theme's blue while it's the one picked.
 */
@Composable
private fun LookRow(
    choices: List<Pair<String, String>>, picked: String, height: Dp, pick: (String) -> Unit,
    art: @Composable (String) -> Unit,
) {
    val look = LocalColors.current
    val row = rememberLazyListState()
    LazyRow(Modifier.fillMaxWidth().height(height).fadeEnds(row), state = row, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(choices) { (name, title) ->
            val chosen = name == picked
            val interaction = remember { MutableInteractionSource() }
            val pressed by interaction.collectIsPressedAsState()
            val ring by animateFloatAsState(if (chosen) 1f else 0f, label = "ring")
            Box(
                Modifier.width(84.dp).height(height)
                    .border(2.dp, look.accent.copy(alpha = ring), RoundedCornerShape(15.dp))
                    .clickable(interaction, indication = null) { if (!chosen) pick(name) },
            ) {
                Column(
                    Modifier.fillMaxSize().padding(3.dp).scale(if (pressed) 0.95f else 1f)
                        .background(look.key, RoundedCornerShape(12.dp)).padding(horizontal = 6.dp, vertical = 5.dp),
                ) {
                    Box(Modifier.weight(1f).fillMaxWidth().alpha(if (pressed) 0.6f else 1f)) { art(name) }
                    Text(
                        title, color = if (chosen) look.label else look.secondary, fontSize = 12.sp,
                        fontWeight = if (chosen) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1,
                        textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().height(16.dp),
                    )
                }
            }
        }
    }
}

@Serializable
private data class Swatch(val themes: List<Theme>, val look: Look)

private val json = Json { ignoreUnknownKeys = true }
private val painter by lazy { KeyPainter() }

/** A theme's A and B keys, painted as the keyboard paints them (`KeycapSwatchView`). */
@Composable
fun Keycaps(theme: String, appearance: String, dark: Boolean) {
    val swatch = remember(theme, appearance, dark) {
        json.decodeFromString<Swatch>(
            Native.swatch(theme.encodeToByteArray(), appearance.encodeToByteArray(), dark).decodeToString(),
        )
    }
    Canvas(Modifier.fillMaxSize()) {
        val key = 44f to 46f
        val gap = 6f
        val scale = minOf(size.width / (key.first * 2 + gap + 4), size.height / (key.second + 4))
        val width = (key.first * 2 + gap) * scale
        drawIntoCanvas { canvas ->
            val native = canvas.nativeCanvas
            for ((index, paint) in swatch.themes.withIndex()) {
                native.save()
                native.translate(size.width / 2 - width / 2 + index * (key.first + gap) * scale, size.height / 2 - key.second * scale / 2)
                native.scale(scale, scale)
                val label = if (index == 0) "A" else "B"
                val cap = Cap(
                    0.0, 0.0, key.first.toDouble(), key.second.toDouble(), "letter", label, null, false, null, "center",
                    false, false, "letter", "character", true, label.lowercase(), null, label, emptyList(), false,
                )
                painter.draw(native, cap, swatch.look, paint, false, true, false)
                native.restore()
            }
        }
    }
}

private val STOPS = listOf("squeeze" to "Squeeze", "drain" to "Drain", "card" to "Card")
private val STOP_GLYPHS = mapOf(
    "squeeze" to "rectangle.arrowtriangle.2.inward", "drain" to "drop.fill", "card" to "rectangle.fill.on.rectangle.angled.fill",
)
