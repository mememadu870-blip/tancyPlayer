import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const TancyApp());
}

class TancyColors {
  static const background = Color(0xFF0E0E0E);
  static const surfaceLow = Color(0xFF131313);
  static const surface = Color(0xFF1A1A1A);
  static const surfaceHigh = Color(0xFF262626);
  static const primary = Color(0xFF81ECFF);
  static const primary2 = Color(0xFF00E3FD);
  static const secondary = Color(0xFFFF734A);
  static const text = Colors.white;
  static const textDim = Color(0xFFADAAAA);
  static const outline = Color(0xFF484847);
}

class TancyApp extends StatelessWidget {
  const TancyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'tancyPlayer',
      theme: base.copyWith(
        scaffoldBackgroundColor: TancyColors.background,
        textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
          bodyColor: TancyColors.text,
          displayColor: TancyColors.text,
        ),
        colorScheme: const ColorScheme.dark(
          primary: TancyColors.primary,
          secondary: TancyColors.secondary,
          surface: TancyColors.surface,
          onSurface: TancyColors.text,
        ),
      ),
      home: const TancyHomePage(),
    );
  }
}

class DuplicateGroup {
  final String hash;
  final List<SongModel> songs;

  const DuplicateGroup({required this.hash, required this.songs});
}

enum PlaylistSongSort {
  name,
  size,
  createdTime,
}

enum LibrarySongSort {
  name,
  artist,
  size,
  duration,
  dateAdded,
}

class _HashCacheEntry {
  final int size;
  final int modifiedMs;
  final String hash;
  final String? sampleSignature;

  const _HashCacheEntry({
    required this.size,
    required this.modifiedMs,
    required this.hash,
    this.sampleSignature,
  });

  Map<String, Object> toJson() => {
        'size': size,
        'modifiedMs': modifiedMs,
        'hash': hash,
        if (sampleSignature != null) 'sampleSignature': sampleSignature!,
      };

  static _HashCacheEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final size = raw['size'];
    final modifiedMs = raw['modifiedMs'];
    final hash = raw['hash'];
    final sampleSignature = raw['sampleSignature'];
    if (size is! int || modifiedMs is! int || hash is! String) return null;
    return _HashCacheEntry(
      size: size,
      modifiedMs: modifiedMs,
      hash: hash,
      sampleSignature: sampleSignature is String ? sampleSignature : null,
    );
  }
}

class SongDetails {
  final SongModel song;
  final bool exists;
  final int size;
  final String path;
  final String fileName;
  final String format;
  final String hash;
  final String quality;
  final String estimatedBitrate;
  final DateTime? modifiedAt;

  const SongDetails({
    required this.song,
    required this.exists,
    required this.size,
    required this.path,
    required this.fileName,
    required this.format,
    required this.hash,
    required this.quality,
    required this.estimatedBitrate,
    required this.modifiedAt,
  });
}

class PlayerStore extends ChangeNotifier {
  static const _kFavorites = 'favorites';
  static const _kPlaylists = 'playlists';
  static const _kNotifControl = 'notif_control';
  static const _kTimerEnabled = 'timer_enabled';
  static const _kTimerMinutes = 'timer_minutes';
  static const _kStopAfterSong = 'stop_after_song';
  static const _kMinDurationSec = 'min_duration_sec';
  static const _kHashCache = 'hash_cache_v2';
  static const _kAudioTypes = 'audio_types';

  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _player = AudioPlayer();

  List<SongModel> songs = [];
  Set<int> favorites = <int>{};
  Map<String, List<int>> playlists = <String, List<int>>{};
  List<DuplicateGroup> duplicateGroups = [];

  int? currentSongId;
  bool loading = false;
  bool duplicateScanning = false;
  int sleepTimerSeconds = 0;
  bool showNotificationControl = true;
  bool timerEnabled = false;
  int timerMinutes = 30;
  bool stopAfterCurrentSong = false;
  int minDurationSeconds = 30;
  Set<String> selectedAudioTypes = <String>{};
  List<String> availableAudioTypes = <String>[];
  LoopMode loopMode = LoopMode.all;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  Timer? _sleepTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<PlayerState>? _stateSub;
  SharedPreferences? _prefs;
  bool _manualIndexChange = false;
  final Map<String, _HashCacheEntry> _hashCache = <String, _HashCacheEntry>{};
  String? _externalTitle;
  String? _externalSubtitle;

  String get currentTitle {
    final song = currentSong;
    if (song != null && song.title.isNotEmpty) return song.title;
    return _externalTitle ?? '未选择歌曲';
  }

  String get currentArtist {
    final song = currentSong;
    if (song?.artist?.isNotEmpty == true) return song!.artist!;
    return _externalSubtitle ?? 'Unknown Artist';
  }

  SongModel? get currentSong {
    if (currentSongId == null) return null;
    for (final s in songs) {
      if (s.id == currentSongId) return s;
    }
    return null;
  }

  bool get isPlaying => _player.playing;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    favorites = (_prefs?.getStringList(_kFavorites) ?? [])
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .toSet();

