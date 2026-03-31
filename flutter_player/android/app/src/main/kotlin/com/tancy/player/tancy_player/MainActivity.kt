package com.tancy.player.tancy_player

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "tancy_player/system"
    private var latestAudioUri: String? = null
    private var initialAudioConsumed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        latestAudioUri = extractAudioUri(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialAudioUri" -> {
                        val uri = if (initialAudioConsumed) null else latestAudioUri
                        initialAudioConsumed = true
                        result.success(uri)
                    }

                    "openDefaultAppsSettings" -> {
                        openDefaultAppsSettings()
                        result.success(true)
                    }

                    "shareAudio" -> {
                        val path = call.argument<String>("path")
                        val title = call.argument<String>("title")
                        if (path.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            shareAudio(path, title)
                            result.success(true)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val audioUri = extractAudioUri(intent) ?: return
        latestAudioUri = audioUri
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, channelName).invokeMethod("audioIntent", audioUri)
        }
    }

    private fun extractAudioUri(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        val mimeType = intent.type ?: contentResolver.getType(data) ?: return null
        return if (mimeType.startsWith("audio/")) data.toString() else null
    }

    private fun openDefaultAppsSettings() {
        val defaultAppsIntent = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(android.net.Uri.parse("package:$packageName"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(defaultAppsIntent)
        } catch (_: Exception) {
            startActivity(fallbackIntent)
        }
    }

    private fun shareAudio(path: String, title: String?) {
        val file = File(path)
        val uri: Uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file
        )
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = contentResolver.getType(uri) ?: "audio/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, title ?: file.name)
            putExtra(Intent.EXTRA_TEXT, title ?: file.name)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(shareIntent, title ?: file.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
