package com.shahidy.iikb.app.stats

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shahidy.iikb.Service
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * A computer that shares its typing and dictation with Stats: an address that answers `GET typing-stats.json`, in
 * Keystroke's shape, to whoever sends its token. `mac/share` sets a Mac up and shows its link (docs/computers.md).
 */
@Serializable
data class Computer(val name: String, val url: String, val token: String) {
    companion object {
        /** `iikb://computer?name=…&url=…&token=…`, the link `mac/share` shows as a QR code. */
        fun of(link: Uri): Computer? {
            if (link.scheme != "iikb" || link.host != "computer") return null
            val name = link.getQueryParameter("name")?.takeIf { it.isNotEmpty() } ?: return null
            val url = link.getQueryParameter("url")?.takeIf(Service::reachable) ?: return null
            val token = link.getQueryParameter("token")?.takeIf { it.isNotEmpty() } ?: return null
            return Computer(name, url, token)
        }
    }
}

/**
 * The computers you added, each with what it last shared, kept so a computer that's asleep or out of reach shows as it
 * last was: the list in the files Android backs up, each one's last answer in the cache.
 */
class Computers private constructor(context: Context) {
    private val list = File(context.filesDir, "computers.json")
    private val copies = File(context.cacheDir, "computers")

    var all by mutableStateOf(runCatching { json.decodeFromString<List<Computer>>(list.readText()) }.getOrDefault(emptyList()))
        private set
    var activity by mutableStateOf(emptyMap<String, Activity>())
        private set

    /** When each computer last changed what it shares. */
    var asOf by mutableStateOf(emptyMap<String, Instant>())
        private set
    private var reading = false

    init {
        for (computer in all) {
            val copy = copy(computer.name)
            KeystrokeStats.decode(runCatching { copy.readText() }.getOrNull() ?: continue)?.let {
                activity += computer.name to it
                asOf += computer.name to Instant.ofEpochMilli(copy.lastModified())
            }
        }
    }

    /** Adds `computer`, in place of one with the same name, and reads it. */
    fun add(computer: Computer) {
        all = all.filter { it.name != computer.name } + computer
        save()
        MainScope().launch { read(computer) }
    }

    fun remove(name: String) {
        all = all.filter { it.name != name }
        activity -= name
        asOf -= name
        copy(name).delete()
        save()
    }

    /** Asks every computer for what it shares now, all at once. */
    suspend fun read() {
        if (reading) return
        reading = true
        try {
            coroutineScope { all.map { async { read(it) } }.awaitAll() }
        } finally {
            reading = false
        }
    }

    private suspend fun read(computer: Computer) {
        val (text, modified) = withContext(Dispatchers.IO) { fetch(computer) } ?: return
        val shared = KeystrokeStats.decode(text) ?: return
        if (computer !in all) return
        activity += computer.name to shared
        asOf += computer.name to modified
        withContext(Dispatchers.IO) {
            copies.mkdirs()
            val copy = copy(computer.name)
            copy.writeText(text)
            copy.setLastModified(modified.toEpochMilli())
        }
    }

    private fun fetch(computer: Computer): Pair<String, Instant>? = runCatching {
        val connection = URL(computer.url.trimEnd('/') + "/typing-stats.json").openConnection() as HttpURLConnection
        try {
            connection.useCaches = false
            connection.connectTimeout = 10_000
            connection.readTimeout = 20_000
            connection.setRequestProperty("Authorization", "Bearer ${computer.token}")
            if (connection.responseCode != 200) return null
            val text = connection.inputStream.bufferedReader().use { it.readText() }
            text to (connection.lastModified.takeIf { it > 0 }?.let(Instant::ofEpochMilli) ?: Instant.now())
        } finally {
            connection.disconnect()
        }
    }.getOrNull()

    private fun save() = list.writeText(json.encodeToString(all))

    private fun copy(name: String) = File(copies, Uri.encode(name) + ".json")

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        @Volatile private var shared: Computers? = null

        fun of(context: Context): Computers =
            shared ?: synchronized(this) { shared ?: Computers(context.applicationContext).also { shared = it } }
    }
}

/** Keystroke's counts of a computer's typing and dictation (never what's typed), the shape every computer shares. */
private object KeystrokeStats {
    /** Keystroke's file, version 3: each day's `typed` (physical keys) and `voice` (dictation) counts, and the apps dictation went into. */
    @Serializable
    private data class Shared(
        val days: Map<String, Daily>,
        val sources: Map<String, Source>? = null,
        val wpmHistogram: Map<String, Double>? = null,
    )

    @Serializable
    private data class Daily(val typed: Counts, val voice: Counts)

    @Serializable
    private data class Source(val name: String, val words: Double)

    @Serializable
    private data class Counts(
        val keystrokes: Double = 0.0, val chars: Double = 0.0, val words: Double = 0.0, val backspaces: Double = 0.0,
        val activeMs: Double = 0.0, val timedChars: Double = 0.0, val timedMs: Double = 0.0, val inserts: Double = 0.0,
        val hourChars: List<Double> = emptyList(), val peakWpm: Double = 0.0,
    )

    private val json = Json { ignoreUnknownKeys = true }

    fun decode(text: String): Activity? {
        val shared = runCatching { json.decodeFromString<Shared>(text) }.getOrNull() ?: return null
        val days = shared.days.mapNotNull { (key, day) ->
            runCatching { LocalDate.parse(key) }.getOrNull()?.let { it to Day(typed(day.typed), said(day.voice)) }
        }.toMap()
        val speeds = shared.wpmHistogram.orEmpty().mapNotNull { (key, count) -> key.toIntOrNull()?.let { it to count } }
            .groupBy({ it.first }, { it.second }).mapValues { it.value.sum() }
        val said = shared.sources.orEmpty().values.map { it.name to it.words.toInt() }.filter { it.second > 0 }
            .sortedByDescending { it.second }
        return Activity(days, mapOf(Kind.SAID to said), speeds)
    }

    private fun typed(counts: Counts) = Channel(
        words = counts.words.toInt(), characters = counts.chars.toInt(), paced = counts.chars / 5,
        seconds = counts.activeMs / 1000, keys = counts.keystrokes.toInt(), deletes = counts.backspaces.toInt(),
        peak = counts.peakWpm, hours = hours(counts.hourChars),
    )

    /** Keystroke knows how long you talked only for some dictations, so the pace goes by those alone. */
    private fun said(counts: Counts) = Channel(
        words = counts.words.toInt(), characters = counts.chars.toInt(), paced = counts.timedChars / 5,
        seconds = counts.timedMs / 1000, dictations = counts.inserts.toInt(), hours = hours(counts.hourChars),
    )

    private fun hours(values: List<Double>) = List(24) { values.getOrElse(it) { 0.0 } }
}
