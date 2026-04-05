import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/util/alist_plugin.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/string_utils.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/widget/overflow_text.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

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
          )
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
  Timer? _slideshowTimer;
  static const slideshowInterval = Duration(seconds: 3);

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
    // preload images around initial index
    _preloadAround(index.value);
  }

  void updateIndex(int index) {
    this.index.value = index;
    rotation.value = 0; // reset rotation on page change
    LogUtil.d("update index=$index");
    _preloadAround(index);
  }

  void _preloadAround(int index) {
    const preloadCount = 2;
    for (int i = 1; i <= preloadCount; i++) {
      final next = index + i;
      final prev = index - i;
      if (next < urls.length) _preloadImage(urls[next]);
      if (prev >= 0) _preloadImage(urls[prev]);
    }
  }

  void _preloadImage(String url) {
    try {
      final config = ExtendedNetworkImageProvider(url, cache: true);
      precacheImage(config, Get.context!);
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
    if (files?[index].localPath != null &&
        files![index].localPath!.isNotEmpty) {
      await ImageGallerySaver.saveFile(files![index].localPath!, name: name)
          .then((value) =>
              SmartDialog.showToast(Intl.galleryScreen_savePhotoSucceed.tr));
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

    // try to get image dimensions from cache
    int? width, height;
    String? dateStr;
    try {
      File? cacheFile = await getCachedImageFile(url);
      if (cacheFile != null) {
        final bytes = await cacheFile.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        width = frame.image.width;
        height = frame.image.height;
        final stat = await cacheFile.stat();
        dateStr = stat.modified.toString().substring(0, 19);
      }
    } catch (_) {}

    SmartDialog.show(builder: (context) {
      return AlertDialog(
        title: const Text("图片信息"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow("文件名", name),
            if (size != null) _infoRow("大小", _formatBytes(size)),
            if (width != null && height != null)
              _infoRow("分辨率", "${width}x${height}"),
            if (dateStr != null) _infoRow("修改时间", dateStr),
          ],
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

class _ImageContainer extends StatelessWidget {
  const _ImageContainer({
    super.key,
    required this.url,
    this.localPath,
  });

  final String url;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    var gestureConfig = GestureConfig(
      minScale: 1,
      animationMinScale: 0.9,
      maxScale: 3.0,
      animationMaxScale: 3.5,
      speed: 1.0,
      inertialSpeed: 100.0,
      initialScale: 1.0,
      inPageView: true,
      cacheGesture: false,
      initialAlignment: InitialAlignment.center,
    );

    if (localPath != null && localPath!.isNotEmpty) {
      return ExtendedImage.file(
        File(localPath!),
        fit: BoxFit.contain,
        mode: ExtendedImageMode.gesture,
        initGestureConfigHandler: (state) {
          return gestureConfig;
        },
        onDoubleTap: (ExtendedImageGestureState state) {
          // Log.d("currentScale=${state.gestureDetails?.totalScale}");
          var currentScale = state.gestureDetails?.totalScale ?? 1.0;
          if (currentScale >= 2.0) {
            state.handleDoubleTap(scale: 1);
          } else {
            state.handleDoubleTap(scale: min(currentScale + 1, 3));
          }
        },
      );
    } else {
      return ExtendedImage.network(
        url,
        fit: BoxFit.contain,
        mode: ExtendedImageMode.gesture,
        initGestureConfigHandler: (state) {
          return gestureConfig;
        },
        onDoubleTap: (ExtendedImageGestureState state) {
          // Log.d("currentScale=${state.gestureDetails?.totalScale}");
          var currentScale = state.gestureDetails?.totalScale ?? 1.0;
          if (currentScale >= 2.0) {
            state.handleDoubleTap(scale: 1);
          } else {
            state.handleDoubleTap(scale: min(currentScale + 1, 3));
          }
        },
      );
    }
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
    return [
      SizedBox(width: menuWidth),
      copyButton,
      const Divider(),
      saveButton,
      const Divider(),
      infoButton,
    ];
  }
}

enum GalleryMenuId { copyLink, saveToAlbum, imageInfo }

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
