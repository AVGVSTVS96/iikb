package com.shahidy.iikb.app.stats

import com.shahidy.iikb.app.Hues
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import com.shahidy.iikb.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shahidy.iikb.app.Palette
import com.shahidy.iikb.app.design.Caption
import com.shahidy.iikb.app.design.ChoicePills
import com.shahidy.iikb.app.design.Format
import com.shahidy.iikb.app.design.Hairline
import com.shahidy.iikb.app.design.LegendDot
import com.shahidy.iikb.app.design.Split
import com.shahidy.iikb.app.design.Stat
import com.shahidy.iikb.app.design.StatCard
import com.shahidy.iikb.app.design.StatGrid
import com.shahidy.iikb.app.design.Tints
import com.shahidy.iikb.app.design.card
import com.shahidy.iikb.app.design.display
import com.shahidy.iikb.app.Symbols
import com.shahidy.iikb.app.palette
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle as DayStyle
import java.time.temporal.WeekFields
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Everything one device wrote, typed and said together, in typing's blue and dictation's pink: today, words or speed a
 * day over 7, 30 or 90 days, your records, the hours and speeds you write at, where your words went, the past year and
 * all of it.
 */
@Composable
fun Overview(activity: Activity, computer: String?) {
    Today(activity, computer)
    History(activity, listOf(Kind.TYPED, Kind.SAID))
    Records(activity)
    Rhythm(activity, listOf(Kind.TYPED, Kind.SAID))
    if (activity.speeds.isNotEmpty()) Speeds(activity.speeds)
    Talking(activity)
    Year(activity)
    AllTime(activity)
}

fun Kind.color(palette: Palette) = if (this == Kind.TYPED) Hues.blue.on(palette) else Hues.pink.on(palette)
val Kind.title get() = if (this == Kind.TYPED) "Typed" else "Dictated"

private val today get() = LocalDate.now()

/** Today's words, large, split typed and said, then today's typing speed, time, accuracy and keys. */
@Composable
private fun Today(activity: Activity, computer: String?) {
    val palette = palette()
    val typed = activity.channel(Kind.TYPED, today)
    val said = activity.channel(Kind.SAID, today)
    val words = typed.words + said.words
    val asOf = computer?.let { Computers.of(LocalContext.current).asOf[it] }
    StatCard(
        "calendar", Hues.orange.on(palette), "Today", today.format(DateTimeFormatter.ofPattern("EEEE, MMM d")),
        accessory = asOf?.let {
            {
                Text(
                    Format.ago(it), color = palette.secondary, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                    modifier = Modifier.clip(CircleShape).background(palette.pressed).padding(horizontal = 8.dp, vertical = 3.dp),
                )
            }
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(Format.count(words), style = display(52f), color = palette.label, maxLines = 1, modifier = Modifier.alignByBaseline())
                Text(
                    if (words == 1) "word" else "words", color = palette.secondary, fontSize = 20.sp,
                    fontWeight = FontWeight.Medium, modifier = Modifier.alignByBaseline(),
                )
            }
            Split(listOf(Kind.TYPED.color(palette) to typed.words.toDouble(), Kind.SAID.color(palette) to said.words.toDouble()))
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                LegendDot(Kind.TYPED.color(palette), "Typed ${Format.count(typed.words)}")
                LegendDot(Kind.SAID.color(palette), "Dictated ${Format.count(said.words)}")
            }
        }
        Hairline()
        val speed = if (typed.seconds >= 10) typed.paced / typed.seconds * 60 else null
        StatGrid(
            facts = listOf(
                { Stat("Typing speed", Format.speed(speed), if (speed == null) null else "wpm") },
                { Stat("Active time", Format.time(typed.seconds + said.seconds)) },
                {
                    Stat(
                        "Accuracy",
                        if (typed.keys > 0) Format.percent(1 - typed.deletes.toDouble() / typed.keys) else "–",
                        detail = if (typed.keys > 0) "${Format.count(typed.deletes)} deleted" else null,
                    )
                },
                { Stat("Keystrokes", Format.count(typed.keys)) },
            ),
        )
    }
}

