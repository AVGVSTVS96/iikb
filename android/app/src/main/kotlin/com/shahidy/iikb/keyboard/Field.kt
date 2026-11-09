package com.shahidy.iikb.keyboard

import android.inputmethodservice.InputMethodService
import android.os.Build
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection

/**
 * The app's field, as the engine reads and edits it (HostDocument.swift calls these by name). Counts are UTF-16, as
 * Android's are. What's around the caret is read once per edit and kept until the next one, so an event reads the
 * field over IPC once, however often the engine asks.
 */
class Field(private val service: InputMethodService) {
    private class Around(val before: String, val selected: String, val after: String, val start: Int?)

    private var around: Around? = null

    private val connection: InputConnection? get() = service.currentInputConnection

    /** The app may have changed the field: read it again next time. */
    fun forget() {
        around = null
    }

    private fun read(): Around? {
        around?.let { return it }
        val connection = connection ?: return null
        val read = if (Build.VERSION.SDK_INT >= 31) {
            connection.getSurroundingText(WINDOW, WINDOW, 0)?.let { s ->
                val text = s.text.toString()
                val start = s.selectionStart.coerceIn(0, text.length)
                val end = s.selectionEnd.coerceIn(start, text.length)
                Around(text.substring(0, start), text.substring(start, end), text.substring(end), s.offset.takeIf { it >= 0 }?.plus(start))
            }
        } else {
            null
        } ?: Around(
            connection.getTextBeforeCursor(WINDOW, 0)?.toString() ?: return null,
            connection.getSelectedText(0)?.toString() ?: "",
            connection.getTextAfterCursor(WINDOW, 0)?.toString() ?: "",
            null,
        )
        around = read
        return read
    }

    fun before(): ByteArray? = read()?.before?.encodeToByteArray()

    fun after(): ByteArray? = read()?.after?.encodeToByteArray()

    fun selected(): ByteArray? = read()?.selected?.encodeToByteArray()

    /** A return the app takes as its action (send, search, go) goes to it as that action, as Android's keyboards do. */
    fun insert(bytes: ByteArray) {
        val text = bytes.decodeToString()
        around = null
        if (text == "\n" && service.sendDefaultEditorAction(true)) return
        if (text == "\n") return service.sendKeyChar('\n')
        connection?.commitText(text, 1)
    }

    fun deleteSelection() {
        around = null
        connection?.commitText("", 1)
    }

    fun deleteBefore(units: Int) {
        around = null
        connection?.deleteSurroundingText(units, 0)
    }

    fun move(units: Int) {
        val connection = connection ?: return
        val start = read()?.start ?: connection.getExtractedText(ExtractedTextRequest(), 0)
            ?.let { it.startOffset + it.selectionEnd } ?: return
        around = null
        val at = (start + units).coerceAtLeast(0)
        connection.setSelection(at, at)
    }

    private companion object {
        const val WINDOW = 2000
    }
}
