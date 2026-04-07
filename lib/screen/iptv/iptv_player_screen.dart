import 'dart:async';

import 'package:alist/screen/iptv/model/iptv_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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

  bool _seeking = false;
  Duration _seekTarget = Duration.zero;
  Duration _seekStartPos = Duration.zero;
  double _dragStartX = 0;
  double _dragStartY = 0;
  bool _dragConfirmed = false; // 确认是横向拖动后才激活 seek

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

  String _fmt(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _onPointerDown(PointerDownEvent e) {
    _dragStartX = e.position.dx;
    _dragStartY = e.position.dy;
    _dragConfirmed = false;
  }

  void _onPointerMove(PointerMoveEvent e) {
    final dx = e.position.dx - _dragStartX;
    final dy = e.position.dy - _dragStartY;

    if (!_dragConfirmed) {
      // 移动超过 10px 才判断方向
      if (dx.abs() < 10 && dy.abs() < 10) return;
      // 横向分量大于纵向才激活 seek
      if (dx.abs() <= dy.abs()) return;
      final dur = _player.state.duration;
      if (dur == Duration.zero) return; // 直播流不 seek
      _dragConfirmed = true;
      _seekStartPos = _player.state.position;
      _seekTarget = _seekStartPos;
      setState(() => _seeking = true);
    }

    if (!_seeking) return;
    final dur = _player.state.duration;
    if (dur == Duration.zero) return;
    final screenW = MediaQuery.of(context).size.width;
    final ratio = dx / screenW;
    final deltaMs = (ratio * 90000).round();
    var target = _seekStartPos + Duration(milliseconds: deltaMs);
    if (target.isNegative) target = Duration.zero;
    if (target > dur) target = dur;
    setState(() => _seekTarget = target);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_seeking) {
      _player.seek(_seekTarget);
      setState(() {
        _seeking = false;
        _dragConfirmed = false;
      });
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_seeking) {
      setState(() {
        _seeking = false;
        _dragConfirmed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final channel = _playlist[_index];

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
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: SizedBox.expand(
                  child: Video(
                    controller: _controller,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              if (_seeking)
                Center(
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _seekTarget < _seekStartPos
                                ? Icons.fast_rewind_rounded
                                : Icons.fast_forward_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _fmt(_seekTarget),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
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
