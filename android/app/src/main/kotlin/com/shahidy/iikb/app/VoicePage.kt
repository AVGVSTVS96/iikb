package com.shahidy.iikb.app

import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import com.shahidy.iikb.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import kotlin.math.roundToInt
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.shahidy.iikb.voice.Microphones
import com.shahidy.iikb.voice.VoiceModel

/**
 * Settings › Voice, as iOS's page: the voice model, each with what it costs, and for the picked Parakeet its download,
 * then which microphone hears you. iOS's Keep Mic On isn't here: it keeps iikb's app recording in the background
 * because an iPhone keyboard can't start a recording, and Android's keyboard records by itself, from the first tap.
 */
@Composable
fun Voice() {
    ModelSettings()
    MicrophoneSettings()
}

@Composable
private fun ModelSettings() {
    val context = LocalContext.current
    val model = remember { VoiceModel.of(context) }
    val picked = model.pickedShown
    val state = model.state
    LaunchedEffect(picked) { if (picked != VoiceModel.Model.ANDROID) model.prepare() }
    Section(
        "Voice Model",
        "What you say is written down on this phone with a Parakeet and never leaves it. What you dictate while a " +
            "Parakeet gets ready is written once it’s ready, in the order you said it.",
    ) {
        VoiceModel.Model.entries.forEachIndexed { index, choice ->
            if (index > 0) Divider()
            val preparing = choice != VoiceModel.Model.ANDROID && picked == choice && state != VoiceModel.State.Ready
            Row(
                Modifier.clickable { model.picked = choice }.row(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    RowText(choice.title, choice.detail)
                    if (preparing) Preparing(state) { model.prepare() }
                }
                Radio(picked == choice)
            }
        }
    }
}

/** How far the picked Parakeet is from ready, under its detail, as iOS's: its download, a spinner, or what failed. */
@Composable
private fun Preparing(state: VoiceModel.State, retry: () -> Unit) {
    val palette = palette()
    val footnote = TextStyle(color = palette.secondary, fontSize = Type.footnote)
    Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        when (state) {
            is VoiceModel.State.Downloading -> {
                Text("Downloading, ${(state.fraction * 100).roundToInt()}%", style = footnote)
                Progress(state.fraction)
            }
            VoiceModel.State.Loading -> Row(
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                CircularProgressIndicator(Modifier.size(12.dp), color = palette.secondary, strokeWidth = 1.5.dp)
                Text("Getting ready", style = footnote)
            }
            is VoiceModel.State.Failed -> {
                Text("Couldn’t get it ready: ${state.reason}", style = footnote.copy(color = palette.red))
                Text(
                    "Try Again", style = footnote.copy(color = palette.accent, fontWeight = FontWeight.SemiBold),
                    modifier = Modifier.clickable(onClick = retry),
                )
            }
            else -> {}
        }
    }
}

/** Which microphone iikb dictates with when there are several, as iOS's `MicrophoneSettings`. */
@Composable
private fun MicrophoneSettings() {
    val context = LocalContext.current
    val microphones = remember { Microphones.of(context) }
    var connected by remember { mutableStateOf(microphones.connected()) }
    DisposableEffect(Unit) {
        val audio = context.getSystemService(AudioManager::class.java)
        val changed = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) {
                connected = microphones.connected()
            }

            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) {
                connected = microphones.connected()
            }
        }
        audio.registerAudioDeviceCallback(changed, Handler(Looper.getMainLooper()))
        onDispose { audio.unregisterAudioDeviceCallback(changed) }
    }
    val picked = microphones.picked
    val shown = (connected + listOfNotNull(picked)).distinct()
    Section(
        "Microphone",
        "Automatic uses this phone’s microphone or a wired headset, never Bluetooth, so music on earbuds keeps its full " +
            "quality. A pick is used whenever it’s connected; a Bluetooth one puts its device on a call while you dictate.",
    ) {
        ChoiceRow("Automatic", picked = picked == null) { microphones.pick(null) }
        for (choice in shown) {
            Divider()
            ChoiceRow(choice.title, detail(choice, choice !in connected), picked = picked == choice) { microphones.pick(choice) }
        }
    }
}

private fun detail(choice: Microphones.Choice, away: Boolean) = when {
    away -> "Not connected. Used when it is."
    choice.kind == Microphones.Kind.PHONE -> "The phone’s own, tuned by Android for speech."
    choice.kind == Microphones.Kind.BLUETOOTH -> "Call quality while you dictate."
    else -> null
}

@Composable
private fun Progress(fraction: Double) {
    val palette = palette()
    Box(Modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(palette.edge)) {
        Box(Modifier.fillMaxWidth(fraction.toFloat().coerceIn(0f, 1f)).height(4.dp).clip(CircleShape).background(palette.accent))
    }
}
