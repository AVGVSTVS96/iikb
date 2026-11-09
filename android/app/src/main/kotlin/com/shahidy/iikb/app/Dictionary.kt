package com.shahidy.iikb.app

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import com.shahidy.iikb.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.shahidy.iikb.Vocabulary

/** The words the voice model gets wrong, each with what it writes instead, under Add Word, in alphabetical order. */
@Composable
fun Dictionary() {
    val terms = Vocabulary.terms()
    var editing by remember { mutableStateOf<Int?>(null) }
    val words = terms.withIndex().sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.value.term })
    Section(
        footer = "iikb types each word as you spell it here, in place of what the voice model wrote, or of the same word with other spaces, hyphens or capitals. Only whole words change.",
    ) { ActionRow("Add Word", "plus") { editing = NEW } }
    if (words.isNotEmpty()) {
        Section(if (words.size == 1) "1 Word" else "${words.size} Words") {
            words.forEachIndexed { row, (index, term) ->
                if (row > 0) Divider()
                WordRow(term, { editing = index }) { Vocabulary.set(terms.filterIndexed { at, _ -> at != index }) }
            }
        }
    }
    editing?.let { index ->
        TermEditor(terms.getOrNull(index), close = { editing = null }, save = { term ->
            Vocabulary.set(if (index == NEW) terms + term else terms.mapIndexed { at, old -> if (at == index) term else old })
        }) { Vocabulary.set(terms.filterIndexed { at, _ -> at != index }) }
    }
}

private const val NEW = -1

/** Words as the model writes them: no capitals or corrections of the keyboard's own. */
private val PLAIN = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false)

/** A word and what it's written as, opening its form; holding it offers Delete. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun WordRow(term: Vocabulary.Term, open: () -> Unit, delete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.combinedClickable(onClick = open, onLongClick = { menu = true }).row(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RowText(
                term.term, term.heardAs.takeIf { it.isNotEmpty() }?.let { "Written as " + it.joinToString(", ") },
                Modifier.weight(1f),
            )
            Trailing("chevron.right")
        }
        DropdownMenu(menu, { menu = false }, containerColor = palette().card) {
            DropdownMenuItem(
                text = { Text("Delete", color = palette().red, fontSize = Type.body) },
                onClick = {
                    menu = false
                    delete()
                },
            )
        }
    }
}

/** A word and what the voice model writes for it, in a sheet like Add Source's, with Cancel and Save. */
@Composable
private fun TermEditor(term: Vocabulary.Term?, close: () -> Unit, save: (Vocabulary.Term) -> Unit, delete: () -> Unit) {
    var word by remember { mutableStateOf(term?.term.orEmpty()) }
    var heardAs by remember { mutableStateOf(term?.heardAs.orEmpty().joinToString(", ")) }
    Sheet(
        if (term == null) "Add Word" else "Edit Word", "Save", word.isNotBlank(), close,
        confirm = {
            save(Vocabulary.Term(word.trim(), heardAs.split(",").map { it.trim() }.filter { it.isNotEmpty() }))
            close()
        },
    ) {
        Section("Word", "Spelled and capitalized as iikb should type it.") {
            FormField(word, "Claude", PLAIN) { word = it }
        }
        Section(
            "Written Instead",
            "What the voice model writes when you say it, separated by commas. Leave it empty to fix only spaces, hyphens and capitals.",
        ) { FormField(heardAs, "clawed, clod", PLAIN) { heardAs = it } }
        if (term != null) {
            Section {
                ActionRow("Delete Word", destructive = true) {
                    delete()
                    close()
                }
            }
        }
    }
}
