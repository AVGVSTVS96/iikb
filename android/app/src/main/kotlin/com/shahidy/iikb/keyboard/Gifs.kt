package com.shahidy.iikb.keyboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.util.concurrent.Executors

/**
 * The GIF panel's feed (docs/design.md, "GIF"): KeyboardCore's `GifSearch` (`Gifs.swift`) picks the one request out
 * and what shows, KLIPY answers it off the main thread, and what shows is Compose state. A GIF tapped goes on the
 * clipboard as a file, never into the clipboard's history, since KLIPY doesn't allow keeping its media.
 */
class Gifs(private val context: Context, private val klipy: Klipy) {
    @Serializable
    data class Shown(val state: String, val gifs: List<Gif>)

    var shown by mutableStateOf(Shown("loading", emptyList()))
        private set
    /** The clock in the search row: your recent GIFs in place of the feed. */
    var recents by mutableStateOf(false)
    /** What the search row says in place of the search, like "Copied", until your next touch. */
    var notice by mutableStateOf<String?>(null)

    private val recentsFile = File(context.filesDir, "gif-recents.json")
    private val handle = Native.gifsCreate(recentsFile.takeIf { it.exists() }?.readBytes())
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var feed: String? = null

    /** Shows the feed for what the field holds: trending when it's blank, a search, or recents with the clock on. */
    fun show(query: String, app: String?) {
        val wanted = if (recents) "recents" else "search:$query"
        if (wanted == feed) return
        feed = wanted
        send(Native.gifsWant(handle, wanted.encodeToByteArray(), app?.encodeToByteArray()))
        refresh()
    }

    /** Scrolled near the end: the next page, while KLIPY has one. */
    fun more() = send(Native.gifsMore(handle))

    /** A panel opening starts on its feed, without recents or a notice. */
    fun reset() {
        recents = false
        notice = null
        feed = null
    }

    private fun send(request: ByteArray?) {
        request ?: return
        val decoded = json.decodeFromString<Klipy.Request>(request.decodeToString())
        work.execute {
            val answer = klipy.gifs(decoded)
            main.post {
                val found = answer?.first?.let { json.encodeToString(it).encodeToByteArray() }
                val next = Native.gifsReceived(handle, request, found, answer?.second == true)
                refresh()
                send(next)
            }
        }
    }

    private fun refresh() {
        shown = json.decodeFromString(Native.gifsShown(handle).decodeToString())
    }

    /** Puts the GIF itself on the clipboard to paste, and keeps it in recents. `done` gets what to say. */
    fun copy(gif: Gif, search: String, app: String?, done: (String) -> Unit) {
        work.execute {
            val file = klipy.download(gif, File(context.cacheDir, "gifs"))
            main.post {
                if (file == null) return@post done("Couldn't copy that GIF.")
                val uri = FileProvider.getUriForFile(context, "com.shahidy.iikb.files", file)
                context.getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newUri(context.contentResolver, gif.title.ifEmpty { "GIF" }, uri))
                Native.gifsUse(handle, Klipy.base(gif.id).encodeToByteArray(), app?.encodeToByteArray())?.let {
                    val next = File(recentsFile.parentFile, recentsFile.name + ".next")
                    next.writeBytes(it)
                    next.renameTo(recentsFile)
                }
                done("Copied. Paste it where you want it.")
                work.execute { klipy.shared(gif, search) }
            }
        }
    }

    fun close() = work.shutdown()

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }
}
