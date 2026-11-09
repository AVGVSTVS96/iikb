package com.shahidy.iikb

import android.content.Context
import android.net.Uri
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** An extension you added (docs/extensions.md): a service whose chats open from the keyboard's menu. */
@Serializable
data class Extension(val name: String, val url: String, val token: String? = null) {
    companion object {
        /** `iikb://extension?name=…&url=…&token=…`, the link an extension gives you to add it. */
        fun of(link: Uri): Extension? {
            if (link.scheme != "iikb" || link.host != "extension") return null
            val name = link.getQueryParameter("name")?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            val url = link.getQueryParameter("url")?.trim()?.takeIf(::reachable) ?: return null
            return Extension(name, url, link.getQueryParameter("token")?.takeIf { it.isNotEmpty() })
        }

        /** `https` anywhere, or `http` on your own network (`localhost`, `.local`), as iOS lets a keyboard reach. */
        fun reachable(url: String): Boolean {
            val uri = Uri.parse(url)
            val host = uri.host ?: return false
            return uri.scheme == "https" || uri.scheme == "http" && (host == "localhost" || host.endsWith(".local"))
        }
    }
}

/** The extensions you added, kept in the app's settings, which the keyboard reads each time its menu opens. */
object Extensions {
    private val json = Json { ignoreUnknownKeys = true }

    private fun preferences(context: Context) = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    fun list(context: Context): List<Extension> =
        preferences(context).getString("extensions", null)
            ?.let { runCatching { json.decodeFromString<List<Extension>>(it) }.getOrNull() }.orEmpty()

    fun save(context: Context, extensions: List<Extension>) =
        preferences(context).edit().putString("extensions", json.encodeToString(extensions)).apply()

    /** Adds one, or replaces the one with its name. */
    fun add(context: Context, extension: Extension) =
        save(context, list(context).filter { it.name != extension.name } + extension)

    fun remove(context: Context, name: String) = save(context, list(context).filter { it.name != name })
}
