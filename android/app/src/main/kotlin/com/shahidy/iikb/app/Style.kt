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
            label = Color.White, secondary = Color(0xFF8E8E93), accent = Color(0xFF0A84FF), selected = Color.White,
            selectedLabel = Color.Black, track = Color(0xFF39393D), pressed = Color(0xFF2C2C2E),
            red = Color(0xFFFF453A), green = Color(0xFF30D158),
        )
        val light = Palette(
            page = Color(0xFFF2F2F5), card = Color.White, edge = Color(0x0F000000), divider = Color(0xFFE3E3E8),
            label = Color.Black, secondary = Color(0xFF6C6C70), accent = Color(0xFF007AFF), selected = Color.Black,
            selectedLabel = Color.White, track = Color(0xFFC5C5C7), pressed = Color(0xFFE5E5EA),
            red = Color(0xFFFF3B30), green = Color(0xFF34C759),
        )
    }
}

val LocalPalette = staticCompositionLocalOf { Palette.dark }

@Composable
fun palette() = LocalPalette.current

/** iOS's system colors, which the iOS app's glyphs sit on (`Glyph`): the same in light and dark, as their gradients are. */
object Hues {
    val purple = Color(0xFFAF52DE)
    val cyan = Color(0xFF28C8F0)
    val pink = Color(0xFFFF2D55)
    val red = Color(0xFFFF3B30)
    val orange = Color(0xFFFF9500)
    val brown = Color(0xFFA2845E)
    val green = Color(0xFF34C759)
    val teal = Color(0xFF30B0C7)
    val indigo = Color(0xFF5856D6)
    val blue = Color(0xFF007AFF)
    val gray = Color(0xFF8E8E93)
}
