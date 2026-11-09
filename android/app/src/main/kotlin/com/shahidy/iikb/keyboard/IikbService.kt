package com.shahidy.iikb.keyboard

import android.Manifest
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.UserDictionary
import android.text.InputType
import android.graphics.BitmapFactory
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.view.inputmethod.EditorInfo
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.shahidy.iikb.Settings
import com.shahidy.iikb.TypingStats
import com.shahidy.iikb.app.MIC_ON
import com.shahidy.iikb.app.MainActivity
import com.shahidy.iikb.voice.Dictation
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.time.LocalDateTime
import java.util.UUID
import java.util.concurrent.Executors

/**
 * iikb as Android's input method: the engine in Swift (`Native`), the app's field (`Field`), and the keys
 * (`KeyboardView`), wired as `FullKeyboardViewController` wires them on iOS.
 */
class IikbService : InputMethodService(), KeyboardView.Actions, Overlay.Actions, Dictation.Typist {
    private lateinit var settings: Settings
    private lateinit var field: Field
    private var handle = 0L
    private var view: KeyboardView? = null
    private var overlay: Overlay? = null
    private lateinit var clips: Clips
    /** KLIPY's GIFs, where the build has its key. */
    private var gifs: Gifs? = null
    private var shownPanel: String? = null
    private lateinit var clipboard: ClipboardManager
    /** The bar's More menu is out, or was when a panel opened from it. */
    private var menuOpen = false
    /** A panel opened from the menu has the keys up under it, typing into its search. */
    private var keysUp = false
    private lateinit var chats: Chats
    /** A chat is open, its message line in the app's field's place, which the keys type into (`Native.lineOpen`). */
    private var chatOpen = false
    /** What you'd begun in each chat you switched away from, by chat id. */
    private val drafts = mutableMapOf<String, String>()
    /** The menu's Chats shelf is following the chats' list. */
    private var listing = false
    private var feedback: Feedback? = null
    private lateinit var dictation: Dictation
    /** The field being typed in, counted up each time the keyboard starts in a new one, so a dictation lands only in its own. */
    private var fieldCount = 0
    /**
     * The field as sources know it, new each time the keyboard starts in one, as iOS's `documentIdentifier` is; none
     * until the first, since the keys draw once before Android names the field and its app.
     */
    private var fieldId: String? = null
    private lateinit var sources: Sources
    /** The personal dictionary as the engine last learned it. */
    private var lexicon: String? = null
    private var app: String? = null
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
        if (name == MIC_ON) {
            if (!settings.bool(MIC_ON)) dictation.stop()
            showDictation()
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
        typing = Native.typingLog()
        settings.preferences.registerOnSharedPreferenceChangeListener(changed)
        clips = Clips.of(this)
        clipboard = getSystemService(ClipboardManager::class.java)
        clipboard.addPrimaryClipChangedListener(copied)
        gifs = Klipy.of(this)?.let { Gifs(this, it) }
        chats = Chats(this)
        chats.changed = ::render
        dictation = Dictation(this, this)
        dictation.onChange = ::showDictation
        dictation.onLevel = { view?.mic?.hear(it, dictation.recorded) }
        sources = Sources(this, handle, ::render)
        configure()
    }

    private val copied = ClipboardManager.OnPrimaryClipChangedListener { catchUp() }

