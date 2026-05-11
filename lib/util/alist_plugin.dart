import 'dart:convert';

import 'package:alist/entity/player_resolve_info_entity.dart';
import 'package:alist/generated/json/base/json_convert_content.dart';
import 'package:alist/util/method_call_handler.dart';
import 'package:flutter/services.dart';

class AlistPlugin {
  static const _methodChannel = MethodChannel("com.github.alist.client.plugin");

  static void setupChannel() {
    _methodChannel.setMethodCallHandler((MethodCall call) async {
      return MethodCallHandler.hand(call);
    });
  }

  // just for android
  static Future<bool> isAppInstall(String packageName) async {
    Map<String, String?> params = {"packageName": packageName};
    bool isInstalled =
        await _methodChannel.invokeMethod("isAppInstalled", params);
    return isInstalled;
  }

  // just for android
  static Future<bool> launchApp(String packageName, {String? uri}) async {
    Map<String, String?> params = {"packageName": packageName, "uri": uri};
    bool isSucceed = await _methodChannel.invokeMethod("launchApp", params);
    return isSucceed;
  }

  // just for android
  static Future<bool> isScopedStorage() async {
    bool isSucceed = await _methodChannel.invokeMethod("isScopedStorage");
    return isSucceed;
  }

  // just for android
  static Future onDownloadingStart() async {
    await _methodChannel.invokeMethod("onDownloadingStart");
  }

  // just for android
  static Future onDownloadingEnd() async {
    await _methodChannel.invokeMethod("onDownloadingEnd");
  }

  // just for android Q above
  static Future saveFileToLocal(String fileName, String filePath) async {
    await _methodChannel.invokeMethod(
        "saveFileToLocal", {"fileName": fileName, "filePath": filePath});
  }

  // just for android
  static Future<String> getExternalDownloadDir() async {
    dynamic result =
        await _methodChannel.invokeMethod("getExternalDownloadDir");
    if (result is String) {
      return result;
    }
    return "";
  }

  // just for android
  static Future<List<ExternalPlayerEntity>?> loadPlayerResoleInfoList() async {
    var result = await _methodChannel.invokeMethod("loadExternalPlayerList");
    return JsonConvert.fromJsonAsT<List<ExternalPlayerEntity>>(
        jsonDecode(result));
  }

  static Future<bool> playVideoWithExternalPlayer(
      String packageName, String activity, String url) async {
    var result = await _methodChannel.invokeMethod(
        "playVideoWithExternalPlayer",
        {"packageName": packageName, "activity": activity, "url": url});
    return result == true;
  }

  static Future<bool> playVideoWithInternalPlayer(
      List<Map<String, String?>> videos,
      int index,
      Map<String, String>? headers,
      String? playerType,
      {bool autoPipEnabled = true}) async {
    String? headersStr = headers != null ? jsonEncode(headers) : null;

    var result =
        await _methodChannel.invokeMethod("playVideoWithInternalPlayer", {
      "videos": jsonEncode(videos),
      "index": index,
      "headers": headersStr,
      "playerType": playerType,
      "autoPipEnabled": autoPipEnabled,
    });
    return result == true;
  }

  // Open document with AndroidDocViewer (Android only)
  static Future<bool> openDocument(String filePath, String title) async {
    try {
      var result = await _methodChannel.invokeMethod("openDocument", {
        "filePath": filePath,
        "title": title,
      });
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// 生成视频缩略图（Android only）
  /// [url] 视频直链
  /// [cacheKey] 缓存文件名（不含扩展名），建议用文件 sign 或 path MD5
  /// [cacheDir] 缓存目录路径
  /// [positionMs] 取帧时间点（毫秒），默认 10000
  /// [headers] 请求头（如百度网盘需要 User-Agent）
  /// 返回生成的缩略图本地路径，失败返回 null
  static Future<String?> generateVideoThumbnail({
    required String url,
    required String cacheKey,
    required String cacheDir,
    int positionMs = 10000,
    Map<String, String>? headers,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        'generateVideoThumbnail',
        {
          'url': url,
          'cacheKey': cacheKey,
          'cacheDir': cacheDir,
          'positionMs': positionMs,
          'headers': headers ?? {},
        },
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 打开原生 HEIC 图片浏览器（Android only）
  static Future<void> openHeicViewer({
    required List<String> names,
    required List<String> urls,
    required List<String> localPaths,
    required int index,
    List<String>? remotePaths,
    List<String>? signs,
    List<String>? sizes,
  }) async {
    await _methodChannel.invokeMethod('openHeicViewer', {
      'names': names,
      'urls': urls,
      'localPaths': localPaths,
      'index': index,
      'remotePaths': remotePaths ?? urls,
      'signs': signs ?? List.filled(urls.length, ''),
      'sizes': sizes ?? List.filled(urls.length, ''),
    });
  }

  /// 进入画中画模式（Android only）
  static Future<void> enterPictureInPicture() async {
    await _methodChannel.invokeMethod('enterPictureInPicture');
  }

  /// 使用 MPV 播放器播放视频（支持 PiP）
  static Future<bool> playVideoWithMpvPlayer({
    required List<Map<String, String?>> videos,
    required int index,
    Map<String, String>? headers,
  }) async {
    String? headersStr = headers != null ? jsonEncode(headers) : null;
    
    final videosJson = jsonEncode(videos.map((v) {
      return {
        "name": v["name"] ?? "",
        "url": v["url"] ?? "",
        "localPath": v["localPath"],
        "remotePath": v["remotePath"],
        "sign": v["sign"],
        "provider": v["provider"],
        "thumb": v["thumb"],
        "size": v["size"],
        "modifiedMilliseconds": v["modifiedMilliseconds"],
      };
    }).toList());
    
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'playVideoWithMpvPlayer',
        {
          'videos': videosJson,
          'index': index,
          'headers': headersStr,
        },
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
