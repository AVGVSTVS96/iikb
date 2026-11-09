package com.shahidy.iikb.app

import androidx.core.view.WindowCompat
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.platform.LocalView
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
import com.shahidy.iikb.Service
import com.shahidy.iikb.Services

/** Your extensions or sources, each opening its form, over Add Extension or Add Source (iOS's `ServicesPage`). */
@Composable
fun ServicesPage(kind: Services) {
    val context = LocalContext.current
    val saved = LocalStore.current.watch { kind.list(context) }
    var editing by remember { mutableStateOf<Service?>(null) }
    var adding by remember { mutableStateOf(false) }
    if (saved.isNotEmpty()) {
        Section("Your ${kind.noun}s") {
            saved.forEachIndexed { index, service ->
                if (index > 0) Divider()
                Row(
                    Modifier.clickable { editing = service }.row(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    RowText(service.name, host(service.url), Modifier.weight(1f))
                    Trailing("chevron.right")
                }
            }
        }
    }
    Section(footer = kind.about) { ActionRow("Add ${kind.noun}", "plus") { adding = true } }
    if (adding || editing != null) {
        ServiceForm(kind, editing, saved, close = {
            adding = false
            editing = null
        })
    }
}

private val Services.about get() = when (this) {
    Services.EXTENSIONS ->
        "An extension is a service you run whose chats open from the bar, to read them and write in them as you would in any field. iikb asks it for its chats and sends it what you write there, nothing else you type."
    Services.SOURCES ->
        "A source is a service you run that iikb tells what you type. Each one gets the app’s package name and the text of the field you’re typing in, never passwords, codes or incognito fields, and can answer with a hint above the keys. Tap a hint to hide it."
}

private fun host(url: String) = runCatching { java.net.URI(url).host }.getOrNull() ?: url

/** A service's name, address and token, checked before it's saved. */
@Composable
private fun ServiceForm(kind: Services, service: Service?, saved: List<Service>, close: () -> Unit) {
    val context = LocalContext.current
    val palette = palette()
    var name by remember { mutableStateOf(service?.name.orEmpty()) }
    var address by remember { mutableStateOf(service?.url ?: "https://") }
    var token by remember { mutableStateOf(service?.token.orEmpty()) }
    val trimmed = name.trim()
    val url = address.trim().takeIf(Service::reachable)
    val problem = when {
        trimmed.isEmpty() -> null
        saved.any { it.name == trimmed && it != service } -> "“$trimmed” is already one of your ${kind.noun.lowercase()}s."
        url == null && address.length > "https://".length -> "The address needs to start with https://."
        else -> null
    }
    val canSave = url != null && trimmed.isNotEmpty() && problem == null
    Dialog(close, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BackHandler(onBack = close)
        val view = LocalView.current
        val dark = isSystemInDarkTheme()
        SideEffect {
            (view.parent as? DialogWindowProvider)?.window?.let {
                WindowCompat.getInsetsController(it, view).isAppearanceLightStatusBars = !dark
            }
        }
        Box(Modifier.fillMaxSize()) {
            Page(
                if (service == null) "Add ${kind.noun}" else "Edit ${kind.noun}", onBack = close,
                actions = {
                    Text(
                        "Save", color = palette.accent.copy(alpha = if (canSave) 1f else 0.4f), fontSize = Type.body,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.cardPress {
                            if (!canSave || url == null) return@cardPress
                            val added = Service(trimmed, url, token.ifEmpty { null })
                            if (service == null) {
                                kind.add(context, added)
                            } else {
                                kind.save(context, saved.map { if (it == service) added else it })
                            }
                            close()
                        }.padding(horizontal = 12.dp, vertical = 10.dp),
                    )
                },
            ) {
                Section(footer = problem ?: "iikb sends the token with each request, so the ${kind.noun.lowercase()} can tell it’s you.") {
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
                if (service != null) {
                    Section {
                        ActionRow("Delete ${kind.noun}", destructive = true) {
                            kind.remove(context, service.name)
                            close()
                        }
                    }
                }
            }
        }
    }
}
