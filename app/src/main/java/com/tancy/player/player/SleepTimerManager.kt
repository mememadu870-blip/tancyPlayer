package com.tancy.player.player

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class SleepTimerManager {
    private var timerJob: Job? = null
    private val _remainingSeconds = MutableStateFlow(0)
    val remainingSeconds: StateFlow<Int> = _remainingSeconds

    fun start(minutes: Int, onTimeout: () -> Unit) {
        timerJob?.cancel()
        val totalSeconds = minutes * 60
        _remainingSeconds.value = totalSeconds
        timerJob = CoroutineScope(Dispatchers.Main.immediate).launch {
            while (_remainingSeconds.value > 0) {
                delay(1000)
                _remainingSeconds.value -= 1
            }
            onTimeout()
        }
    }

    fun stop() {
        timerJob?.cancel()
        timerJob = null
        _remainingSeconds.value = 0
    }
}
