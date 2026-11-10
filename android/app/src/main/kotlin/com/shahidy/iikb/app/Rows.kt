package com.shahidy.iikb.app

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import com.shahidy.iikb.Text
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import com.shahidy.iikb.R
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.unit.Constraints
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.drawPlainBackdrop
import com.kyant.backdrop.effects.blur
import com.shahidy.iikb.app.design.isDark
import com.shahidy.iikb.app.design.Tints

/** iOS's Dynamic Type sizes at Large, which the iOS app's text takes. */
object Type {
    val body = 17.sp
    val subheadline = 15.sp
    val footnote = 13.sp
    val title3 = 20.sp

    /** SF Mono's stand-in, Roboto Mono, bundled since Android's own monospace has no slashed zero. */
    val mono = FontFamily(Font(R.font.roboto_mono))

    /**
     * Material's styles set as SF Pro's text sizes run: a line of text as tall as its font, as UIKit sets one, lines
     * apart by iOS's leading at that size, and tracked a little open, since Roboto is narrower than SF Pro and would fit
     * more on each line.
     */
    val typography = Typography().run {
        val ios = { style: TextStyle ->
            style.copy(
                letterSpacing = 0.01.em, lineHeight = 1.3.em,
                lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.Both),
            )
        }
        Typography(
            ios(displayLarge), ios(displayMedium), ios(displaySmall), ios(headlineLarge), ios(headlineMedium),
            ios(headlineSmall), ios(titleLarge), ios(titleMedium), ios(titleSmall), ios(bodyLarge),
            ios(bodyMedium), ios(bodySmall), ios(labelLarge), ios(labelMedium), ios(labelSmall),
        )
    }
}

/** Rounded rectangles as iOS's continuous corners come closest to on Android. */
val CardShape = RoundedCornerShape(22.dp)

/**
 * A page: its title and buttons in a bar pinned at the top, as iOS's navigation bar holds them, over a column of
 * sections 28 apart that scrolls under it. A tab's page has a large title until it scrolls (iOS's `.inlineLarge`);
 * one opened from another (`onBack`) a small one. It makes room for the keyboard unless it lies `underKeyboard`, as
 * Home does (iOS's `.ignoresSafeArea(.keyboard)`).
 */
@Composable
fun Page(
    title: String, onBack: (() -> Unit)? = null, pinned: (@Composable () -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {}, underKeyboard: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val scroll = rememberScrollState()
    val scrolled by remember { derivedStateOf { scroll.value > 0 } }
    Frame(title, onBack, scrolled, pinned, actions) { top ->
        Column(
            Modifier.fillMaxSize().let { if (underKeyboard) it else it.imePadding() }.verticalScroll(scroll)
                .padding(start = 16.dp, end = 16.dp, top = top + 8.dp, bottom = 40.dp + if (underKeyboard) LocalTabBarUnderKeys.current else LocalTabBar.current),
            verticalArrangement = Arrangement.spacedBy(28.dp),
            content = content,
        )
    }
}

/** A page of rows made as they scroll into view, for a list that can grow long. */
@Composable
fun ListPage(
    title: String, onBack: (() -> Unit)? = null, pinned: (@Composable () -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {}, content: LazyListScope.() -> Unit,
) {
    val list = rememberLazyListState()
    val scrolled by remember { derivedStateOf { list.firstVisibleItemIndex > 0 || list.firstVisibleItemScrollOffset > 0 } }
    Frame(title, onBack, scrolled, pinned, actions) { top ->
        LazyColumn(
            Modifier.fillMaxSize().imePadding(),
            state = list,
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = top + 8.dp, bottom = 40.dp + LocalTabBar.current),
        ) { content() }
    }
}

/**
 * A page's bar, its title, Back and buttons, with what's pinned under it, over what scrolls, which starts `top` down
 * and runs under the bar and the status bar. Once it's under them they blur and wash it out to a hard edge at the
 * bar's foot, as iOS 26's navigation bar does with its own background hidden; what's pinned keeps the page's color
 * behind it, as iOS's inset rows do, so there nothing shows through. The page's color is in what blurs, so text on the
 * bare page, like a section's footer, blurs as a card's does rather than showing through the wash.
 */
@Composable
private fun Frame(
    title: String, onBack: (() -> Unit)?, scrolled: Boolean, pinned: (@Composable () -> Unit)?,
    actions: @Composable RowScope.() -> Unit, content: @Composable (top: Dp) -> Unit,
) {
    val palette = palette()
    val backdrop = rememberLayerBackdrop()
    val under by animateFloatAsState(if (scrolled && pinned == null) 1f else 0f, tween(150), label = "edge")
    SubcomposeLayout(Modifier.fillMaxSize().background(palette.page)) { constraints ->
        val loose = constraints.copy(minHeight = 0)
        val header = subcompose("header") {
            Column(
                Modifier.fillMaxWidth().let { if (pinned != null) it.background(palette.page) else it }
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top)),
            ) {
                Bar(title, onBack, scrolled, actions)
                pinned?.let { Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp)) { it() } }
            }
        }.map { it.measure(loose) }
        val height = header.maxOfOrNull { it.height } ?: 0
        val body = subcompose("content") {
            Box(Modifier.fillMaxSize().layerBackdrop(backdrop).background(palette.page)) { content(height.toDp()) }
        }.map { it.measure(constraints) }
        val edge = subcompose("edge") {
            Box(Modifier.fillMaxSize().scrollEdge(backdrop, under))
        }.map { it.measure(Constraints.fixed(constraints.maxWidth, height)) }
        layout(constraints.maxWidth, constraints.maxHeight) {
            body.forEach { it.place(0, 0) }
            edge.forEach { it.place(0, 0) }
            header.forEach { it.place(0, 0) }
        }
    }
}

