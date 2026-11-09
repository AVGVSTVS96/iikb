package com.shahidy.iikb.keyboard

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * Voice typing in place: Android lets a keyboard use the microphone, so the mic records right where you type, with
 * no trip to the app. What's heard is typed through the engine as a dictation, in Settings › Writing Style.
 */
class Voice(private val context: Context, private val heard: (String) -> Unit) {
    var onChange: (Boolean) -> Unit = {}
    private var recognizer: SpeechRecognizer? = null
    var listening = false
        private set(value) {
            field = value
            onChange(value)
        }

    val permitted get() =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun toggle() = if (listening) stop() else start()

    private fun start() {
        val recognizer = recognizer ?: create().also { recognizer = it }
        recognizer.setRecognitionListener(listener)
        recognizer.startListening(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L),
        )
        listening = true
    }

    fun stop() {
        if (!listening) return
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
        override fun onResults(results: Bundle) {
            listening = false
            results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                ?.takeIf { it.isNotBlank() }?.let(heard)
        }

        override fun onError(error: Int) {
            listening = false
        }

        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onPartialResults(partialResults: Bundle?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }
}
