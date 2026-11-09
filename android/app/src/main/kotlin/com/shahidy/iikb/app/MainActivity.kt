package com.shahidy.iikb.app

import android.Manifest
import android.app.AlertDialog
import android.net.Uri
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings.ACTION_INPUT_METHOD_SETTINGS
import android.provider.Settings.Secure
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shahidy.iikb.Extension
import com.shahidy.iikb.Extensions
import com.shahidy.iikb.Settings
import com.shahidy.iikb.app.clipboard.keepCopied
import com.shahidy.iikb.keyboard.IikbService

/** iikb's app: setting the keyboard up, a field to try it, and every setting. */
class MainActivity : ComponentActivity() {
    private var resumes by mutableIntStateOf(0)
    private var setup by mutableStateOf(Setup(enabled = false, picked = false, microphone = false))
    private val microphone = registerForActivityResult(ActivityResultContracts.RequestPermission()) { refresh() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val settings = Settings(this)
        val page = intent.getStringExtra(PAGE)
        setContent {
            CompositionLocalProvider(LocalResumes provides resumes) {
                App(
                    settings = settings,
                    setup = setup,
                    startPage = page,
                    onEnable = { startActivity(Intent(ACTION_INPUT_METHOD_SETTINGS)) },
                    onPick = { getSystemService(InputMethodManager::class.java).showInputMethodPicker() },
                    onMicrophone = { microphone.launch(Manifest.permission.RECORD_AUDIO) },
                )
            }
        }
        if (page == VOICE && !setup.microphone) microphone.launch(Manifest.permission.RECORD_AUDIO)
        offer(intent)
    }

    /** An extension's link (docs/extensions.md) asks before its chats open from the keyboard's menu. */
    private fun offer(intent: Intent) {
        val added = intent.data?.let(Extension::of) ?: return
        setIntent(Intent(this, MainActivity::class.java))
        AlertDialog.Builder(this)
            .setTitle("Add “${added.name}”?")
            .setMessage("Its chats open from the keyboard’s menu, and what you write in them goes to ${Uri.parse(added.url).host}.")
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Add") { _, _ -> Extensions.add(this, added) }
            .show()
    }

    /** The keyboard opens a page of the app it's already running, like Appearance from the menu's Theme row. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        offer(intent)
        if (intent.getStringExtra(PAGE) != null) {
            setIntent(intent)
            recreate()
        }
    }

    override fun onResume() {
        super.onResume()
        resumes++
        refresh()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            refresh()
            keepCopied(this)
        }
    }

    /** Read each time iikb comes forward, so the steps check off as you come back from Android's settings. */
    private fun refresh() {
        val id = ComponentName(this, IikbService::class.java).flattenToShortString()
        val full = ComponentName(this, IikbService::class.java).flattenToString()
        val imm = getSystemService(InputMethodManager::class.java)
        val enabled = imm.enabledInputMethodList.any { it.id == id || it.id == full }
        val current = Secure.getString(contentResolver, Secure.DEFAULT_INPUT_METHOD)
        setup = Setup(
            enabled = enabled,
            picked = current == id || current == full,
            microphone = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED,
        )
    }

    companion object {
        const val PAGE = "page"
        const val VOICE = "voice"
    }
}

data class Setup(val enabled: Boolean, val picked: Boolean, val microphone: Boolean) {
    val done get() = enabled && picked && microphone
}