/** iOS 26's scroll edge under a bar: what's under it blurred and washed toward white in light and near black in dark. */
@Composable
private fun Modifier.scrollEdge(backdrop: Backdrop, shown: Float): Modifier {
    if (shown == 0f) return this
    val wash = if (palette().isDark) Color(0xFF121212).copy(alpha = 0.7f) else Color.White.copy(alpha = 0.7f)
    return drawPlainBackdrop(
        backdrop, { RectangleShape },
        effects = { blur(4.dp.toPx()) },
        layerBlock = { alpha = shown },
        onDrawSurface = { drawRect(wash) },
    )
}

/**
 * iOS's navigation bar: Back at the left, the buttons at the right, and the small title centered on the screen, or
 * just after Back when centered it would run into either. A tab's large title sits at the left until the page scrolls,
 * then gives way to the small one.
 */
@Composable
private fun Bar(title: String, onBack: (() -> Unit)?, scrolled: Boolean, actions: @Composable RowScope.() -> Unit) {
    val palette = palette()
    val small by animateFloatAsState(if (onBack != null || scrolled) 1f else 0f, tween(200), label = "title")
    Layout(
        content = {
            if (onBack != null) {
                Box(
                    Modifier.layoutId("back").size(44.dp).glass(CircleShape).clip(CircleShape).clickable(onClick = onBack),
                    contentAlignment = Alignment.Center,
                ) { Icon(Symbols["chevron.left"], "Back", tint = palette.label, modifier = Modifier.size(30.dp)) }
            } else {
                Text(
                    title, color = palette.label, fontSize = 34.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.02).em,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.layoutId("large").padding(start = 4.dp).alpha(1 - small),
                )
            }
            Text(
                title, color = palette.label, fontSize = Type.body, fontWeight = FontWeight.SemiBold, maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.layoutId("small").alpha(small),
            )
            Row(Modifier.layoutId("actions"), verticalAlignment = Alignment.CenterVertically, content = actions)
        },
        modifier = Modifier.fillMaxWidth().heightIn(min = 60.dp).padding(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 6.dp),
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val gap = 14.dp.roundToPx()
        fun part(id: String) = measurables.firstOrNull { it.layoutId == id }
        val back = part("back")?.measure(loose)
        val trailing = part("actions")!!.measure(loose)
        val end = width - trailing.width - if (trailing.width > 0) gap else 0
        val start = back?.let { it.width + gap } ?: 0
        val large = part("large")?.measure(loose.copy(maxWidth = maxOf(end, 0)))
        val inline = part("small")!!.measure(loose.copy(maxWidth = maxOf(end - start, 0)))
        val height = maxOf(constraints.minHeight, back?.height ?: 0, trailing.height, large?.height ?: 0, inline.height)
        layout(width, height) {
            fun Placeable.center(x: Int) = place(x, (height - this.height) / 2)
            back?.center(0)
            large?.center(0)
            trailing.center(width - trailing.width)
            val centered = (width - inline.width) / 2
            inline.center(if (centered >= start && centered + inline.width <= end) centered else start)
        }
    }
}

