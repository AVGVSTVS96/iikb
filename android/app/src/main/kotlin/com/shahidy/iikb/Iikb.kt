package com.shahidy.iikb

import android.app.Application

/** The process the keyboard and the app share: what both read is loaded once, here, before either starts. */
class Iikb : Application() {
    override fun onCreate() {
        super.onCreate()
        Transcripts.load(this)
        TypingStats.load(this)
        Vocabulary.load(this)
    }
}
