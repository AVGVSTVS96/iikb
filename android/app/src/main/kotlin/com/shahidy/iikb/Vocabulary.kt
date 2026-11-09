package com.shahidy.iikb

import android.content.Context
import androidx.compose.runtime.mutableStateOf
import com.shahidy.iikb.keyboard.Native
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Your Dictionary: the words the voice model gets wrong, each with what it writes instead, kept as iOS's `Vocabulary`
 * JSON in `filesDir/vocabulary.json`. The keyboard and the app share the process, so both read this one copy, loaded
 * as it starts (`Iikb`) and used on the main thread.
 */
object Vocabulary {
    @Serializable
    data class Term(val term: String, val heardAs: List<String> = emptyList())

    @Serializable
    private data class Saved(val terms: List<Term>)

    private lateinit var file: File
    private val json = Json { ignoreUnknownKeys = true }
    private val saved = mutableStateOf(emptyList<Term>())

    fun load(context: Context) {
        file = File(context.filesDir, "vocabulary.json")
        saved.value = file.takeIf { it.exists() }
            ?.let { runCatching { json.decodeFromString<Saved>(it.readText()).terms }.getOrNull() }.orEmpty()
    }

    fun terms(): List<Term> = saved.value

    /** Written beside, then moved over, so a process killed mid-write keeps the file as it was. */
    fun set(terms: List<Term>) {
        saved.value = terms
        val next = File(file.parentFile, file.name + ".next")
        next.writeText(json.encodeToString(Saved.serializer(), Saved(terms)))
        next.renameTo(file)
    }

    /** `text` as a dictation should type it, each word you listed spelled as you spelled it (KeyboardCore's `Vocabulary`). */
    fun corrected(text: String): String =
        if (saved.value.isEmpty()) text else corrected(text.encodeToByteArray(), file.readBytes()).decodeToString()

    init {
        Native
    }

    @JvmStatic private external fun corrected(text: ByteArray, vocabulary: ByteArray): ByteArray
}