    final raw = _prefs?.getString(_kPlaylists);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      playlists = decoded.map((k, v) {
        final ids = (v as List).map((e) => e as int).toList();
        return MapEntry(k, ids);
      });
    }
    showNotificationControl = _prefs?.getBool(_kNotifControl) ?? true;
    timerEnabled = _prefs?.getBool(_kTimerEnabled) ?? false;
    timerMinutes = _prefs?.getInt(_kTimerMinutes) ?? 30;
    stopAfterCurrentSong = _prefs?.getBool(_kStopAfterSong) ?? false;
    minDurationSeconds = _prefs?.getInt(_kMinDurationSec) ?? 30;
    selectedAudioTypes =
        (_prefs?.getStringList(_kAudioTypes) ?? const <String>[])
            .map((type) => type.toLowerCase())
            .toSet();
    _loadHashCache();

    await _preparePlayerStreams();
    await scanSongs();
  }

  Future<void> _preparePlayerStreams() async {
    await _player.setLoopMode(loopMode);
    _posSub = _player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });
    _durSub = _player.durationStream.listen((d) {
      duration = d ?? Duration.zero;
      notifyListeners();
    });
    _indexSub = _player.currentIndexStream.listen((idx) {
      if (idx == null || idx < 0 || idx >= songs.length) return;
      if (stopAfterCurrentSong && !_manualIndexChange && _player.playing) {
        _player.pause();
        timerEnabled = false;
        _sleepTimer?.cancel();
        sleepTimerSeconds = 0;
      }
      currentSongId = songs[idx].id;
      _manualIndexChange = false;
      notifyListeners();
    });
    _stateSub = _player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed &&
          stopAfterCurrentSong) {
        await _player.pause();
        timerEnabled = false;
        _sleepTimer?.cancel();
        sleepTimerSeconds = 0;
        notifyListeners();
      }
    });
    _applySleepTimer();
  }

  Future<void> scanSongs() async {
    loading = true;
    notifyListeners();

    bool permission = await _audioQuery.permissionsStatus();
    if (!permission) {
      permission = await _audioQuery.permissionsRequest();
    }
    if (!permission) {
      loading = false;
      notifyListeners();
      return;
    }

    final queried = await _audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    availableAudioTypes = queried
        .map((song) => _fileExtension(song.data).toLowerCase())
        .where((type) => type.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    songs = queried.where((s) {
      final d = s.duration ?? 0;
      final type = _fileExtension(s.data).toLowerCase();
      final matchesType =
          selectedAudioTypes.isEmpty || selectedAudioTypes.contains(type);
      return d >= minDurationSeconds * 1000 && matchesType;
    }).toList(growable: true);

    await _resetAudioSources(
        keepSongId: currentSongId, keepPosition: Duration.zero);

    loading = false;
    notifyListeners();
  }

  Future<void> playById(int songId) async {
    final idx = songs.indexWhere((s) => s.id == songId);
    if (idx < 0) return;
    _manualIndexChange = true;
    await _player.seek(Duration.zero, index: idx);
    await _player.play();
    currentSongId = songId;
    _externalTitle = null;
    _externalSubtitle = null;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> next() async {
    _manualIndexChange = true;
    await _player.seekToNext();
    await _player.play();
  }

  Future<void> previous() async {
    _manualIndexChange = true;
    await _player.seekToPrevious();
    await _player.play();
  }

  Future<void> seek(double v) async {
    await _player.seek(Duration(milliseconds: v.toInt()));
  }

  Future<void> setRepeatMode(LoopMode mode) async {
    loopMode = mode;
    await _player.setLoopMode(mode);
    notifyListeners();
  }

  Future<void> toggleFavorite(int songId) async {
    if (favorites.contains(songId)) {
      favorites.remove(songId);
    } else {
      favorites.add(songId);
    }
    await _prefs?.setStringList(
        _kFavorites, favorites.map((e) => e.toString()).toList());
    notifyListeners();
  }

  Future<void> createPlaylist(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    playlists.putIfAbsent(trimmed, () => <int>[]);
    await _persistPlaylists();
    notifyListeners();
  }

  Future<void> addToPlaylist(String name, int songId) async {
    final list = playlists.putIfAbsent(name, () => <int>[]);
    if (!list.contains(songId)) {
      list.add(songId);
      await _persistPlaylists();
      notifyListeners();
    }
  }

  List<SongModel> playlistSongs(String name) {
    final ids = playlists[name] ?? const <int>[];
    final byId = <int, SongModel>{for (final s in songs) s.id: s};
    return ids
        .map((id) => byId[id])
        .whereType<SongModel>()
        .toList(growable: false);
  }

  Future<void> removeFromPlaylist(String name, int songId) async {
    final list = playlists[name];
    if (list == null) return;
    list.remove(songId);
    await _persistPlaylists();
    notifyListeners();
  }

  Future<void> deletePlaylist(String name) async {
    playlists.remove(name);
    await _persistPlaylists();
    notifyListeners();
  }

  Future<void> setNotificationControl(bool enabled) async {
    showNotificationControl = enabled;
    await _prefs?.setBool(_kNotifControl, enabled);
    notifyListeners();
  }

  Future<void> setTimerEnabled(bool enabled) async {
    timerEnabled = enabled;
    await _prefs?.setBool(_kTimerEnabled, enabled);
    _applySleepTimer();
    notifyListeners();
  }

  Future<void> setTimerMinutes(double minutes) async {
    timerMinutes = minutes.round().clamp(0, 180);
    await _prefs?.setInt(_kTimerMinutes, timerMinutes);
    if (timerEnabled) {
      _applySleepTimer();
    }
    notifyListeners();
  }

  Future<void> setStopAfterCurrentSong(bool enabled) async {
    stopAfterCurrentSong = enabled;
    await _prefs?.setBool(_kStopAfterSong, enabled);
    notifyListeners();
  }

  Future<void> setMinDurationSeconds(double seconds) async {
    minDurationSeconds = seconds.round().clamp(0, 300);
    await _prefs?.setInt(_kMinDurationSec, minDurationSeconds);
    await scanSongs();
  }

  Future<void> setAudioTypeEnabled(String type, bool enabled) async {
    final normalized = type.toLowerCase();
    if (enabled) {
      selectedAudioTypes.add(normalized);
    } else {
      selectedAudioTypes.remove(normalized);
    }
    await _prefs?.setStringList(
        _kAudioTypes, selectedAudioTypes.toList()..sort());
    await scanSongs();
  }

  Future<void> clearAudioTypeFilter() async {
    selectedAudioTypes.clear();
    await _prefs?.remove(_kAudioTypes);
    await scanSongs();
  }

  Future<void> setAudioTypes(Set<String> types) async {
    selectedAudioTypes = types.map((type) => type.toLowerCase()).toSet();
    await _prefs?.setStringList(
        _kAudioTypes, selectedAudioTypes.toList()..sort());
    await scanSongs();
  }

  Future<void> queueNext(int songId) async {
    final currentIdx = songs.indexWhere((s) => s.id == currentSongId);
    final targetIdx = songs.indexWhere((s) => s.id == songId);
    if (targetIdx < 0) return;
    if (currentIdx < 0) {
      await playById(songId);
      return;
    }
    final song = songs[targetIdx];
    songs.removeAt(targetIdx);
    var insertAt = currentIdx + 1;
    if (targetIdx < insertAt) {
      insertAt -= 1;
    }
    if (insertAt < 0) insertAt = 0;
    if (insertAt > songs.length) insertAt = songs.length;
    songs.insert(insertAt, song);
    final wasPlaying = _player.playing;
    await _resetAudioSources(
      keepSongId: currentSongId,
      keepPosition: position,
      playAfter: wasPlaying,
    );
    notifyListeners();
  }

  Future<bool> playUri(String rawUri) async {
    final uri = Uri.tryParse(rawUri);
    if (uri == null) return false;
    final matchedSong = _matchSongByUri(uri);
    if (matchedSong != null) {
      await playById(matchedSong.id);
      return true;
    }
    try {
      await _player.setAudioSource(AudioSource.uri(uri));
      await _player.play();
      currentSongId = null;
      _externalTitle = _titleFromUri(uri);
      _externalSubtitle = 'Opened from Android';
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteSong(SongModel song) async {
    final path = song.data;
    if (path.isEmpty) return false;
    final file = File(path);
    if (!await file.exists()) return false;
    try {
      await file.delete();
      final deleted = !await file.exists();
      if (!deleted) return false;
      favorites.remove(song.id);
      for (final entry in playlists.entries) {
        entry.value.remove(song.id);
      }
      _hashCache.remove(path);
      await _prefs?.setStringList(
          _kFavorites, favorites.map((e) => e.toString()).toList());
      await _persistPlaylists();
      if (currentSongId == song.id) {
        await _player.stop();
        currentSongId = null;
        _externalTitle = null;
        _externalSubtitle = null;
      }
      await scanSongs();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistPlaylists() async {
    await _prefs?.setString(_kPlaylists, jsonEncode(playlists));
  }

  Future<void> _resetAudioSources({
    int? keepSongId,
    Duration keepPosition = Duration.zero,
    bool playAfter = false,
  }) async {
    final sources = songs
        .map((s) => AudioSource.uri(
            Uri.parse('content://media/external/audio/media/${s.id}')))
        .toList(growable: false);
    if (sources.isEmpty) {
      await _player.stop();
      currentSongId = null;
      _externalTitle = null;
      _externalSubtitle = null;
      return;
    }
    var initialIndex = 0;
    if (keepSongId != null) {
      final matchedIndex = songs.indexWhere((s) => s.id == keepSongId);
      if (matchedIndex >= 0) {
        initialIndex = matchedIndex;
      }
    }
    await _player.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: keepPosition,
    );
    currentSongId = songs[initialIndex].id;
    _externalTitle = null;
    _externalSubtitle = null;
    if (playAfter) {
      await _player.play();
    }
  }

  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes <= 0) {
      sleepTimerSeconds = 0;
      notifyListeners();
      return;
    }
    sleepTimerSeconds = minutes * 60;
    notifyListeners();

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      sleepTimerSeconds -= 1;
      if (sleepTimerSeconds <= 0) {
        timer.cancel();
        sleepTimerSeconds = 0;
        await _player.pause();
      }
      notifyListeners();
    });
  }

  void _applySleepTimer() {
    _sleepTimer?.cancel();
    if (!timerEnabled || timerMinutes <= 0) {
      sleepTimerSeconds = 0;
      return;
    }
    sleepTimerSeconds = timerMinutes * 60;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      sleepTimerSeconds -= 1;
      if (sleepTimerSeconds <= 0) {
        timer.cancel();
        sleepTimerSeconds = 0;
        timerEnabled = false;
        await _prefs?.setBool(_kTimerEnabled, false);
        await _player.pause();
      }
      notifyListeners();
    });
  }

  Future<void> detectDuplicates() async {
    duplicateScanning = true;
    duplicateGroups = [];
    notifyListeners();

    final candidates = <({
      SongModel song,
      File file,
      int size,
      int modifiedMs,
      int durationMs
    })>[];
    for (final s in songs) {
      final path = s.data;
      if (path.isEmpty) continue;
      final file = File(path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      candidates.add((
        song: s,
        file: file,
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
        durationMs: s.duration ?? 0,
      ));
    }

    final sizeGroups = <String,
        List<
            ({
              SongModel song,
              File file,
              int size,
              int modifiedMs,
              int durationMs
            })>>{};
    for (final item in candidates) {
      final key = '${item.size}:${item.durationMs}';
      sizeGroups
          .putIfAbsent(
            key,
            () => <({
              SongModel song,
              File file,
              int size,
              int modifiedMs,
              int durationMs
            })>[],
          )
          .add(item);
    }

    final grouped = <String, List<SongModel>>{};
    for (final sizeGroup
        in sizeGroups.values.where((group) => group.length > 1)) {
      final sampleGroups = <String,
          List<
              ({
                SongModel song,
                File file,
                int size,
                int modifiedMs,
                int durationMs
              })>>{};
      final signatureResults = await _mapInBatches(
        sizeGroup,
        8,
        (item) async => (
          item: item,
          signature: await _quickFileSignature(
            item.file,
            size: item.size,
            modifiedMs: item.modifiedMs,
          ),
        ),
      );
      for (final result in signatureResults) {
        sampleGroups
            .putIfAbsent(
              result.signature,
              () => <({
                SongModel song,
                File file,
                int size,
                int modifiedMs,
                int durationMs
              })>[],
            )
            .add(result.item);
      }
      for (final sampleGroup
          in sampleGroups.values.where((group) => group.length > 1)) {
        final hashResults = await _mapInBatches(
          sampleGroup,
          4,
          (item) async => (
            song: item.song,
            hash: await _sha256File(
              item.file,
              size: item.size,
              modifiedMs: item.modifiedMs,
            ),
          ),
        );
        for (final item in hashResults) {
          grouped.putIfAbsent(item.hash, () => <SongModel>[]).add(item.song);
        }
      }
    }

    duplicateGroups = grouped.entries
        .where((e) => e.value.length > 1)
        .map((e) => DuplicateGroup(hash: e.key, songs: e.value))
        .toList()
      ..sort((a, b) => b.songs.length.compareTo(a.songs.length));

    await _persistHashCache();
    duplicateScanning = false;
    notifyListeners();
  }

  /// 大文件阈值：超过此值使用采样 hash（1MB）
  static const int _largeFileThreshold = 1024 * 1024;

  /// 采样块大小：64KB
  static const int _sampleChunkSize = 64 * 1024;

  Future<String> _sha256File(
    File file, {
    required int size,
    required int modifiedMs,
  }) async {
    final cached = _hashCache[file.path];
    if (cached != null &&
        cached.size == size &&
        cached.modifiedMs == modifiedMs &&
        cached.hash.isNotEmpty) {
      return cached.hash;
    }

    // 大文件用采样 hash，小文件全量
    final String hash;
    if (size > _largeFileThreshold) {
      hash = await _sampledSha256(file, size: size);
    } else {
      final digest = await sha256.bind(file.openRead()).first;
      hash = digest.toString();
    }

    _hashCache[file.path] = _HashCacheEntry(
      size: size,
      modifiedMs: modifiedMs,
      hash: hash,
      sampleSignature: cached?.sampleSignature,
    );
    return hash;
  }

  /// 采样 SHA-256：文件头 + 文件尾 + 大小
  /// 对于大文件能快 10-100 倍，且碰撞概率极低
  Future<String> _sampledSha256(File file, {required int size}) async {
    final raf = await file.open();
    try {
      final headSize = size < _sampleChunkSize ? size : _sampleChunkSize;
      final head = await raf.read(headSize);

      List<int> tail = const <int>[];
      if (size > _sampleChunkSize) {
        await raf.setPosition(size - _sampleChunkSize);
        tail = await raf.read(_sampleChunkSize);
      }

      // 组合：大小 + 头 + 尾
      final combined = <int>[
        ...utf8.encode('$size:'),
        ...head,
        ...tail,
      ];

      final digest = sha256.convert(combined);
      return digest.toString();
    } finally {
      await raf.close();
    }
  }

  Future<String> _quickFileSignature(
    File file, {
    required int size,
    required int modifiedMs,
  }) async {
    final cached = _hashCache[file.path];
    if (cached != null &&
        cached.size == size &&
        cached.modifiedMs == modifiedMs &&
        cached.sampleSignature != null) {
      return cached.sampleSignature!;
    }
    final raf = await file.open();
    try {
      const chunkSize = 64 * 1024;
      final head = await raf.read(size < chunkSize ? size : chunkSize);
      List<int> tail = const <int>[];
      if (size > chunkSize) {
        await raf.setPosition(size > chunkSize ? size - chunkSize : 0);
        tail = await raf.read(size < chunkSize ? size : chunkSize);
      }
      final sampled = <int>[
        ...utf8.encode('$size:$modifiedMs:'),
        ...head,
        ...tail,
      ];
      final signature = md5.convert(sampled).toString();
      _hashCache[file.path] = _HashCacheEntry(
        size: size,
        modifiedMs: modifiedMs,
        hash: cached?.hash ?? '',
        sampleSignature: signature,
      );
      return signature;
    } finally {
      await raf.close();
    }
  }

  Future<List<R>> _mapInBatches<T, R>(
    List<T> items,
    int batchSize,
    Future<R> Function(T item) mapper,
  ) async {
    final results = <R>[];
    for (var start = 0; start < items.length; start += batchSize) {
      final end =
          start + batchSize < items.length ? start + batchSize : items.length;
      final batch = items.sublist(start, end);
      results.addAll(await Future.wait(batch.map(mapper)));
    }
    return results;
  }

  /// 快速构建基础详情（不含 hash），用于 UI 快速显示
  Future<SongDetails> buildSongDetailsQuick(SongModel song) async {
    final file = File(song.data);
    final stat = await file.stat();
    final exists = stat.type == FileSystemEntityType.file;
    final size = exists ? stat.size : 0;
    final bitrate = _estimateBitrate(size, song.duration ?? 0);
    return SongDetails(
      song: song,
      exists: exists,
      size: size,
      path: song.data,
      fileName: _titleFromPath(song.data),
      format: _fileExtension(song.data).toUpperCase(),
      hash: '', // 先空着，后台算
      quality: _qualityLabel(bitrate),
      estimatedBitrate:
          bitrate <= 0 ? 'N/A' : '${bitrate.toStringAsFixed(0)} kbps',
      modifiedAt: exists ? stat.modified : null,
    );
  }

  /// 异步计算 hash，算完后通过回调更新
  Future<String> computeSongHash(SongModel song) async {
    final file = File(song.data);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) return 'N/A';
    final hash = await _sha256File(
      file,
      size: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
    );
    await _persistHashCache();
    return hash;
  }

  void _loadHashCache() {
    final raw = _prefs?.getString(_kHashCache);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      _hashCache
        ..clear()
        ..addEntries(
          decoded.entries
              .map((entry) =>
                  MapEntry(entry.key, _HashCacheEntry.fromJson(entry.value)))
              .where((entry) => entry.value != null)
              .map((entry) => MapEntry(entry.key, entry.value!)),
        );
    } catch (_) {
      _hashCache.clear();
    }
  }

  Future<void> _persistHashCache() async {
    await _prefs?.setString(
      _kHashCache,
      jsonEncode(_hashCache.map((key, value) => MapEntry(key, value.toJson()))),
    );
  }

  SongModel? _matchSongByUri(Uri uri) {
    final id =
        int.tryParse(uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '');
    if (id != null) {
      for (final song in songs) {
        if (song.id == id) return song;
      }
    }
    final normalized = uri.toString().toLowerCase();
    for (final song in songs) {
      if (song.data.toLowerCase() == normalized) return song;
      if (song.data
          .toLowerCase()
          .endsWith(Uri.decodeComponent(uri.path).toLowerCase())) {
        return song;
      }
    }
    return null;
  }

  String _titleFromUri(Uri uri) => _titleFromPath(Uri.decodeComponent(
      uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.toString()));

  String _titleFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (!normalized.contains('/')) return normalized;
    return normalized.split('/').last;
  }

  String _fileExtension(String path) {
    final fileName = _titleFromPath(path);
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1);
  }

  double _estimateBitrate(int sizeBytes, int durationMs) {
    if (sizeBytes <= 0 || durationMs <= 0) return 0;
    return (sizeBytes * 8) / durationMs;
  }

  String _qualityLabel(double bitrateKbps) {
    if (bitrateKbps <= 0) return 'Unknown';
    if (bitrateKbps >= 900) return 'Lossless / Hi-Res';
    if (bitrateKbps >= 320) return 'Very High';
    if (bitrateKbps >= 192) return 'High';
    if (bitrateKbps >= 128) return 'Standard';
    return 'Low';
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _indexSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}

