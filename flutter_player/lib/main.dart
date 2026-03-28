import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
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

class PlayerStore extends ChangeNotifier {
  static const _kFavorites = 'favorites';
  static const _kPlaylists = 'playlists';
  static const _kNotifControl = 'notif_control';

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
  LoopMode loopMode = LoopMode.all;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  Timer? _sleepTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<int?>? _indexSub;
  SharedPreferences? _prefs;

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
      currentSongId = songs[idx].id;
      notifyListeners();
    });
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

    songs = await _audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final sources = songs
        .map((s) => AudioSource.uri(Uri.parse('content://media/external/audio/media/${s.id}')))
        .toList(growable: false);

    if (sources.isNotEmpty) {
      await _player.setAudioSource(ConcatenatingAudioSource(children: sources));
      currentSongId ??= songs.first.id;
    } else {
      await _player.stop();
      currentSongId = null;
    }

    loading = false;
    notifyListeners();
  }

  Future<void> playById(int songId) async {
    final idx = songs.indexWhere((s) => s.id == songId);
    if (idx < 0) return;
    await _player.seek(Duration.zero, index: idx);
    await _player.play();
    currentSongId = songId;
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
    await _player.seekToNext();
    await _player.play();
  }

  Future<void> previous() async {
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
    await _prefs?.setStringList(_kFavorites, favorites.map((e) => e.toString()).toList());
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

  Future<void> setNotificationControl(bool enabled) async {
    showNotificationControl = enabled;
    await _prefs?.setBool(_kNotifControl, enabled);
    notifyListeners();
  }

  Future<void> _persistPlaylists() async {
    await _prefs?.setString(_kPlaylists, jsonEncode(playlists));
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

  Future<void> detectDuplicates() async {
    duplicateScanning = true;
    duplicateGroups = [];
    notifyListeners();

    final grouped = <String, List<SongModel>>{};
    for (final s in songs) {
      final path = s.data;
      if (path.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final hash = await _sha256File(file);
      grouped.putIfAbsent(hash, () => <SongModel>[]).add(s);
    }

    duplicateGroups = grouped.entries
        .where((e) => e.value.length > 1)
        .map((e) => DuplicateGroup(hash: e.key, songs: e.value))
        .toList()
      ..sort((a, b) => b.songs.length.compareTo(a.songs.length));

    duplicateScanning = false;
    notifyListeners();
  }

  Future<String> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _indexSub?.cancel();
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
  final PlayerStore store = PlayerStore();
  int tab = 2;
  String search = '';

  @override
  void initState() {
    super.initState();
    store.init();
    store.addListener(_onStore);
  }

  void _onStore() => setState(() {});

  @override
  void dispose() {
    store.removeListener(_onStore);
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned(top: 50, left: -100, right: -100, child: _AmbientGlow()),
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
          if (tab != 2) _miniNowPlaying(),
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
            onPressed: () {},
            icon: const Icon(Icons.search_rounded, color: TancyColors.textDim),
          ),
        ],
      ),
    );
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
    }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 180),
      children: [
        TextField(
          onChanged: (v) => setState(() => search = v),
          decoration: InputDecoration(
            hintText: 'Search your library...',
            hintStyle: const TextStyle(color: TancyColors.textDim),
            filled: true,
            fillColor: TancyColors.surfaceHigh,
            prefixIcon: const Icon(Icons.search_rounded, color: TancyColors.textDim),
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
                  Text('System Sync', style: GoogleFonts.spaceGrotesk(color: TancyColors.primary, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${store.songs.length} tracks', style: const TextStyle(color: TancyColors.textDim)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Scanning local storage...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                  _chipBtn('Hash查重', Icons.fingerprint_rounded, _runDuplicateScan),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('Songs', style: GoogleFonts.spaceGrotesk(fontSize: 30, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final s in filtered) _songTile(s),
      ],
    );
  }

  Widget _playlistsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 180),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(colors: [Color(0x45FF734A), Color(0x1000E3FD)]),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [Icon(Icons.favorite_rounded, color: TancyColors.secondary), SizedBox(width: 8), Text('Curated for you', style: TextStyle(color: TancyColors.textDim))]),
              const SizedBox(height: 8),
              Text('Favorites', style: GoogleFonts.spaceGrotesk(fontSize: 44, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic)),
              Text('${store.favorites.length} Tracks', style: const TextStyle(color: TancyColors.textDim)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Text('Your Playlists', style: GoogleFonts.spaceGrotesk(fontSize: 30, fontWeight: FontWeight.w700)),
            const Spacer(),
            FilledButton.icon(
              onPressed: _createPlaylistDialog,
              style: FilledButton.styleFrom(backgroundColor: TancyColors.surfaceHigh),
              icon: const Icon(Icons.add_rounded, color: TancyColors.primary),
              label: const Text('Create New'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (store.playlists.isEmpty) _glassCard(child: const Text('还没有歌单，点击 Create New 创建。', style: TextStyle(color: TancyColors.textDim))),
        ...store.playlists.entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: TancyColors.surfaceLow, borderRadius: BorderRadius.circular(18)),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [Color(0xFF1B2836), Color(0xFF213E57)]),
                    ),
                    child: const Icon(Icons.playlist_play_rounded, color: TancyColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.key, style: GoogleFonts.spaceGrotesk(fontSize: 21, fontWeight: FontWeight.w700))),
                  Text('${e.value.length} songs', style: const TextStyle(color: TancyColors.textDim)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _playerPage() {
    final song = store.currentSong;
    final title = (song?.title.isNotEmpty == true) ? song!.title : '未选择歌曲';
    final artist = (song?.artist?.isNotEmpty == true) ? song!.artist! : 'Unknown Artist';
    final max = store.duration.inMilliseconds.toDouble().clamp(1.0, (1 << 30).toDouble()).toDouble();
    final value = store.position.inMilliseconds.toDouble().clamp(0.0, max).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        Container(
          height: 360,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: const LinearGradient(colors: [Color(0xFF203245), Color(0xFF111B29), Color(0xFF0E3842)]),
          ),
          child: Stack(
            children: [
              const Center(child: Icon(Icons.album_rounded, size: 110, color: Colors.white70)),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _glassCard(
                  child: Row(
                    children: [
                      const Icon(Icons.equalizer_rounded, color: TancyColors.primary),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Currently Playing', style: TextStyle(color: TancyColors.textDim))),
                      Text(store.isPlaying ? 'LIVE' : 'PAUSED', style: const TextStyle(color: TancyColors.primary)),
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
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 34, fontWeight: FontWeight.w700)),
                  Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TancyColors.textDim, fontSize: 18)),
                ],
              ),
            ),
            IconButton(
              onPressed: song == null ? null : () => store.toggleFavorite(song.id),
              icon: Icon(
                song != null && store.favorites.contains(song.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
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
          activeColor: TancyColors.primary,
          inactiveColor: TancyColors.outline.withValues(alpha: 0.3),
        ),
        Row(
          children: [
            Text(_fmt(store.position), style: const TextStyle(color: TancyColors.textDim)),
            const Spacer(),
            Text(_fmt(store.duration), style: const TextStyle(color: TancyColors.textDim)),
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
              icon: Icon(store.loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded, color: store.loopMode == LoopMode.off ? TancyColors.textDim : TancyColors.primary),
            ),
            IconButton(onPressed: store.previous, icon: const Icon(Icons.skip_previous_rounded, size: 44)),
            GestureDetector(
              onTap: store.togglePlayPause,
              child: Container(
                width: 86,
                height: 86,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [TancyColors.primary, TancyColors.primary2]),
                ),
                child: Icon(store.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: const Color(0xFF003840), size: 44),
              ),
            ),
            IconButton(onPressed: store.next, icon: const Icon(Icons.skip_next_rounded, size: 44)),
            IconButton(onPressed: _runDuplicateScan, icon: const Icon(Icons.more_vert_rounded, color: TancyColors.textDim)),
          ],
        ),
      ],
    );
  }

  Widget _settingsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        Text('Settings', style: GoogleFonts.spaceGrotesk(fontSize: 52, fontWeight: FontWeight.w700)),
        const Text('Fine-tune your auditory environment.', style: TextStyle(color: TancyColors.textDim)),
        const SizedBox(height: 20),
        _glassCard(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _timerBtn('15m', 15),
              _timerBtn('30m', 30),
              _timerBtn('60m', 60),
              _timerBtn('Cancel', 0, danger: true),
            ],
          ),
        ),
        if (store.sleepTimerSeconds > 0) ...[
          const SizedBox(height: 8),
          Text('剩余 ${store.sleepTimerSeconds}s', style: const TextStyle(color: TancyColors.primary)),
        ],
        const SizedBox(height: 16),
        SwitchListTile(
          value: store.showNotificationControl,
          activeColor: TancyColors.primary2,
          onChanged: store.setNotificationControl,
          title: const Text('Show Notification Control'),
          subtitle: const Text('Keep playback actions in status bar', style: TextStyle(color: TancyColors.textDim)),
        ),
        ListTile(
          onTap: store.scanSongs,
          leading: const Icon(Icons.refresh_rounded, color: TancyColors.primary),
          title: const Text('Rescan Storage'),
          subtitle: const Text('Force indexer to look for new audio files', style: TextStyle(color: TancyColors.textDim)),
        ),
        ListTile(
          onTap: _runDuplicateScan,
          leading: const Icon(Icons.fingerprint_rounded, color: TancyColors.primary),
          title: const Text('Duplicate Detection (SHA-256)'),
          subtitle: const Text('Find repeated audio files by hash', style: TextStyle(color: TancyColors.textDim)),
        ),
      ],
    );
  }

  Widget _songTile(SongModel s) {
    final liked = store.favorites.contains(s.id);
    final active = store.currentSongId == s.id;
    return Container(
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
              gradient: const LinearGradient(colors: [Color(0xFF192A3D), Color(0xFF0E5B66)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.music_note_rounded, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => store.playById(s.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(s.artist?.isNotEmpty == true ? s.artist! : 'Unknown Artist', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TancyColors.textDim)),
                ],
              ),
            ),
          ),
          Text(_fmt(Duration(milliseconds: s.duration ?? 0)), style: const TextStyle(color: TancyColors.textDim)),
          IconButton(
            onPressed: () => store.toggleFavorite(s.id),
            icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: liked ? TancyColors.secondary : TancyColors.textDim),
          ),
          IconButton(
            onPressed: () => _addToPlaylistSheet(s.id),
            icon: const Icon(Icons.playlist_add_rounded, color: TancyColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _miniNowPlaying() {
    final song = store.currentSong;
    if (song == null) return const SizedBox.shrink();
    return Positioned(
      left: 20,
      right: 20,
      bottom: 92,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        decoration: BoxDecoration(
          color: TancyColors.surfaceHigh.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(colors: [Color(0xFF1B2836), Color(0xFF213E57)]),
              ),
              child: const Icon(Icons.music_note_rounded, color: Colors.white70, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  Text(song.artist ?? 'Unknown Artist', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: TancyColors.textDim)),
                ],
              ),
            ),
            IconButton(onPressed: store.previous, icon: const Icon(Icons.skip_previous_rounded, size: 18)),
            IconButton(onPressed: store.togglePlayPause, icon: Icon(store.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 18, color: TancyColors.primary)),
            IconButton(onPressed: store.next, icon: const Icon(Icons.skip_next_rounded, size: 18)),
          ],
        ),
      ),
    );
  }

  Widget _bottomNav() {
    final items = const [
      (Icons.library_music_rounded, 'Library'),
      (Icons.playlist_play_rounded, 'Playlists'),
      (Icons.play_circle_rounded, 'Player'),
      (Icons.settings_rounded, 'Settings'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
      decoration: BoxDecoration(
        color: TancyColors.surfaceHigh.withValues(alpha: 0.75),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final active = tab == i;
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => setState(() => tab = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? TancyColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(items[i].$1, color: active ? const Color(0xFF003840) : TancyColors.textDim, size: 22),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$2,
                    style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: active ? const Color(0xFF003840) : TancyColors.textDim, fontWeight: FontWeight.w700),
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
      onTap: onTap,
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

  Widget _timerBtn(String label, int m, {bool danger = false}) {
    final active = m > 0 && store.sleepTimerSeconds == m * 60;
    return InkWell(
      onTap: () => store.startSleepTimer(m),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 82,
        height: 78,
        decoration: BoxDecoration(
          color: active ? TancyColors.surfaceHigh : TancyColors.surfaceLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: danger ? TancyColors.secondary.withValues(alpha: 0.35) : Colors.transparent),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: danger ? TancyColors.secondary : (active ? TancyColors.primary : TancyColors.text),
            ),
          ),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await store.createPlaylist(controller.text);
              if (mounted) Navigator.pop(context);
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
                trailing: const Icon(Icons.playlist_add_rounded, color: TancyColors.primary),
                onTap: () async {
                  await store.addToPlaylist(name, songId);
                  if (mounted) Navigator.pop(context);
                },
              ),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未发现重复音频')));
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
              Text('Duplicate Songs Detected', style: GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Verification Method: SHA-256 Hash', style: TextStyle(color: TancyColors.textDim)),
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
                      Text('Hash: ${g.hash.substring(0, 10)}...', style: const TextStyle(color: TancyColors.textDim, fontSize: 12)),
                      const SizedBox(height: 8),
                      ...g.songs.map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.music_note_rounded, size: 14, color: TancyColors.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
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

  String _fmt(Duration d) {
    final sec = d.inSeconds;
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
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
          boxShadow: [BoxShadow(color: Color(0x3381ECFF), blurRadius: 160, spreadRadius: 18)],
        ),
      ),
    );
  }
}
