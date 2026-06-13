import 'dart:io';

import 'package:alist/util/log_utils.dart';
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

  /// 通过 HEAD 请求获取远程流媒体的实际大小
  ///
  /// [url] - 远程视频流的完整 URL
  /// [timeout] - 请求超时时间，默认 3 秒（避免阻塞播放体验）
  ///
  /// 返回文件大小（字节），失败返回 null
  static Future<int?> resolve(String url, {Duration? timeout}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = timeout ?? const Duration(seconds: 3);
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