private enum class Measure(val title: String) { WORDS("Words"), SPEED("Speed") }

/** Words a day, typed and said stacked, or each one's speed a day, over 7, 30 or 90 days; a day picked shows its own. */
@Composable
fun History(activity: Activity, kinds: List<Kind>) {
    val palette = palette()
    var measure by remember { mutableStateOf(Measure.WORDS) }
    var span by remember { mutableIntStateOf(30) }
    var picked by remember(span) { mutableStateOf<Int?>(null) }
    val dates = (span - 1 downTo 0).map { today.minusDays(it.toLong()) }
    fun total(dates: List<LocalDate>) =
        dates.fold(Channel()) { sum, date -> kinds.fold(sum) { all, kind -> all + activity.channel(kind, date) } }
    fun speed(channel: Channel) = if (channel.seconds >= 60) channel.paced / channel.seconds * 60 else null
    val values = dates.map { date ->
        kinds.map { kind ->
            val channel = activity.channel(kind, date)
            when (measure) {
                Measure.WORDS -> channel.words.toDouble()
                Measure.SPEED -> if (channel.seconds >= 30) channel.paced / channel.seconds * 60 else null
            }
        }
    }
    val top = Format.roundUp(
        when (measure) {
            Measure.WORDS -> values.maxOfOrNull { column -> column.sumOf { it ?: 0.0 } } ?: 0.0
            Measure.SPEED -> values.flatten().filterNotNull().maxOrNull() ?: 0.0
        },
    )
    val noun = when (kinds) {
        listOf(Kind.SAID) -> "said"
        listOf(Kind.TYPED) -> "typed"
        else -> "written"
    }
    StatCard(
        "chart.bar.fill", Hues.indigo.on(palette), "History",
        if (measure == Measure.WORDS) "Words $noun per day" else "Words a minute per day",
        accessory = {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ChoicePills(Measure.entries, measure, { it.title }) { measure = it }
                ChoicePills(listOf(7, 30, 90), span, { "${it}D" }) { span = it }
            }
        },
    ) {
        Box(Modifier.heightIn(min = 58.dp)) {
            val day = picked
            if (day != null) {
                val date = dates[day]
                StatGrid(
                    3,
                    listOf<@Composable () -> Unit>({
                        Stat(
                            date.format(DateTimeFormatter.ofPattern("EEE, MMM d")),
                            Format.short(kinds.sumOf { activity.channel(it, date).words }), "words",
                        )
                    }) + kinds.map { kind ->
                        {
                            val channel = activity.channel(kind, date)
                            Stat(
                                kind.title, Format.short(channel.words),
                                detail = speed(channel)?.let { "${it.roundToInt()} wpm" }, detailColor = kind.color(palette),
                            )
                        }
                    },
                )
            } else {
                val now = total(dates)
                val before = total(dates.map { it.minusDays(span.toLong()) })
                val active = dates.count { date -> kinds.any { activity.channel(it, date).words > 0 } }
                val words = Format.change(now.words.toDouble(), before.words.toDouble())
                val pace = speed(now)?.let { a -> speed(before)?.let { Format.change(a, it) } }
                val up = Hues.green.on(palette)
                val down = Hues.orange.on(palette)
                StatGrid(
                    facts = listOf(
                        {
                            Stat(
                                "Words · ${span}d", Format.short(now.words), detailColor = words?.let { if (it.up) up else down },
                                trend = words,
                            )
                        },
                        { Stat("Per active day", Format.short(if (active > 0) now.words / active else 0)) },
                        {
                            Stat(
                                if (kinds.size > 1) "Overall speed" else "Speed", Format.speed(speed(now)), "wpm",
                                detailColor = pace?.let { if (it.up) up else down }, trend = pace,
                            )
                        },
                        { Stat("Active days", "$active", "of $span") },
                    ),
                )
            }
        }
        val ticks = when (span) {
            7 -> dates.mapIndexed { index, date -> Tick(index, date.dayOfWeek.getDisplayName(DayStyle.NARROW, Locale.getDefault()), true) }
            30 -> dates.indices.filter { (dates.lastIndex - it) % 7 == 0 }.map { Tick(it, Format.day(dates[it])) }
            else -> dates.indices.filter { (dates.lastIndex - it) % 30 == 0 }.map { Tick(it, Format.day(dates[it])) }
        }
        ColumnChart(
            values, kinds.map { Tints.gradient(it.color(palette)) }, top, 170.dp, ticks,
            ratio = if (span > 30) 0.8f else 0.66f, radius = if (span > 30) 1.5.dp else 3.dp,
            lines = measure == Measure.SPEED, lineColors = kinds.map { it.color(palette) },
            picked = picked, onPick = { picked = it },
        )
        if (kinds.size > 1) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) { kinds.forEach { LegendDot(it.color(palette), it.title) } }
        }
    }
}

