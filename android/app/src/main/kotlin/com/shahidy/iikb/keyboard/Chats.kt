package com.shahidy.iikb.keyboard

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shahidy.iikb.Service
import com.shahidy.iikb.Services
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Base64
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.Future

/**
 * The chats of the extensions you added (docs/extensions.md), as iOS's `Chats` keeps them: every extension's list,
 * pinned first, and the open chat's messages, asked for again as soon as each answer comes, so the extension holds the
 * request until they change and a reply shows the moment it's written. It stops when the panel closes. What you send
 * is kept until its extension has it (`Unsent`), and goes again whenever the keyboard appears or an extension answers.
 * Compose state.
 */
class Chats(private val context: Context) {
    data class Chat(val service: Service, val id: String, val name: String, val line: String?, val pinned: Boolean) {
        fun holds(message: Unsent) = message.service == service.url && message.chat == id
    }

    /** A message you sent that its extension doesn't have yet, as iOS's `UnsentMessage`. */
    @Serializable
    data class Unsent(
        val service: String, val chat: String, val id: String, val text: String, val photos: List<ChatPhotos.Photo>? = null,
    ) {
        val where get() = service + "\n" + chat
    }

    @Serializable
    data class Message(
        val from: String, val text: String, val pending: Boolean? = null, val files: List<File>? = null,
        /** Pending, and its chat's last try to send failed. */
        val failed: Boolean? = null,
    ) {
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
    /** The open chat as its extension last gave it, then what you sent that the extension doesn't have yet. */
    val messages: List<Message>
        get() {
            val open = open ?: return emptyList()
            return said + unsent.filter(open::holds).map { pending(it, failed = it.where in stuck) }
        }
    private var said by mutableStateOf(emptyList<Message>())
    private val kept = java.io.File(context.noBackupFilesDir, "chat-unsent.json")
    private var unsent by mutableStateOf(load())
    /** The chats whose last send failed, so what waits in them shows as not sent. */
    private var stuck by mutableStateOf(emptySet<String>())
    /** Counts the open chat's answers, so a send knows whether one came while it was on its way. */
    private var answers = 0
    private var sending = false
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

    /** The open chat's last read failed, so nothing is asking for its messages. */
    private var dropped = false
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private var network: ConnectivityManager.NetworkCallback? = null

    fun reload() {
        services = Services.EXTENSIONS.list(context)
        deliver()
        again()
    }

    /** Reads the open chat again if its last read failed: the network changed, you sent, touched the chat or the keyboard appeared. */
    fun again() {
        if (dropped) pick(open)
    }

    /** The photos the messages still to send hold, which mustn't be cleared away. */
    val held get() = unsent.flatMap { it.photos.orEmpty() }.map { it.name }.toSet()

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
                deliver()
                if (opening) pick(list.firstOrNull { it.id == kept } ?: list.firstOrNull())
                changed()
            }
        }
    }

    fun pick(chat: Chat?) {
        reading?.cancel(true)
        generation++
        dropped = false
        if (chat != open) {
            val last = chat?.let { seen[key(it)] }
            said = last ?: emptyList()
            loaded = last != null
        }
        open = chat
        chat ?: return
        follow(chat, null, generation)
        if (network == null) {
            network = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    main.post(::again)
                }
            }.also(connectivity::registerDefaultNetworkCallback)
        }
    }

    fun stop() {
        generation++
        listing?.cancel(true)
        reading?.cancel(true)
        listing = null
        reading = null
        dropped = false
        network?.let(connectivity::unregisterNetworkCallback)
        network = null
    }

    /** Keeps `text` and `photos` for the open chat, shown as pending, and sends them. False with no chat open to keep them for. */
    fun send(text: String, photos: List<ChatPhotos.Photo>): Boolean {
        val chat = open ?: return false
        keep(unsent + Unsent(chat.service.url, chat.id, UUID.randomUUID().toString(), text, photos.ifEmpty { null }))
        deliver()
        again()
        return true
    }

    /** Yours on its way, its photos read from the keyboard's own copies. */
    private fun pending(message: Unsent, failed: Boolean = false) = Message(
        "me", message.text, pending = true,
        files = message.photos?.map {
            Message.File(it.name, it.file(context).toURI().toString(), "image/jpeg", it.width.toDouble(), it.height.toDouble())
        },
        failed = if (failed) true else null,
    )

    /**
     * Sends what's kept, oldest first, each to its chat's extension until the extension has it. A chat whose message
     * can't go waits for the next send, answer or keyboard, and the other chats' go on. One the open chat's next answer
     * hasn't shown yet stays in it as pending.
     */
    private fun deliver() {
        if (sending) return
        sending = true
        deliver(waiting = emptySet())
    }

    private fun deliver(waiting: Set<String>) {
        val next = unsent.firstOrNull { it.where !in waiting && service(it) != null }
        val service = next?.let(::service)
        if (next == null || service == null || work.isShutdown) {
            sending = false
            return
        }
        val answered = answers
        work.execute {
            val sent = post(service, next)
            main.post {
                if (!sent) {
                    stuck = stuck + next.where
                    problem = "Can’t reach ${service.name}. What you sent is kept and goes again."
                    changed()
                    return@post deliver(waiting + next.where)
                }
                stuck = stuck - next.where
                keep(unsent - next)
                if (open?.holds(next) == true && answers == answered) said = said + pending(next)
                changed()
                deliver(waiting)
            }
        }
    }

    private fun service(message: Unsent) = services.firstOrNull { it.url == message.service }

    private fun load(): List<Unsent> =
        runCatching { json.decodeFromString<List<Unsent>>(kept.readText()) }.getOrNull().orEmpty()

    /** Written beside, then moved over, so a keyboard killed mid-write keeps the file as it was. */
    private fun keep(messages: List<Unsent>) {
        unsent = messages
        val next = java.io.File(kept.parentFile, kept.name + ".next")
        next.writeText(json.encodeToString(messages))
        next.renameTo(kept)
    }

    /** A failed read says so and stops, until `again`. */
    private fun follow(chat: Chat, version: String?, started: Int) {
        reading = work.submit {
            val read = read(chat, version)
            main.post {
                if (started != generation || open != chat) return@post
                if (read == null) {
                    problem = "Can’t reach ${chat.service.name}. Tap the chat to try again."
                    dropped = true
                    changed()
                    return@post
                }
                if (read.version != version || problem != null) {
                    said = read.messages
                    seen[key(chat)] = read.messages
                    answers++
                    loaded = true
                    problem = null
                    changed()
                    deliver()
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

    /** A file's bytes from the open chat's extension, with its token, or a photo of yours on its way, off the main thread; `done` on it. */
    fun fetch(url: String, done: (ByteArray?) -> Unit) {
        val service = open?.service ?: return done(null)
        work.execute {
            val bytes = runCatching {
                if (url.startsWith("file:")) return@runCatching java.io.File(java.net.URI(url)).readBytes()
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

    /** The words and the photos' JPEGs, in base64; a photo whose copy is gone goes without, and one with nothing left counts as sent. */
    private fun post(service: Service, message: Unsent): Boolean = runCatching {
        val text = message.text
        val files = message.photos.orEmpty().mapNotNull { photo ->
            runCatching { photo.file(context).readBytes() }.getOrNull()?.let { jpeg ->
                buildJsonObject {
                    put("type", "image/jpeg")
                    put("data", Base64.getEncoder().encodeToString(jpeg))
                    put("width", photo.width)
                    put("height", photo.height)
                }
            }
        }
        if (text.isEmpty() && files.isEmpty()) return@runCatching true
        val connection = open(service, address(service, message.chat))
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        val body = buildJsonObject {
            put("text", text)
            put("id", message.id)
            if (files.isNotEmpty()) put("files", JsonArray(files))
        }
        connection.outputStream.use { it.write(body.toString().encodeToByteArray()) }
        connection.responseCode in 200..299
    }.getOrDefault(false)

    private inline fun <reified Answer> get(service: Service, url: String): Answer? = runCatching {
        val connection = open(service, url)
        if (connection.responseCode !in 200..299) return null
        json.decodeFromString<Answer>(connection.inputStream.use { it.readBytes().decodeToString() })
    }.getOrNull()

    private fun address(chat: Chat) = address(chat.service, chat.id)

    private fun address(service: Service, chat: String) =
        service.url.trimEnd('/') + "/" + URLEncoder.encode(chat, "UTF-8").replace("+", "%20")

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
