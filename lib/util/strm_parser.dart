import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math' show Random;

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/strm_url_cache.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/user_controller.dart';
import 'package:dio/dio.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// .strm 文件解析工具类
///
/// .strm 文件是一个纯文本文件，内部存储了一段完整的视频流 URL。
/// 示例内容：
///   http://192.168.2.124:8024/smartstrm_fid/open115_php112/.../?sign=...
///
/// 该类负责：
/// 1. 通过 alist 直链读取 .strm 文件的文本内容
/// 2. 清洗提取出的 URL（去除首尾空白、换行符等）
/// 3. 验证 URL 格式的合法性
class StrmParser {
  static final RegExp _invisibleCharsRegex = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u200B-\u200F\uFEFF]',
  );

  // ============ 并发池 ============
  static int _activeCount = 0;
  static const int _maxConcurrent = 8;
  static final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  // ============ 内存缓存（快速层） ============
  static final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();
  static const int _maxCacheSize = 200;
  static const Duration _cacheTTL = Duration(minutes: 10);

  // ============ 安全限制 ============
  static const int _maxContentSize = 512 * 1024;

  // ============ 重试策略 ============
  static const int _maxRetries = 3;
  static const Duration _retryBaseDelay = Duration(milliseconds: 500);
  static final Random _random = Random();

  /// 带并发限制的任务执行器
  static Future<T> _withPool<T>(Future<T> Function() task) async {
    while (_activeCount >= _maxConcurrent) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
    }
    _activeCount++;
    try {
      return await task();
    } finally {
      _activeCount--;
      if (_waitQueue.isNotEmpty) {
        _waitQueue.removeFirst().complete();
      }
    }
  }

  static String? _getCached(String path) {
    final entry = _cache[path];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.timestamp) > _cacheTTL) {
      _cache.remove(path);
      return null;
    }
    return entry.url;
  }

  /// 从数据库获取缓存（持久层）
  static Future<String?> _getCachedFromDb(String path) async {
    try {
      final db = Get.find<AlistDatabaseController>();
      final user = Get.find<UserController>().user.value;
      final record = await db.strmUrlCacheDao.findByPath(
        user.serverUrl,
        user.username,
        path,
      );
      if (record != null) {
        // 写入内存缓存
        _cache[path] = _CacheEntry(record.url);
        return record.url;
      }
    } catch (_) {}
    return null;
  }

  static void _putCache(String path, String url) {
    if (_cache.length >= _maxCacheSize && !_cache.containsKey(path)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[path] = _CacheEntry(url);
    // 异步写入数据库（持久层）
    _putCacheToDb(path, url);
  }

  /// 将缓存写入数据库
  static Future<void> _putCacheToDb(String path, String url) async {
    try {
      final db = Get.find<AlistDatabaseController>();
      final user = Get.find<UserController>().user.value;
      // 先删除旧记录
      await db.strmUrlCacheDao.deleteByPath(user.serverUrl, user.username, path);
      // 插入新记录
      await db.strmUrlCacheDao.insertRecord(StrmUrlCache(
        serverUrl: user.serverUrl,
        userId: user.username,
        path: path,
        url: url,
        createTime: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (_) {}
  }

  /// 手动清除缓存（列表刷新时调用）
  static void clearCache() {
    _cache.clear();
    // 异步清除数据库缓存
    _clearDbCache();
  }

  static Future<void> _clearDbCache() async {
    try {
      final db = Get.find<AlistDatabaseController>();
      await db.strmUrlCacheDao.deleteAll();
    } catch (_) {}
  }

  /// 仅从缓存读取 URL（内存 → 数据库），不发网络请求
  /// 用于播放器加载 siblings 时快速读取已缓存的结果
  static Future<String?> getCachedUrl(String path) async {
    final mem = _getCached(path);
    if (mem != null) return mem;
    return _getCachedFromDb(path);
  }

  /// 读取 .strm 文件并解析出其中的视频流 URL
  ///
  /// [path] - .strm 文件在 alist 上的远程路径
  /// [sign] - 文件的签名（部分 alist 驱动需要）
  /// [cancelToken] - 可选的取消令牌，页面 dispose 时可一键取消
  ///
  /// 返回清洗后的视频流 URL，若读取或解析失败则返回 null
  static Future<String?> parseStrmUrl(
    String path,
    String? sign, {
    CancelToken? cancelToken,
  }) async {
    // 内存缓存
    final cached = _getCached(path);
    if (cached != null) return cached;

    // 数据库缓存（持久层）
    final dbCached = await _getCachedFromDb(path);
    if (dbCached != null) return dbCached;

    try {
      final strmFileUrl = await FileUtils.makeFileLink(path, sign);
      if (strmFileUrl == null || strmFileUrl.isEmpty) {
        debugPrint('[StrmParser] 无法生成 .strm 文件直链: $path');
        return null;
      }

      final content = await _fetchTextContent(strmFileUrl, cancelToken: cancelToken);
      if (content == null || content.isEmpty) {
        debugPrint('[StrmParser] .strm 文件内容为空: $path');
        return null;
      }

      final url = _sanitizeUrl(content);
      if (url != null) _putCache(path, url);
      return url;
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        debugPrint('[StrmParser] 解析 .strm 文件异常: $path, error=$e');
      }
      return null;
    } catch (e) {
      debugPrint('[StrmParser] 解析 .strm 文件异常: $path, error=$e');
      return null;
    }
  }

  /// 批量解析多个 .strm 文件，返回成功解析的结果列表
  ///
  /// [strmEntries] - Map 列表，每个元素包含 'path' 和 'sign' 键
  /// [cancelToken] - 可选的取消令牌，页面 dispose 时可一键取消所有请求
  /// 每个成功解析的条目返回 {path, url}
  static Future<List<Map<String, String>>> batchParseStrmUrls(
    List<Map<String, String?>> strmEntries, {
    CancelToken? cancelToken,
  }) async {
    // Phase 1: 分离缓存命中与需要网络请求的条目
    final cached = <Map<String, String>>[];
    final uncached = <Map<String, String?>>[];
    for (final entry in strmEntries) {
      final path = entry['path'] ?? '';
      final url = _getCached(path);
      if (url != null) {
        cached.add({'path': path, 'url': url});
      } else {
        uncached.add(entry);
      }
    }

    if (uncached.isEmpty) return cached;
    if (cancelToken?.isCancelled ?? false) return cached;

    // Phase 2: 并发获取 .strm 文件内容（受并发池限制 + CancelToken）
    final fetchResults = await Future.wait(
      uncached.map((entry) => _withPool(() async {
        if (cancelToken?.isCancelled ?? false) {
          return (path: entry['path'] ?? '', content: null as String?);
        }
        final path = entry['path'] ?? '';
        final sign = entry['sign'];
        try {
          final strmFileUrl = await FileUtils.makeFileLink(path, sign);
          if (strmFileUrl == null || strmFileUrl.isEmpty) {
            return (path: path, content: null as String?);
          }
          final content = await _fetchTextContent(strmFileUrl, cancelToken: cancelToken);
          return (path: path, content: content);
        } catch (e) {
          return (path: path, content: null as String?);
        }
      })),
      eagerError: false,
    );

    // Phase 3: 在 Isolate 中批量清洗 URL（避免阻塞 UI 线程）
    final validFetches = fetchResults.where((r) => r.content != null).toList();
    if (validFetches.isEmpty) return cached;

    final contents = validFetches.map((r) => r.content!).toList();
    List<String?> sanitizedUrls;
    try {
      sanitizedUrls = validFetches.length > 5
          ? await Isolate.run(() => contents.map(_sanitizeUrlPure).toList())
          : contents.map(_sanitizeUrlPure).toList();
    } catch (e) {
      debugPrint('[StrmParser] Isolate 执行失败，回退到主线程: $e');
      sanitizedUrls = contents.map(_sanitizeUrlPure).toList();
    }

    // Phase 4: 在主线程应用主机替换并写入缓存
    final results = List<Map<String, String>>.from(cached);
    for (var i = 0; i < validFetches.length; i++) {
      final pureUrl = sanitizedUrls[i];
      if (pureUrl != null) {
        final url = _applyHostOverride(pureUrl);
        if (url != null) {
          _putCache(validFetches[i].path, url);
          results.add({'path': validFetches[i].path, 'url': url});
        }
      }
    }

    return results;
  }

  /// 判断是否为可重试的网络错误
  static bool _isRetryable(DioException e) {
    if (e.type == DioExceptionType.cancel) return false;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }
    final statusCode = e.response?.statusCode;
    if (statusCode != null && statusCode >= 500) return true;
    return false;
  }

  /// 指数退避延迟，支持 CancelToken 中断
  static Future<void> _retryDelay(int attempt, CancelToken? cancelToken) async {
    final delay = Duration(
      milliseconds: _retryBaseDelay.inMilliseconds * (1 << attempt) +
          _random.nextInt(200),
    );
    debugPrint('[StrmParser] 第${attempt + 1}次重试，等待 ${delay.inMilliseconds}ms');
    if (cancelToken != null) {
      await Future.any([Future.delayed(delay), cancelToken.whenCancel]);
    } else {
      await Future.delayed(delay);
    }
  }

  /// 通过 HTTP GET 获取远程文件的文本内容（带指数退避重试）
  static Future<String?> _fetchTextContent(
    String url, {
    CancelToken? cancelToken,
  }) async {
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      if (cancelToken?.isCancelled ?? false) return null;

      try {
        final dio = DioUtils.instance.dio;

        final response = await dio.get(
          url,
          options: Options(
            connectTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 5),
            responseType: ResponseType.plain,
          ),
          cancelToken: cancelToken,
        );

        if (response.statusCode == 200 && response.data != null) {
          final content = response.data.toString();
          if (content.length > _maxContentSize) {
            debugPrint('[StrmParser] .strm 文件内容过大: ${content.length} bytes');
            return null;
          }
          return content;
        }

        // 5xx 可重试，4xx 不重试
        final statusCode = response.statusCode ?? 0;
        if (statusCode >= 500 && attempt < _maxRetries) {
          await _retryDelay(attempt, cancelToken);
          continue;
        }
        debugPrint('[StrmParser] HTTP请求失败: statusCode=$statusCode');
        return null;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) return null;
        if (_isRetryable(e) && attempt < _maxRetries) {
          await _retryDelay(attempt, cancelToken);
          continue;
        }
        debugPrint('[StrmParser] HTTP请求异常: $e');
        return null;
      } catch (e) {
        debugPrint('[StrmParser] HTTP请求异常: $e');
        return null;
      }
    }
    return null;
  }

  /// 纯文本清洗（Isolate 安全，无 SpUtil 依赖）
  static String? _sanitizeUrlPure(String rawContent) {
    String? candidate;
    for (final line in rawContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        candidate = trimmed;
        break;
      }
    }
    if (candidate == null || candidate.isEmpty) return null;

    candidate = candidate.replaceAll(_invisibleCharsRegex, '').trim();
    if (candidate.isEmpty) return null;

    try {
      final uri = Uri.parse(candidate);
      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return null;
      }
      if (!uri.hasAuthority || uri.host.isEmpty) {
        return null;
      }
    } catch (e) {
      return null;
    }

    return candidate;
  }

  /// 完整清洗（主线程，含主机替换）
  static String? _sanitizeUrl(String rawContent) {
    final pure = _sanitizeUrlPure(rawContent);
    if (pure == null) return null;
    return _applyHostOverride(pure);
  }

  /// 根据设置中的开关与地址映射，替换 .strm URL 中的原始主机为代理后的主机
  ///
  /// 场景：内网服务器 (192.168.x.x:8024) 通过 frp 穿透暴露到公网
  /// (frp.example.com:12345)，应用此替换后可在外网直接播放。
  static String? _applyHostOverride(String url) {
    try {
      final enabled = SpUtil.getBool(AlistConstant.strmHostOverrideEnabled, defValue: false) ?? false;
      if (!enabled) return url;

      final from = SpUtil.getString(AlistConstant.strmHostOverrideFrom);
      final to = SpUtil.getString(AlistConstant.strmHostOverrideTo);

      if (from == null || from.isEmpty || to == null || to.isEmpty) return url;

      final uri = Uri.parse(url);
      final originalAuthority = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

      if (originalAuthority == from.trim()) {
        final toUri = Uri.parse('http://${to.trim()}');
        final newUri = uri.replace(
          host: toUri.host,
          port: toUri.hasPort ? toUri.port : null,
        );
        debugPrint('[StrmParser] 主机替换: $originalAuthority → ${to.trim()}');
        return newUri.toString();
      }
    } catch (e) {
      debugPrint('[StrmParser] 主机替换异常: $e');
    }
    return url;
  }

  /// 判断给定路径是否指向 .strm 文件
  static bool isStrmFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ext == 'strm';
  }
}

class _CacheEntry {
  final String url;
  final DateTime timestamp;
  _CacheEntry(this.url) : timestamp = DateTime.now();
}