class TancyHomePage extends StatefulWidget {
  const TancyHomePage({super.key});

  @override
  State<TancyHomePage> createState() => _TancyHomePageState();
}

class _TancyHomePageState extends State<TancyHomePage> {
  static const MethodChannel _platform = MethodChannel('tancy_player/system');
  final PlayerStore store = PlayerStore();
  final FocusNode _searchFocus = FocusNode();
  int tab = 2;
  String search = '';
  double _minDurationPreview = -1;
  LibrarySongSort _librarySort = LibrarySongSort.name;

  @override
  void initState() {
    super.initState();
    _wirePlatformChannel();
    store.init().then((_) => _loadInitialAudioIntent());
    store.addListener(_onStore);
  }

  void _onStore() => setState(() {});

  @override
  void dispose() {
    _platform.setMethodCallHandler(null);
    _searchFocus.dispose();
    store.removeListener(_onStore);
    store.dispose();
    super.dispose();
  }

  void _wirePlatformChannel() {
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'audioIntent' && call.arguments is String) {
        await _handleIncomingAudio(call.arguments as String);
      }
      return null;
    });
  }

  Future<void> _loadInitialAudioIntent() async {
    try {
      final uri = await _platform.invokeMethod<String>('getInitialAudioUri');
      if (uri == null || uri.isEmpty) return;
      await _handleIncomingAudio(uri);
    } catch (_) {
      // Ignore platform channel errors and keep app usable.
    }
  }

  Future<void> _handleIncomingAudio(String uri) async {
    final opened = await store.playUri(uri);
    if (!mounted) return;
    if (opened) {
      setState(() => tab = 2);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已打开来自系统的音频文件')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned(
              top: 50, left: -100, right: -100, child: _AmbientGlow()),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                if (store.loading)
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: TancyColors.primary,
                    backgroundColor: Colors.transparent,
                  ),
                Expanded(child: _bodyForTab()),
              ],
            ),
          ),
          if (store.duplicateScanning)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: TancyColors.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('正在计算音频 Hash...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
      backgroundColor: TancyColors.background,
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq_rounded, color: TancyColors.primary),
          const SizedBox(width: 8),
          Text(
            'tancyPlayer',
            style: GoogleFonts.spaceGrotesk(
              color: TancyColors.primary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _openGlobalSearch,
            icon: const Icon(Icons.search_rounded, color: TancyColors.textDim),
          ),
        ],
      ),
    );
  }

  Future<void> _openGlobalSearch() async {
    if (store.songs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可搜索的歌曲，请先扫描音乐')),
      );
      return;
    }
    final picked = await showSearch<SongModel?>(
      context: context,
      delegate: SongSearchDelegate(
        songs: store.songs,
        onSongLongPress: _showSongDetails,
      ),
    );
    if (picked != null) {
      await store.playById(picked.id);
      if (!mounted) return;
      setState(() => tab = 2);
    }
  }

  Widget _bodyForTab() {
    switch (tab) {
      case 0:
        return _libraryPage();
      case 1:
        return _playlistsPage();
      case 2:
        return _playerPage();
      default:
        return _settingsPage();
    }
  }

  Widget _libraryPage() {
    final filtered = store.songs.where((s) {
      if (search.trim().isEmpty) return true;
      final key = search.toLowerCase();
      return s.title.toLowerCase().contains(key) ||
          (s.artist ?? '').toLowerCase().contains(key) ||
          (s.album ?? '').toLowerCase().contains(key);
    }).toList(growable: true)
      ..sort(_librarySortComparator);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 200),
      children: [
        TextField(
          focusNode: _searchFocus,
          onChanged: (v) => setState(() => search = v),
          decoration: InputDecoration(
            hintText: 'Search your library...',
            hintStyle: const TextStyle(color: TancyColors.textDim),
            filled: true,
            fillColor: TancyColors.surfaceHigh,
            prefixIcon:
                const Icon(Icons.search_rounded, color: TancyColors.textDim),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('System Sync',
                      style: GoogleFonts.spaceGrotesk(
                          color: TancyColors.primary,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${store.songs.length} tracks',
                      style: const TextStyle(color: TancyColors.textDim)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Scanning local storage...',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: store.loading ? null : 1,
                minHeight: 6,
                color: TancyColors.primary,
                backgroundColor: TancyColors.outline.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(99),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  _chipBtn('Rescan', Icons.refresh_rounded, store.scanSongs),
                  _chipBtn(
                      'Hash查重', Icons.fingerprint_rounded, _runDuplicateScan),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text('Songs',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 30, fontWeight: FontWeight.w700)),
            const Spacer(),
            _sortDropdown(),
          ],
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          _glassCard(
            child: Text(
              search.trim().isEmpty
                  ? '没有可显示的歌曲，点击 Rescan 扫描本地音频。'
                  : '没有匹配 "$search" 的结果。',
              style: const TextStyle(color: TancyColors.textDim),
            ),
          ),
        for (final s in filtered) _songTile(s),
      ],
    );
  }

  Widget _sortDropdown() {
    return PopupMenuButton<LibrarySongSort>(
      initialValue: _librarySort,
      onSelected: (value) => setState(() => _librarySort = value),
      icon: const Icon(Icons.sort_rounded, color: TancyColors.primary),
      tooltip: '排序方式',
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: LibrarySongSort.name,
          child: Row(
            children: [
              Icon(Icons.text_fields_rounded, size: 20),
              SizedBox(width: 8),
              Text('按名称'),
            ],
          ),
        ),
        PopupMenuItem(
          value: LibrarySongSort.artist,
          child: Row(
            children: [
              Icon(Icons.person_rounded, size: 20),
              SizedBox(width: 8),
              Text('按艺术家'),
            ],
          ),
        ),
        PopupMenuItem(
          value: LibrarySongSort.size,
          child: Row(
            children: [
              Icon(Icons.sd_card_rounded, size: 20),
              SizedBox(width: 8),
              Text('按大小'),
            ],
          ),
        ),
        PopupMenuItem(
          value: LibrarySongSort.duration,
          child: Row(
            children: [
              Icon(Icons.timer_rounded, size: 20),
              SizedBox(width: 8),
              Text('按时长'),
            ],
          ),
        ),
        PopupMenuItem(
          value: LibrarySongSort.dateAdded,
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 20),
              SizedBox(width: 8),
              Text('按添加时间'),
            ],
          ),
        ),
      ],
    );
  }

  int _librarySortComparator(SongModel a, SongModel b) {
    switch (_librarySort) {
      case LibrarySongSort.name:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case LibrarySongSort.artist:
        final aArtist = a.artist?.toLowerCase() ?? '';
        final bArtist = b.artist?.toLowerCase() ?? '';
        final cmp = aArtist.compareTo(bArtist);
        return cmp != 0 ? cmp : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case LibrarySongSort.size:
        final aSize = _fileSizeOf(a);
        final bSize = _fileSizeOf(b);
        final cmp = bSize.compareTo(aSize); // 大文件优先
        return cmp != 0 ? cmp : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case LibrarySongSort.duration:
        final aDur = a.duration ?? 0;
        final bDur = b.duration ?? 0;
        final cmp = bDur.compareTo(aDur); // 长歌优先
        return cmp != 0 ? cmp : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case LibrarySongSort.dateAdded:
        // dateAdded 在 SongModel 中可能没有，用文件修改时间代替
        final aTime = _fileTimeOf(a);
        final bTime = _fileTimeOf(b);
        final cmp = bTime.compareTo(aTime); // 新歌优先
        return cmp != 0 ? cmp : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }
  }

  int _fileSizeOf(SongModel song) {
    try {
      return File(song.data).statSync().size;
    } catch (_) {
      return 0;
    }
  }

  int _fileTimeOf(SongModel song) {
    try {
      return File(song.data).statSync().modified.millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  Widget _playlistsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 200),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
                colors: [Color(0x45FF734A), Color(0x1000E3FD)]),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.favorite_rounded, color: TancyColors.secondary),
                SizedBox(width: 8),
                Text('Curated for you',
                    style: TextStyle(color: TancyColors.textDim))
              ]),
              const SizedBox(height: 8),
              Text('Favorites',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic)),
              Text('${store.favorites.length} Tracks',
                  style: const TextStyle(color: TancyColors.textDim)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Text('Your Playlists',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 30, fontWeight: FontWeight.w700)),
            const Spacer(),
            FilledButton.icon(
              onPressed: _createPlaylistDialog,
              style: FilledButton.styleFrom(
                  backgroundColor: TancyColors.surfaceHigh),
              icon: const Icon(Icons.add_rounded, color: TancyColors.primary),
              label: const Text('Create New'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (store.playlists.isEmpty)
          _glassCard(
              child: const Text('还没有歌单，点击 Create New 创建。',
                  style: TextStyle(color: TancyColors.textDim))),
        ...store.playlists.entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await _openPlaylist(e.key);
                },
                onLongPress: () => _confirmDeletePlaylist(e.key),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: TancyColors.surfaceLow,
                      borderRadius: BorderRadius.circular(18)),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                              colors: [Color(0xFF1B2836), Color(0xFF213E57)]),
                        ),
                        child: const Icon(Icons.playlist_play_rounded,
                            color: TancyColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(e.key,
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 21, fontWeight: FontWeight.w700))),
                      Text('${e.value.length} songs',
                          style: const TextStyle(color: TancyColors.textDim)),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _playerPage() {
    final song = store.currentSong;
    final title = store.currentTitle;
    final artist = store.currentArtist;
    final max = store.duration.inMilliseconds
        .toDouble()
        .clamp(1.0, (1 << 30).toDouble())
        .toDouble();
    final value =
        store.position.inMilliseconds.toDouble().clamp(0.0, max).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 200),
      children: [
        Container(
          height: 360,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: const LinearGradient(colors: [
              Color(0xFF203245),
              Color(0xFF111B29),
              Color(0xFF0E3842)
            ]),
          ),
          child: Stack(
            children: [
              const Center(
                  child: Icon(Icons.album_rounded,
                      size: 110, color: Colors.white70)),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _glassCard(
                  child: Row(
                    children: [
                      const Icon(Icons.equalizer_rounded,
                          color: TancyColors.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('Currently Playing',
                              style: TextStyle(color: TancyColors.textDim))),
                      Text(store.isPlaying ? 'LIVE' : 'PAUSED',
                          style: const TextStyle(color: TancyColors.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoMarqueeText(
                    text: title,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 34, fontWeight: FontWeight.w700),
                  ),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: TancyColors.textDim, fontSize: 18)),
                ],
              ),
            ),
            IconButton(
              onPressed:
                  song == null ? null : () => store.toggleFavorite(song.id),
              icon: Icon(
                song != null && store.favorites.contains(song.id)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: TancyColors.secondary,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: max,
          onChanged: store.seek,
        ),
        Row(
          children: [
            Text(_fmt(store.position),
                style: const TextStyle(color: TancyColors.textDim)),
            const Spacer(),
            Text(_fmt(store.duration),
                style: const TextStyle(color: TancyColors.textDim)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: () => store.setRepeatMode(
                store.loopMode == LoopMode.one
                    ? LoopMode.off
                    : store.loopMode == LoopMode.off
                        ? LoopMode.all
                        : LoopMode.one,
              ),
              icon: Icon(
                  store.loopMode == LoopMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  color: store.loopMode == LoopMode.off
                      ? TancyColors.textDim
                      : TancyColors.primary),
            ),
            IconButton(
                onPressed: store.previous,
                icon: const Icon(Icons.skip_previous_rounded, size: 44)),
            GestureDetector(
              onTap: store.togglePlayPause,
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [TancyColors.primary, TancyColors.primary2]),
                ),
                child: Icon(
                    store.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: const Color(0xFF003840),
                    size: 44),
              ),
            ),
            IconButton(
                onPressed: store.next,
                icon: const Icon(Icons.skip_next_rounded, size: 44)),
            IconButton(
                onPressed: song == null ? null : () => _showSongMenu(song),
                icon: const Icon(Icons.more_vert_rounded,
                    color: TancyColors.textDim)),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _settingsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        Text('Settings',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 52, fontWeight: FontWeight.w700)),
        const Text('Fine-tune your auditory environment.',
            style: TextStyle(color: TancyColors.textDim)),
        const SizedBox(height: 20),
        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: store.timerEnabled,
                onChanged: store.setTimerEnabled,
                title: const Text('启用定时'),
              ),
              Row(
                children: [
                  const Text('0 分钟'),
                  Expanded(
                    child: Slider(
                      value: store.timerMinutes.toDouble(),
                      min: 0,
                      max: 180,
                      divisions: 180,
                      label: '${store.timerMinutes} 分钟',
                      onChanged: store.setTimerMinutes,
                    ),
                  ),
                  const Text('180 分钟'),
                ],
              ),
              Text('当前：${store.timerMinutes} 分钟',
                  style: const TextStyle(color: TancyColors.textDim)),
              CheckboxListTile(
                value: store.stopAfterCurrentSong,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => store.setStopAfterCurrentSong(v ?? false),
                title: const Text('播放完整歌曲后停止'),
              ),
            ],
          ),
        ),
        if (store.timerEnabled && store.sleepTimerSeconds > 0) ...[
          const SizedBox(height: 8),
          Text('剩余 ${store.sleepTimerSeconds}s',
              style: const TextStyle(color: TancyColors.primary)),
        ],
        if (store.stopAfterCurrentSong)
          const Text('已启用：播放完整歌曲后停止',
              style: TextStyle(color: TancyColors.primary)),
        const SizedBox(height: 16),
        SwitchListTile(
          value: store.showNotificationControl,
          onChanged: store.setNotificationControl,
          title: const Text('Show Notification Control'),
          subtitle: const Text('Keep playback actions in status bar',
              style: TextStyle(color: TancyColors.textDim)),
        ),
        ListTile(
          onTap: store.scanSongs,
          leading:
              const Icon(Icons.refresh_rounded, color: TancyColors.primary),
          title: const Text('Rescan Storage'),
          subtitle: const Text('Force indexer to look for new audio files',
              style: TextStyle(color: TancyColors.textDim)),
        ),
        const SizedBox(height: 4),
        ListTile(
          title: const Text('最短音频时长筛选'),
          subtitle: Text('过滤短于 ${store.minDurationSeconds}s 的音频（铃声/系统音）',
              style: const TextStyle(color: TancyColors.textDim)),
        ),
        Slider(
          value: _minDurationPreview >= 0
              ? _minDurationPreview
              : store.minDurationSeconds.toDouble(),
          min: 0,
          max: 300,
          divisions: 60,
          label:
              '${(_minDurationPreview >= 0 ? _minDurationPreview : store.minDurationSeconds.toDouble()).round()}s',
          onChanged: (v) => setState(() => _minDurationPreview = v),
          onChangeEnd: (v) async {
            await store.setMinDurationSeconds(v);
            if (!mounted) return;
            setState(() => _minDurationPreview = -1);
          },
        ),
        const SizedBox(height: 8),
        ListTile(
          title: const Text('音频文件类型筛选'),
          subtitle: Text(
            store.selectedAudioTypes.isEmpty
                ? '当前：全部类型'
                : '当前：${store.selectedAudioTypes.map((type) => type.toUpperCase()).join(', ')}',
            style: const TextStyle(color: TancyColors.textDim),
          ),
          trailing: store.selectedAudioTypes.isEmpty
              ? null
              : TextButton(
                  onPressed: store.clearAudioTypeFilter,
                  child: const Text('清除'),
                ),
        ),
        if (store.availableAudioTypes.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('扫描后会显示可用的音频类型。',
                style: TextStyle(color: TancyColors.textDim)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: store.availableAudioTypes.map((type) {
              final active = store.selectedAudioTypes.isEmpty ||
                  store.selectedAudioTypes.contains(type);
              return FilterChip(
                selected: active,
                label: Text(type.toUpperCase()),
                onSelected: (selected) async {
                  if (store.selectedAudioTypes.isEmpty && !selected) {
                    final next = store.availableAudioTypes
                        .where((item) => item != type)
                        .map((item) => item.toLowerCase())
                        .toSet();
                    await store.setAudioTypes(next);
                    return;
                  }
                  await store.setAudioTypeEnabled(type, selected);
                },
              );
            }).toList(growable: false),
          ),
        const SizedBox(height: 12),
        ListTile(
          onTap: _runDuplicateScan,
          leading:
              const Icon(Icons.fingerprint_rounded, color: TancyColors.primary),
          title: const Text('Duplicate Detection (SHA-256)'),
          subtitle: const Text(
              'Fast scan with size + duration grouping, cached sample signature and cached hash',
              style: TextStyle(color: TancyColors.textDim)),
        ),
        const SizedBox(height: 4),
        ListTile(
          onTap: _openDefaultPlayerSettings,
          leading:
              const Icon(Icons.audio_file_rounded, color: TancyColors.primary),
          title: const Text('注册到系统音频打开方式'),
          subtitle: const Text('打开 Android 默认应用设置，选择 tancyPlayer 作为音频打开方式',
              style: TextStyle(color: TancyColors.textDim)),
        ),
      ],
    );
  }

  Widget _songTile(SongModel s) {
    final liked = store.favorites.contains(s.id);
    final active = store.currentSongId == s.id;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        HapticFeedback.selectionClick();
        await store.playById(s.id);
      },
      onLongPress: () => _showSongDetails(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? const Color(0x2238D9B7) : TancyColors.surfaceLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF192A3D), Color(0xFF0E5B66)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.music_note_rounded, color: Colors.white70),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(
                      s.artist?.isNotEmpty == true
                          ? s.artist!
                          : 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: TancyColors.textDim)),
                ],
              ),
            ),
            Text(_fmt(Duration(milliseconds: s.duration ?? 0)),
                style: const TextStyle(color: TancyColors.textDim)),
            IconButton(
              onPressed: () => store.toggleFavorite(s.id),
              icon: Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liked ? TancyColors.secondary : TancyColors.textDim),
            ),
            IconButton(
              onPressed: () => _showSongMenu(s),
              icon: const Icon(Icons.more_horiz_rounded,
                  color: TancyColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomNav() {
    const items = [
      (Icons.library_music_rounded, 'Library'),
      (Icons.playlist_play_rounded, 'Playlists'),
      (Icons.play_circle_rounded, 'Player'),
      (Icons.settings_rounded, 'Settings'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
      decoration: BoxDecoration(
        color: TancyColors.surfaceHigh.withValues(alpha: 0.75),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28), topRight: Radius.circular(28)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final active = tab == i;
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => tab = i);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? TancyColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(items[i].$1,
                      color: active
                          ? const Color(0xFF003840)
                          : TancyColors.textDim,
                      size: 22),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$2,
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        color: active
                            ? const Color(0xFF003840)
                            : TancyColors.textDim,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TancyColors.surfaceHigh.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _chipBtn(String label, IconData icon, Future<void> Function() onTap) {
    return InkWell(
      onTap: () async {
        HapticFeedback.lightImpact();
        await onTap();
      },
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: TancyColors.surfaceHigh,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: TancyColors.primary, size: 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }

  Future<void> _createPlaylistDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: TancyColors.surface,
        title: const Text('创建歌单'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '例如：夜间通勤'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              await store.createPlaylist(name);
              if (!mounted) return;
              Navigator.pop(context);
              if (name.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已创建歌单：$name')),
                );
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _addToPlaylistSheet(int songId) async {
    if (store.playlists.isEmpty) {
      await _createPlaylistDialog();
      if (store.playlists.isEmpty) return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: TancyColors.surface,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('加入歌单')),
            ...store.playlists.keys.map(
              (name) => ListTile(
                title: Text(name),
                trailing: const Icon(Icons.playlist_add_rounded,
                    color: TancyColors.primary),
                onTap: () async {
                  await store.addToPlaylist(name, songId);
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已加入歌单：$name')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSongMenu(SongModel song, {String? playlistName}) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: TancyColors.surface,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(song.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(song.artist ?? 'Unknown Artist',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded,
                  color: TancyColors.primary),
              title: const Text('下一首播放'),
              onTap: () async {
                Navigator.pop(context);
                await store.queueNext(song.id);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已加入下一首：${song.title}')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded,
                  color: TancyColors.primary),
              title: const Text('加入歌单'),
              onTap: () async {
                Navigator.pop(context);
                await _addToPlaylistSheet(song.id);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.send_rounded, color: TancyColors.primary),
              title: const Text('发送到'),
              onTap: () async {
                Navigator.pop(context);
                final shared = await _shareSong(song);
                if (!mounted || shared) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('发送失败，文件可能已不存在')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded,
                  color: TancyColors.primary),
              title: const Text('显示更多详情'),
              onTap: () async {
                Navigator.pop(context);
                await _showSongDetails(song);
              },
            ),
            if (playlistName != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded,
                    color: TancyColors.secondary),
                title: const Text('从当前歌单移除'),
                onTap: () async {
                  Navigator.pop(context);
                  await store.removeFromPlaylist(playlistName, song.id);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已从歌单移除')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _runDuplicateScan() async {
    await store.detectDuplicates();
    if (!mounted) return;
    if (store.duplicateGroups.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未发现重复音频')));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TancyColors.background,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (_, ctrl) => Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: ListView(
            controller: ctrl,
            children: [
              Text('Duplicate Songs Detected',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Verification Method: SHA-256 Hash',
                  style: TextStyle(color: TancyColors.textDim)),
              const SizedBox(height: 16),
              for (final g in store.duplicateGroups.take(30))
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TancyColors.surfaceLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hash: ${g.hash.substring(0, 10)}...',
                          style: const TextStyle(
                              color: TancyColors.textDim, fontSize: 12)),
                      const SizedBox(height: 8),
                      ...g.songs.map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.music_note_rounded,
                                  size: 14, color: TancyColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(s.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPlaylist(String name) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailPage(
          store: store,
          name: name,
          onSongLongPress: _showSongDetails,
          onSongMenu: _showSongMenu,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeletePlaylist(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: TancyColors.surface,
        title: const Text('删除歌单'),
        content: Text('确认删除歌单「$name」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                FilledButton.styleFrom(backgroundColor: TancyColors.secondary),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.deletePlaylist(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除歌单：$name')),
      );
    }
  }

  Future<void> _showSongDetails(SongModel song) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SongDetailPage(store: store, song: song),
      ),
    );
    if (!mounted || deleted != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除：${song.title}')),
    );
  }

  Future<void> _openDefaultPlayerSettings() async {
    try {
      await _platform.invokeMethod<void>('openDefaultAppsSettings');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开系统设置')),
      );
    }
  }

  Future<bool> _shareSong(SongModel song) async {
    final path = song.data;
    if (path.isEmpty) return false;
    final file = File(path);
    if (!await file.exists()) return false;
    try {
      await _platform.invokeMethod<void>('shareAudio', {
        'path': path,
        'title': song.title,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  String _fmt(Duration d) {
    final sec = d.inSeconds;
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }
}

class PlaylistDetailPage extends StatefulWidget {
  final PlayerStore store;
  final String name;
  final Future<void> Function(SongModel song) onSongLongPress;
  final Future<void> Function(SongModel song, {String? playlistName})
      onSongMenu;

  const PlaylistDetailPage({
    super.key,
    required this.store,
    required this.name,
    required this.onSongLongPress,
    required this.onSongMenu,
  });

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  PlaylistSongSort _sort = PlaylistSongSort.name;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.store.playlistSongs(widget.name).toList(growable: true)
      ..sort(_songComparator);
    return Scaffold(
      backgroundColor: TancyColors.background,
      appBar: AppBar(
        backgroundColor: TancyColors.background,
        title: Text(widget.name),
        actions: [
          PopupMenuButton<PlaylistSongSort>(
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: PlaylistSongSort.name,
                child: Text('按名称排序'),
              ),
              PopupMenuItem(
                value: PlaylistSongSort.size,
                child: Text('按大小排序'),
              ),
              PopupMenuItem(
                value: PlaylistSongSort.createdTime,
                child: Text('按创建时间排序'),
              ),
            ],
            icon: const Icon(Icons.sort_rounded, color: TancyColors.primary),
          ),
          IconButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: TancyColors.surface,
                  title: const Text('删除歌单'),
                  content: Text('确认删除歌单「${widget.name}」吗？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                      onPressed: () async {
                        await widget.store.deletePlaylist(widget.name);
                        if (!context.mounted) return;
                        Navigator.pop(context); // close confirm
                        Navigator.pop(context); // close detail page
                      },
                      style: FilledButton.styleFrom(
                          backgroundColor: TancyColors.secondary),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
            },
            icon:
                const Icon(Icons.delete_rounded, color: TancyColors.secondary),
          ),
        ],
      ),
      body: songs.isEmpty
          ? const Center(
              child: Text('歌单为空', style: TextStyle(color: TancyColors.textDim)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: TancyColors.surfaceLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text('共 ${songs.length} 首',
                          style: const TextStyle(color: TancyColors.textDim)),
                      const Spacer(),
                      Text(_sortLabel(_sort),
                          style: const TextStyle(color: TancyColors.textDim)),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          await widget.store.playById(songs.first.id);
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('播放全部'),
                      ),
                    ],
                  ),
                ),
                ...songs.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        tileColor: TancyColors.surfaceLow,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        title: Text(s.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          s.artist?.isNotEmpty == true
                              ? s.artist!
                              : 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => widget.store.playById(s.id),
                        onLongPress: () => widget.onSongLongPress(s),
                        trailing: IconButton(
                          onPressed: () =>
                              widget.onSongMenu(s, playlistName: widget.name),
                          icon: const Icon(Icons.more_horiz_rounded,
                              color: TancyColors.primary),
                        ),
                      ),
                    )),
              ],
            ),
    );
  }

  int _songComparator(SongModel a, SongModel b) {
    switch (_sort) {
      case PlaylistSongSort.name:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case PlaylistSongSort.size:
        return _fileSizeOf(b).compareTo(_fileSizeOf(a));
      case PlaylistSongSort.createdTime:
        return _fileTimeOf(b).compareTo(_fileTimeOf(a));
    }
  }

  int _fileSizeOf(SongModel song) {
    try {
      return File(song.data).statSync().size;
    } catch (_) {
      return 0;
    }
  }

  int _fileTimeOf(SongModel song) {
    try {
      return File(song.data).statSync().changed.millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  String _sortLabel(PlaylistSongSort sort) {
    switch (sort) {
      case PlaylistSongSort.name:
        return '名称';
      case PlaylistSongSort.size:
        return '大小';
      case PlaylistSongSort.createdTime:
        return '创建时间';
    }
  }
}

class SongDetailPage extends StatefulWidget {
  final PlayerStore store;
  final SongModel song;

  const SongDetailPage({
    super.key,
    required this.store,
    required this.song,
  });

  @override
  State<SongDetailPage> createState() => _SongDetailPageState();
}

class _SongDetailPageState extends State<SongDetailPage> {
  SongDetails? _details;
  bool _loading = true;
  bool _hashLoading = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 快速加载基础信息（不含 hash）
    final details = await widget.store.buildSongDetailsQuick(widget.song);
    if (!mounted) return;
    setState(() {
      _details = details;
      _loading = false;
      _hashLoading = true;
    });

    // 后台计算 hash
    final hash = await widget.store.computeSongHash(widget.song);
    if (!mounted) return;
    setState(() {
      _details = SongDetails(
        song: details.song,
        exists: details.exists,
        size: details.size,
        path: details.path,
        fileName: details.fileName,
        format: details.format,
        hash: hash,
        quality: details.quality,
        estimatedBitrate: details.estimatedBitrate,
        modifiedAt: details.modifiedAt,
      );
      _hashLoading = false;
    });
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: TancyColors.surface,
        title: const Text('删除音频文件'),
        content: Text('确认删除「${widget.song.title}」吗？此操作会同时从库和歌单中移除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                FilledButton.styleFrom(backgroundColor: TancyColors.secondary),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deleting = true);
    final deleted = await widget.store.deleteSong(widget.song);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (deleted) {
      Navigator.pop(context, true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('删除失败，系统可能未授予文件删除权限')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    return Scaffold(
      backgroundColor: TancyColors.background,
      appBar: AppBar(
        backgroundColor: TancyColors.background,
        title: const Text('音频详情'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            onPressed: _deleting ? null : _confirmDelete,
            icon:
                const Icon(Icons.delete_rounded, color: TancyColors.secondary),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: TancyColors.surfaceLow,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                              colors: [Color(0xFF192A3D), Color(0xFF0E5B66)]),
                        ),
                        child: const Icon(Icons.library_music_rounded,
                            color: Colors.white, size: 34),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.song.title,
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 24, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(widget.song.artist ?? 'Unknown Artist',
                                style: const TextStyle(
                                    color: TancyColors.textDim)),
                            const SizedBox(height: 4),
                            Text(
                                '${details?.quality ?? 'Unknown'}  ${details?.estimatedBitrate ?? 'N/A'}',
                                style: const TextStyle(
                                    color: TancyColors.primary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _detailCard('文件名', details?.fileName ?? 'N/A'),
                _detailCard(
                    '格式',
                    (details?.format.isNotEmpty ?? false)
                        ? details!.format
                        : 'Unknown'),
                _detailCard('质量', details?.quality ?? 'Unknown'),
                _detailCard('估算码率', details?.estimatedBitrate ?? 'N/A'),
                _detailCard('时长',
                    '${((widget.song.duration ?? 0) / 1000).toStringAsFixed(1)} 秒'),
                _detailCard(
                    '大小',
                    details == null || !details.exists
                        ? 'N/A'
                        : '${(details.size / 1024 / 1024).toStringAsFixed(2)} MB'),
                _detailCard('路径', details?.path ?? 'N/A'),
                _detailCard(
                    '修改时间', details?.modifiedAt?.toLocal().toString() ?? 'N/A'),
                // Hash 单独处理：计算中显示 loading
                _hashDetailCard(),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: details == null
                          ? null
                          : () => _copy(details.path, '已复制文件路径'),
                      icon: const Icon(Icons.content_copy_rounded),
                      label: const Text('复制路径'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: details == null ||
                              details.hash.isEmpty ||
                              _hashLoading
                          ? null
                          : () => _copy(details.hash, '已复制 Hash'),
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('复制 Hash'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _hashDetailCard() {
    if (_hashLoading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TancyColors.surfaceLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            const Text('正在计算 SHA-256...',
                style: TextStyle(color: TancyColors.textDim)),
          ],
        ),
      );
    }
    return _detailCard('SHA-256', _details?.hash.isEmpty ?? true ? 'N/A' : _details!.hash);
  }

  Widget _detailCard(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TancyColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: TancyColors.textDim)),
          const SizedBox(height: 6),
          SelectableText(value),
        ],
      ),
    );
  }
}

class AutoMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const AutoMarqueeText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  State<AutoMarqueeText> createState() => _AutoMarqueeTextState();
}

