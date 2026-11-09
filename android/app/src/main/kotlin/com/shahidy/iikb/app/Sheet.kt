package com.shahidy.iikb.app

import androidx.compose.foundation.background
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.FlingBehavior
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.ScrollScope
import androidx.compose.foundation.gestures.rememberScrollableState
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.statusBars
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import com.shahidy.iikb.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shahidy.iikb.app.design.isDark

/**
 * iOS's form sheet at its medium and large heights: floating 8 off the screen's edges over the page dimmed behind it,
 * a grabber at its top, its title between Cancel and what it's for, which turns accent once it can, over sections that
 * scroll. Dragged up, or its sections scrolled, it grows to the large height and settles at the nearer one; dragged
 * down from the medium height it closes. It rides up on the keyboard.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Sheet(
    title: String, action: String, enabled: Boolean, close: () -> Unit, confirm: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val palette = palette()
    val density = LocalDensity.current
    val screen = with(density) { LocalWindowInfo.current.containerSize.height.toDp() }
    val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    // iOS's medium detent, measured on an iPhone 17 Pro: its top 415 of 874 pt down the screen; its large 10 under the status bar.
    val detents = with(density) { (screen * (1 - 415f / 874) - 8.dp).toPx() to (screen - top - 10.dp - 8.dp).toPx() }
    var height by remember { mutableFloatStateOf(detents.first) }
    val grow = rememberScrollableState { delta ->
        val next = (height - delta).coerceIn(detents.first, detents.second)
        val used = height - next
        height = next
        -used
    }
    val settle = remember(detents) {
        object : FlingBehavior {
            override suspend fun ScrollScope.performFling(initialVelocity: Float): Float {
                val (medium, large) = detents
                if (height <= medium && initialVelocity > 0) return initialVelocity
                val target = when {
                    initialVelocity < -600 -> large
                    initialVelocity > 600 -> medium
                    else -> if (height - medium > (large - medium) / 2) large else medium
                }
                animate(height, target, initialVelocity = -initialVelocity, animationSpec = spring(stiffness = Spring.StiffnessMediumLow)) { value, _ ->
                    height = value
                }
                return 0f
            }
        }
    }
    ModalBottomSheet(
        close, Modifier.imePadding().padding(start = 8.dp, end = 8.dp, bottom = 8.dp),
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        shape = RoundedCornerShape(38.dp), containerColor = palette.page,
        scrimColor = Color.Black.copy(alpha = if (palette.isDark) 0.48f else 0.2f),
        dragHandle = null, contentWindowInsets = { WindowInsets(0) },
    ) {
        Box(
            Modifier.fillMaxWidth().height(with(density) { height.toDp() })
                .scrollable(grow, Orientation.Vertical, flingBehavior = settle),
        ) {
            Column {
                Row(Modifier.fillMaxWidth().padding(start = 14.5.dp, end = 14.5.dp, top = 15.5.dp), verticalAlignment = Alignment.CenterVertically) {
                    SheetButton("Cancel", enabled = true, prominent = false, onClick = close)
                    Text(
                        title, color = palette.label, fontSize = Type.body, fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center, maxLines = 1, modifier = Modifier.weight(1f),
                    )
                    SheetButton(action, enabled, prominent = true, onClick = confirm)
                }
                Column(
                    Modifier.verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 18.dp, bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(28.dp),
                    content = content,
                )
            }
            Box(
                Modifier.align(Alignment.TopCenter).padding(top = 5.67.dp).size(57.dp, 4.dp).clip(CircleShape)
                    .background(if (palette.isDark) Color(0x4DEBEBF5) else Color(0x4D3C3C43)),
            )
        }
    }
}

/** Cancel, a glass capsule, or what the sheet is for, filled with the accent once it can be done and glass till then. */
@Composable
private fun SheetButton(title: String, enabled: Boolean, prominent: Boolean, onClick: () -> Unit) {
    val palette = palette()
    val filled = prominent && enabled
    Box(
        Modifier.height(44.dp).let { if (filled) it.clip(CircleShape).background(palette.accent) else it.glass(CircleShape).clip(CircleShape) }
            .clickable(enabled, onClick = onClick).padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title, fontSize = Type.body, fontWeight = if (filled) FontWeight.SemiBold else FontWeight.Medium,
            color = when {
                filled -> Color.White
                enabled -> palette.label
                else -> palette.label.copy(alpha = 0.3f)
            },
        )
    }
}
