package com.shahidy.iikb.keyboard

import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.View
import android.view.inputmethod.EditorInfo
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.shahidy.iikb.Settings
import com.shahidy.iikb.app.MainActivity
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.Executors

/**
 * iikb as Android's input method: the engine in Swift (`Native`), the app's field (`Field`), and the keys
 * (`KeyboardView`), wired as `FullKeyboardViewController` wires them on iOS.
 */
class IikbService : InputMethodService(), KeyboardView.Actions {
    private lateinit var settings: Settings
    private lateinit var field: Field
    private var handle = 0L
    private var view: KeyboardView? = null
    private var feedback: Feedback? = null
    private var voice: Voice? = null
    private var bottom = 0.0
    private val main = Handler(Looper.getMainLooper())
    private val ranking = Executors.newSingleThreadExecutor()
    private var ranks = false
    /** The mapped model files, kept as long as the engine reads them in place. */
    private val mapped = mutableListOf<ByteBuffer>()
    private val changed = SharedPreferences.OnSharedPreferenceChangeListener { _, name ->
        if (name == "memoryResets") {
            memoryFile.delete()
            Native.resetMemory(handle)
        }
        configure()
    }

    override fun onCreate() {
        super.onCreate()
        settings = Settings(this)
        field = Field(this)
        handle = Native.create(
            field, map("en.lexicon"), map("en.network"), map("en.swipe"),
            assets.open("emoji.txt").use { it.readBytes() }, assets.open("emoji-search.txt").use { it.readBytes() },
        )
        memoryFile.takeIf { it.exists() }?.readBytes()?.let { Native.restoreMemory(handle, it) }
        emojiFile.takeIf { it.exists() }?.readBytes()?.let { Native.restoreEmojiHistory(handle, it) }
        settings.preferences.registerOnSharedPreferenceChangeListener(changed)
        configure()
    }

    override fun onDestroy() {
        settings.preferences.unregisterOnSharedPreferenceChangeListener(changed)
        save()
        voice?.close()
        Native.destroy(handle)
        ranking.shutdown()
        super.onDestroy()
    }

    /** The model data is stored uncompressed in the APK (build.gradle.kts), so it maps straight from it. */
    private fun map(name: String): ByteBuffer = assets.openFd(name).use { descriptor ->
        FileInputStream(descriptor.fileDescriptor).channel.use { channel ->
            channel.map(FileChannel.MapMode.READ_ONLY, descriptor.startOffset, descriptor.length)
        }
    }.also(mapped::add)

    private val memoryFile get() = File(filesDir, "typing-memory.json")
    private val emojiFile get() = File(filesDir, "emoji-history.json")

    private fun save() {
        Native.memory(handle)?.let { write(memoryFile, it) }
        Native.emojiHistory(handle)?.let { write(emojiFile, it) }
    }

    /** Written beside, then moved over, so a keyboard killed mid-write keeps what was learned before. */
    private fun write(file: File, bytes: ByteArray) {
        val next = File(file.parentFile, file.name + ".next")
        next.writeBytes(bytes)
        next.renameTo(file)
    }

