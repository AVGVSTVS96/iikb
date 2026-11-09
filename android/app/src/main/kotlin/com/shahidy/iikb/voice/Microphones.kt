package com.shahidy.iikb.voice

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Which microphone voice typing hears with, picked in Settings › Voice, as iOS's `MicrophoneChoices`. Automatic is
 * the phone's own, or a wired or USB headset plugged in; never Bluetooth, which would put earbuds on a call and drop
 * their music to call quality. A Bluetooth microphone is used only once it's picked, and only while it's connected.
 * A pick is kept by its kind and name, since Android numbers a device afresh each time it connects.
 */
class Microphones private constructor(private val context: Context) {
    enum class Kind { PHONE, WIRED, BLUETOOTH }

    data class Choice(val kind: Kind, val name: String) {
        val key get() = "$kind:$name"
    }

    private val audio = context.getSystemService(AudioManager::class.java)
    private val preferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    /** What the Voice page draws; Compose reads it. */
    var picked by mutableStateOf(read())
        private set

    fun pick(choice: Choice?) {
        preferences.edit().putString(KEY, choice?.key).apply()
        picked = choice
    }

    /** The microphones connected now, the phone's first, each once. */
    fun connected(): List<Choice> = inputs().map { it.second }.distinct().sortedBy { it.kind }

    /** The input to record from now: the pick while it's connected, else Automatic's. */
    fun input(): AudioDeviceInfo? {
        val inputs = inputs()
        picked?.let { choice -> inputs.firstOrNull { it.second == choice }?.let { return it.first } }
        return inputs.firstOrNull { it.second.kind == Kind.WIRED }?.first
            ?: inputs.firstOrNull { it.second.kind == Kind.PHONE }?.first
    }

    /** For a Bluetooth input, the output Android has to make its call device so that the input hears. */
    fun callDevice(input: AudioDeviceInfo): AudioDeviceInfo? =
        if (kind(input.type) != Kind.BLUETOOTH || Build.VERSION.SDK_INT < 31) {
            null
        } else {
            audio.availableCommunicationDevices.firstOrNull { it.type == input.type && it.address == input.address }
                ?: audio.availableCommunicationDevices.firstOrNull { it.type == input.type }
        }

    /** A microphone as Settings › Voice names it, or null for one it never lists. */
    fun choice(device: AudioDeviceInfo): Choice? =
        kind(device.type)?.let { Choice(it, if (it == Kind.PHONE) PHONE else device.productName.toString()) }

    private fun inputs(): List<Pair<AudioDeviceInfo, Choice>> =
        audio.getDevices(AudioManager.GET_DEVICES_INPUTS).mapNotNull { device -> choice(device)?.let { device to it } }

    private fun read(): Choice? {
        val (kind, name) = preferences.getString(KEY, null)?.split(":", limit = 2)?.takeIf { it.size == 2 } ?: return null
        val picked = Kind.entries.firstOrNull { it.name == kind } ?: return null
        return Choice(picked, if (picked == Kind.PHONE) PHONE else name)
    }

    companion object {
        private const val KEY = "microphone"

        /** The phone's own microphones, named as iOS names an iPhone's ("iPhone Microphone"), one though they're several. */
        const val PHONE = "Phone Microphone"
        @Volatile private var shared: Microphones? = null

        fun of(context: Context): Microphones =
            shared ?: synchronized(this) { shared ?: Microphones(context.applicationContext).also { shared = it } }

        private fun kind(type: Int): Kind? = when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> Kind.PHONE
            AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> Kind.WIRED
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET -> Kind.BLUETOOTH
            else -> null
        }
    }
}
