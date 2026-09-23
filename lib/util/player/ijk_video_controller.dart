import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// IJK（FFmpeg）播放内核的 Dart 侧控制器。
///
/// 画面由原生分配的 `SurfaceTexture` 提供，Dart 侧只用 `Texture` 渲染，
/// 因此它和 ExoPlayer 的 `VideoPlayer` 一样，就是一块会自己刷新的视频画面，
/// 外层不需要为它改任何手势 / HUD 逻辑。
///
/// 状态采用**拉取式**（[refresh]）：由播放器页面已有的 400ms 定时器统一驱动，
/// 这样 Exo 与 IJK 两条链路的刷新节奏完全一致，不会出现两套重建时机。
class IjkVideoController {
  static const MethodChannel _ch =
      MethodChannel('com.github.alist.clientn.plugin');

  /// 预热 IJK 的 native 解码库（进播放器页时调用，失败静默）。
  ///
  /// `libijkffmpeg.so` 有 5MB+，第一次回落 FFmpeg 内核时才装载会把
  /// 「切换内核」的等待再拉长几百毫秒，这里提前到进页面就后台加载。
  static Future<void> preloadLibraries() async {
    try {
      await _ch.invokeMethod<void>('ijkPreload');
    } catch (_) {}
  }

  int? _id;
  int? _textureId;
  bool _disposed = false;

  /// 播放器内核已准备就绪（IJK 已收到 onPrepared）
  bool ready = false;

  /// 首帧是否已经渲染出来（用于决定何时摘掉 loading）
  bool firstFrameRendered = false;

  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  Size size = Size.zero;
  bool playing = false;
  bool buffering = false;
  bool hasError = false;
  String errorMessage = '';

  /// IJK 原生统计的真实下行速率（字节/秒）
  int tcpSpeedBps = 0;

  /// 已缓冲的时长（毫秒）
  Duration cachedDuration = Duration.zero;

  int? get textureId => _textureId;

  double get aspectRatio {
    if (size.height <= 0 || size.width <= 0) return 16 / 9;
    return size.width / size.height;
  }

  Future<void> initialize({
    required String url,
    Map<String, String> headers = const {},
    required bool autoPlay,
    String fileName = '',
    bool forceSoft = false,
  }) async {
    final res = await _ch.invokeMethod<Map<dynamic, dynamic>>(
      'createIjkPlayer',
      <String, dynamic>{
        'url': url,
        'headers': headers,
        'autoPlay': autoPlay,
        // 原生侧按扩展名决定要不要强制软解（rmvb 这类没有硬解器）
        'fileName': fileName,
        // 硬解已经试过一次仍无首帧时置位：强制纯 FFmpeg 软解再试
        'forceSoft': forceSoft,
      },
    );
    if (res == null) throw Exception('无法创建 IJK 播放器实例');
    _id = res['id'] is int ? res['id'] as int : int.tryParse('${res['id']}');
    final tid = res['textureId'];
    _textureId = tid is int ? tid : (tid is num ? tid.toInt() : null);
    if (_id == null || _textureId == null) {
      throw Exception('创建 IJK 播放器失败');
    }

    // 等到 onPrepared（或先等到报错）再返回，语义上和 Exo 的 initialize() 对齐。
    // 不做这一步的话：错误（比如 native 库没加载、链接 404）在 create 之后
    // 才异步冒出来，上层拿到的永远是一个「还没准备好」的核，界面就一直转圈。
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      await refresh();
      if (_disposed) return;
      if (hasError) {
        throw Exception(
            errorMessage.isNotEmpty ? errorMessage : 'FFmpeg 内核打开失败');
      }
      if (ready) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    // 超时不抛：网络特别慢时 IJK 可能还在缓冲，交给页面的轮询继续等，
    // 这样至少不会把一个本来能放的片子判死。
  }

  /// 拉取一次播放器状态（供播放器页面的定时器调用）。
  Future<void> refresh() async {
    if (_disposed || _id == null) return;
    Map<dynamic, dynamic>? s;
    try {
      s = await _ch.invokeMethod<Map<dynamic, dynamic>>(
        'ijkGetState',
        <String, dynamic>{'id': _id},
      );
    } catch (_) {
      return;
    }
    if (s == null) return;
    ready = s['ready'] == true;
    firstFrameRendered = s['firstFrame'] == true;
    hasError = s['error'] == true;
    errorMessage = (s['errorMessage'] ?? '').toString();
    final w = (s['width'] as num?)?.toDouble() ?? 0;
    final h = (s['height'] as num?)?.toDouble() ?? 0;
    if (w > 0 && h > 0) size = Size(w, h);
    duration = Duration(milliseconds: (s['durationMs'] as num?)?.toInt() ?? 0);
    position = Duration(milliseconds: (s['positionMs'] as num?)?.toInt() ?? 0);
    cachedDuration =
        Duration(milliseconds: (s['cachedDurationMs'] as num?)?.toInt() ?? 0);
    playing = s['playing'] == true;
    buffering = s['buffering'] == true;
    tcpSpeedBps = (s['tcpSpeed'] as num?)?.toInt() ?? 0;
  }

  Future<void> play() => _invoke('ijkPlay');

  Future<void> pause() => _invoke('ijkPause');

  Future<void> seekTo(Duration target) => _invoke(
        'ijkSeekTo',
        <String, dynamic>{'positionMs': target.inMilliseconds},
      );

  Future<void> setLooping(bool looping) => _invoke(
        'ijkSetLooping',
        <String, dynamic>{'looping': looping},
      );

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final id = _id;
    _id = null;
    if (id == null) return;
    try {
      await _ch.invokeMethod<void>(
          'ijkDispose', <String, dynamic>{'id': id});
    } catch (_) {}
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (_disposed || _id == null) return;
    final payload = <String, dynamic>{'id': _id};
    if (args != null) payload.addAll(args);
    try {
      await _ch.invokeMethod<void>(method, payload);
    } catch (_) {}
  }
}

/// 把 IJK 的 SurfaceTexture 渲染到 Flutter 树里。
///
/// 注意这里不能用 `RepaintBoundary` 去截图 —— 纹理内容不参与 Flutter 的合成，
/// toImage 拿到的是黑的。截图在 IJK 内核下会走「不支持」提示。
class IjkVideoView extends StatelessWidget {
  final IjkVideoController controller;

  const IjkVideoView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final textureId = controller.textureId;
    if (textureId == null) return const SizedBox.expand();
    return Texture(
      textureId: textureId,
      filterQuality: FilterQuality.low,
    );
  }
}
