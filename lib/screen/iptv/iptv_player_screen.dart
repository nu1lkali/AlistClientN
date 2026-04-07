import 'dart:async';

import 'package:alist/screen/iptv/model/iptv_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// IPTV 频道播放器 —— 使用 media_kit 播放 HLS/m3u8 直播流
class IptvPlayerScreen extends StatefulWidget {
  const IptvPlayerScreen({super.key});

  @override
  State<IptvPlayerScreen> createState() => _IptvPlayerScreenState();
}

class _IptvPlayerScreenState extends State<IptvPlayerScreen> {
  late final List<IptvChannel> _playlist;
  late int _index;

  late final Player _player;
  late final VideoController _controller;

  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map<String, dynamic>;
    _playlist = List<IptvChannel>.from(args['playlist'] as List);
    _index = args['index'] as int? ?? 0;

    _player = Player(
      configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
    );
    _controller = VideoController(_player);

    // 进入播放器时隐藏系统 UI，只调用一次避免横竖屏切换时闪烁
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _playAt(_index);
    _resetHideTimer();
  }

  void _playAt(int index) {
    if (index < 0 || index >= _playlist.length) return;
    setState(() => _index = index);
    _player.open(Media(_playlist[index].url));
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _resetHideTimer,
          child: Stack(
            children: [
              // 视频画面
              Center(
                child: Video(controller: _controller),
              ),
              // 控制层
              if (_showControls) Positioned.fill(child: _buildControls()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final channel = _playlist[_index];
    return Stack(
      children: [
        // 顶部标题栏
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Get.back(),
                  ),
                  Expanded(
                    child: Text(
                      channel.name,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 底部控制栏，固定在底部，padding 留出安全区
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  onPressed: _index > 0 ? () => _playAt(_index - 1) : null,
                ),
                StreamBuilder<bool>(
                  stream: _player.stream.playing,
                  builder: (_, snap) {
                    final playing = snap.data ?? false;
                    return IconButton(
                      iconSize: 40,
                      icon: Icon(
                        playing ? Icons.pause_circle : Icons.play_circle,
                        color: Colors.white,
                      ),
                      onPressed: () => _player.playOrPause(),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  onPressed: _index < _playlist.length - 1
                      ? () => _playAt(_index + 1)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