class _AutoMarqueeTextState extends State<AutoMarqueeText> {
  bool _forward = true;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final textWidth = painter.width;
        final maxWidth = constraints.maxWidth;
        final overflow = (textWidth - maxWidth).clamp(0.0, 10000.0);
        if (overflow <= 0) {
          return Text(widget.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.style);
        }
        return ClipRect(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(
                begin: _forward ? 0 : -overflow, end: _forward ? -overflow : 0),
            duration: const Duration(seconds: 8),
            onEnd: () {
              if (!mounted) return;
              setState(() => _forward = !_forward);
            },
            builder: (_, value, child) =>
                Transform.translate(offset: Offset(value, 0), child: child),
            child: Text(widget.text, maxLines: 1, style: widget.style),
          ),
        );
      },
    );
  }
}

class SongSearchDelegate extends SearchDelegate<SongModel?> {
  final List<SongModel> songs;
  final Future<void> Function(SongModel song) onSongLongPress;

  SongSearchDelegate({
    required this.songs,
    required this.onSongLongPress,
  });

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: TancyColors.background,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: TancyColors.textDim),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () => query = '',
        icon: const Icon(Icons.close_rounded),
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }

  List<SongModel> _filtered() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return songs.take(40).toList(growable: false);
    return songs.where((s) {
      return s.title.toLowerCase().contains(q) ||
          (s.artist ?? '').toLowerCase().contains(q) ||
          (s.album ?? '').toLowerCase().contains(q);
    }).toList(growable: false);
  }

  @override
  Widget buildResults(BuildContext context) {
    final data = _filtered();
    if (data.isEmpty) {
      return const Center(
          child: Text('没有匹配结果', style: TextStyle(color: TancyColors.textDim)));
    }
    return ListView.builder(
      itemCount: data.length,
      itemBuilder: (_, i) {
        final s = data[i];
        return ListTile(
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(s.artist ?? 'Unknown Artist',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => close(context, s),
          onLongPress: () => onSongLongPress(s),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return buildResults(context);
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: 260,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Color(0x3381ECFF), blurRadius: 160, spreadRadius: 18)
          ],
        ),
      ),
    );
  }
}
