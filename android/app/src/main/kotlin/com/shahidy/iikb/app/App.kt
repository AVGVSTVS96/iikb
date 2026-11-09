package com.shahidy.iikb.app

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.ExperimentalLayoutApi
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
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.Settings

/** The look of Raycast's app (docs/design.md, "The app"): black pages, cards with a hairline edge, blue switches. */
data class Palette(
    val page: Color, val card: Color, val edge: Color, val label: Color, val secondary: Color, val accent: Color,
    val selected: Color, val selectedLabel: Color, val track: Color,
)

val LocalPalette = staticCompositionLocalOf {
    Palette(
        Color.Black, Color(0xFF1C1C1E), Color(0x1FFFFFFF), Color.White, Color(0xFF8E8E93), Color(0xFF0A84FF),
        Color.White, Color.Black, Color(0xFF39393D),
    )
}

@Composable
fun palette() = LocalPalette.current

/** The tabs go under the keyboard while it's up, as iOS's do, so the page keeps the room above the keys. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun App(
    settings: Settings, setup: Setup, startPage: String?, onEnable: () -> Unit, onPick: () -> Unit,
    onMicrophone: () -> Unit,
) {
    val dark = isSystemInDarkTheme()
    val palette = if (dark) {
        LocalPalette.current
    } else {
        Palette(
            Color(0xFFF2F2F5), Color.White, Color(0x14000000), Color.Black, Color(0xFF6C6C70), Color(0xFF007AFF),
            Color.Black, Color.White, Color(0xFFE9E9EA),
        )
    }
    val colors = if (dark) {
        darkColorScheme(background = palette.page, surface = palette.page, primary = palette.accent)
    } else {
        lightColorScheme(background = palette.page, surface = palette.page, primary = palette.accent)
    }
    val store = remember { Store(settings) }
    CompositionLocalProvider(LocalPalette provides palette, LocalStore provides store) {
        MaterialTheme(colorScheme = colors) {
            var tab by rememberSaveable { mutableIntStateOf(0) }
            var page by rememberSaveable { mutableStateOf<String?>(null) }
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
                        Tab.entries[tab] == Tab.HOME -> Home(setup, onEnable, onPick, onMicrophone) { page = it }
                        else -> SettingsList { page = it }
                    }
                }
            }
        }
    }
}

enum class Tab(val title: String, val icon: ImageVector) {
    HOME("iikb", glyph("M5 6h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2Z M7 10h1m3 0h2m3 0h1M8 14h8")),
    SETTINGS(
        "Settings",
        glyph(
            "M15 12a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z M12 2.5l1.6 2.4 2.8-.7.7 2.8 2.4 1.6-1.2 2.6 1.2 2.6-2.4 1.6-.7 2.8-2.8-.7L12 21.5l-1.6-2.4-2.8.7-.7-2.8-2.4-1.6L5.7 12 4.5 9.4l2.4-1.6.7-2.8 2.8.7Z",
        ),
    ),
}

/** A 24-unit glyph from path data, stroked as the keyboard's are. */
fun glyph(data: String): ImageVector = ImageVector.Builder(
    defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f,
).addPath(
    pathData = PathParser().parsePathString(data).toNodes(),
    stroke = SolidColor(Color.Black), strokeLineWidth = 1.7f,
    strokeLineCap = androidx.compose.ui.graphics.StrokeCap.Round,
    strokeLineJoin = androidx.compose.ui.graphics.StrokeJoin.Round,
).build()

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Page(title: String, onBack: (() -> Unit)? = null, content: @Composable () -> Unit) {
    val palette = palette()
    val behavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(rememberTopAppBarState())
    Scaffold(
        modifier = Modifier.nestedScroll(behavior.nestedScrollConnection),
        containerColor = palette.page,
        topBar = {
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
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).imePadding().verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
        ) {
            content()
            Spacer(Modifier.height(32.dp))
        }
    }
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

