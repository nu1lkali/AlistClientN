import 'dart:async';
import 'package:alist/util/constant.dart';
import 'package:alist/util/player/compat_video_engine.dart';
import 'package:alist/util/video_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flustars/flustars.dart';

/// 增强 MPV 播放器内核（mpvEx）。
///
/// 通过 MethodChannel 驱动原生 [MpvExFlutterPlayer]（is.xyz.mpv / libmpv），
/// 渲染走 Flutter Texture。同时实现 [CompatVideoEngine] 与 [VideoEngine]：
/// - [CompatVideoEngine]：与 [MediaKitEngine] 在门面层互换（含 isBuffering /
///   nativeSpeedBps / cachedAhead 等兼容内核独有读值）。
/// - [VideoEngine]：与 [VideoPlayerEngine] 在统一引擎接口层互换，让现有
///   strm/IPTV 等页面无需改字段类型即可切换内核。
///
/// **单例约束**：原生 MPVLib 是进程级单例，同一时刻只能有一个 mpvEx 实例
/// 持有 native。多页场景（抖音流）由上层做「当前页持有、离页降级回
/// media_kit」的轮转：被踢出时本引擎收到 `evicted` 事件并回调 [onEvicted]，
/// 门面据此降级。
class MpvExEngine implements VideoEngine, CompatVideoEngine {
  MpvExEngine._(this._id, this._textureId);

  static const MethodChannel _plugin =
      MethodChannel('com.github.alist.clientn.plugin');

  /// 创建一个 mpvEx 内核实例。返回的实例已发起 acquire（异步占用 MPVLib
  /// 单例）；调用方随后用 [createFromNetwork] 加载媒体。
  static Future<MpvExEngine> create() async {
    final res = await _plugin.invokeMapMethod<String, dynamic>('mpvCreate');
    final id = res?['id'] as int;
    final textureId = (res?['textureId'] as num?)?.toInt() ?? 0;
    final engine = MpvExEngine._(id, textureId);
    engine._wireEvents();
    return engine;
  }

  final int _id;
  final int _textureId;
  late final MethodChannel _eventChannel =
      MethodChannel('com.github.alist.clientn.mpvex/$_id');

  // ── 状态（由原生事件回写） ──
  bool _ready = false;
  bool _opened = false;
  bool _firstFrame = false;
  bool _playing = false;
  bool _buffering = false;
  bool _hasError = false;
  String _errorMessage = '';
  int _width = 0;
  int _height = 0;
  double _positionSec = 0;
  double _durationSec = 0;
  int _cacheSpeedBps = 0;
  double _cachedAheadSec = 0;
  bool _evicted = false;

  // ── 事件流 ──
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _completedCtrl = StreamController<void>.broadcast();
  final _bufferingCtrl = StreamController<bool>.broadcast();

  @override
  void Function(String reason)? onSeekFailed;

  @override
  void Function()? onPictureStalled;

  /// 被单例仲裁踢出时回调（门面据此降级回 media_kit）。
  void Function()? onEvicted;

  String? _mediaUrl;
  Map<String, String>? _mediaHeaders;

