import 'dart:io';

import 'package:alist/util/constant.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/subtitle/subtitle_controller.dart';
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

      final candidates = [
        '$dir${Platform.pathSeparator}$nameWithoutExt.srt',
        '$dir${Platform.pathSeparator}$nameWithoutExt.SRT',
      ];

      for (final candidate in candidates) {
        final file = File(candidate);
        if (await file.exists()) {
          debugPrint('SubtitleLoader: 找到本地字幕 -> $candidate');
          SubtitleController.addLog('找到本地字幕: $candidate');
          return await file.readAsString();
        }
      }
      SubtitleController.addLog('本地未找到同名 .srt');
    } catch (e) {
      debugPrint('SubtitleLoader: 本地字幕查找异常 -> $e');
      SubtitleController.addLog('本地查找异常: $e');
    }
    return null;
  }

  static Future<String?> _tryLoadRemoteWithCache(String remotePath, {String? sign}) async {
    try {
      final lastDot = remotePath.lastIndexOf('.');
      if (lastDot <= 0) {
        SubtitleController.addLog('远程路径无扩展名: $remotePath');
        return null;
      }

      final srtRemotePath = '${remotePath.substring(0, lastDot)}.srt';
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
        debugPrint('SubtitleLoader: 远程无同名字幕 (404)');
        SubtitleController.addLog('远程无同名字幕 (404)');
      } else {
        debugPrint('SubtitleLoader: 异常 -> ${e.message}');
        SubtitleController.addLog('下载异常: ${e.message} (${e.response?.statusCode})');
      }
      return null;
    } catch (e) {
      debugPrint('SubtitleLoader: 异常 -> $e');
      SubtitleController.addLog('下载异常: $e');
      return null;
    }
  }

  static String _getNameWithoutExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot <= 0) return fileName;
    return fileName.substring(0, lastDot);
  }
}