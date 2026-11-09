package com.shahidy.iikb.voice

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * A recording longer than Parakeet's 15 s window, written as FluidAudio writes one on iOS (`ChunkProcessor`), so the
 * encoder never holds more than 15 s however long you talk. Windows are 14.96 s. Each ends at the latest pause in its
 * last 5 s (three quiet frames running, quiet as under 0.18 of the window's loudest frame), where the next starts with
 * no overlap: FluidAudio's path for an encoder that takes shorter windows for less, as sherpa-onnx's does on the CPU.
 * With no pause there, the next starts 2 s back over it, at the quietest frame near where it falls (within 4 s if one
 * is near silence, else within 0.5 s if one is a valley between words), and the two are joined token by token where
 * they overlap. The last is filled back to full length with sound already heard. Token times are seconds into the
 * recording.
 */
object Windows {
    const val FRAME = 1280
    const val CHUNK = (240_000 - 160) / FRAME * FRAME
    private const val OVERLAP = 32_000 / FRAME * FRAME
    private const val STRIDE = (CHUNK - OVERLAP) / FRAME * FRAME
    private const val RATE = 16_000f
    private const val FRAME_SECONDS = FRAME / RATE
    private const val OVERLAP_SECONDS = OVERLAP / RATE

    /**
     * Samples `begin` to `end` are written; tokens before `keep` belong to the window before, which ends where this
     * starts if it starts at a pause (`cut`), so the two simply follow each other.
     */
    class Window(val begin: Int, val end: Int, val keep: Int, val cut: Boolean)

    private class Start(val at: Int, val cut: Boolean)

    class Token(val text: String, val start: Float) {
        /** Starts a word (SentencePiece's ▁, a space here) or is only punctuation: a join may cut before it. */
        val safe = text.startsWith(" ") || (text.isNotBlank() && text.none { it.isLetterOrDigit() })
    }

    fun plan(samples: FloatArray): List<Window> {
        val starts = starts(samples)
        return starts.mapIndexed { index, start ->
            val next = starts.getOrNull(index + 1)
            val end = if (next?.cut == true) next.at else min(samples.size, start.at + CHUNK)
            val filled = index == starts.lastIndex && index > 0 && !start.cut && end - start.at < CHUNK
            Window(if (filled) max(0, end - CHUNK) / FRAME * FRAME else start.at, end, start.at, start.cut)
        }
    }

    private fun starts(samples: FloatArray): List<Start> {
        val starts = mutableListOf(Start(0, false))
        val sums = frameSums(samples)
        var previous = 0
        var target = STRIDE
        while (target < samples.size && previous + CHUNK < samples.size) {
            val cut = pause(sums, previous, samples.size)
            if (cut != null) {
                starts += Start(cut, true)
                previous = cut
                target = cut + STRIDE
                continue
            }
            val frame = target / FRAME
            val latest = previous + CHUNK - FRAME * 6
            val fixed = min(max(frame * FRAME, previous + FRAME), latest)
            val quiet = quietest(samples, frame, (4 * RATE / FRAME).toInt(), previous, latest)
            var start = if (quiet.median > 0 && quiet.score <= quiet.median * 0.05f) {
                quiet.start
            } else {
                val valley = quietest(samples, frame, (0.5f * RATE / FRAME).toInt(), previous, latest)
                if (valley.median > 0 && valley.score <= valley.median * 0.35f) valley.start else fixed
            }
            if (start <= previous) start = min(previous + STRIDE, samples.size)
            starts += Start(start, false)
            previous = start
            target += STRIDE
        }
        return starts
    }

    /** Each 80 ms frame's sum of squares. */
    private fun frameSums(samples: FloatArray) = FloatArray((samples.size + FRAME - 1) / FRAME) { frame ->
        var sum = 0f
        for (i in frame * FRAME until min(samples.size, (frame + 1) * FRAME)) sum += samples[i] * samples[i]
        sum
    }

    /**
     * FluidAudio's `latestPauseCut`: the middle of the latest run of three or more quiet frame boundaries in the last
     * 5 s of the window starting at `previous`, quiet as under 0.18 of its loudest frame's level (at least 0.004).
     */
    private fun pause(sums: FloatArray, previous: Int, size: Int): Int? {
        val end = min(previous + CHUNK, size) - FRAME
        val band = max(previous + FRAME, previous + CHUNK - (5 * RATE).toInt())
        if (end <= band) return null
        val boundaries = mutableListOf<Pair<Int, Float>>()
        var frame = (previous + FRAME) / FRAME
        while (frame * FRAME <= end && frame < sums.size) {
            boundaries += frame * FRAME to (sums[frame - 1] + sums[frame]) / (2 * FRAME)
            frame++
        }
        val peak = boundaries.maxOfOrNull { it.second }?.takeIf { it > 0 } ?: return null
        val gate = max(0.004f, 0.18f * sqrt(peak)).let { it * it }
        val late = boundaries.filter { it.first >= band }
        if (late.size < 3) return null
        var runEnd = late.lastIndex
        while (runEnd >= 0) {
            if (late[runEnd].second > gate) {
                runEnd--
                continue
            }
            var runStart = runEnd
            while (runStart > 0 && late[runStart - 1].second <= gate) runStart--
            if (runEnd - runStart + 1 >= 3) return late[(runStart + runEnd) / 2].first
            runEnd = runStart - 1
        }
        return null
    }

    private class Candidate(val start: Int, val score: Float, val median: Float)

    /** The frame within `radius` of `frame` with the least energy in the 80 ms either side, and the median energy. */
    private fun quietest(samples: FloatArray, frame: Int, radius: Int, previous: Int, latest: Int): Candidate {
        val fixed = min(max(frame * FRAME, previous + FRAME), latest)
        var start = fixed
        var score = Float.MAX_VALUE
        val scores = mutableListOf<Float>()
        for (candidate in max(1, frame - radius)..min((samples.size - 1) / FRAME, frame + radius)) {
            val at = candidate * FRAME
            if (at <= previous || at > latest) continue
            val energy = energy(samples, at)
            scores += energy
            if (energy < score) {
                score = energy
                start = at
            }
        }
        if (scores.isEmpty()) return Candidate(fixed, Float.MAX_VALUE, 0f)
        scores.sort()
        return Candidate(start, score, scores[scores.size / 2])
    }

    private fun energy(samples: FloatArray, center: Int): Float {
        val from = max(0, center - FRAME)
        val to = min(samples.size, center + FRAME)
        if (to <= from) return 0f
        var sum = 0f
        for (i in from until to) sum += samples[i] * samples[i]
        return sum / (to - from)
    }

    /**
     * The two windows' tokens as one: the right's added on if they don't overlap; else joined at the longest run both
     * heard (the same piece, ignoring case, within a second), or failing that their longest common subsequence, or at
     * the overlap's middle; and cut only before a word, so one window spells a word the join falls in.
     */
    fun merge(left: List<Token>, right: List<Token>): List<Token> {
        if (left.isEmpty()) return right
        if (right.isEmpty()) return left
        val leftEnd = left.last().start + FRAME_SECONDS
        val rightStart = right.first().start
        if (leftEnd <= rightStart) return left + right
        val overlapLeft = left.indices.filter { left[it].start + FRAME_SECONDS > rightStart - OVERLAP_SECONDS }
        val overlapRight = right.indices.filter { right[it].start < leftEnd + OVERLAP_SECONDS }
        if (overlapLeft.size < 2 || overlapRight.size < 2) return midpoint(left, right, leftEnd, rightStart)
        val same = { i: Int, j: Int ->
            val a = left[overlapLeft[i]]
            val b = right[overlapRight[j]]
            a.text.equals(b.text, ignoreCase = true) && abs(a.start - b.start) < OVERLAP_SECONDS / 2
        }
        val run = contiguous(overlapLeft.size, overlapRight.size, same)
        val matches = if (run.size >= max(overlapLeft.size / 2, 1)) run else common(overlapLeft.size, overlapRight.size, same)
        if (matches.isEmpty()) return midpoint(left, right, leftEnd, rightStart)
        return joined(matches.map { (i, j) -> overlapLeft[i] to overlapRight[j] }, left, right)
    }

    private fun contiguous(n: Int, m: Int, same: (Int, Int) -> Boolean): List<Pair<Int, Int>> {
        var best = 0
        var bestLeft = 0
        var bestRight = 0
        var previous = IntArray(m + 1)
        for (i in 1..n) {
            val current = IntArray(m + 1)
            for (j in 1..m) {
                if (!same(i - 1, j - 1)) continue
                current[j] = previous[j - 1] + 1
                if (current[j] > best) {
                    best = current[j]
                    bestLeft = i - best
                    bestRight = j - best
                }
            }
            previous = current
        }
        return (0 until best).map { bestLeft + it to bestRight + it }
    }

    private fun common(n: Int, m: Int, same: (Int, Int) -> Boolean): List<Pair<Int, Int>> {
        val lengths = Array(n + 1) { IntArray(m + 1) }
        for (i in n - 1 downTo 0) for (j in m - 1 downTo 0) {
            lengths[i][j] = if (same(i, j)) lengths[i + 1][j + 1] + 1 else max(lengths[i + 1][j], lengths[i][j + 1])
        }
        val pairs = mutableListOf<Pair<Int, Int>>()
        var i = 0
        var j = 0
        while (i < n && j < m) {
            when {
                same(i, j) -> pairs += i++ to j++
                lengths[i + 1][j] >= lengths[i][j + 1] -> i++
                else -> j++
            }
        }
        return pairs
    }

    /**
     * Left up to the first match, the matches with whichever window heard more between each two, then right's tail.
     * A tail that starts mid-word takes right's whole seam word if right heard its start, else left's, resuming right
     * at its next word; with no word start to resume at it keeps the tail as is, since a glued word beats a lost one.
     */
    private fun joined(matches: List<Pair<Int, Int>>, left: List<Token>, right: List<Token>): List<Token> {
        val result = left.subList(0, matches.first().first).toMutableList()
        matches.forEachIndexed { index, (l, r) ->
            result += left[l]
            val next = matches.getOrNull(index + 1) ?: return@forEachIndexed
            val gapLeft = left.subList(l + 1, max(l + 1, next.first))
            val gapRight = right.subList(r + 1, max(r + 1, next.second))
            result += if (gapRight.size > gapLeft.size) gapRight else gapLeft
        }
        val lastLeft = matches.last().first
        val lastRight = matches.last().second
        val tail = right.subList(lastRight + 1, right.size)
        if (tail.isEmpty() || tail.first().safe) return result + tail
        val wordStart = (lastRight downTo 0).firstOrNull { right[it].safe }
        val seamWord = result.indices.lastOrNull { result[it].safe }
        if (wordStart != null && seamWord != null) {
            return result.subList(0, seamWord) + right.subList(wordStart, right.size)
        }
        var cursor = lastLeft + 1
        while (cursor < left.size && !left[cursor].safe) result += left[cursor++]
        val resume = tail.indexOfFirst { it.safe }
        return result + if (resume >= 0) tail.subList(resume, tail.size) else tail
    }

    /** Left before the overlap's middle and right after it, left finishing the word it's in. */
    private fun midpoint(left: List<Token>, right: List<Token>, leftEnd: Float, rightStart: Float): List<Token> {
        val cut = (leftEnd + rightStart) / 2
        var leftStop = left.indexOfFirst { it.start >= cut }.takeIf { it >= 0 } ?: left.size
        var rightFrom = right.indexOfFirst { it.start >= cut }.takeIf { it >= 0 } ?: right.size
        if (leftStop > 0) while (leftStop < left.size && !left[leftStop].safe) leftStop++
        var scan = rightFrom
        while (scan < right.size && !right[scan].safe) scan++
        if (scan < right.size) rightFrom = scan
        return left.subList(0, leftStop) + right.subList(rightFrom, right.size)
    }
}
