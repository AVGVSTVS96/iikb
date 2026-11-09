package com.shahidy.iikb.keyboard

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.shahidy.iikb.Service
import com.shahidy.iikb.Services
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Sends each source you added (docs/sources.md) the field you're typing in and keeps the hint it answers, as iOS's
 * `Sources` does: KeyboardCore's `SourceFeed` picks what goes (`Native.sources…`), each update is posted off the main
 * thread, and a source's next waits for its answer, so a slow one never holds up a tap.
 */
class Sources(private val context: Context, private val handle: Long, private val changed: () -> Unit) {
    private var services = emptyList<Service>()
    private val network = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    /** Counts each change to the list, so an answer for a source list that's gone is dropped. */
    private var generation = 0

    fun reload() {
        val services = Services.SOURCES.list(context)
        if (services == this.services) return
        this.services = services
        generation++
        Native.sourcesReset(handle, services.size)
    }

    fun observe(field: String, app: String?, byKeyboard: Boolean) {
        if (services.isEmpty()) return
        Native.sourcesObserve(
            handle, field.encodeToByteArray(), app?.encodeToByteArray(), byKeyboard, System.currentTimeMillis() / 1000.0,
        )
        services.indices.forEach(::send)
    }

    fun hint(field: String, app: String?): String? =
        if (services.isEmpty()) null else Native.sourcesHint(handle, field.encodeToByteArray(), app?.encodeToByteArray())?.decodeToString()

    /** Hides the hint until a source answers with a different one. */
    fun dismissHint() = Native.sourcesDismiss(handle)

    private fun send(index: Int) {
        val body = Native.sourcesNext(handle, index) ?: return
        val service = services[index]
        val sent = generation
        network.execute {
            val answer = post(service, body)
            main.post {
                if (sent != generation) return@post
                if (answer == null) {
                    Native.sourcesFailed(handle, index)
                } else {
                    Native.sourcesAnswered(handle, index, answer.hint?.encodeToByteArray())
                }
                changed()
                send(index)
            }
        }
    }

    private class Answer(val hint: String?)

    /** A 2xx with `{"hint": …}`, or nothing, is an answer; anything else, or no answer in 10 seconds, is unreachable. */
    private fun post(service: Service, body: ByteArray): Answer? = runCatching {
        val connection = (URL(service.url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000
            readTimeout = 10_000
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            service.token?.let { setRequestProperty("Authorization", "Bearer $it") }
        }
        connection.outputStream.use { it.write(body) }
        if (connection.responseCode !in 200..299) return null
        val text = connection.inputStream.use { it.readBytes().decodeToString() }
        if (text.isBlank()) return Answer(null)
        val hint = (Json.parseToJsonElement(text) as? JsonObject ?: return null)["hint"]
        Answer((hint as? JsonPrimitive)?.takeIf { it != JsonNull && it.isString }?.content)
    }.getOrNull()

    fun close() {
        generation++
        network.shutdownNow()
    }
}
