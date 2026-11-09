package com.shahidy.iikb.keyboard

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.UUID

/** A GIF as KeyboardCore's `Gif` is coded: KLIPY's slug, the small WebP the grid animates, the GIF that's sent. */
@Serializable
data class Gif(val id: String, val title: String, val preview: Media, val full: Media) {
    @Serializable
    data class Media(val url: String, val width: Int, val height: Int)
}

/**
 * GIFs from KLIPY's API (docs/design.md, "GIF"), as iOS's `Klipy` asks for them. Its key is `klipy.key`, an asset
 * copied from `Resources/Keys`, kept out of git; a build without it has no GIFs. Calls block: run them off the main
 * thread.
 */
class Klipy private constructor(private val key: String, private val customer: String) {
    @Serializable
    data class Request(val feed: String, val page: Int, val slugs: List<String>)

    /** A page of a feed's GIFs in KLIPY's order, and whether it has a page after it; null when the request failed. */
    fun gifs(request: Request): Pair<List<Gif>, Boolean>? {
        val (path, query) = when {
            request.feed == "recents" -> "gifs/items" to mapOf("slugs" to request.slugs.joinToString(","))
            request.feed.startsWith("search:") ->
                "gifs/search" to mapOf("q" to request.feed.removePrefix("search:"), "per_page" to "30", "page" to "${request.page}")
            else -> "gifs/trending" to mapOf("per_page" to "30", "page" to "${request.page}")
        }
        val body = runCatching {
            val connection = open(path, query + mapOf("customer_id" to customer, "format_filter" to "gif,webp"))
            connection.inputStream.use { it.readBytes().decodeToString() }.takeIf { connection.responseCode == 200 }
        }.getOrNull() ?: return null
        val page = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull() ?: return null
        if (page["result"]?.jsonPrimitive?.boolean != true) return null
        val data = page["data"]?.jsonObject ?: return null
        val gifs = data["data"]?.jsonArray.orEmpty().mapNotNull { runCatching { gif(it.jsonObject) }.getOrNull() }
        if (request.feed != "recents") return gifs to (data["has_next"]?.jsonPrimitive?.booleanOrNull == true)
        return request.slugs.mapNotNull { slug -> gifs.firstOrNull { base(it.id) == slug } } to false
    }

    /** Tells KLIPY a GIF was sent, with the search that found it. */
    fun shared(gif: Gif, search: String) {
        runCatching {
            val connection = open("gifs/share/${gif.id}", emptyMap())
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use {
                it.write(buildJsonObject { put("customer_id", customer); put("q", search) }.toString().encodeToByteArray())
            }
            connection.responseCode
        }
    }

    /** The GIF's file, downloaded into `directory`, or null when the download failed. */
    fun download(gif: Gif, directory: File): File? = runCatching {
        directory.mkdirs()
        val file = File(directory, fileName(gif))
        val connection = URL(gif.full.url).openConnection() as HttpURLConnection
        if (connection.responseCode != 200) return null
        connection.inputStream.use { input -> file.outputStream().use { input.copyTo(it) } }
        file
    }.getOrNull()

    private fun open(path: String, query: Map<String, String>): HttpURLConnection {
        val encoded = query.entries.sortedBy { it.key }
            .joinToString("&") { "${it.key}=${URLEncoder.encode(it.value, "UTF-8")}" }
        val url = "https://api.klipy.com/api/v1/$key/$path" + if (encoded.isEmpty()) "" else "?$encoded"
        return (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000
            readTimeout = 10_000
        }
    }

    /** The grid shows the small WebP; the clipboard gets the medium GIF. Ads and items missing either are left out. */
    private fun gif(item: JsonObject): Gif? {
        val type = item["type"]?.jsonPrimitive?.content
        if (type != null && type != "gif") return null
        val slug = item["slug"]?.jsonPrimitive?.content ?: return null
        val file = item["file"]?.jsonObject ?: return null
        fun media(size: String, format: String) = file[size]?.jsonObject?.get(format)?.jsonObject?.let {
            Gif.Media(it["url"]!!.jsonPrimitive.content, it["width"]!!.jsonPrimitive.int, it["height"]!!.jsonPrimitive.int)
        }
        val preview = media("sm", "webp") ?: media("sm", "gif") ?: return null
        val full = media("md", "gif") ?: media("hd", "gif") ?: return null
        return Gif(slug, item["title"]?.jsonPrimitive?.content ?: "", preview, full)
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun fileName(gif: Gif) = base(gif.id).replace(Regex("[^A-Za-z0-9_-]"), "") + ".gif"

        /** A slug without the suffix a search adds to it, as `gifs/items` answers with it, so a GIF is one recent. */
        fun base(slug: String) = slug.substringBefore("--")

        fun of(context: Context): Klipy? {
            val key = runCatching { context.assets.open("klipy.key").use { it.readBytes().decodeToString().trim() } }
                .getOrNull()?.takeIf { it.isNotEmpty() } ?: return null
            val preferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
            val customer = preferences.getString("klipyCustomer", null)
                ?: UUID.randomUUID().toString().also { preferences.edit().putString("klipyCustomer", it).apply() }
            return Klipy(key, customer)
        }
    }
}
