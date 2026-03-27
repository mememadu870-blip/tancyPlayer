package com.tancy.player.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

class LibraryRepository(private val context: Context) {
    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true }
    private val cacheFile = File(context.filesDir, "library_cache.json")

    suspend fun load(): LibraryCache = withContext(Dispatchers.IO) {
        if (!cacheFile.exists()) return@withContext LibraryCache()
        runCatching {
            json.decodeFromString<LibraryCache>(cacheFile.readText())
        }.getOrDefault(LibraryCache())
    }

    suspend fun save(cache: LibraryCache) = withContext(Dispatchers.IO) {
        cacheFile.writeText(json.encodeToString(cache))
    }

    suspend fun saveTracks(current: LibraryCache, tracks: List<AudioTrack>) {
        save(current.copy(tracks = tracks))
    }

    suspend fun toggleFavorite(current: LibraryCache, trackId: Long): LibraryCache {
        val updated = if (trackId in current.favoriteTrackIds) {
            current.favoriteTrackIds - trackId
        } else {
            current.favoriteTrackIds + trackId
        }
        return current.copy(favoriteTrackIds = updated).also { save(it) }
    }

    suspend fun createPlaylist(current: LibraryCache, name: String): LibraryCache {
        val nextId = (current.playlists.maxOfOrNull { it.id } ?: 0L) + 1L
        val updated = current.copy(
            playlists = current.playlists + Playlist(id = nextId, name = name.trim())
        )
        save(updated)
        return updated
    }

    suspend fun addTrackToPlaylist(
        current: LibraryCache,
        playlistId: Long,
        trackId: Long
    ): LibraryCache {
        val updatedPlaylists = current.playlists.map { playlist ->
            if (playlist.id != playlistId) return@map playlist
            if (trackId in playlist.trackIds) playlist else playlist.copy(trackIds = playlist.trackIds + trackId)
        }
        val updated = current.copy(playlists = updatedPlaylists)
        save(updated)
        return updated
    }
}