  void _wireEvents() {
    _eventChannel.setMethodCallHandler((call) async {
      if (_evicted && call.method != 'evicted') return;
      switch (call.method) {
        case 'ready':
          _ready = true;
          break;
        case 'firstFrame':
          _firstFrame = true;
          break;
        case 'position':
          final v = (call.arguments as num?)?.toDouble() ?? 0;
          _positionSec = v;
          _positionCtrl.add(Duration(milliseconds: (v * 1000).round()));
          break;
        case 'duration':
          final v = (call.arguments as num?)?.toDouble() ?? 0;
          _durationSec = v;
          _durationCtrl.add(Duration(milliseconds: (v * 1000).round()));
          break;
        case 'playing':
          final v = call.arguments as bool? ?? false;
          _playing = v;
          _playingCtrl.add(v);
          break;
        case 'buffering':
          final v = call.arguments as bool? ?? false;
          _buffering = v;
          _bufferingCtrl.add(v);
          break;
        case 'completed':
          _completedCtrl.add(null);
          break;
        case 'videoSize':
          final m = (call.arguments as Map?)?.cast<String, dynamic>();
          _width = (m?['w'] as num?)?.toInt() ?? 0;
          _height = (m?['h'] as num?)?.toInt() ?? 0;
          break;
        case 'cacheSpeed':
          _cacheSpeedBps = (call.arguments as num?)?.toInt() ?? 0;
          break;
        case 'cachedAhead':
          _cachedAheadSec = (call.arguments as num?)?.toDouble() ?? 0;
          break;
        case 'error':
        case 'logError':
          final msg = call.arguments is String
              ? call.arguments as String
              : ((call.arguments as Map?)?['text'] as String?) ?? 'mpvEx 播放出错';
          _hasError = true;
          _errorMessage = msg;
          break;
        case 'evicted':
          _evicted = true;
          _ready = false;
          _firstFrame = false;
          onEvicted?.call();
          break;
      }
    });
  }

  // ════════════════ 读值 ════════════════

  @override
  Duration get position => Duration(milliseconds: (_positionSec * 1000).round());

  @override
  Duration get duration => Duration(milliseconds: (_durationSec * 1000).round());

  @override
  Size get videoSize => Size(_width.toDouble(), _height.toDouble());

  @override
  double get aspectRatio =>
      (_width > 0 && _height > 0) ? _width / _height : 16 / 9;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isInitialized => _ready && _opened;

  @override
  bool get isBuffering => _buffering;

  @override
  bool get hasError => _hasError;

  @override
  String get errorMessage => _errorMessage;

  @override
  bool get hasRenderedFrame => _firstFrame;

  /// mpv 暴露真实下行速率（cache-speed），比 media_kit 的 0 更准。
  @override
  int get nativeSpeedBps => _cacheSpeedBps;

  /// 已缓冲时长（demuxer-cache-time）。
  @override
  Duration get cachedAhead =>
      Duration(milliseconds: (_cachedAheadSec * 1000).round());

  @override
  String get engineName => 'mpvEx';

  // ════════════════ 事件流 ════════════════

  @override
  Stream<Duration> get onPositionChanged => _positionCtrl.stream;

  @override
  Stream<Duration> get onDurationChanged => _durationCtrl.stream;

  @override
  Stream<bool> get onPlayingChanged => _playingCtrl.stream;

  @override
  Stream<void> get onCompleted => _completedCtrl.stream;

  @override
  Stream<bool> get onBufferingChanged => _bufferingCtrl.stream;

  // ════════════════ 创建 / 控制 ════════════════

  @override
  Future<void> createFromNetwork(String url,
      {Map<String, String>? httpHeaders, bool autoPlay = true}) async {
    _mediaUrl = url;
    _mediaHeaders = httpHeaders;
    _opened = true;
    _hasError = false;
    _errorMessage = '';
    _firstFrame = false;
    try {
      await _plugin.invokeMethod('mpvOpen', {
        'id': _id,
        'url': url,
        'headers': httpHeaders ?? const <String, String>{},
        'startSec': 0.0,
        'autoPlay': autoPlay,
      });
    } on PlatformException catch (e) {
      _hasError = true;
      _errorMessage = e.message ?? 'mpvEx 打开失败';
    }
  }

  /// 在指定位置打开媒体（热升级时续播用）。
  Future<void> openAt(String url, Map<String, String>? headers,
      double startSec, bool autoPlay) async {
    _mediaUrl = url;
    _mediaHeaders = headers;
    _opened = true;
    _hasError = false;
    _errorMessage = '';
    _firstFrame = false;
    try {
      await _plugin.invokeMethod('mpvOpen', {
        'id': _id,
        'url': url,
        'headers': headers ?? const <String, String>{},
        'startSec': startSec,
        'autoPlay': autoPlay,
      });
    } on PlatformException catch (e) {
      _hasError = true;
      _errorMessage = e.message ?? 'mpvEx 打开失败';
    }
  }

