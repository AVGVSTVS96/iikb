package com.shahidy.iikb.voice

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * A Parakeet's joiner held to the Latin alphabet: v3 otherwise leaves for Cyrillic or Greek on short or unclear English,
 * and sherpa-onnx has no setting to stop it. FluidAudio's `language: .english` on iOS takes the best Latin token
 * whenever the joiner's best isn't one; this gets the same pick by setting the joiner's last bias to -1e9 for every
 * token with a letter outside the Latin alphabet (its rule, `TokenLanguageFilter.matches`), so no such token can win.
 * The joiner is the downloaded one, checked by its SHA-256, written beside it with those biases changed.
 */
object LatinJoiner {
    /** The joiner's output bias: its name, then raw_data (field 9) of 8,198 floats, 8,193 tokens and 5 durations. */
    private val BIAS = "joint_net.2.bias".encodeToByteArray() + byteArrayOf(0x4A, 0x98.toByte(), 0x80.toByte(), 0x02)
    private const val OUTPUTS = 8198

    /** The Latin joiner beside [joiner], written the first time. */
    fun of(joiner: File, tokens: File): File {
        val latin = File(joiner.parentFile, "joiner.latin.onnx")
        if (latin.exists()) return latin
        val bytes = joiner.readBytes()
        val at = find(bytes)
        val bias = ByteBuffer.wrap(bytes, at, OUTPUTS * 4).slice().order(ByteOrder.LITTLE_ENDIAN)
        for (id in outside(tokens)) bias.putFloat(id * 4, -1e9f)
        val next = File(latin.parentFile, latin.name + ".next")
        next.writeBytes(bytes)
        next.renameTo(latin)
        return latin
    }

    /** Where the bias's floats start; the joiner holds it once. */
    private fun find(bytes: ByteArray): Int {
        var found = -1
        outer@ for (start in 0..bytes.size - BIAS.size) {
            for (i in BIAS.indices) if (bytes[start + i] != BIAS[i]) continue@outer
            check(found < 0) { "The joiner holds its bias twice" }
            found = start + BIAS.size
        }
        check(found >= 0 && found + OUTPUTS * 4 <= bytes.size) { "The joiner has no bias where iikb looks" }
        return found
    }

    /** The ids of the tokens with a letter outside the Latin alphabet, from `tokens.txt` (`<text> <id>` a line). */
    fun outside(tokens: File): List<Int> = tokens.readLines().mapNotNull { line ->
        val space = line.lastIndexOf(' ')
        if (space < 0 || latin(line.substring(0, space))) null else line.substring(space + 1).toIntOrNull()
    }

    /** FluidAudio's Latin: ASCII, Latin-1, Latin Extended A and B and Additional, combining marks and currency. */
    fun latin(token: String) = token.replace("▁", "").codePoints().allMatch {
        it in 0x20..0x7F || it in 0xA0..0x24F || it in 0x300..0x36F || it in 0x1E00..0x1EFF ||
            Character.getType(it) == Character.CURRENCY_SYMBOL.toInt()
    }
}
