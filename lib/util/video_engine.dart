import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

/// 统一视频引擎接口，屏蔽 video_player 和 media_kit 的差异
abstract class VideoEngine {
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> setLooping(bool looping);
  Duration get position;
  Duration get duration;
  bool get isPlaying;
  bool get isInitialized;
  double get aspectRatio;
  Size get videoSize;
  Widget buildVideoWidget();
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
  Stream<bool> get onPlayingChanged;
  Stream<void> get onCompleted;
  Future<void> dispose();
}

/// video_player 引擎（ExoPlayer 硬解，MP4/MKV 等正常格式）
class VideoPlayerEngine implements VideoEngine {
  VideoPlayerController? _ctrl;
  VideoPlayerController? get ctrl => _ctrl;

  @override
  Duration get position => _ctrl?.value.position ?? Duration.zero;

  @override
  Duration get duration => _ctrl?.value.duration ?? Duration.zero;

  @override
  bool get isPlaying => _ctrl?.value.isPlaying ?? false;

  @override
  bool get isInitialized => _ctrl?.value.isInitialized ?? false;

  @override
  double get aspectRatio => _ctrl?.value.aspectRatio ?? 16 / 9;

  @override
  Size get videoSize => _ctrl?.value.size ?? Size.zero;

  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _completedCtrl = StreamController<void>.broadcast();

  @override
  Stream<Duration> get onPositionChanged => _positionCtrl.stream;

  @override
  Stream<Duration> get onDurationChanged => _durationCtrl.stream;

  @override
  Stream<bool> get onPlayingChanged => _playingCtrl.stream;

  @override
  Stream<void> get onCompleted => _completedCtrl.stream;

  Future<void> createFromNetwork(String url, {Map<String, String>? httpHeaders}) async {
    _ctrl = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: httpHeaders ?? {},
    );
  }

  @override
  Future<void> initialize() async {
    await _ctrl?.initialize();
    _ctrl?.addListener(_onChanged);
  }

  void _onChanged() {
    final c = _ctrl;
    if (c == null) return;
    _positionCtrl.add(c.value.position);
    _durationCtrl.add(c.value.duration);
    _playingCtrl.add(c.value.isPlaying);
    if (c.value.position >= c.value.duration && c.value.duration > Duration.zero) {
      _completedCtrl.add(null);
    }
  }

  @override
  Future<void> play() => _ctrl?.play() ?? Future.value();

  @override
  Future<void> pause() => _ctrl?.pause() ?? Future.value();

  @override
  Future<void> seekTo(Duration position) => _ctrl?.seekTo(position) ?? Future.value();

  @override
  Future<void> setSpeed(double speed) => _ctrl?.setPlaybackSpeed(speed) ?? Future.value();

  @override
  Future<void> setLooping(bool looping) => _ctrl?.setLooping(looping) ?? Future.value();

  @override
  Widget buildVideoWidget() {
    final c = _ctrl;
    if (c != null && c.value.isInitialized) {
      return VideoPlayer(c);
    }
    return const SizedBox.shrink();
  }

  @override
  Future<void> dispose() async {
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _playingCtrl.close();
    await _completedCtrl.close();
    _ctrl?.removeListener(_onChanged);
    await _ctrl?.dispose();
    _ctrl = null;
  }
}

/// media_kit 引擎（libmpv/FFmpeg 软解，AVI/WMV/RMVB 等老格式）
class MediaKitEngine implements VideoEngine {
  Player? _player;
  VideoController? _videoCtrl;

  @override
  Duration get position => _player?.state.position ?? Duration.zero;

  @override
  Duration get duration => _player?.state.duration ?? Duration.zero;

  @override
  bool get isPlaying => _player?.state.playing ?? false;

  @override
  bool get isInitialized => _player != null;

  @override
  double get aspectRatio {
    final w = _player?.state.width ?? 0;
    final h = _player?.state.height ?? 0;
    return (w > 0 && h > 0) ? w / h : 16 / 9;
  }

