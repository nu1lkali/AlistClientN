import 'dart:async';

import 'package:alist/util/player/container_sniffer.dart';
import 'package:alist/util/video_engine.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 视频播放内核。
///
/// - [exo]：ExoPlayer（video_player 插件），硬解，性能好，作为默认内核；
/// - [compat]：libmpv（media_kit，自带完整 FFmpeg），只在 ExoPlayer 放不出来的
///   老格式（WMV/ASF、AVI、RMVB、MPEG 家族、TS、FLV 等）上启用。
///
/// 注：项目早期用 IJK（GSY 预编译的 libijkffmpeg.so）做兼容内核，但该 .so
/// 既没编入 ASF 解封装器（WMV 连容器都打不开），也放不出 AVI 内常见编码，
/// 故兼容内核统一改为 media_kit（libmpv 自带完整 FFmpeg，含 ASF/VC-1）。
enum TikTokEngine { exo, compat }

/// 交给兼容内核（libmpv）兜底的格式清单。
///
/// 判据只有一条：**ExoPlayer 有没有对应的解封装器 / 设备有没有对应解码器**。
/// - `wmv / wm / asf / asx / wvx / wmx / wtv / dvr-ms`：ASF 容器，Exo 无 demuxer，
///   且 IJK 的预编译 .so 也没编 ASF，只能走 media_kit；
/// - `avi / divx / xvid / nsv`：容器 Exo 有，但里面常见 H.264/DivX 在不少设备上
///   只有软解、IJK 同样放不出，统一交给 media_kit 更稳；
/// - `rmvb / rm / ra / ram`：RealMedia，Exo/IJK 都放不出；
/// - `mpg / mpeg / vob / dat / ts / m2ts ...`：MPEG 家族，设备解码器不全；
/// - `flv / f4v`：老站点常见 VP6 / Sorenson 编码。
/// `mp4 / mkv / webm / mov` 这类不动 —— Exo 硬解体验最好。
const Set<String> kCompatFormatsHandledByMediaKit = <String>{
  // Windows Media / ASF
  'wmv', 'wm', 'asf', 'asx', 'wmx', 'wvx', 'wtv', 'dvr-ms',
  // AVI / DivX / Xvid
  'avi', 'divx', 'xvid', 'nsv',
  // RealMedia
  'rmvb', 'rm', 'ra', 'ram',
  // MPEG-PS / Program Stream
  'mpg', 'mpeg', 'mpe', 'm1v', 'm2v', 'mp2', 'vcd', 'vob', 'dat',
  // MPEG-TS 家族
  'ts', 'm2ts', 'mts', 'm2t',
  // FLV 家族
  'flv', 'f4v',
};

/// 文件名 → 是否需要使用兼容解码内核（libmpv）。
bool needsCompatKernel(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return false;
  final ext = fileName.substring(dot + 1).toLowerCase();
  return kCompatFormatsHandledByMediaKit.contains(ext);
}

/// TikTok 播放器的播放内核门面。
///
/// 对上只暴露一组统一的读值 / 控制方法，内部可能是 ExoPlayer 或 libmpv。
/// 这样播放器页面里除「创建」和「渲染」两处之外的代码完全不用关心当前是哪个内核，
/// 也不会出现两个内核各写一套逻辑的版本。
class TikTokPlaybackCore {
  TikTokPlaybackCore._(this.engine);

  final TikTokEngine engine;

  VideoPlayerController? _exo;
  MediaKitEngine? _mk;
  // 缓存 media_kit 的 Video 控件实例：避免每次进度刷新 setState 都重建 Texture
  // 导致画面闪烁 / 平台视图反复挂载。
  Widget? _mkView;

  /// 内核名，用于信息面板 / toast 提示
  String get engineName => engine == TikTokEngine.compat ? 'libmpv' : 'ExoPlayer';

