package com.shahidy.iikb.voice

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File

/**
 * The speech model voice typing writes with, picked in Settings › Voice: Parakeet v3 (the default) or Parakeet Ultra,
 * each downloaded once on first use, or Android's own recognizer. One per process, so the app's Voice page and the
 * keyboard see the same downloads. Android's never stands in for a Parakeet: a dictation made while one downloads or
 * loads waits for it.
 */
class VoiceModel private constructor(context: Context) {
    enum class Model(val id: String, val title: String, val detail: String, val folder: String?, val remote: List<ModelFiles.Remote>) {
        V3("v3", "Parakeet v3", "Fast and accurate. Downloads once, about 670 MB.", "parakeet-tdt-0.6b-v3-int8", Parakeet.V3),
        ULTRA(
            "ultra", "Parakeet Ultra", "A little more accurate, as fast on Android. Downloads once, about 670 MB.",
            "parakeet-tdt-0.6b-ultra-int8", Parakeet.ULTRA,
        ),
        ANDROID("android", "Android", "Built into Android.", null, emptyList()),
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
    private val models = File(context.noBackupFilesDir, "models")
    private val files = Model.entries.filter { it.folder != null }
        .associateWith { ModelFiles(File(models, it.folder!!), it.remote) }

    var picked: Model
        get() = Model.entries.firstOrNull { it.id == preferences.getString(KEY, null) } ?: Model.V3
        set(value) {
            preferences.edit().putString(KEY, value.id).apply()
            pickedShown = value
            if (value != Model.ANDROID) prepare()
        }

    /** What the app's Voice page draws; Compose reads it. */
    var pickedShown by mutableStateOf(picked)
        private set

    /** The Parakeet a recording is written with: the picked one, or v3 while Android's is picked. */
    val parakeetModel get() = picked.takeIf { it != Model.ANDROID } ?: Model.V3

    /** The files of [parakeetModel]. */
    val parakeetFiles get() = files.getValue(parakeetModel)

    private val states = mutableStateMapOf<Model, State>()

    /** How far along [parakeetModel] is. */
    val state: State
        get() = states[parakeetModel] ?: if (parakeetFiles.present) State.Ready else State.Missing

    private val listeners = mutableListOf<() -> Unit>()

    fun listen(listener: () -> Unit) = listeners.add(listener)

    fun unlisten(listener: () -> Unit) = listeners.remove(listener)

    private fun show(model: Model, next: State) = main.post {
        states[model] = next
        listeners.toList().forEach { it() }
    }

    private val downloading = mutableMapOf<Model, Thread>()
    private val waiting = mutableMapOf<Model, MutableList<() -> Unit>>()

    /** Downloads [parakeetModel] if it isn't on the phone yet; [ready] runs on the main thread once its files are. */
    fun prepare(ready: (() -> Unit)? = null) {
        val model = parakeetModel
        val files = files.getValue(model)
        if (files.present) {
            if (state is State.Missing || state is State.Failed) show(model, State.Ready)
            ready?.let { main.post(it) }
            return
        }
        ready?.let { waiting.getOrPut(model, ::mutableListOf).add(it) }
        if (model in downloading) return
        show(model, State.Downloading(0.0))
        downloading[model] = Thread({
            val result = runCatching { files.download { show(model, State.Downloading(it.toDouble() / files.total)) } }
            main.post {
                downloading.remove(model)
                result.onSuccess {
                    show(model, State.Ready)
                    waiting.remove(model).orEmpty().forEach { it() }
                }.onFailure { show(model, State.Failed(it.message ?: "The download stopped")) }
            }
        }, "iikb-model-download").apply { start() }
    }

    private var parakeet: Parakeet? = null

    /**
     * [parakeetModel], loaded once its files are here, letting go of the other first so only one is ever in memory;
     * called on the dictation's own thread, never the main one.
     */
    @Synchronized
    fun parakeet(): Parakeet {
        val model = parakeetModel
        parakeet?.let { if (it.model == model) return it }
        letGo()
        show(model, State.Loading)
        try {
            return Parakeet.load(model, files.getValue(model)).also { parakeet = it }
        } finally {
            show(model, State.Ready)
        }
    }

    /**
     * What [parakeetModel] heard in [recording], and its title, written one recording at a time, whether the keyboard's
     * dictation or the app's Transcribe Again asks; off the main thread, once [prepare] has its files here.
     */
    @Synchronized
    fun write(recording: Recording): Pair<String, String> = parakeet().let { it.write(recording) to it.model.title }

    /** Let go once nothing is left to write, since a Parakeet loads again in a moment and holds its 700 MB meanwhile. */
    @Synchronized
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