    /**
     * Keeps what's on the clipboard if the history hasn't seen it, by the time Android says it was copied: the keyboard
     * reads the clipboard only while it's Android's keyboard, so what was copied while it wasn't is kept when it's
     * next up. Never kept: what an app marks sensitive (a password manager's) and anything copied in a password or
     * incognito field.
     */
    private fun catchUp() {
        val clip = runCatching { clipboard.primaryClip }.getOrNull() ?: return
        val description = clip.description
        val time = description.timestamp
        val seen = settings.preferences.getLong(SEEN_CLIP, 0)
        if (time <= seen) return
        settings.preferences.edit().putLong(SEEN_CLIP, time).apply()
        if (incognito || description.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) == true) return
        val text = clip.getItemAt(0)?.text?.toString()?.takeIf { it.isNotBlank() } ?: return
        clips.keep(text, time / 1000.0)
    }

    override fun onDestroy() {
        settings.preferences.unregisterOnSharedPreferenceChangeListener(changed)
        clipboard.removePrimaryClipChangedListener(copied)
        overlay?.destroy()
        gifs?.close()
        chats.close()
        sources.close()
        save()
        TypingStats.append(Native.takeTyping(typing))
        dictation.close()
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
        view.mic.stopAnimation = settings.string("stopAnimation")
        feedback = Feedback(this, view)
        showDictation()
        view.addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
            if (right - left != oldRight - oldLeft) place()
        }
        ViewCompat.setOnApplyWindowInsetsListener(view) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.navigationBars() or WindowInsetsCompat.Type.tappableElement())
            bottom = bars.bottom / resources.displayMetrics.density.toDouble()
            place()
            insets
        }
        val overlay = Overlay(this, this, gifs, chats)
        this.overlay = overlay
        overlay.view.visibility = View.GONE
        val root = FrameLayout(this)
        root.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(overlay.view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0))
        overlay.attach(root)
        window.window?.decorView?.let(overlay::attach)
        overlay.resume()
        configure()
        return root
    }

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        if (!restarting) {
            leave()
            fieldCount++
            fieldId = UUID.randomUUID().toString()
            learnLexicon()
        }
        app = info.packageName
        chats.reload()
        Native.changeApp(handle, app?.encodeToByteArray())
        traits(info)
        place()
        showDictation()
        field.forget()
        Native.documentChanged(handle)
        catchUp()
        render()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        dictation.stop()
        leaveChat()
        menuOpen = false
        keysUp = false
        Native.panel(handle, null)
        Native.endSession(handle)
        if (!incognito) save()
        TypingStats.append(Native.takeTyping(typing))
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
        if (Native.documentChanged(handle)) {
            tellSources(byKeyboard = false)
            if (!incognito) save()
        }
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
        sources.reload()
        feedback?.strength = settings.string("hapticFeedback")
        feedback?.sound = settings.bool("sound")
        view?.characterPreview = settings.string("characterPreviewStyle")
        view?.mic?.stopAnimation = settings.string("stopAnimation")
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

    /** The hours typed since the keyboard last closed, as counts, for Stats (`TypingStats`). */
    private var typing = 0L

    private fun noteTyping() {
        val now = LocalDateTime.now()
        Native.noteTyping(
            typing, handle, SystemClock.elapsedRealtime() / 1000.0, now.toLocalDate().toString().encodeToByteArray(),
            now.hour, app?.encodeToByteArray(),
        )
    }

    /** A field that asks for no learning (an incognito tab) or holds a password: what's typed there isn't kept. */
    private var incognito = false

    /**
     * What a source sees: the field's text as the keyboard knows it, outside password fields and the ones that ask for
     * no learning (an incognito tab), and never a chat's line or the stand-in Android starts a keyboard on when no field
     * is focused (`TYPE_NULL`).
     */
    private fun tellSources(byKeyboard: Boolean) {
        val info = currentInputEditorInfo ?: return
        val field = fieldId ?: return
        if (incognito || chatOpen || info.inputType == InputType.TYPE_NULL || currentInputConnection == null) return
        sources.observe(field, app, byKeyboard)
    }

    private val hint get() = fieldId?.takeUnless { incognito || chatOpen }?.let { sources.hint(it, app) }

    /**
     * Android's personal dictionary, which a keyboard reads as iOS's reads Text Replacements: each word with a shortcut
     * is typed for it, and each without is kept as yours. Read off the main thread as each field opens.
     */
    private fun learnLexicon() {
        ranking.execute {
            val entries = runCatching {
                contentResolver.query(
                    UserDictionary.Words.CONTENT_URI, arrayOf(UserDictionary.Words.WORD, UserDictionary.Words.SHORTCUT),
                    null, null, null,
                )?.use { rows ->
                    buildList {
                        while (rows.moveToNext()) {
                            val word = rows.getString(0)?.takeIf { it.isNotBlank() } ?: continue
                            add(listOfNotNull(word, rows.getString(1)?.takeIf { it.isNotBlank() }))
                        }
                    }
                }
            }.getOrNull() ?: return@execute
            val json = Json.encodeToString(entries)
            main.post {
                if (json == lexicon) return@post
                lexicon = json
                Native.learnLexicon(handle, json.encodeToByteArray())
                render()
            }
        }
    }

    private fun render() {
        val view = view ?: return
        tellSources(byKeyboard = true)
        val frame = Frame.parse(Native.frame(handle))
        val chat = chatOpen
        if (frame.panel == null && !chat) keysUp = false
        val fromMenu = chat || frame.panel in setOf("clipboard", "transcripts", "gif")
        val menuShown = menuOpen && frame.panel == null && !chat
        val inPlace = fromMenu && !keysUp
        val metrics = resources.displayMetrics
        val normal = (frame.toolbar.height + frame.height).toFloat()
        view.grown = if (menuShown || chat) maxOf(normal, metrics.heightPixels / metrics.density - ROOM_FOR_APP) else 0f
        view.keysHidden = menuShown || inPlace
        view.barCovered = fromMenu && keysUp
        view.moreOn = menuShown || inPlace
        view.edits = if (menuShown) edits() else null
        view.chats = if (chat && !keysUp) chats.list.map { it.name } else null
        view.openChat = chats.list.indexOf(chats.open).takeIf { it >= 0 }
        view.hint = hint
        view.frame = frame
        follow(frame, menuShown)
        listChats(menuShown && hasChats(frame))
        place(frame, menuShown, fromMenu, inPlace, hasChats(frame))
        rank()
    }

    /** The overlay in the keys' place for the menu or a panel opened from it, or in the bar's with the keys up. */
    private fun place(frame: Frame, menuShown: Boolean, fromMenu: Boolean, inPlace: Boolean, hasChats: Boolean) {
        val overlay = overlay ?: return
        val shown = menuShown || fromMenu
        overlay.view.visibility = if (shown) View.VISIBLE else View.GONE
        if (!shown) return
        val density = resources.displayMetrics.density
        val bar = frame.toolbar
        val grown = view!!.grown.toDouble()
        val (top, height) = when {
            menuShown || chatOpen && inPlace -> bar.height to grown - bar.height - bottom
            chatOpen -> 0.0 to grown - frame.height
            inPlace -> bar.height to frame.height - bottom
            else -> 0.0 to bar.panelHeight
        }
        val params = overlay.view.layoutParams as FrameLayout.LayoutParams
        val wanted = (height.toFloat() * density).toInt()
        val margin = (top.toFloat() * density).toInt()
        if (params.height != wanted || params.topMargin != margin) {
            params.height = wanted
            params.topMargin = margin
            overlay.view.layoutParams = params
        }
        overlay.state = Overlay.State(
            Colors.of(frame.theme), bar.blockMinX.toFloat(), bar.blockMaxX.toFloat(),
            if (menuShown) null else frame.panel, frame.query, keysUp, bar.field.toFloat(), frame.width.toFloat(),
            Native.lineState(handle)?.let { Json.decodeFromString<Overlay.Line>(it.decodeToString()) }, hasChats,
            dictation.phase.name,
        )
    }

    /** Chats' shelf, with an extension added, where the keyboard is an iPhone's width or more. */
    private fun hasChats(frame: Frame) = chats.services.isNotEmpty() && frame.width >= 375

    /** The menu's shelf follows the chats while it's out; they stop once neither it nor a chat is. */
    private fun listChats(wanted: Boolean) {
        if (wanted == listing) return
        listing = wanted
        if (wanted) chats.start(opening = false) else if (!chatOpen) chats.stop()
    }

    /**
     * A chat opens with its message line in place of the app's field, which the keys type into as into a field whose
     * return key sends; `id` the chat, or the first.
     */
    private fun startChat(id: String?) {
        if (chatOpen) return
        menuOpen = false
        keysUp = false
        Native.panel(handle, null)
        Native.leaveField(handle)
        Native.traits(handle, "text other send sentences".encodeToByteArray(), true, requiresText = true, autocorrection = true)
        Native.lineOpen(handle, null)
        chatOpen = true
        chats.reload()
        chats.start(id)
        render()
    }

    /** Another chat from its pill: the line you'd begun goes with the chat you left, and this chat's comes back. */
    private fun switchChat(chat: Chats.Chat) {
        if (!chatOpen || chat == chats.open) return
        val line = Native.lineState(handle)?.let { Json.decodeFromString<Overlay.Line>(it.decodeToString()) }
        chats.open?.let { open -> if (line?.text.isNullOrEmpty()) drafts.remove(open.id) else drafts[open.id] = line!!.text }
        Native.lineRestore(handle, (drafts.remove(chat.id) ?: "").encodeToByteArray())
        chats.pick(chat)
        render()
    }

    /** Back to the app's field, as the keyboard found it. */
    private fun closeChat() {
        if (!chatOpen) return
        leaveChat()
        field.forget()
        Native.documentChanged(handle)
        render()
    }

    private fun leaveChat() {
        if (!chatOpen) return
        chats.stop()
        Native.leaveField(handle)
        Native.lineClose(handle)
        chatOpen = false
        keysUp = false
        currentInputEditorInfo?.let(::traits)
    }

    /** What return took from the line goes to the open chat; if it can't, it comes back to the line, unless you've begun another. */
    private fun sendTaken() {
        val text = Native.lineTake(handle)?.decodeToString()?.trim()?.takeIf { it.isNotEmpty() } ?: return
        chats.send(text) {
            val line = Native.lineState(handle)?.let { Json.decodeFromString<Overlay.Line>(it.decodeToString()) }
            if (chatOpen && line?.text.isNullOrEmpty()) {
                Native.lineRestore(handle, text.encodeToByteArray())
                render()
            }
        }
    }

    /** The GIF feed follows the panel's search, and shows trending on the menu's shelf. */
    private fun follow(frame: Frame, menuShown: Boolean) {
        val gifs = gifs ?: return
        if (frame.panel == "gif" && shownPanel != "gif") gifs.reset()
        shownPanel = frame.panel
        if (frame.panel == "gif") gifs.show(frame.query, app) else if (menuShown) gifs.show("", app)
    }

    override fun copyGif(gif: Gif, search: String) {
        feedback(Feedback.Kind.INPUT)
        gifs?.copy(gif, search, app) { said ->
            if (menuOpen && view?.frame?.panel == null) {
                menuOpen = false
                view?.notice = said
                render()
            } else {
                gifs?.notice = said
            }
        }
    }

    /**
     * A held GIF lifts out and drops into the app's field as the GIF itself, no paste: a drag across windows, which
     * the app takes or not, as an image drop on iOS. What's under the finger is the GIF's first frame.
     */
    override fun dragGif(gif: Gif, search: String) {
        feedback(Feedback.Kind.OTHER)
        gifs?.drag(gif, search, app) { clip, file ->
            val view = overlay?.view ?: return@drag
            if (clip == null || file == null) {
                gifs?.notice = "Couldn't get that GIF."
                return@drag
            }
            val frame = BitmapFactory.decodeFile(file.path) ?: return@drag
            view.startDragAndDrop(
                clip, GifShadow(frame, resources.displayMetrics.density), null,
                View.DRAG_FLAG_GLOBAL or View.DRAG_FLAG_GLOBAL_URI_READ,
            )
        }
    }

    /** What Cut, Copy and Paste can do: cut and copy need a selection, paste text on the clipboard. */
    private fun edits(): KeyboardView.Edits {
        val selected = !currentInputConnection?.getSelectedText(0).isNullOrEmpty()
        val paste = clipboard.primaryClipDescription?.let {
            it.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) || it.hasMimeType(ClipDescription.MIMETYPE_TEXT_HTML)
        } == true
        return KeyboardView.Edits(selected, selected, paste)
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
        noteTyping()
        connection?.endBatchEdit()
        if (chatOpen) sendTaken()
        render()
    }

    // KeyboardView.Actions

    override fun down(index: Int, taps: Int) {
        gifs?.notice = null
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
        keepOneHanded()
    }

    override fun expand() {
        event { Native.expand(handle) }
        keepOneHanded()
    }

    /** A one-handed side picked on the keyboard is saved as the setting, as iOS saves it, so it outlives the next change. */
    private fun keepOneHanded() {
        val side = Native.oneHanded(handle)?.decodeToString() ?: return
        if (side != settings.string("oneHanded")) settings.set("oneHanded", side)
    }

    override fun select(slot: Int) {
        feedback(Feedback.Kind.INPUT)
        event { Native.select(handle, slot) }
    }

    override fun acceptEmoji(emoji: String) {
        feedback(Feedback.Kind.INPUT)
        event { Native.acceptEmoji(handle, emoji.encodeToByteArray()) }
    }

    /** More opens the menu, and closes it or a panel opened from it, giving the keys back. */
    override fun more() {
        feedback(Feedback.Kind.OTHER)
        if (chatOpen) return closeChat()
        val panel = view?.frame?.panel
        if (panel != null && panel != "emoji") {
            menuOpen = false
            return event { Native.panel(handle, null) }
        }
        menuOpen = !menuOpen
        if (menuOpen) catchUp()
        render()
    }

    override fun edit(name: String) {
        menuOpen = false
        feedback(Feedback.Kind.OTHER)
        when (name) {
            "cut" -> currentInputConnection?.performContextMenuAction(android.R.id.cut)
            "copy" -> currentInputConnection?.performContextMenuAction(android.R.id.copy)
            else -> clipboard.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()?.let { return paste(it) }
        }
        render()
    }

    // Overlay.Actions

    /** Something picked in a panel or the menu's shelves is typed, and the menu gives the keys back. */
    override fun paste(text: String) {
        feedback(Feedback.Kind.INPUT)
        menuOpen = false
        event { Native.paste(handle, text.encodeToByteArray()) }
    }

    override fun open(panel: String) {
        feedback(Feedback.Kind.OTHER)
        keysUp = false
        event { Native.panel(handle, panel.encodeToByteArray()) }
    }

    /** Back steps out one level: the keys down, then the panel back to the menu it was opened from. */
    override fun back() {
        feedback(Feedback.Kind.OTHER)
        if (keysUp) {
            keysUp = false
            return render()
        }
        menuOpen = true
        event { Native.panel(handle, null) }
    }

    override fun raiseKeys() {
        if (keysUp) return
        feedback(Feedback.Kind.OTHER)
        keysUp = true
        render()
    }

    override fun appearance() {
        menuOpen = false
        render()
        openApp("appearance")
    }

    /**
     * Stops a dictation in progress, so what was heard is typed; otherwise starts one, right here, since Android lets
     * a keyboard use the microphone. With the mic turned off on Home, iikb opens there, as iOS's opens to turn it on.
     */
    override fun mic() {
        feedback(Feedback.Kind.OTHER)
        if (dictation.phase == Dictation.Phase.LISTENING) return dictation.stop()
        if (!settings.bool(MIC_ON)) return openApp()
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED ||
            !dictation.start(fieldCount, app)
        ) {
            return openApp(MainActivity.VOICE)
        }
        if (chatOpen && keysUp) {
            keysUp = false
            render()
        }
    }

    override fun cancelDictation() {
        feedback(Feedback.Kind.OTHER)
        dictation.cancel()
    }

    private fun showDictation() {
        val mic = view?.mic ?: return
        mic.ready = settings.bool(MIC_ON) && checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        mic.show(dictation.phase, dictation.recorded, dictation.saved, dictation.waitingFor)
        if (chatOpen) render()
    }

    // Dictation.Typist

    override fun style(heard: String, app: String?) =
        Native.written(handle, heard.encodeToByteArray(), app?.encodeToByteArray()).decodeToString()

    override fun type(text: String, plain: String, field: Int): Boolean {
        if (field != fieldCount || !isInputViewShown) {
            if (isInputViewShown && field != Dictation.NO_FIELD) {
                view?.notice = "Not typed here: it’s in Transcripts"
                view?.invalidate()
            }
            return false
        }
        event { Native.dictated(handle, text.encodeToByteArray(), plain.encodeToByteArray(), null) }
        return true
    }

    override fun dismissHint() {
        sources.dismissHint()
        render()
    }

    override fun tell(notice: String) {
        if (!isInputViewShown) return
        view?.notice = notice
        view?.invalidate()
    }

    override fun repeatDelete(words: Boolean) = event { Native.deleteRepeat(handle, words) }

    override fun pickEmoji(emoji: String, base: String?) {
        feedback(Feedback.Kind.INPUT)
        event { Native.pickEmoji(handle, emoji.encodeToByteArray(), base?.encodeToByteArray()) }
    }

    override fun chat(index: Int) {
        val chat = chats.list.getOrNull(index) ?: return
        feedback(Feedback.Kind.OTHER)
        switchChat(chat)
    }

    override fun openChat(id: String) {
        feedback(Feedback.Kind.OTHER)
        startChat(id.ifEmpty { null })
    }

    override fun browse() {
        keysUp = false
        render()
    }

    /** The send button sends as return does. */
    override fun send() {
        val index = view?.frame?.caps?.indexOfFirst { it.action == "return" }?.takeIf { it >= 0 } ?: return
        feedback(Feedback.Kind.SEPARATOR)
        event { Native.trigger(handle, index) }
    }

    override fun closePanel() {
        feedback(Feedback.Kind.OTHER)
        event { Native.panel(handle, null) }
    }

    /** Opening the panel again empties its search. */
    override fun clearSearch() {
        val panel = view?.frame?.panel ?: return
        event { Native.panel(handle, panel.encodeToByteArray()) }
    }

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

    companion object {
        /** The menu fills a keyboard grown to all of the screen but this, in dp, for the app (docs/design.md). */
        const val ROOM_FOR_APP = 140f
        const val SEEN_CLIP = "clipboard.seen"
    }
}
