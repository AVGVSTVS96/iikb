package com.shahidy.iikb.voice

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.shahidy.iikb.Transcript
import com.shahidy.iikb.Transcripts
import com.shahidy.iikb.Vocabulary
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Voice typing in the keyboard, as iOS's `Listener` joins its microphone and model: the [Microphone] records, and once
 * you stop, Parakeet writes the finished recording down, in the order said, while the next one records. Recording never
 * waits for the model: a dictation made while Parakeet downloads or loads is saved and written once it's ready. With
 * Android's recognizer picked, it listens and writes at once instead. Each is kept in [Transcripts] and handed to
 * [typist], who types it where it was said if that field is still the one being typed in.
 */
class Dictation(context: Context, private val typist: Typist) {
    interface Typist {
        /** What iikb types for what the model heard, in the Writing Style picked for [app]. */
        fun style(heard: String, app: String?): String

        /**
         * Types [text] if the field it was said in, [field], is still the keyboard's; false if not. [plain] is what the
         * model wrote with only your Dictionary on it, which a field of addresses or digits reads instead.
         */
        fun type(text: String, plain: String, field: Int): Boolean

        /** Says something about a dictation in the keyboard's bar, if it's up. */
        fun tell(notice: String)
    }

    enum class Phase { OFF, LISTENING, WRITING }

    /** One dictation: where it was said, and its sound once recorded (none for Android's recognizer). */
    private class Take(
        val id: String, val date: Long, val field: Int, val app: String?, val speech: Boolean = false,
        val recovered: Boolean = false,
    ) {
        var recording: Recording? = null
        var canceled = false
    }

    private val main = Handler(Looper.getMainLooper())
    private val model = VoiceModel.of(context)
    private val writer = Executors.newSingleThreadExecutor { Thread(it, "iikb-dictation") }
    private val microphone = Microphone(context, ::heard) { stop() }
    private val speech = AndroidSpeech(context, { heard(it, (System.currentTimeMillis() - started) / 1000.0) }, ::spoken)

    var onChange: () -> Unit = {}
    var onLevel: (Float) -> Unit = {}

    private var listening: Take? = null
    private var started = 0L

    /** Recorded and waiting for Parakeet, oldest first; the first may be being written. */
    private val queue = ArrayDeque<Take>()
    private var writing = false

    /** Android's recognizer, stopped and still writing. */
    private var speaking: Take? = null
    private var closed = false

    /** How long the dictation being said has run, in seconds. */
    var recorded = 0.0
        private set

    val phase
        get() = when {
            listening != null -> Phase.LISTENING
            queue.isNotEmpty() || speaking != null -> Phase.WRITING
            else -> Phase.OFF
        }

    /** The lengths of the dictations waiting for Parakeet, the next first. */
    val saved get() = queue.mapNotNull { it.recording?.seconds }

    /** What they wait for, while Parakeet downloads or loads; null once it's writing. */
    val waitingFor: String?
        get() = if (queue.isEmpty()) {
            null
        } else {
            when (val state = model.state) {
                is VoiceModel.State.Downloading -> "Downloading ${(state.fraction * 100).toInt()}%"
                VoiceModel.State.Loading -> "Model loading…"
                is VoiceModel.State.Failed -> "Couldn't download. Tap the mic to try again."
                else -> null
            }
        }

    private val modelChanged: () -> Unit = { onChange() }

    init {
        model.listen(modelChanged)
        val left = Transcripts.unwritten()
        writer.execute {
            val takes = left.map { file ->
                Take(file.nameWithoutExtension, file.lastModified(), NO_FIELD, null, recovered = true)
                    .apply { recording = Recording.read(file) ?: Recording(FloatArray(0)) }
            }
            main.post {
                queue.addAll(takes)
                pump()
            }
        }
    }

