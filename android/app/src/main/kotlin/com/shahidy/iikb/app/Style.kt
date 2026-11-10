package com.shahidy.iikb.app

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance

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
            selectedLabel = Color.Black, track = Color(0xFF5A5A5E), pressed = Color(0xFF2C2C2E),
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

/**
 * One of iOS's system colors, as it reads on a light page and on a dark one, with the end SwiftUI's `.gradient` shades it
 * to on each, as iOS 26 draws it (measured: SwiftUI doesn't say how it makes them).
 */
class Hue(private val light: Color, private val dark: Color, private val lightShade: Color, private val darkShade: Color) {
    fun on(palette: Palette) = if (palette == Palette.dark) dark else light

    fun shade(color: Color) = when (color.copy(alpha = 1f)) {
        light -> lightShade
        dark -> darkShade
        else -> null
    }
}

/** iOS 26's system colors, which the iOS app draws its glyphs, charts and figures in (`Color.purple` and the rest). */
object Hues {
    val red = Hue(Color(0xFFFF383C), Color(0xFFFF4245), Color(0xFFFF6367), Color(0xFFFF6B6E))
    val orange = Hue(Color(0xFFFF8D28), Color(0xFFFF9230), Color(0xFFFFAD58), Color(0xFFFFB05F))
    val yellow = Hue(Color(0xFFFFCC00), Color(0xFFFFD600), Color(0xFFEFB800), Color(0xFFEDC200))
    val green = Hue(Color(0xFF34C759), Color(0xFF30D158), Color(0xFF62DD81), Color(0xFF5EE580))
    val mint = Hue(Color(0xFF00C8B3), Color(0xFF00DAC3), Color(0xFF37DFCD), Color(0xFF35ECD9))
    val teal = Hue(Color(0xFF00C3D0), Color(0xFF00D2E0), Color(0xFF37DBE6), Color(0xFF35E6F2))
    val cyan = Hue(Color(0xFF00C0E8), Color(0xFF3CD3FE), Color(0xFF37D8FA), Color(0xFF65E4FF))
    val blue = Hue(Color(0xFF0088FF), Color(0xFF0091FF), Color(0xFF2EA9FF), Color(0xFF2DB0FF))
    val indigo = Hue(Color(0xFF6155F5), Color(0xFF6D7CFF), Color(0xFF887DFF), Color(0xFF96A2FF))
    val purple = Hue(Color(0xFFCB30E0), Color(0xFFDB34F2), Color(0xFFE85DFC), Color(0xFFF65FFF))
    val pink = Hue(Color(0xFFFF2D55), Color(0xFFFF375F), Color(0xFFFF5A7F), Color(0xFFFF6287))
    val brown = Hue(Color(0xFFAC7F5E), Color(0xFFB78A66), Color(0xFFCAA489), Color(0xFFD2AC8E))
    val gray = Hue(Color(0xFF8E8E93), Color(0xFF8E8E93), Color(0xFFB0B0B4), Color(0xFFB0B0B4))

    /** Taps' misses (iOS's `TapMapPalette.miss`). */
    val miss = Hue(Color(0xFFEB6834), Color(0xFFD95926), Color(0xFFFF9267), Color(0xFFF27F51))

    private val all = listOf(red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray, miss)

    /**
     * SwiftUI's `.gradient` on `color`: a lighter top that reaches the color 70% of the way down, or, on a color too
     * light to lighten (yellow), the color to 35% and darker below. A color that isn't one of these gets 18% white on top.
     */
    fun gradient(color: Color): Brush {
        val shade = all.firstNotNullOfOrNull { it.shade(color) }?.copy(alpha = color.alpha)
            ?: return Brush.verticalGradient(0f to lerp(color, Color.White.copy(alpha = color.alpha), 0.18f), 0.7f to color)
        return if (shade.luminance() > color.luminance()) {
            Brush.verticalGradient(0f to shade, 0.7f to color)
        } else {
            Brush.verticalGradient(0.35f to color, 1f to shade)
        }
    }
}