/** A card of rows under a gray header and over a gray footer (iOS's `Box`). */
@Composable
fun Section(header: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val palette = palette()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (header != null) {
            Text(
                header, color = palette.secondary, fontSize = Type.subheadline, fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(horizontal = 20.dp),
            )
        }
        Column(
            Modifier.fillMaxWidth().clip(CardShape).background(palette.card).border(BorderStroke(1.dp, palette.edge), CardShape),
            content = content,
        )
        if (footer != null) {
            Text(
                footer, color = palette.secondary, fontSize = Type.footnote, lineHeight = 18.sp,
                modifier = Modifier.padding(horizontal = 20.dp).widthIn(max = 560.dp),
            )
        }
    }
}

/** The hairline between two rows of a card, inset from its leading edge. */
@Composable
fun Divider() = Box(Modifier.padding(start = 20.dp, end = 1.dp).fillMaxWidth().height(1.dp).background(palette().divider))

/** A row's title and, under it, a line on what it does. */
@Composable
fun RowText(title: String, detail: String? = null, modifier: Modifier = Modifier, color: Color = palette().label) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(title, color = color, fontSize = Type.body)
        if (detail != null) Text(detail, color = palette().secondary, fontSize = Type.subheadline, lineHeight = 20.sp)
    }
}

/** A row's padding and height, the same for every kind of row. */
fun Modifier.row() = fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 20.dp, vertical = 14.dp)

/** A row: its text, then whatever sits at its right. */
@Composable
fun Line(
    title: String, detail: String? = null, value: String? = null, onClick: (() -> Unit)? = null,
    color: Color? = null, trailing: @Composable (() -> Unit)? = null,
) {
    val palette = palette()
    Row(
        Modifier.let { if (onClick != null) it.clickable(onClick = onClick) else it }.row(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        RowText(title, detail, Modifier.weight(1f), color ?: palette.label)
        if (value != null) Text(value, color = palette.secondary, fontSize = Type.body, maxLines = 1)
        trailing?.invoke()
    }
}

/** A small gray symbol at a row's right: a chevron for a page, an arrow for what leaves the app. */
@Composable
fun Trailing(symbol: String, tint: Color = palette().secondary) =
    Icon(Symbols[symbol], null, tint = tint, modifier = Modifier.size(16.dp))

/** A white symbol on a colored rounded square, as Raycast's More page draws its commands (iOS's `Glyph`). */
@Composable
fun Glyph(symbol: String, color: Color, size: Dp = 30.dp) {
    Box(
        Modifier.size(size).clip(RoundedCornerShape(size * 0.26f))
            .background(Hues.gradient(color)),
        contentAlignment = Alignment.Center,
    ) { Icon(Symbols[symbol], null, tint = Color.White, modifier = Modifier.size(size * 0.68f)) }
}

/** A row that opens a page, with what it's set to and a chevron. */
@Composable
fun Link(title: String, value: String? = null, detail: String? = null, onClick: () -> Unit) {
    Line(title, detail, value, onClick) { Trailing("chevron.right") }
}

/** A row that does something, in the accent or, for what can't be undone, red; dimmed while it can't. */
@Composable
fun ActionRow(
    title: String, symbol: String? = null, destructive: Boolean = false, enabled: Boolean = true, onClick: () -> Unit,
) {
    val palette = palette()
    val color = if (destructive) palette.red else palette.accent
    Row(
        Modifier.clickable(enabled = enabled, onClick = onClick).row().alpha(if (enabled) 1f else 0.4f),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = color, fontSize = Type.body, modifier = Modifier.weight(1f))
        if (symbol != null) Icon(Symbols[symbol], null, tint = color, modifier = Modifier.size(17.dp))
    }
}

