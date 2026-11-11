package com.shahidy.iikb.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import com.shahidy.iikb.keyboard.ChatPhotos

/**
 * Asks Android for your photos for the keyboard's Chats, which can't ask itself, then goes back to the app you were in,
 * where the chat opens again as you left it. Once Android won't ask again, it opens iikb's page in Settings instead.
 */
class AllowPhotos : ComponentActivity() {
    private val ask = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { answers ->
        val refused = answers.values.none { it } && ChatPhotos.permissions.none(::shouldShowRequestPermissionRationale)
        if (refused) startActivity(Intent(ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) ask.launch(ChatPhotos.permissions)
    }
}
