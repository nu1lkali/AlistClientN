import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/util/image_utils.dart';
import 'package:alist/util/alist_plugin.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/string_utils.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/widget/overflow_text.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:extended_image/extended_image.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

/// 全局 HEIC 转换缓存，避免同一文件重复转换
class HeicConvertCache {
  HeicConvertCache._();
  static final HeicConvertCache instance = HeicConvertCache._();

  // key: 原始路径或 url → value: 转换后的 jpg 路径 Future
  final Map<String, Future<String?>> _cache = {};

  /// 获取或发起转换，返回 jpg 路径（失败返回 null）
  Future<String?> getOrConvert(String key, Future<String?> Function() convert) {
    return _cache.putIfAbsent(key, convert);
  }

  void remove(String key) => _cache.remove(key);
}

/// 提前触发 HEIC 转换并缓存，供文件列表在跳转前调用（fire-and-forget）
void preWarmHeicConversion(String? localPath, String url) {
  if (!_isHeic(localPath ?? url)) return;
  final cacheKey = (localPath?.isNotEmpty == true) ? localPath! : url;
  HeicConvertCache.instance.getOrConvert(
    cacheKey,
    () => _doConvertHeic(localPath, url),
  );
}

/// 顶层转换函数（优先用 Android 原生 ImageDecoder，API<28 降级到 flutter_image_compress）
Future<String?> _doConvertHeic(String? localPath, String url) async {
  try {
    String heicFilePath;
    if (localPath != null && localPath.isNotEmpty) {
      heicFilePath = localPath;
    } else {
      final tmpDir = await getTemporaryDirectory();
      final fileName = Uri.parse(url).pathSegments.last;
      final heicTmpPath = '${tmpDir.path}/$fileName';
      if (!File(heicTmpPath).existsSync()) {
        await dio_pkg.Dio().download(url, heicTmpPath);
      }
      heicFilePath = heicTmpPath;
    }

    final tmpDir = await getTemporaryDirectory();
    // 用文件路径的 hash 作为缓存 key，同一文件不重复转换
    final cacheKey = heicFilePath.hashCode.toRadixString(16);
    const int maxLongEdge = 2048;

    // API 28+ 用原生 ImageDecoder，速度更快，内存更可控
    if (Platform.isAndroid) {
      const channel = MethodChannel('com.github.alist.client.plugin');
      final result = await channel.invokeMethod<String>('convertHeic', {
        'srcPath': heicFilePath,
        'cacheDir': tmpDir.path,
        'cacheKey': cacheKey,
        'maxLongEdge': maxLongEdge,
      });
      if (result != null) return result;
      // 原生返回 null 说明 API < 28，降级处理
    }

    // 降级：flutter_image_compress（iOS 或 Android API < 28）
    final outputPath = '${tmpDir.path}/$cacheKey.jpg';
    if (File(outputPath).existsSync()) return outputPath;

    // flutter_image_compress 的缩放算法按短边对齐，用正方形目标让长边也被约束
    final result = await FlutterImageCompress.compressAndGetFile(
      heicFilePath, outputPath,
      quality: 85, minWidth: maxLongEdge, minHeight: maxLongEdge,
      format: CompressFormat.jpeg,
    );
    return result?.path;
  } catch (e) {
    debugPrint('HEIC 转换失败: $e');
    return null;
  }
}

typedef OnGalleryMenuClickCallback = Function(GalleryMenuId menuId);

class GalleryScreen extends StatelessWidget {
  GalleryScreen({Key? key}) : super(key: key);

  final List<String>? urls = Get.arguments["urls"];
  final List<PhotoItem>? files = Get.arguments["files"];
  final int initializedIndex = Get.arguments["index"];

