package com.shahidy.iikb.keyboard

import java.nio.ByteBuffer

/** iikb's engine, KeyboardCore built for Android (android/Sources/KeyboardAndroid/Bridge.swift). Text is UTF-8. */
object Native {
    init {
        System.loadLibrary("iikb")
    }

    @JvmStatic external fun create(
        field: Field, lexicon: ByteBuffer?, network: ByteBuffer?, swipe: ByteBuffer?, emoji: ByteArray, search: ByteArray,
        panels: ByteArray,
    ): Long

    @JvmStatic external fun destroy(handle: Long)
    @JvmStatic external fun place(
        handle: Long, width: Double, screenWidth: Double, screenHeight: Double, folds: Boolean, bottom: Double,
        dark: Boolean, globe: Boolean,
    )

    @JvmStatic external fun configure(handle: Long, settings: ByteArray)
    @JvmStatic external fun traits(
        handle: Long, names: ByteArray, smartPunctuation: Boolean, requiresText: Boolean, autocorrection: Boolean,
    )

    @JvmStatic external fun frame(handle: Long): ByteArray
    @JvmStatic external fun resolve(handle: Long, x: Double, y: Double): Int
    @JvmStatic external fun down(handle: Long, index: Int, taps: Int)
    @JvmStatic external fun up(handle: Long, index: Int)
    @JvmStatic external fun type(handle: Long, index: Int, text: ByteArray, x: Double, y: Double)
    @JvmStatic external fun trigger(handle: Long, index: Int)
    @JvmStatic external fun slide(handle: Long, text: ByteArray)
    @JvmStatic external fun swipe(handle: Long, xs: FloatArray, ys: FloatArray, times: FloatArray)
    @JvmStatic external fun cursor(handle: Long, offset: Int)
    @JvmStatic external fun crossed(handle: Long, step: Int): ByteArray?
    @JvmStatic external fun menu(handle: Long, item: Int)
    @JvmStatic external fun select(handle: Long, index: Int)
    @JvmStatic external fun expand(handle: Long)
    @JvmStatic external fun oneHanded(handle: Long): ByteArray?
    @JvmStatic external fun acceptEmoji(handle: Long, emoji: ByteArray)
    @JvmStatic external fun pickEmoji(handle: Long, emoji: ByteArray, base: ByteArray?)
    @JvmStatic external fun paste(handle: Long, text: ByteArray)
    @JvmStatic external fun panel(handle: Long, name: ByteArray?)
    @JvmStatic external fun emojiResults(handle: Long): ByteArray
    @JvmStatic external fun tones(handle: Long, emoji: ByteArray): ByteArray
    @JvmStatic external fun written(handle: Long, heard: ByteArray, app: ByteArray?): ByteArray
    @JvmStatic external fun dictated(handle: Long, text: ByteArray, plain: ByteArray?, id: ByteArray?)
    @JvmStatic external fun deleteRepeat(handle: Long, words: Boolean)
    @JvmStatic external fun documentChanged(handle: Long): Boolean
    @JvmStatic external fun leaveField(handle: Long)
    /** What the keyboard shows, for the bar's More and mic (`Keyboard.shown`). */
    @JvmStatic external fun shown(handle: Long, menu: Boolean, chat: Boolean, keysUp: Boolean)
    @JvmStatic external fun endSession(handle: Long)
    @JvmStatic external fun suggestionJob(handle: Long): Long
    @JvmStatic external fun runJob(job: Long)
    @JvmStatic external fun finishJob(handle: Long, job: Long)
    @JvmStatic external fun memory(handle: Long): ByteArray?
    @JvmStatic external fun restoreMemory(handle: Long, bytes: ByteArray)
    @JvmStatic external fun emojiHistory(handle: Long): ByteArray?
    @JvmStatic external fun restoreEmojiHistory(handle: Long, bytes: ByteArray)
    @JvmStatic external fun changeApp(handle: Long, app: ByteArray?)
    @JvmStatic external fun resetMemory(handle: Long)
    @JvmStatic external fun learnLexicon(handle: Long, entries: ByteArray)
    @JvmStatic external fun sourcesReset(handle: Long, count: Int)
    @JvmStatic external fun sourcesObserve(handle: Long, field: ByteArray, app: ByteArray?, byKeyboard: Boolean, at: Double)
    @JvmStatic external fun sourcesNext(handle: Long, index: Int): ByteArray?
    @JvmStatic external fun sourcesAnswered(handle: Long, index: Int, hint: ByteArray?)
    @JvmStatic external fun sourcesFailed(handle: Long, index: Int)
    @JvmStatic external fun sourcesHint(handle: Long, field: ByteArray, app: ByteArray?): ByteArray?
    @JvmStatic external fun sourcesDismiss(handle: Long)

    @JvmStatic external fun clipsCreate(json: ByteArray?): Long
    @JvmStatic external fun clipsSave(handle: Long): ByteArray?
    @JvmStatic external fun clipsKeep(handle: Long, text: ByteArray?, image: ByteArray?, time: Double)
    @JvmStatic external fun clipsRows(handle: Long, search: ByteArray, words: Boolean, now: Double): ByteArray
    @JvmStatic external fun clipsPin(handle: Long, text: ByteArray, image: ByteArray?, pinned: Boolean)
    @JvmStatic external fun clipsRemove(handle: Long, text: ByteArray, image: ByteArray?)
    @JvmStatic external fun clipsClear(handle: Long): ByteArray
    @JvmStatic external fun gifsCreate(recents: ByteArray?): Long
    @JvmStatic external fun gifsWant(handle: Long, feed: ByteArray, app: ByteArray?): ByteArray?
    @JvmStatic external fun gifsMore(handle: Long): ByteArray?
    @JvmStatic external fun gifsReceived(handle: Long, request: ByteArray, found: ByteArray?, hasNext: Boolean): ByteArray?
    @JvmStatic external fun gifsShown(handle: Long): ByteArray
    @JvmStatic external fun gifsUse(handle: Long, slug: ByteArray, app: ByteArray?): ByteArray?
    @JvmStatic external fun age(found: Double, now: Double): ByteArray
    @JvmStatic external fun length(text: ByteArray, words: Boolean): ByteArray
    @JvmStatic external fun swatch(name: ByteArray, appearance: ByteArray, dark: Boolean): ByteArray

    // A chat's message line (Line.swift)
    @JvmStatic external fun lineOpen(handle: Long, text: ByteArray?)
    @JvmStatic external fun lineClose(handle: Long)
    @JvmStatic external fun lineState(handle: Long): ByteArray?
    @JvmStatic external fun lineTake(handle: Long): ByteArray?
    @JvmStatic external fun lineRestore(handle: Long, text: ByteArray?)

    // Stats (Stats.swift)
    @JvmStatic external fun typingLog(): Long
    @JvmStatic external fun noteTyping(log: Long, handle: Long, time: Double, day: ByteArray, hour: Int, app: ByteArray?)
    @JvmStatic external fun takeTyping(log: Long): ByteArray
    @JvmStatic external fun taps(
        memory: ByteArray?, settings: ByteArray, signature: ByteArray?, width: Double, height: Double, folds: Boolean,
    ): ByteArray
}