/** Your streak, the day you wrote most, your fastest day and your fastest stretch, two to a row. */
@Composable
private fun Records(activity: Activity) {
    val palette = palette()
    val (current, longest) = streaks(activity)
    val most = activity.days.maxByOrNull { it.value.typed.words + it.value.said.words }
    val fastest = activity.days.mapNotNull { (date, day) ->
        if (day.typed.seconds >= 120) day.typed.speed?.let { date to it } else null
    }.maxByOrNull { it.second }
    val burst = activity.days.map { it.key to it.value.typed.peak }.maxByOrNull { it.second }
    val records = listOf(
        Record("flame.fill", Hues.orange.on(palette), "Streak", "$current", if (current == 1) "day" else "days", "Longest $longest ${if (longest == 1) "day" else "days"}"),
        Record(
            "trophy.fill", Hues.yellow.on(palette), "Most words",
            Format.short(most?.let { it.value.typed.words + it.value.said.words } ?: 0), "words",
            most?.let { Format.day(it.key) } ?: "–",
        ),
        Record(
            "gauge.with.dots.needle.67percent", Hues.green.on(palette), "Fastest day", Format.speed(fastest?.second), "wpm",
            fastest?.let { Format.day(it.first) } ?: "Two minutes of typing a day",
        ),
        Record(
            "bolt.fill", Hues.purple.on(palette), "Top burst",
            Format.speed(burst?.second?.takeIf { it > 0 }), "wpm",
            burst?.takeIf { it.second > 0 }?.let { Format.day(it.first) } ?: "–",
        ),
    )
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val across = if (maxWidth >= 150.dp * 4 + 36.dp) 4 else 2
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            records.chunked(across).forEach { row ->
                Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { Box(Modifier.weight(1f).fillMaxHeight()) { RecordTile(it) } }
                }
            }
        }
    }
}

/** Days in a row with words, up to today (or yesterday, while today has none yet), and the most ever. */
private fun streaks(activity: Activity): Pair<Int, Int> {
    val days = activity.activeDays.toSet()
    var longest = 0
    var run = 0
    var previous: LocalDate? = null
    for (day in days.sorted()) {
        run = if (previous?.plusDays(1) == day) run + 1 else 1
        longest = maxOf(longest, run)
        previous = day
    }
    var current = 0
    var day = today
    if (day !in days) day = day.minusDays(1)
    while (day in days) {
        current++
        day = day.minusDays(1)
    }
    return current to longest
}

private class Record(
    val symbol: String, val color: Color, val title: String, val value: String, val unit: String, val detail: String,
)

