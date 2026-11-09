package com.shahidy.iikb

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

/** One dictation, as iOS's `Transcript` keeps it. `date` is seconds since 1970; `app` is the package it was typed into. */
@Serializable
data class Transcript(
    val id: String,
    val date: Double,
    val text: String,
    val seconds: Double,
    val typed: Boolean = true,
    val model: String? = null,
    val app: String? = null,
) {
    val words get() = text.split(' ', '\n', '\t').count { it.isNotEmpty() }
}

/**
 * Every dictation, newest first, one JSON line each in `filesDir/transcripts.jsonl`, as iOS's `Transcripts` keeps them.
 * The keyboard and the app run in one process, so both read this one copy; it's loaded as the process starts (`Iikb`)
 * and used on the main thread.
 */
object Transcripts {
    private lateinit var file: File
    private var all = listOf<Transcript>()
    private val listeners = mutableSetOf<() -> Unit>()
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    fun load(context: Context) {
        file = File(context.filesDir, "transcripts.jsonl")
        all = file.takeIf { it.exists() }?.readLines().orEmpty()
            .mapNotNull { line -> runCatching { json.decodeFromString<Transcript>(line) }.getOrNull() }
            .sortedByDescending { it.date }
    }

    fun list(): List<Transcript> = all

    fun add(text: String, seconds: Double, app: String?, model: String?): Transcript {
        val transcript = Transcript(
            UUID.randomUUID().toString(), System.currentTimeMillis() / 1000.0, text, seconds, model = model, app = app,
        )
        all = listOf(transcript) + all
        file.appendText(json.encodeToString(Transcript.serializer(), transcript) + "\n")
        changed()
        return transcript
    }

    fun delete(ids: Set<String>) {
        all = all.filter { it.id !in ids }
        save()
    }

    fun deleteAll() = delete(all.map { it.id }.toSet())

    /** Calls `listener` after each change, until the returned function is called. */
    fun listen(listener: () -> Unit): () -> Unit {
        listeners += listener
        return { listeners -= listener }
    }

    /** Written beside, then moved over, so a process killed mid-write keeps the file as it was. */
    private fun save() {
        val next = File(file.parentFile, file.name + ".next")
        next.writeText(all.reversed().joinToString("") { json.encodeToString(Transcript.serializer(), it) + "\n" })
        next.renameTo(file)
        changed()
    }

    private fun changed() = listeners.toList().forEach { it() }
}
