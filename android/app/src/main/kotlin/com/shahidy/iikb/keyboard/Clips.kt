package com.shahidy.iikb.keyboard

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/**
 * What you copied (docs/design.md, "Clipboard"), one history for the app's process, so the keyboard and the app's
 * Clipboard tab show the same: KeyboardCore's `ClipboardHistory` in Swift (`Clips.swift`), saved as its JSON in
 * `clipboard.json`. It never leaves the phone. Used on the main thread.
 */
class Clips private constructor(private val file: File) {
    private val handle = Native.clipsCreate(file.takeIf { it.exists() }?.readBytes())
    private val listeners = mutableSetOf<() -> Unit>()

    @Serializable
    data class Row(
        val text: String, val kind: String, val length: String? = null, val age: String, val pinned: Boolean,
        val site: String? = null, val name: String? = null, val color: Int? = null,
    )

    /** The clips holding `search`, pinned first, then newest; `words` counts their length in words. */
    fun rows(search: String = "", words: Boolean = false): List<Row> = json.decodeFromString(
        Native.clipsRows(handle, search.encodeToByteArray(), words, now()).decodeToString(),
    )

    /** Keeps something copied at `time`, in seconds since 1970; copying it again moves it up. */
    fun keep(text: String, time: Double = now()) = change { Native.clipsKeep(handle, text.encodeToByteArray(), time) }
    fun pin(text: String, pinned: Boolean) = change { Native.clipsPin(handle, text.encodeToByteArray(), pinned) }
    fun remove(text: String) = change { Native.clipsRemove(handle, text.encodeToByteArray()) }
    fun clearUnpinned() = change { Native.clipsClear(handle) }

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

    private fun now() = System.currentTimeMillis() / 1000.0

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        private var shared: Clips? = null

        fun of(context: Context): Clips =
            shared ?: Clips(File(context.applicationContext.filesDir, "clipboard.json")).also { shared = it }
    }
}