@Composable
private fun RecordTile(record: Record) {
    val palette = palette()
    val glow = record.color.copy(alpha = 0.2f)
    Box(
        Modifier.fillMaxSize().card(palette).drawBehind {
            val center = Offset(20.dp.toPx(), 10.dp.toPx())
            drawCircle(Brush.radialGradient(listOf(glow, Color.Transparent), center, 80.dp.toPx()), 80.dp.toPx(), center)
        },
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(
                    Modifier.size(26.dp).background(record.color.copy(alpha = 0.18f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Symbols[record.symbol], null, tint = record.color, modifier = Modifier.size(17.7.dp))
                }
                Text(record.title, color = palette.label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(record.value, style = display(30f), color = palette.label, maxLines = 1, modifier = Modifier.alignByBaseline())
                    Text(
                        record.unit, color = palette.secondary, fontSize = 13.sp, fontWeight = FontWeight.Medium,
                        modifier = Modifier.alignByBaseline(),
                    )
                }
                Text(record.detail, color = palette.secondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** The hours of the day you write in, typed and said stacked, in words. */
@Composable
fun Rhythm(activity: Activity, kinds: List<Kind>) {
    val palette = palette()
    val hours = (0 until 24).map { hour -> kinds.map { activity.total(it).hours[hour] / 5 } }
    val sums = hours.map { it.sum() }
    val busiest = sums.indices.maxByOrNull { sums[it] } ?: return
    if (sums[busiest] <= 0) return
    StatCard("clock.fill", Hues.teal.on(palette), "Daily rhythm", "Most active around ${Format.hour(busiest)}") {
        ColumnChart(
            hours, kinds.map { Tints.gradient(it.color(palette)) }, Format.roundUp(sums[busiest]), 140.dp,
            listOf(0, 6, 12, 18).map { Tick(it, Format.hour(it)) }, ratio = 0.72f, radius = 2.dp,
        )
        if (kinds.size > 1) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) { kinds.forEach { LegendDot(it.color(palette), it.title) } }
        }
    }
}

/** How often you type at each speed, a column per 5 wpm, the usual span in color and the rest gray. */
@Composable
fun Speeds(speeds: Map<Int, Double>) {
    val palette = palette()
    val bands = speeds.toSortedMap().toList()
    fun percentile(share: Double): Int {
        val total = bands.sumOf { it.second }
        var seen = 0.0
        for ((speed, count) in bands) {
            seen += count
            if (seen >= total * share) return speed + 2
        }
        return bands.lastOrNull()?.first ?: 0
    }
    val low = percentile(0.1) / 5 * 5
    val high = (percentile(0.9) + 4) / 5 * 5
    val median = percentile(0.5)
    val usual = Brush.verticalGradient(listOf(Hues.cyan.on(palette), Hues.blue.on(palette), Hues.indigo.on(palette)))
    val other = Brush.verticalGradient(listOf(palette.secondary.copy(alpha = 0.5f), palette.secondary.copy(alpha = 0.5f)))
    StatCard("speedometer", Hues.blue.on(palette), "Speed range", "Usually $low–$high wpm · median ~$median wpm") {
        ColumnChart(
            bands.map { (speed, count) -> if (speed in low..high) listOf(count, null) else listOf(null, count) },
            listOf(usual, other), bands.maxOf { it.second }, 130.dp,
            bands.mapIndexedNotNull { index, (speed, _) -> if (speed % 20 == 0) Tick(index, "$speed", true) else null },
            ratio = 0.78f, radius = 2.dp, yLabel = null,
        )
        Caption("Words a minute, each column a stretch of typing")
    }
}

/** Every word dictated, its share of all you've written, how fast you talk, and the apps your words went into. */
@Composable
private fun Talking(activity: Activity) {
    val palette = palette()
    val said = activity.total(Kind.SAID)
    val typed = activity.total(Kind.TYPED)
    val all = said.words + typed.words
    if (all == 0) return
    val apps = buildMap<String, Pair<Int, Int>> {
        activity.apps[Kind.TYPED].orEmpty().forEach { (name, words) -> merge(name, words to 0) { a, b -> a.first + b.first to a.second + b.second } }
        activity.apps[Kind.SAID].orEmpty().forEach { (name, words) -> merge(name, 0 to words) { a, b -> a.first + b.first to a.second + b.second } }
    }.toList().sortedByDescending { it.second.first + it.second.second }.take(5)
    StatCard("waveform", Hues.pink.on(palette), "Dictation", "All time") {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(Format.count(said.words), style = display(40f), color = palette.label, maxLines = 1, modifier = Modifier.alignByBaseline())
                Text(
                    "words dictated", color = palette.secondary, fontSize = 15.sp, fontWeight = FontWeight.Medium,
                    modifier = Modifier.alignByBaseline(),
                )
            }
            Split(listOf(Kind.SAID.color(palette) to said.words.toDouble(), Kind.TYPED.color(palette) to typed.words.toDouble()))
            Caption("${Format.percent(said.words.toDouble() / all)} of everything you’ve written")
        }
        StatGrid(
            3,
            listOf(
                {
                    Stat(
                        "Speaking", Format.speed(said.speed), "wpm",
                        said.speed?.let { s -> typed.speed?.let { "%.1f× your typing".format(s / it) } }, Hues.pink.on(palette),
                    )
                },
                { Stat("Dictations", Format.count(said.dictations)) },
                { Stat("Avg length", if (said.dictations > 0) "${said.words / said.dictations}" else "–", "words") },
            ),
        )
        if (apps.isNotEmpty()) {
            Hairline()
            Text("By app", color = palette.secondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            val top = (apps.first().second.first + apps.first().second.second).coerceAtLeast(1)
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                apps.forEach { (name, words) ->
                    val (typedWords, saidWords) = words
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row {
                            Text(name, color = palette.label, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1, modifier = Modifier.weight(1f))
                            Text("${Format.count(typedWords + saidWords)} words", color = palette.secondary, fontSize = 13.sp)
                        }
                        BoxWithConstraints(Modifier.fillMaxWidth()) {
                            Split(
                                listOf(Kind.TYPED.color(palette) to typedWords.toDouble(), Kind.SAID.color(palette) to saidWords.toDouble()),
                                6.dp, Modifier.width(maxOf(maxWidth * ((typedWords + saidWords).toFloat() / top), 6.dp)),
                            )
                        }
                    }
                }
            }
            if (apps.any { it.second.first > 0 }) {
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Kind.entries.forEach { LegendDot(it.color(palette), it.title) }
                }
            }
        }
    }
}

