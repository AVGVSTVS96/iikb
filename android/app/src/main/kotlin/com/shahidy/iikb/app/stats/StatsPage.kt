package com.shahidy.iikb.app.stats

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.shahidy.iikb.Transcript
import com.shahidy.iikb.Transcripts
import com.shahidy.iikb.TypingStats
import com.shahidy.iikb.app.LocalResumes
import com.shahidy.iikb.app.Page
import com.shahidy.iikb.app.design.SectionPills
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class StatsSection(val title: String) { OVERVIEW("Overview"), TYPING("Typing"), DICTATION("Dictation"), TAPS("Taps") }

/** How you type and talk, and where your taps land: Overview, Typing, Dictation and Taps as pills under the title. */
@Composable
fun StatsPage(section: StatsSection, pick: (StatsSection) -> Unit) {
    val (activity, transcripts) = phoneActivity()
    Page("Stats", pinned = { SectionPills(StatsSection.entries, section, { it.title }, pick) }) {
        Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            when (section) {
                StatsSection.OVERVIEW -> Overview(activity)
                StatsSection.TYPING -> DeviceStats(Kind.TYPED, activity, transcripts)
                StatsSection.DICTATION -> DeviceStats(Kind.SAID, activity, transcripts)
                StatsSection.TAPS -> Taps()
            }
        }
    }
}

/**
 * The phone's typing, from the hours the keyboard keeps as it closes, and its dictation, from Transcripts: read again
 * each time either changes and each time the app comes forward.
 */
@Composable
fun phoneActivity(): Pair<Activity, List<Transcript>> {
    val context = LocalContext.current
    val resumes = LocalResumes.current
    val names = remember { AppNames(context) }
    var changes by remember { mutableIntStateOf(0) }
    var shown by remember { mutableStateOf(Activity() to Transcripts.list()) }
    DisposableEffect(Unit) {
        val typing = TypingStats.listen { changes++ }
        val transcripts = Transcripts.listen { changes++ }
        onDispose {
            typing()
            transcripts()
        }
    }
    LaunchedEffect(resumes, changes) {
        val transcripts = Transcripts.list()
        shown = withContext(Dispatchers.Default) { Activity.of(TypingStats.hours(), transcripts, names::of) } to transcripts
    }
    return shown
}
