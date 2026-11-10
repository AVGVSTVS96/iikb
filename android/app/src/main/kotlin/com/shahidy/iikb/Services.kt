package com.shahidy.iikb

import android.content.Context
import android.net.Uri
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** A service you run, added in Settings or from its link: an extension or a source (iOS's `Extension` and `Source`). */
@Serializable
data class Service(val name: String, val url: String, val token: String? = null) {
    companion object {
        /** `https` anywhere, or `http` on your own network (`localhost`, `.local`), as iOS lets a keyboard reach. */
        fun reachable(url: String): Boolean {
            val uri = Uri.parse(url)
            val host = uri.host ?: return false
            return uri.scheme == "https" || uri.scheme == "http" && (host == "localhost" || host.endsWith(".local"))
        }
    }
}

/**
 * The services of one kind you added, kept in the settings under iOS's name for them, which the keyboard reads again
 * as it hears they changed: extensions, whose chats open from the menu (docs/extensions.md), and sources, told the field
 * you type in (docs/sources.md).
 */
enum class Services(val key: String, val noun: String, private val onePerAddress: Boolean) {
    /** One address serves one list of chats, so a second extension there would list them twice. */
    EXTENSIONS("extensions", "Extension", onePerAddress = true),
    SOURCES("sources", "Source", onePerAddress = false);

    private fun preferences(context: Context) = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    fun list(context: Context): List<Service> =
        preferences(context).getString(key, null)
            ?.let { runCatching { json.decodeFromString<List<Service>>(it) }.getOrNull() }.orEmpty()

    fun save(context: Context, services: List<Service>) =
        preferences(context).edit().putString(key, json.encodeToString(services)).apply()

    /** Adds one, in place of the one with its name, or for an extension the one at its address. */
    fun add(context: Context, service: Service) =
        save(
            context,
            list(context).filter { it.name != service.name && !(onePerAddress && it.url == service.url) } + service,
        )

    fun remove(context: Context, name: String) = save(context, list(context).filter { it.name != name })

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** `iikb://extension?name=…&url=…&token=…` or `iikb://source?…`, the link a service gives you to add it. */
        fun of(link: Uri): Pair<Services, Service>? {
            if (link.scheme != "iikb") return null
            val kind = entries.firstOrNull { it.noun.lowercase() == link.host } ?: return null
            val name = link.getQueryParameter("name")?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            val url = link.getQueryParameter("url")?.trim()?.takeIf(Service::reachable) ?: return null
            return kind to Service(name, url, link.getQueryParameter("token")?.takeIf { it.isNotEmpty() })
        }
    }
}