/** Raycast's radio mark: a gray ring, or a filled circle with a check when picked. */
@Composable
fun Radio(on: Boolean) {
    val palette = palette()
    val fill by animateFloatAsState(if (on) 1f else 0f, label = "radio")
    Box(
        Modifier.size(26.dp).clip(CircleShape)
            .border(BorderStroke(1.5.dp, palette.secondary.copy(alpha = 0.9f * (1 - fill))), CircleShape)
            .background(palette.selected.copy(alpha = fill)),
        contentAlignment = Alignment.Center,
    ) {
        if (on) Icon(Symbols["checkmark"], null, tint = palette.selectedLabel, modifier = Modifier.size(17.7.dp))
    }
}

/** One of a setting's values, with the radio mark at its right. */
@Composable
fun ChoiceRow(title: String, detail: String? = null, picked: Boolean, onClick: () -> Unit) {
    Line(title, detail, onClick = onClick) { Radio(picked) }
}

/** A switch row for a setting kept by `name`. */
@Composable
fun Toggle(title: String, name: String, detail: String? = null) {
    val store = LocalStore.current
    val on = store.bool(name)
    Line(title, detail, onClick = { store.set(name, !on) }) { Switch(on) { store.set(name, it) } }
}

/** A switch as iOS 26's: a capsule knob the same size on and off, sliding over a gray (`off`) or accent track. */
@Composable
fun Switch(on: Boolean, off: Color = palette().track, onChange: (Boolean) -> Unit) {
    val palette = palette()
    val knob by animateDpAsState(if (on) 22.dp else 2.dp, label = "knob")
    val track by animateColorAsState(if (on) palette.accent else off, label = "track")
    Box(Modifier.size(62.dp, 28.dp).clip(CircleShape).background(track).clickable { onChange(!on) }) {
        Box(Modifier.padding(start = knob, top = 2.dp).size(38.dp, 24.dp).shadow(2.dp, CircleShape).background(Color.White, CircleShape))
    }
}

/** One value from a list, each a row with a radio mark at its right. */
@Composable
fun Choices(name: String, options: List<Pair<String, String>>, details: Map<String, String> = emptyMap()) {
    val store = LocalStore.current
    val picked = store.string(name)
    options.forEachIndexed { index, (value, title) ->
        if (index > 0) Divider()
        ChoiceRow(title, details[value], picked == value) { store.set(name, value) }
    }
}

/** A row whose value opens a menu of the others, as Raycast's pop-up rows do (iOS's `MenuRow`). */
@Composable
fun MenuRow(title: String, name: String, choices: List<Pair<String, String>>) {
    val store = LocalStore.current
    MenuRow(title, store.string(name), choices) { store.set(name, it) }
}

@Composable
fun MenuRow(title: String, picked: String, choices: List<Pair<String, String>>, pick: (String) -> Unit) {
    val palette = palette()
    var open by remember { mutableStateOf(false) }
    Box {
        Line(title, value = choices.firstOrNull { it.first == picked }?.second, onClick = { open = true }) {
            Trailing("chevron.up.chevron.down")
        }
        DropdownMenu(
            open, { open = false }, Modifier.background(palette.card), shape = RoundedCornerShape(14.dp),
            containerColor = palette.card,
        ) {
            choices.forEach { (value, label) ->
                DropdownMenuItem(
                    text = { Text(label, color = palette.label, fontSize = Type.body) },
                    leadingIcon = {
                        Box(Modifier.width(18.dp)) {
                            if (value == picked) Icon(Symbols["checkmark"], null, tint = palette.label, modifier = Modifier.size(15.dp))
                        }
                    },
                    onClick = {
                        pick(value)
                        open = false
                    },
                )
            }
        }
    }
}