  @override
  Size get videoSize {
    final w = _player?.state.width ?? 0;
    final h = _player?.state.height ?? 0;
    return Size(w.toDouble(), h.toDouble());
  }

  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _completedCtrl = StreamController<void>.broadcast();

  StreamSubscription? _posSub, _playSub, _compSub;

  @override
  Stream<Duration> get onPositionChanged => _positionCtrl.stream;

  @override
  Stream<Duration> get onDurationChanged => _durationCtrl.stream;

  @override
  Stream<bool> get onPlayingChanged => _playingCtrl.stream;

  @override
  Stream<void> get onCompleted => _completedCtrl.stream;

  /// 先创建 Player 和 VideoController（同步），让 PlatformView 提前挂到 widget 树
  void createPlayer() {
    _player?.dispose();
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
        protocolWhitelist: ['http', 'https', 'tcp', 'tls', 'rtmp', 'rtsp', 'data', 'file'],
      ),
    );
    _videoCtrl = VideoController(_player!);
    _configureFfmpeg();
    _posSub = _player!.stream.position.listen((d) => _positionCtrl.add(d));
    _playSub = _player!.stream.playing.listen((b) => _playingCtrl.add(b));
    _compSub = _player!.stream.completed.listen((_) => _completedCtrl.add(null));
    _player!.stream.duration.listen((d) => _durationCtrl.add(d));
  }

  /// 加载媒体（Player 和 VideoController 已提前创建）
  Future<void> openMedia(String url, {Map<String, String>? httpHeaders}) async {
    _player?.open(Media(url, httpHeaders: httpHeaders ?? {}), play: true);
  }

  /// 兼容旧接口
  Future<void> createFromNetwork(String url, {Map<String, String>? httpHeaders}) async {
    createPlayer();
    _player?.open(Media(url, httpHeaders: httpHeaders ?? {}), play: true);
  }

  void _configureFfmpeg() {
    try {
      final native = _player!.platform as dynamic;
      native.setProperty('hwdec', 'no');
      native.setProperty('vd-lavc-dr', 'no');
      native.setProperty('vd-lavc-threads', '0');
      native.setProperty('vd-lavc-error-resilience', '1');
      native.setProperty('demuxer-lavf-analyzeduration', '5000000');
      native.setProperty('demuxer-lavf-probesize', '50000000');
      native.setProperty('network-timeout', '30');
      native.setProperty('cache', 'yes');
      native.setProperty('cache-secs', '30');
      native.setProperty('demuxer-max-bytes', '100MiB');
      native.setProperty('demuxer-max-back-bytes', '50MiB');
      native.setProperty('ad-lavc-dr', 'no');
      native.setProperty('audio-pitch-correction', 'yes');
    } catch (_) {}
  }

  @override
  Future<void> initialize() async {
    // 监听器已在 createFromNetwork 中设置，无需重复
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seekTo(Duration position) async => _player?.seek(position);

  @override
  Future<void> setSpeed(double speed) async => _player?.setRate(speed);

  @override
  Future<void> setLooping(bool looping) async {
    // media_kit handles looping via player configuration
    if (looping) {
      _player?.setPlaylistMode(PlaylistMode.single);
    } else {
      _player?.setPlaylistMode(PlaylistMode.none);
    }
  }

  @override
  Widget buildVideoWidget() {
    final vc = _videoCtrl;
    if (vc != null) {
      return Video(controller: vc, controls: NoVideoControls, fit: BoxFit.contain);
    }
    return const SizedBox.shrink();
  }

  @override
  Future<void> dispose() async {
    await _posSub?.cancel();
    await _playSub?.cancel();
    await _compSub?.cancel();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _playingCtrl.close();
    await _completedCtrl.close();
    _videoCtrl = null;
    _player?.dispose();
    _player = null;
    _videoCtrl = null;
  }
}
