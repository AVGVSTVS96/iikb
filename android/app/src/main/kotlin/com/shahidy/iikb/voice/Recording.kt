package com.shahidy.iikb.voice

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

/** A finished dictation's sound: 16 kHz mono samples in -1...1, kept as a 16-bit WAV beside its transcript. */
class Recording(val samples: FloatArray) {
    val seconds get() = samples.size / RATE.toDouble()

    /**
     * A second or more with no sample past 100 of 32767: the microphone gave no sound, as iOS's `Listener` tells it (each
     * of his 628 real dictations had one past 200).
     */
    val deaf get() = seconds >= 1 && samples.none { abs(it) > SILENCE }

    /** The samples as 16-bit little-endian PCM, as the WAV holds them. */
    fun pcm16(): ByteArray {
        val bytes = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (sample in samples) bytes.putShort((sample.coerceIn(-1f, 1f) * Short.MAX_VALUE).toInt().toShort())
        return bytes.array()
    }

    /** Written beside, then moved over, so a recording is either whole or not there. */
    fun write(file: File) {
        val bytes = ByteBuffer.allocate(44 + samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        bytes.put("RIFF".toByteArray()).putInt(36 + samples.size * 2).put("WAVEfmt ".toByteArray())
        bytes.putInt(16).putShort(1).putShort(1).putInt(RATE).putInt(RATE * 2).putShort(2).putShort(16)
        bytes.put("data".toByteArray()).putInt(samples.size * 2)
        bytes.put(pcm16())
        val next = File(file.parentFile, file.name + ".next")
        next.writeBytes(bytes.array())
        next.renameTo(file)
    }

    companion object {
        const val RATE = 16_000
        private const val SILENCE = 100f / 32767

        /** A WAV this class wrote; null when it can't be read as one. */
        fun read(file: File): Recording? {
            val bytes = runCatching { file.readBytes() }.getOrNull() ?: return null
            if (bytes.size < 44 || String(bytes, 0, 4) != "RIFF") return null
            val data = ByteBuffer.wrap(bytes, 44, bytes.size - 44).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
            return Recording(FloatArray(data.remaining()) { data.get(it) / Short.MAX_VALUE.toFloat() })
        }
    }
}