@Composable
fun Home(setup: Setup, onEnable: () -> Unit, onPick: () -> Unit, onMicrophone: () -> Unit, open: (String) -> Unit) {
    val palette = palette()
    Page("iikb") {
        Section {
            var text by remember { mutableStateOf("") }
            BasicTextField(
                value = text, onValueChange = { text = it },
                textStyle = TextStyle(color = palette.label, fontSize = 17.sp),
                cursorBrush = SolidColor(palette.accent),
                modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp).padding(16.dp),
                decorationBox = { inner ->
                    if (text.isEmpty()) Text("Tap here to try iikb", color = palette.secondary, fontSize = 17.sp)
                    inner()
                },
            )
        }
        if (!setup.done) {
            Section("Set up", "iikb needs the microphone only for voice typing.") {
                Step("Turn on iikb", "In Android's keyboard settings", setup.enabled, onEnable)
                Divider()
                Step("Switch to iikb", "Pick iikb as your keyboard", setup.picked, onPick)
                Divider()
                Step("Allow the microphone", "For voice typing, right in the keyboard", setup.microphone, onMicrophone)
            }
        }
        Section("Keyboard") {
            Link("Appearance", value = LocalStore.current.themeTitle()) { open("appearance") }
            Divider()
            Link("Typing") { open("typing") }
            Divider()
            Link("Sound & Haptics") { open("feel") }
            Divider()
            Link("Writing Style") { open("style") }
        }
    }
}

