package com.shahidy.iikb.app

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import com.shahidy.iikb.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.shahidy.iikb.Settings
import com.shahidy.iikb.app.clipboard.ClipboardPage
import com.shahidy.iikb.app.stats.StatsPage
import com.shahidy.iikb.app.stats.StatsSection
import com.shahidy.iikb.app.transcripts.TranscriptsPage

/** The tabs go under the keyboard while it's up, as iOS's do, so the page keeps the room above the keys. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun App(
    settings: Settings, setup: Setup, startPage: String?, onEnable: () -> Unit, onPick: () -> Unit,
    onMicrophone: () -> Unit, added: AddedComputer? = null,
) {
    val dark = isSystemInDarkTheme()
    val palette = if (dark) Palette.dark else Palette.light
    val colors = if (dark) {
        darkColorScheme(background = palette.page, surface = palette.page, primary = palette.accent)
    } else {
        lightColorScheme(background = palette.page, surface = palette.page, primary = palette.accent)
    }
    val store = remember { Store(settings) }
    DisposableEffect(store) { onDispose(store.listen()) }
    val access = Access(setup, onEnable, onPick, onMicrophone)
    CompositionLocalProvider(LocalPalette provides palette, LocalStore provides store, LocalAccess provides access) {
        MaterialTheme(colorScheme = colors, typography = Type.typography) {
            var page by rememberSaveable { mutableStateOf(startPage?.takeIf { it != MainActivity.VOICE }) }
            var tab by rememberSaveable { mutableIntStateOf(if (page != null) Tab.SETTINGS.ordinal else 0) }
            var stats by rememberSaveable { mutableStateOf(StatsSection.OVERVIEW) }
            var statsComputer by rememberSaveable { mutableStateOf<String?>(null) }
            LaunchedEffect(added) {
                added ?: return@LaunchedEffect
                statsComputer = added.name
                tab = Tab.STATS.ordinal
                page = null
            }
            BackHandler(enabled = page != null) { page = null }
            val backdrop = rememberLayerBackdrop()
            Scaffold(
                containerColor = palette.page,
                bottomBar = {
                    if (!WindowInsets.isImeVisible) {
                        TabBar(tab, backdrop) {
                            tab = it
                            page = null
                        }
                    }
                },
            ) { padding ->
                val bottom = PaddingValues(bottom = padding.calculateBottomPadding())
                CompositionLocalProvider(LocalTabBar provides bottom.calculateBottomPadding()) {
                Box(Modifier.consumeWindowInsets(bottom).layerBackdrop(backdrop)) {
                    when {
                        page != null -> SettingsPage(page!!) { page = null }
                        else -> when (Tab.entries[tab]) {
                            Tab.HOME -> Home(
                                open = {
                                    tab = Tab.SETTINGS.ordinal
                                    page = it
                                },
                            ) { to, section ->
                                section?.let { stats = it }
                                tab = to.ordinal
                            }
                            Tab.TRANSCRIPTS -> TranscriptsPage {
                                stats = StatsSection.DICTATION
                                tab = Tab.STATS.ordinal
                            }
                            Tab.CLIPBOARD -> ClipboardPage()
                            Tab.STATS -> StatsPage(stats, { stats = it }, statsComputer) { statsComputer = it }
                            Tab.SETTINGS -> SettingsList { page = it }
                        }
                    }
                }
                }
            }
        }
    }
}

/** A computer a link just added, for Stats to show; each link its own, so the same computer linked again shows again. */
class AddedComputer(val name: String)

/** The five tabs, by the SF Symbols iOS's tab bar fills (house, waveform, list.clipboard, chart.bar.xaxis, gearshape). */
enum class Tab(val title: String, val symbol: String) {
    HOME("iikb", "house.fill"),
    TRANSCRIPTS("Transcripts", "waveform"),
    CLIPBOARD("Clipboard", "list.clipboard.fill"),
    STATS("Stats", "chart.bar.xaxis"),
    SETTINGS("Settings", "gearshape.fill"),
}

/**
 * The tabs as iOS's tab bar draws them on an iPhone: a capsule of glass floating over the page's foot, the page
 * scrolling on under it, each tab its filled glyph over its name in the label's color, the picked one tinted on a
 * darker pill of its own.
 */
@Composable
private fun TabBar(tab: Int, backdrop: Backdrop, pick: (Int) -> Unit) {
    val palette = palette()
    val dark = palette == Palette.dark
    val capsule = RoundedCornerShape(percent = 50)
    Box(Modifier.fillMaxWidth().navigationBarsPadding().padding(start = 21.dp, end = 21.dp, top = 6.dp, bottom = 4.dp)) {
        Row(Modifier.fillMaxWidth().height(62.dp).glass(capsule, backdrop).padding(4.dp)) {
            Tab.entries.forEachIndexed { index, item ->
                val picked = index == tab
                val tint = if (picked) palette.accent else palette.label
                Column(
                    Modifier.weight(1f).fillMaxHeight().clip(capsule)
                        .background(if (picked) Color.Black.copy(alpha = if (dark) 0.42f else 0.08f) else Color.Transparent)
                        .clickable(interactionSource = null, indication = null) { pick(index) }
                        .semantics { role = Role.Tab; selected = picked },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icon(Symbols[item.symbol], null, tint = tint, modifier = Modifier.size(30.dp))
                    Text(
                        item.title, color = tint, fontSize = 10.sp, fontWeight = FontWeight.Medium, maxLines = 1,
                        modifier = Modifier.padding(top = 1.dp),
                    )
                }
            }
        }
    }
}

/** A 24-unit glyph from path data, stroked as the keyboard's are. */
fun glyph(data: String, width: Float = 1.7f): ImageVector = ImageVector.Builder(
    defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f,
).addPath(
    pathData = PathParser().parsePathString(data).toNodes(),
    stroke = SolidColor(Color.Black), strokeLineWidth = width,
    strokeLineCap = androidx.compose.ui.graphics.StrokeCap.Round,
    strokeLineJoin = androidx.compose.ui.graphics.StrokeJoin.Round,
).build()

/** How tall the tab bar is over the page's foot, for the page to scroll its end out from under it. */
val LocalTabBar = compositionLocalOf { 0.dp }

/** How many times the app has come forward, so a page reads again what the keyboard kept while it was away. */
val LocalResumes = compositionLocalOf { 0 }