/** Stops on one track, Standard in the middle, named at its ends, the picked one's name beside the title (iOS's `StopSlider`). */
@Composable
fun Stops(title: String, name: String, stops: List<Pair<String, String>>, low: String, high: String, picked: (String) -> Unit = {}) {
    val store = LocalStore.current
    val palette = palette()
    val index = stops.indexOfFirst { it.first == store.string(name) }.takeIf { it >= 0 } ?: (stops.size / 2)
    val pick = { stop: Int ->
        val next = stops[stop.coerceIn(stops.indices)].first
        if (next != stops[index].first) {
            store.set(name, next)
            picked(next)
        }
    }
    Column(Modifier.row(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row {
            Text(title, color = palette.label, fontSize = Type.body, modifier = Modifier.weight(1f))
            Text(stops[index].second, color = palette.secondary, fontSize = Type.body)
        }
        val position by animateFloatAsState(index.toFloat(), label = "stop")
        Canvas(
            Modifier.fillMaxWidth().height(28.dp)
                .pointerInput(stops) {
                    detectTapGestures { pick(((it.x - 14.dp.toPx()) / ((size.width - 28.dp.toPx()) / (stops.size - 1))).let(Math::round)) }
                }
                .pointerInput(stops, index) {
                    detectHorizontalDragGestures { change, _ ->
                        pick(((change.position.x - 14.dp.toPx()) / ((size.width - 28.dp.toPx()) / (stops.size - 1))).let(Math::round))
                    }
                },
        ) {
            val thumb = 28.dp.toPx()
            val step = (size.width - thumb) / (stops.size - 1)
            val y = size.height / 2
            val x = thumb / 2 + position * step
            drawLine(palette.divider, Offset(thumb / 2, y), Offset(size.width - thumb / 2, y), 4.dp.toPx(), StrokeCap.Round)
            drawLine(palette.accent, Offset(thumb / 2, y), Offset(x, y), 4.dp.toPx(), StrokeCap.Round)
            for (stop in stops.indices) {
                val color = if (stop <= index) palette.accent else palette.secondary.copy(alpha = 0.45f)
                drawCircle(color, 4.dp.toPx(), Offset(thumb / 2 + stop * step, y))
            }
            drawIntoCanvas {
                val paint = Paint().asFrameworkPaint().apply {
                    isAntiAlias = true
                    color = android.graphics.Color.WHITE
                    setShadowLayer(3.dp.toPx(), 0f, 1.dp.toPx(), Color.Black.copy(alpha = 0.25f).toArgb())
                }
                it.nativeCanvas.drawCircle(x, y, thumb / 2, paint)
            }
        }
        Box(Modifier.fillMaxWidth()) {
            val style = TextStyle(color = palette.secondary, fontSize = Type.footnote)
            Text(low, style = style, modifier = Modifier.align(Alignment.CenterStart))
            Text("Standard", style = style, textAlign = TextAlign.Center, modifier = Modifier.align(Alignment.Center))
            Text(high, style = style, modifier = Modifier.align(Alignment.CenterEnd))
        }
    }
}

/** A press that dims a card the way Raycast's do. */
@Composable
fun Modifier.cardPress(onClick: () -> Unit): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.98f else 1f, label = "press")
    return scale(scale).alpha(if (pressed) 0.7f else 1f).clickable(interaction, indication = null, onClick = onClick)
}

/** A card in the app's look: its edge, fill and corner (iOS's `.background(Color.appCard, in: …)` with its edge). */
@Composable
fun Modifier.card() = clip(CardShape).background(palette().card).border(BorderStroke(1.dp, palette().edge), CardShape)

/**
 * A Raycast tile: a glyph at its top left and a title and a line in gray at its bottom left, as a widget sets them
 * out when it's taller than they need.
 */
@Composable
fun Tile(symbol: String, color: Color, title: String, detail: String?, modifier: Modifier = Modifier) {
    val palette = palette()
    Column(
        modifier.card().heightIn(min = 128.dp).padding(18.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Glyph(symbol, color, 34.dp)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = palette.label, fontSize = Type.body, fontWeight = FontWeight.Medium, maxLines = 2)
            if (detail != null) Text(detail, color = palette.secondary, fontSize = Type.footnote, maxLines = 2)
        }
    }
}

/** A form's one-line field, its placeholder in gray while it's empty. */
@Composable
fun FormField(
    value: String, placeholder: String, options: KeyboardOptions = KeyboardOptions.Default,
    transformation: VisualTransformation = VisualTransformation.None, change: (String) -> Unit,
) {
    val palette = palette()
    BasicTextField(
        value, change, singleLine = true,
        textStyle = TextStyle(color = palette.label, fontSize = Type.body),
        cursorBrush = SolidColor(palette.accent), keyboardOptions = options, visualTransformation = transformation,
        modifier = Modifier.fillMaxWidth().row(),
        decorationBox = { inner ->
            Box(contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty()) Text(placeholder, color = Tints.placeholder(palette), fontSize = Type.body)
                inner()
            }
        },
    )
}