@Composable
private fun Step(title: String, detail: String, done: Boolean, onClick: () -> Unit) {
    val palette = palette()
    Line(title, detail, onClick = if (done) null else onClick) {
        if (done) {
            Icon(glyph("M6 12.5l4 4L18 8"), null, tint = Color(0xFF30D158))
        } else {
            Icon(glyph("M9 4.5l7.5 7.5L9 19.5"), null, tint = palette.secondary, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
fun SettingsList(open: (String) -> Unit) {
    Page("Settings") {
        Section("Keyboard") {
            Link("Appearance", value = LocalStore.current.themeTitle()) { open("appearance") }
            Divider()
            Link("Typing") { open("typing") }
            Divider()
            Link("Sound & Haptics") { open("feel") }
        }
        Section("Voice Typing") {
            Link("Writing Style") { open("style") }
        }
        Section("iikb") {
            Link("Privacy & Data") { open("privacy") }
            Divider()
            Link("About iikb") { open("about") }
        }
    }
}

@Composable
fun SettingsPage(page: String, back: () -> Unit) {
    when (page) {
        "appearance" -> Page("Appearance", back) { Appearance() }
        "typing" -> Page("Typing", back) { Typing() }
        "feel" -> Page("Sound & Haptics", back) { Feel() }
        "style" -> Page("Writing Style", back) { Style() }
        "privacy" -> Page("Privacy & Data", back) { Privacy() }
        else -> Page("About iikb", back) { About() }
    }
}

@Composable
private fun Appearance() {
    val store = LocalStore.current
    Section("Theme") {
        Choices(
            "theme", THEMES,
            mapOf(
                "standard" to "iikb’s own keys, flat.",
                "clear" to "Only the letters, no keys around them.",
                "physical" to "Solid keys, dark or light.",
                "mechanical" to "Raised keycaps you can almost press.",
                "classic" to "The glossy keyboard of 2011.",
            ),
        )
    }
    if (store.string("theme") in setOf("physical", "mechanical")) {
        Section("Keys") {
            Choices("themeAppearance", listOf("automatic" to "Automatic", "dark" to "Dark", "light" to "Light"))
        }
    }
    Section("Character Preview") {
        Choices("characterPreviewStyle", listOf("none" to "None", "detached" to "Detached", "attached" to "Attached"))
    }
    Section("Size and Shape") {
        Stops("Key Spacing", "keySpacing", SPACING, "Bigger Keys", "More Space")
        Divider()
        Stops("Key Roundness", "keyRoundness", ROUNDNESS, "Sharper", "Rounder")
    }
    Section("Keys") {
        Toggle("Number Row", "numberRow")
        Divider()
        Toggle("Emoji Key", "emojiKey")
    }
    Section("One-Handed Keyboard") {
        Choices("oneHanded", listOf("off" to "Off", "left" to "Left", "right" to "Right"))
    }
    Section("Skin Tone") {
        Choices(
            "skinTone",
            listOf(
                "" to "👋 None", "light" to "👋🏻 Light", "mediumLight" to "👋🏼 Medium Light", "medium" to "👋🏽 Medium",
                "mediumDark" to "👋🏾 Medium Dark", "dark" to "👋🏿 Dark",
            ),
        )
    }
    Section("Keyboard Menu", "Where the menu of layouts and iikb Settings opens.") {
        Choices("keyboardMenu", listOf("both" to "Both", "hold" to "Hold 123", "button" to "Menu Button"))
    }
}

@Composable
private fun Typing() {
    Section {
        Toggle("Auto-Capitalization", "autoCapitalization")
        Divider()
        Toggle("Auto-Correction", "autoCorrection")
        Divider()
        Toggle("Predictive Text", "predictiveText")
        Divider()
        Toggle("Slide to Type", "slideToType")
    }
    Section {
        Toggle("Smart Punctuation", "smartPunctuation")
        Divider()
        Toggle("Enable Caps Lock", "capsLock")
        Divider()
        Toggle("\".\" Shortcut", "periodShortcut", "Double-tap the space bar for a period")
    }
}

@Composable
private fun Feel() {
    val store = LocalStore.current
    Section {
        Toggle("Key Haptics", "haptics.on")
        if (store.bool("haptics.on")) {
            Divider()
            Stops("Strength", "haptics.strength", HAPTICS, "Lightest", "Strongest")
        }
    }
    Section {
        Toggle("Sound", "sound")
    }
}

@Composable
private fun Style() {
    Section("Style") {
        Choices(
            "writingStyle",
            listOf("formal" to "Formal.", "casual" to "Casual", "veryCasual" to "very casual", "excited" to "Excited!"),
            mapOf(
                "formal" to "Every comma, every period",
                "casual" to "No period at the end",
                "veryCasual" to "Casual, in lowercase",
                "excited" to "Formal, ending with !",
            ),
        )
    }
    Section("Editing") {
        Choices(
            "dictationEditing", listOf("asSaid" to "As Said", "light" to "Light", "clean" to "Clean"),
            mapOf(
                "asSaid" to "Every word you say",
                "light" to "Leaves out um and uh",
                "clean" to "Also what you take back and repeat",
            ),
        )
    }
    Section("Lists") {
        Choices("spokenLists", listOf("numbered" to "Numbered", "bulleted" to "Bulleted", "off" to "Off"))
    }
    Section("Text Mode") {
        Choices(
            "textMode",
            listOf("spelledOut" to "Spelled Out", "abbreviated" to "Abbreviated", "texting" to "Texting", "genZ" to "Gen Z"),
        )
    }
}

@Composable
private fun Privacy() {
    val store = LocalStore.current
    var reset by remember { mutableStateOf(false) }
    Section(footer = "Everything iikb learns stays on this phone. Voice typing uses Android's speech recognizer, on the phone where it can.") {
        Line(
            if (reset) "Learned words and taps reset" else "Reset Learned Words and Taps",
            onClick = {
                store.resetMemory()
                reset = true
            },
        )
    }
}

@Composable
private fun About() {
    val palette = palette()
    Section {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("iikb", color = palette.label, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Text(
                "The keyboard iikb builds for iPhone, on Android: the same typing engine, autocorrect, predictions, " +
                    "swipe and emoji search. Open source under MIT.",
                color = palette.secondary, fontSize = 15.sp,
            )
            Text("github.com/AVGVSTVS96/iikb", color = palette.accent, fontSize = 15.sp)
        }
    }
}

val THEMES = listOf(
    "standard" to "Default", "clear" to "Clear", "physical" to "Physical", "mechanical" to "Mechanical",
    "classic" to "iOS 5",
)
val SPACING = listOf("tighter", "tight", "standard", "roomy", "roomier")
val ROUNDNESS = listOf("sharper", "sharp", "standard", "round", "rounder")
val HAPTICS = listOf("lightest", "lighter", "light", "standard", "strong", "stronger", "strongest")

val LocalStore = staticCompositionLocalOf<Store> { error("no store") }

/** The settings as Compose reads them: each change redraws the pages that show it. */
class Store(private val settings: Settings) {
    private var revision by mutableIntStateOf(0)

    fun bool(name: String): Boolean {
        revision
        return when (name) {
            "haptics.on" -> settings.string("hapticFeedback") != "off"
            else -> settings.bool(name)
        }
    }

    fun string(name: String): String {
        revision
        return when (name) {
            "haptics.strength" -> settings.preferences.getString("hapticStrength", null) ?: "standard"
            else -> settings.string(name)
        }
    }

    fun set(name: String, value: Boolean) {
        when (name) {
            "haptics.on" -> settings.set("hapticFeedback", if (value) string("haptics.strength") else "off")
            else -> settings.set(name, value)
        }
        revision++
    }

    /** Haptic Feedback keeps its strength while it's off, as iOS's Strength slider does. */
    fun set(name: String, value: String) {
        when (name) {
            "haptics.strength" -> {
                settings.set("hapticStrength", value)
                settings.set("hapticFeedback", value)
            }
            else -> settings.set(name, value)
        }
        revision++
    }

    fun themeTitle() = THEMES.firstOrNull { it.first == string("theme") }?.second ?: "Default"

    /** The keyboard reads the token and starts over from nothing. */
    fun resetMemory() {
        settings.set("memoryResets", (settings.preferences.getString("memoryResets", "0")!!.toInt() + 1).toString())
    }
}
