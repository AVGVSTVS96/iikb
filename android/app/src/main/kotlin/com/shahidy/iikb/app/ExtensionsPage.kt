package com.shahidy.iikb.app

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.shahidy.iikb.Extension
import com.shahidy.iikb.Extensions

/** Your extensions, each opening its form, over Add Extension (iOS's `ServicesPage<Extension>`). */
@Composable
fun ExtensionsPage() {
    val context = LocalContext.current
    val saved = LocalStore.current.watch { Extensions.list(context) }
    var editing by remember { mutableStateOf<Extension?>(null) }
    var adding by remember { mutableStateOf(false) }
    if (saved.isNotEmpty()) {
        Section("Your Extensions") {
            saved.forEachIndexed { index, extension ->
                if (index > 0) Divider()
                Row(
                    Modifier.clickable { editing = extension }.row(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    RowText(extension.name, host(extension.url), Modifier.weight(1f))
                    Trailing("chevron.right")
                }
            }
        }
    }
    Section(footer = ABOUT) { ActionRow("Add Extension", "plus") { adding = true } }
    if (adding || editing != null) {
        ExtensionForm(editing, saved, close = {
            adding = false
            editing = null
        })
    }
}

private const val ABOUT =
    "An extension is a service you run whose chats open from the bar, to read them and write in them as you would in any field. iikb asks it for its chats and sends it what you write there, nothing else you type."

private fun host(url: String) = runCatching { java.net.URI(url).host }.getOrNull() ?: url

/** An extension's name, address and token, checked before it's saved. */
@Composable
private fun ExtensionForm(extension: Extension?, saved: List<Extension>, close: () -> Unit) {
    val context = LocalContext.current
    val palette = palette()
    var name by remember { mutableStateOf(extension?.name.orEmpty()) }
    var address by remember { mutableStateOf(extension?.url ?: "https://") }
    var token by remember { mutableStateOf(extension?.token.orEmpty()) }
    val trimmed = name.trim()
    val url = address.trim().takeIf(Extension::reachable)
    val problem = when {
        trimmed.isEmpty() -> null
        saved.any { it.name == trimmed && it != extension } -> "“$trimmed” is already one of your extensions."
        url == null && address.length > "https://".length -> "The address needs to start with https://."
        else -> null
    }
    val canSave = url != null && trimmed.isNotEmpty() && problem == null
    Dialog(close, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BackHandler(onBack = close)
        Box(Modifier.fillMaxSize()) {
            Page(
                if (extension == null) "Add Extension" else "Edit Extension", onBack = close,
                actions = {
                    Text(
                        "Save", color = palette.accent.copy(alpha = if (canSave) 1f else 0.4f), fontSize = Type.body,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.cardPress {
                            if (!canSave || url == null) return@cardPress
                            val added = Extension(trimmed, url, token.ifEmpty { null })
                            if (extension == null) {
                                Extensions.add(context, added)
                            } else {
                                Extensions.save(context, saved.map { if (it == extension) added else it })
                            }
                            close()
                        }.padding(horizontal = 12.dp, vertical = 10.dp),
                    )
                },
            ) {
                Section(footer = problem ?: "iikb sends the token with each request, so the extension can tell it’s you.") {
                    FormField(name, "Name", KeyboardOptions(capitalization = KeyboardCapitalization.Words)) { name = it }
                    Divider()
                    FormField(
                        address, "https://", KeyboardOptions(keyboardType = KeyboardType.Uri, autoCorrectEnabled = false),
                    ) { address = it }
                    Divider()
                    FormField(
                        token, "Token (optional)", KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                        PasswordVisualTransformation(),
                    ) { token = it }
                }
                if (extension != null) {
                    Section {
                        ActionRow("Delete Extension", destructive = true) {
                            Extensions.remove(context, extension.name)
                            close()
                        }
                    }
                }
            }
        }
    }
}
