import 'dart:async';
import 'dart:io';

import 'package:alist/screen/iptv/model/iptv_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class IptvPlayerScreen extends StatefulWidget {
  const IptvPlayerScreen({super.key});

  @override
  State<IptvPlayerScreen> createState() => _IptvPlayerScreenState();
}

class _IptvPlayerScreenState extends State<IptvPlayerScreen>
    with WidgetsBindingObserver {
  late final List<IptvChannel> _playlist;
  late int _index;
  late final Player _player;
  late final VideoController _controller;

  bool _showControls = true;
  Timer? _hideTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _bufSub;

  bool _isDraggingSlider = false;

  bool _seeking = false;
  Duration _seekTarget = Duration.zero;
  Duration _seekStartPos = Duration.zero;
  double _dragStartX = 0;
  double _dragStartY = 0;
  bool _dragConfirmed = false;

  bool _isFullscreen = false;

  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.black,
      systemNavigationBarDividerColor: Colors.black,
      statusBarColor: Colors.transparent,
    ));
  }

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map<String, dynamic>;
    _playlist = List<IptvChannel>.from(args['playlist'] as List);
    _index = args['index'] as int? ?? 0;

    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
        ready: () => _applySystemProxy(),
      ),
    );
    _controller = VideoController(_player);

    _hideSystemUI();
    WidgetsBinding.instance.addObserver(this);

    _posSub = _player.stream.position.listen((p) {
      if (mounted && !_isDraggingSlider) setState(() => _position = p);
    });
    _durSub = _player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _playSub = _player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
    _bufSub = _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _playAt(_index));
    _resetHideTimer();
  }

  /// 读取系统代理并传给 libmpv，使 media_kit 能走 VPN 隧道
  void _applySystemProxy() {
    if (!Platform.isAndroid) return;
    try {
      final proxyHost = Platform.environment['http.proxyHost'] ??
          Platform.environment['HTTP_PROXY'] ??
          Platform.environment['http_proxy'];
      final proxyPort = Platform.environment['http.proxyPort'];

      String? proxyUrl;
      if (proxyHost != null && proxyHost.isNotEmpty) {
        proxyUrl = proxyPort != null
            ? 'http://$proxyHost:$proxyPort'
            : 'http://$proxyHost';
      }

      if (proxyUrl != null) {
        final native = _player.platform as NativePlayer;
        native.setProperty('http-proxy', proxyUrl);
      }
    } catch (_) {
      // 读取代理失败不影响播放
    }
  }

  @override
  void didChangeMetrics() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _hideSystemUI();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _hideSystemUI();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _bufSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    _player.dispose();
    super.dispose();
  }

  void _playAt(int index) {
    if (index < 0 || index >= _playlist.length) return;
    setState(() => _index = index);
    _player.open(Media(_playlist[index].url));
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    if (_showControls) {
      _hideTimer?.cancel();
      setState(() => _showControls = false);
    } else {
      _resetHideTimer();
    }
  }

  void _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    setState(() => _isFullscreen = !_isFullscreen);
    _hideSystemUI();
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
      if (dx.abs() < 10 && dy.abs() < 10) return;
      if (dx.abs() <= dy.abs()) return;
      if (_duration == Duration.zero) return;
      _dragConfirmed = true;
      _seekStartPos = _position;
      _seekTarget = _seekStartPos;
      setState(() => _seeking = true);
    }
    if (!_seeking) return;
    if (_duration == Duration.zero) return;
    final screenW = MediaQuery.of(context).size.width;
    var target = _seekStartPos +
        Duration(milliseconds: (dx / screenW * 90000).round());
    if (target.isNegative) target = Duration.zero;
    if (target > _duration) target = _duration;
    setState(() => _seekTarget = target);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_seeking) {
      _player.seek(_seekTarget);
      setState(() { _seeking = false; _dragConfirmed = false; });
    } else if (!_dragConfirmed) {
      _toggleControls();
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_seeking) setState(() { _seeking = false; _dragConfirmed = false; });
  }

  @override
  Widget build(BuildContext context) {
    final channel = _playlist[_index];
    final isLive = _duration == Duration.zero;

    return WillPopScope(
      onWillPop: () async {
        if (_isFullscreen) { _toggleFullscreen(); return false; }
        return true;
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.black,
          systemNavigationBarDividerColor: Colors.black,
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: Stack(
              children: [
                SizedBox.expand(
                  child: Video(
                    controller: _controller,
                    controls: null,
                    fit: BoxFit.contain,
                  ),
                ),

                if (_buffering && !_seeking)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
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

                if (_showControls) ...[
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () {
                                if (_isFullscreen) {
                                  _toggleFullscreen();
                                } else {
                                  Get.back();
                                }
                              },
                            ),
                            Expanded(
                              child: Text(
                                channel.name,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          iconSize: 48,
                          icon: Icon(
                            Icons.skip_previous_rounded,
                            color: _index > 0
                                ? Colors.white
                                : Colors.white.withOpacity(0.3),
                          ),
                          onPressed: _index > 0
                              ? () { _playAt(_index - 1); _resetHideTimer(); }
                              : null,
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          iconSize: 64,
                          icon: Icon(
                            _playing
                                ? Icons.pause_circle_outline_rounded
                                : Icons.play_circle_outline_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            _player.playOrPause();
                            _resetHideTimer();
                          },
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          iconSize: 48,
                          icon: Icon(
                            Icons.skip_next_rounded,
                            color: _index < _playlist.length - 1
                                ? Colors.white
                                : Colors.white.withOpacity(0.3),
                          ),
                          onPressed: _index < _playlist.length - 1
                              ? () { _playAt(_index + 1); _resetHideTimer(); }
                              : null,
                        ),
                      ],
                    ),
                  ),

                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isLive)
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 14),
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor:
                                      Colors.white.withOpacity(0.3),
                                  thumbColor: Colors.white,
                                  overlayColor:
                                      Colors.white.withOpacity(0.2),
                                ),
                                child: Slider(
                                  value: _position.inMilliseconds
                                      .toDouble()
                                      .clamp(0,
                                          _duration.inMilliseconds.toDouble()),
                                  min: 0,
                                  max: _duration.inMilliseconds
                                      .toDouble()
                                      .clamp(1, double.infinity),
                                  onChangeStart: (_) {
                                    _isDraggingSlider = true;
                                    _hideTimer?.cancel();
                                  },
                                  onChanged: (v) {
                                    setState(() => _position =
                                        Duration(milliseconds: v.toInt()));
                                  },
                                  onChangeEnd: (v) {
                                    _isDraggingSlider = false;
                                    _player.seek(
                                        Duration(milliseconds: v.toInt()));
                                    _resetHideTimer();
                                  },
                                ),
                              ),
                            Row(
                              children: [
                                const Spacer(),
                                if (!isLive)
                                  Text(
                                    '${_fmt(_position)} / ${_fmt(_duration)}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                if (isLive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('LIVE',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(
                                    _isFullscreen
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                    color: Colors.white,
                                  ),
                                  onPressed: _toggleFullscreen,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
