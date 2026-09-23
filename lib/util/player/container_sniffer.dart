import 'dart:async';
import 'dart:io';

/// 真实容器类型。
enum ContainerKind {
  mp4,
  mov,
  matroska,
  webm,
  avi,
  realMedia,
  asf,
  mpegTs,
  mpegPs,
  flv,
  ogg,

  /// 嗅探成功但认不出 —— 保守交给 Exo（维持原有行为）。
  unknown;

  /// ExoPlayer 能否稳妥处理这种容器。
  ///
  /// false 的四类正是「Exo 必失败」的老容器：AVI（内里 MPEG-4 ASP / DivX）、
  /// RealMedia（RM/RMVB）、ASF（WMV/VC-1）、MPEG-PS/TS（MPEG-2）。
  /// 这些直接走 FFmpeg 内核，一秒都不浪费在 Exo 上。
  bool get exoFriendly {
    switch (this) {
      case ContainerKind.avi:
      case ContainerKind.realMedia:
      case ContainerKind.asf:
      case ContainerKind.mpegTs:
      case ContainerKind.mpegPs:
        return false;
      default:
        return true;
    }
  }
}

/// 一次嗅探的结果：容器类型 + 本次请求的响应速度（毫秒）。
class ContainerSniff {
  const ContainerSniff({required this.kind, required this.latencyMs});

  final ContainerKind kind;

  /// 从发起到读到首字节/头部数据的耗时，用于推算 Exo 的合理等待上限。
  final int latencyMs;
}

/// 播放前的容器嗅探器。
///
/// 用一个 **8KB 的 Range 请求**读文件头，凭魔数判断真实容器：
/// - 扩展名经常骗人（`.mp4` 里装 DivX、`.mkv` 改名 `.mp4` 是常态），
///   嗅探能直接跳过必失败的 Exo，把「切内核等半天」变成「一上来就对」；
/// - 顺带测一次服务器响应速度，给后面 Exo 的等待上限提供依据；
/// - 结果按 URL 缓存：左右滑来回切同一个视频不会重复发请求。
///
/// 代价与风控：每次播放**只多发这一个小请求**，且与后续真正的播放连接
/// 严格串行（绝不并发两条下载连接），不会触发 CDN / 网盘的多连接限制。
class ContainerSniffer {
  ContainerSniffer._();

  static final Map<String, ContainerSniff> _cache = {};

  /// 嗅探失败返回 null（调用方按「未知容器」处理，不阻塞播放主流程）。
  static Future<ContainerSniff?> sniff(
    String url,
    Map<String, String> headers,
  ) async {
    final cached = _cache[url];
    if (cached != null) return cached;

    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null; // 本地路径等场景没有嗅探意义
    }

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      headers.forEach(req.headers.set);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-8191');

      final watch = Stopwatch()..start();
      final res = await req.close().timeout(const Duration(seconds: 6));
      // 服务器不支持 Range 时可能回整包 200 —— 读够判断用的字节数
      // 就立刻断开，绝不把带宽耗在这。
      final head = <int>[];
      await for (final chunk
          in res.timeout(const Duration(seconds: 6),
              onTimeout: (EventSink<List<int>> sink) {
        sink.close();
      })) {
        head.addAll(chunk);
        if (head.length >= 4096) break;
      }
      watch.stop();

      final kind = detect(head);
      final sniff = ContainerSniff(kind: kind, latencyMs: watch.elapsedMilliseconds);
      _cache[url] = sniff;
      return sniff;
    } catch (_) {
      return null;
    } finally {
      // force：不管读没读完都立刻断开这条连接
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }

  /// 按魔数识别容器。只认头部 12 字节内就能判断的类型。
  static ContainerKind detect(List<int> b) {
    if (b.length < 12) return ContainerKind.unknown;

    bool ascii(int off, String sig) {
      if (off + sig.length > b.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[off + i] != sig.codeUnitAt(i)) return false;
      }
      return true;
    }

    // RealMedia：".RMF"
    if (ascii(0, '.RMF')) return ContainerKind.realMedia;
    // AVI：RIFF....AVI␣（AVIX 变体也在 8~11 位）
    if (ascii(0, 'RIFF') && (ascii(8, 'AVI ') || ascii(8, 'AVIX'))) {
      return ContainerKind.avi;
    }
    // ASF / WMV：30 26 B2 75 8E 66 CF 11
    if (b[0] == 0x30 && b[1] == 0x26 && b[2] == 0xB2 && b[3] == 0x75) {
      return ContainerKind.asf;
    }
    // Matroska / WebM：1A 45 DF A3
    if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) {
      return ContainerKind.matroska;
    }
    // MP4 / MOV / M4V：4~7 位是 "ftyp"
    if (ascii(4, 'ftyp')) return ContainerKind.mp4;
    // FLV
    if (ascii(0, 'FLV')) return ContainerKind.flv;
    // MPEG-PS（VOB/MPG 常见）：00 00 01 BA
    if (b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x01 && b[3] == 0xBA) {
      return ContainerKind.mpegPs;
    }
    // MPEG-TS：0x47 每 188 字节重复；M2TS 是 192 字节包（前 4 字节时间戳）
    if (b[0] == 0x47 && b.length > 188 && b[188] == 0x47) {
      return ContainerKind.mpegTs;
    }
    if (b.length > 4 + 192 && b[4] == 0x47 && b[4 + 192] == 0x47) {
      return ContainerKind.mpegTs;
    }
    // Ogg
    if (ascii(0, 'OggS')) return ContainerKind.ogg;
    return ContainerKind.unknown;
  }
}
