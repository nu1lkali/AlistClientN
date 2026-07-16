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

  /// 包装一个已初始化的 VideoPlayerController
  void wrapController(VideoPlayerController c) {
    _ctrl?.removeListener(_onChanged);
    _ctrl?.dispose();
    _ctrl = c;
    _ctrl?.addListener(_onChanged);
  }

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
  bool _mediaOpened = false;

  // Seek 防抖：WMV 等老格式频繁 seek 容易卡死
  DateTime _lastSeekTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _seekMinInterval = Duration(milliseconds: 400);
  Timer? _seekDebounceTimer;
  Duration? _pendingSeekPosition;

  @override
  Duration get position => _player?.state.position ?? Duration.zero;

  @override
  Duration get duration => _player?.state.duration ?? Duration.zero;

  @override
  bool get isPlaying => _player?.state.playing ?? false;

  @override
  bool get isInitialized => _player != null && _mediaOpened;

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
  final _bufferingCtrl = StreamController<bool>.broadcast();

  StreamSubscription? _posSub, _playSub, _compSub, _bufferingSub;

  @override
  Stream<Duration> get onPositionChanged => _positionCtrl.stream;

  @override
  Stream<Duration> get onDurationChanged => _durationCtrl.stream;

  @override
  Stream<bool> get onPlayingChanged => _playingCtrl.stream;

  @override
  Stream<void> get onCompleted => _completedCtrl.stream;

  /// 是否正在缓冲（供 UI 显示 loading）
  Stream<bool> get onBufferingChanged => _bufferingCtrl.stream;
  bool get isBuffering => _player?.state.buffering ?? false;

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
    _bufferingSub = _player!.stream.buffering.listen((b) => _bufferingCtrl.add(b));
  }

  /// 加载媒体（Player 和 VideoController 已提前创建）
  Future<void> openMedia(String url, {Map<String, String>? httpHeaders}) async {
    _player?.open(Media(url, httpHeaders: httpHeaders ?? {}), play: true);
    _mediaOpened = true;
  }

  /// 兼容旧接口
  Future<void> createFromNetwork(String url, {Map<String, String>? httpHeaders}) async {
    createPlayer();
    _player?.open(Media(url, httpHeaders: httpHeaders ?? {}), play: true);
    _mediaOpened = true;
  }

  void _configureFfmpeg() {
    try {
      final native = _player!.platform as dynamic;

      // ==================== 硬件解码 ====================
      // 优先尝试硬解（GPU 解码 WMV3 等老格式性能远超纯软解），失败自动回退软解
      native.setProperty('hwdec', 'auto-safe');

      // ==================== 视频解码 ====================
      native.setProperty('vd-lavc-dr', 'no');
      // 明确分配 4 个解码线程，避免 auto 策略对 WMV/ASF 只分 1~2 线程
      native.setProperty('vd-lavc-threads', '4');
      native.setProperty('vd-lavc-error-resilience', '1');

      // ==================== 容器探测 ====================
      native.setProperty('demuxer-lavf-analyzeduration', '5000000');
      native.setProperty('demuxer-lavf-probesize', '50000000');
      native.setProperty('demuxer-lavf-format', '');
      native.setProperty('network-timeout', '30');

      // ==================== 缓存 ====================
      native.setProperty('cache', 'yes');
      // 网络流缓存 10 秒即可，30 秒过大导致内存压力 + 起播慢
      native.setProperty('cache-secs', '10');
      native.setProperty('demuxer-max-bytes', '50MiB');
      native.setProperty('demuxer-max-back-bytes', '10MiB');

      // ==================== 音频 ====================
      native.setProperty('ad-lavc-dr', 'no');
      native.setProperty('audio-pitch-correction', 'yes');

      // ==================== 同步与 seek ====================
      // 视频跟音频时钟同步，避免画面卡住不动
      native.setProperty('video-sync', 'audio');
      // 双端丢帧（decoder + vo），软解跟不上时平滑降帧而非冻住
      native.setProperty('framedrop', 'decoder+vo');
      // 精确 seek：WMV/ASF 无关键帧索引，启用后 seek 更快恢复
      native.setProperty('hr-seek', 'yes');

      // ==================== 渲染兼容 ====================
      native.setProperty('correct-pts', 'yes');
      native.setProperty('video-aspect-override', '0');
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
  Future<void> seekTo(Duration position) async {
    final now = DateTime.now();
    // 距离上次 seek 太近，延迟执行
    if (now.difference(_lastSeekTime) < _seekMinInterval) {
      _pendingSeekPosition = position;
      _seekDebounceTimer?.cancel();
      _seekDebounceTimer = Timer(_seekMinInterval, () {
        final target = _pendingSeekPosition;
        _pendingSeekPosition = null;
        if (target != null) {
          _lastSeekTime = DateTime.now();
          _player?.seek(target);
        }
      });
      return;
    }
    _lastSeekTime = now;
    _seekDebounceTimer?.cancel();
    _pendingSeekPosition = null;
    _player?.seek(position);
  }

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
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    _pendingSeekPosition = null;
    try { _player?.pause(); } catch (_) {}
    try { _player?.stop(); } catch (_) {}
    await _posSub?.cancel();
    await _playSub?.cancel();
    await _compSub?.cancel();
    await _bufferingSub?.cancel();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _playingCtrl.close();
    await _completedCtrl.close();
    await _bufferingCtrl.close();
    _videoCtrl = null;
    _player?.dispose();
    _player = null;
    _mediaOpened = false;
  }
}
