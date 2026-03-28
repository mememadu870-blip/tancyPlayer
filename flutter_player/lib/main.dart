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

class TancyApp extends StatelessWidget {
  const TancyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tancy Player',
      theme: ThemeData(
        brightness: Brightness.dark,
        textTheme: GoogleFonts.outfitTextTheme(),
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF38D9B7)),
      ),
      home: const PlayerPage(),
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
  LoopMode loopMode = LoopMode.all;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  Timer? _sleepTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<int?>? _indexSub;
  SharedPreferences? _prefs;

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

    await _preparePlayerStreams();
    await scanSongs();
  }

  Future<void> _preparePlayerStreams() async {
    _player.setLoopMode(loopMode);

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
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
      );
      currentSongId = songs.first.id;
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
    final target = Duration(milliseconds: v.toInt());
    await _player.seek(target);
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

  bool get isPlaying => _player.playing;

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

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final store = PlayerStore();
  String selectedPlaylist = '';

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
    SongModel? current;
    if (store.songs.isNotEmpty) {
      current = store.songs.first;
      for (final s in store.songs) {
        if (s.id == store.currentSongId) {
          current = s;
          break;
        }
      }
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF090E18), Color(0xFF101D30), Color(0xFF102328)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              if (store.loading) const LinearProgressIndicator(minHeight: 2),
              _nowPlaying(current),
              _toolbar(),
              Expanded(child: _songList()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _playerBar(current),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text('Tancy Player', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const Spacer(),
          _chip('本地 ${store.songs.length} 首'),
        ],
      ),
    );
  }

  Widget _nowPlaying(SongModel? song) {
    final title = (song?.title.isNotEmpty == true) ? song!.title : '未选择歌曲';
    final artist = (song?.artist?.isNotEmpty == true) ? song!.artist! : 'Unknown Artist';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0x1AFFFFFF),
        border: Border.all(color: const Color(0x30FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Now Playing', style: TextStyle(color: Colors.white.withValues(alpha: 0.72))),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(artist, style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 8),
          Slider(
            value: store.position.inMilliseconds
                .toDouble()
                .clamp(0.0, store.duration.inMilliseconds.toDouble().clamp(1.0, (1 << 30).toDouble()))
                .toDouble(),
            min: 0,
            max: store.duration.inMilliseconds.toDouble().clamp(1.0, (1 << 30).toDouble()).toDouble(),
            onChanged: (v) => store.seek(v),
          ),
          Row(
            children: [
              Text(_fmt(store.position), style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
              const Spacer(),
              Text(_fmt(store.duration), style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonal(onPressed: store.scanSongs, child: const Text('扫描音乐')),
          FilledButton.tonal(
            onPressed: () => _createPlaylistDialog(),
            child: const Text('创建歌单'),
          ),
          FilledButton.tonal(
            onPressed: () => _chooseSleepTimer(),
            child: Text(store.sleepTimerSeconds > 0 ? '定时 ${store.sleepTimerSeconds}s' : '定时停止'),
          ),
          FilledButton.tonal(
            onPressed: store.duplicateScanning ? null : () => _runDuplicateScan(),
            child: Text(store.duplicateScanning ? '查重中...' : 'Hash查重'),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedPlaylist.isEmpty ? null : selectedPlaylist,
              hint: const Text('选中歌单'),
              dropdownColor: const Color(0xFF14253A),
              items: store.playlists.keys
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => selectedPlaylist = v ?? ''),
            ),
          ),
          SegmentedButton<LoopMode>(
            segments: const [
              ButtonSegment(value: LoopMode.off, label: Text('不循环')),
              ButtonSegment(value: LoopMode.one, label: Text('单曲')),
              ButtonSegment(value: LoopMode.all, label: Text('列表')),
            ],
            selected: {store.loopMode},
            onSelectionChanged: (v) => store.setRepeatMode(v.first),
          ),
        ],
      ),
    );
  }

  Widget _songList() {
    return ListView.builder(
      itemCount: store.songs.length,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
      itemBuilder: (_, i) {
        final s = store.songs[i];
        final active = s.id == store.currentSongId;
        final liked = store.favorites.contains(s.id);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: active ? const Color(0x2238D9B7) : const Color(0x13213244),
            border: Border.all(color: active ? const Color(0x6638D9B7) : Colors.white12),
          ),
          child: ListTile(
            onTap: () => store.playById(s.id),
            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              (s.artist?.isNotEmpty == true ? s.artist! : 'Unknown Artist'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(_fmt(Duration(milliseconds: s.duration ?? 0))),
                IconButton(
                  onPressed: () => store.toggleFavorite(s.id),
                  icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.pinkAccent : null),
                ),
                IconButton(
                  onPressed: selectedPlaylist.isEmpty
                      ? null
                      : () => store.addToPlaylist(selectedPlaylist, s.id),
                  icon: const Icon(Icons.playlist_add_rounded),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _playerBar(SongModel? song) {
    final title = (song?.title.isNotEmpty == true) ? song!.title : '未选择歌曲';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      decoration: const BoxDecoration(color: Color(0xFF0E1726), border: Border(top: BorderSide(color: Colors.white12))),
      child: Row(
        children: [
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(onPressed: store.previous, icon: const Icon(Icons.skip_previous_rounded)),
          FilledButton.tonal(
            onPressed: store.togglePlayPause,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF38D9B7), foregroundColor: Colors.black),
            child: Icon(store.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          IconButton(onPressed: store.next, icon: const Icon(Icons.skip_next_rounded)),
        ],
      ),
    );
  }

  Future<void> _createPlaylistDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('创建歌单'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: '例如：夜间通勤')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await store.createPlaylist(controller.text);
              if (store.playlists.isNotEmpty && selectedPlaylist.isEmpty) {
                selectedPlaylist = store.playlists.keys.first;
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseSleepTimer() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('15 分钟后停止'), onTap: () => _setSleep(15)),
            ListTile(title: const Text('30 分钟后停止'), onTap: () => _setSleep(30)),
            ListTile(title: const Text('60 分钟后停止'), onTap: () => _setSleep(60)),
            ListTile(title: const Text('取消定时'), onTap: () => _setSleep(0)),
          ],
        ),
      ),
    );
  }

  void _setSleep(int min) {
    store.startSleepTimer(min);
    Navigator.pop(context);
  }

  Future<void> _runDuplicateScan() async {
    await store.detectDuplicates();
    if (!mounted) return;
    if (store.duplicateGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未发现重复音频')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重复音频提示'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: store.duplicateGroups.take(20).map((g) {
              final first = g.songs.first;
              return ListTile(
                dense: true,
                title: Text(first.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('重复 ${g.songs.length} 首 | hash ${g.hash.substring(0, 10)}...'),
              );
            }).toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: const Color(0x2138D9B7),
        border: Border.all(color: const Color(0x6638D9B7)),
      ),
      child: Text(text),
    );
  }

  String _fmt(Duration d) {
    final sec = d.inSeconds;
    final min = sec ~/ 60;
    final remain = sec % 60;
    return '$min:${remain.toString().padLeft(2, '0')}';
  }
}
