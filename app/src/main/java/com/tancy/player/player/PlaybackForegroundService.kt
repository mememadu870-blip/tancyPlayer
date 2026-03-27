package com.tancy.player.player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.tancy.player.MainActivity

class PlaybackForegroundService : Service() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP_SERVICE) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        ensureChannel()
        startForeground(NOTIFICATION_ID, buildForegroundNotification())
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Playback Service", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    private fun buildForegroundNotification(): android.app.Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            3001,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Tancy Player")
            .setContentText("后台播放服务运行中")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val ACTION_START_SERVICE = "com.tancy.player.action.START_FOREGROUND"
        private const val ACTION_STOP_SERVICE = "com.tancy.player.action.STOP_FOREGROUND"
        private const val CHANNEL_ID = "tancy_foreground_service"
        private const val NOTIFICATION_ID = 2011

        fun start(context: Context) {
            val intent = Intent(context, PlaybackForegroundService::class.java).apply {
                action = ACTION_START_SERVICE
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, PlaybackForegroundService::class.java).apply {
                action = ACTION_STOP_SERVICE
            }
            context.startService(intent)
        }
    }
}
