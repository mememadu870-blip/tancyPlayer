package com.tancy.player

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.tancy.player.ui.MainViewModel
import com.tancy.player.ui.RepeatMode

class MainActivity : ComponentActivity() {
    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                val uiState by viewModel.uiState.collectAsState()
                val permissionLauncher = rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.RequestMultiplePermissions(),
                    onResult = { result ->
                        val hasAudioPermission = if (Build.VERSION.SDK_INT >= 33) {
                            result[Manifest.permission.READ_MEDIA_AUDIO] == true
                        } else {
                            result[Manifest.permission.READ_EXTERNAL_STORAGE] == true
                        }
                        if (hasAudioPermission) {
                            viewModel.scanMusicFiles()
                        }
                    }
                )
                val permissions = if (Build.VERSION.SDK_INT >= 33) {
                    arrayOf(
                        Manifest.permission.READ_MEDIA_AUDIO,
                        Manifest.permission.POST_NOTIFICATIONS
                    )
                } else {
                    arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
                }

                LaunchedEffect(Unit) {
                    permissionLauncher.launch(permissions)
                }

                MainScreen(
                    uiState = uiState,
                    onScan = { permissionLauncher.launch(permissions) },
                    onPlay = viewModel::play,
                    onTogglePlayPause = viewModel::togglePlayPause,
                    onPrevious = viewModel::previous,
                    onNext = viewModel::next,
                    onToggleFavorite = viewModel::toggleFavorite,
                    onCreatePlaylist = viewModel::createPlaylist,
                    onSelectPlaylist = viewModel::choosePlaylist,
                    onAddTrackToPlaylist = viewModel::addTrackToSelectedPlaylist,
                    onSleepTimer = viewModel::setSleepTimer,
                    onSetRepeat = viewModel::setRepeatMode,
                    onSeekTo = viewModel::seekTo,
                    onDetectDuplicate = viewModel::detectDuplicatesByHash,
                    onDismissDuplicates = viewModel::clearDuplicateResult
                )
            }
        }
    }
}

@Composable
private fun MainScreen(
    uiState: com.tancy.player.ui.MainUiState,
    onScan: () -> Unit,
    onPlay: (Long) -> Unit,
    onTogglePlayPause: () -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onToggleFavorite: (Long) -> Unit,
    onCreatePlaylist: (String) -> Unit,
    onSelectPlaylist: (Long?) -> Unit,
    onAddTrackToPlaylist: (Long) -> Unit,
    onSleepTimer: (Int) -> Unit,
    onSetRepeat: (RepeatMode) -> Unit,
    onSeekTo: (Long) -> Unit,
    onDetectDuplicate: () -> Unit,
    onDismissDuplicates: () -> Unit
) {
    var playlistName by rememberSaveable { mutableStateOf("") }
    var playlistMenuExpanded by remember { mutableStateOf(false) }

    Scaffold(modifier = Modifier.fillMaxSize()) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("Tancy Player", style = MaterialTheme.typography.headlineMedium)
            Text("歌曲数: ${uiState.tracks.size} | 扫描中: ${if (uiState.isScanning) "是" else "否"}")
            Text("当前播放: ${uiState.nowPlayingTrackId ?: "无"} | 状态: ${if (uiState.isPlaying) "播放中" else "暂停"}")
            Text("睡眠定时剩余: ${uiState.sleepTimerRemainingSeconds}s")
            Text("进度: ${formatDuration(uiState.playbackPositionMs)} / ${formatDuration(uiState.playbackDurationMs)}")
            Slider(
                value = uiState.playbackPositionMs.toFloat(),
                onValueChange = { onSeekTo(it.toLong()) },
                valueRange = 0f..(uiState.playbackDurationMs.coerceAtLeast(1L).toFloat())
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                Button(onClick = onScan) { Text("扫描音乐") }
                Button(onClick = onDetectDuplicate) { Text("Hash查重") }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                Button(onClick = onPrevious) { Text("上一首") }
                Button(onClick = onTogglePlayPause) { Text("播放/暂停") }
                Button(onClick = onNext) { Text("下一首") }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                Button(onClick = { onSleepTimer(15) }) { Text("15分钟停") }
                Button(onClick = { onSleepTimer(30) }) { Text("30分钟停") }
                Button(onClick = { onSleepTimer(0) }) { Text("取消定时") }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                Button(onClick = { onSetRepeat(RepeatMode.NONE) }) { Text("不重复") }
                Button(onClick = { onSetRepeat(RepeatMode.ONE) }) { Text("单曲循环") }
                Button(onClick = { onSetRepeat(RepeatMode.ALL) }) { Text("列表循环") }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = playlistName,
                    onValueChange = { playlistName = it },
                    label = { Text("新歌单名") },
                    modifier = Modifier.weight(1f)
                )
                Button(
                    onClick = {
                        onCreatePlaylist(playlistName)
                        playlistName = ""
                    }
                ) { Text("创建") }
            }

            Button(onClick = { playlistMenuExpanded = true }) {
                val selectedName = uiState.playlists.firstOrNull { it.id == uiState.selectedPlaylistId }?.name ?: "选择歌单"
                Text(selectedName)
            }
            DropdownMenu(expanded = playlistMenuExpanded, onDismissRequest = { playlistMenuExpanded = false }) {
                DropdownMenuItem(
                    text = { Text("不选择") },
                    onClick = {
                        onSelectPlaylist(null)
                        playlistMenuExpanded = false
                    }
                )
                uiState.playlists.forEach { playlist ->
                    DropdownMenuItem(
                        text = { Text("${playlist.name} (${playlist.trackIds.size})") },
                        onClick = {
                            onSelectPlaylist(playlist.id)
                            playlistMenuExpanded = false
                        }
                    )
                }
            }

            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(uiState.tracks, key = { it.id }) { track ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(track.title, style = MaterialTheme.typography.titleMedium)
                            Text(track.artist, style = MaterialTheme.typography.bodySmall)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Button(onClick = { onPlay(track.id) }) { Text("播放") }
                                Button(onClick = { onToggleFavorite(track.id) }) {
                                    Text(if (track.id in uiState.favoriteTrackIds) "取消收藏" else "收藏")
                                }
                                Button(onClick = { onAddTrackToPlaylist(track.id) }) {
                                    Text("加到选中歌单")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (uiState.duplicateGroups.isNotEmpty()) {
        AlertDialog(
            onDismissRequest = onDismissDuplicates,
            title = { Text("发现重复音频") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("重复组数量: ${uiState.duplicateGroups.size}")
                    uiState.duplicateGroups.take(5).forEachIndexed { idx, group ->
                        Text("${idx + 1}. ${group.firstOrNull()?.title ?: "Unknown"} 等 ${group.size} 首")
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = onDismissDuplicates) { Text("知道了") }
            }
        )
    }
}

private fun formatDuration(ms: Long): String {
    val totalSec = (ms / 1000L).coerceAtLeast(0)
    val min = totalSec / 60
    val sec = totalSec % 60
    return "%02d:%02d".format(min, sec)
}