  // use key to get the more icon's location and size
  final GlobalKey _moreIconKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    GalleryController controller = Get.put(GalleryController(
      urls: urls,
      files: files,
      index: initializedIndex,
    ));
    Widget widget = Container(
      color: Colors.black, // Add solid black background to prevent previous page showing through
      child: Stack(
        children: [
          _buildImageViewPager(controller),
          // gradient scrim so AppBar title is readable over bright images
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 100,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: _buildAppBar(controller),
          ),
          // 左下角悬浮切图按钮
          Positioned(
            left: 12,
            bottom: 0,
            child: Obx(() {
              if (controller.urls.length <= 1) return const SizedBox();
              if (!controller.showNavButtons.value) return const SizedBox();
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
                          onPressed: controller.goPrev,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                          onPressed: controller.goNext,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );

    return GalleryMenuAnchor(
        controller: controller,
        child: widget,
        onMenuClickCallback: (menuId) {
          switch (menuId) {
            case GalleryMenuId.copyLink:
              Clipboard.setData(
                  ClipboardData(text: controller.urls[controller.index.value]));
              SmartDialog.showToast(Intl.galleryScreen_copied.tr);
              break;
            case GalleryMenuId.saveToAlbum:
              controller.saveToAlbum(controller.index.value);
              break;
            case GalleryMenuId.imageInfo:
              controller.showImageInfo(controller.index.value);
              break;
            case GalleryMenuId.toggleNavButtons:
              controller.showNavButtons.value = !controller.showNavButtons.value;
              break;
          }
        });
  }

  AppBar _buildAppBar(GalleryController controller) {
    return AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      title: controller.files == null
          ? null
          : Obx(() => OverflowText(
                text: controller.files?[controller.index.value].name ?? "",
                style: const TextStyle(color: Colors.white),
              )),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      actions: [
        Obx(() => IconButton(
              icon: Icon(
                controller.slideshowActive.value
                    ? Icons.pause_circle_outline
                    : Icons.slideshow_rounded,
              ),
              tooltip: controller.slideshowActive.value ? '停止幻灯片' : '幻灯片播放',
              onPressed: controller.toggleSlideshow,
            )),
        IconButton(
          icon: const Icon(Icons.rotate_right_rounded),
          tooltip: '旋转',
          onPressed: controller.rotate,
        ),
        Obx(() => IconButton(
              icon: Icon(
                controller.isFavorite.value
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: controller.isFavorite.value ? Colors.red : Colors.white,
              ),
              tooltip: controller.isFavorite.value ? '取消收藏' : '收藏',
              onPressed: controller.toggleFavorite,
            )),
        _menuMoreIcon(controller),
      ],
    );
  }

  Widget _buildImageViewPager(GalleryController controller) {
    return Obx(
      () => controller.urls.isEmpty
          ? const SizedBox()
          : ExtendedImageGesturePageView.builder(
              itemBuilder: (context, index) {
                String? localPath;
                if (controller.files != null &&
                    controller.files!.length > index) {
                  localPath = controller.files?[index].localPath;
                }
                return GestureDetector(
                  onLongPress: () => controller.saveToAlbum(index),
                  child: Obx(() => RotatedBox(
                        quarterTurns: controller.rotation.value ~/ 90,
                        child: _ImageContainer(
                          url: controller.urls[index],
                          localPath: localPath,
                        ),
                      )),
                );
              },
              controller: controller.pageController,
              onPageChanged: (index) {
                controller.updateIndex(index);
              },
              itemCount: controller.urls.length,
              scrollDirection: Axis.horizontal,
              // 使用 BouncingScrollPhysics 提供更灵敏的滑动体验
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
            ),
    );
  }

  IconButton _menuMoreIcon(GalleryController controller) {
    return IconButton(
      key: _moreIconKey,
      onPressed: () {
        var menuController = controller.menuController;
        RenderObject? renderObject =
            _moreIconKey.currentContext?.findRenderObject();
        if (renderObject is RenderBox) {
          var position = renderObject.localToGlobal(Offset.zero);
          var size = renderObject.size;
          var menuWidth = controller.menuWidth;
          menuController.open(
              position: Offset(position.dx + size.width - menuWidth - 10,
                  position.dy + size.height));
        }
      },
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

class GalleryController extends GetxController {
  final urls = <String>[].obs;
  final List<PhotoItem>? files;
  late RxInt index;
  late ExtendedPageController pageController;
  final isMenuOpen = false.obs;
  final menuController = MenuController();
  var menuWidth = 120.0;
  final rotation = 0.obs; // 0, 90, 180, 270
  final slideshowActive = false.obs;
  final showNavButtons = true.obs; // 是否显示悬浮切图按钮
  Timer? _slideshowTimer;

  Duration get slideshowInterval {
    final seconds = SpUtil.getInt(AlistConstant.slideshowIntervalSeconds, defValue: 3) ?? 3;
    return Duration(seconds: seconds.clamp(1, 60));
  }
  final isFavorite = false.obs;
  final AlistDatabaseController _databaseController = Get.find();
  final UserController _userController = Get.find();

  GalleryController(
      {required List<String>? urls, required this.files, required int index})
      : super() {
    this.urls.value = urls ?? [];
    this.index = index.obs;
    pageController = ExtendedPageController(initialPage: index);
  }

  @override
  void onInit() {
    super.onInit();
    LogUtil.d("index=$index");
    if (files != null && files!.isNotEmpty) {
      _initUrls(files!);
    }
    if (Get.locale.toString().contains("zh")) {
      menuWidth = 140;
    } else {
      menuWidth = 120;
    }
    _checkFavoriteStatus();
    
    // 监听页面切换，更新收藏状态
    ever(index, (_) => _checkFavoriteStatus());
  }

  Future<void> _initUrls(List<PhotoItem> files) async {
    AlistDatabaseController databaseController = Get.find();
    UserController userController = Get.find();
    var user = userController.user.value;

    List<String> urls = [];
    for (var file in files) {
      if (file.localPath == null || file.localPath!.isEmpty) {
        var record = await databaseController.downloadRecordRecordDao
            .findRecordByRemotePath(
                user.serverUrl, user.username, file.remotePath);
        if (record != null && File(record.localPath).existsSync()) {
          file.localPath = record.localPath;
        }
      }

      var url = await FileUtils.makeFileLink(file.remotePath, file.sign);
      if (url == null) {
        break;
      }
      urls.add(url);
    }
    this.urls.value = urls;
    
    // Preload images around initial index
    Future.delayed(const Duration(milliseconds: 100), () {
      _preloadAround(index.value);
    });
  }

  void updateIndex(int index) {
    this.index.value = index;
    rotation.value = 0; // reset rotation on page change
    LogUtil.d("update index=$index");
    _preloadAround(index);
  }

  void goNext() {
    if (index.value >= urls.length - 1) {
      SmartDialog.showToast('已经是最后一张了');
      return;
    }
    pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void goPrev() {
    if (index.value <= 0) {
      SmartDialog.showToast('已经是第一张了');
      return;
    }
    pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  final Set<int> _preloadedIndices = {};
  static const int _maxPreloadCount = 3; // 限制预加载数量，防止内存溢出

  void _preloadAround(int index) {
    // 清理超出范围的旧缓存
    final toRemove = _preloadedIndices
        .where((i) => (i - index).abs() > _maxPreloadCount * 2)
        .toSet();
    for (final i in toRemove) {
      _preloadedIndices.remove(i);
      // 清理 HEIC 转换缓存（避免内存积累）
      if (files != null && files!.length > i) {
        final localPath = files![i].localPath;
        if (localPath != null && localPath.isNotEmpty && _isHeic(localPath)) {
          HeicConvertCache.instance.remove(localPath);
        } else if (i < urls.length && _isHeic(urls[i])) {
          HeicConvertCache.instance.remove(urls[i]);
        }
      }
    }
    
    const preloadCount = _maxPreloadCount;
    for (int i = 1; i <= preloadCount; i++) {
      final next = index + i;
      final prev = index - i;
      if (next < urls.length && !_preloadedIndices.contains(next)) {
        _preloadImage(next);
        _preloadedIndices.add(next);
      }
      if (prev >= 0 && !_preloadedIndices.contains(prev)) {
        _preloadImage(prev);
        _preloadedIndices.add(prev);
      }
    }
  }

  void _preloadImage(int index) {
    try {
      String? localPath;
      if (files != null && files!.length > index) {
        localPath = files?[index].localPath;
      }

      final path = localPath ?? urls[index];

      if (_isHeic(path)) {
        // HEIC 文件：提前触发转换并缓存，不走 Flutter image provider
        final cacheKey = localPath?.isNotEmpty == true ? localPath! : urls[index];
        HeicConvertCache.instance.getOrConvert(
          cacheKey,
          () => _doConvertHeic(localPath, urls[index]),
        );
        return;
      }

      if (localPath != null && localPath.isNotEmpty) {
        final config = ExtendedFileImageProvider(File(localPath));
        precacheImage(config, Get.context!);
      } else {
        final config = ExtendedNetworkImageProvider(urls[index], cache: true);
        precacheImage(config, Get.context!);
      }
    } catch (_) {}
  }

  void rotate() {
    rotation.value = (rotation.value + 90) % 360;
  }

  void toggleSlideshow() {
    if (slideshowActive.value) {
      _stopSlideshow();
    } else {
      _startSlideshow();
    }
  }

  void _startSlideshow() {
    slideshowActive.value = true;
    _slideshowTimer = Timer.periodic(slideshowInterval, (_) {
      if (urls.isEmpty) return;
      final next = (index.value + 1) % urls.length;
      pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopSlideshow() {
    slideshowActive.value = false;
    _slideshowTimer?.cancel();
    _slideshowTimer = null;
  }

  Future<void> _checkFavoriteStatus() async {
    if (files == null || files!.isEmpty || index.value >= files!.length) {
      isFavorite.value = false;
      return;
    }
    
    final file = files![index.value];
    final user = _userController.user.value;
    final favorite = await _databaseController.favoriteDao
        .findByPath(user.serverUrl, user.username, file.remotePath);
    isFavorite.value = favorite != null;
  }

  Future<void> toggleFavorite() async {
    if (files == null || files!.isEmpty || index.value >= files!.length) {
      return;
    }
    
    final file = files![index.value];
    final user = _userController.user.value;
    
    if (isFavorite.value) {
      // 取消收藏
      await _databaseController.favoriteDao
          .deleteByPath(user.serverUrl, user.username, file.remotePath);
      isFavorite.value = false;
      SmartDialog.showToast('已取消收藏');
    } else {
      // 添加收藏
      await _databaseController.favoriteDao.insertRecord(
        Favorite(
          isDir: false,
          serverUrl: user.serverUrl,
          userId: user.username,
          remotePath: file.remotePath,
          path: file.remotePath,
          name: file.name,
          size: file.size ?? 0,
          sign: null,
          thumb: null,
          modified: 0,
          provider: "",
          createTime: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      isFavorite.value = true;
      SmartDialog.showToast('已添加到收藏');
    }
  }

  @override
  void onClose() {
    _stopSlideshow();
    super.onClose();
  }

  Future<void> saveToAlbum(int index) async {
    if (Platform.isAndroid && !(await AlistPlugin.isScopedStorage())) {
      if (!await Permission.storage.isGranted) {
        var storagePermissionStatus = await Permission.storage.request();
        if (!storagePermissionStatus.isGranted) {
          SmartDialog.showToast(Intl.galleryScreen_storagePermissionDenied.tr);
          return;
        }
      }
    }

    var name = files?[index].name;
    var url = urls[index];
    name ??= Uri.parse(url).path.substringAfterLast("/")!;

    name = _makeSavedFileName(name);

    // 有本地路径，直接保存原始文件
    if (files?[index].localPath != null &&
        files![index].localPath!.isNotEmpty) {
      await ImageGallerySaver.saveFile(files![index].localPath!, name: name)
          .then((value) =>
              SmartDialog.showToast(Intl.galleryScreen_savePhotoSucceed.tr));
      return;
    }

    // HEIC/HEIF：getCachedImageFile 返回的是转换后的 jpg，不是原图
    // 需要重新下载原始文件保存
    final originalName = files?[index].name ?? Uri.parse(url).path.substringAfterLast("/") ?? "image.heic";
    if (_isHeic(originalName)) {
      SmartDialog.showToast('正在保存原图...');
      try {
        final tmpDir = await getTemporaryDirectory();
        final tmpFile = File('${tmpDir.path}/${originalName.hashCode}_orig.heic');
        if (!tmpFile.existsSync()) {
          await dio_pkg.Dio().download(url, tmpFile.path);
        }
        await ImageGallerySaver.saveFile(tmpFile.path, name: name)
            .then((_) => SmartDialog.showToast(Intl.galleryScreen_savePhotoSucceed.tr));
      } catch (e) {
        SmartDialog.showToast(Intl.galleryScreen_loadPhotoFailed.tr);
      }
      return;
    }

    File? cacheFile = await getCachedImageFile(url);
    if (cacheFile == null) {
      SmartDialog.showToast(Intl.galleryScreen_loadPhotoFailed.tr);
      return;
    }

    var tmpFilePath = p.join(File(cacheFile.path).parent.path, name);
    await cacheFile.copy(tmpFilePath);
    await ImageGallerySaver.saveFile(tmpFilePath, name: name).then((value) =>
        SmartDialog.showToast(Intl.galleryScreen_savePhotoSucceed.tr));
    await File(tmpFilePath).delete();
  }

  Future<void> showImageInfo(int index) async {
    final file = files?[index];
    final url = urls[index];
    final name = file?.name ?? Uri.parse(url).path.substringAfterLast("/") ?? "";
    final size = file?.size;

    // try to get image dimensions and EXIF from cache
    int? width, height;
    String? dateStr;
    Map<String, dynamic> exifData = {};
    
    try {
      File? cacheFile = await getCachedImageFile(url);
      if (cacheFile != null) {
        // 获取图片尺寸
        final bytes = await cacheFile.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        width = frame.image.width;
        height = frame.image.height;
        
        // 获取文件修改时间
        final stat = await cacheFile.stat();
        dateStr = stat.modified.toString().substring(0, 19);
        
        // 读取 EXIF 信息
        try {
          final exif = await Exif.fromPath(cacheFile.path);
          final attributes = await exif.getAttributes();
          
          // 提取常用 EXIF 信息
          if (attributes != null) {
            // 相机信息
            if (attributes.containsKey('Make')) {
              exifData['相机品牌'] = attributes['Make'];
            }
            if (attributes.containsKey('Model')) {
              exifData['相机型号'] = attributes['Model'];
            }
            
            // 拍摄参数
            if (attributes.containsKey('FNumber')) {
              exifData['光圈'] = 'f/${attributes['FNumber']}';
            }
            if (attributes.containsKey('ExposureTime')) {
              exifData['快门速度'] = '${attributes['ExposureTime']}s';
            }
            if (attributes.containsKey('ISOSpeedRatings')) {
              exifData['ISO'] = attributes['ISOSpeedRatings'];
            }
            if (attributes.containsKey('FocalLength')) {
              exifData['焦距'] = '${attributes['FocalLength']}mm';
            }
            
            // 拍摄时间
            if (attributes.containsKey('DateTime')) {
              exifData['拍摄时间'] = attributes['DateTime'];
            } else if (attributes.containsKey('DateTimeOriginal')) {
              exifData['拍摄时间'] = attributes['DateTimeOriginal'];
            }
            
            // GPS 信息
            if (attributes.containsKey('GPSLatitude') && attributes.containsKey('GPSLongitude')) {
              exifData['GPS'] = '${attributes['GPSLatitude']}, ${attributes['GPSLongitude']}';
            }
            
            // 软件信息
            if (attributes.containsKey('Software')) {
              exifData['软件'] = attributes['Software'];
            }
          }
          
          await exif.close();
        } catch (e) {
          debugPrint('读取 EXIF 失败: $e');
        }
      }
    } catch (e) {
      debugPrint('获取图片信息失败: $e');
    }

    SmartDialog.show(builder: (context) {
      return AlertDialog(
        title: const Text("图片信息"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow("文件名", name),
              if (size != null) _infoRow("大小", _formatBytes(size)),
              if (width != null && height != null)
                _infoRow("分辨率", "${width}x${height}"),
              if (dateStr != null) _infoRow("修改时间", dateStr),
              
              // 显示 EXIF 信息
              if (exifData.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  "EXIF 信息",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...exifData.entries.map((entry) => 
                  _infoRow(entry.key, entry.value.toString())
                ).toList(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: const Text("关闭"),
          )
        ],
      );
    });
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  String? _makeSavedFileName(String originalName) {
    if (Platform.isIOS) {
      return originalName;
    } else {
      String extension = "";
      if (originalName.contains(".")) {
        extension = originalName.substringAfterLast(".")!;
      }
      if (extension.isEmpty) {
        extension = ".jpg";
      }

      return "${const Uuid().v4()}.$extension";
    }
  }
}

bool _isHeic(String path) {
  final ext = path.split('.').last.toLowerCase();
  return ext == 'heic' || ext == 'heif';
}

class _ImageContainer extends StatefulWidget {
  const _ImageContainer({
    super.key,
    required this.url,
    this.localPath,
  });

  final String url;
  final String? localPath;

  @override
  State<_ImageContainer> createState() => _ImageContainerState();
}

class _ImageContainerState extends State<_ImageContainer> {
  String? _convertedFilePath;  // 转换后的本地 JPG 路径
  bool _converting = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    final path = widget.localPath ?? widget.url;
    if (_isHeic(path)) _converting = true;
    _maybeConvertHeic();
  }

  @override
  void didUpdateWidget(_ImageContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.localPath != widget.localPath) {
      _convertedFilePath = null;
      _errorMsg = null;
      final path = widget.localPath ?? widget.url;
      if (_isHeic(path)) setState(() => _converting = true);
      _maybeConvertHeic();
    }
  }

  @override
  void dispose() {
    // 不删除转换后的临时文件，缓存复用
    super.dispose();
  }

  Future<void> _maybeConvertHeic() async {
    final path = widget.localPath ?? widget.url;
    if (!_isHeic(path)) return;

    final cacheKey = widget.localPath?.isNotEmpty == true ? widget.localPath! : widget.url;

    try {
      final convertedPath = await HeicConvertCache.instance.getOrConvert(
        cacheKey,
        () => _doConvertHeic(widget.localPath, widget.url),
      );

      if (convertedPath == null) throw Exception('转换返回空路径');
      if (mounted) setState(() { _convertedFilePath = convertedPath; _converting = false; });
    } catch (e) {
      HeicConvertCache.instance.remove(cacheKey);
      debugPrint('HEIC 转换失败: $e');
      if (mounted) setState(() { _errorMsg = '图片加载失败'; _converting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gestureConfig = GestureConfig(
      minScale: 1,
      animationMinScale: 0.9,
      maxScale: 3.0,
      animationMaxScale: 3.5,
      speed: 1.0,
      inertialSpeed: 100.0,
      initialScale: 1.0,
      inPageView: true,
      cacheGesture: true,
      initialAlignment: InitialAlignment.center,
    );

    void onDoubleTap(ExtendedImageGestureState state) {
      var currentScale = state.gestureDetails?.totalScale ?? 1.0;
      if (currentScale >= 2.0) {
        state.handleDoubleTap(scale: 1);
      } else {
        state.handleDoubleTap(scale: math.min(currentScale + 1, 3));
      }
    }

    final path = widget.localPath ?? widget.url;

    // HEIC 转换中
    if (_isHeic(path) && _converting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text('正在转换 HEIC...', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      );
    }

    // HEIC 转换失败
    if (_isHeic(path) && _errorMsg != null) {
      return Center(
        child: Text(_errorMsg!, style: const TextStyle(color: Colors.white70)),
      );
    }

    // HEIC 转换完成，用 ResizeImage 限制解码分辨率防 OOM（2048px 覆盖 2K 屏）
    if (_isHeic(path) && _convertedFilePath != null) {
      return ExtendedImage(
        image: ResizeImage(
          FileImage(File(_convertedFilePath!)),
          width: 2048,
          policy: ResizeImagePolicy.fit,
          allowUpscaling: false,
        ),
        fit: BoxFit.contain,
        mode: ExtendedImageMode.gesture,
        enableMemoryCache: true,
        gaplessPlayback: true,
        initGestureConfigHandler: (_) => gestureConfig,
        onDoubleTap: onDoubleTap,
      );
    }

    // 本地非 HEIC 文件
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      return ExtendedImage.file(
        File(widget.localPath!),
        fit: BoxFit.contain,
        mode: ExtendedImageMode.gesture,
        enableMemoryCache: true,
        gaplessPlayback: true,
        initGestureConfigHandler: (_) => gestureConfig,
        onDoubleTap: onDoubleTap,
      );
    }

    // 网络图片
    return ExtendedImage(
      image: noProxyImageProvider(widget.url, cache: true),
      fit: BoxFit.contain,
      mode: ExtendedImageMode.gesture,
      enableMemoryCache: true,
      gaplessPlayback: true,
      initGestureConfigHandler: (_) => gestureConfig,
      onDoubleTap: onDoubleTap,
    );
  }
}

class GalleryMenuAnchor extends StatelessWidget {
  final GalleryController controller;
  final Widget child;
  final OnGalleryMenuClickCallback? onMenuClickCallback;

  const GalleryMenuAnchor({
    super.key,
    required this.controller,
    required this.child,
    this.onMenuClickCallback,
  });

  @override
  Widget build(BuildContext context) {
    final menuWidth = controller.menuWidth;
    return MenuAnchor(
      style: MenuStyle(
          fixedSize: MaterialStatePropertyAll(Size.fromWidth(menuWidth))),
      controller: controller.menuController,
      anchorTapClosesMenu: true,
      onOpen: () {
        controller.isMenuOpen.value = true;
      },
      onClose: () {
        controller.isMenuOpen.value = false;
      },
      menuChildren: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: _buildMenus(
            menuWidth,
            onMenuClickCallback,
          ),
        ),
      ],
      child: Obx(
        () => AbsorbPointer(
          absorbing: controller.isMenuOpen.value,
          child: child,
        ),
      ),
    );
  }

  List<Widget> _buildMenus(
      double menuWidth, OnGalleryMenuClickCallback? onMenuClickCallback) {
    var copyButton = MenuItemButton(
        onPressed: () => onMenuClickCallback?.call(GalleryMenuId.copyLink),
        child: Text(Intl.galleryScreen_menu_copyLink.tr));
    var saveButton = MenuItemButton(
        onPressed: () => onMenuClickCallback?.call(GalleryMenuId.saveToAlbum),
        child: Text(Intl.galleryScreen_menu_saveToAlbum.tr));
    var infoButton = MenuItemButton(
        onPressed: () => onMenuClickCallback?.call(GalleryMenuId.imageInfo),
        child: const Text("图片信息"));
    var navButton = Obx(() => MenuItemButton(
        onPressed: () => onMenuClickCallback?.call(GalleryMenuId.toggleNavButtons),
        child: Text(controller.showNavButtons.value ? "隐藏切图按钮" : "显示切图按钮")));
    return [
      SizedBox(width: menuWidth),
      copyButton,
      const Divider(),
      saveButton,
      const Divider(),
      infoButton,
      const Divider(),
      navButton,
    ];
  }
}

enum GalleryMenuId { copyLink, saveToAlbum, imageInfo, toggleNavButtons }

class PhotoItem {
  final String name;
  String? localPath;
  final String remotePath;
  final String? sign;
  final String? provider;
  final int? size;

  PhotoItem({
    required this.name,
    this.localPath,
    required this.remotePath,
    this.sign,
    this.provider,
    this.size,
  });
}
