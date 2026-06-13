import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/disliked_video.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/database/table/file_viewing_record.dart';
import 'package:alist/entity/tiktok_play_list_model.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/log_utils.dart' as log;
import 'package:alist/util/user_controller.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock/wakelock.dart';
import 'dart:io';

class StrmPlayerScreen extends StatefulWidget {
  const StrmPlayerScreen({super.key});
  @override
  State<StrmPlayerScreen> createState() => _StrmPlayerScreenState();
}

class _StrmPlayerScreenState extends State<StrmPlayerScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final TikTokPlayListModel _playList;
  late int _currentIndex;

  VideoPlayerController? _controller;
  bool _isInitializing = false;
  bool _isPlaying = false;
  bool _isLandscape = false;
  bool _loopSingle = false;
  bool _hideUI = false;
  bool _manualHideUI = false; // 竖屏下用户手动点击隐藏按钮

  final AlistDatabaseController _database = Get.find();
  final UserController _userController = Get.find();

  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  Timer? _progressTimer;
  final GlobalKey _repaintKey = GlobalKey();

  Timer? _landscapeHideTimer;
  static const _landscapeAutoHide = Duration(seconds: 2);

  double _uiOpacity = 1.0;

  // ══════ Gesture state ══════
  static const _gestureDecideThreshold = 10.0; // px
  static const _systemGestureBottomMargin = 40.0; // px, ignore touches near bottom edge
  double _screenWidth = 1;
  double _screenHeight = 1;
  bool _ignoreCurrentGesture = false;

  // horizontal seek
  bool _isSeeking = false;
  double _seekStartX = 0;
  Duration _seekStartPosition = Duration.zero;
  Duration _seekTarget = Duration.zero;
  bool _wasPlayingBeforeSeek = false;

  // vertical brightness / volume
  bool _isVerticalDragging = false;
  double _verticalStartY = 0;
  bool? _isLeftSide; // true=left(brightness), false=right(volume)
  double _dragStartBrightness = 0.5;
  double _dragStartVolume = 0.5;
  double _currentBrightness = 0.5;
  double _currentVolume = 0.5;
  bool _showBrightnessIndicator = false;
  bool _showVolumeIndicator = false;
  Timer? _indicatorFadeTimer;

  // Playlist drawer
  bool _isPlaylistVisible = false;
  late final AnimationController _playlistAnimController;
  late final Animation<Offset> _playlistSlideAnim;
  bool _nameSortAscending = true;
  bool _sizeSortAscending = false;
  late List<TikTokVideoItem> _sortedVideos;
  late Map<int, int> _videoIndexMap;

  // Preload next video
  VideoPlayerController? _preloadController;
  int _preloadIdx = -1;
  Timer? _preloadTimer;

  void _startLandscapeAutoHide() {
    _landscapeHideTimer?.cancel();
    if (_isLandscape && _isPlaying && !_hideUI) {
      _landscapeHideTimer = Timer(_landscapeAutoHide, () {
        if (mounted) setState(() => _hideUI = true);
      });
    }
  }

  void _cancelLandscapeAutoHide() {
    _landscapeHideTimer?.cancel();
  }

  // ═══════════════ Gesture handlers ═══════════════
  void _initBrightnessAndVolume() async {
    try {
      final saved = SpUtil.getDouble(AlistConstant.strmBrightness);
      if (saved != null && saved >= 0 && saved <= 1) {
        _currentBrightness = saved;
      } else {
        // 优先读取系统亮度（而非 App 级别亮度），避免首次安装时读到 0
        try {
          _currentBrightness = await ScreenBrightness().system;
        } catch (_) {
          _currentBrightness = await ScreenBrightness().current;
        }
        // 下限保护：防止系统亮度读取失败导致黑屏
        if (_currentBrightness < 0.1) _currentBrightness = 1.0;
      }
      ScreenBrightness().setScreenBrightness(_currentBrightness);
    } catch (_) { _currentBrightness = 1.0; }
    try { _currentVolume = await VolumeController().getVolume(); } catch (_) { _currentVolume = 0.5; }
  }

  void _onPointerDown(PointerDownEvent e) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final bottomThreshold = bottomInset > 0 ? bottomInset : _systemGestureBottomMargin;
    _ignoreCurrentGesture = e.position.dy > _screenHeight - bottomThreshold;
    if (_ignoreCurrentGesture) return;

    // 左右边缘 24dp 安全边距：避免与系统返回手势冲突
    final edgeSafeZone = 24.0;
    final dx = e.position.dx;
    if (dx < edgeSafeZone || dx > _screenWidth - edgeSafeZone) {
      _ignoreCurrentGesture = true;
      return;
    }

    _seekStartX = e.position.dx;
    _verticalStartY = e.position.dy;
    _isSeeking = false;
    _isVerticalDragging = false;
    _isLeftSide = null;
    _seekStartPosition = _pos;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_ignoreCurrentGesture) return;

    final dx = e.position.dx - _seekStartX;
    final dy = e.position.dy - _verticalStartY;

    // direction not yet decided
    if (!_isSeeking && !_isVerticalDragging) {
      if (dx.abs() < _gestureDecideThreshold && dy.abs() < _gestureDecideThreshold) return;
      if (dx.abs() > dy.abs()) {
        // horizontal → seek
        _isSeeking = true;
        _wasPlayingBeforeSeek = _isPlaying;
        _controller?.pause();
        _progressTimer?.cancel();
      } else {
        // vertical → brightness / volume
        _isVerticalDragging = true;
        _isLeftSide = e.position.dx < _screenWidth / 2;
        if (_isLeftSide!) {
          _dragStartBrightness = _currentBrightness;
        } else {
          _dragStartVolume = _currentVolume;
        }
      }
    }

    if (_isSeeking) {
      final totalMs = _dur.inMilliseconds.toDouble();
      if (totalMs <= 0) return;
      // Full-screen swipe ≈ 8% of total duration
      // 2h video → ~10min, 20min video → ~1.5min, 10min video → ~50s
      final sensitivityFactor = (totalMs * 0.08) / _screenWidth;
      final deltaMs = (dx * sensitivityFactor).round();
      final targetMs = (_seekStartPosition.inMilliseconds + deltaMs).clamp(0, totalMs.toInt());
      setState(() => _seekTarget = Duration(milliseconds: targetMs));
    }

    if (_isVerticalDragging) {
      final dragDistance = _verticalStartY - e.position.dy;
      final ratio = (dragDistance / _screenHeight * 1.5).clamp(-1.0, 1.0);
      if (_isLeftSide!) {
        _currentBrightness = (_dragStartBrightness + ratio).clamp(0.0, 1.0);
        ScreenBrightness().setScreenBrightness(_currentBrightness);
        SpUtil.putDouble(AlistConstant.strmBrightness, _currentBrightness);
        setState(() { _showBrightnessIndicator = true; _showVolumeIndicator = false; });
      } else {
        _currentVolume = (_dragStartVolume + ratio).clamp(0.0, 1.0);
        VolumeController().setVolume(_currentVolume, showSystemUI: false);
        setState(() { _showVolumeIndicator = true; _showBrightnessIndicator = false; });
      }
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_ignoreCurrentGesture) {
      _ignoreCurrentGesture = false;
      return;
    }
    _ignoreCurrentGesture = false;

    final dx = e.position.dx - _seekStartX;
    final dy = e.position.dy - _verticalStartY;

    if (_isSeeking) {
      _controller?.seekTo(_seekTarget);
      if (_wasPlayingBeforeSeek) _controller?.play();
      _startTimer();
      setState(() => _isSeeking = false);
    }

    if (_isVerticalDragging) {
      setState(() { _isVerticalDragging = false; });
      _indicatorFadeTimer?.cancel();
      _indicatorFadeTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() { _showBrightnessIndicator = false; _showVolumeIndicator = false; });
      });
    }

    // tap detection: minimal movement → toggle play/pause
    if (!_isSeeking && !_isVerticalDragging &&
        dx.abs() < _gestureDecideThreshold && dy.abs() < _gestureDecideThreshold) {
      _onScreenTap();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playList = Get.arguments as TikTokPlayListModel;
    _currentIndex = _playList.initialIndex;
    _uiOpacity = SpUtil.getDouble(AlistConstant.tiktokUiOpacity, defValue: 1.0) ?? 1.0;

    _sortedVideos = List.from(_playList.videos);
    _updateVideoIndexMap();

    _playlistAnimController = AnimationController(
        duration: const Duration(milliseconds: 250), vsync: this);
    _playlistSlideAnim = Tween<Offset>(
            begin: const Offset(1.0, 0.0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _playlistAnimController, curve: Curves.easeOutCubic));

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    Wakelock.enable();

    _initController(_currentIndex);
    _initBrightnessAndVolume();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _landscapeHideTimer?.cancel();
    _preloadTimer?.cancel();
    _controller?.dispose();
    _preloadController?.dispose();
    _preloadController = null;
    _playlistAnimController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Wakelock.disable();
    // 释放系统亮度控制权，恢复系统默认亮度调节
    try {
      ScreenBrightness().resetScreenBrightness();
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _safePause();
    } else if (state == AppLifecycleState.resumed) {
      _safePlay();
    }
  }

  // ═══════════════ Controller Management ═══════════════
  Future<int?> _fetchVideoSize(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final req = await client.openUrl('HEAD', Uri.parse(url));
      final resp = await req.close();
      final length = resp.contentLength;
      client.close();
      if (length > 0) return length;
    } catch (_) {}
    return null;
  }

  Future<void> _initController(int idx) async {
    if (idx < 0 || idx >= _playList.videos.length) return;
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      _controller?.dispose();
      _controller = null;
      if (mounted) setState(() {});

      final v = _playList.videos[idx];
      final url = v.videoUrl;
      if (url == null || url.isEmpty) {
        _isInitializing = false;
        return;
      }

      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: v.provider == 'BaiduNetdisk'
            ? {'User-Agent': 'pan.baidu.com'}
            : {},
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        _isInitializing = false;
        return;
      }

      ctrl.setLooping(_loopSingle);
      _controller = ctrl;
      _isInitializing = false;

      ctrl.play();
      _isPlaying = true;
      _recordViewing(idx);
      _startTimer();
      if (mounted) setState(() {});

      // Fetch real video size in background (non-blocking)
      _fetchVideoSize(url).then((size) {
        if (size != null && size > 0 && mounted && _currentIndex == idx) {
          _playList.videos[idx].fileSize = size;
          // 更新观看记录中的文件大小（解决 strm 文件记录显示 0B 的问题）
          _recordViewing(idx);
          if (mounted) setState(() {});
        }
      });

      // Schedule preload of next video after 2 seconds
      _schedulePreload(idx);
    } catch (e) {
      log.Log.e('StrmPlayer initCtrl[$idx]: $e');
      _isInitializing = false;
      if (mounted) setState(() {});
    }
  }

  void _schedulePreload(int currentIdx) {
    _preloadTimer?.cancel();
    _disposePreload();
    final preloadEnabled = SpUtil.getBool(AlistConstant.strmPreloadEnabled, defValue: false) ?? false;
    if (!preloadEnabled) return;
    final nextIdx = _loopSingle ? currentIdx : currentIdx + 1;
    if (nextIdx < 0 || nextIdx >= _playList.videos.length) return;
    if (_loopSingle && nextIdx == currentIdx) return;
    _preloadTimer = Timer(const Duration(seconds: 2), () {
      _preloadNext(nextIdx);
    });
  }

  Future<void> _preloadNext(int idx) async {
    if (idx < 0 || idx >= _playList.videos.length) return;
    try {
      final v = _playList.videos[idx];
      final url = v.videoUrl;
      if (url == null || url.isEmpty) return;

      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: v.provider == 'BaiduNetdisk'
            ? {'User-Agent': 'pan.baidu.com'}
            : {},
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      _preloadController = ctrl;
      _preloadIdx = idx;

      _fetchVideoSize(url).then((size) {
        if (size != null && size > 0 && mounted) {
          _playList.videos[idx].fileSize = size;
          if (mounted) setState(() {});
        }
      });
    } catch (_) {}
  }

  void _disposePreload() {
    _preloadController?.dispose();
    _preloadController = null;
    _preloadIdx = -1;
  }

  void _safePlay() {
    try {
      final c = _controller;
      if (c != null && c.value.isInitialized) {
        c.play();
        _isPlaying = true;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _safePause() {
    try {
      final c = _controller;
      if (c != null && c.value.isInitialized) {
        c.pause();
        _isPlaying = false;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  // ═══════════════ DB ═══════════════
  Future<void> _recordViewing(int idx) async {
    if (idx < 0 || idx >= _playList.videos.length) return;
    try {
      final v = _playList.videos[idx];
      final u = _userController.user.value;
      await _database.fileViewingRecordDao
          .deleteByPath(u.serverUrl, u.username, v.filePath);
      await _database.fileViewingRecordDao.insertRecord(FileViewingRecord(
        serverUrl: u.serverUrl,
        userId: u.username,
        remotePath: v.filePath,
        name: v.fileName,
        path: v.filePath,
        size: v.fileSize ?? 0,
        sign: v.sign,
        thumb: v.thumb,
        modified: v.modifiedMilliseconds ?? 0,
        provider: v.provider ?? '',
        createTime: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (_) {}
  }

  Future<void> _loadStates(int idx) async {
    if (idx < 0 || idx >= _playList.videos.length || !mounted) return;
    try {
      final v = _playList.videos[idx];
      final u = _userController.user.value;
      v.isLiked = (await _database.favoriteDao
              .findByPath(u.serverUrl, u.username, v.filePath)) !=
          null;
      v.isDisliked = (await _database.dislikedVideoDao
              .findByPath(u.serverUrl, u.username, v.filePath)) !=
          null;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final v = _playList.videos[_currentIndex];
    v.isLiked = !v.isLiked;
    if (v.isLiked && v.isDisliked) v.isDisliked = false;
    try {
      final u = _userController.user.value;
      if (v.isLiked) {
        await _database.dislikedVideoDao
            .deleteByPath(u.serverUrl, u.username, v.filePath);
        await _database.favoriteDao.insertRecord(Favorite(
          isDir: false,
          serverUrl: u.serverUrl,
          userId: u.username,
          remotePath: v.filePath,
          name: v.fileName,
          path: v.filePath,
          size: v.fileSize ?? 0,
          sign: v.sign,
          thumb: v.thumb,
          modified: v.modifiedMilliseconds ?? 0,
          provider: v.provider ?? '',
          createTime: DateTime.now().millisecondsSinceEpoch,
        ));
      } else {
        await _database.favoriteDao
            .deleteByPath(u.serverUrl, u.username, v.filePath);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _toggleDislike() async {
    final v = _playList.videos[_currentIndex];
    v.isDisliked = !v.isDisliked;
    if (v.isDisliked && v.isLiked) v.isLiked = false;
    try {
      final u = _userController.user.value;
      if (v.isDisliked) {
        await _database.favoriteDao
            .deleteByPath(u.serverUrl, u.username, v.filePath);
        await _database.dislikedVideoDao.insertRecord(DislikedVideo(
          serverUrl: u.serverUrl,
          userId: u.username,
          remotePath: v.filePath,
          name: v.fileName,
          path: v.filePath,
          size: v.fileSize ?? 0,
          sign: v.sign,
          thumb: v.thumb,
          modified: v.modifiedMilliseconds ?? 0,
          provider: v.provider ?? '',
          createTime: DateTime.now().millisecondsSinceEpoch,
        ));
      } else {
        await _database.dislikedVideoDao
            .deleteByPath(u.serverUrl, u.username, v.filePath);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  // ═══════════════ Timer ═══════════════
  bool _completing = false;
  void _startTimer() {
    _progressTimer?.cancel();
    _progressTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      try {
        final c = _controller;
        if (c != null && c.value.isInitialized) {
          setState(() {
            _pos = c.value.position;
            _dur = c.value.duration;
          });
          if (c.value.duration > Duration.zero &&
              c.value.position >=
                  c.value.duration -
                      const Duration(milliseconds: 500) &&
              !_completing) {
            _completing = true;
            if (_loopSingle) {
              c.seekTo(Duration.zero)
                  .then((_) {
                c.play();
                _completing = false;
              });
            } else if (_currentIndex < _playList.videos.length - 1) {
              _playAt(_currentIndex + 1).then((_) => _completing = false);
            } else {
              _safePause();
              _completing = false;
            }
          }
        }
      } catch (_) {}
    });
  }

  // ═══════════════ Playback Control ═══════════════
  Future<void> _playAt(int idx) async {
    if (idx < 0 || idx >= _playList.videos.length) return;
    _progressTimer?.cancel();
    _preloadTimer?.cancel();
    _currentIndex = idx;
    _pos = Duration.zero;
    _dur = Duration.zero;
    _isPlaying = false;
    if (mounted) setState(() {});

    if (_preloadIdx == idx && _preloadController != null) {
      final ctrl = _preloadController!;
      _preloadController = null;
      _preloadIdx = -1;

      _controller?.dispose();
      _controller = ctrl;
      _isInitializing = false;

      ctrl.setLooping(_loopSingle);
      ctrl.play();
      _isPlaying = true;
      _recordViewing(idx);
      _startTimer();
      _loadStates(idx);
      if (mounted) setState(() {});
      _schedulePreload(idx);
    } else {
      _disposePreload();
      await _initController(idx);
      _loadStates(idx);
    }
  }

  void _togglePlayPause() {
    try {
      final c = _controller;
      if (c == null || !c.value.isInitialized) return;
      if (_isPlaying) {
        c.pause();
        _isPlaying = false;
        _cancelLandscapeAutoHide();
      } else {
        c.play();
        _isPlaying = true;
        _hideUI = false;
        _manualHideUI = false;
        _startLandscapeAutoHide();
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _onScreenTap() {
    if (_isLandscape) {
      if (_hideUI) {
        _hideUI = false;
        _manualHideUI = false;
        _startLandscapeAutoHide();
      } else {
        _hideUI = true;
        _manualHideUI = true;
        _cancelLandscapeAutoHide();
      }
    } else {
      if (_hideUI) {
        // 竖屏手动隐藏后，单击屏幕不恢复显示
        if (_manualHideUI) return;
        setState(() { _hideUI = false; _manualHideUI = false; });
      } else {
        _togglePlayPause();
      }
    }
    if (mounted) setState(() {});
  }

  void _toggleOrientation() {
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
      _cancelLandscapeAutoHide();
      _hideUI = false;
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight
      ]);
      _hideUI = false;
      _startLandscapeAutoHide();
    }
    _isLandscape = !_isLandscape;
    if (mounted) setState(() {});
  }

  void _toggleLoop() {
    _loopSingle = !_loopSingle;
    try {
      _controller?.setLooping(_loopSingle);
    } catch (_) {}
    if (mounted) setState(() {});
    SmartDialog.showToast(_loopSingle ? '单视频循环' : '自动播放下一个');
  }

  // ═══════════════ Seek ═══════════════
  void _onSeekStart() {
    _progressTimer?.cancel();
  }

  void _onSeekChanged(double val) {
    if (_dur.inMilliseconds <= 0) return;
    setState(
        () => _pos = Duration(milliseconds: (val * _dur.inMilliseconds).round()));
  }

  void _onSeekEnd(double val) {
    try {
      if (_dur.inMilliseconds > 0) {
        _controller
            ?.seekTo(Duration(milliseconds: (val * _dur.inMilliseconds).round()));
      }
    } catch (_) {}
    _startTimer();
  }

  // ═══════════════ Screenshot ═══════════════
  Future<void> _takeScreenshot() async {
    try {
      SmartDialog.showLoading(msg: '截图中...');
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) {
        SmartDialog.dismiss();
        return;
      }
      final boundary =
          _repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        SmartDialog.dismiss();
        SmartDialog.showToast('截图失败');
        return;
      }

      double pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ctrl = _controller;
      if (ctrl != null && ctrl.value.isInitialized) {
        final videoSize = ctrl.value.size;
        final widgetWidth = boundary.size.width;
        if (widgetWidth > 0 && videoSize.width > 0) {
          pixelRatio = videoSize.width / widgetWidth;
        }
      }

      final ui.Image image =
          await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        SmartDialog.dismiss();
        SmartDialog.showToast('截图失败');
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      if (bytes.length < 100) {
        SmartDialog.dismiss();
        SmartDialog.showToast('截图失败');
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final fileName =
          "alist_${DateTime.now().millisecondsSinceEpoch}.png";
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);
      final result =
          await ImageGallerySaver.saveFile(tempFile.path, name: fileName);
      SmartDialog.dismiss();
      SmartDialog.showToast(
          result['isSuccess'] == true ? '截图已保存到相册' : '保存失败');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('截图失败: $e');
    }
  }

  // ═══════════════ Video Info ═══════════════
  void _showInfo() {
    final v = _playList.videos[_currentIndex];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white30,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                const Text('视频信息',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _infoRow('文件名', v.fileName),
                _infoRow('文件大小', v.formattedSize),
                _infoRow('文件路径', v.filePath),
                _infoRow('修改时间', v.formattedModified),
                _infoRow('Provider', v.provider ?? '未知'),
                _infoRow('播放位置',
                    '${_currentIndex + 1} / ${_playList.videos.length}'),
                const SizedBox(height: 16),
              ]),
        ),
      ),
    );
  }

  Widget _infoRow(String l, String val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 80,
                  child: Text(l,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13))),
              Expanded(
                  child: Text(val,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13))),
            ]),
      );

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  // ═══════════════ Playlist Drawer ═══════════════
  void _updateVideoIndexMap() {
    _videoIndexMap = {};
    for (int sortedIdx = 0; sortedIdx < _sortedVideos.length; sortedIdx++) {
      final originalIdx = _playList.videos
          .indexWhere((v) => v.filePath == _sortedVideos[sortedIdx].filePath);
      _videoIndexMap[sortedIdx] = originalIdx >= 0 ? originalIdx : sortedIdx;
    }
  }

  int _getCurrentSortedIndex() {
    return _sortedVideos.indexWhere(
        (v) => v.filePath == _playList.videos[_currentIndex].filePath);
  }

  void _togglePlaylist() {
    if (_isPlaylistVisible) {
      _playlistAnimController.reverse();
      setState(() {
        _isPlaylistVisible = false;
      });
    } else {
      setState(() {
        _isPlaylistVisible = true;
      });
      _playlistAnimController.forward();
    }
  }

  int _naturalCompare(String a, String b) {
    final regExp = RegExp(r'(\d+)');
    final aM = regExp.allMatches(a).toList();
    final bM = regExp.allMatches(b).toList();
    int ai = 0, bi = 0, api = 0, bpi = 0;
    while (ai < a.length && bi < b.length) {
      if (api < aM.length &&
          bpi < bM.length &&
          aM[api].start == ai &&
          bM[bpi].start == bi) {
        final aNum = int.tryParse(aM[api].group(0) ?? "") ?? 0;
        final bNum = int.tryParse(bM[bpi].group(0) ?? "") ?? 0;
        if (aNum != bNum) return aNum.compareTo(bNum);
        ai = aM[api].end;
        bi = bM[bpi].end;
        api++;
        bpi++;
      } else {
        final ac = a[ai].toLowerCase();
        final bc = b[bi].toLowerCase();
        if (ac != bc) return ac.compareTo(bc);
        ai++;
        bi++;
      }
    }
    if (ai < a.length) return 1;
    if (bi < b.length) return -1;
    return 0;
  }

  // ═══════════════ Build ═══════════════
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    _screenWidth = screenSize.width;
    _screenHeight = screenSize.height;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            behavior: HitTestBehavior.opaque,
            child: RepaintBoundary(
                key: _repaintKey, child: _buildVideoView())),
        _buildPauseIcon(),
        _buildTopBar(),
        if (!_hideUI) _buildToolBar(),
        _buildProgress(),
        if (!_hideUI && !_isLandscape) _buildBottomInfo(),
        if (!_hideUI && _playList.videos.length > 1 && !_isLandscape)
          _buildFloatingSwitchButton(),
        if (_isSeeking) _buildSeekPreview(),
        if (_showBrightnessIndicator && _isVerticalDragging)
          Positioned(left: 20, top: 0, bottom: 0,
              child: Center(child: _VerticalSliderIndicator(
                  icon: Icons.brightness_high_rounded,
                  value: _currentBrightness,
                  color: Colors.amber))),
        if (_showVolumeIndicator && _isVerticalDragging)
          Positioned(right: 20, top: 0, bottom: 0,
              child: Center(child: _VerticalSliderIndicator(
                  icon: Icons.volume_up_rounded,
                  value: _currentVolume,
                  color: Colors.blue))),
        if (_isPlaylistVisible) _buildPlaylistScrim(),
        if (_isPlaylistVisible) _buildPlaylistDrawer(),
      ]),
    );
  }

  Widget _buildVideoView() {
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      if (_isLandscape) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
        );
      }
      return Center(
          child:
              AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)));
    }
    return const Center(
        child: CircularProgressIndicator(
            color: Colors.white, strokeWidth: 2));
  }

  Widget _buildPauseIcon() {
    if (_isPlaying) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Center(
          child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(36)),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white70, size: 44))),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Opacity(
              opacity: _uiOpacity,
              child: Row(children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white, size: 24),
                  onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: _playList.videos.length > 1
                        ? _togglePlaylist
                        : null,
                    child: Container(
                      height: 36,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _playList
                                    .videos[_currentIndex].fileName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_playList.videos.length > 1) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                  Icons.arrow_drop_down_rounded,
                                  color: Colors.white70,
                                  size: 20),
                            ],
                          ]),
                    ),
                  ),
                ),
              ),
              if (!_isLandscape)
                IconButton(
                  icon: Icon(
                      _hideUI
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.white,
                      size: 22),
                  onPressed: () {
                    setState(() {
                      _hideUI = !_hideUI;
                      _manualHideUI = _hideUI;
                    });
                  },
                )
              else
                const SizedBox(width: 48),
            ]),
            ),
          ),
        ));
  }

  Widget _buildToolBar() {
    final v = _playList.videos[_currentIndex];
    final screenH = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final bottomOffset = _isLandscape ? (bottomPad + 70) : 160.0;
    final maxH = screenH - topPad - bottomOffset - 20;
    return Positioned(
        right: 12,
        bottom: bottomOffset,
        child: Opacity(
          opacity: _uiOpacity,
          child: SizedBox(
            height: maxH.clamp(0.0, 500.0),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_isLandscape)
                    _toolbarBtn(
                        icon: _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        label: _isPlaying ? '暂停' : '播放',
                        color: Colors.white,
                        onTap: _togglePlayPause),
                  _toolbarBtn(
                      icon: v.isLiked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      label: v.isLiked ? '已收藏' : '收藏',
                      color: v.isLiked ? Colors.red : Colors.white,
                      onTap: _toggleLike),
                  _toolbarBtn(
                      icon: v.isDisliked
                          ? Icons.thumb_down
                          : Icons.thumb_down_outlined,
                      label: v.isDisliked ? '已踩' : '踩',
                      color: v.isDisliked ? Colors.blue : Colors.white,
                      onTap: _toggleDislike),
                  if (!_isLandscape)
                    _toolbarBtn(
                        icon: _loopSingle
                            ? Icons.repeat_one
                            : Icons.repeat,
                        label: _loopSingle ? '单视频循环' : '自动下一个',
                        color:
                            _loopSingle ? Colors.amber : Colors.white,
                        onTap: _toggleLoop),
                  if (_isLandscape) ...[
                    _toolbarBtn(
                        icon: _isLandscape
                            ? Icons.stay_current_portrait
                            : Icons.stay_current_landscape,
                        label: _isLandscape ? '竖屏' : '横屏',
                        color: Colors.white,
                        onTap: _toggleOrientation),
                    _toolbarBtn(
                        icon: Icons.camera_alt_outlined,
                        label: '截图',
                        color: Colors.white,
                        onTap: _takeScreenshot),
                  ],
                  _toolbarBtn(
                      icon: Icons.info_outline,
                      label: '信息',
                      color: Colors.white,
                      onTap: _showInfo),
            ]),
          ),
        ),
      );
  }

  Widget _toolbarBtn(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: color, fontSize: 11))
        ]));
  }

  Widget _buildProgress() {
    final totalMs = _dur.inMilliseconds.toDouble();
    final curMs = _pos.inMilliseconds.toDouble();
    final val = totalMs > 0 ? (curMs / totalMs).clamp(0.0, 1.0) : 0.0;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final bottomOffset = _isLandscape ? (bottomPad + 16) : 80.0;
    return Positioned(
        left: 0,
        right: 0,
        bottom: bottomOffset,
        child: Opacity(
          opacity: _uiOpacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Text(_fmtDur(_pos),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24),
                  child: Slider(
                      value: val,
                      onChangeStart: (_) => _onSeekStart(),
                      onChanged: _onSeekChanged,
                      onChangeEnd: _onSeekEnd),
                ),
              ),
              Text(_fmtDur(_dur),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11)),
            ]),
          ),
        ),
      );
  }

  Widget _buildBottomInfo() {
    final v = _playList.videos[_currentIndex];
    return Positioned(
        left: 12,
        bottom: 20,
        right: 12,
        child: Opacity(
          opacity: _uiOpacity,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Builder(builder: (_) {
                        String dn = v.fileName;
                        final di = dn.lastIndexOf('.');
                        if (di > 0) dn = dn.substring(0, di);
                        if (dn.length > 30) dn = '${dn.substring(0, 27)}...';
                        return Text(dn,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis);
                      }),
                      const SizedBox(height: 4),
                      Text(
                          '${_getCurrentSortedIndex() + 1}/${_sortedVideos.length}  |  ${v.formattedSize}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ]),
              ),
              if (!_isLandscape) ...[
                GestureDetector(
                  onTap: _toggleOrientation,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.screen_rotation_outlined,
                        color: Colors.white.withOpacity(0.7), size: 22),
                  ),
                ),
                GestureDetector(
                  onTap: _takeScreenshot,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.camera_alt_outlined,
                        color: Colors.white.withOpacity(0.7), size: 22),
                  ),
                ),
              ],
            ],
          ),
        ));
  }

  // ═══════════════ Floating Switch Button ═══════════════
  Widget _buildFloatingSwitchButton() {
    final sortedIdx = _getCurrentSortedIndex();
    return Positioned(
      left: 16,
      bottom: MediaQuery.of(context).padding.bottom + 110,
      child: GestureDetector(
        onTap: () {}, // absorb taps so they don't pass through
        child: Container(
          width: 130,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: sortedIdx > 0
                      ? () {
                          final prev = _sortedVideos[sortedIdx - 1];
                          final origIdx = _playList.videos.indexWhere(
                              (v) => v.filePath == prev.filePath);
                          if (origIdx >= 0) _playAt(origIdx);
                        }
                      : null,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    child: Icon(Icons.skip_previous_rounded,
                        color: sortedIdx > 0
                            ? Colors.white
                            : Colors.white38,
                        size: 20),
                  ),
                ),
                Text(
                  '${sortedIdx + 1}/${_sortedVideos.length}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
                GestureDetector(
                  onTap: sortedIdx < _sortedVideos.length - 1
                      ? () {
                          final next = _sortedVideos[sortedIdx + 1];
                          final origIdx = _playList.videos.indexWhere(
                              (v) => v.filePath == next.filePath);
                          if (origIdx >= 0) _playAt(origIdx);
                        }
                      : null,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    child: Icon(Icons.skip_next_rounded,
                        color:
                            sortedIdx < _sortedVideos.length - 1
                                ? Colors.white
                                : Colors.white38,
                        size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════ Seek Preview ═══════════════
  Widget _buildSeekPreview() {
    final delta = _seekTarget - _seekStartPosition;
    final deltaSec = delta.inSeconds;
    final icon = deltaSec >= 0
        ? Icons.fast_forward_rounded
        : Icons.fast_rewind_rounded;
    final sign = deltaSec >= 0 ? '+' : '';
    return Positioned(
      top: _screenHeight * 0.3,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Text('${_fmtDur(_seekTarget)}  ($sign${deltaSec}s)',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ═══════════════ Playlist Drawer ═══════════════
  Widget _buildPlaylistScrim() {
    return GestureDetector(
      onTap: _togglePlaylist,
      child: Container(color: Colors.black54),
    );
  }

  Widget _buildPlaylistDrawer() {
    final drawerWidth = MediaQuery.of(context).size.width * 0.75;
    final currentSortedIdx = _getCurrentSortedIndex();
    return Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: drawerWidth,
        child: SlideTransition(
          position: _playlistSlideAnim,
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: SafeArea(
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                      border: Border(
                          bottom:
                              BorderSide(color: Colors.white24))),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                            '播放列表 (${_playList.videos.length})',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold))),
                    IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white),
                        onPressed: _togglePlaylist),
                  ]),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _sortedVideos.length,
                    itemBuilder: (_, idx) {
                      final item = _sortedVideos[idx];
                      final isPlaying = idx == currentSortedIdx;
                      return ListTile(
                        leading: Icon(
                            isPlaying
                                ? Icons.play_arrow
                                : Icons.video_file,
                            color: isPlaying
                                ? Colors.blue
                                : Colors.white70),
                        title: Text(
                          item.fileName,
                          style: TextStyle(
                              color:
                                  isPlaying ? Colors.blue : Colors.white,
                              fontWeight: isPlaying
                                  ? FontWeight.bold
                                  : FontWeight.normal),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isPlaying
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius:
                                        BorderRadius.circular(4)),
                                child: const Text("播放中",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10)))
                            : null,
                        selected: isPlaying,
                        selectedTileColor:
                            Colors.blue.withOpacity(0.1),
                        onTap: () {
                          final originalIdx =
                              _videoIndexMap[idx] ?? idx;
                          _togglePlaylist();
                          _playAt(originalIdx);
                        },
                      );
                    },
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                      color: Color(0x1AFFFFFF),
                      border: Border(
                          top: BorderSide(color: Colors.white24))),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceEvenly,
                      children: [
                        _sortButton(
                            icon: _nameSortAscending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            label:
                                '名称${_nameSortAscending ? "↑" : "↓"}',
                            onPressed: () {
                              setState(() {
                                if (_nameSortAscending) {
                                  _sortedVideos.sort((a, b) =>
                                      _naturalCompare(
                                          b.fileName, a.fileName));
                                  SmartDialog.showToast('名称降序');
                                } else {
                                  _sortedVideos.sort((a, b) =>
                                      _naturalCompare(
                                          a.fileName, b.fileName));
                                  SmartDialog.showToast('名称升序');
                                }
                                _nameSortAscending =
                                    !_nameSortAscending;
                                _updateVideoIndexMap();
                              });
                            }),
                        _sortButton(
                            icon: _sizeSortAscending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            label:
                                '大小${_sizeSortAscending ? "↑" : "↓"}',
                            onPressed: () {
                              setState(() {
                                if (_sizeSortAscending) {
                                  _sortedVideos.sort((a, b) =>
                                      (b.fileSize ?? 0)
                                          .compareTo(a.fileSize ?? 0));
                                  SmartDialog.showToast('大小降序');
                                } else {
                                  _sortedVideos.sort((a, b) =>
                                      (a.fileSize ?? 0)
                                          .compareTo(b.fileSize ?? 0));
                                  SmartDialog.showToast('大小升序');
                                }
                                _sizeSortAscending =
                                    !_sizeSortAscending;
                                _updateVideoIndexMap();
                              });
                            }),
                        _sortButton(
                            icon: Icons.shuffle,
                            label: '随机',
                            onPressed: () {
                              setState(() {
                                final current = _playList.videos[_currentIndex];
                                _sortedVideos.shuffle();
                                final curIdx = _sortedVideos.indexWhere(
                                    (v) => v.filePath == current.filePath);
                                if (curIdx > 0) {
                                  _sortedVideos.removeAt(curIdx);
                                  _sortedVideos.insert(0, current);
                                }
                                _updateVideoIndexMap();
                              });
                              SmartDialog.showToast('已打乱顺序');
                            }),
                      ]),
                ),
              ]),
            ),
          ),
        ));
  }

  Widget _sortButton(
      {required IconData icon,
      required String label,
      required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _VerticalSliderIndicator extends StatelessWidget {
  final IconData icon;
  final double value;
  final Color color;
  const _VerticalSliderIndicator(
      {required this.icon, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text('${(value * 100).toInt()}%',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            width: 24,
            height: 120,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Stack(alignment: Alignment.bottomCenter, children: [
              Container(
                  width: 8,
                  height: 100,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4))),
              Positioned(
                  bottom: 0,
                  child: Container(
                      width: 8,
                      height: 100 * value,
                      decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4)))),
            ]),
          ),
        ]),
      );
}
