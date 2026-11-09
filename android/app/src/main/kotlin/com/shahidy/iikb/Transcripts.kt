package com.shahidy.iikb

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/** One dictation, as iOS's `Transcript` keeps it. `date` is seconds since 1970; `app` is the package it was said for. */
@Serializable
data class Transcript(
    val id: String,
    val date: Double,
    /** What iikb typed for it, in your Writing Style; empty when the model heard no one. */
    val text: String,
    val seconds: Double,
    /** False when it wasn't typed where you said it: you canceled it, left the field first, or iikb ended mid-dictation. */
    val typed: Boolean = true,
    /** The model that wrote it, as Settings › Voice names it. */
    val model: String? = null,
    val app: String? = null,
    /** What the model wrote, when your style changed it. */
    val heard: String? = null,
    /** The microphone it was said into, as Settings › Voice names it; null for Android's recognizer, which listens itself. */
    val mic: String? = null,
    /** Whether that microphone was heard through a call's voice processing; never, since iikb records with Android's source for speech recognition. */
    val voiceProcessing: Boolean? = null,
    /** Written after iikb ended mid-dictation, the next time it started. */
    val recovered: Boolean? = null,
    /** What it was first written as, kept once Transcribe Again put another writing in its place. */
    val replaced: Replaced? = null,
) {
    val words get() = text.split(' ', '\n', '\t').count { it.isNotEmpty() }

    @Serializable
    data class Replaced(val model: String? = null, val text: String)
}

/**
 * Every dictation, newest first, one JSON line each in `filesDir/transcripts.jsonl`, as iOS's `Transcripts` keeps them,
 * and the sound of each Parakeet wrote as `recordings/<id>.wav` in the files Android doesn't back up, up to 512 MB
 * (about 4½ hours of talking), past which the oldest lose their sound. A recording with no transcript was left by a
 * keyboard that ended before writing it (`Dictation` writes it as it next starts). The keyboard and the app run in one
 * process, so both read this one copy; it's loaded as the process starts (`Iikb`) and used on the main thread.
 */
object Transcripts {
    private lateinit var file: File
    lateinit var recordings: File
        private set
    private var all = listOf<Transcript>()
    private val listeners = mutableSetOf<() -> Unit>()
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }
    private const val SOUND_LIMIT = 512L shl 20

    fun load(context: Context) {
        file = File(context.filesDir, "transcripts.jsonl")
        recordings = File(context.noBackupFilesDir, "recordings").apply { mkdirs() }
        all = file.takeIf { it.exists() }?.readLines().orEmpty()
            .mapNotNull { line -> runCatching { json.decodeFromString<Transcript>(line) }.getOrNull() }
            .sortedByDescending { it.date }
    }

    fun list(): List<Transcript> = all

    fun recording(id: String) = File(recordings, "$id.wav")

    fun hasRecording(id: String) = recording(id).exists()

    /** The recordings no transcript has, oldest first. */
    fun unwritten(): List<File> {
        val written = all.mapTo(HashSet()) { it.id }
        return sounds().filter { it.nameWithoutExtension !in written }.sortedBy { it.lastModified() }
    }

    fun add(transcript: Transcript) {
        all = listOf(transcript) + all
        file.appendText(json.encodeToString(Transcript.serializer(), transcript) + "\n")
        var kept = 0L
        for (sound in sounds().sortedByDescending { it.lastModified() }) {
            kept += sound.length()
            if (kept > SOUND_LIMIT) sound.delete()
        }
        changed()
    }

    fun delete(ids: Set<String>) {
        all = all.filter { it.id !in ids }
        ids.forEach { recording(it).delete() }
        save()
    }

    fun deleteAll() = delete(all.map { it.id }.toSet())

    /** Puts a new writing of a transcript's recording in its place, keeping the first as `replaced`. */
    fun replace(id: String, text: String, heard: String, model: String) {
        if (text.isEmpty()) return
        all = all.map {
            if (it.id != id) it else it.copy(
                text = text, heard = heard.takeIf { heard -> heard != text }, model = model,
                replaced = it.replaced ?: Transcript.Replaced(it.model, it.text),
            )
        }
        save()
    }

    /** Calls `listener` after each change, until the returned function is called. */
    fun listen(listener: () -> Unit): () -> Unit {
        listeners += listener
        return { listeners -= listener }
    }

    private fun sounds() = recordings.listFiles { it -> it.extension == "wav" }.orEmpty().toList()

    /** Written beside, then moved over, so a process killed mid-write keeps the file as it was. */
    private fun save() {
        val next = File(file.parentFile, file.name + ".next")
        next.writeText(all.reversed().joinToString("") { json.encodeToString(Transcript.serializer(), it) + "\n" })
        next.renameTo(file)
        changed()
    }

    private fun changed() = listeners.toList().forEach { it() }
}