/** A square a day for as many weeks back as fit, up to a year, brighter the more you wrote, bluer typed, pinker said. */
@Composable
fun Year(activity: Activity, kinds: List<Kind> = listOf(Kind.TYPED, Kind.SAID)) {
    val palette = palette()
    val measurer = rememberTextMeasurer()
    val levels = listOf(0f, 0.3f, 0.5f, 0.75f, 1f)
    fun words(date: LocalDate) =
        (if (Kind.TYPED in kinds) activity.channel(Kind.TYPED, date).words else 0) to
            (if (Kind.SAID in kinds) activity.channel(Kind.SAID, date).words else 0)
    fun shade(level: Int, said: Float): Color {
        if (level == 0) return palette.pressed
        val color = when (kinds) {
            listOf(Kind.SAID) -> Kind.SAID.color(palette)
            listOf(Kind.TYPED) -> Kind.TYPED.color(palette)
            else -> lerp(Kind.TYPED.color(palette), Kind.SAID.color(palette), said)
        }
        return color.copy(alpha = levels[level])
    }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val cell = 10.dp
        val gap = 3.dp
        val left = 26.dp
        val inner = maxWidth - 36.dp
        val weeks = ((inner - left + gap) / (cell + gap)).toInt().coerceIn(1, 53)
        val since = today.minusDays(weeks * 7L)
        val active = activity.days.count { (date, _) -> date > since && words(date).let { it.first + it.second } > 0 }
        val months = (weeks / 4.35).roundToInt()
        StatCard(
            "square.grid.3x3.fill", Hues.green.on(palette), if (weeks >= 52) "Past year" else "Past $months months",
            "$active active ${if (active == 1) "day" else "days"} · shaded by words written",
        ) {
            val label = TextStyle(color = palette.secondary, fontSize = 9.sp, fontWeight = FontWeight.Medium)
            val first = WeekFields.of(Locale.getDefault()).firstDayOfWeek
            val weekday = ((today.dayOfWeek.value - first.value) + 7) % 7
            val start = today.minusDays((weeks - 1) * 7L + weekday)
            val totals = (0 until weeks * 7).map { words(start.plusDays(it.toLong())).let { w -> w.first + w.second } }
                .filter { it > 0 }.sorted()
            fun level(value: Int): Int {
                if (value <= 0 || totals.isEmpty()) return 0
                val rank = (totals.indexOfFirst { it >= value }.takeIf { it >= 0 } ?: totals.lastIndex).toDouble() /
                    (totals.size - 1).coerceAtLeast(1)
                return minOf(4, 1 + (rank * 4).toInt())
            }
            Canvas(Modifier.fillMaxWidth().height(cell * 7 + gap * 6 + 18.dp)) {
                val top = 16.dp.toPx()
                val c = cell.toPx()
                val g = gap.toPx()
                for (row in listOf(1, 3, 5)) {
                    val name = first.plus(row.toLong()).getDisplayName(DayStyle.SHORT, Locale.getDefault())
                    text(measurer, name, label, Offset(0f, top + row * (c + g) + c / 2), centerY = true)
                }
                var lastMonth = -1
                for (week in 0 until weeks) {
                    val x = left.toPx() + week * (c + g)
                    val firstDay = start.plusDays(week * 7L)
                    if (firstDay.monthValue != lastMonth) {
                        if (lastMonth != -1 || firstDay.dayOfMonth <= 7) {
                            val name = firstDay.month.getDisplayName(DayStyle.SHORT, Locale.getDefault())
                            text(measurer, name, label, Offset(x, 0f), fit = size.width)
                        }
                        lastMonth = firstDay.monthValue
                    }
                    for (day in 0 until 7) {
                        val date = start.plusDays(week * 7L + day)
                        if (date > today) continue
                        val (t, s) = words(date)
                        val total = t + s
                        val y = top + day * (c + g)
                        square(shade(level(total), if (total > 0) s.toFloat() / total else 0f), Offset(x, y), c, 2.5.dp.toPx())
                        if (date == today) {
                            drawRoundRect(
                                palette.label.copy(alpha = 0.7f), Offset(x - 1.dp.toPx(), y - 1.dp.toPx()),
                                androidx.compose.ui.geometry.Size(c + 2.dp.toPx(), c + 2.dp.toPx()),
                                CornerRadius(3.5.dp.toPx()), style = Stroke(1.dp.toPx()),
                            )
                        }
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (kinds.size > 1) {
                    LegendDot(Kind.TYPED.color(palette), "Typed")
                    LegendDot(Kind.SAID.color(palette), "Dictated")
                }
                Spacer(Modifier.weight(1f))
                Text("Less", color = palette.secondary, fontSize = 12.sp)
                (0 until 5).forEach { level ->
                    Box(
                        Modifier.size(10.dp).clip(RoundedCornerShape(2.5.dp)).background(
                            if (level == 0) {
                                Brush.linearGradient(listOf(palette.pressed, palette.pressed))
                            } else {
                                Brush.linearGradient(kinds.map { it.color(palette).copy(alpha = levels[level]) }.let { if (it.size == 1) it + it else it })
                            },
                        ),
                    )
                }
                Text("More", color = palette.secondary, fontSize = 12.sp)
            }
        }
    }
}

/** Everything since the first day counted. */
@Composable
private fun AllTime(activity: Activity) {
    val palette = palette()
    val typed = activity.total(Kind.TYPED)
    val said = activity.total(Kind.SAID)
    val first = activity.activeDays.firstOrNull() ?: return
    StatCard("infinity", Hues.gray.on(palette), "All time", "Since ${first.format(DateTimeFormatter.ofPattern("MMM d, yyyy"))}") {
        StatGrid(
            3,
            listOf(
                { Stat("Words", Format.short(typed.words + said.words)) },
                { Stat("Typed", Format.short(typed.words), detail = typed.speed?.let { "${it.roundToInt()} wpm" }, detailColor = Kind.TYPED.color(palette)) },
                { Stat("Dictated", Format.short(said.words), detail = said.speed?.let { "${it.roundToInt()} wpm" }, detailColor = Kind.SAID.color(palette)) },
                { Stat("Active time", Format.time(typed.seconds + said.seconds)) },
                { Stat("Keystrokes", Format.short(typed.keys)) },
                { Stat("Active days", "${activity.activeDays.size}") },
            ),
        )
    }
}
