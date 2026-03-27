package com.tancy.player.player

import android.content.Context

object PlayerHolder {
    @Volatile
    private var instance: PlayerController? = null

    fun get(context: Context): PlayerController {
        return instance ?: synchronized(this) {
            instance ?: PlayerController(context.applicationContext).also { instance = it }
        }
    }
}
