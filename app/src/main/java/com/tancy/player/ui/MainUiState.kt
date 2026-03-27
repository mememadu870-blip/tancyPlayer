package com.tancy.player.ui

import com.tancy.player.data.AudioTrack
import com.tancy.player.data.Playlist

data class MainUiState(
    val tracks: List<AudioTrack> = emptyList(),
    val playlists: List<Playlist> = emptyList(),
    val favoriteTrackIds: Set<Long> = emptySet(),
    val selectedPlaylistId: Long? = null,
    val nowPlayingTrackId: Long? = null,
    val isPlaying: Boolean = false,
    val playbackPositionMs: Long = 0L,
    val playbackDurationMs: Long = 0L,
    val duplicateGroups: List<List<AudioTrack>> = emptyList(),
    val isScanning: Boolean = false,
    val sleepTimerRemainingSeconds: Int = 0,
    val repeatMode: RepeatMode = RepeatMode.NONE
)

enum class RepeatMode {
    NONE,
    ONE,
    ALL
}