    override fun onCreateInputView(): View {
        val view = KeyboardView(this, this)
        view.handle = handle
        this.view = view
        feedback = Feedback(this, view)
        voice = Voice(this) { heard -> event { Native.dictated(handle, heard.encodeToByteArray(), null, null) } }
        voice?.onChange = { view.micListening = it; view.invalidate() }
        ViewCompat.setOnApplyWindowInsetsListener(view) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.navigationBars() or WindowInsetsCompat.Type.tappableElement())
            bottom = bars.bottom / resources.displayMetrics.density.toDouble()
            place()
            insets
        }
        configure()
        return view
    }

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        if (!restarting) leave()
        Native.changeApp(handle, info.packageName?.encodeToByteArray())
        traits(info)
        place()
        field.forget()
        Native.documentChanged(handle)
        render()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        voice?.stop()
        Native.endSession(handle)
        if (!incognito) save()
        super.onFinishInputView(finishingInput)
    }

    /** Leaves the field; what an incognito field taught is dropped by reading back what was kept before it. */
    private fun leave() {
        Native.leaveField(handle)
        if (incognito) memoryFile.takeIf { it.exists() }?.readBytes()?.let { Native.restoreMemory(handle, it) }
    }

    override fun onUpdateSelection(
        oldSelStart: Int, oldSelEnd: Int, newSelStart: Int, newSelEnd: Int, candidatesStart: Int, candidatesEnd: Int,
    ) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        field.forget()
        if (Native.documentChanged(handle) && !incognito) save()
        render()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        place()
    }

    override fun onEvaluateFullscreenMode() = false

    private fun configure() {
        if (handle == 0L) return
        Native.configure(handle, settings.lines().encodeToByteArray())
        feedback?.strength = settings.string("hapticFeedback")
        feedback?.sound = settings.bool("sound")
        view?.characterPreview = settings.string("characterPreviewStyle")
        render()
    }

    private val dark get() = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES

    /** Android draws its own keyboard switcher in the bar under the keys, as iOS does on Face ID iPhones: no globe key. */
    private fun place() {
        val metrics = resources.displayMetrics
        val width = (view?.width?.takeIf { it > 0 } ?: metrics.widthPixels) / metrics.density
        Native.place(
            handle, width.toDouble(), metrics.widthPixels / metrics.density.toDouble(),
            metrics.heightPixels / metrics.density.toDouble(), bottom, dark, false,
        )
        render()
    }

    /** The field's keyboard, return key and capitals, as `InputTraits(_ proxy:)` reads them on iOS. */
    private fun traits(info: EditorInfo) {
        val type = info.inputType
        val variation = type and InputType.TYPE_MASK_VARIATION
        val text = type and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT
        val kind = when {
            type and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_NUMBER ->
                if (type and InputType.TYPE_NUMBER_FLAG_DECIMAL != 0) "decimal" else "number"
            type and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_PHONE -> "number"
            text && (variation == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS) -> "email"
            text && variation == InputType.TYPE_TEXT_VARIATION_URI -> "url"
            else -> "text"
        }
        val password = text && variation in setOf(
            InputType.TYPE_TEXT_VARIATION_PASSWORD, InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        )
        val content = when {
            type and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_PHONE -> "telephoneNumber"
            kind == "email" -> "emailAddress"
            kind == "url" -> "url"
            else -> "other"
        }
        val action = info.imeOptions and EditorInfo.IME_MASK_ACTION
        val noEnterAction = info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0
        val returnKind = if (noEnterAction) "default" else when (action) {
            EditorInfo.IME_ACTION_GO -> "go"
            EditorInfo.IME_ACTION_SEARCH -> "search"
            EditorInfo.IME_ACTION_SEND -> "send"
            EditorInfo.IME_ACTION_DONE -> "done"
            EditorInfo.IME_ACTION_NEXT -> "next"
            else -> "default"
        }
        val capitals = when {
            !text -> "none"
            type and InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS != 0 -> "allCharacters"
            type and InputType.TYPE_TEXT_FLAG_CAP_WORDS != 0 -> "words"
            type and InputType.TYPE_TEXT_FLAG_CAP_SENTENCES != 0 -> "sentences"
            else -> "none"
        }
        val corrects = text && !password && type and InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS == 0 &&
            kind == "text" && variation != InputType.TYPE_TEXT_VARIATION_FILTER
        Native.traits(
            handle, "$kind $content $returnKind $capitals".encodeToByteArray(), smartPunctuation = !password,
            requiresText = false, autocorrection = corrects,
        )
        incognito = info.imeOptions and EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING != 0 || password
        if (incognito) save()
    }

    /** A field that asks for no learning (an incognito tab) or holds a password: what's typed there isn't kept. */
    private var incognito = false

    private fun render() {
        val view = view ?: return
        view.frame = Frame.parse(Native.frame(handle))
        rank()
    }

    /** Suggestions rank off the main thread, as on iOS, one job at a time; the newest text wins. */
    private fun rank() {
        if (ranks) return
        val job = Native.suggestionJob(handle).takeIf { it != 0L } ?: return
        ranks = true
        ranking.execute {
            Native.runJob(job)
            main.post {
                ranks = false
                Native.finishJob(handle, job)
                render()
            }
        }
    }

    /** Runs one event against the field as one batch edit, so the app sees a correction land at once. */
    private inline fun event(body: () -> Unit) {
        val connection = currentInputConnection
        connection?.beginBatchEdit()
        field.forget()
        body()
        connection?.endBatchEdit()
        render()
    }

    // KeyboardView.Actions

    override fun down(index: Int, taps: Int) {
        val cap = view?.frame?.caps?.getOrNull(index)
        feedback(
            when (cap?.action) {
                "character" -> Feedback.Kind.INPUT
                "space", "return", "tab" -> Feedback.Kind.SEPARATOR
                "delete" -> Feedback.Kind.DELETE
                else -> Feedback.Kind.OTHER
            },
        )
        event { Native.down(handle, index, taps) }
    }

    override fun up(index: Int) = event { Native.up(handle, index) }

    override fun type(index: Int, text: String, x: Double, y: Double) =
        event { Native.type(handle, index, text.encodeToByteArray(), x, y) }

    override fun trigger(index: Int) {
        when (view?.frame?.caps?.getOrNull(index)?.action) {
            "dismiss" -> return requestHideSelf(0)
            "nextKeyboard" -> {
                switchToNextInputMethod(false)
                return
            }
            "dictate" -> return mic()
        }
        event { Native.trigger(handle, index) }
    }

    override fun slide(text: String) = event { Native.slide(handle, text.encodeToByteArray()) }

    override fun swipe(path: List<KeyboardView.SwipePoint>) = event {
        Native.swipe(
            handle, path.map { it.x }.toFloatArray(), path.map { it.y }.toFloatArray(),
            path.map { it.time }.toFloatArray(),
        )
    }

    override fun cursor(step: Int) = event { Native.cursor(handle, step) }

    private val measure = android.graphics.Paint().apply { textSize = 17f }

    override fun advance(step: Int): Float {
        field.forget()
        val crossed = Native.crossed(handle, step)?.decodeToString()?.takeUnless { it == "\n" } ?: " "
        return measure.measureText(crossed)
    }

    override fun menu(item: Int) {
        when (view?.frame?.menu?.getOrNull(item)?.symbol) {
            "gearshape" -> openApp()
            "globe" -> switchToNextInputMethod(false)
        }
        event { Native.menu(handle, item) }
    }

    override fun select(slot: Int) {
        feedback(Feedback.Kind.INPUT)
        event { Native.select(handle, slot) }
    }

    override fun acceptEmoji(emoji: String) {
        feedback(Feedback.Kind.INPUT)
        event { Native.acceptEmoji(handle, emoji.encodeToByteArray()) }
    }

    override fun more() {
        openApp()
    }

    override fun mic() {
        feedback(Feedback.Kind.OTHER)
        val voice = voice ?: return
        if (!voice.permitted) return openApp(MainActivity.VOICE)
        voice.toggle()
    }

    override fun repeatDelete(words: Boolean) = event { Native.deleteRepeat(handle, words) }

    override fun pickEmoji(emoji: String, base: String?) {
        feedback(Feedback.Kind.INPUT)
        event { Native.pickEmoji(handle, emoji.encodeToByteArray(), base?.encodeToByteArray()) }
    }

    override fun closePanel() {
        feedback(Feedback.Kind.OTHER)
        event { Native.panel(handle, null) }
    }

    /** Opening the panel again empties its search. */
    override fun clearSearch() = event { Native.panel(handle, "emoji".encodeToByteArray()) }

    override fun emojiResults() = Native.emojiResults(handle).decodeToString().split("\n").filter { it.isNotEmpty() }

    override fun tones(emoji: String) =
        Native.tones(handle, emoji.encodeToByteArray()).decodeToString().split("\n").filter { it.isNotEmpty() }

    override fun feedback(kind: Feedback.Kind) {
        feedback?.play(kind)
    }

    private fun openApp(page: String? = null) {
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .apply { page?.let { putExtra(MainActivity.PAGE, it) } },
        )
    }
}
