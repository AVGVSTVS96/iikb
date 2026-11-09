package com.shahidy.iikb.app.stats

import android.content.Context
import com.shahidy.iikb.Transcript
import com.shahidy.iikb.TypingHour
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Typing or talking, as iOS's `Activity` counts it: the phone's typing from the keyboard's hours, its talking from Transcripts. */
enum class Kind { TYPED, SAID }

/**
 * Typing or talking on one day. Speed is `paced` words over `seconds`: for typing, words of five characters a minute
 * of typing, pauses left out; for talking, the words of each dictation over its length.
 */
data class Channel(
    val words: Int = 0,
    val characters: Int = 0,
    val paced: Double = 0.0,
    val seconds: Double = 0.0,
    val keys: Int = 0,
    val deletes: Int = 0,
    val dictations: Int = 0,
    val corrected: Int = 0,
    val undone: Int = 0,
    val picked: Int = 0,
    val emoji: Int = 0,
    /** The fastest stretch's words a minute. */
    val peak: Double = 0.0,
    /** Characters in each hour of the day, midnight first. */
    val hours: List<Double> = List(24) { 0.0 },
) {
    operator fun plus(other: Channel) = Channel(
        words + other.words, characters + other.characters, paced + other.paced, seconds + other.seconds,
        keys + other.keys, deletes + other.deletes, dictations + other.dictations, corrected + other.corrected,
        undone + other.undone, picked + other.picked, emoji + other.emoji, maxOf(peak, other.peak),
        hours.zip(other.hours) { a, b -> a + b },
    )

    /** Words a minute, once there's a minute to tell by. */
    val speed get() = if (seconds >= 60) paced / seconds * 60 else null
    val isEmpty get() = words == 0 && keys == 0 && dictations == 0
}

data class Day(val typed: Channel = Channel(), val said: Channel = Channel()) {
    operator fun get(kind: Kind) = if (kind == Kind.TYPED) typed else said
}

/** How much the phone typed and said, a day at a time. */
class Activity(
    val days: Map<LocalDate, Day> = emptyMap(),
    /** Words by the app they went into, most first. */
    val apps: Map<Kind, List<Pair<String, Int>>> = emptyMap(),
    /** How often you type at each speed: the start of each 5 wpm band, and how many stretches fell in it. */
    val speeds: Map<Int, Double> = emptyMap(),
) {
    fun channel(kind: Kind, day: LocalDate) = days[day]?.get(kind) ?: Channel()

    fun total(kind: Kind, since: LocalDate? = null) =
        days.filterKeys { since == null || it >= since }.values.fold(Channel()) { sum, day -> sum + day[kind] }

    fun isEmpty(kind: Kind) = total(kind).isEmpty

    fun both(day: LocalDate) = channel(Kind.TYPED, day) + channel(Kind.SAID, day)

    /** Days with words in them, oldest first. */
    val activeDays by lazy { days.filter { it.value.typed.words + it.value.said.words > 0 }.keys.sorted() }

    companion object {
        /** The hours the keyboard kept and every transcript, with apps named by `name`. */
        fun of(hours: List<TypingHour>, transcripts: List<Transcript>, name: (String) -> String): Activity {
            val days = mutableMapOf<LocalDate, Day>()
            val speeds = mutableMapOf<Int, Double>()
            val typedApps = mutableMapOf<String, Int>()
            for (hour in hours) {
                val date = runCatching { LocalDate.parse(hour.day) }.getOrNull() ?: continue
                if (hour.hour !in 0 until 24) continue
                val tally = hour.tally
                var peak = 0.0
                if (hour.seconds >= 10 && tally.characters >= 20) {
                    val speed = tally.characters / 5.0 / hour.seconds * 60
                    peak = speed
                    if (speed < 250) speeds.merge((speed / 5).toInt() * 5, 1.0, Double::plus)
                }
                val channel = Channel(
                    words = tally.words, characters = tally.characters, paced = tally.characters / 5.0,
                    seconds = hour.seconds, keys = tally.keys, deletes = tally.deletes, corrected = tally.corrected,
                    undone = tally.undone, picked = tally.picked, emoji = tally.emoji, peak = peak,
                    hours = List(24) { if (it == hour.hour) tally.characters.toDouble() else 0.0 },
                )
                val day = days[date] ?: Day()
                days[date] = day.copy(typed = day.typed + channel)
                if (hour.app.isNotEmpty()) typedApps.merge(hour.app, tally.words, Int::plus)
            }
            val saidApps = mutableMapOf<String, Int>()
            val zone = ZoneId.systemDefault()
            for (transcript in transcripts) {
                if (transcript.text.isEmpty()) continue
                val time = Instant.ofEpochMilli((transcript.date * 1000).toLong()).atZone(zone)
                val words = transcript.words
                if (transcript.typed) transcript.app?.let { saidApps.merge(it, words, Int::plus) }
                val channel = Channel(
                    words = words, characters = transcript.text.length, paced = words.toDouble(),
                    seconds = transcript.seconds, dictations = 1,
                    hours = List(24) { if (it == time.hour) transcript.text.length.toDouble() else 0.0 },
                )
                val date = time.toLocalDate()
                val day = days[date] ?: Day()
                days[date] = day.copy(said = day.said + channel)
            }
            fun named(apps: Map<String, Int>) = apps.entries.groupBy({ name(it.key) }, { it.value })
                .map { (name, words) -> name to words.sum() }.filter { it.second > 0 }.sortedByDescending { it.second }
            return Activity(days, mapOf(Kind.TYPED to named(typedApps), Kind.SAID to named(saidApps)), speeds)
        }
    }
}

/**
 * Apps by the name their launcher shows, which Android tells iikb for any app it can open (the manifest's `queries`);
 * any other by its package's last part.
 */
class AppNames(private val context: Context) {
    private val names = mutableMapOf<String, String>()

    fun of(app: String): String = names.getOrPut(app) {
        runCatching {
            val manager = context.packageManager
            manager.getApplicationLabel(manager.getApplicationInfo(app, 0)).toString()
        }.getOrElse { app.substringAfterLast('.').replaceFirstChar(Char::uppercase) }
    }
}
