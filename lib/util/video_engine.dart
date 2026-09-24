import 'dart:async';
import 'package:dio/dio.dart';
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
  /// 设置播放音量（0.0 ~ 1.0）。
  /// 用于「只有当前页出声、离屏页静音」的幻听根治：非当前页内核一律 volume=0，
  /// 从创建起就不可能漏出声音，比事后 pause 更彻底（零窗口）。
  Future<void> setVolume(double volume);
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
  /// 重新加载当前媒体并恢复到指定位置（不销毁重建，仅 stop + reopen）
  Future<void> reload(String url, Duration resumePosition, {Map<String, String>? httpHeaders});
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
  Future<void> setVolume(double volume) => _ctrl?.setVolume(volume) ?? Future.value();

  @override
  Widget buildVideoWidget() {
    final c = _ctrl;
    if (c != null && c.value.isInitialized) {
      return VideoPlayer(c);
    }
    return const SizedBox.shrink();
  }

  @override
  Future<void> reload(String url, Duration resumePosition, {Map<String, String>? httpHeaders}) async {
    _ctrl?.removeListener(_onChanged);
    await _ctrl?.dispose();
    _ctrl = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: httpHeaders ?? {},
    );
    await _ctrl?.initialize();
    _ctrl?.addListener(_onChanged);
    await _ctrl?.seekTo(resumePosition);
    await _ctrl?.play();
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

  // Seek 实效校验：mpv 对流不可 seek（服务端没给 Accept-Ranges / Content-Length）
  // 时不会报错，而是静默从头重开 → UI 上表现为「拖了进度条又弹回 00:00」。
  // 与其让用户猜是片源问题还是 App 问题，不如 seek 后复查一次，没到位就回调上层。
  Timer? _seekVerifyTimer;

  /// seek 未真正生效时回调（mpv 静默回到开头）。由门面透传给页面弹提示。
  ///
  /// [reason] 是诊断后的结论：**必须区分**下面两种情况，因为它们的表现完全
  /// 一样（进度弹回 0），但一个客户端能修、另一个根本无从下手。
  void Function(String reason)? onSeekFailed;

  /// 当前媒体地址与请求头。仅用于 seek 校验失败后做一次 Range 可用性实测。
  String? _mediaUrl;
  Map<String, String>? _mediaHeaders;

  /// 诊断请求去重：拖动失败往往连着触发，别对同一条 URL 反复发探测请求。
  bool _diagnosingSeek = false;

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
  StreamSubscription? _errorSub;

  // 解码错误上屏：media_kit 把中途冒出的解码失败通过 stream.error 抛出，
  // 门面层据此把错误显示到错误页，而不是永远停在 loading。
  bool _hasError = false;
  String _errorMessage = '';

  /// Expose the native player platform for property queries (e.g. cache-speed)
  dynamic get playerPlatform => _player?.platform;

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

  /// 解码错误（供 TikTok 门面把中途冒出的错误上屏）。
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;

  /// media_kit 不暴露 TCP 速率，返回 0，由上层走系统流量采样。
  int get nativeSpeedBps => 0;

  /// media_kit 无「已缓冲时长」概念，返回零。
  Duration get cachedAhead => Duration.zero;

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

    // 解码错误上屏：media_kit 不同版本 error 流类型不同，用动态访问规避编译差异。
    try {
      final dyn = _player! as dynamic;
      final errStream = dyn.stream?.error;
      if (errStream != null) {
        _errorSub = errStream.listen((dynamic e) {
          _hasError = true;
          final msg = e?.toString();
          _errorMessage =
              (msg != null && msg.isNotEmpty) ? msg : '解码发生未知错误';
        });
      }
    } catch (_) {}
  }

  /// 加载媒体（Player 和 VideoController 已提前创建）
  Future<void> openMedia(String url, {Map<String, String>? httpHeaders}) async {
    _mediaUrl = url;
    _mediaHeaders = httpHeaders;
    _player?.open(Media(url, httpHeaders: httpHeaders ?? {}), play: true);
    _mediaOpened = true;
  }

  /// 兼容旧接口。
  ///
  /// [autoPlay]：是否在 open 后立即开始播放。
  /// - TikTok 门面传 false：相邻**预加载**的视频必须保持静默，只有真正切到当前页的
  ///   那条才会被显式 `play()`；否则离屏的 AVI/WMV/RMVB 会在后台同时出声（"幻听"）。
  /// - strm 单屏播放器仍用默认 true，保持原自动起播行为。
  Future<void> createFromNetwork(String url,
      {Map<String, String>? httpHeaders, bool autoPlay = true}) async {
    createPlayer();
    _mediaUrl = url;
    _mediaHeaders = httpHeaders;
    _player?.open(Media(url, httpHeaders: httpHeaders ?? {}), play: autoPlay);
    _mediaOpened = true;
  }

  void _configureFfmpeg() {
    try {
      final native = _player!.platform as dynamic;

      // ════════════════════════════════════════════════════════════════
      // 本套参数的原则：**尽量贴近 mpv 默认**。
      //
      // 实测对照：同一个 Emby 视频，Yamby（同样是 mpv 内核）能播、能拖进度条，
      // 本项目却「播不了 / 拖不动」。差异不在 URL —— Emby 官方文档明确写了
      // 「direct streaming 时文件按静态方式提供，客户端 seek 可用」，所以
      // static=true 直连这条链路本身没问题。剩下的差异只可能在参数上。
      // 之前堆的这批非默认选项里有多个是负优化，已逐条移除（理由见下方注释）。
      // ════════════════════════════════════════════════════════════════

      // ==================== 硬件解码 ====================
      // 锁死纯软解。走兼容内核的都是 FLV/WMV/AVI/RMVB 这类老格式，Android
      // 根本没有对应硬件解码器（mediacodec 不支持 FLV1 / VC-1 / WMV3 / RV40），
      // 硬解尝试只有副作用：部分机型 mediacodec 初始化会挂住 → 直接「播不了」。
      native.setProperty('hwdec', 'no');

      // ==================== 视频解码 ====================
      native.setProperty('vd-lavc-dr', 'no');
      // 明确分配 4 个解码线程，避免 auto 策略对 WMV/ASF 只分 1~2 线程
      native.setProperty('vd-lavc-threads', '4');

      // ==================== 缓存 ====================
      // ⚠️ 已移除 cache=yes / cache-secs=10。这两个是 mpv 的 **legacy 流式缓存**，
      // 新版 mpv 已改用 demuxer cache 并由它自行管理，手册明确把它们标为
      // 「legacy option for backwards compatibility」。更关键的是：legacy cache 一旦
      // 启用，网络流的 seek 要走 cache 层而非底层 HTTP Range ——正是「拖进度条被
      // 顶回开头」的高发路径。去掉后 mpv 回到默认的 demuxer cache（默认即开启），
      // seek 直接落到底层字节 seek。
      // ⚠️ 不要再压 demuxer-max-bytes / demuxer-max-back-bytes：
      // mpv 默认值远大于此前写的 50MiB / 10MiB。back-bytes 是解封装器的
      // 「向后可 seek 缓存」，调小后往回拖时 mpv 拿不到已读区间，只能弃流重新拉，
      // 表现就是进度被顶回开头。交回 mpv 默认。

      // ==================== 音频 ====================
      native.setProperty('ad-lavc-dr', 'no');

      // ==================== 同步与 seek ====================
      // 视频跟音频时钟同步，避免画面卡住不动
      native.setProperty('video-sync', 'audio');
      // 双端丢帧（decoder + vo），软解跟不上时平滑降帧而非冻住
      native.setProperty('framedrop', 'decoder+vo');
      // ⚠️ 不再覆盖 hr-seek：mpv 默认 hr-seek=default，对「绝对位置 seek」会自动
      // 启用精确 seek —— 进度条拖动走的正是这条路。之前强制 hr-seek=no（只对齐
      // 关键帧），而 FLV 这种缺索引的容器定位不到目标关键帧就会落到 0。
      // ⚠️ 同理不再设置 demuxer-lavf-probesize / analyzeduration / network-timeout：
      //  · probesize=50MB 会让 mpv 起播前在网络上狂读一大段 → 表现为「播不了」/极慢；
      //  · network-timeout=30s 对 FLV 这种要多次 Range 探测的慢 seek 太短，会中途放弃。
      // 服务端没回 Accept-Ranges / Content-Length 时 mpv 会把流判为不可 seek，
      // 拖动时直接从头重开 → 进度回到 0。强制按可 seek 处理才会发 Range 字节定位。
      native.setProperty('force-seekable', 'yes');
    } catch (_) {}
  }

  @override
  Future<void> initialize() async {
    // 监听器已在 createFromNetwork 中设置，无需重复
  }

  /// 空操作：media_kit 通过事件流自行刷新状态，无需主动轮询。
  Future<void> refresh() async {}

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seekTo(Duration position) async {
    // 取消之前挂起的 seek，直接 seek 到最新目标位置
    // 旧防抖策略会导致 UI 已恢复轮询但实际 seek 延迟执行，进度条跳动
    _seekDebounceTimer?.cancel();
    _pendingSeekPosition = null;
    _lastSeekTime = DateTime.now();
    _player?.seek(position);

    // seek 后复查：mpv 对流不可 seek 时是「静默失败」——不抛错、直接把流拉回开头。
    // 1.5s 后看真实 position 有没有到目标附近，没到就回调上层给明确提示。
    _seekVerifyTimer?.cancel();
    if (position > const Duration(seconds: 3)) {
      final target = position;
      // 给 2.5s：FLV 这种无索引容器做网络 seek 要多次 Range 探测 + 重新缓冲，
      // 判太快会把「seek 慢」误报成「seek 失败」。
      _seekVerifyTimer = Timer(const Duration(milliseconds: 2500), () {
        final st = _player?.state;
        if (st == null) return;
        // 还在缓冲 = seek 没跑完，不能下结论
        if (st.buffering) return;
        final dur = st.duration;
        // 目标超过片源实际时长（元数据不准）不算 seek 失败
        if (dur > Duration.zero && target > dur) return;
        if ((st.position - target).abs() > const Duration(seconds: 3)) {
          _diagnoseSeek();
        }
      });
    }
  }

  /// seek 实效校验失败后定位真实原因。
  ///
  /// mpv 只会静默把流拉回开头，不会告诉你为什么。而两种最可能的原因——
  /// **服务端不提供 HTTP Range** 和 **容器缺关键帧索引**——表现一模一样，
  /// 却一个客户端无从下手、一个可以针对性修复。这里实测一次 Range 请求区分开，
  /// 让用户/开发者能一步定性，而不是继续在播放器参数上试错。
  Future<void> _diagnoseSeek() async {
    if (_diagnosingSeek) return;
    _diagnosingSeek = true;
    try {
      final url = _mediaUrl;
      String reason;
      // 文案一律精简到单行放得下：页面提示条已强制 maxLines=1，
      // 折行会让那块本来「低调」的浮层突兀地鼓成两行。
      if (url == null) {
        reason = '拖动失败：媒体地址已失效';
      } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
        reason = '拖动失败：非网络流，无法定位';
      } else {
        final rangeOk =
            await SeekSupportProbe.isRangeSupported(url, _mediaHeaders);
        reason = rangeOk
            // Range 正常却仍拖不动 → 锅在容器本身：FLV/ASF 这类容器靠索引定位，
            // 缺索引时解封装器找不到目标关键帧，只能退回头。
            ? '拖动失败：片源缺少关键帧索引'
            : '拖动失败：服务端不支持 Range 定位';
      }
      onSeekFailed?.call(reason);
    } catch (_) {
      onSeekFailed?.call('拖动失败：播放器无法定位到目标位置');
    } finally {
      _diagnosingSeek = false;
    }
  }

  @override
  Future<void> reload(String url, Duration resumePosition, {Map<String, String>? httpHeaders}) async {
    _seekDebounceTimer?.cancel();
    _pendingSeekPosition = null;
    try { _player?.stop(); } catch (_) {}
    _player?.open(Media(url, httpHeaders: httpHeaders ?? {}), play: false);
    // 等待播放器完成流打开和初始化解码
    await Future.delayed(const Duration(milliseconds: 300));
    _player?.seek(resumePosition);
    _player?.play();
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
  Future<void> setVolume(double volume) async => _player?.setVolume(volume * 100);

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
    _seekVerifyTimer?.cancel();
    _seekVerifyTimer = null;
    _pendingSeekPosition = null;
    onSeekFailed = null;
    try { _player?.pause(); } catch (_) {}
    try { _player?.stop(); } catch (_) {}
    await _posSub?.cancel();
    await _playSub?.cancel();
    await _compSub?.cancel();
    await _bufferingSub?.cancel();
    await _errorSub?.cancel();
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

/// 实测服务端是否提供 HTTP Range（字节定位）请求。
///
/// 存在的理由：播放器拖进度条失败时，"服务端不可定位" 和 "容器缺索引" 的
/// 表现完全一样，但前者是服务端限制（换任何播放器都拖不动），后者可针对性修复。
/// 与其在参数上反复试错，不如发一次 Range 请求把两者钉死。
class SeekSupportProbe {
  SeekSupportProbe._();

  /// [url] 媒体直链，[headers] 播放时用到的鉴权头（否则探到的是 401）。
  static Future<bool> isRangeSupported(
      String url, Map<String, String>? headers) async {
    Dio? dio;
    try {
      dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final res = await dio.get<dynamic>(
        url,
        options: Options(
          // 只要 2 字节即可：够判定服务端认不认 Range，又不会多拉流量。
          headers: <String, dynamic>{
            if (headers != null) ...headers,
            'Range': 'bytes=0-1',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );
      final status = res.statusCode ?? 0;
      // 206 Partial Content = 明确支持 Range
      if (status == 206) return true;
      // 少数服务端返 200 但仍带 Content-Range / Accept-Ranges，也算支持
      final cr = res.headers.value('content-range');
      if (cr != null && cr.isNotEmpty) return true;
      final ar = res.headers.value('accept-ranges');
      if (ar != null && ar.toLowerCase() == 'bytes') return true;
      return false;
    } catch (_) {
      // 探测本身失败（超时 / DNS / TLS）不能据此断言服务端不支持，但也没别的信
      // 息可用。返回 true 让结论落到「容器缺索引」这一侧，避免误导成服务端问题。
      return true;
    } finally {
      dio?.close(force: true);
    }
  }
}
