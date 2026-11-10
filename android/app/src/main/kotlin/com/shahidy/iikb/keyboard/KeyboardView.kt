package com.shahidy.iikb.keyboard

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import androidx.core.graphics.ColorUtils
import com.shahidy.iikb.voice.Dictation
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The bar and the keys, drawn from the engine's `Frame` in dp, with touches read as `KeyboardView+Touches` reads them
 * on iOS: typing with rollover, held accents, the space bar trackpad, sliding from the layer key, the hold menu, and
 * swipes over the letters. What a touch does goes to [Actions]; the view only draws and times holds.
 */
@SuppressLint("ViewConstructor")
class KeyboardView(context: Context, private val actions: Actions) : View(context) {
    interface Actions {
        fun down(index: Int, taps: Int)
        fun up(index: Int)
        fun type(index: Int, text: String, x: Double, y: Double)
        fun trigger(index: Int)
        fun slide(text: String)
        fun swipe(path: List<SwipePoint>)
        fun cursor(step: Int)
        /** How far the trackpad's finger travels to move the caret one step, in dp. */
        fun advance(step: Int): Float
        fun menu(item: Int)
        fun select(slot: Int)
        fun acceptEmoji(emoji: String)
        fun more()
        /** A tool at the bar's left: its panel opened in the keys' place, as from the menu. */
        fun open(panel: String)
        fun mic()
        fun cancelDictation()
        fun dismissHint()
        fun repeatDelete(words: Boolean)
        fun feedback(kind: Feedback.Kind)
        fun pickEmoji(emoji: String, base: String?)
        fun closePanel()
        fun clearSearch()
        /** One of the menu's Cut, Copy and Paste. */
        fun edit(name: String)
        /** The one-handed keyboard's chevron: both hands back. */
        fun expand()
        fun emojiResults(): List<String>
        fun tones(emoji: String): List<String>
        /** A writing style picked in the bar for the app the keyboard is in, or null to follow the default again. */
        fun pickStyle(style: String?)
        /** The bar's writing style was held, where it is in the window's pixels, to offer going back to the default. */
        fun holdStyle(source: RectF, reset: String)
    }

    data class SwipePoint(val x: Float, val y: Float, val time: Float)

    private enum class Mode { TYPING, ALTERNATES, TRACKPAD, SLIDE, MENU, SWIPE }

    private class Touch(var index: Int, val start: Pair<Float, Float>, val began: Long, val swipeReach: Float) {
        var mode = Mode.TYPING
        var x = start.first
        var y = start.second
        var cursorX = x
        var flicked = false
        var hold: Runnable? = null
        var menu = false
        val path = mutableListOf(SwipePoint(x, y, 0f))
    }

    var frame: Frame? = null
        set(value) {
            val old = field
            field = value
            if (value != null && old?.layout != value.layout) touches.values.forEach { it.index = -1 }
            if (value?.emoji != old?.emoji) emojiScroll = 0f
            if (value?.chips != old?.chips) style.fold()
            style.update(value?.writing)
            if (value?.panel == "emoji" && (old?.panel != "emoji" || old.query != value.query)) {
                emoji.query = value.query
                emoji.results = actions.emojiResults()
            }
            requestLayout()
            invalidate()
        }

    private val emoji = EmojiPanel(this, android.widget.OverScroller(context))
    private var panelPointer: Int? = null
    private var emojiHold: Runnable? = null
    private var toneOf: String? = null

    /** What the menu's Cut, Copy and Paste can do now, while the menu is out; the bar shows them over its suggestions. */
    data class Edits(val cut: Boolean, val copy: Boolean, val paste: Boolean)

    var edits: Edits? = null
    /** The More button stays pressed while the menu, or a panel opened from it, is out. */
    var moreOn = false
    /** The menu or a panel sits in the keys' place, over a keyboard grown to `grown` dp. */
    var keysHidden = false
    var grown = 0f
    /** A panel drawn over the bar's place (`Overlay`), with the keys up under it. */
    var barCovered = false

    /**
     * While a chat is read with the keys down, its tabs and More, which the overlay draws on glass, take the bar's place
     * but for the mic, so the bar leaves them out.
     */
    var chatTabs = false
    /** The bar sits on the keys, under a chat over it, as with the keys up in a chat. */
    var barOnKeys = false

    /** A line in the bar's place until your next touch, like a GIF's "Copied" once the menu gives the keys back. */
    var notice: String? = null
    /** A source's hint (docs/sources.md), in the suggestions' place; a tap hides it. */
    var hint: String? = null
    /** The touch going on began over a notice, which it cleared, so it isn't a tap on the hint under it. */
    private var clearedNotice = false

    var characterPreview = "attached"
    val mic = MicBar(this)

    private val density = resources.displayMetrics.density
    private val painter = KeyPainter()
    private val handler = Handler(Looper.getMainLooper())
    private val touches = mutableMapOf<Int, Touch>()
    private var lastDown = -1 to 0L
    private var pressedBar: String? = null
    private var accents: Accents? = null
    private val text = Paint(Paint.ANTI_ALIAS_FLAG)
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val chevron = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val trail = Trail(this)
    private val glass = BarGlass()
    private val style = StylePicker(this, painter.labels)
    private var styleHold: Runnable? = null
    private var deleteRepeat: Runnable? = null

    private class Accents(
        val options: List<String>, val symbols: Boolean, val box: RectF, val cell: Float, val padding: Float,
        val highlight: Float, var selected: Int,
    )

    private val bar get() = frame?.toolbar
    private val barHeight get() = frame?.let {
        (if (it.panel != null && !keysHidden) it.toolbar.panelHeight else it.toolbar.height).toFloat()
    } ?: 0f

    /** Where the keys start: under the bar, or at the bottom of a keyboard grown taller, as for a chat with the keys up. */
    private val keysTop get() = frame?.let { maxOf(barHeight, grown - it.height.toFloat()) } ?: 0f

