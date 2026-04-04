import 'dart:async';
import 'dart:io';

import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/util/download/download_manager.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class CacheManagerScreen extends StatelessWidget {
  const CacheManagerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var controller = Get.put(CacheManagerController());
    return AlistScaffold(
      appbarTitle: Text(Intl.screenName_cacheManagement.tr),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _CacheTile(
              title: Intl.cacheManagement_imageCache.tr,
              sizeStr: controller.imageCacheSizeStr,
              onClear: () => _confirm(context, "清除图片缓存？", controller.clearImageCache),
            ),
            const Divider(),
            _CacheTile(
              title: "视频缓存",
              sizeStr: controller.videoCacheSizeStr,
              onClear: () => _confirm(context, "清除视频缓存？", controller.clearVideoCache),
            ),
            const Divider(),
            _CacheTile(
              title: Intl.cacheManagement_audioCache.tr,
              sizeStr: controller.audioCacheSizeStr,
              onClear: () => _confirm(context, "清除音频缓存？", controller.clearAudioCache),
            ),
            const Divider(),
            _CacheTile(
              title: Intl.cacheManagement_otherCache.tr,
              sizeStr: controller.otherCacheSizeStr,
              onClear: () => _confirm(context, "清除其他缓存？", controller.clearOtherCache),
            ),
            const Divider(),
            Obx(() => ListTile(
              title: const Text("清除全部缓存"),
              subtitle: Text("共 ${controller.totalCacheSizeStr.value}"),
              trailing: const Icon(Icons.delete_sweep_outlined),
              onTap: () => _confirm(context, "清除全部缓存？", controller.clearAllCache),
            )),
          ],
        ),
      ),
    );
  }

  void _confirm(BuildContext context, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认"),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }
}

class _CacheTile extends StatelessWidget {
  const _CacheTile({
    required this.title,
    required this.sizeStr,
    required this.onClear,
  });
  final String title;
  final RxString sizeStr;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Obx(() => Text(sizeStr.value)),
      trailing: const Icon(Icons.delete_outline),
      onTap: onClear,
    );
  }
}

class CacheManagerController extends GetxController {
  var _imageCacheSize = 0;
  var _audioCacheSize = 0;
  var _videoCacheSize = 0;
  var _otherCacheSize = 0;
  var imageCacheSizeStr = "0 B".obs;
  var audioCacheSizeStr = "0 B".obs;
  var videoCacheSizeStr = "0 B".obs;
  var otherCacheSizeStr = "0 B".obs;
  var totalCacheSizeStr = "0 B".obs;

  final Set<String> _imageCachePaths = {};
  final Set<String> _audioCachePaths = {};
  final Set<String> _videoCachePaths = {};
  String _downloadDir = "";

  @override
  void onInit() {
    super.onInit();
    _calculateCacheFilesSize();
  }

  void _calculateCacheFilesSize() async {
    var temporaryDirectory = await getTemporaryDirectory();
    _downloadDir = (await DownloadManager.acquireDownloadDirectory()).path;
    final videoDir = await DownloadManager.findDownloadDir("video");
    if (isClosed) return;
    _imageCachePaths.add(path.join(temporaryDirectory.path, "cacheimage"));
    _imageCachePaths.add(path.join(temporaryDirectory.path, "libCachedImageData"));
    _audioCachePaths.add(path.join(temporaryDirectory.path, "just_audio_cache"));
    // flutter_aliplayer local cache lives in the video download dir
    _videoCachePaths.add(videoDir.path);

    await _calculateDirectoryFilesSize(temporaryDirectory);
    // video cache is outside temp dir, calculate separately
    if (await videoDir.exists()) {
      await _calculateDirectoryFilesSize(videoDir);
    }
    _updateTotal();
  }

  void _updateTotal() {
    final total = _imageCacheSize + _audioCacheSize + _videoCacheSize + _otherCacheSize;
    totalCacheSizeStr.value = _formatBytes(total);
  }

  Future<void> _calculateDirectoryFilesSize(Directory directory) async {
    if (isClosed) {
      return;
    }

    final completer = Completer<void>();

    late final StreamSubscription<FileSystemEntity> subscription;
    subscription = directory.list().listen((entity) async {
      subscription.pause();
      if (entity is File) {
        var path = entity.path;
        var filesSize = await entity.length();
        if (_checkIsImagePath(path)) {
          _imageCacheSize += filesSize;
          imageCacheSizeStr.value = _formatBytes(_imageCacheSize);
        } else if (_checkIsAudioPath(path)) {
          _audioCacheSize += filesSize;
          audioCacheSizeStr.value = _formatBytes(_audioCacheSize);
        } else if (_checkIsVideoPath(path)) {
          _videoCacheSize += filesSize;
          videoCacheSizeStr.value = _formatBytes(_videoCacheSize);
        } else if (path.startsWith(_downloadDir)) {
          // do nothing
        } else {
          _otherCacheSize += filesSize;
          debugPrint(entity.path);
          otherCacheSizeStr.value = _formatBytes(_otherCacheSize);
        }
      } else if (entity is Directory) {
        await _calculateDirectoryFilesSize(entity);
      }
      subscription.resume();
    }, onDone: () {
      completer.complete();
    });

    return completer.future;
  }

