package com.shahidy.iikb.voice

import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig
import com.k2fsa.sherpa.onnx.SileroVadModelConfig
import com.k2fsa.sherpa.onnx.Vad
import com.k2fsa.sherpa.onnx.VadModelConfig

/**
 * NVIDIA's Parakeet v3 (parakeet-tdt-0.6b-v3), int8, run on the phone's CPU by sherpa-onnx, with Silero's
 * voice-activity model beside it. Where no one talks Parakeet writes "Yeah." or "Thank you.", as on iOS; sherpa-onnx
 * gives no confidence for a word, so a recording in which Silero hears no one at all is written as nothing.
 */
class Parakeet private constructor(private val recognizer: OfflineRecognizer, private val talking: Vad) {
    fun write(recording: Recording): String {
        if (recording.samples.isEmpty() || !talks(recording.samples)) return ""
        val stream = recognizer.createStream()
        try {
            stream.acceptWaveform(recording.samples, Recording.RATE)
            recognizer.decode(stream)
            return recognizer.getResult(stream).text.trim()
        } finally {
            stream.release()
        }
    }

    /** Whether any of Silero's 32 ms windows hears talking at even odds. */
    private fun talks(samples: FloatArray): Boolean {
        talking.reset()
        var start = 0
        while (start + WINDOW <= samples.size) {
            if (talking.compute(samples.copyOfRange(start, start + WINDOW)) >= 0.5f) return true
            start += WINDOW
        }
        return false
    }

    fun release() {
        recognizer.release()
        talking.release()
    }

    companion object {
        private const val WINDOW = 512

        fun load(files: ModelFiles): Parakeet {
            val config = OfflineRecognizerConfig(
                modelConfig = OfflineModelConfig(
                    transducer = OfflineTransducerModelConfig(
                        encoder = files.file("encoder.int8.onnx").path,
                        decoder = files.file("decoder.int8.onnx").path,
                        joiner = files.file("joiner.int8.onnx").path,
                    ),
                    tokens = files.file("tokens.txt").path,
                    modelType = "nemo_transducer",
                    numThreads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4),
                ),
            )
            val vad = VadModelConfig(
                sileroVadModelConfig = SileroVadModelConfig(model = files.file("silero_vad.onnx").path, windowSize = WINDOW),
            )
            return Parakeet(OfflineRecognizer(null, config), Vad(null, vad))
        }

        private const val REVISION = "ed5d745623472f97cfc2e6c2916ee248798fc5a8"
        private const val HUB = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/$REVISION"

        /** The sherpa-onnx export of v3 on Hugging Face, at the revision iikb was tested with, and Silero v5. */
        val REMOTE = listOf(
            ModelFiles.Remote(
                "encoder.int8.onnx", "$HUB/encoder.int8.onnx", 652_282_294,
                "1afbe69c1ffdabee94755f42e4daf1d93549131a3da11356bda84fcef0f2c479",
            ),
            ModelFiles.Remote(
                "decoder.int8.onnx", "$HUB/decoder.int8.onnx", 11_845_274,
                "0222a86147299d4dee90edf95b6d13827edb42ad8b7c9cf0b2582f030937c0b5",
            ),
            ModelFiles.Remote(
                "joiner.int8.onnx", "$HUB/joiner.int8.onnx", 6_355_277,
                "cbd02f3696e9944970111fb439d9c3fd365a80374565f13f2b9c7007d253fc98",
            ),
            ModelFiles.Remote(
                "tokens.txt", "$HUB/tokens.txt", 93_939,
                "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d",
            ),
            ModelFiles.Remote(
                "silero_vad.onnx", "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx",
                643_854, "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6",
            ),
        )
    }
}
