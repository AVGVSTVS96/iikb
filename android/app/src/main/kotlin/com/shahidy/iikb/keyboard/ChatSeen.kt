package com.shahidy.iikb.keyboard

import android.content.Context
import kotlinx.serialization.json.Json
import java.io.File

/**
 * What this keyboard last showed of each chat, as iOS's `ChatSeen` keeps it, so a chat whose latest line in the list is
 * newer is marked new until you open it. It counts only what the keyboard showed: a message read elsewhere still marks
 * its chat. A chat seen for the first time is taken as read, so nothing is marked new the first time Chats opens.
 */
class ChatSeen(context: Context) {
    private val file = File(context.filesDir, "chat-seen.json")
    private var seen: Map<String, List<String>> =
        runCatching { Json.decodeFromString<Map<String, List<String>>>(file.readText()) }.getOrDefault(emptyMap())

    /** The open chat taken as seen, and the indices in the list of the chats with something newer. */
    fun update(chats: Chats): Set<Int> {
        if (!chats.listed) return emptySet()
        val next = seen.toMutableMap()
        for (chat in chats.list) if (chat.id !in next) next[chat.id] = listOf(chat.line ?: "")
        val open = chats.open
        if (open != null && chats.loaded) next[open.id] = listOf(open.line ?: "", chats.messages.lastOrNull()?.text ?: "")
        if (next != seen) {
            seen = next
            runCatching {
                val written = File(file.parentFile, file.name + ".next")
                written.writeText(Json.encodeToString(next))
                written.renameTo(file)
            }
        }
        return chats.list.indices.filter { index ->
            val chat = chats.list[index]
            val line = (chat.line ?: "").trim('…')
            chat != open && seen[chat.id].orEmpty().none { it == line || it.startsWith(line) }
        }.toSet()
    }
}