  bool _checkIsImagePath(String path) {
    for (var value in _imageCachePaths) {
      if (path.startsWith(value)) {
        return true;
      }
    }
    return false;
  }

  bool _checkIsAudioPath(String path) {
    for (var value in _audioCachePaths) {
      if (path.startsWith(value)) return true;
    }
    return false;
  }

  bool _checkIsVideoPath(String path) {
    for (var value in _videoCachePaths) {
      if (path.startsWith(value)) return true;
    }
    return false;
  }

  String _formatBytes(int bytes) {
    const int kilobyte = 1024;
    const int megabyte = kilobyte * 1024;
    const int gigabyte = megabyte * 1024;

    String format(double value) {
      if (value.truncate() == value) {
        // 是整数，不保留小数
        return value.toInt().toString();
      } else {
        // 保留一位小数
        return value.toStringAsFixed(1);
      }
    }

    if (bytes < kilobyte) {
      return '${format(bytes.toDouble())} B';
    } else if (bytes < megabyte) {
      return '${format(bytes / kilobyte)} KB';
    } else if (bytes < gigabyte) {
      return '${format(bytes / megabyte)} MB';
    } else {
      return '${format(bytes / gigabyte)} GB';
    }
  }

  Future<void> _deleteFilesByDirectory(Directory directory,
      {List<String>? excludePaths}) async {
    if (excludePaths != null) {
      for (var value in excludePaths) {
        if (directory.path.startsWith(value)) {
          return;
        }
      }
    }

    final completer = Completer<void>();

    late final StreamSubscription<FileSystemEntity> subscription;
    subscription = directory.list().listen((entity) async {
      subscription.pause();
      if (entity is File) {
        await entity.delete();
      } else if (entity is Directory) {
        await _deleteFilesByDirectory(entity, excludePaths: excludePaths);
      }
      subscription.resume();
    }, onDone: () {
      completer.complete();
    });

    return completer.future;
  }

  void clearImageCache() async {
    SmartDialog.showLoading(msg: Intl.cacheManagement_tips_clearing_cache.tr);
    for (var p in _imageCachePaths) {
      await _deleteFilesByDirectory(Directory(p));
    }
    _imageCacheSize = 0;
    imageCacheSizeStr.value = "0 B";
    _updateTotal();
    SmartDialog.dismiss();
  }

  void clearVideoCache() async {
    SmartDialog.showLoading(msg: Intl.cacheManagement_tips_clearing_cache.tr);
    for (var p in _videoCachePaths) {
      await _deleteFilesByDirectory(Directory(p));
    }
    _videoCacheSize = 0;
    videoCacheSizeStr.value = "0 B";
    _updateTotal();
    SmartDialog.dismiss();
  }

  void clearAudioCache() async {
    SmartDialog.showLoading(msg: Intl.cacheManagement_tips_clearing_cache.tr);
    for (var p in _audioCachePaths) {
      await _deleteFilesByDirectory(Directory(p));
    }
    _audioCacheSize = 0;
    audioCacheSizeStr.value = "0 B";
    _updateTotal();
    SmartDialog.dismiss();
  }

  void clearOtherCache() async {
    SmartDialog.showLoading(msg: Intl.cacheManagement_tips_clearing_cache.tr);
    var temporaryDirectory = await getTemporaryDirectory();
    var excludePaths = <String>[];
    excludePaths.addAll(_imageCachePaths);
    excludePaths.addAll(_audioCachePaths);
    excludePaths.addAll(_videoCachePaths);
    excludePaths.add(_downloadDir);
    await _deleteFilesByDirectory(temporaryDirectory, excludePaths: excludePaths);
    _otherCacheSize = 0;
    otherCacheSizeStr.value = "0 B";
    _updateTotal();
    SmartDialog.dismiss();
  }

  void clearAllCache() async {
    SmartDialog.showLoading(msg: Intl.cacheManagement_tips_clearing_cache.tr);
    var temporaryDirectory = await getTemporaryDirectory();
    await _deleteFilesByDirectory(temporaryDirectory, excludePaths: [_downloadDir]);
    _imageCacheSize = 0; imageCacheSizeStr.value = "0 B";
    _videoCacheSize = 0; videoCacheSizeStr.value = "0 B";
    _audioCacheSize = 0; audioCacheSizeStr.value = "0 B";
    _otherCacheSize = 0; otherCacheSizeStr.value = "0 B";
    totalCacheSizeStr.value = "0 B";
    SmartDialog.dismiss();
  }
}
