package com.shahidy.iikb

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/** What typing did, as counts, never a letter of it (KeyboardCore's `TypingTally`). */
@Serializable
data class TypingTally(
    val keys: Int = 0,
    val characters: Int = 0,
    val deletes: Int = 0,
    val words: Int = 0,
    val corrected: Int = 0,
    val undone: Int = 0,
    val picked: Int = 0,
    val emoji: Int = 0,
)

/** One hour of typing in one app (KeyboardCore's `TypingHour`): `day` is local, as `2026-11-04`. */
@Serializable
data class TypingHour(val day: String, val hour: Int, val app: String, val tally: TypingTally, val seconds: Double)

/**
 * The hours the keyboard typed, one JSON line each in `filesDir/typing.jsonl`, appended each time it closes, as iOS's
 * `TypingStats` keeps them. Used on the main thread.
 */
object TypingStats {
    private lateinit var file: File
    private val listeners = mutableSetOf<() -> Unit>()
    private val json = Json { ignoreUnknownKeys = true }

    fun load(context: Context) {
        file = File(context.filesDir, "typing.jsonl")
    }

    /** Lines from the engine's `TypingLog`. */
    fun append(lines: ByteArray) {
        if (lines.isEmpty()) return
        file.appendBytes(lines)
        listeners.toList().forEach { it() }
    }

    fun hours(): List<TypingHour> = file.takeIf { it.exists() }?.readLines().orEmpty()
        .mapNotNull { line -> runCatching { json.decodeFromString<TypingHour>(line) }.getOrNull() }

    fun delete() {
        file.delete()
        listeners.toList().forEach { it() }
    }

    fun listen(listener: () -> Unit): () -> Unit {
        listeners += listener
        return { listeners -= listener }
    }
}
