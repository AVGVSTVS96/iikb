package com.shahidy.iikb.keyboard

import android.content.ClipData
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * What you copied (docs/design.md, "Clipboard"), one history for the app's process, so the keyboard and the app's
 * Clipboard tab show the same: KeyboardCore's `ClipboardHistory` in Swift (`Clips.swift`), saved as its JSON in
 * `clipboard.json`, and each copied image as a file in `clipboard/`, named by its SHA-256 as iOS's `ClipboardStore`
 * names it, so copying one again is the same clip. It never leaves the phone. Used on the main thread.
 */
class Clips private constructor(private val context: Context) {
    private val file = File(context.filesDir, "clipboard.json")
    private val images = File(context.filesDir, "clipboard")
    private val handle = Native.clipsCreate(file.takeIf { it.exists() }?.readBytes())
    private val listeners = mutableSetOf<() -> Unit>()
    private val work = Executors.newSingleThreadExecutor { Thread(it, "iikb-clips") }
    private val main = Handler(Looper.getMainLooper())

    @Serializable
    data class Row(
        /** Empty for an image. */
        val text: String, val kind: String, val length: String? = null, val age: String, val pinned: Boolean,
        val found: Double = 0.0, val site: String? = null, val name: String? = null, val color: Int? = null,
        /** An image's file in [file]'s folder. */
        val image: String? = null,
    )

    /** The clips holding `search`, pinned first, then newest; `words` counts their length in words. Images match no search. */
    fun rows(search: String = "", words: Boolean = false): List<Row> = json.decodeFromString(
        Native.clipsRows(handle, search.encodeToByteArray(), words, now()).decodeToString(),
    )

    /** Keeps text copied at `time`, in seconds since 1970; copying it again moves it up. */
    fun keep(text: String, time: Double = now()) = change { Native.clipsKeep(handle, text.encodeToByteArray(), null, time) }

    /**
     * Keeps what an app put on the clipboard at `time`: its image, copied here off the main thread, else its text. A
     * clip of iikb's own files is left out, since it's a GIF, which KLIPY doesn't allow keeping, or an image already
     * kept.
     */
    fun keep(clip: ClipData, time: Double) {
        val item = clip.getItemAt(0) ?: return
        val type = (0 until clip.description.mimeTypeCount).map(clip.description::getMimeType).firstOrNull { it.startsWith("image/") }
        val uri = item.uri
        if (uri != null && type != null) {
            if (uri.authority == AUTHORITY) return
            work.execute {
                val name = runCatching { save(uri, type) }.getOrNull() ?: return@execute
                main.post { change { Native.clipsKeep(handle, null, name.encodeToByteArray(), time) } }
            }
            return
        }
        item.text?.toString()?.takeIf { it.isNotBlank() }?.let { keep(it, time) }
    }

    fun pin(row: Row, pinned: Boolean) = change { Native.clipsPin(handle, row.text.encodeToByteArray(), row.image?.encodeToByteArray(), pinned) }

    fun remove(row: Row) {
        change { Native.clipsRemove(handle, row.text.encodeToByteArray(), row.image?.encodeToByteArray()) }
        row.image?.let { file(it).delete() }
    }

    fun clearUnpinned() {
        var gone = emptyList<String>()
        change { gone = json.decodeFromString(Native.clipsClear(handle).decodeToString()) }
        gone.forEach { file(it).delete() }
    }

    /** An image clip's file. */
    fun file(image: String) = File(images, image)

    /** An image clip as another app may read it, once granted: through the app's `FileProvider`. */
    fun uri(image: String): Uri = FileProvider.getUriForFile(context, AUTHORITY, file(image))

    /** An image clip as a clip for the clipboard. */
    fun clip(image: String): ClipData = ClipData.newUri(context.contentResolver, "Image", uri(image))

    fun listen(listener: () -> Unit) = listeners.add(listener)
    fun stopListening(listener: () -> Unit) = listeners.remove(listener)

    private fun change(body: () -> Unit) {
        body()
        Native.clipsSave(handle)?.let { bytes ->
            val next = File(file.parentFile, file.name + ".next")
            next.writeBytes(bytes)
            next.renameTo(file)
        }
        listeners.toList().forEach { it() }
    }

    /** The image at `uri` copied in under its hash, or null if it isn't one Android can read. */
    private fun save(uri: Uri, type: String): String? {
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(type) ?: return null
        images.mkdirs()
        val next = File.createTempFile("copied", ".next", images)
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            context.contentResolver.openInputStream(uri)?.use { input ->
                DigestOutputStream(next.outputStream(), digest).use { input.copyTo(it) }
            } ?: return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(next.path, bounds)
            if (bounds.outWidth <= 0) return null
            val name = digest.digest().joinToString("") { "%02x".format(it) } + "." + extension
            val kept = File(images, name)
            if (!kept.exists()) next.renameTo(kept)
            return name
        } finally {
            next.delete()
        }
    }

    private fun now() = System.currentTimeMillis() / 1000.0

    companion object {
        /** The app's `FileProvider` (AndroidManifest.xml, res/xml/files.xml). */
        const val AUTHORITY = "com.shahidy.iikb.files"
        private val json = Json { ignoreUnknownKeys = true }
        private var shared: Clips? = null

        fun of(context: Context): Clips = shared ?: Clips(context.applicationContext).also { shared = it }

        /** An image clip's type, from its file's extension. */
        fun type(image: String): String =
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(image.substringAfterLast('.')) ?: "image/*"
    }
}
