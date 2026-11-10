package com.shahidy.iikb.app

import android.content.Context
import com.shahidy.iikb.Settings
import com.shahidy.iikb.folds
import com.shahidy.iikb.keyboard.Native
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

/** What the app's pages ask iikb's engine (android/Sources/KeyboardAndroid/App.swift). */
object Core {
    init {
        Native
    }

    /** A keyboard of its own for the Keyboard pages' preview, driven through `Native` by its handle. */
    fun preview(context: Context): Long =
        preview(PreviewField(), mapped(context, "en.lexicon"), mapped(context, "en.network"))

    @JvmStatic private external fun preview(field: PreviewField, lexicon: ByteBuffer, network: ByteBuffer): Long

    @JvmStatic private external fun typed(said: ByteArray, settings: ByteArray, lexicon: ByteBuffer?): ByteArray
    @JvmStatic private external fun keysHere(width: Double, height: Double, folds: Boolean): ByteArray
    @JvmStatic private external fun taps(memory: ByteArray): Int

    /** The model files, mapped once and kept for as long as the app runs, since the engine reads them in place. */
    private val mapped = mutableMapOf<String, ByteBuffer>()

    private fun mapped(context: Context, name: String): ByteBuffer = mapped.getOrPut(name) {
        context.assets.openFd(name).use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).channel.use {
                it.map(FileChannel.MapMode.READ_ONLY, descriptor.startOffset, descriptor.length)
            }
        }
    }

    /** `said` as a dictation types it with the settings `lines` (`Settings.lines`) give. */
    fun typed(context: Context, said: String, lines: String): String =
        typed(said.encodeToByteArray(), lines.encodeToByteArray(), mapped(context, "en.lexicon")).decodeToString()

    /** What `heard` is written as for a dictation said in `app`, with Settings' `lines`, as a dictation's Writing Style writes it. */
    fun written(heard: String, lines: String, app: String?): String =
        written(heard.encodeToByteArray(), lines.encodeToByteArray(), app?.encodeToByteArray()).decodeToString()

    @JvmStatic private external fun written(heard: ByteArray, settings: ByteArray, app: ByteArray?): ByteArray

    @Serializable
    data class Style(val value: String, val title: String)

    /** The writing styles in order, as they're kept and titled. */
    val styles: List<Style> by lazy { Json.decodeFromString(styles().decodeToString()) }

    @JvmStatic private external fun styles(): ByteArray

    /** The style the settings `lines` write in, a Text Mode among them folded into it. */
    fun style(lines: String): String = style(lines.encodeToByteArray()).decodeToString()

    @JvmStatic private external fun style(settings: ByteArray): ByteArray

    @Serializable
    data class KeysHere(
        val numberRow: Boolean, val emojiKey: Boolean, val recordKey: Boolean, val keyboardMenu: Boolean,
        val split: Boolean, val oneHanded: Boolean, val largePanels: Boolean, val characterPreview: Boolean,
    )

    /** Which of Appearance's layout settings change the keys on this phone's screen, in dp. */
    fun keysHere(context: Context): KeysHere {
        val metrics = context.resources.displayMetrics
        val bytes = keysHere(
            metrics.widthPixels / metrics.density.toDouble(), metrics.heightPixels / metrics.density.toDouble(), context.folds(),
        )
        return Json.decodeFromString(bytes.decodeToString())
    }

    /** The taps the keyboard has learned where your thumbs land. */
    fun taps(context: Context): Int =
        File(context.filesDir, "typing-memory.json").takeIf { it.exists() }?.readBytes()?.let(::taps) ?: 0
}

/** The preview keyboard's field: always empty, and nothing typed into it goes anywhere (HostDocument calls these by name). */
class PreviewField {
    fun before() = ByteArray(0)
    fun after() = ByteArray(0)
    fun selected() = ByteArray(0)
    fun insert(@Suppress("UNUSED_PARAMETER") text: ByteArray) {}
    fun deleteSelection() {}
    fun deleteBefore(@Suppress("UNUSED_PARAMETER") count: Int) {}
    fun move(@Suppress("UNUSED_PARAMETER") offset: Int) {}
}

/** Settings' lines with `name` set to `value`, as Writing Style shows each choice with everything else as picked. */
fun Settings.linesWith(name: String, value: String) =
    lines().lines().joinToString("\n") { if (it.startsWith("$name=")) "$name=$value" else it }
