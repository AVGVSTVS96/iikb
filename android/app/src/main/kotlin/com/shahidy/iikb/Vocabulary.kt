package com.shahidy.iikb

import android.content.Context
import androidx.compose.runtime.mutableStateOf
import com.shahidy.iikb.keyboard.Native
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

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
    /** The English lexicon, mapped in place, for the made-up words that sound like a term. */
    private lateinit var lexicon: ByteBuffer
    /** Every field written, even an empty `heardAs`: iOS's `Vocabulary` reads none as missing. */
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val saved = mutableStateOf(emptyList<Term>())

    fun load(context: Context) {
        file = File(context.filesDir, "vocabulary.json")
        lexicon = context.assets.openFd("en.lexicon").use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).channel.use {
                it.map(FileChannel.MapMode.READ_ONLY, descriptor.startOffset, descriptor.length)
            }
        }
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

    /**
     * `text` as a dictation should type it, each word you listed spelled as you spelled it, and a made-up word that
     * sounds like one of them made it too (KeyboardCore's `Vocabulary`, with the English lexicon as iOS's app runs it).
     */
    fun corrected(text: String): String {
        if (saved.value.isEmpty()) return text
        val vocabulary = json.encodeToString(Saved.serializer(), Saved(saved.value)).encodeToByteArray()
        return corrected(text.encodeToByteArray(), vocabulary, lexicon).decodeToString()
    }

    init {
        Native
    }

    @JvmStatic private external fun corrected(text: ByteArray, vocabulary: ByteArray, lexicon: ByteBuffer): ByteArray
}
