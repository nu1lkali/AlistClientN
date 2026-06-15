import 'dart:io';

import 'package:alist/util/strm_parser.dart';

/// 公共的流媒体真实大小解析服务
///
/// 用于 .strm 文件场景：.strm 文件本身只有几十字节，
/// 需要通过 HEAD 请求获取远程视频流的实际大小。
///
/// 使用方式：
///   final size = await StreamSizeResolver.resolve(videoUrl);
///   if (size != null) fileSize = size;
class StreamSizeResolver {
  StreamSizeResolver._();

  static final Map<String, int> _sizeCache = {};

  /// 获取远程流媒体的实际大小（结果会缓存，同一URL只请求一次）
  ///
  /// 优先用 GET Range bytes=0-0 从 Content-Range 头解析总大小，
  /// CDN 将其视为正常播放请求，不易触发风控。
  /// 若 Range 请求失败或未返回大小，则兜底 HEAD。
  ///
  /// [url] - 远程视频流的完整 URL
  /// [timeout] - 请求超时时间，默认 3 秒
  ///
  /// 返回文件大小（字节），失败返回 null
  static Future<int?> resolve(String url, {Duration? timeout}) async {
    if (_sizeCache.containsKey(url)) return _sizeCache[url];
    final effectiveTimeout = timeout ?? const Duration(seconds: 3);
    int? size = await _resolveWithRangeGet(url, effectiveTimeout);
    size ??= await _resolveWithHead(url, effectiveTimeout);
    if (size != null && size > 0) {
      _sizeCache[url] = size;
      return size;
    }
    return null;
  }

  /// GET Range bytes=0-0，从 Content-Range: bytes 0-0/TOTAL 解析总大小
  static Future<int?> _resolveWithRangeGet(String url, Duration timeout) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = timeout;
      client.idleTimeout = const Duration(seconds: 3);
      final req = await client.openUrl('GET', Uri.parse(url));
      req.headers.set('Range', 'bytes=0-0');
      final resp = await req.close();
      int? size;
      if (resp.statusCode == 206) {
        final cr = resp.headers.value('content-range');
        if (cr != null) {
          final m = RegExp(r'/(\d+)').firstMatch(cr);
          if (m != null) size = int.tryParse(m.group(1)!);
        }
        size ??= resp.contentLength;
      } else if (resp.statusCode == 200) {
        size = resp.contentLength;
      }
      client.close(force: true);
      if (size != null && size > 0) return size;
    } catch (_) {}
    return null;
  }

  /// HEAD 请求兜底
  static Future<int?> _resolveWithHead(String url, Duration timeout) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = timeout;
      client.idleTimeout = const Duration(seconds: 3);
      final req = await client.openUrl('HEAD', Uri.parse(url));
      final resp = await req.close();
      final length = resp.contentLength;
      client.close(force: true);
      if (length > 0) return length;
    } catch (_) {}
    return null;
  }

  /// 判断文件是否为 .strm 类型（基于路径后缀）
  static bool isStrmFile(String path) {
    return StrmParser.isStrmFile(path);
  }

  /// 异步解析 .strm 文件的真实流大小并回调
  ///
  /// [videoUrl] - 已解析的视频流 URL
  /// [onResolved] - 成功获取大小后的回调
  ///
  /// 非阻塞，适合在后台调用
  static void resolveAsync(String videoUrl, void Function(int size) onResolved) {
    resolve(videoUrl).then((size) {
      if (size != null && size > 0) {
        onResolved(size);
      }
    });
  }
}
