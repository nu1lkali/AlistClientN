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

  // 横向拖动 seek 状态
  bool _seeking = false;
  Duration _seekDelta = Duration.zero;
  Duration _seekStartPos = Duration.zero;
  double _dragStartX = 0;

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

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playAt(_index);
    });
  }

  void _playAt(int index) {
    if (index < 0 || index >= _playlist.length) return;
    setState(() => _index = index);
    _player.open(Media(_playlist[index].url));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final channel = _playlist[_index];
    final screenW = MediaQuery.of(context).size.width;

    return WillPopScope(
      onWillPop: () async {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        return true;
      },
      child: MaterialVideoControlsTheme(
        normal: _buildThemeData(channel),
        fullscreen: _buildThemeData(channel),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // 视频 + 手势层
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (d) {
                  final pos = _player.state.position;
                  final dur = _player.state.duration;
                  // 直播流没有 duration，不支持 seek
                  if (dur == Duration.zero) return;
                  setState(() {
                    _seeking = true;
                    _seekStartPos = pos;
                    _seekDelta = Duration.zero;
                    _dragStartX = d.localPosition.dx;
                  });
                },
                onHorizontalDragUpdate: (d) {
                  if (!_seeking) return;
                  final dur = _player.state.duration;
                  if (dur == Duration.zero) return;
                  // 每屏宽度对应最多 90 秒
                  final ratio = (d.localPosition.dx - _dragStartX) / screenW;
                  final deltaMs = (ratio * 90000).round();
                  final newPos = _seekStartPos + Duration(milliseconds: deltaMs);
                  final clamped = newPos.isNegative
                      ? Duration.zero
                      : newPos > dur ? dur : newPos;
                  setState(() {
                    _seekDelta = Duration(milliseconds: deltaMs);
                    _seekStartPos = _seekStartPos; // keep reference
                    // show preview position
                    _seekDelta = clamped - _seekStartPos;
                  });
                },
                onHorizontalDragEnd: (_) {
                  if (!_seeking) return;
                  final dur = _player.state.duration;
                  if (dur != Duration.zero) {
                    final target = _seekStartPos + _seekDelta;
                    final clamped = target.isNegative
                        ? Duration.zero
                        : target > dur ? dur : target;
                    _player.seek(clamped);
                  }
                  setState(() {
                    _seeking = false;
                    _seekDelta = Duration.zero;
                  });
                },
                onHorizontalDragCancel: () {
                  setState(() {
                    _seeking = false;
                    _seekDelta = Duration.zero;
                  });
                },
                child: SizedBox.expand(
                  child: Video(
                    controller: _controller,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              // 拖动 seek 提示浮层
              if (_seeking)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _seekDelta.isNegative
                              ? Icons.fast_rewind_rounded
                              : Icons.fast_forward_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration((_seekStartPos + _seekDelta).abs()),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  MaterialVideoControlsThemeData _buildThemeData(IptvChannel channel) {
    return MaterialVideoControlsThemeData(
      topButtonBar: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            Get.back();
          },
        ),
        Expanded(
          child: Text(
            channel.name,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      bottomButtonBar: [
        if (_index > 0)
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Colors.white),
            onPressed: () => _playAt(_index - 1),
          ),
        const Spacer(),
        if (_index < _playlist.length - 1)
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white),
            onPressed: () => _playAt(_index + 1),
          ),
        const MaterialFullscreenButton(),
      ],
      padding: const EdgeInsets.only(bottom: 0),
    );
  }
}
