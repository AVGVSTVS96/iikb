package com.shahidy.iikb.voice

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File

/**
 * The speech model voice typing writes with, picked in Settings › Voice: Parakeet v3 (the default), downloaded once
 * on first use, or Android's own recognizer. One per process, so the app's Voice page and the keyboard see the same
 * download. Android's never stands in for Parakeet: a dictation made while Parakeet downloads or loads waits for it.
 */
class VoiceModel private constructor(context: Context) {
    enum class Model(val id: String, val title: String, val detail: String) {
        V3("v3", "Parakeet v3", "Fast and accurate, on your phone. Downloads once, about 670 MB."),
        ANDROID("android", "Android", "Built into Android."),
    }

    sealed interface State {
        data object Missing : State
        data class Downloading(val fraction: Double) : State
        data object Loading : State
        data object Ready : State
        data class Failed(val reason: String) : State
    }

    private val preferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    val files = ModelFiles(File(context.noBackupFilesDir, "models/parakeet-tdt-0.6b-v3-int8"), Parakeet.REMOTE)

    var picked: Model
        get() = Model.entries.firstOrNull { it.id == preferences.getString(KEY, null) } ?: Model.V3
        set(value) {
            preferences.edit().putString(KEY, value.id).apply()
            pickedShown = value
            if (value == Model.V3) prepare()
        }

    /** What the app's Voice page draws; Compose reads it. */
    var pickedShown by mutableStateOf(picked)
        private set

    var state by mutableStateOf(if (files.present) State.Ready else State.Missing)
        private set

    private val listeners = mutableListOf<() -> Unit>()

    fun listen(listener: () -> Unit) = listeners.add(listener)

    fun unlisten(listener: () -> Unit) = listeners.remove(listener)

    private fun show(next: State) = main.post {
        state = next
        listeners.toList().forEach { it() }
    }

    private var downloading: Thread? = null
    private val waiting = mutableListOf<() -> Unit>()

    /** Downloads Parakeet if it isn't on the phone yet; [ready] runs on the main thread once its files are. */
    fun prepare(ready: (() -> Unit)? = null) {
        if (files.present) {
            if (state is State.Missing || state is State.Failed) show(State.Ready)
            ready?.let { main.post(it) }
            return
        }
        ready?.let(waiting::add)
        if (downloading != null) return
        show(State.Downloading(0.0))
        downloading = Thread({
            val result = runCatching { files.download { show(State.Downloading(it.toDouble() / files.total)) } }
            main.post {
                downloading = null
                result.onSuccess {
                    show(State.Ready)
                    waiting.toList().also { waiting.clear() }.forEach { it() }
                }.onFailure { show(State.Failed(it.message ?: "The download stopped")) }
            }
        }, "iikb-model-download").apply { start() }
    }

    private var parakeet: Parakeet? = null

    /** Parakeet, loaded once its files are here; called on the dictation's own thread, never the main one. */
    fun parakeet(): Parakeet {
        parakeet?.let { return it }
        show(State.Loading)
        try {
            return Parakeet.load(files).also { parakeet = it }
        } finally {
            show(State.Ready)
        }
    }

    /** Let go once nothing is left to write, since v3 loads again in a moment and holds its 700 MB meanwhile. */
    fun letGo() {
        parakeet?.release()
        parakeet = null
    }

    companion object {
        private const val KEY = "voiceModel"
        @Volatile private var shared: VoiceModel? = null

        fun of(context: Context): VoiceModel =
            shared ?: synchronized(this) { shared ?: VoiceModel(context.applicationContext).also { shared = it } }
    }
}
