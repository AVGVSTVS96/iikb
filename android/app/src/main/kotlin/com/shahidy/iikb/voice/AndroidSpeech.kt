package com.shahidy.iikb.voice

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlin.concurrent.thread
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

    private fun create(): SpeechRecognizer = recognizer(context)

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

    companion object {
        private fun recognizer(context: Context): SpeechRecognizer =
            if (Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            } else {
                SpeechRecognizer.createSpeechRecognizer(context)
            }

        /**
         * A kept recording written down, as Transcribe Again asks: Android 13's audio source, the recording's samples
         * piped in rather than the microphone's, in one session that ends where the recording does. [done] gets what it
         * heard, empty for no one, on the main thread, where it's called.
         */
        fun write(context: Context, recording: Recording, done: (Result<String>) -> Unit) {
            if (Build.VERSION.SDK_INT < 33) {
                return done(Result.failure(IllegalStateException("Android’s recognizer writes a kept recording from Android 13")))
            }
            val (source, sink) = ParcelFileDescriptor.createPipe()
            thread(name = "iikb-speech-source") {
                ParcelFileDescriptor.AutoCloseOutputStream(sink).use { it.write(recording.pcm16()) }
            }
            val recognizer = recognizer(context)
            val heard = mutableListOf<String>()
            var finished = false
            val finish = { result: Result<String> ->
                if (!finished) {
                    finished = true
                    recognizer.destroy()
                    source.close()
                    done(result)
                }
            }
            recognizer.setRecognitionListener(object : RecognitionListener {
                private fun first(results: Bundle) =
                    results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim().orEmpty()

                override fun onSegmentResults(segmentResults: Bundle) {
                    first(segmentResults).takeIf { it.isNotEmpty() }?.let(heard::add)
                }

                override fun onEndOfSegmentedSession() = finish(Result.success(heard.joinToString(" ")))

                override fun onResults(results: Bundle) {
                    first(results).takeIf { it.isNotEmpty() }?.let(heard::add)
                    finish(Result.success(heard.joinToString(" ")))
                }

                override fun onError(error: Int) = finish(
                    if (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                        Result.success(heard.joinToString(" "))
                    } else {
                        Result.failure(IllegalStateException("Android’s recognizer couldn’t write it (error $error)"))
                    },
                )

                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            recognizer.startListening(
                Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                    .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, source)
                    .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                    .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                    .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, Recording.RATE)
                    .putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE),
            )
        }
    }
}
