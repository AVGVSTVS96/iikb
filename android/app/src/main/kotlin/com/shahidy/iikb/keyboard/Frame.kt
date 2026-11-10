package com.shahidy.iikb.keyboard

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** What the engine hands Kotlin to draw after each event (android/Sources/KeyboardAndroid/Frame.swift). */
@Serializable
data class Frame(
    val layout: String,
    val width: Double,
    val height: Double,
    val toolbar: Bar,
    val caps: List<Cap>,
    val showsSuggestions: Boolean,
    val chips: List<Chip>,
    val emoji: List<String>,
    val look: Look,
    val theme: Theme,
    val menuKeys: List<Int>,
    val menu: List<MenuItem>,
    val menuCurrent: Int? = null,
    val panel: String? = null,
    val query: String,
    val uppercase: Boolean,
    /** The chevron in a one-handed keyboard's margin that brings both hands back, in the keys' dp. */
    val expander: Expander? = null,
) {
    companion object {
        private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

        fun parse(bytes: ByteArray): Frame = json.decodeFromString(serializer(), bytes.decodeToString())
    }
}

@Serializable
data class Cap(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
    val face: String,
    val label: String,
    val secondary: String? = null,
    val secondaryDimmed: Boolean,
    val corner: String? = null,
    val align: String,
    val prominent: Boolean,
    val dimmed: Boolean,
    val paint: String,
    val action: String,
    val isInput: Boolean,
    val typed: String? = null,
    val flicked: String? = null,
    val shown: String? = null,
    val alternates: List<String>,
    val startsSwipe: Boolean,
) {
    val right get() = x + width
    val bottom get() = y + height
}

@Serializable data class Chip(val text: String, val kind: String)

@Serializable data class Expander(val x: Double, val y: Double, val width: Double, val height: Double, val pointsRight: Boolean)

@Serializable data class Box(val x: Double, val y: Double, val width: Double, val height: Double) {
    fun contains(px: Double, py: Double) = px >= x && px < x + width && py >= y && py < y + height
    val midX get() = x + width / 2
    val midY get() = y + height / 2
}

/** A tool at the bar's left: the panel it opens and its button. */
@Serializable data class Tool(val panel: String, val box: Box)

@Serializable
data class Bar(
    val top: Double,
    val bar: Double,
    val button: Double,
    val glyph: Double,
    val results: Double,
    val field: Double,
    val panelHeight: Double,
    val compact: Boolean,
    val blockMinX: Double,
    val blockMaxX: Double,
    /** Between the tools and the mic, where the suggestions and a notice go. */
    val minX: Double,
    val maxX: Double,
    val more: Box? = null,
    /** Where the top row's first key starts, as an open chat's More does. */
    val keysMinX: Double = blockMinX,
    val mic: Box? = null,
    val tools: List<Tool>,
    val slots: List<Box>,
    val emoji: Box,
    val emojiBeside: Boolean,
    val cancel: Box,
    val recording: Box,
) {
    val height get() = top + bar
}

@Serializable data class MenuItem(val symbol: String, val title: String)

@Serializable
data class Look(
    val keyHeight: Double,
    val rowGap: Double,
    val cornerRadius: Double,
    val letterSize: Double,
    val numberRowLetterSize: Double,
    val labelSize: Double,
    val smallLabelSize: Double,
    val symbolSize: Double,
    val secondarySize: Double,
    val cornerSize: Double,
    val pairSize: Double,
    val letterOffset: Double,
    val numberRowLetterOffset: Double,
    val labelLift: Double,
    val edgeInsetX: Double,
    val edgeInsetY: Double,
    val textInset: Double,
    val textBaselineInset: Double,
    val letterBaselineInset: Double,
    val secondaryCapTop: Double,
    val pairCapTopRatio: Double,
    val pairBaselineRatio: Double,
    val numberRowHeight: Double,
    val dimsKeyUnderAccents: Boolean,
)

@Serializable
data class Theme(
    val key: Int,
    val keyPressed: Int,
    val card: Int,
    val label: Int,
    val secondaryLabel: Int,
    val prominent: Int,
    val prominentLabel: Int,
    val shadow: Int,
    val candidate: Int,
    val candidateHighlighted: Int,
    val candidatePill: Int,
    val candidateDivider: Int,
    val expander: Int,
    val mic: Int,
    val micGlyph: Int,
    val record: Int,
    val searchField: Int,
    val bubble: Int,
    val bubbleLabel: Int,
    val selection: Int,
    val selectionLabel: Int,
    val continuous: Boolean,
    val letter: KeyPaint,
    val function: KeyPaint,
    val prominentKey: KeyPaint,
) {
    fun paint(cap: Cap) = when (cap.paint) {
        "prominent" -> prominentKey
        "letter" -> letter
        else -> function
    }
}

@Serializable
data class KeyPaint(
    val top: Int,
    val bottom: Int,
    val pressedTop: Int,
    val pressedBottom: Int,
    val label: Int,
    val labelShadow: Shadow? = null,
    val rim: Rim? = null,
    val keycap: Keycap? = null,
    val drop: Drop? = null,
) {
    @Serializable data class Shadow(val color: Int, val y: Double)
    @Serializable data class Rim(val color: Int, val width: Double, val fade: Double)
    @Serializable data class Keycap(val sides: List<Int>, val at: List<Double>, val glow: Int)
    @Serializable data class Drop(val color: Int, val y: Double, val blur: Double)
}
