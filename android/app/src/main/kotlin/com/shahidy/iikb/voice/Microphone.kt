package com.shahidy.iikb.voice

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import kotlin.math.sqrt

/**
 * The phone's microphone, recording one dictation at a time on a thread of its own. It knows nothing of the models:
 * each 50 ms it hears goes to [heard] as its level (the root mean square, as iOS's `Microphone` publishes it), and a
 * stop hands back the whole [Recording]. When the microphone fails mid-dictation, [lost] says so, and the stop that
 * follows keeps what was heard until then. It records with Android's source for speech recognition, which leaves out
 * the noise suppression and gain a call's source adds.
 */
class Microphone(
    private val heard: (level: Float, seconds: Double) -> Unit,
    private val lost: () -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private var thread: Thread? = null
    @Volatile private var running = false
    private var finished: Recording? = null

    val recording get() = running

    /** Starts recording; false when Android won't give iikb the microphone (another app holds it, or no permission). */
    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        if (running) return true
        val chunk = Recording.RATE / 20
        val size = maxOf(
            AudioRecord.getMinBufferSize(Recording.RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT),
            chunk * 2 * 4,
        )
        val record = runCatching {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, Recording.RATE, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, size,
            )
        }.getOrNull()?.takeIf { it.state == AudioRecord.STATE_INITIALIZED } ?: return false
        record.startRecording()
        if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            record.release()
            return false
        }
        running = true
        thread = Thread({ capture(record, chunk) }, "iikb-microphone").also(Thread::start)
        return true
    }

    /** Stops and hands back what was recorded. */
    fun stop(): Recording {
        running = false
        thread?.join()
        thread = null
        return finished ?: Recording(FloatArray(0))
    }

    private fun capture(record: AudioRecord, chunk: Int) {
        val buffer = ShortArray(chunk)
        val samples = ArrayList<FloatArray>()
        var count = 0
        while (running) {
            val read = record.read(buffer, 0, chunk)
            if (read <= 0) {
                main.post(lost)
                break
            }
            val floats = FloatArray(read) { buffer[it] / Short.MAX_VALUE.toFloat() }
            samples.add(floats)
            count += read
            val level = sqrt(floats.fold(0.0) { sum, sample -> sum + sample * sample } / read).toFloat()
            val seconds = count / Recording.RATE.toDouble()
            main.post { heard(level, seconds) }
        }
        record.stop()
        record.release()
        val all = FloatArray(count)
        var at = 0
        for (piece in samples) {
            piece.copyInto(all, at)
            at += piece.size
        }
        finished = Recording(all)
    }
}
