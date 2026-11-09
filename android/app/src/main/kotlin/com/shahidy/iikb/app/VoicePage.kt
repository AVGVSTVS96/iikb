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

/** Settings › Voice: the voice model, each with what it costs, and for the picked one its download, as iOS's page. */
@Composable
fun Voice() {
    val context = LocalContext.current
    val model = remember { VoiceModel.of(context) }
    val picked = model.pickedShown
    val state = model.state
    LaunchedEffect(picked) { if (picked == VoiceModel.Model.V3) model.prepare() }
    Section("Voice Model", "The sound never leaves your phone with Parakeet.") {
        VoiceModel.Model.entries.forEachIndexed { index, choice ->
            if (index > 0) Divider()
            val detail = if (choice == VoiceModel.Model.V3 && picked == choice) status(state, model) else choice.detail
            Line(choice.title, detail, onClick = { model.picked = choice }) { Radio(picked == choice) }
            if (choice == VoiceModel.Model.V3 && picked == choice && state is VoiceModel.State.Downloading) {
                Progress(state.fraction)
            }
        }
        if (picked == VoiceModel.Model.V3 && state is VoiceModel.State.Failed) {
            Divider()
            Link("Try Again") { model.prepare() }
        }
    }
}

private fun status(state: VoiceModel.State, model: VoiceModel) = when (state) {
    VoiceModel.State.Missing -> VoiceModel.Model.V3.detail
    is VoiceModel.State.Downloading ->
        "Downloading, ${(state.fraction * model.files.total / 1_000_000).toInt()} of ${model.files.total / 1_000_000} MB"
    VoiceModel.State.Loading -> "Getting ready"
    VoiceModel.State.Ready -> "Fast and accurate, on your phone."
    is VoiceModel.State.Failed -> "Couldn't download: ${state.reason}"
}

@Composable
private fun Progress(fraction: Double) {
    val palette = palette()
    Box(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 12.dp).height(4.dp).clip(CircleShape).background(palette.edge)) {
        Box(Modifier.fillMaxWidth(fraction.toFloat().coerceIn(0f, 1f)).height(4.dp).clip(CircleShape).background(palette.accent))
    }
}
