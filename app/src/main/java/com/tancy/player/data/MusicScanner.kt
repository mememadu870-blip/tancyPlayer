package com.tancy.player.data

import android.content.Context
import android.provider.MediaStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class MusicScanner(private val context: Context) {
    suspend fun scanLocalAudioFiles(): List<AudioTrack> = withContext(Dispatchers.IO) {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.DATE_ADDED} DESC"

        val tracks = mutableListOf<AudioTrack>()
        context.contentResolver.query(collection, projection, selection, null, sortOrder)?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val durationIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val sizeIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idIndex)
                val uri = "${MediaStore.Audio.Media.EXTERNAL_CONTENT_URI}/$id"
                tracks += AudioTrack(
                    id = id,
                    uri = uri,
                    title = cursor.getString(titleIndex) ?: "Unknown",
                    artist = cursor.getString(artistIndex) ?: "Unknown",
                    durationMs = cursor.getLong(durationIndex),
                    sizeBytes = cursor.getLong(sizeIndex),
                    hash = null
                )
            }
        }

        tracks
    }
}
