package com.shahidy.iikb.keyboard

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shahidy.iikb.Service
import com.shahidy.iikb.Services
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.Future

/**
 * The chats of the extensions you added (docs/extensions.md), as iOS's `Chats` keeps them: every extension's list,
 * pinned first, and the open chat's messages, asked for again as soon as each answer comes, so the extension holds the
 * request until they change and a reply shows the moment it's written. It stops when the panel closes. Compose state.
 */
class Chats(private val context: Context) {
    data class Chat(val service: Service, val id: String, val name: String, val line: String?, val pinned: Boolean)

    @Serializable
    data class Message(val from: String, val text: String, val pending: Boolean? = null, val files: List<File>? = null) {
        val mine get() = from == "me"

        /** A file sent with the message, at `url` relative to the extension's address; a photo (`image/…`) shows as one. */
        @Serializable
        data class File(
            val name: String, val url: String, val type: String? = null, val width: Double? = null, val height: Double? = null,
        ) {
            val isImage get() = type?.startsWith("image/") == true
        }
    }

    var list by mutableStateOf(emptyList<Chat>())
        private set
    var open by mutableStateOf<Chat?>(null)
        private set
    var messages by mutableStateOf(emptyList<Message>())
        private set
    var loaded by mutableStateOf(false)
        private set
    var listed by mutableStateOf(false)
        private set
    var problem by mutableStateOf<String?>(null)
        private set
    var services = Services.EXTENSIONS.list(context)
        private set
    /** Something shown changed: the list, the open chat's messages, or what went wrong. */
    var changed: () -> Unit = {}

    /** Each chat's last answer, by its extension and id, so switching back to a chat shows it at once. */
    private val seen = mutableMapOf<String, List<Message>>()
    private val work = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private var listing: Future<*>? = null
    private var reading: Future<*>? = null
    /** Counts each start and pick, so an answer for one that's gone is dropped. */
    private var generation = 0

    fun reload() {
        services = Services.EXTENSIONS.list(context)
    }

    /** Every extension's chats, kept on show until the new list comes; then, `opening`, `kept` open again, or the first. */
    fun start(kept: String? = null, opening: Boolean = true) {
        stop()
        if (list.isEmpty()) listed = false
        val started = generation
        val services = services
        listing = work.submit {
            val unreachable = mutableListOf<String>()
            val all = services.flatMap { service -> list(service) ?: emptyList<Chat>().also { unreachable += service.name } }
            main.post {
                if (started != generation) return@post
                list = all.filter { it.pinned } + all.filter { !it.pinned }
                listed = true
                problem = if (unreachable.isEmpty()) null else "Can’t reach ${unreachable.joinToString(", ")}."
                if (opening) pick(list.firstOrNull { it.id == kept } ?: list.firstOrNull())
                changed()
            }
        }
    }

    fun pick(chat: Chat?) {
        reading?.cancel(true)
        generation++
        if (chat != open) {
            val last = chat?.let { seen[key(it)] }
            messages = last ?: emptyList()
            loaded = last != null
        }
        open = chat
        chat ?: return
        follow(chat, null, generation)
    }

    fun stop() {
        generation++
        listing?.cancel(true)
        reading?.cancel(true)
        listing = null
        reading = null
    }

    /** Sends `text` to the open chat, pending until the chat's next messages carry it; `failed` if it couldn't. */
    fun send(text: String, failed: () -> Unit) {
        val chat = open ?: return
        messages = messages + Message("me", text, pending = true)
        work.execute {
            val sent = post(chat, text)
            main.post {
                if (sent || open != chat) return@post
                messages = messages.filterNot { it.pending == true && it.text == text }
                problem = "Not sent: ${chat.service.name} didn’t answer."
                failed()
            }
        }
    }

    private fun follow(chat: Chat, version: String?, started: Int) {
        reading = work.submit {
            val read = read(chat, version)
            main.post {
                if (started != generation || open != chat) return@post
                if (read == null) {
                    problem = "Can’t reach ${chat.service.name}. Pick the chat to try again."
                    changed()
                    return@post
                }
                if (read.version != version || problem != null) {
                    messages = read.messages
                    seen[key(chat)] = read.messages
                    loaded = true
                    problem = null
                    changed()
                }
                follow(chat, read.version, started)
            }
        }
    }

    private fun key(chat: Chat) = chat.service.url + "\n" + chat.id

    /** Where the open chat's extension serves `file`: its address, or one under the extension's. */
    fun url(file: Message.File): String? {
        val service = open?.service ?: return null
        if (Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:").containsMatchIn(file.url)) return file.url
        return service.url.trimEnd('/') + "/" + file.url.trimStart('/')
    }

    /** The open chat's extension's token, which its files are fetched with. */
    val token get() = open?.service?.token

    /** A file's bytes from the open chat's extension, with its token, off the main thread; `done` on it. */
    fun fetch(url: String, done: (ByteArray?) -> Unit) {
        val service = open?.service ?: return done(null)
        work.execute {
            val bytes = runCatching {
                val connection = open(service, url)
                if (connection.responseCode in 200..299) connection.inputStream.use { it.readBytes() } else null
            }.getOrNull()
            main.post { done(bytes) }
        }
    }

    @Serializable
    private data class Listed(val chats: List<Item>) {
        @Serializable
        data class Item(val id: String, val name: String, val line: String? = null, val pinned: Boolean? = null)
    }

    @Serializable
    private data class Read(val version: String, val messages: List<Message>)

    private fun list(service: Service): List<Chat>? = get<Listed>(service, service.url)?.chats?.map {
        Chat(service, it.id, it.name, it.line, it.pinned == true)
    }

    private fun read(chat: Chat, after: String?): Read? {
        val url = address(chat) + (after?.let { "?after=" + URLEncoder.encode(it, "UTF-8") } ?: "")
        return get(chat.service, url)
    }

    private fun post(chat: Chat, text: String): Boolean = runCatching {
        val connection = open(chat.service, address(chat))
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        val body = buildJsonObject { put("text", text); put("id", UUID.randomUUID().toString()) }
        connection.outputStream.use { it.write(body.toString().encodeToByteArray()) }
        connection.responseCode in 200..299
    }.getOrDefault(false)

    private inline fun <reified Answer> get(service: Service, url: String): Answer? = runCatching {
        val connection = open(service, url)
        if (connection.responseCode !in 200..299) return null
        json.decodeFromString<Answer>(connection.inputStream.use { it.readBytes().decodeToString() })
    }.getOrNull()

    private fun address(chat: Chat) = chat.service.url.trimEnd('/') + "/" + URLEncoder.encode(chat.id, "UTF-8").replace("+", "%20")

    /** A read waits up to about 25 seconds for a change, so the timeout leaves it room. */
    private fun open(service: Service, url: String) = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = 10_000
        readTimeout = 40_000
        service.token?.let { setRequestProperty("Authorization", "Bearer $it") }
    }

    fun close() = work.shutdownNow()

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }
}
