package com.tancy.player.ui

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.Player
import com.tancy.player.data.AudioTrack
import com.tancy.player.data.HashUtils
import com.tancy.player.data.LibraryCache
import com.tancy.player.data.LibraryRepository
import com.tancy.player.data.MusicScanner
import com.tancy.player.player.PlayerController
import com.tancy.player.player.PlayerHolder
import com.tancy.player.player.PlaybackForegroundService
import com.tancy.player.player.SleepTimerManager
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val scanner = MusicScanner(application)
    private val repository = LibraryRepository(application)
    private val playerController = PlayerHolder.get(application)
    private val sleepTimerManager = SleepTimerManager()

    private val _uiState = MutableStateFlow(MainUiState())
    val uiState: StateFlow<MainUiState> = _uiState.asStateFlow()

    private var cache = LibraryCache()

    init {
        viewModelScope.launch {
            cache = repository.load()
            _uiState.update {
                it.copy(
                    tracks = cache.tracks,
                    playlists = cache.playlists,
                    favoriteTrackIds = cache.favoriteTrackIds
                )
            }
            playerController.submitQueue(cache.tracks)
        }

        viewModelScope.launch {
            sleepTimerManager.remainingSeconds.collect { seconds ->
                _uiState.update { it.copy(sleepTimerRemainingSeconds = seconds) }
            }
        }

        viewModelScope.launch {
            while (true) {
                _uiState.update {
                    it.copy(
                        playbackPositionMs = playerController.currentPosition(),
                        playbackDurationMs = playerController.duration()
                    )
                }
                delay(500)
            }
        }
    }

    fun scanMusicFiles() {
        viewModelScope.launch {
            _uiState.update { it.copy(isScanning = true) }
            val tracks = scanner.scanLocalAudioFiles()
            cache = cache.copy(tracks = tracks)
            repository.save(cache)
            playerController.submitQueue(tracks)
            _uiState.update {
                it.copy(
                    tracks = tracks,
                    isScanning = false
                )
            }
        }
    }

    fun play(trackId: Long) {
        playerController.playByTrackId(trackId)
        PlaybackForegroundService.start(getApplication())
        _uiState.update {
            it.copy(
                nowPlayingTrackId = trackId,
                isPlaying = playerController.isPlaying()
            )
        }
    }

    fun togglePlayPause() {
        playerController.togglePlayPause()
        if (playerController.isPlaying()) {
            PlaybackForegroundService.start(getApplication())
        } else {
            PlaybackForegroundService.stop(getApplication())
        }
        _uiState.update { it.copy(isPlaying = playerController.isPlaying()) }
    }

    fun next() {
        val next = playerController.next()
        PlaybackForegroundService.start(getApplication())
        _uiState.update {
            it.copy(
                nowPlayingTrackId = next?.id,
                isPlaying = playerController.isPlaying()
            )
        }
    }

    fun previous() {
        val prev = playerController.previous()
        PlaybackForegroundService.start(getApplication())
        _uiState.update {
            it.copy(
                nowPlayingTrackId = prev?.id,
                isPlaying = playerController.isPlaying()
            )
        }
    }

    fun toggleFavorite(trackId: Long) {
        viewModelScope.launch {
            cache = repository.toggleFavorite(cache, trackId)
            _uiState.update { it.copy(favoriteTrackIds = cache.favoriteTrackIds) }
        }
    }

    fun createPlaylist(name: String) {
        if (name.isBlank()) return
        viewModelScope.launch {
            cache = repository.createPlaylist(cache, name)
            val newestId = cache.playlists.maxOfOrNull { it.id }
            _uiState.update {
                it.copy(
                    playlists = cache.playlists,
                    selectedPlaylistId = newestId
                )
            }
        }
    }

    fun choosePlaylist(playlistId: Long?) {
        _uiState.update { it.copy(selectedPlaylistId = playlistId) }
    }

    fun addTrackToSelectedPlaylist(trackId: Long) {
        val playlistId = _uiState.value.selectedPlaylistId ?: return
        viewModelScope.launch {
            cache = repository.addTrackToPlaylist(cache, playlistId, trackId)
            _uiState.update { it.copy(playlists = cache.playlists) }
        }
    }

    fun setSleepTimer(minutes: Int) {
        if (minutes <= 0) {
            sleepTimerManager.stop()
            return
        }
        sleepTimerManager.start(minutes) {
            playerController.pause()
            PlaybackForegroundService.stop(getApplication())
            _uiState.update { it.copy(isPlaying = false) }
        }
    }

    fun seekTo(positionMs: Long) {
        playerController.seekTo(positionMs)
        _uiState.update {
            it.copy(playbackPositionMs = playerController.currentPosition())
        }
    }

    fun setRepeatMode(mode: RepeatMode) {
        val playerRepeat = when (mode) {
            RepeatMode.NONE -> Player.REPEAT_MODE_OFF
            RepeatMode.ONE -> Player.REPEAT_MODE_ONE
            RepeatMode.ALL -> Player.REPEAT_MODE_ALL
        }
        playerController.setRepeatMode(playerRepeat)
        _uiState.update { it.copy(repeatMode = mode) }
    }

    fun detectDuplicatesByHash() {
        viewModelScope.launch {
            val hashed = cache.tracks.map { track ->
                if (!track.hash.isNullOrBlank()) {
                    track
                } else {
                    val input = getApplication<Application>().contentResolver
                        .openInputStream(Uri.parse(track.uri))
                    track.copy(hash = HashUtils.sha256(input))
                }
            }
            cache = cache.copy(tracks = hashed)
            repository.save(cache)
            playerController.submitQueue(hashed)
            val grouped = hashed
                .filter { !it.hash.isNullOrBlank() }
                .groupBy { it.hash!! }
                .values
                .filter { it.size > 1 }
                .sortedByDescending { it.size }
            _uiState.update {
                it.copy(
                    tracks = hashed,
                    duplicateGroups = grouped
                )
            }
        }
    }

    fun clearDuplicateResult() {
        _uiState.update { it.copy(duplicateGroups = emptyList()) }
    }

    override fun onCleared() {
        PlaybackForegroundService.stop(getApplication())
        super.onCleared()
    }
}