    /** Where the bar starts: the top, or just over the keys. */
    private val barTop get() = if (barOnKeys) keysTop - barHeight else 0f

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val frame = frame
        val height = if (frame == null) 0 else (maxOf(barHeight + frame.height.toFloat(), grown) * density).toInt()
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), height)
    }

    override fun onDraw(canvas: Canvas) {
        val frame = frame ?: return
        canvas.save()
        canvas.scale(density, density)
        when {
            frame.panel == "emoji" -> emoji.draw(canvas, frame, painter.labels)
            !barCovered -> {
                canvas.save()
                canvas.translate(0f, barTop)
                drawBar(canvas, frame)
                canvas.restore()
            }
        }
        if (keysHidden) return canvas.restore()
        canvas.translate(0f, keysTop)
        val pressed = pressedKeys(frame)
        val trackpad = touches.values.any { it.mode == Mode.TRACKPAD }
        for ((index, cap) in frame.caps.withIndex()) {
            val flicked = touches.values.any { it.index == index && it.flicked }
            if (cap.action == "dictate" && frame.toolbar.mic == null) mic.drawKey(canvas, cap, frame, index in pressed)
            else painter.draw(canvas, cap, frame.look, frame.theme, index in pressed, !trackpad, flicked)
        }
        frame.expander?.let { drawExpander(canvas, frame, it) }
        trail.draw(canvas, frame.theme.prominent)
        preview(frame)?.let { drawCallout(canvas, frame, it) }
        accents?.let { drawAccents(canvas, frame, it) }
        canvas.restore()
    }

    override fun computeScroll() = emoji.scroll()

    /** Holding an emoji with skin tones shows them over it, as a key's accents. */
    fun holdEmoji(index: Int) {
        cancelEmojiHold()
        emojiHold = Runnable {
            val frame = frame ?: return@Runnable
            val picked = emoji.results.getOrNull(index) ?: return@Runnable
            val tones = actions.tones(picked)
            if (tones.size <= 1) return@Runnable
            val place = emoji.frameOf(index, frame) ?: return@Runnable
            emoji.startHold(index)
            toneOf = tones.first()
            val cap = Cap(
                place.left.toDouble(), (place.top - keysTop).toDouble(), place.width().toDouble(), place.height().toDouble(),
                "letter", picked, null, true, null, "center", false, false, "letter", "character", true, picked, null,
                picked, tones, false,
            )
            showAccents(frame, cap, tones, symbols = false, selected = tones.indexOf(picked).coerceAtLeast(0))
            invalidate()
        }.also { handler.postDelayed(it, ACCENT_HOLD) }
    }

    fun cancelEmojiHold() {
        emojiHold?.let(handler::removeCallbacks)
        emojiHold = null
    }

    // The bar

    private fun drawBar(canvas: Canvas, frame: Frame) {
        val bar = frame.toolbar
        val theme = frame.theme
        bar.more?.takeUnless { chatTabs }?.let { box ->
            glass.draw(canvas, square(box.midX.toFloat(), box.midY.toFloat(), bar.button.toFloat()), theme)
            fill.color = pressedInk(theme, pressedBar == "more")
            Glyphs.draw(canvas, "more", box.midX.toFloat(), box.midY.toFloat(), bar.glyph.toFloat(), fill)
        }
        drawTools(canvas, frame)
        val edits = edits
        val notice = notice
        val styled = showsStyle(frame)
        if (!styled) style.hide()
        val under = mic.suggestions * (1 - if (styled) style.openness() else 0f)
        if (under < 1) canvas.saveLayerAlpha(0f, 0f, width / density, bar.height.toFloat(), (255 * under).toInt())
        when {
            edits != null -> drawEdits(canvas, frame, edits)
            chatTabs -> {}
            notice != null && !mic.covers -> drawNotice(canvas, frame, notice)
            hint != null && showsHint(frame) -> drawNotice(canvas, frame, hint!!)
            frame.showsSuggestions && frame.panel == null && !mic.covers -> drawSuggestions(canvas, frame)
            frame.panel != null && !mic.covers -> drawDividers(canvas, frame)
        }
        if (under < 1) canvas.restore()
        if (styled) style.draw(canvas, bar, frame.writing!!, theme, glass)
        mic.draw(canvas, frame, pressedBar)
    }

    /**
     * Whether the writing style shows, as iOS's `refresh` has it: where the bar has its room and the app is known, over
     * the suggestions with nothing in their place, never while you dictate.
     */
    private fun showsStyle(frame: Frame) =
        frame.writing != null && frame.toolbar.style != null && frame.showsSuggestions && frame.panel == null &&
            edits == null && notice == null && !(hint != null && showsHint(frame)) && !chatTabs && mic.phase == Dictation.Phase.OFF

    /** A glass button's glyph: the label, faded while pressed, as iOS's glassy `BarButton`. */
    private fun pressedInk(theme: Theme, pressed: Boolean) =
        if (pressed) ColorUtils.setAlphaComponent(theme.label, (Color.alpha(theme.label) * 0.55f).toInt()) else theme.label

    private fun square(x: Float, y: Float, side: Float) = RectF(x - side / 2, y - side / 2, x + side / 2, y + side / 2)

    /**
     * Where the tools sit, as iOS's `placeTools`: on BarLayout's places, or, where no suggestions show and every title
     * fits, each titled, the capsule running on to the mic as far from it as from More, the spare room shared out so
     * every gap between them is one size.
     */
    private fun toolPlaces(frame: Frame): Pair<List<RectF>, Boolean> {
        val bar = frame.toolbar
        val side = bar.button.toFloat()
        val boxes = bar.tools.map { square(it.box.midX.toFloat(), it.box.midY.toFloat(), side) }
        val first = boxes.firstOrNull() ?: return boxes to false
        val pad = (side * 0.2f).roundToInt().toFloat()
        val gap = bar.pitch.toFloat() - side - pad
        val end = (bar.mic?.x ?: bar.maxX).toFloat() - gap - pad
        val widths = bar.tools.map { titledWidth(frame, it.panel) }
        val spare = (end - first.left - widths.sum()) / widths.size
        val recording = mic.phase != Dictation.Phase.OFF
        if (frame.showsSuggestions || recording || edits != null || notice != null || spare < 0) return boxes to false
        var x = first.left
        return widths.map { width -> RectF(x, first.top, x + width + spare, first.bottom).also { x = it.right } } to true
    }

    /** A titled tool's width: its glyph and title a gap apart, with a glyph's room before and after them. */
    private fun titledWidth(frame: Frame, panel: String): Float {
        val bar = frame.toolbar
        val ink = toolInk(panel, bar.glyph.toFloat())
        toolTitle(bar)
        return ink + TITLE_GAP + ceil(text.measureText(TOOL_TITLES.getValue(panel))) + (bar.button.toFloat() - ink)
    }

    private fun toolInk(panel: String, glyph: Float) =
        if (panel == "gif") Glyphs.GIF_FILLED * glyph else Glyphs.fittedWidth(TOOL_GLYPHS.getValue(panel), glyph)

    private fun toolTitle(bar: Bar) {
        text.typeface = android.graphics.Typeface.create(painter.labels, 500, false)
        text.textSize = (bar.glyph.toFloat() * 0.7f).roundToInt().toFloat()
    }

    /** The tools in one capsule of the bar's glass, which reaches a fifth of a button past them, each as iOS's `BarButton`. */
    private fun drawTools(canvas: Canvas, frame: Frame) {
        val bar = frame.toolbar
        if (bar.tools.isEmpty()) return
        val (places, titled) = toolPlaces(frame)
        val pad = (bar.button.toFloat() * 0.2f).roundToInt().toFloat()
        glass.draw(canvas, RectF(places.first().left - pad, places.first().top, places.last().right + pad, places.first().bottom), frame.theme)
        val glyph = bar.glyph.toFloat()
        for ((tool, place) in bar.tools.zip(places)) {
            val ink = pressedInk(frame.theme, pressedBar == "tool:${tool.panel}")
            fill.color = ink
            var x = place.centerX()
            if (titled) {
                toolTitle(bar)
                val title = TOOL_TITLES.getValue(tool.panel)
                val width = toolInk(tool.panel, glyph)
                val start = ((place.width() - width - TITLE_GAP - ceil(text.measureText(title))) / 2).roundToInt() + place.left
                x = start + width / 2
                text.color = ink
                canvas.drawText(title, start + width + TITLE_GAP, place.centerY() + (text.textSize * 0.7f) / 2 - 0.5f, text)
            }
            if (tool.panel == "gif") Glyphs.drawGif(canvas, x, place.centerY(), glyph, fill, painter.labels) else Glyphs.drawFitted(canvas, TOOL_GLYPHS.getValue(tool.panel), x, place.centerY(), glyph, fill)
        }
    }

    private fun drawSuggestions(canvas: Canvas, frame: Frame) {
        val bar = frame.toolbar
        val theme = frame.theme
        val showsEmoji = frame.emoji.isNotEmpty()
        val slots = if (showsEmoji && !bar.emojiBeside) bar.slots.dropLast(1) else bar.slots
        text.typeface = painter.labels
        text.textSize = 17f
        for ((index, box) in slots.withIndex()) {
            val chip = frame.chips.getOrNull(index) ?: continue
            val held = pressedBar == "slot$index"
            if (chip.kind == "correction" || held) {
                fill.color = theme.candidatePill
                val pill = RectF(box.x.toFloat() + 8 / 3f, box.y.toFloat() + 2, (box.x + box.width).toFloat() - 8 / 3f, (box.y + box.height).toFloat() - 2)
                canvas.drawRoundRect(pill, pill.height() / 2, pill.height() / 2, fill)
            }
            text.color = when {
                chip.kind == "correction" || held -> theme.candidateHighlighted
                index == 1 -> theme.label
                else -> theme.candidate
            }
            text.typeface = if (index == 1) android.graphics.Typeface.create(painter.labels, 500, false) else painter.labels
            val label = ellipsize(chip.text, box.width.toFloat() - 8)
            val width = text.measureText(label)
            val capHeight = text.textSize * 0.7f
            canvas.drawText(label, (box.midX - width / 2).toFloat(), (box.midY + capHeight / 2).toFloat(), text)
        }
        drawDividers(canvas, frame)
        if (showsEmoji) drawEmoji(canvas, frame)
    }

    /** A divider shows between two slots shown without a pill, empty ones too, as iOS's bar has it over a panel, and before an emoji in the last slot's place unless it's held. */
    private fun drawDividers(canvas: Canvas, frame: Frame) {
        val bar = frame.toolbar
        val showsEmoji = frame.panel == null && frame.emoji.isNotEmpty()
        fill.color = frame.theme.candidateDivider
        for (index in 0 until 2) {
            val box = bar.slots[index]
            val pill = { at: Int -> frame.panel == null && (frame.chips.getOrNull(at)?.kind == "correction" || pressedBar == "slot$at") }
            val emojiNext = index + 1 == 2 && showsEmoji && !bar.emojiBeside
            if (pill(index) || if (emojiNext) pressedBar == "emoji0" else pill(index + 1)) continue
            val x = (box.x + box.width).toFloat()
            canvas.drawRect(x - 0.5f, box.midY.toFloat() - 14, x + 0.5f, box.midY.toFloat() + 14, fill)
        }
    }

    private fun showsHint(frame: Frame) = frame.showsSuggestions && frame.panel == null && !mic.covers && edits == null && !chatTabs

    /** A notice or a source's hint, centered between the tools and the mic, shrinking to 70% before it's cut at its end. */
    private fun drawNotice(canvas: Canvas, frame: Frame, notice: String) {
        val bar = frame.toolbar
        text.typeface = painter.labels
        text.color = frame.theme.candidate
        val left = bar.minX.toFloat() + 4
        val right = bar.maxX.toFloat() - 4
        val room = right - left
        text.textSize = 15f
        text.textSize = (15f * room / text.measureText(notice)).coerceIn(15f * 0.7f, 15f)
        var label = notice
        while (label.length > 1 && text.measureText(label) > room) label = label.dropLast(2) + "…"
        canvas.drawText(label, (left + right) / 2 - text.measureText(label) / 2, (bar.top + bar.bar / 2).toFloat() + text.textSize / 3, text)
    }

    /** Cut, Copy and Paste as three pills in the theme's key color, from the More button to the mic. */
    private fun editPills(frame: Frame): List<Pair<String, RectF>> {
        val bar = frame.toolbar
        val anchor = bar.tools.lastOrNull()?.box ?: bar.more
        val left = (anchor?.let { it.x + it.width } ?: bar.blockMinX).toFloat() + 6
        val right = (bar.mic?.x ?: bar.blockMaxX).toFloat() - 6
        val width = (right - left - 16) / 3
        val height = minOf(bar.bar - 4, bar.button + 8).toFloat()
        val top = (bar.top + bar.bar / 2).toFloat() - height / 2
        return EDITS.mapIndexed { index, name ->
            val x = left + index * (width + 8)
            name to RectF(x, top, x + width, top + height)
        }
    }

    private fun drawEdits(canvas: Canvas, frame: Frame, edits: Edits) {
        val theme = frame.theme
        text.typeface = android.graphics.Typeface.create(painter.labels, 500, false)
        text.textSize = 16f
        for ((name, box) in editPills(frame)) {
            val enabled = enabled(edits, name)
            fill.color = if (pressedBar == name) theme.keyPressed else theme.key
            canvas.drawRoundRect(box, box.height() / 2, box.height() / 2, fill)
            val color = if (enabled) theme.label else theme.candidate
            val title = name.replaceFirstChar(Char::uppercase)
            val glyph = Glyphs.square(15f)
            val width = glyph + 6 + text.measureText(title)
            val x = box.centerX() - width / 2
            fill.color = color
            Glyphs.draw(canvas, EDIT_GLYPHS.getValue(name), x + glyph / 2, box.centerY(), glyph, fill, Glyphs.MEDIUM)
            text.color = color
            canvas.drawText(title, x + glyph + 6, box.centerY() + text.textSize * 0.35f, text)
        }
    }

    private fun enabled(edits: Edits, name: String) = when (name) {
        "cut" -> edits.cut
        "copy" -> edits.copy
        else -> edits.paste
    }

    /**
     * The word's emoji as iOS's strip sets them out: centered, or at the end beside the suggestions, and from the start
     * once they don't fit, the rest a swipe left away (`emojiScroll`).
     */
    private fun emojiPlaces(frame: Frame): List<Pair<String, Float>> {
        val box = frame.toolbar.emoji
        val total = EMOJI_PITCH * frame.emoji.size
        val room = box.width.toFloat()
        val start = box.x.toFloat() + maxOf(if (frame.toolbar.emojiBeside) room - total else (room - total) / 2, 0f) - emojiScroll
        return frame.emoji.mapIndexed { index, emoji -> emoji to start + EMOJI_PITCH * (index + 0.5f) }
    }

    private var emojiScroll = 0f
    /** Where a touch on the emoji began, and the scroll then, until it moves far enough to scroll them. */
    private var emojiDrag: Pair<Float, Float>? = null

    private fun scrollEmoji(frame: Frame, x: Float) {
        val (downX, from) = emojiDrag ?: return
        if (pressedBar != null && abs(x - downX) < EMOJI_SLOP) return
        pressedBar = null
        val most = maxOf(EMOJI_PITCH * frame.emoji.size - frame.toolbar.emoji.width.toFloat(), 0f)
        emojiScroll = (from + downX - x).coerceIn(0f, most)
    }

    private fun drawEmoji(canvas: Canvas, frame: Frame) {
        val box = frame.toolbar.emoji
        canvas.save()
        canvas.clipRect(box.x.toFloat(), 0f, (box.x + box.width).toFloat(), frame.toolbar.height.toFloat())
        text.textSize = EMOJI_SIZE
        text.typeface = painter.labels
        text.color = frame.theme.label
        for ((index, place) in emojiPlaces(frame).withIndex()) {
            val (emoji, x) = place
            if (pressedBar == "emoji$index") {
                fill.color = frame.theme.candidatePill
                canvas.drawCircle(x, box.midY.toFloat(), 16f, fill)
            }
            val width = text.measureText(emoji)
            val metrics = text.fontMetrics
            canvas.drawText(emoji, x - width / 2, box.midY.toFloat() - (metrics.ascent + metrics.descent) / 2, text)
        }
        canvas.restore()
    }

    private fun ellipsize(label: String, width: Float): String {
        if (text.measureText(label) <= width) return label
        var cut = label.length
        while (cut > 1) {
            cut--
            val half = cut / 2
            val tried = label.take(half) + "…" + label.takeLast(cut - half)
            if (text.measureText(tried) <= width) return tried
        }
        return label
    }

    /** The chevron, a stroke pointing toward the keys' empty side, as iOS's `ExpanderView` draws it. */
    private fun drawExpander(canvas: Canvas, frame: Frame, expander: Expander) {
        chevron.color = frame.theme.expander
        chevron.strokeWidth = 16f / 3
        val inset = chevron.strokeWidth / 2
        val top = (expander.y + inset).toFloat()
        val bottom = (expander.y + expander.height - inset).toFloat()
        val left = (expander.x + inset).toFloat()
        val right = (expander.x + expander.width - inset).toFloat()
        val (tip, tail) = if (expander.pointsRight) right to left else left to right
        val path = android.graphics.Path().apply {
            moveTo(tail, top)
            lineTo(tip, (top + bottom) / 2)
            lineTo(tail, bottom)
        }
        canvas.drawPath(path, chevron)
    }

    /** The column the chevron takes taps in, down the keyboard: from its middle to the keyboard's edge on its side. */
    private fun expanderColumn(frame: Frame): Pair<Float, Float>? {
        val expander = frame.expander ?: return null
        val column = maxOf(44.0, expander.width)
        val mid = expander.x + expander.width / 2
        return if (expander.pointsRight) (mid - column / 2).toFloat() to frame.width.toFloat()
        else 0f to (mid + column / 2).toFloat()
    }

    private fun barTarget(frame: Frame, x: Float, y: Float): String? {
        val bar = frame.toolbar
        if (y < 0) return null
        bar.more?.takeUnless { chatTabs }?.let { if (abs(it.midX - x) <= bar.bar / 2 && y < bar.height) return "more" }
        if (y < bar.height && bar.tools.isNotEmpty()) {
            val (places, titled) = toolPlaces(frame)
            val reach = if (titled) 0f else bar.bar.toFloat() / 2
            bar.tools.indices.filter { x >= places[it].centerX() - maxOf(reach, places[it].width() / 2) && x <= places[it].centerX() + maxOf(reach, places[it].width() / 2) }
                .minByOrNull { abs(places[it].centerX() - x) }?.let { return "tool:${bar.tools[it].panel}" }
        }
        bar.mic?.let { if (abs(it.midX - x) <= bar.bar / 2 && y < bar.height) return "mic" }
        if (mic.hitsCancel(frame, x, y)) return "cancel"
        edits?.let { edits ->
            return editPills(frame).firstOrNull { (name, box) -> enabled(edits, name) && x >= box.left && x <= box.right }?.first
        }
        if (chatTabs) return null
        if (showsStyle(frame) && y < bar.height) {
            val track = style.track(bar, frame.writing!!)
            if (x >= track.left && x <= track.right) return "style"
            if (style.isOpen) return null
        }
        if (hint != null && !clearedNotice && showsHint(frame) && y < bar.height) return "hint"
        if (!frame.showsSuggestions || frame.panel != null || mic.covers) return null
        val showsEmoji = frame.emoji.isNotEmpty()
        if (showsEmoji && bar.emoji.contains(x.toDouble(), bar.emoji.y)) {
            val places = emojiPlaces(frame)
            val index = places.indices.minByOrNull { abs(places[it].second - x) } ?: return null
            return "emoji$index"
        }
        val slots = if (showsEmoji && !bar.emojiBeside) bar.slots.dropLast(1) else bar.slots
        val index = slots.indexOfFirst { x >= it.x && x < it.x + it.width }
        return if (index >= 0 && frame.chips.getOrNull(index) != null) "slot$index" else null
    }

    private fun barTap(frame: Frame, target: String, x: Float) {
        when {
            target == "style" -> frame.writing?.let { writing ->
                style.tap(frame.toolbar, writing, x)?.let { actions.pickStyle(writing.styles[it].value) }
            }
            target == "more" -> actions.more()
            target == "mic" -> actions.mic()
            target.startsWith("tool:") -> actions.open(target.removePrefix("tool:"))
            target == "cancel" -> {
                mic.dissolve(frame, density)
                actions.cancelDictation()
            }
            target == "hint" -> actions.dismissHint()
            target in EDITS -> actions.edit(target)
            target.startsWith("slot") -> actions.select(target.removePrefix("slot").toInt())
            target.startsWith("emoji") ->
                emojiPlaces(frame).getOrNull(target.removePrefix("emoji").toInt())?.let { actions.acceptEmoji(it.first) }
        }
    }

    // Touches

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        val frame = frame ?: return false
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            clearedNotice = notice != null
            notice = null
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val pointer = event.actionIndex
                val x = event.getX(pointer) / density
                val y = event.getY(pointer) / density
                if (frame.panel == "emoji" && y - keysTop < -TOP_ROW_REACH && panelPointer == null) {
                    panelPointer = event.getPointerId(pointer)
                    emoji.touch(event, x, y, frame, actions)
                } else {
                    begin(frame, event.getPointerId(pointer), x, y)
                }
            }

            MotionEvent.ACTION_MOVE -> {
                for (pointer in 0 until event.pointerCount) {
                    val id = event.getPointerId(pointer)
                    if (id == panelPointer) {
                        val x = event.getX(pointer) / density
                        if (emoji.holding >= 0) accents?.let { track(it, x) } else emoji.touch(event, x, event.getY(pointer) / density, frame, actions)
                        continue
                    }
                    if (id == barPointer) scrollEmoji(frame, event.getX(pointer) / density)
                    val touch = touches[id] ?: continue
                    if (touch.mode == Mode.SWIPE || touch.swipeReach.isFinite()) {
                        for (h in 0 until event.historySize) {
                            follow(touch, event.getHistoricalX(pointer, h) / density, event.getHistoricalY(pointer, h) / density - keysTop, event.getHistoricalEventTime(h))
                        }
                    }
                    move(frame, touch, event.getX(pointer) / density, event.getY(pointer) / density - keysTop, event.eventTime)
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val pointer = event.actionIndex
                val id = event.getPointerId(pointer)
                if (id == panelPointer) {
                    panelPointer = null
                    val tones = accents
                    if (emoji.holding >= 0 && tones != null) {
                        accents = null
                        actions.pickEmoji(tones.options[tones.selected], toneOf)
                    }
                    emoji.touch(event, event.getX(pointer) / density, event.getY(pointer) / density, frame, actions)
                }
                if (id == barPointer) {
                    barPointer = null
                    cancelStyleHold()
                    val target = pressedBar
                    pressedBar = null
                    val x = event.getX(pointer) / density
                    if (target != null && target == barTarget(frame, x, event.getY(pointer) / density - barTop)) {
                        barTap(frame, target, x)
                    }
                    invalidate()
                }
                touches.remove(id)?.let { touch ->
                    touch.x = event.getX(pointer) / density
                    touch.y = event.getY(pointer) / density - keysTop
                    finish(frame, touch, commit = true)
                }
            }

            MotionEvent.ACTION_CANCEL -> {
                if (panelPointer != null) emoji.touch(event, 0f, 0f, frame, actions)
                panelPointer = null
                accents = null
                barPointer = null
                pressedBar = null
                cancelStyleHold()
                for (touch in touches.values.toList()) finish(frame, touch, commit = false)
                touches.clear()
            }
        }
        invalidate()
        return true
    }

    private var barPointer: Int? = null

    private fun begin(frame: Frame, id: Int, x: Float, y: Float) {
        val keyY = y - keysTop
        if (!keysHidden && keyY >= 0 && expanderColumn(frame)?.let { x >= it.first && x <= it.second } == true) {
            actions.feedback(Feedback.Kind.OTHER)
            actions.expand()
            return
        }
        if (keyY < -TOP_ROW_REACH || keysHidden) {
            val target = barTarget(frame, x, y - barTop) ?: return
            barPointer = id
            pressedBar = target
            emojiDrag = if (target.startsWith("emoji")) x to emojiScroll else null
            if (target == "style") holdStyle(frame)
            actions.feedback(Feedback.Kind.OTHER)
            return
        }
        rollOver(frame)
        val index = Native.resolve(handle, x.toDouble(), keyY.toDouble())
        if (index < 0) return
        val cap = frame.caps.getOrNull(index) ?: return
        val now = SystemClock.uptimeMillis()
        val taps = if (lastDown.first == index && now - lastDown.second < DOUBLE_TAP) 2 else 1
        lastDown = index to if (taps == 2) 0L else now
        val reach = if (cap.startsSwipe) (cap.width * SWIPE_DISTANCE).toFloat() else Float.POSITIVE_INFINITY
        val touch = Touch(index, x to keyY, now, reach)
        if (index in frame.menuKeys && frame.menu.isNotEmpty()) touch.menu = true
        if (cap.action == "layer") touch.mode = Mode.SLIDE
        touches[id] = touch
        scheduleHold(touch)
        actions.down(index, taps)
        if (cap.action == "delete") startDeleteRepeat()
    }

    /**
     * Holding the writing style, where the app has one of its own, offers going back to the default, as iOS's context
     * menu on its `StylePicker` does.
     */
    private fun holdStyle(frame: Frame) {
        val writing = frame.writing ?: return
        val reset = writing.reset ?: return
        styleHold = Runnable {
            styleHold = null
            if (pressedBar != "style") return@Runnable
            pressedBar = null
            barPointer = null
            val track = style.track(frame.toolbar, writing)
            style.fold()
            val at = IntArray(2).also(::getLocationInWindow)
            actions.holdStyle(
                RectF(at[0] + track.left * density, at[1] + (track.top + barTop) * density, at[0] + track.right * density, at[1] + (track.bottom + barTop) * density),
                reset,
            )
            invalidate()
        }.also { handler.postDelayed(it, MENU_HOLD) }
    }

    private fun cancelStyleHold() {
        styleHold?.let(handler::removeCallbacks)
        styleHold = null
    }

    /** Set by the service: the engine's handle, so hit testing asks the key map made for the text as it is. */
    var handle = 0L

    private fun follow(touch: Touch, x: Float, y: Float, time: Long) {
        touch.path.add(SwipePoint(x, y, (time - touch.began) / 1000f))
        if (touch.mode == Mode.SWIPE) trail.add(x, y)
    }

    private fun move(frame: Frame, touch: Touch, x: Float, y: Float, time: Long) {
        touch.x = x
        touch.y = y
        when (touch.mode) {
            Mode.ALTERNATES, Mode.MENU -> accents?.let { track(it, x) }
            Mode.TRACKPAD -> {
                while (true) {
                    val step = if (x > touch.cursorX) 1 else -1
                    val width = actions.advance(step)
                    if (abs(x - touch.cursorX) < width) break
                    touch.cursorX += step * width
                    actions.cursor(step)
                }
            }

            Mode.SWIPE -> follow(touch, x, y, time)
            Mode.TYPING, Mode.SLIDE -> {
                if (touch.swipeReach.isFinite()) {
                    follow(touch, x, y, time)
                    if (hypot(x - touch.start.first, y - touch.start.second) >= touch.swipeReach) {
                        touch.mode = Mode.SWIPE
                        trail.begin(touch.path)
                        cancelHold(touch)
                        return
                    }
                }
                val cap = frame.caps.getOrNull(touch.index)
                if (touch.menu && cap != null && !(x >= cap.x && x < cap.right && y >= cap.y && y < cap.bottom)) {
                    touch.menu = false
                    cancelHold(touch)
                }
                val index = Native.resolve(handle, x.toDouble(), y.toDouble())
                if (index < 0 || index == touch.index) return
                val next = frame.caps.getOrNull(index) ?: return
                if (touch.mode != Mode.SLIDE && !(next.isInput && cap?.isInput == true)) return
                touch.index = index
                if (!touch.menu) {
                    cancelHold(touch)
                    scheduleHold(touch)
                }
            }
        }
    }

    private fun rollOver(frame: Frame) {
        for ((id, other) in touches.toList()) {
            val cap = frame.caps.getOrNull(other.index)
            if (other.mode == Mode.SWIPE || (other.mode == Mode.TYPING && cap?.isInput == true)) {
                touches.remove(id)
                finish(frame, other, commit = true)
            }
        }
    }

    private fun finish(frame: Frame, touch: Touch, commit: Boolean) {
        cancelHold(touch)
        val cap = frame.caps.getOrNull(touch.index)
        val selected = accents
        accents = null
        if (cap?.action == "delete") stopDeleteRepeat()
        if (cap == null) return
        val (x, y) = touch.x.toDouble() to touch.y.toDouble()
        when (touch.mode) {
            Mode.ALTERNATES ->
                if (commit && selected != null) actions.type(touch.index, selected.options[selected.selected], x, y)

            Mode.MENU -> if (commit && selected != null) actions.menu(selected.selected)
            Mode.TRACKPAD -> {}
            Mode.SLIDE -> if (commit && cap.isInput) typed(cap, touch)?.let(actions::slide)
            Mode.SWIPE -> if (commit) actions.swipe(timed(touch.path))
            Mode.TYPING -> if (commit) {
                val text = typed(cap, touch)
                when {
                    text != null -> actions.type(touch.index, text, x, y)
                    cap.action == "space" -> actions.type(touch.index, " ", x, y)
                    else -> actions.trigger(touch.index)
                }
            }
        }
        actions.up(touch.index)
    }

    private fun typed(cap: Cap, touch: Touch) = if (touch.flicked) cap.flicked ?: cap.typed else cap.typed

    /** A path whose samples all came at once (a test's injected swipe) is timed as one sampled at 120 Hz. */
    private fun timed(path: List<SwipePoint>): List<SwipePoint> {
        if (path.size <= 2 || path.dropLast(1).any { it.time != 0f }) return path
        return path.mapIndexed { index, point -> point.copy(time = index / 120f) }
    }

    private fun scheduleHold(touch: Touch) {
        val frame = frame ?: return
        val cap = frame.caps.getOrNull(touch.index) ?: return
        if (touch.menu) {
            touch.hold = Runnable {
                if (touch.mode != Mode.SLIDE && touch.mode != Mode.TYPING) return@Runnable
                touch.mode = Mode.MENU
                showAccents(frame, cap, frame.menu.map { it.symbol }, symbols = true, selected = frame.menuCurrent ?: 0)
                invalidate()
            }.also { handler.postDelayed(it, MENU_HOLD) }
            return
        }
        if (touch.mode != Mode.TYPING) return
        val space = cap.action == "space"
        if (!space && cap.alternates.size <= 1) return
        touch.hold = Runnable {
            if (touch.mode != Mode.TYPING || touch !in touches.values) return@Runnable
            if (space) {
                touch.mode = Mode.TRACKPAD
                touch.cursorX = touch.x
            } else {
                touch.mode = Mode.ALTERNATES
                val base = cap.shown ?: ""
                showAccents(frame, cap, cap.alternates, symbols = false, selected = cap.alternates.indexOf(base).coerceAtLeast(0))
            }
            invalidate()
        }.also { handler.postDelayed(it, if (space) TRACKPAD_HOLD else ACCENT_HOLD) }
    }

    private fun cancelHold(touch: Touch) {
        touch.hold?.let(handler::removeCallbacks)
        touch.hold = null
    }

    private fun startDeleteRepeat() {
        var count = 0
        val fire = object : Runnable {
            override fun run() {
                count++
                val words = count > 20
                actions.repeatDelete(words)
                actions.feedback(if (words) Feedback.Kind.DELETE_RAPID else Feedback.Kind.DELETE_REPEAT)
                handler.postDelayed(this, if (words) 250 else 100)
            }
        }
        deleteRepeat = fire
        handler.postDelayed(fire, 500)
    }

    private fun stopDeleteRepeat() {
        deleteRepeat?.let(handler::removeCallbacks)
        deleteRepeat = null
    }

    // What a pressed key shows

    private fun pressedKeys(frame: Frame): Set<Int> = buildSet {
        for (touch in touches.values) {
            val cap = frame.caps.getOrNull(touch.index) ?: continue
            when (touch.mode) {
                Mode.TRACKPAD, Mode.SWIPE -> continue
                Mode.ALTERNATES -> if (frame.look.dimsKeyUnderAccents) add(touch.index)
                else -> if (!(showsCallouts && characterPreview == "attached" && cap.typed != null)) add(touch.index)
            }
        }
    }

    private val showsCallouts get() = characterPreview != "none"

    private fun preview(frame: Frame): Cap? {
        if (!showsCallouts) return null
        val touch = touches.values.lastOrNull { it.mode == Mode.TYPING || it.mode == Mode.SLIDE } ?: return null
        val cap = frame.caps.getOrNull(touch.index) ?: return null
        return if (cap.typed != null && cap.isInput && cap.action != "space") cap else null
    }

    private val callout = Path()

    private fun drawCallout(canvas: Canvas, frame: Frame, cap: Cap) {
        val r = frame.look.cornerRadius.toFloat()
        val key = RectF(cap.x.toFloat(), cap.y.toFloat(), cap.right.toFloat(), cap.bottom.toFloat())
        val top = -keysTop + 1
        val bubble: RectF
        callout.reset()
        if (characterPreview == "detached") {
            val w = key.width() * 1.4f
            val h = key.height() * 1.12f
            val left = (key.centerX() - w / 2).coerceIn(1f, frame.width.toFloat() - w - 1)
            bubble = RectF(left, (key.top - h - 6).coerceAtLeast(top), left + w, (key.top - h - 6).coerceAtLeast(top) + h)
            callout.addRoundRect(bubble, r * 1.4f, r * 1.4f, Path.Direction.CW)
        } else {
            val spread = key.width() * 0.32f
            val h = key.height() * 1.22f
            val neck = key.height() * 0.3f
            val left = (key.left - spread).coerceIn(1f, frame.width.toFloat() - key.width() - spread * 2 - 1)
            val y = (key.top - neck - h).coerceAtLeast(top)
            bubble = RectF(left, y, left + key.width() + spread * 2, y + h)
            val br = r * 1.4f
            val shoulder = bubble.bottom
            val neckTop = maxOf(key.top, shoulder + r)
            callout.moveTo(key.left + r, key.bottom)
            callout.arcTo(RectF(key.left, key.bottom - 2 * r, key.left + 2 * r, key.bottom), 90f, 90f)
            callout.lineTo(key.left, neckTop)
            callout.cubicTo(key.left, neckTop - (neckTop - shoulder) * 0.6f, bubble.left, shoulder + (neckTop - shoulder) * 0.2f, bubble.left, shoulder - br)
            callout.lineTo(bubble.left, bubble.top + br)
            callout.arcTo(RectF(bubble.left, bubble.top, bubble.left + 2 * br, bubble.top + 2 * br), 180f, 90f)
            callout.lineTo(bubble.right - br, bubble.top)
            callout.arcTo(RectF(bubble.right - 2 * br, bubble.top, bubble.right, bubble.top + 2 * br), 270f, 90f)
            callout.lineTo(bubble.right, shoulder - br)
            callout.cubicTo(bubble.right, shoulder + (neckTop - shoulder) * 0.2f, key.right, neckTop - (neckTop - shoulder) * 0.6f, key.right, neckTop)
            callout.lineTo(key.right, key.bottom - r)
            callout.arcTo(RectF(key.right - 2 * r, key.bottom - 2 * r, key.right, key.bottom), 0f, 90f)
            callout.close()
        }
        fill.color = frame.theme.bubble
        fill.setShadowLayer(2.5f, 0f, 1f, frame.theme.shadow)
        canvas.drawPath(callout, fill)
        fill.clearShadowLayer()
        text.typeface = painter.labels
        text.textSize = (frame.look.letterSize * 1.55 / 1.08).toFloat()
        text.color = frame.theme.bubbleLabel
        val label = cap.shown ?: cap.label
        val width = text.measureText(label)
        val metrics = text.fontMetrics
        val baseline = bubble.centerY() - frame.look.keyHeight.toFloat() * 0.06f - (metrics.ascent + metrics.descent) / 2
        canvas.drawText(label, bubble.centerX() - width / 2, baseline, text)
    }

    private fun showAccents(frame: Frame, cap: Cap, options: List<String>, symbols: Boolean, selected: Int) {
        val padding = 10f
        val cell = if (symbols) 50f else (cap.width + 4).toFloat()
        val height = (if (symbols) cap.height + 18 else cap.height * 1.57).toFloat()
        val highlight = (cap.height + if (symbols) 2 else 4).toFloat()
        val width = cell * options.size + padding * 2
        val x = (cap.x + cap.width / 2 - padding - cell * (selected + 0.5)).toFloat()
            .coerceAtLeast(7f).coerceAtMost((frame.width - width - 7).toFloat())
        val y = (cap.y - height - 3).toFloat().coerceAtLeast(-keysTop + 1)
        accents = Accents(options, symbols, RectF(x, y, x + width, y + height), cell, padding, highlight, selected)
    }

    private fun track(accents: Accents, x: Float) {
        accents.selected = floor((x - accents.box.left - accents.padding) / accents.cell).toInt()
            .coerceIn(0, accents.options.size - 1)
    }

    private fun drawAccents(canvas: Canvas, frame: Frame, accents: Accents) {
        val r = frame.look.cornerRadius.toFloat()
        fill.color = frame.theme.bubble
        fill.setShadowLayer(4f, 0f, 1f, frame.theme.shadow)
        canvas.drawRoundRect(accents.box, r * 2, r * 2, fill)
        fill.clearShadowLayer()
        val cellHeight = accents.highlight
        val left = accents.box.left + accents.padding + accents.selected * accents.cell
        val top = accents.box.centerY() - cellHeight / 2
        fill.color = frame.theme.selection
        canvas.drawRoundRect(RectF(left, top, left + accents.cell, top + cellHeight), r * 1.25f, r * 1.25f, fill)
        text.typeface = painter.letters
        text.textSize = frame.look.letterSize.toFloat()
        for ((index, option) in accents.options.withIndex()) {
            val color = if (index == accents.selected) frame.theme.selectionLabel else frame.theme.bubbleLabel
            val cx = accents.box.left + accents.padding + accents.cell * (index + 0.5f)
            if (accents.symbols) {
                fill.color = color
                Glyphs.draw(canvas, option, cx, accents.box.centerY(), Glyphs.square(frame.look.symbolSize.toFloat()), fill)
            } else {
                text.color = color
                val width = text.measureText(option)
                val metrics = text.fontMetrics
                canvas.drawText(option, cx - width / 2, accents.box.centerY() - (metrics.ascent + metrics.descent) / 2, text)
            }
        }
    }

    private companion object {
        const val TOP_ROW_REACH = 10f
        const val TITLE_GAP = 6f
        val TOOL_TITLES = mapOf("emoji" to "Emoji", "gif" to "GIFs", "transcripts" to "Transcripts", "clipboard" to "Clipboard")
        /** iOS's `BarLayout.emojiPitch`, and its 24 pt emoji at the size Noto's draw as wide as Apple's. */
        const val EMOJI_PITCH = 36f
        const val EMOJI_SIZE = 24f * 24f / 27f
        const val EMOJI_SLOP = 8f
        const val SWIPE_DISTANCE = 0.8
        const val DOUBLE_TAP = 350L
        const val ACCENT_HOLD = 450L
        const val TRACKPAD_HOLD = 400L
        const val MENU_HOLD = 500L
        val EDITS = listOf("cut", "copy", "paste")
        val EDIT_GLYPHS = mapOf("cut" to "scissors", "copy" to "square.on.square", "paste" to "doc.on.clipboard")
        val TOOL_GLYPHS = mapOf("emoji" to "face.smiling.inverse", "transcripts" to "text.bubble.fill", "clipboard" to "list.clipboard.fill")
    }
}
