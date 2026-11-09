package com.shahidy.iikb.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.shahidy.iikb.voice.VoiceModel

/**
 * Settings › Voice, as iOS's page: the voice model, each with what it costs, and for the picked Parakeet its download.
 * iOS's Keep Mic On isn't here: it keeps iikb's app recording in the background
 * because an iPhone keyboard can't start a recording, and Android's keyboard records by itself, from the first tap.
 */
@Composable
fun Voice() {
    ModelSettings()
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
        "What you say is written down on this phone with a Parakeet and never leaves it. What you dictate while one gets " +
            "ready is written once it’s ready, in the order you said it.",
    ) {
        VoiceModel.Model.entries.forEachIndexed { index, choice ->
            if (index > 0) Divider()
            val parakeet = choice != VoiceModel.Model.ANDROID && picked == choice
            Line(choice.title, if (parakeet) status(state, choice, model) else choice.detail, onClick = { model.picked = choice }) {
                Radio(picked == choice)
            }
            if (parakeet && state is VoiceModel.State.Downloading) Progress(state.fraction)
        }
        if (picked != VoiceModel.Model.ANDROID && state is VoiceModel.State.Failed) {
            Divider()
            Link("Try Again") { model.prepare() }
        }
    }
}

private fun status(state: VoiceModel.State, choice: VoiceModel.Model, model: VoiceModel) = when (state) {
    VoiceModel.State.Missing -> choice.detail
    is VoiceModel.State.Downloading ->
        "Downloading, ${(state.fraction * model.parakeetFiles.total / 1_000_000).toInt()} of ${model.parakeetFiles.total / 1_000_000} MB"
    VoiceModel.State.Loading -> "Getting ready"
    VoiceModel.State.Ready -> choice.detail.substringBefore(" Downloads once")
    is VoiceModel.State.Failed -> "Couldn’t download: ${state.reason}"
}

@Composable
private fun Progress(fraction: Double) {
    val palette = palette()
    Box(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 12.dp).height(4.dp).clip(CircleShape).background(palette.edge)) {
        Box(Modifier.fillMaxWidth(fraction.toFloat().coerceIn(0f, 1f)).height(4.dp).clip(CircleShape).background(palette.accent))
    }
}
