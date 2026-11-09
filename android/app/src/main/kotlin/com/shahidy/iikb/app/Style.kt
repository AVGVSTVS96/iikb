package com.shahidy.iikb.app

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * The look of Raycast's app (docs/design.md, "The app"), in iOS's `AppStyle` colors: black pages, cards with a hairline
 * edge, inset dividers, white pills for what's picked, blue switches.
 */
data class Palette(
    val page: Color, val card: Color, val edge: Color, val divider: Color, val label: Color, val secondary: Color,
    val accent: Color, val selected: Color, val selectedLabel: Color, val track: Color, val pressed: Color,
    val red: Color, val green: Color,
) {
    companion object {
        val dark = Palette(
            page = Color.Black, card = Color(0xFF1C1C1E), edge = Color(0x12FFFFFF), divider = Color(0xFF2C2C2E),
            label = Color.White, secondary = Color(0xFF8E8E93), accent = Color(0xFF0091FF), selected = Color.White,
            selectedLabel = Color.Black, track = Color(0xFF39393D), pressed = Color(0xFF2C2C2E),
            red = Color(0xFFFF4245), green = Color(0xFF30D158),
        )
        val light = Palette(
            page = Color(0xFFF2F2F5), card = Color.White, edge = Color(0x0F000000), divider = Color(0xFFE3E3E8),
            label = Color.Black, secondary = Color(0xFF6C6C70), accent = Color(0xFF0088FF), selected = Color.Black,
            selectedLabel = Color.White, track = Color(0xFFC5C5C7), pressed = Color(0xFFE5E5EA),
            red = Color(0xFFFF383C), green = Color(0xFF34C759),
        )
    }
}

val LocalPalette = staticCompositionLocalOf { Palette.dark }

@Composable
fun palette() = LocalPalette.current

/** One of iOS's system colors, as it reads on a light page and on a dark one. */
class Hue(private val light: Color, private val dark: Color) {
    fun on(palette: Palette) = if (palette == Palette.dark) dark else light
}

/** iOS 26's system colors, which the iOS app draws its glyphs, charts and figures in (`Color.purple` and the rest). */
object Hues {
    val red = Hue(Color(0xFFFF383C), Color(0xFFFF4245))
    val orange = Hue(Color(0xFFFF8D28), Color(0xFFFF9230))
    val yellow = Hue(Color(0xFFFFCC00), Color(0xFFFFD600))
    val green = Hue(Color(0xFF34C759), Color(0xFF30D158))
    val mint = Hue(Color(0xFF00C8B3), Color(0xFF00DAC3))
    val teal = Hue(Color(0xFF00C3D0), Color(0xFF00D2E0))
    val cyan = Hue(Color(0xFF00C0E8), Color(0xFF3CD3FE))
    val blue = Hue(Color(0xFF0088FF), Color(0xFF0091FF))
    val indigo = Hue(Color(0xFF6155F5), Color(0xFF6D7CFF))
    val purple = Hue(Color(0xFFCB30E0), Color(0xFFDB34F2))
    val pink = Hue(Color(0xFFFF2D55), Color(0xFFFF375F))
    val brown = Hue(Color(0xFFAC7F5E), Color(0xFFB78A66))
    val gray = Hue(Color(0xFF8E8E93), Color(0xFF8E8E93))
}
