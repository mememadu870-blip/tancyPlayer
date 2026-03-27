package com.tancy.player.data

import kotlinx.serialization.Serializable

@Serializable
data class AudioTrack(
    val id: Long,
    val uri: String,
    val title: String,
    val artist: String,
    val durationMs: Long,
    val sizeBytes: Long,
    val hash: String? = null
)

@Serializable
data class Playlist(
    val id: Long,
    val name: String,
    val trackIds: List<Long> = emptyList()
)

@Serializable
data class LibraryCache(
    val tracks: List<AudioTrack> = emptyList(),
    val playlists: List<Playlist> = emptyList(),
    val favoriteTrackIds: Set<Long> = emptySet()
)
