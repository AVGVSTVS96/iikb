package com.shahidy.iikb.voice

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlin.math.pow

/**
 * Android's own speech recognizer, on the phone where it can be, the other choice in Settings › Voice as Apple's is
 * on iOS. It listens itself, so it hears while you talk rather than writing a finished recording: [level] gets its
 * loudness as the microphone's root mean square, and [written] what it heard once you stop, or null.
 */
class AndroidSpeech(
    private val context: Context,
    private val level: (Float) -> Unit,
    private val written: (String?) -> Unit,
) {
    private var recognizer: SpeechRecognizer? = null

    fun start() {
        val recognizer = recognizer ?: create().also { recognizer = it }
        recognizer.setRecognitionListener(listener)
        recognizer.startListening(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L),
        )
    }

    fun stop() {
        recognizer?.stopListening()
    }

    fun close() {
        recognizer?.destroy()
        recognizer = null
    }

    private fun create(): SpeechRecognizer =
        if (Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } else {
            SpeechRecognizer.createSpeechRecognizer(context)
        }

    private val listener = object : RecognitionListener {
        override fun onResults(results: Bundle) =
            written(results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim())

        override fun onError(error: Int) = written(null)

        /** Android's level runs from about -2 to 10 dB over its own floor; as iikb's, -50 dBFS to -10. */
        override fun onRmsChanged(rmsdB: Float) = level(10f.pow((rmsdB.coerceIn(-2f, 10f) * 40 / 12 - 50) / 20))

        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onPartialResults(partialResults: Bundle?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }
}
