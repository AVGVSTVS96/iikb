package com.shahidy.iikb.keyboard

import android.content.Context
import android.media.AudioManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.HapticFeedbackConstants
import android.view.View

/**
 * A press's haptic and click. Haptic Feedback's seven strengths scale the vibrator's click primitive, Standard in the
 * middle and Strongest twice it; a phone without primitives plays Android's own keyboard tap, at its strength.
 */
class Feedback(context: Context, private val view: View) {
    enum class Kind { INPUT, SEPARATOR, DELETE, DELETE_REPEAT, DELETE_RAPID, OTHER }

    private val vibrator = context.getSystemService(Vibrator::class.java)
    private val audio = context.getSystemService(AudioManager::class.java)
    private val primitives = vibrator?.areAllPrimitivesSupported(
        VibrationEffect.Composition.PRIMITIVE_CLICK, VibrationEffect.Composition.PRIMITIVE_TICK,
    ) == true

    var strength = "standard"
    var sound = true

    fun play(kind: Kind) {
        if (sound && audio?.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            audio.playSoundEffect(
                when (kind) {
                    Kind.SEPARATOR -> AudioManager.FX_KEYPRESS_SPACEBAR
                    Kind.DELETE, Kind.DELETE_REPEAT, Kind.DELETE_RAPID -> AudioManager.FX_KEYPRESS_DELETE
                    else -> AudioManager.FX_KEYPRESS_STANDARD
                },
                -1f,
            )
        }
        val scale = SCALES[strength] ?: return
        if (!primitives) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
            return
        }
        val primitive = when (kind) {
            Kind.INPUT, Kind.SEPARATOR, Kind.DELETE -> VibrationEffect.Composition.PRIMITIVE_CLICK
            else -> VibrationEffect.Composition.PRIMITIVE_TICK
        }
        val weight = if (kind == Kind.OTHER || kind == Kind.DELETE_REPEAT) 0.7f else 1f
        vibrator?.vibrate(VibrationEffect.startComposition().addPrimitive(primitive, scale * weight).compose())
    }

    private companion object {
        val SCALES = mapOf(
            "lightest" to 0.15f, "lighter" to 0.25f, "light" to 0.35f, "standard" to 0.5f,
            "strong" to 0.65f, "stronger" to 0.8f, "strongest" to 1f,
        )
    }
}
