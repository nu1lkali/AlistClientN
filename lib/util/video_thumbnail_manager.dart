import 'dart:async';
import 'dart:io';

import 'package:alist/util/alist_plugin.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

/// 视频缩略图管理器
/// - 并发限制：最多同时 3 个取帧任务
/// - 缓存：以 cacheKey 为文件名存储到 app 缓存目录
class VideoThumbnailManager {
  static final VideoThumbnailManager _instance = VideoThumbnailManager._();
  static VideoThumbnailManager get instance => _instance;
  VideoThumbnailManager._();

  static const _maxConcurrent = 3;
  int _running = 0;
  final _queue = <_ThumbnailTask>[];
  String? _cacheDir;

  Future<String> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final dir = await getTemporaryDirectory();
    _cacheDir = '${dir.path}/video_thumbs';
    await Directory(_cacheDir!).create(recursive: true);
    return _cacheDir!;
  }

  /// 生成缩略图，返回本地文件路径；已有缓存直接返回
  Future<String?> getThumbnail({
    required String url,
    required String cacheKey,
    int positionMs = 10000,
    Map<String, String>? headers,
  }) async {
    final dir = await _getCacheDir();
    final safeKey = _safeKey(cacheKey);
    final cached = File('$dir/$safeKey.jpg');
    if (await cached.exists()) return cached.path;

    final completer = Completer<String?>();
    _queue.add(_ThumbnailTask(
      url: url,
      cacheKey: safeKey,
      cacheDir: dir,
      positionMs: positionMs,
      headers: headers,
      completer: completer,
    ));
    _drain();
    return completer.future;
  }

  void _drain() {
    while (_running < _maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      _running++;
      _execute(task);
    }
  }

  Future<void> _execute(_ThumbnailTask task) async {
    try {
      final path = await AlistPlugin.generateVideoThumbnail(
        url: task.url,
        cacheKey: task.cacheKey,
        cacheDir: task.cacheDir,
        positionMs: task.positionMs,
        headers: task.headers,
      );
      task.completer.complete(path);
    } catch (e) {
      task.completer.complete(null);
    } finally {
      _running--;
      _drain();
    }
  }

  /// 清除所有缩略图缓存
  Future<void> clearCache() async {
    final dir = await _getCacheDir();
    final d = Directory(dir);
    if (await d.exists()) await d.delete(recursive: true);
    _cacheDir = null;
  }

  String _safeKey(String key) {
    // 用 MD5 确保文件名合法
    return md5.convert(utf8.encode(key)).toString();
  }
}

class _ThumbnailTask {
  final String url;
  final String cacheKey;
  final String cacheDir;
  final int positionMs;
  final Map<String, String>? headers;
  final Completer<String?> completer;

  _ThumbnailTask({
    required this.url,
    required this.cacheKey,
    required this.cacheDir,
    required this.positionMs,
    required this.headers,
    required this.completer,
  });
}
