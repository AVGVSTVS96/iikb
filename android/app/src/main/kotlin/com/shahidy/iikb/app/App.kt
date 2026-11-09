package com.shahidy.iikb.app

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
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
import com.shahidy.iikb.Settings
import com.shahidy.iikb.app.design.Glyphs
import com.shahidy.iikb.app.stats.StatsPage
import com.shahidy.iikb.app.stats.StatsSection

/** The tabs go under the keyboard while it's up, as iOS's do, so the page keeps the room above the keys. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun App(
    settings: Settings, setup: Setup, startPage: String?, onEnable: () -> Unit, onPick: () -> Unit,
    onMicrophone: () -> Unit,
) {
    val dark = isSystemInDarkTheme()
    val palette = if (dark) Palette.dark else Palette.light
    val colors = if (dark) {
        darkColorScheme(background = palette.page, surface = palette.page, primary = palette.accent)
    } else {
        lightColorScheme(background = palette.page, surface = palette.page, primary = palette.accent)
    }
    val store = remember { Store(settings) }
    CompositionLocalProvider(LocalPalette provides palette, LocalStore provides store) {
        MaterialTheme(colorScheme = colors) {
            var tab by rememberSaveable { mutableIntStateOf(0) }
            var page by rememberSaveable { mutableStateOf(startPage?.takeIf { it != MainActivity.VOICE }) }
            var stats by rememberSaveable { mutableStateOf(StatsSection.OVERVIEW) }
            BackHandler(enabled = page != null) { page = null }
            Scaffold(
                containerColor = palette.page,
                bottomBar = {
                    if (page == null && !WindowInsets.isImeVisible) {
                        NavigationBar(containerColor = palette.card) {
                            Tab.entries.forEachIndexed { index, item ->
                                NavigationBarItem(
                                    selected = tab == index,
                                    onClick = { tab = index },
                                    icon = { Icon(item.icon, contentDescription = null) },
                                    label = { Text(item.title) },
                                    colors = NavigationBarItemDefaults.colors(
                                        selectedIconColor = palette.accent, selectedTextColor = palette.accent,
                                        indicatorColor = Color.Transparent, unselectedIconColor = palette.secondary,
                                        unselectedTextColor = palette.secondary,
                                    ),
                                )
                            }
                        }
                    }
                },
            ) { padding ->
                val bottom = PaddingValues(bottom = padding.calculateBottomPadding())
                Box(Modifier.padding(bottom).consumeWindowInsets(bottom)) {
                    when {
                        page != null -> SettingsPage(page!!) { page = null }
                        else -> when (Tab.entries[tab]) {
                            Tab.HOME -> Home(setup, onEnable, onPick, onMicrophone) { page = it }
                            Tab.STATS -> StatsPage(stats) { stats = it }
                            Tab.SETTINGS -> SettingsList { page = it }
                        }
                    }
                }
            }
        }
    }
}

enum class Tab(val title: String, val icon: ImageVector) {
    HOME("iikb", glyph("M5 6h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2Z M7 10h1m3 0h2m3 0h1M8 14h8")),
    STATS("Stats", glyph(Glyphs.CHART)),
    SETTINGS(
        "Settings",
        glyph(
            "M15 12a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z M12 2.5l1.6 2.4 2.8-.7.7 2.8 2.4 1.6-1.2 2.6 1.2 2.6-2.4 1.6-.7 2.8-2.8-.7L12 21.5l-1.6-2.4-2.8.7-.7-2.8-2.4-1.6L5.7 12 4.5 9.4l2.4-1.6.7-2.8 2.8.7Z",
        ),
    ),
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

/** How many times the app has come forward, so a page reads again what the keyboard kept while it was away. */
val LocalResumes = compositionLocalOf { 0 }
