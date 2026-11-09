package com.shahidy.iikb.app

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun Page(
    title: String, onBack: (() -> Unit)? = null, pinned: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    Frame(title, onBack, pinned) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).imePadding().verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
        ) {
            content()
            Spacer(Modifier.height(32.dp))
        }
    }
}

/** A page's large title, collapsing as it scrolls, with its Back and what's pinned under it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Frame(
    title: String, onBack: (() -> Unit)?, pinned: (@Composable () -> Unit)?,
    content: @Composable (PaddingValues) -> Unit,
) {
    val palette = palette()
    val behavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())
    Scaffold(
        modifier = Modifier.nestedScroll(behavior.nestedScrollConnection),
        containerColor = palette.page,
        topBar = {
            Column(Modifier.background(palette.page)) {
                LargeTopAppBar(
                    title = { Text(title, fontWeight = FontWeight.Bold) },
                    navigationIcon = {
                        if (onBack != null) {
                            IconButton(onClick = onBack) { Icon(glyph("M15 4.5 7.5 12l7.5 7.5"), "Back") }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = palette.page, scrolledContainerColor = palette.page,
                        titleContentColor = palette.label, navigationIconContentColor = palette.label,
                    ),
                    expandedHeight = 104.dp,
                    scrollBehavior = behavior,
                )
                pinned?.let { Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp)) { it() } }
            }
        },
        content = content,
    )
}

@Composable
fun Section(header: String? = null, footer: String? = null, content: @Composable () -> Unit) {
    val palette = palette()
    Column(Modifier.padding(top = 20.dp)) {
        if (header != null) {
            Text(header, color = palette.secondary, fontSize = 13.sp, modifier = Modifier.padding(start = 16.dp, bottom = 8.dp))
        }
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(palette.card)
                .border(BorderStroke(1.dp, palette.edge), RoundedCornerShape(22.dp)),
        ) { content() }
        if (footer != null) {
            Text(footer, color = palette.secondary, fontSize = 13.sp, modifier = Modifier.padding(start = 16.dp, top = 8.dp, end = 16.dp))
        }
    }
}

@Composable
fun Line(
    title: String, detail: String? = null, value: String? = null, onClick: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    val palette = palette()
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, color = palette.label, fontSize = 17.sp)
            if (detail != null) Text(detail, color = palette.secondary, fontSize = 13.sp)
        }
        if (value != null) Text(value, color = palette.secondary, fontSize = 17.sp)
        trailing?.invoke()
    }
}

/** A row that opens a page, with its value and a chevron. */
@Composable
fun Link(title: String, value: String? = null, onClick: () -> Unit) {
    val palette = palette()
    Line(title, value = value, onClick = onClick) {
        Icon(
            glyph("M9 4.5l7.5 7.5L9 19.5"), null, tint = palette.secondary,
            modifier = Modifier.padding(start = 8.dp).size(16.dp),
        )
    }
}

@Composable
fun Divider() = HorizontalDivider(Modifier.padding(start = 16.dp), thickness = 0.5.dp, color = palette().edge)

@Composable
fun Radio(on: Boolean) {
    val palette = palette()
    Box(
        Modifier.size(22.dp).clip(CircleShape)
            .background(if (on) palette.selected else Color.Transparent)
            .border(BorderStroke(1.5.dp, if (on) palette.selected else palette.secondary), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (on) Icon(glyph("M6 12.5l4 4L18 8"), null, tint = palette.selectedLabel, modifier = Modifier.size(16.dp))
    }
}

@Composable
fun Toggle(title: String, name: String, detail: String? = null) {
    val store = LocalStore.current
    val on = store.bool(name)
    val palette = palette()
    Line(title, detail, onClick = { store.set(name, !on) }) {
        Switch(on, palette) { store.set(name, it) }
    }
}

/** A switch as the iOS app's: a round knob the same size on and off, sliding over a gray or accent track. */
@Composable
private fun Switch(on: Boolean, palette: Palette, onChange: (Boolean) -> Unit) {
    val knob by animateDpAsState(if (on) 22.dp else 2.dp, label = "knob")
    val track by animateColorAsState(if (on) palette.accent else palette.track, label = "track")
    Box(
        Modifier.padding(start = 12.dp).size(51.dp, 31.dp).clip(CircleShape).background(track)
            .clickable { onChange(!on) },
    ) {
        Box(
            Modifier.padding(start = knob, top = 2.dp).size(27.dp)
                .shadow(2.dp, CircleShape).background(Color.White, CircleShape),
        )
    }
}

/** One value from a list, each a row with a radio mark at its right. */
@Composable
fun Choices(name: String, options: List<Pair<String, String>>, details: Map<String, String> = emptyMap()) {
    val store = LocalStore.current
    val picked = store.string(name)
    options.forEachIndexed { index, (value, title) ->
        if (index > 0) Divider()
        Line(title, details[value], onClick = { store.set(name, value) }) { Radio(picked == value) }
    }
}

/** Stops on a slider, the middle one Standard, named at its ends. */
@Composable
fun Stops(title: String, name: String, stops: List<String>, low: String, high: String) {
    val store = LocalStore.current
    val palette = palette()
    val index = stops.indexOf(store.string(name)).coerceAtLeast(0)
    Column(Modifier.padding(16.dp)) {
        Text(title, color = palette.label, fontSize = 17.sp)
        Slider(
            value = index.toFloat(), onValueChange = { store.set(name, stops[it.toInt().coerceIn(stops.indices)]) },
            valueRange = 0f..(stops.size - 1).toFloat(), steps = stops.size - 2,
            colors = SliderDefaults.colors(
                activeTrackColor = palette.accent, inactiveTrackColor = palette.edge, thumbColor = palette.accent,
                activeTickColor = Color.White, inactiveTickColor = palette.secondary,
            ),
        )
        Row {
            Text(low, color = palette.secondary, fontSize = 13.sp)
            Spacer(Modifier.weight(1f))
            Text(high, color = palette.secondary, fontSize = 13.sp)
        }
    }
}