    /** Starts a dictation said for [field], in [app]; false if the microphone couldn't start. */
    fun start(field: Int, app: String?): Boolean {
        if (listening != null) return true
        val speech = model.picked == VoiceModel.Model.ANDROID
        if (speech) {
            this.speech.start()
        } else {
            if (!microphone.start()) return false
            if (model.parakeetFiles.present) writer.execute { runCatching { model.parakeet() } } else model.prepare()
        }
        recorded = 0.0
        started = System.currentTimeMillis()
        listening = Take(UUID.randomUUID().toString(), started, field, app, speech)
        onChange()
        return true
    }

    fun stop() = finish(canceled = false)

    /** Stops without typing it; Transcripts still keeps it. */
    fun cancel() = finish(canceled = true)

    private fun finish(canceled: Boolean) {
        val take = listening ?: return
        listening = null
        take.canceled = canceled
        if (take.speech) {
            speaking = take
            speech.stop()
        } else {
            val recording = microphone.stop()
            take.recording = recording
            if (!canceled && recording.deaf) typist.tell("The microphone gave no sound: tap the mic again")
            val file = Transcripts.recording(take.id)
            writer.execute { recording.write(file) }
            queue.add(take)
            pump()
        }
        onChange()
    }

    private fun heard(level: Float, seconds: Double) {
        if (listening == null) return
        recorded = seconds
        onLevel(level)
    }

    /** Android's recognizer finished, once you stopped or once it heard you stop talking. */
    private fun spoken(heard: String?) {
        val take = speaking ?: listening?.takeIf { it.speech } ?: return
        if (take === listening) listening = null
        speaking = null
        val seconds = (System.currentTimeMillis() - take.date) / 1000.0
        if (closed) return onChange()
        if (!heard.isNullOrEmpty()) {
            deliver(take, heard, seconds, VoiceModel.Model.ANDROID.title)
        } else if (!take.canceled) {
            typist.tell("${VoiceModel.Model.ANDROID.title} heard nothing")
        }
        onChange()
    }

    /** Writes the oldest waiting dictation once Parakeet is here, then the next; lets go of it once none is left. */
    private fun pump() {
        if (writing || closed) return
        val take = queue.firstOrNull() ?: return
        if (!model.parakeetFiles.present) {
            model.prepare { pump() }
            return onChange()
        }
        writing = true
        writer.execute {
            val heard = runCatching { model.write(take.recording!!) }
            main.post {
                if (closed) return@post
                writing = false
                queue.removeFirst()
                heard.onSuccess { (text, title) -> deliver(take, text, take.recording!!.seconds, title) }
                if (queue.isEmpty() && listening == null) writer.execute(model::letGo)
                onChange()
                pump()
            }
        }
    }

    /**
     * Keeps a dictation in Transcripts, typed as your Writing Style and then your Dictionary have it (iOS's
     * `DictationWriting.typed`) unless you canceled it. One the model heard nothing in is kept too, with its sound,
     * and the bar says where it is, as on iOS.
     */
    private fun deliver(take: Take, heard: String, seconds: Double, model: String) {
        val text = if (heard.isEmpty()) "" else Vocabulary.corrected(typist.style(heard, take.app))
        val meant = !take.canceled && take.field != NO_FIELD
        if (meant && text.isEmpty() && take.recording?.deaf != true) {
            typist.tell("$model heard nothing: it’s in Transcripts")
        }
        val typed = meant && (text.isEmpty() || typist.type(text, Vocabulary.corrected(heard), take.field))
        Transcripts.add(
            Transcript(
                id = take.id, date = take.date / 1000.0, text = text, seconds = seconds, typed = typed,
                recovered = take.recovered.takeIf { it }, model = model, heard = heard.takeIf { it != text },
                app = take.app,
            ),
        )
    }

    /**
     * The keyboard went away: what's being said is stopped and saved, and whatever wasn't written yet stays a
     * recording on its own, written when the keyboard starts again.
     */
    fun close() {
        stop()
        closed = true
        model.unlisten(modelChanged)
        speech.close()
        writer.execute(model::letGo)
        writer.shutdown()
    }

    companion object {
        /** No field: a recording left by a keyboard that ended, written but never typed. */
        const val NO_FIELD = -1
    }
}