  String? get mediaUrl => _mediaUrl;

  @override
  Future<void> play() =>
      _plugin.invokeMethod('mpvPlay', {'id': _id});

  @override
  Future<void> pause() =>
      _plugin.invokeMethod('mpvPause', {'id': _id});

  @override
  Future<void> seekTo(Duration position) =>
      _plugin.invokeMethod('mpvSeekTo', {
        'id': _id,
        'sec': position.inMilliseconds / 1000.0,
      });

  @override
  Future<void> setSpeed(double speed) =>
      _plugin.invokeMethod('mpvSetSpeed', {'id': _id, 'speed': speed});

  @override
  Future<void> setVolume(double volume) =>
      _plugin.invokeMethod('mpvSetVolume', {'id': _id, 'volume': volume});

  @override
  Future<void> setLooping(bool looping) =>
      _plugin.invokeMethod('mpvSetLooping', {'id': _id, 'looping': looping});

  /// mpvEx 由原生事件驱动，无需轮询刷新。
  @override
  Future<void> refresh() async {}

  // ── VideoEngine 接口补齐（mpvEx 创建时即已初始化，无需异步 initialize） ──

  /// mpvEx 的 native create 已在 [create] 中完成，无需额外异步初始化。
  /// 此处空实现仅为满足 [VideoEngine] 接口契约，让现有 strm/IPTV 页面
  /// 在 engine.initialize() 调用上无差异。
  @override
  Future<void> initialize() async {}

  /// 重新加载媒体并回到指定位置（VideoEngine.reload）。
  /// 复用 [openAt] 实现：原地重开当前 url + headers，从 resumePosition 续播。
  @override
  Future<void> reload(String url, Duration resumePosition,
      {Map<String, String>? httpHeaders}) async {
    await openAt(url, httpHeaders, resumePosition.inMilliseconds / 1000.0, _playing);
  }

  /// mpvEx 用事件流的 firstFrame 做画面就绪判定，无需 media_kit 那套帧号探针。
  @override
  Future<void> probePictureHealth() async {}

  /// 画面故障自愈：原地重开当前媒体并回到原位置。
  @override
  Future<void> recoverPicture() async {
    final url = _mediaUrl;
    if (url == null) return;
    final pos = position;
    await openAt(url, _mediaHeaders, pos.inMilliseconds / 1000.0, _playing);
  }

  @override
  void resetPictureTracking() {
    _firstFrame = false;
  }

  // ════════════════ 渲染 / 释放 ════════════════

  @override
  Widget buildVideoWidget() {
    if (_evicted) return const SizedBox.shrink();
    // 与 media_kit 一致：全屏固定尺寸 Texture，mpv 内部 letterbox。
    return SizedBox.expand(
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: (_width > 0 ? _width : 1).toDouble(),
            height: (_height > 0 ? _height : 1).toDouble(),
            child: Texture(textureId: _textureId),
          ),
        ),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    try {
      await _plugin.invokeMethod('mpvDispose', {'id': _id});
    } catch (_) {}
    _evicted = true;
    _ready = false;
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _playingCtrl.close();
    await _completedCtrl.close();
    await _bufferingCtrl.close();
  }

  /// 预热 mpvEx native 库（进播放器页时调用，装载 libplayer）。
  static Future<void> preload() async {
    try {
      await _plugin.invokeMethod('mpvPreload');
    } catch (_) {}
  }

  /// 读取「增强 MPV 播放器」开关。
  static bool get enabled =>
      SpUtil.getBool(AlistConstant.enableMpvExPlayer, defValue: false) ?? false;
}
