package com.tancy.player.player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.ui.PlayerNotificationManager
import com.tancy.player.data.AudioTrack

class PlayerController(context: Context) {
    interface ForegroundBridge {
        fun onNotificationPosted(notificationId: Int, ongoing: Boolean)
        fun onNotificationCancelled(notificationId: Int)
    }

    private val appContext = context.applicationContext
    private val exoPlayer = ExoPlayer.Builder(appContext).build()
    private val mediaSession = MediaSession.Builder(appContext, exoPlayer).build()
    private val notificationManager = buildNotificationManager()
    private var foregroundBridge: ForegroundBridge? = null
    private var queue: List<AudioTrack> = emptyList()
    private var currentIndex = -1

    fun submitQueue(tracks: List<AudioTrack>) {
        queue = tracks
        val mediaItems = tracks.map {
            MediaItem.Builder()
                .setUri(it.uri)
                .setMediaMetadata(
                    MediaMetadata.Builder()
                        .setTitle(it.title)
                        .setArtist(it.artist)
                        .build()
                )
                .build()
        }
        exoPlayer.setMediaItems(mediaItems)
        exoPlayer.prepare()
        if (currentIndex !in tracks.indices) currentIndex = if (tracks.isNotEmpty()) 0 else -1
    }

    fun playByTrackId(trackId: Long) {
        val index = queue.indexOfFirst { it.id == trackId }
        if (index < 0) return
        currentIndex = index
        exoPlayer.seekTo(index, 0L)
        exoPlayer.playWhenReady = true
        exoPlayer.play()
    }

    fun togglePlayPause() {
        if (exoPlayer.isPlaying) exoPlayer.pause() else exoPlayer.play()
    }

    fun next(): AudioTrack? {
        if (queue.isEmpty()) return null
        currentIndex = (currentIndex + 1).mod(queue.size)
        exoPlayer.seekTo(currentIndex, 0L)
        exoPlayer.play()
        return queue[currentIndex]
    }

    fun previous(): AudioTrack? {
        if (queue.isEmpty()) return null
        currentIndex = if (currentIndex <= 0) queue.lastIndex else currentIndex - 1
        exoPlayer.seekTo(currentIndex, 0L)
        exoPlayer.play()
        return queue[currentIndex]
    }

    fun currentTrack(): AudioTrack? = queue.getOrNull(currentIndex)

    fun isPlaying(): Boolean = exoPlayer.isPlaying

    fun pause() {
        exoPlayer.pause()
    }

    fun setRepeatMode(mode: Int) {
        exoPlayer.repeatMode = mode
    }

    fun seekTo(positionMs: Long) {
        exoPlayer.seekTo(positionMs.coerceAtLeast(0L))
    }

    fun currentPosition(): Long = exoPlayer.currentPosition.coerceAtLeast(0L)

    fun duration(): Long = if (exoPlayer.duration > 0) exoPlayer.duration else 0L

    fun setForegroundBridge(bridge: ForegroundBridge?) {
        foregroundBridge = bridge
    }

    fun release() {
        notificationManager.setPlayer(null)
        mediaSession.release()
        exoPlayer.release()
    }

    private fun buildNotificationManager(): PlayerNotificationManager {
        val channelId = "tancy_playback"
        val channelName = "Tancy Playback"
        val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(channelId) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    channelName,
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }

        return PlayerNotificationManager.Builder(appContext, 1101, channelId)
            .setMediaDescriptionAdapter(object : PlayerNotificationManager.MediaDescriptionAdapter {
                override fun getCurrentContentTitle(player: Player): CharSequence {
                    return player.mediaMetadata.title ?: "Unknown Title"
                }

                override fun createCurrentContentIntent(player: Player): PendingIntent? {
                    val launchIntent = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)
                        ?: Intent()
                    return PendingIntent.getActivity(
                        appContext,
                        2026,
                        launchIntent,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                }

                override fun getCurrentContentText(player: Player): CharSequence {
                    return player.mediaMetadata.artist ?: "Unknown Artist"
                }

                override fun getCurrentLargeIcon(
                    player: Player,
                    callback: PlayerNotificationManager.BitmapCallback
                ) = null
            })
            .setNotificationListener(object : PlayerNotificationManager.NotificationListener {
                override fun onNotificationPosted(
                    notificationId: Int,
                    notification: android.app.Notification,
                    ongoing: Boolean
                ) {
                    foregroundBridge?.onNotificationPosted(notificationId, ongoing)
                }

                override fun onNotificationCancelled(notificationId: Int, dismissedByUser: Boolean) {
                    foregroundBridge?.onNotificationCancelled(notificationId)
                }
            })
            .build()
            .also { it.setPlayer(exoPlayer) }
    }
}
