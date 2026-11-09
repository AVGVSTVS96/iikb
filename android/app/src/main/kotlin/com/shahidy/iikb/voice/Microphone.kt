package com.shahidy.iikb.voice

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import kotlin.math.sqrt

/**
 * The phone's microphone, recording one dictation at a time on a thread of its own. It knows nothing of the models:
 * each 50 ms it hears goes to [heard] as its level (the root mean square, as iOS's `Microphone` publishes it), and a
 * stop hands back the whole [Recording]. When the microphone fails mid-dictation, [lost] says so, and the stop that
 * follows keeps what was heard until then. It records with Android's source for speech recognition, which leaves out
 * the noise suppression and gain a call's source adds, from the microphone [Microphones] picks; a device coming or
 * going moves it onto the right one, in the same recording.
 */
class Microphone(
    context: Context,
    private val heard: (level: Float, seconds: Double) -> Unit,
    private val lost: () -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(AudioManager::class.java)
    private val microphones = Microphones.of(context)
    private var thread: Thread? = null
    @Volatile private var running = false
    private var finished: Recording? = null
    private var record: AudioRecord? = null
    /** A picked Bluetooth microphone hears only while Android has its device on a call. */
    private var onCall = false

    private val devices = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = route()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = route()
    }

    val recording get() = running

    /** The microphone the dictation being recorded started on, as Settings › Voice names it. */
    var input: String? = null
        private set

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
        this.record = record
        route()
        record.startRecording()
        if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            record.release()
            this.record = null
            hangUp()
            return false
        }
        input = (record.routedDevice ?: microphones.input())?.let(microphones::choice)?.name
        audio.registerAudioDeviceCallback(devices, main)
        running = true
        thread = Thread({ capture(record, chunk) }, "iikb-microphone").also(Thread::start)
        return true
    }

    /** Stops and hands back what was recorded. */
    fun stop(): Recording {
        running = false
        thread?.join()
        thread = null
        if (record != null) {
            audio.unregisterAudioDeviceCallback(devices)
            record = null
            hangUp()
        }
        return finished ?: Recording(FloatArray(0))
    }

    /** Hears from the input [Microphones] picks now, putting a Bluetooth one's device on a call, or taking it off. */
    private fun route() {
        val record = record ?: return
        val input = microphones.input()
        record.preferredDevice = input
        val call = input?.let(microphones::callDevice)
        when {
            call != null && Build.VERSION.SDK_INT >= 31 -> onCall = audio.setCommunicationDevice(call)
            input?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO && Build.VERSION.SDK_INT < 31 -> {
                @Suppress("DEPRECATION")
                audio.startBluetoothSco()
                onCall = true
            }
            else -> hangUp()
        }
    }

    private fun hangUp() {
        if (!onCall) return
        onCall = false
        if (Build.VERSION.SDK_INT >= 31) {
            audio.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            audio.stopBluetoothSco()
        }
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
