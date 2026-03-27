package com.tancy.player.data

import java.io.InputStream
import java.security.MessageDigest

object HashUtils {
    fun sha256(input: InputStream?): String? {
        if (input == null) return null
        return runCatching {
            val digest = MessageDigest.getInstance("SHA-256")
            input.buffered().use { stream ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val bytes = stream.read(buffer)
                    if (bytes <= 0) break
                    digest.update(buffer, 0, bytes)
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        }.getOrNull()
    }
}
