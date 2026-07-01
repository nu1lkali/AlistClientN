import 'dart:io';

import 'package:alist/util/constant.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/subtitle/subtitle_controller.dart';
import 'package:alist/util/subtitle/subtitle_matcher.dart';
import 'package:alist/util/subtitle/subtitle_matcher_util.dart';
import 'package:dio/dio.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SubtitleLoader {
  SubtitleLoader._();
  static String? _cacheDirPath;

  static Future<void> _initCacheDir() async {
    if (_cacheDirPath != null) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final subtitleDir = Directory('${appDir.path}/subtitles');
      if (!await subtitleDir.exists()) {
        await subtitleDir.create(recursive: true);
      }
      _cacheDirPath = subtitleDir.path;
      debugPrint('SubtitleLoader: 缓存目录 -> $_cacheDirPath');
      SubtitleController.addLog('缓存目录: $_cacheDirPath');
    } catch (e) {
      debugPrint('SubtitleLoader: 初始化缓存目录失败 -> $e');
      SubtitleController.addLog('缓存目录初始化失败: $e');
    }
  }

  static Future<String?> loadSubtitleContent({
    String? videoPath,
    String? remotePath,
    String? sign,
  }) async {
    if (videoPath != null && videoPath.isNotEmpty) {
      final localContent = await _tryLoadLocal(videoPath);
      if (localContent != null) return localContent;
    }
    // 用户配置的本地字幕库目录：按视频名匹配同名 .srt
    final videoName = (remotePath != null && remotePath.isNotEmpty)
        ? remotePath.split('/').last
        : (videoPath != null && videoPath.isNotEmpty
            ? videoPath.split(RegExp(r'[/\\]')).last
            : '');
    final libPath = await SubtitleMatcherUtil.findLocalSubtitle(videoName);
    if (libPath != null) {
      try {
        final content = await File(libPath).readAsString();
        SubtitleController.addLog('使用本地字幕库: $libPath');
        return content;
      } catch (e) {
        debugPrint('SubtitleLoader: 读取本地字幕库失败 -> $e');
        SubtitleController.addLog('读取本地字幕库失败: $e');
      }
    }
    if (remotePath != null && remotePath.isNotEmpty) {
      final remoteContent = await _tryLoadRemoteWithCache(remotePath, sign: sign);
      if (remoteContent != null) return remoteContent;
    }
    debugPrint('SubtitleLoader: 本地和远程均未找到字幕文件');
    SubtitleController.addLog('本地和远程均未找到字幕文件');
    return null;
  }

  static Future<String?> _tryLoadLocal(String videoPath) async {
    if (videoPath.isEmpty) return null;
    try {
      final videoFile = File(videoPath);
      final dir = videoFile.parent.path;
      final nameWithoutExt = _getNameWithoutExtension(videoFile.uri.pathSegments.last);
      if (nameWithoutExt.isEmpty) return null;

      // 1. 精确同名：neob-017.srt
      final exactCandidates = [
        '$dir${Platform.pathSeparator}$nameWithoutExt.srt',
        '$dir${Platform.pathSeparator}$nameWithoutExt.SRT',
      ];
      for (final candidate in exactCandidates) {
        final file = File(candidate);
        if (await file.exists()) {
          debugPrint('SubtitleLoader: 找到本地字幕(精确) -> $candidate');
          SubtitleController.addLog('找到本地字幕(精确): $candidate');
          return await file.readAsString();
        }
      }

      // 2. 语言标签变体：扫描目录，匹配 neob-017.*.srt / neob-017.*.SRT 等
      //    例如 neob-017.ja.srt, neob-017.chs.srt, neob-017.zh-CN.srt
      final videoDir = Directory(dir);
      if (await videoDir.exists()) {
        final prefix = nameWithoutExt.toLowerCase();
        const srtExts = ['.srt', '.ass', '.vtt', '.ssa', '.sub'];
        final matchedFiles = <File>[];
        await for (final entity in videoDir.list()) {
          if (entity is File) {
            final fileName = _baseName(entity.path).toLowerCase();
            final ext = _getExtension(entity.path).toLowerCase();
            // 文件名以 "视频名." 开头（如 neob-017.ja.srt → neob-017. 开头）
            // 且扩展名是字幕格式
            if (fileName.startsWith('$prefix.') && srtExts.contains(ext)) {
              matchedFiles.add(entity);
            }
          }
        }
        if (matchedFiles.isNotEmpty) {
          // 优先选择 .srt，其次按文件名长度升序（越短越接近原始名）
          matchedFiles.sort((a, b) {
            final extA = _getExtension(a.path).toLowerCase();
            final extB = _getExtension(b.path).toLowerCase();
            if (extA == '.srt' && extB != '.srt') return -1;
            if (extA != '.srt' && extB == '.srt') return 1;
            return _baseName(a.path).length.compareTo(_baseName(b.path).length);
          });
          final best = matchedFiles.first;
          debugPrint('SubtitleLoader: 找到本地字幕(语言标签) -> ${best.path}');
          SubtitleController.addLog('找到本地字幕(语言标签): ${best.path}');
          return await best.readAsString();
        }
      }

      SubtitleController.addLog('本地未找到同名 .srt');
    } catch (e) {
      debugPrint('SubtitleLoader: 本地字幕查找异常 -> $e');
      SubtitleController.addLog('本地查找异常: $e');
    }
    return null;
  }

  /// 取路径最后一段文件名
  static String _baseName(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  /// 获取文件扩展名（含点号，如 .srt）
  static String _getExtension(String path) {
    final base = _baseName(path);
    final idx = base.lastIndexOf('.');
    return idx >= 0 ? base.substring(idx) : '';
  }

  static Future<String?> _tryLoadRemoteWithCache(String remotePath, {String? sign}) async {
    try {
      final lastDot = remotePath.lastIndexOf('.');
      if (lastDot <= 0) {
        SubtitleController.addLog('远程路径无扩展名: $remotePath');
        return null;
      }

      final baseWithoutExt = remotePath.substring(0, lastDot);

      // 构建候选远程路径列表：先精确同名，再语言标签变体
      // neob-017.mp4 → neob-017.srt, neob-017.ja.srt, neob-017.chs.srt, ...
      final candidates = <String>[
        '$baseWithoutExt.srt',
      ];
      // 常见语言标签变体（优先级从高到低）
      const langTags = [
        '.chs.srt', '.cht.srt',   // 中文简繁
        '.zh.srt', '.zh-CN.srt', '.zh-TW.srt', // 中文标准标签
        '.ja.srt', '.jpn.srt',   // 日文
        '.en.srt', '.eng.srt',   // 英文
        '.ko.srt', '.kor.srt',   // 韩文
      ];
      for (final tag in langTags) {
        candidates.add('$baseWithoutExt$tag');
      }

      for (final srtRemotePath in candidates) {
        final result = await _tryDownloadRemoteSrt(srtRemotePath, sign: sign);
        if (result != null) return result;
      }

      return null;
    } catch (e) {
      debugPrint('SubtitleLoader: 异常 -> $e');
      SubtitleController.addLog('下载异常: $e');
      return null;
    }
  }

  /// 尝试下载单个远程字幕文件（带缓存）
  static Future<String?> _tryDownloadRemoteSrt(String srtRemotePath, {String? sign}) async {
    try {
      debugPrint('SubtitleLoader: 尝试远程字幕 -> $srtRemotePath');
      SubtitleController.addLog('尝试远程字幕: $srtRemotePath');

      await _initCacheDir();

      final cacheFileName = 'srt_${srtRemotePath.hashCode.toRadixString(16)}.srt';
      final cacheFilePath = '${_cacheDirPath ?? ''}${Platform.pathSeparator}$cacheFileName';
      final cacheFile = File(cacheFilePath);

      if (await cacheFile.exists()) {
        debugPrint('SubtitleLoader: 使用缓存字幕 -> $cacheFilePath');
        SubtitleController.addLog('使用缓存字幕');
        return await cacheFile.readAsString();
      }

      final srtUrl = await FileUtils.makeFileLink(srtRemotePath, sign, toastShowTips: false);
      if (srtUrl == null || srtUrl.isEmpty) {
        debugPrint('SubtitleLoader: 无法构造字幕 URL');
        SubtitleController.addLog('无法构造字幕 URL');
        return null;
      }

      debugPrint('SubtitleLoader: 字幕下载 URL -> $srtUrl');
      SubtitleController.addLog('下载URL: $srtUrl');

      final accessToken = SpUtil.getString(AlistConstant.token) ?? "";
      final serverUrl = SpUtil.getString(AlistConstant.serverUrl) ?? "";
      final headers = <String, String>{};

      if (accessToken.isNotEmpty && serverUrl.isNotEmpty && srtUrl.startsWith(serverUrl)) {
        headers['Authorization'] = accessToken;
        debugPrint('SubtitleLoader: 已添加 Authorization');
        SubtitleController.addLog('已添加 Authorization');
      } else {
        debugPrint('SubtitleLoader: 认证信息不匹配, token非空=${accessToken.isNotEmpty}, serverUrl=$serverUrl');
        SubtitleController.addLog('认证不匹配 token=${accessToken.isNotEmpty} server=$serverUrl');
      }

      final ignoreSSL = SpUtil.getBool(AlistConstant.ignoreSSLError) ?? false;
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 15);

      if (ignoreSSL) {
        (dio.httpClientAdapter as dynamic).onHttpClientCreate = (HttpClient client) {
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }

      SubtitleController.addLog('发起HTTP请求...');
      final response = await dio.get<List<int>>(
        srtUrl,
        options: Options(headers: headers, responseType: ResponseType.bytes, followRedirects: true),
      );

      debugPrint('SubtitleLoader: HTTP ${response.statusCode}');
      SubtitleController.addLog('HTTP响应: ${response.statusCode}');

      if (response.statusCode == 200 && response.data != null) {
        final content = String.fromCharCodes(response.data!);
        debugPrint('SubtitleLoader: 下载成功 ${content.length} 字符');
        SubtitleController.addLog('下载成功! ${content.length} 字符');

        try {
          await cacheFile.writeAsString(content);
          debugPrint('SubtitleLoader: 已缓存');
          SubtitleController.addLog('已缓存到本地');
        } catch (e) {
          SubtitleController.addLog('缓存失败: $e');
        }
        return content;
      }

      SubtitleController.addLog('下载失败: HTTP ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // 404 是正常的（该语言标签变体不存在），不打印错误，静默跳过
        return null;
      }
      debugPrint('SubtitleLoader: 异常 -> ${e.message}');
      SubtitleController.addLog('下载异常: ${e.message} (${e.response?.statusCode})');
      return null;
    } catch (e) {
      debugPrint('SubtitleLoader: 异常 -> $e');
      SubtitleController.addLog('下载异常: $e');
      return null;
    }
  }

  /// 安全剥离文件多重后缀和语言标记（与 SubtitleMatcher._nameWithoutExt 对齐）
  ///
  /// 例如:
  /// - neob-017.mp4 → neob-017
  /// - neob-017.1080p.mp4 → neob-017 (剥离分辨率标签)
  /// - neob-017.ja.srt → neob-017
  static String _getNameWithoutExtension(String fileName) {
    // 使用 SubtitleMatcher 的公开方法进行深度清洗
    final cleaned = SubtitleMatcher.cleanName(fileName);
    if (cleaned.isNotEmpty) return cleaned;
    // 兜底：如果深度清洗后为空，回退到简单剥离
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot <= 0) return fileName;
    return fileName.substring(0, lastDot);
  }
}