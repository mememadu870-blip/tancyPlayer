import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const TancyApp());
}

class TancyApp extends StatelessWidget {
  const TancyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.outfitTextTheme();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tancy Player',
      theme: ThemeData(
        brightness: Brightness.dark,
        textTheme: textTheme,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF46D7B5)),
      ),
      home: const PlayerHomePage(),
    );
  }
}

class Track {
  final String title;
  final String artist;
  final Duration duration;
  final bool liked;

  const Track({
    required this.title,
    required this.artist,
    required this.duration,
    this.liked = false,
  });

  Track copyWith({bool? liked}) {
    return Track(
      title: title,
      artist: artist,
      duration: duration,
      liked: liked ?? this.liked,
    );
  }
}

class PlayerHomePage extends StatefulWidget {
  const PlayerHomePage({super.key});

  @override
  State<PlayerHomePage> createState() => _PlayerHomePageState();
}

class _PlayerHomePageState extends State<PlayerHomePage> {
  final _tracks = <Track>[
    const Track(title: 'Midnight Drive', artist: 'Tancy', duration: Duration(minutes: 3, seconds: 12)),
    const Track(title: 'Rain on Neon', artist: 'Aster', duration: Duration(minutes: 4, seconds: 4)),
    const Track(title: 'Signal Lost', artist: 'Mira', duration: Duration(minutes: 2, seconds: 48)),
    const Track(title: 'Parallel Hearts', artist: 'WAVE', duration: Duration(minutes: 3, seconds: 51)),
    const Track(title: 'Cloud Memory', artist: 'Juno', duration: Duration(minutes: 3, seconds: 26)),
  ];

  int _current = 0;
  bool _playing = false;
  bool _repeatAll = true;
  double _progress = 0.24;

  @override
  Widget build(BuildContext context) {
    final track = _tracks[_current];
    final h = MediaQuery.sizeOf(context).height;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0D14), Color(0xFF111B2A), Color(0xFF16232B)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: -80,
                right: -40,
                child: _glow(const Color(0xFF46D7B5), 220),
              ),
              Positioned(
                bottom: -100,
                left: -60,
                child: _glow(const Color(0xFF42A5F5), 260),
              ),
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  _topBar(),
                  const SizedBox(height: 16),
                  _nowPlayingCard(track, h),
                  const SizedBox(height: 16),
                  _quickActions(),
                  const SizedBox(height: 16),
                  _sectionTitle('播放队列'),
                  const SizedBox(height: 8),
                  ...List.generate(_tracks.length, (i) => _trackTile(i, _tracks[i])),
                  const SizedBox(height: 100),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomControlBar(track),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Text('Tancy Player', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const Spacer(),
        _chip('本地 328 首'),
      ],
    );
  }

  Widget _nowPlayingCard(Track track, double h) {
    final size = min(180.0, h * 0.22);
    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF49E7C4), Color(0xFF4B9AF9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.album_rounded, size: 72, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Now Playing', style: TextStyle(color: Colors.white.withValues(alpha: 0.72))),
                    const SizedBox(height: 4),
                    Text(track.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(track.artist, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16)),
                    const SizedBox(height: 16),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(trackHeight: 4),
                      child: Slider(
                        value: _progress,
                        onChanged: (v) => setState(() => _progress = v),
                      ),
                    ),
                    Row(
                      children: [
                        Text(_fmt(track.duration * _progress), style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                        const Spacer(),
                        Text(_fmt(track.duration), style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return Row(
      children: [
        Expanded(child: _actionCard(Icons.timer_outlined, '定时停止', '30 分钟')),
        const SizedBox(width: 10),
        Expanded(child: _actionCard(Icons.library_music_outlined, '歌单', '夜间通勤')),
        const SizedBox(width: 10),
        Expanded(child: _actionCard(Icons.find_in_page_outlined, '查重', '发现 12 组')),
      ],
    );
  }

  Widget _actionCard(IconData icon, String title, String sub) {
    return _glass(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF7CE9D1)),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(sub, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const Spacer(),
        TextButton(onPressed: () {}, child: const Text('查看全部')),
      ],
    );
  }

  Widget _trackTile(int index, Track track) {
    final active = index == _current;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _current = index),
        child: Ink(
          decoration: BoxDecoration(
            color: active ? const Color(0x2246D7B5) : const Color(0x141D2738),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? const Color(0x6646D7B5) : Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: active
                          ? const [Color(0xFF49E7C4), Color(0xFF4B9AF9)]
                          : const [Color(0xFF2A3342), Color(0xFF1F2734)],
                    ),
                  ),
                  child: Icon(active ? Icons.graphic_eq_rounded : Icons.music_note_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(track.artist, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                Text(_fmt(track.duration), style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () {
                    setState(() => _tracks[index] = track.copyWith(liked: !track.liked));
                  },
                  icon: Icon(track.liked ? Icons.favorite : Icons.favorite_border, color: track.liked ? Colors.pinkAccent : null),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomControlBar(Track track) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1724),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.72))),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _repeatAll = !_repeatAll),
            icon: Icon(_repeatAll ? Icons.repeat_rounded : Icons.repeat_one_rounded),
          ),
          IconButton(
            onPressed: () => setState(() => _current = (_current - 1 + _tracks.length) % _tracks.length),
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF46D7B5),
              foregroundColor: Colors.black,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(16),
            ),
            onPressed: () => setState(() => _playing = !_playing),
            child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 26),
          ),
          IconButton(
            onPressed: () => setState(() => _current = (_current + 1) % _tracks.length),
            icon: const Icon(Icons.skip_next_rounded),
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.playlist_add_rounded)),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: const Color(0x202FF0C8),
        border: Border.all(color: const Color(0x555DEFD2)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _glass({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x35FFFFFF)),
      ),
      child: child,
    );
  }

  Widget _glow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.26), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}
