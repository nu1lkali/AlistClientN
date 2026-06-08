import 'dart:convert';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/screen/disliked_videos_screen.dart';
import 'package:alist/database/table/disliked_video.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/database/table/file_viewing_record.dart';
import 'package:alist/database/table/video_viewing_record.dart';
import 'package:alist/entity/file_remove_req.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/util/proxy.dart';
import 'package:alist/util/string_utils.dart';
import 'package:alist/util/user_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class MethodCallHandler {
  static Future<String> hand(MethodCall call) async {
    switch (call.method) {
      case 'findVideoRecordByPath':
        String path = call.arguments["path"];
        final AlistDatabaseController database = Get.find();
        final UserController userController = Get.find();
        final userId = userController.user().username;
        final baseUrl = userController.user().baseUrl;
        var record = await database.videoViewingRecordDao
            .findRecordByPath(baseUrl, userId, path);
        var result = <String, int?>{};
        result["videoCurrentPosition"] = record?.videoCurrentPosition;
        result["videoDuration"] = record?.videoDuration;
        return jsonEncode(result);
      case 'deleteVideoRecord':
        String path = call.arguments["path"];
        final AlistDatabaseController database = Get.find();
        final UserController userController = Get.find();
        final userId = userController.user().username;
        final baseUrl = userController.user().baseUrl;
        var record = await database.videoViewingRecordDao
            .findRecordByPath(baseUrl, userId, path);
        if (record != null) {
          database.videoViewingRecordDao.deleteRecord(record);
        }
        return "";
      case 'insertOrUpdateVideoRecord':
        String path = call.arguments["path"];
        int videoCurrentPosition = call.arguments["videoCurrentPosition"];
        int videoDuration = call.arguments["videoDuration"];
        String sign = call.arguments["sign"];
        final AlistDatabaseController database = Get.find();
        final UserController userController = Get.find();
        final userId = userController.user().username;
        final baseUrl = userController.user().baseUrl;
        var record = await database.videoViewingRecordDao
            .findRecordByPath(baseUrl, userId, path);

        if (record != null) {
          var recordNew = VideoViewingRecord(
            id: record.id,
            serverUrl: record.serverUrl,
            userId: record.userId,
            videoSign: record.videoSign,
            path: record.path,
            videoCurrentPosition: videoCurrentPosition,
            videoDuration: videoDuration,
          );
          database.videoViewingRecordDao.updateRecord(recordNew);
        } else {
          var recordNew = VideoViewingRecord(
            serverUrl: baseUrl,
            userId: userId,
            videoSign: sign,
            path: path,
            videoCurrentPosition: videoCurrentPosition,
            videoDuration: videoDuration,
          );
          database.videoViewingRecordDao.insertRecord(recordNew);
        }
        return "";
      case "onPayerDestroyed":
        final String pendingDelete = call.arguments as String? ?? "";
        ProxyServer proxyServer = Get.find();
        proxyServer.stop();
        if (pendingDelete.isNotEmpty) {
          // wait for server-side connection to fully close before deleting
          await Future.delayed(const Duration(seconds: 2));
          final String fileName = pendingDelete.substringAfterLast("/") ?? "";
          final String dir = pendingDelete.substringBeforeLast("/$fileName") ?? "/";
          FileRemoveReq req = FileRemoveReq();
          req.dir = dir.isEmpty ? "/" : dir;
          req.names = [fileName];

          bool deleted = false;
          // retry up to 3 times with increasing delay
          for (int attempt = 0; attempt < 3 && !deleted; attempt++) {
            if (attempt > 0) await Future.delayed(Duration(seconds: attempt * 2));
            await DioUtils.instance.requestNetwork<String?>(
              Method.post, "fs/remove",
              params: req.toJson(),
              onSuccess: (_) async {
                deleted = true;
                final AlistDatabaseController db = Get.find();
                final UserController uc = Get.find();
                final user = uc.user.value;
                final record = await db.videoViewingRecordDao
                    .findRecordByPath(user.baseUrl, user.username, pendingDelete);
                if (record != null) db.videoViewingRecordDao.deleteRecord(record);
                SmartDialog.showToast("删除成功");
                uc.notifyFileDeleted();
              },
              onError: (_, msg) {
                if (attempt == 2) SmartDialog.showToast("删除失败：$msg");
              },
            );
          }
        }
        return "";

      case "deleteRemoteFile":
        // called from PlayerActivity when user confirms delete
        final String filePath = call.arguments["path"];
        final String fileName = filePath.substringAfterLast("/") ?? "";
        final String dir = filePath.substringBeforeLast("/$fileName") ?? "/";
        FileRemoveReq req = FileRemoveReq();
        req.dir = dir.isEmpty ? "/" : dir;
        req.names = [fileName];
        String deleteResult = "error";
        await DioUtils.instance.requestNetwork<String?>(
          Method.post, "fs/remove",
          params: req.toJson(),
          onSuccess: (_) { deleteResult = "ok"; },
          onError: (_, msg) { deleteResult = msg; },
        );
        return deleteResult;

      case "addFileViewingRecord":
        String path = call.arguments["path"];
        String name = call.arguments["name"];
        String? sign = call.arguments["sign"];
        String size = call.arguments["size"];
        String? thumb = call.arguments["thumb"];
        String modifiedMilliseconds = call.arguments["modifiedMilliseconds"];
        String? provider = call.arguments["provider"];

        final AlistDatabaseController databaseController = Get.find();
        final UserController userController = Get.find();
        var user = userController.user.value;
        var recordData = databaseController.fileViewingRecordDao;
        await recordData.deleteByPath(user.serverUrl, user.username, path);
        await recordData.insertRecord(FileViewingRecord(
          serverUrl: user.serverUrl,
          userId: user.username,
          remotePath: path,
          name: name,
          path: path,
          size: int.tryParse(size) ?? 0,
          sign: sign,
          thumb: thumb,
          modified: int.tryParse(modifiedMilliseconds) ?? 0,
          provider: provider ?? "",
          createTime: DateTime.now().millisecondsSinceEpoch,
        ));
        return "";

      case "toggleDislike":
        String path = call.arguments["path"];
        String name = call.arguments["name"];
        String size = call.arguments["size"];
        String? sign = call.arguments["sign"];
        String? thumb = call.arguments["thumb"];
        String modifiedMilliseconds = call.arguments["modifiedMilliseconds"];
        String? provider = call.arguments["provider"];

        final AlistDatabaseController databaseController = Get.find();
        final UserController userController = Get.find();
        var user = userController.user.value;
        var dao = databaseController.dislikedVideoDao;
        
        var existing = await dao.findByPath(user.serverUrl, user.username, path);
        
        if (existing != null) {
          await dao.deleteByPath(user.serverUrl, user.username, path);
          await DislikeLog.append('取消标记(原生)', name, path, user.username, user.serverUrl);
          return "false";
        } else {
          await dao.insertRecord(DislikedVideo(
            serverUrl: user.serverUrl,
            userId: user.username,
            remotePath: path,
            name: name,
            path: path,
            size: int.tryParse(size) ?? 0,
            sign: sign,
            thumb: thumb,
            modified: int.tryParse(modifiedMilliseconds) ?? 0,
            provider: provider ?? "",
            createTime: DateTime.now().millisecondsSinceEpoch,
          ));
          await DislikeLog.append('标记不喜欢(原生)', name, path, user.username, user.serverUrl);
          return "true";
        }

      case "toggleFavorite":
        String path = call.arguments["path"];
        String name = call.arguments["name"];
        String size = call.arguments["size"];
        String? provider = call.arguments["provider"];

        final AlistDatabaseController databaseController = Get.find();
        final UserController userController = Get.find();
        var user = userController.user.value;
        var favoriteDao = databaseController.favoriteDao;
        
        // Check if already favorited
        var existing = await favoriteDao.findByPath(
          user.serverUrl, 
          user.username, 
          path
        );
        
        if (existing != null) {
          // Remove from favorites
          await favoriteDao.deleteByPath(user.serverUrl, user.username, path);
          return "false"; // Return false to indicate unfavorited
        } else {
          // Add to favorites
          await favoriteDao.insertRecord(Favorite(
            isDir: false,
            serverUrl: user.serverUrl,
            userId: user.username,
            remotePath: path,
            path: path,
            name: name,
            size: int.tryParse(size) ?? 0,
            sign: null,
            thumb: null,
            modified: 0,
            provider: provider ?? "",
            createTime: DateTime.now().millisecondsSinceEpoch,
          ));
          return "true"; // Return true to indicate favorited
        }

      case "checkFavoriteStatus":
        String path = call.arguments["path"];
        
        final AlistDatabaseController databaseController = Get.find();
        final UserController userController = Get.find();
        var user = userController.user.value;
        var favoriteDao = databaseController.favoriteDao;
        
        var existing = await favoriteDao.findByPath(
          user.serverUrl, 
          user.username, 
          path
        );
        
        return existing != null ? "true" : "false";

      case "checkDislikeStatus":
        String path = call.arguments["path"];
        
        final AlistDatabaseController databaseController = Get.find();
        final UserController userController = Get.find();
        var user = userController.user.value;
        var dislikedDao = databaseController.dislikedVideoDao;
        
        var existing = await dislikedDao.findByPath(
          user.serverUrl, 
          user.username, 
          path
        );
        
        return existing != null ? "true" : "false";

      case "fallbackToMediaKit":
        // ExoPlayer 播放失败时，原生层通知 Flutter 使用 MediaKit 重试
        String? videosJson = call.arguments["videos"];
        int index = call.arguments["index"] ?? 0;
        String? headersStr = call.arguments["headers"];
        
        if (videosJson != null && videosJson.isNotEmpty) {
          try {
            final videosList = jsonDecode(videosJson) as List;
            final videos = videosList.map((v) => Map<String, String?>.from(v as Map)).toList();
            final headers = headersStr != null && headersStr.isNotEmpty 
                ? Map<String, String>.from(jsonDecode(headersStr)) 
                : <String, String>{};
            
            // 使用 Future.delayed 确保当前 Activity 已关闭
            Future.delayed(const Duration(milliseconds: 300), () {
              Get.toNamed(
                '/mediaKitPlayer', // NamedRouter.mediaKitPlayer
                arguments: {
                  "videos": videos,
                  "index": index,
                  "headers": headers,
                },
              );
            });
          } catch (e) {
            // 解析失败静默处理
          }
        }
        return "";

      default:
        throw PlatformException(
            code: 'Method not implemented',
            message: 'Method ${call.method} not implemented.');
    }
  }
}