  Future<void> _prepare({
    required TikTokEngine engine,
    required String url,
    Map<String, String>? headers,
    required bool autoPlay,
    required String fileName,
    bool forceSoft = false,
  }) async {
    if (engine == TikTokEngine.compat) {
      final e = MediaKitEngine();
      // 先挂到实例上再 initialize：并行赛跑中途弃用 compat 时 dispose 才有目标，
      // 不会把还在探测 / 下载的 native 播放器漏在后台。
      _mk = e;
      // libmpv 自带完整 FFmpeg，无需「强制软解」开关；forceSoft 在此忽略。
      // autoPlay:false —— 相邻预加载视频保持静默，只有真正切到当前页才被显式 play()，
      // 否则 WMV/AVI/RMVB 等离屏视频会在后台同时出声（"幻听"）。
      await e.createFromNetwork(url, httpHeaders: headers ?? const {}, autoPlay: false);
      // 缓存渲染控件，保证后续每次 rebuild 复用同一实例（见 [_mkView]）。
      _mkView = SizedBox.expand(child: e.buildVideoWidget());
      return;
    }
    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers ?? const {},
    );
    // 先挂到实例上再 initialize：并行赛跑中途放弃 Exo 时，
    // dispose() 才能真正释放到这个 controller，不会泄漏半个初始化的实例。
    _exo = ctrl;
    await ctrl.initialize();
    // Exo 有一部分错误不会抛异常，而是塞进 value.hasError
    // （DataSource.file could not be loaded / codec querying error 之类）。
    // 这里把它也当成失败抛出去，好让 create() 的回落真正兜住这类片子。
    if (ctrl.value.hasError) {
      final msg = ctrl.value.errorDescription ?? 'ExoPlayer 初始化失败';
      await ctrl.dispose();
      _exo = null;
      throw Exception(msg);
    }
    ctrl.setLooping(false);
  }

  /// 静默释放一个内核并等它的 Future 收尾（后台执行，防止未处理异步错误）。
  static Future<void> _discardCore(Future<void> done, TikTokPlaybackCore core) async {
    try {
      await core.dispose();
    } catch (_) {}
    try {
      await done;
    } catch (_) {}
  }

  /// 停掉一个内核并**等它的连接真正断开**（最多 3 秒），保证串行回落时
  /// 不会出现两条并发连接 —— 这是规避 CDN / 网盘「多连接下载」风控的关键。
  ///
  /// video_player 的 dispose 会先等创建 completer；Exo 卡在网络层时 dispose
  /// 可能长时间不返回，这里用 3 秒上限兜底：超时就先走（旧连接由它自己的
  /// HTTP 超时最终回收），绝不为等它阻塞 libmpv 的启动太久。
  static Future<void> _stopCore(Future<void> done, TikTokPlaybackCore core) async {
    try {
      await core.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
    unawaited(
      done.catchError((Object e) {}),
    );
  }

  static Future<TikTokPlaybackCore> _createCompat({
    required String url,
    Map<String, String>? headers,
    required String fileName,
    required bool autoPlay,
    bool forceSoft = false,
  }) async {
    final core = TikTokPlaybackCore._(TikTokEngine.compat);
    await core._prepare(
      engine: TikTokEngine.compat,
      url: url,
      headers: headers,
      autoPlay: autoPlay,
      fileName: fileName,
      forceSoft: forceSoft,
    );
    return core;
  }

  /// 用嗅探到的真实响应速度推算 Exo 的耐心上限：
  /// - 快服务器（TTFB ~200ms）→ ~4 秒：真打不开的片子不用陪它干等；
  /// - 慢服务器（TTFB 1.5s+）→ 15 秒封顶：别把「网络慢」误判成「放不了」。
  /// 嗅探失败按中等速度（1.2s）估计。
  static Duration _exoPatience(ContainerSniff? sniff) {
    final l = (sniff?.latencyMs ?? 1200).clamp(0, 5000);
    final ms = (l * 3 + 3000).clamp(5000, 15000);
    return Duration(milliseconds: ms);
  }

  /// 创建播放器。
  ///
  /// [forceCompat] 为 true 时直接用 libmpv 兼容内核（老格式 / 用户手动指定）。
  ///
  /// 常规格式的选路流程（**全程对同一个 URL 只保持一条活跃连接**，
  /// 避免触发 CDN / 网盘的多连接下载风控）：
  /// 1. **容器嗅探**：一次 8KB 的 Range 请求读文件头魔数，扩展名骗人的
  ///    片子（.mp4 里装 DivX 等）直接跳过必失败的 Exo；
  /// 2. Exo 优先，耐心上限按嗅探到的服务器速度自适应（5~15 秒）；
  /// 3. Exo **快失败**或**超耐心**：先停掉 Exo 的连接，再串行回落 libmpv；
  /// 4. [isAborted] 返回 true（用户点了手动切内核）→ 立刻停掉在途的 Exo
  ///    并抛 [KernelAbortedException]，让新的初始化接管。
  static Future<TikTokPlaybackCore> create({
    required String url,
    Map<String, String>? headers,
    required String fileName,
    required bool autoPlay,
    bool forceCompat = false,
    bool forceSoft = false,
    bool Function()? isAborted,
  }) async {
    // 老格式（或手动指定）：Exo 必失败，直接 libmpv，一秒都不浪费
    if (forceCompat || needsCompatKernel(fileName)) {
      return _createCompat(
        url: url,
        headers: headers,
        fileName: fileName,
        autoPlay: autoPlay,
        forceSoft: forceSoft,
      );
    }

    // ── 容器嗅探：先弄清「这到底是什么容器」再选内核 ──
    final sniff = await ContainerSniffer.sniff(url, headers ?? const {});
    if (isAborted?.call() == true) throw const KernelAbortedException();
    if (sniff != null && !sniff.kind.exoFriendly) {
      // 嗅探确认是 Exo 放不了的容器（AVI/RM/ASF/MPEG-PS/TS）→ 直接 libmpv
      return _createCompat(
        url: url,
        headers: headers,
        fileName: fileName,
        autoPlay: autoPlay,
        forceSoft: forceSoft,
      );
    }

    // ── Exo 优先（串行），耐心按服务器速度自适应 ──
    final exo = TikTokPlaybackCore._(TikTokEngine.exo);
    Object? exoError;
    final exoDone = exo._prepare(
      engine: TikTokEngine.exo,
      url: url,
      headers: headers,
      autoPlay: autoPlay,
      fileName: fileName,
    );
    // watch 永不抛错：完成状态收进 exoSettled，错误收进 exoError
    var exoSettled = false;
    final watch = exoDone.then<void>((_) {
      exoSettled = true;
    }, onError: (Object e) {
      exoError = e;
      exoSettled = true;
    });

    final patience = _exoPatience(sniff);
    final deadline = DateTime.now().add(patience);
    while (!DateTime.now().isAfter(deadline)) {
      if (isAborted?.call() == true) {
        // 用户手动切内核：立刻掐断这条在途连接，把选择权交给新初始化
        await _stopCore(exoDone, exo);
        throw const KernelAbortedException();
      }
      await Future.any<void>(<Future<void>>[
        watch,
        Future<void>.delayed(const Duration(milliseconds: 120)),
      ]);
      if (exoSettled) break;
    }

    if (exoError != null) {
      // 快失败：先归零连接，再串行回落 libmpv
      await _stopCore(exoDone, exo);
      try {
        return await _createCompat(
          url: url,
          headers: headers,
          fileName: fileName,
          autoPlay: autoPlay,
          forceSoft: forceSoft,
        );
      } catch (_) {
        // 双失败：把 Exo 的原始异常抛给上层提示
        throw exoError!;
      }
    }
    if (exoSettled && exo.isInitialized && !exo.hasError) {
      return exo; // Exo 正常，直接用
    }
    // 超耐心（慢失败）：停掉 Exo 再起 libmpv —— 宁可多等几秒，
    // 也不在同一个 CDN URL 上开两条并发连接去赌风控。
    await _stopCore(exoDone, exo);
    if (isAborted?.call() == true) throw const KernelAbortedException();
    return await _createCompat(
      url: url,
      headers: headers,
      fileName: fileName,
      autoPlay: autoPlay,
      forceSoft: forceSoft,
    );
  }

  // ══════════════ 读值 ══════════════

  bool get isInitialized {
    final exo = _exo;
    if (exo != null) return exo.value.isInitialized;
    return _mk?.isInitialized ?? false;
  }

  /// 画面是否**真的渲染出了第一帧**。
  ///
  /// 两个内核的语义不一样：
  /// - ExoPlayer 到达 ready 时就已经把首帧画上（暂停状态也有静帧），所以
  ///   `isInitialized` ≈ 有画面；
  /// - libmpv 的 `isInitialized` 在 `open()` 后立刻为真，但首帧可能还没解出。
  ///   这里用 `width > 0` 当「有画面」判据——这同时是规避 media_kit
  ///   **首帧撕裂**的关键：画面真正稳定（首帧解出）后才允许上屏，
  ///   撕裂只出现在首帧解出前的瞬时 Surface，被 loading 画面挡住，用户看不到。
  bool get isFrameVisible {
    final exo = _exo;
    if (exo != null) return exo.value.isInitialized;
    final mk = _mk;
    if (mk != null) {
      final sz = mk.videoSize;
      return mk.isInitialized && sz.width > 0 && sz.height > 0;
    }
    return false;
  }

  /// 兼容旧调用点：等价于 [isFrameVisible]。
  bool get isFrameReady => isFrameVisible;

  Duration get position {
    final exo = _exo;
    if (exo != null) return exo.value.position;
    return _mk?.position ?? Duration.zero;
  }

  Duration get duration {
    final exo = _exo;
    if (exo != null) return exo.value.duration;
    return _mk?.duration ?? Duration.zero;
  }

  Size get size {
    final exo = _exo;
    if (exo != null) return exo.value.size;
    return _mk?.videoSize ?? Size.zero;
  }

  double get aspectRatio {
    final exo = _exo;
    if (exo != null) return exo.value.aspectRatio;
    return _mk?.aspectRatio ?? (16 / 9);
  }

  bool get isPlaying {
    final exo = _exo;
    if (exo != null) return exo.value.isPlaying;
    return _mk?.isPlaying ?? false;
  }

  bool get isBuffering {
    final exo = _exo;
    if (exo != null) return exo.value.isBuffering;
    return _mk?.isBuffering ?? false;
  }

  bool get hasError {
    final exo = _exo;
    if (exo != null) return exo.value.hasError;
    return _mk?.hasError ?? false;
  }

  /// 内核最近一次错误的可读描述（无错误时为空串）。
  ///
  /// 供页面把「创建成功后才冒出来的错误」展示到错误页上。
  String get errorMessage {
    final exo = _exo;
    if (exo != null) return exo.value.errorDescription ?? '';
    return _mk?.errorMessage ?? '';
  }

  /// Exo 的已缓冲区间；libmpv 没有区间概念，返回空列表。
  List<DurationRange> get buffered {
    final exo = _exo;
    if (exo != null) return exo.value.buffered;
    return const [];
  }

  /// 内核自己统计的真实下行速率（字节/秒）。
  /// Exo 与 libmpv 都不暴露该值，统一返回 0，由上层走系统流量采样。
  int get nativeSpeedBps => 0;

  /// libmpv 无「已缓冲时长」概念，返回零。
  Duration get cachedAhead => _mk?.cachedAhead ?? Duration.zero;

  // ══════════════ 控制 ══════════════

  Future<void> play() async {
    final exo = _exo;
    if (exo != null) {
      await exo.play();
      return;
    }
    await _mk?.play();
  }

  Future<void> pause() async {
    final exo = _exo;
    if (exo != null) {
      await exo.pause();
      return;
    }
    await _mk?.pause();
  }

  Future<void> seekTo(Duration target) async {
    final exo = _exo;
    if (exo != null) {
      await exo.seekTo(target);
      return;
    }
    await _mk?.seekTo(target);
  }

  Future<void> setLooping(bool looping) async {
    final exo = _exo;
    if (exo != null) {
      // 这里不能 await：某些设备上 Exo 的 setLooping 会等到缓冲状态更新才返回，
      // 拖住的话切换视频会明显变慢。
      exo.setLooping(looping);
      return;
    }
    await _mk?.setLooping(looping);
  }

  /// libmpv 事件驱动（位置/时长走 Stream 自行刷新），无需轮询；Exo 自身是
  /// ChangeNotifier，也无需处理。这里留作统一出口，便于将来扩展。
  Future<void> tick() async {
    await _mk?.refresh();
  }

  Future<void> dispose() async {
    try {
      await _exo?.dispose();
    } catch (_) {}
    _exo = null;
    try {
      await _mk?.dispose();
    } catch (_) {}
    _mk = null;
    _mkView = null;
  }

  /// 渲染该内核对应的画面。
  ///
  /// libmpv 分支用 `SizedBox.expand` 包成**全屏固定尺寸**的 Texture：
  /// 固定尺寸能避免首帧期间父级 AspectRatio/布局抖动触发 media_kit 的
  /// **首帧撕裂**，画面内部用 `BoxFit.contain` 自行留边。
  Widget buildView() {
    final exo = _exo;
    if (exo != null) return VideoPlayer(exo);
    if (_mkView != null) return _mkView!;
    return const SizedBox.expand();
  }

  /// 当前画面能否用 RepaintBoundary 截图（libmpv 走纹理，截不到内容）。
  bool get supportsTextureScreenshot => _exo != null;
}

/// 在途初始化被更新的请求取代时抛出（用户点了「手动切内核」/ 触发重试）。
///
/// 页面侧按代次判断后静默忽略，不进错误 UI、不打扰用户。
class KernelAbortedException implements Exception {
  const KernelAbortedException();

  @override
  String toString() => 'kernel init aborted';
}
