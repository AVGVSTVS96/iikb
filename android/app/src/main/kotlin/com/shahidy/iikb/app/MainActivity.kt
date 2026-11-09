package com.shahidy.iikb.app

import android.Manifest
import android.app.AlertDialog
import android.net.Uri
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
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
import com.shahidy.iikb.Services
import com.shahidy.iikb.Settings
import com.shahidy.iikb.app.clipboard.keepCopied
import com.shahidy.iikb.keyboard.IikbService

/** iikb's app: setting the keyboard up, a field to try it, and every setting. */
class MainActivity : ComponentActivity() {
    private var resumes by mutableIntStateOf(0)
    private var setup by mutableStateOf(Setup(enabled = false, picked = false, microphone = false))
    private val microphone = registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        refresh()
        if (!allowed && !shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)) refused()
    }

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

    /**
     * A service's link asks before it's added: an extension's (docs/extensions.md) before its chats open from the
     * keyboard's menu, a source's (docs/sources.md) before it's told what you type.
     */
    private fun offer(intent: Intent) {
        val (kind, added) = intent.data?.let(Services::of) ?: return
        setIntent(Intent(this, MainActivity::class.java))
        val host = Uri.parse(added.url).host
        AlertDialog.Builder(this)
            .setTitle("Add “${added.name}”?")
            .setMessage(
                when (kind) {
                    Services.EXTENSIONS -> "Its chats open from the keyboard’s menu, and what you write in them goes to $host."
                    Services.SOURCES -> "iikb will send $host the text of the fields you type in, with the app’s package name."
                },
            )
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Add") { _, _ -> kind.add(this, added) }
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

    /** Android asks no more once you've said no twice, so this says where to allow it, as iOS's switch does. */
    private fun refused() {
        AlertDialog.Builder(this)
            .setTitle("Couldn’t Turn On the Microphone")
            .setMessage("Allow iikb the microphone in Settings › Apps › iikb › Permissions.")
            .setNegativeButton("OK", null)
            .setPositiveButton("Settings") { _, _ ->
                startActivity(Intent(ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
            }
            .show()
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
