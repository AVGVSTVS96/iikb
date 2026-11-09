package com.shahidy.iikb.app

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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
