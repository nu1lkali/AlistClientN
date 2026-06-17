import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/disliked_video.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/database/table/file_viewing_record.dart';
import 'package:alist/entity/tiktok_play_list_model.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/log_utils.dart' as log;
import 'package:alist/util/stream_size_resolver.dart';
import 'package:alist/util/user_controller.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

class TikTokPlayerPage extends StatefulWidget {
  const TikTokPlayerPage({super.key});
  @override
  State<TikTokPlayerPage> createState() => _TikTokPlayerPageState();
}

class _TikTokPlayerPageState extends State<TikTokPlayerPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final TikTokPlayListModel _playList;
  late PageController _pageController;
  late int _currentIndex;

  final Map<int, VideoPlayerController> _controllers = {};
  final Set<int> _initializingIndexes = {};
  bool _isPlaying = false;
  bool _isLandscape = false;
  bool _loopSingle = false;
  final List<Offset> _doubleTapIcons = [];

  // 预加载1个前后视频，但切换时立即释放所有旧控制器
  static const int _preloadRange = 1;
  static const int _cacheRange = 1;
  bool _hideUI = false;
  bool _manualHideUI = false; // 竖屏下用户手动点击隐藏按钮

  final AlistDatabaseController _database = Get.find();
  final UserController _userController = Get.find();

  final Map<int, bool> _pendingFav = {};
  final Map<int, bool> _pendingDislike = {};

  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  Timer? _progressTimer;
  final GlobalKey _repaintKey = GlobalKey();

  /// 控件透明度
  double _uiOpacity = 1.0;

  Timer? _landscapeHideTimer;
  static const _landscapeAutoHide = Duration(seconds: 2);

  // ══════ Gesture state ══════
  static const _gestureDecideThreshold = 10.0;
  static const _systemGestureBottomMargin = 40.0;
  static const _edgeZoneRatio = 0.15; // 左侧15%为亮度区域
  static const _edgeZoneRatioRight = 0.25; // 右侧25%为音量区域（覆盖控件左侧部分）
  static const _videoSwitchMinDy = 50.0; // 切换视频最小滑动距离
  static const _videoSwitchMinVelocity = 300.0; // 切换视频最小速度 (px/s)
  double _screenWidth = 1;
  double _screenHeight = 1;
  bool _ignoreCurrentGesture = false;

  bool _isSeeking = false;
  double _seekStartX = 0;
  Duration _seekStartPosition = Duration.zero;
  Duration _seekTarget = Duration.zero;
  bool _wasPlayingBeforeSeek = false;

  bool _isVerticalDragging = false;
  double _verticalStartY = 0;
  bool? _isLeftSide;
  double _dragStartBrightness = 0.5;
  double _dragStartVolume = 0.5;
  double _currentBrightness = 0.5;
  double _currentVolume = 0.5;
  bool _showBrightnessIndicator = false;
  bool _showVolumeIndicator = false;
  Timer? _indicatorFadeTimer;

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

  // ══════ Gesture handlers (edge zone vertical + horizontal seek) ══════
  void _initBrightnessAndVolume() async {
    try {
      final saved = SpUtil.getDouble(AlistConstant.strmBrightness);
      if (saved != null && saved >= 0.1 && saved <= 1) {
        _currentBrightness = saved;
      } else {
        try { _currentBrightness = await ScreenBrightness().system; } catch (_) {
          try { _currentBrightness = await ScreenBrightness().current; } catch (_) {
            _currentBrightness = 0.7;
          }
        }
        if (_currentBrightness < 0.1) _currentBrightness = 0.7;
      }
    } catch (_) { _currentBrightness = 0.7; }
    try { ScreenBrightness().setScreenBrightness(_currentBrightness); } catch (_) {}
    try { _currentVolume = await VolumeController().getVolume(); } catch (_) { _currentVolume = 0.5; }
  }

  // —— 边缘区域垂直滑动：亮度/音量 ——
  void _onEdgeVerticalDragStart(DragStartDetails details) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final bottomThreshold = bottomInset > 0 ? bottomInset : _systemGestureBottomMargin;
    if (details.globalPosition.dy > _screenHeight - bottomThreshold) return;
    _isLeftSide = details.globalPosition.dx < _screenWidth / 2;
    if (_isLeftSide!) {
      _dragStartBrightness = _currentBrightness;
    } else {
      _dragStartVolume = _currentVolume;
    }
    _verticalStartY = details.globalPosition.dy;
    _isVerticalDragging = true;
  }

  void _onEdgeVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isVerticalDragging) return;
    final dragDistance = _verticalStartY - details.globalPosition.dy;
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

  void _onEdgeVerticalDragEnd(DragEndDetails details) {
    if (!_isVerticalDragging) return;
    _isVerticalDragging = false;
    _indicatorFadeTimer?.cancel();
    _indicatorFadeTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() { _showBrightnessIndicator = false; _showVolumeIndicator = false; });
    });
  }

  // —— 水平滑动：进度调节 ——
  void _onHorizontalDragStart(DragStartDetails details) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final bottomThreshold = bottomInset > 0 ? bottomInset : _systemGestureBottomMargin;
    if (details.globalPosition.dy > _screenHeight - bottomThreshold) return;
    _seekStartX = details.globalPosition.dx;
    _seekStartPosition = _pos;
    _isSeeking = true;
    _wasPlayingBeforeSeek = _isPlaying;
    _controllers[_currentIndex]?.pause();
    _progressTimer?.cancel();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isSeeking) return;
    final dx = details.globalPosition.dx - _seekStartX;
    final totalMs = _dur.inMilliseconds.toDouble();
    if (totalMs <= 0) return;
    final sensitivityFactor = (totalMs * 0.08) / _screenWidth;
    final deltaMs = (dx * sensitivityFactor).round();
    final targetMs = (_seekStartPosition.inMilliseconds + deltaMs).clamp(0, totalMs.toInt());
    setState(() => _seekTarget = Duration(milliseconds: targetMs));
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isSeeking) return;
    _controllers[_currentIndex]?.seekTo(_seekTarget);
    if (_wasPlayingBeforeSeek) _controllers[_currentIndex]?.play();
    _startTimer();
    setState(() => _isSeeking = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playList = Get.arguments as TikTokPlayListModel;
    _currentIndex = _playList.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _uiOpacity = SpUtil.getDouble(AlistConstant.tiktokUiOpacity, defValue: 1.0) ?? 1.0;

    PaintingBinding.instance.imageCache.maximumSize = 20;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 30 * 1024 * 1024;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    Wakelock.enable();

    _initBrightnessAndVolume();
    _safeInitCtrl(_currentIndex);
    _preloadNearby(_currentIndex);
    _loadStates(_currentIndex);
    _startTimer();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _landscapeHideTimer?.cancel();
    _indicatorFadeTimer?.cancel();
    _flushPending();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _controllers.values) {
      try { c.dispose(); } catch (_) {}
    }
    _controllers.clear();
    _clearImageCache();
    try { _pageController.dispose(); } catch (_) {}
    try { _indicatorScrollCtrl.dispose(); } catch (_) {}
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Wakelock.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _safePause();
      _releaseNonCurrentControllers();
      _clearImageCache();
    } else if (state == AppLifecycleState.resumed) {
      _preloadNearby(_currentIndex);
      _safePlay();
    }
  }

  @override
  void didHaveMemoryPressure() {
    _safePause();
    _releaseNonCurrentControllers();
    _clearImageCache();
  }

  void _releaseNonCurrentControllers() {
    final rm = _controllers.keys.where((k) => k != _currentIndex).toList();
    for (final k in rm) {
      try { _controllers[k]?.dispose(); } catch (_) {}
      _controllers.remove(k);
    }
    _initializingIndexes.clear();
  }

  // ═══════════════ DB Batch Flush ═══════════════
  Future<void> _flushPending() async {
    if (_pendingFav.isEmpty && _pendingDislike.isEmpty) return;
    try {
      final u = _userController.user.value;
      for (final e in _pendingFav.entries) {
        if (e.key >= _playList.videos.length) continue;
        final v = _playList.videos[e.key];
        if (e.value) {
          if (await _database.favoriteDao.findByPath(u.serverUrl, u.username, v.filePath) == null) {
            await _database.dislikedVideoDao.deleteByPath(u.serverUrl, u.username, v.filePath);
            await _database.favoriteDao.insertRecord(Favorite(
              isDir: false, serverUrl: u.serverUrl, userId: u.username,
              remotePath: v.filePath, name: v.fileName, path: v.filePath,
              size: v.fileSize ?? 0, sign: v.sign, thumb: v.thumb,
              modified: v.modifiedMilliseconds ?? 0, provider: v.provider ?? '',
              createTime: DateTime.now().millisecondsSinceEpoch,
            ));
          }
        } else {
          await _database.favoriteDao.deleteByPath(u.serverUrl, u.username, v.filePath);
        }
      }
      for (final e in _pendingDislike.entries) {
        if (e.key >= _playList.videos.length) continue;
        final v = _playList.videos[e.key];
        if (e.value) {
          if (await _database.dislikedVideoDao.findByPath(u.serverUrl, u.username, v.filePath) == null) {
            await _database.favoriteDao.deleteByPath(u.serverUrl, u.username, v.filePath);
            await _database.dislikedVideoDao.insertRecord(DislikedVideo(
              serverUrl: u.serverUrl, userId: u.username,
              remotePath: v.filePath, name: v.fileName, path: v.filePath,
              size: v.fileSize ?? 0, sign: v.sign, thumb: v.thumb,
              modified: v.modifiedMilliseconds ?? 0, provider: v.provider ?? '',
              createTime: DateTime.now().millisecondsSinceEpoch,
            ));
          }
        } else {
          await _database.dislikedVideoDao.deleteByPath(u.serverUrl, u.username, v.filePath);
        }
      }
      _pendingFav.clear();
      _pendingDislike.clear();
    } catch (e) { log.Log.e('flush: $e'); }
  }

  // ═══════════════ Timer ═══════════════
  bool _completing = false;
  void _startTimer() {
    _progressTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      try {
        final c = _controllers[_currentIndex];
        if (c != null && c.value.isInitialized) {
          // 滑动调整进度期间，不从播放器读取位置，避免覆盖预览进度导致闪烁
            setState(() { _pos = c.value.position; _dur = c.value.duration; });
          if (c.value.duration > Duration.zero &&
              c.value.position >= c.value.duration - const Duration(milliseconds: 500) &&
              !_completing) {
            _completing = true;
            if (_loopSingle) {
              c.seekTo(Duration.zero).then((_) { c.play(); _completing = false; });
            } else if (!_isLandscape && _currentIndex < _playList.videos.length - 1) {
              _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut)
                  .then((_) => _completing = false);
            } else {
              _safePause();
              _completing = false;
            }
          }
        }
      } catch (_) {}
    });
  }

  // ═══════════════ State Query ═══════════════
  Future<void> _loadStates(int idx) async {
    if (idx < 0 || idx >= _playList.videos.length || !mounted) return;
    try {
      final v = _playList.videos[idx];
      final u = _userController.user.value;
      v.isLiked = (await _database.favoriteDao.findByPath(u.serverUrl, u.username, v.filePath)) != null;
      v.isDisliked = (await _database.dislikedVideoDao.findByPath(u.serverUrl, u.username, v.filePath)) != null;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _recordViewing(int idx) async {
    if (!_playList.recordHistory) return;
    if (idx < 0 || idx >= _playList.videos.length) return;
    try {
      final v = _playList.videos[idx];
      final u = _userController.user.value;
      await _database.fileViewingRecordDao.deleteByPath(u.serverUrl, u.username, v.filePath);
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

  // ═══════════════ Controller Management ═══════════════
  Future<void> _safeInitCtrl(int idx) async {
    if (idx < 0 || idx >= _playList.videos.length) return;
    if (_controllers.containsKey(idx) || _initializingIndexes.contains(idx)) return;
    if (_initializingIndexes.length >= 2) return;
    _initializingIndexes.add(idx);
    VideoPlayerController? ctrl;
    try {
      final v = _playList.videos[idx];
      if (v.videoUrl == null || v.videoUrl!.isEmpty) {
        final url = await FileUtils.makeFileLink(v.filePath, v.sign);
        if (url == null || url.isEmpty) { _initializingIndexes.remove(idx); return; }
        v.videoUrl = url;
      }
      if (!mounted) { _initializingIndexes.remove(idx); return; }
      ctrl = VideoPlayerController.networkUrl(
        Uri.parse(v.videoUrl!),
        httpHeaders: v.provider == 'BaiduNetdisk' ? {'User-Agent': 'pan.baidu.com'} : {},
      );
      await ctrl.initialize();
      if (!mounted || !_initializingIndexes.contains(idx)) {
        try { ctrl.dispose(); } catch (_) {}
        _initializingIndexes.remove(idx);
        return;
      }
      if ((idx - _currentIndex).abs() > _cacheRange) {
        try { ctrl.dispose(); } catch (_) {}
        _initializingIndexes.remove(idx);
        return;
      }
      ctrl.setLooping(_loopSingle);
      _controllers[idx] = ctrl;
      _initializingIndexes.remove(idx);
      if (idx == _currentIndex) { ctrl.play(); _isPlaying = true; _recordViewing(idx); }
      if (mounted) setState(() {});

      // 仅当前播放视频获取大小，预加载视频延迟到切换时再获取（减少CDN请求）
      if (idx == _currentIndex && (v.fileSize == null || v.fileSize! <= 0)) {
        StreamSizeResolver.resolveAsync(v.videoUrl!, (size) {
          v.fileSize = size;
          if (idx == _currentIndex) _recordViewing(idx);
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      log.Log.e('initCtrl[$idx]: $e');
      try { ctrl?.dispose(); } catch (_) {}
      _initializingIndexes.remove(idx);
    }
  }

  void _preloadNearby(int idx) {
    for (int i = idx - _preloadRange; i <= idx + _preloadRange; i++) {
      if (i >= 0 && i < _playList.videos.length) _safeInitCtrl(i);
    }
  }

  void _disposeOutOfRange(int idx) {
    final rm = _controllers.keys.where((k) => (k - idx).abs() > _cacheRange).toList();
    for (final k in rm) { try { _controllers[k]?.dispose(); } catch (_) {} _controllers.remove(k); }
    _initializingIndexes.removeWhere((k) => (k - idx).abs() > _cacheRange);
    if (rm.isNotEmpty) _clearImageCache();
  }

  /// 释放所有控制器（切视频时调用，彻底释放内存防OOM）
  void _disposeAll() {
    for (final c in _controllers.values) {
      try { c.dispose(); } catch (_) {}
    }
    _controllers.clear();
    _initializingIndexes.clear();
    _clearImageCache();
  }

  void _clearImageCache() {
    try { PaintingBinding.instance.imageCache.clear(); } catch (_) {}
    try { PaintingBinding.instance.imageCache.clearLiveImages(); } catch (_) {}
  }

  void _safePlay() {
    try { final c = _controllers[_currentIndex]; if (c != null && c.value.isInitialized) { c.play(); _isPlaying = true; if (mounted) setState(() {}); } } catch (_) {}
  }

  void _safePause() {
    try { final c = _controllers[_currentIndex]; if (c != null && c.value.isInitialized) { c.pause(); _isPlaying = false; if (mounted) setState(() {}); } } catch (_) {}
  }

  // ═══════════════ Gesture: Single Tap (immediate) + Double Tap ═══════════════
  void _onDoubleTap(TapDownDetails d) {
    if (mounted) setState(() => _doubleTapIcons.add(d.globalPosition));
    final v = _playList.videos[_currentIndex];
    v.isLiked = !v.isLiked;
    if (v.isLiked && v.isDisliked) v.isDisliked = false;
    _pendingFav[_currentIndex] = v.isLiked;
    if (v.isLiked) _pendingDislike[_currentIndex] = false;
    if (mounted) setState(() {});
  }

  void _togglePlayPause() {
    try {
      final c = _controllers[_currentIndex];
      if (c == null || !c.value.isInitialized) return;
      if (_isPlaying) {
        c.pause(); _isPlaying = false;
        _cancelLandscapeAutoHide();
      } else {
        c.play(); _isPlaying = true;
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
    _isLandscape = !_isLandscape;
    if (!_isLandscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      _cancelLandscapeAutoHide();
      _hideUI = false;
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      _hideUI = false;
      _startLandscapeAutoHide();
    }
    if (mounted) setState(() {});
  }

  void _toggleLoop() {
    _loopSingle = !_loopSingle;
    try { _controllers[_currentIndex]?.setLooping(_loopSingle); } catch (_) {}
    if (mounted) setState(() {});
    SmartDialog.showToast(_loopSingle ? '单视频循环' : '自动播放下一个');

  }

  void _toggleLike() {
    final v = _playList.videos[_currentIndex];
    v.isLiked = !v.isLiked;
    if (v.isLiked && v.isDisliked) v.isDisliked = false;
    _pendingFav[_currentIndex] = v.isLiked;
    if (v.isLiked) _pendingDislike[_currentIndex] = false;
    if (mounted) setState(() {});
  }

  void _toggleDislike() {
    final v = _playList.videos[_currentIndex];
    v.isDisliked = !v.isDisliked;
    if (v.isDisliked && v.isLiked) v.isLiked = false;
    _pendingDislike[_currentIndex] = v.isDisliked;
    if (v.isDisliked) _pendingFav[_currentIndex] = false;
    if (mounted) setState(() {});
  }

  // ═══════════════ Seek ═══════════════
  void _onSeekStart() { _progressTimer?.cancel(); }
  void _onSeekChanged(double val) {
    if (_dur.inMilliseconds <= 0) return;
    setState(() => _pos = Duration(milliseconds: (val * _dur.inMilliseconds).round()));
  }
  void _onSeekEnd(double val) {
    try {
      if (_dur.inMilliseconds > 0) {
        _controllers[_currentIndex]?.seekTo(Duration(milliseconds: (val * _dur.inMilliseconds).round()));
      }
    } catch (_) {}
    _startTimer();
  }

  // ═══════════════ Screenshot ═══════════════
  Future<void> _takeScreenshot() async {
    try {
      SmartDialog.showLoading(msg: '截图中...');
      // 等待一帧确保视频画面已合成
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) { SmartDialog.dismiss(); return; }
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) { SmartDialog.dismiss(); SmartDialog.showToast('截图失败'); return; }

      // 计算pixelRatio，使截图分辨率为视频原始分辨率
      // 原理：pixelRatio = 视频原始宽度 / 控件逻辑宽度
      // 例如：视频1280x720，控件逻辑宽度384 → pixelRatio≈3.33 → 截图1280x720
      double pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ctrl = _controllers[_currentIndex];
      if (ctrl != null && ctrl.value.isInitialized) {
        final videoSize = ctrl.value.size;
        final widgetWidth = boundary.size.width;
        if (widgetWidth > 0 && videoSize.width > 0) {
          pixelRatio = videoSize.width / widgetWidth;
        }
      }

      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) { SmartDialog.dismiss(); SmartDialog.showToast('截图失败'); return; }
      final bytes = byteData.buffer.asUint8List();
      if (bytes.length < 100) { SmartDialog.dismiss(); SmartDialog.showToast('截图失败'); return; }
      // 先写临时文件，再用 saveFile 保存到相册（与原生播放器行为一致）
      final tempDir = await getTemporaryDirectory();
      final fileName = "alist_${DateTime.now().millisecondsSinceEpoch}.png";
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);
      final result = await ImageGallerySaver.saveFile(tempFile.path, name: fileName);
      SmartDialog.dismiss();
      SmartDialog.showToast(result['isSuccess'] == true ? '截图已保存到相册' : '保存失败');
    } catch (e) { SmartDialog.dismiss(); SmartDialog.showToast('截图失败: $e'); }
  }

  // ═══════════════ Video Info ═══════════════
  void _showInfo() {
    final v = _playList.videos[_currentIndex];
    showModalBottomSheet(
      context: context, backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('视频信息', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _row('文件名', v.fileName), _row('文件大小', v.formattedSize), _row('文件路径', v.filePath),
            _row('修改时间', v.formattedModified), _row('Provider', v.provider ?? '未知'),
            _row('文件签名', v.sign ?? '无'), _row('播放位置', '${_currentIndex + 1} / ${_playList.videos.length}'),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Widget _row(String l, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(l, style: const TextStyle(color: Colors.white54, fontSize: 13))),
      Expanded(child: Text(val, style: const TextStyle(color: Colors.white, fontSize: 13))),
    ]),
  );

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
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
        _buildGestureLayer(),
        _buildPauseIcon(),
        if (!(_hideUI && _isLandscape)) _buildTopBar(),
        if (!_hideUI) _buildToolBar(),
        if (!_hideUI) _buildProgress(),
        if (!_hideUI && !_isLandscape) _buildBottomInfo(),
        if (!_hideUI && _isLandscape) _buildLandscapeCenterControls(),
        if (!_hideUI && _isLandscape && _playList.videos.length > 1)
          _buildLandscapeFloatingSwitchButton(),
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
        ..._buildHearts(),
        if (!_hideUI) _buildIndicator(),
      ]),
    );
  }

  // 竖屏中间区域垂直滑动：翻页
  double _pageSwitchStartY = 0;
  double _pageSwitchDeltaY = 0;

  void _onPageSwitchStart(DragStartDetails details) {
    _pageSwitchStartY = details.globalPosition.dy;
    _pageSwitchDeltaY = 0;
  }

  void _onPageSwitchUpdate(DragUpdateDetails details) {
    _pageSwitchDeltaY = details.globalPosition.dy - _pageSwitchStartY;
  }

  void _onPageSwitchEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final dy = _pageSwitchDeltaY;
    // 向上滑（负dy）→ 下一个，向下滑（正dy）→ 上一个
    if (dy.abs() > _videoSwitchMinDy || velocity.abs() > _videoSwitchMinVelocity) {
      if (dy < 0 && _currentIndex < _playList.videos.length - 1) {
        _pageController.animateToPage(_currentIndex + 1,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      } else if (dy > 0 && _currentIndex > 0) {
        _pageController.animateToPage(_currentIndex - 1,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    }
  }

  Widget _buildGestureLayer() {
    final leftEdge = _screenWidth * _edgeZoneRatio;
    final rightEdge = _screenWidth * (1 - _edgeZoneRatioRight);
    return RawGestureDetector(
      gestures: {
        _EdgeVerticalDragRecognizer: GestureRecognizerFactoryWithHandlers<_EdgeVerticalDragRecognizer>(
          () => _EdgeVerticalDragRecognizer(
            isEdgeZone: (pos) => _isLandscape
                ? true
                : (pos.dx < leftEdge || pos.dx > rightEdge),
          ),
          (r) {
            r.onStart = _onEdgeVerticalDragStart;
            r.onUpdate = _onEdgeVerticalDragUpdate;
            r.onEnd = _onEdgeVerticalDragEnd;
          },
        ),
        _MiddleVerticalDragRecognizer: GestureRecognizerFactoryWithHandlers<_MiddleVerticalDragRecognizer>(
          () => _MiddleVerticalDragRecognizer(
            isMiddleZone: (pos) => !_isLandscape &&
                pos.dx >= leftEdge && pos.dx <= rightEdge,
          ),
          (r) {
            r.onStart = _onPageSwitchStart;
            r.onUpdate = _onPageSwitchUpdate;
            r.onEnd = _onPageSwitchEnd;
          },
        ),
        HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          () => HorizontalDragGestureRecognizer(),
          (r) {
            r.onStart = _onHorizontalDragStart;
            r.onUpdate = _onHorizontalDragUpdate;
            r.onEnd = _onHorizontalDragEnd;
          },
        ),
      },
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onScreenTap,
        child: _buildPageView(),
      ),
    );
  }

  void _onPageChanged(int idx) {
    _flushPending();
    try { _controllers[_currentIndex]?.pause(); } catch (_) {}
    _currentIndex = idx;
    _isPlaying = false;
    _pos = Duration.zero;
    _dur = Duration.zero;
    _disposeOutOfRange(idx);
    if (mounted) setState(() {});
    final c = _controllers[idx];
    if (c != null && c.value.isInitialized) {
      c.play();
      _isPlaying = true;
      _recordViewing(idx);
      if (mounted) setState(() {});
      final v = _playList.videos[idx];
      if ((v.fileSize == null || v.fileSize! <= 0) && v.videoUrl != null) {
        StreamSizeResolver.resolveAsync(v.videoUrl!, (size) {
          v.fileSize = size;
          if (idx == _currentIndex) _recordViewing(idx);
          if (mounted) setState(() {});
        });
      }
    } else {
      _safeInitCtrl(idx);
    }
    _preloadNearby(idx);
    _loadStates(idx);
  }

  Widget _buildVideoItem(BuildContext context, int idx) {
    final c = _controllers[idx];
    if (c != null && c.value.isInitialized) {
      final video = RepaintBoundary(
        key: idx == _currentIndex ? _repaintKey : null,
        child: VideoPlayer(c),
      );
      if (_isLandscape) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: video),
          ),
        );
      }
      return Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: video));
    }
    return const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2));
  }

  Widget _buildPageView() {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _playList.videos.length,
      onPageChanged: _onPageChanged,
      itemBuilder: _buildVideoItem,
    );
  }

  Widget _buildTopBar() {
    return Positioned(top: 0, left: 0, right: 0, child: SafeArea(
      child: Opacity(opacity: _uiOpacity, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 24),
            onPressed: () => Navigator.pop(context)),
          const Spacer(),
          Text('${_currentIndex + 1}/${_playList.videos.length}',
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const Spacer(),
          if (!_isLandscape)
            IconButton(
              icon: Icon(_hideUI ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white, size: 22),
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
      )),
    ));
  }

  Widget _buildToolBar() {
    final v = _playList.videos[_currentIndex];
    final screenH = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final bottomOffset = _isLandscape ? (bottomPad + 70) : 160.0;
    final maxH = screenH - topPad - bottomOffset - 20;
    return Positioned(right: 12, bottom: bottomOffset,
      child: Opacity(opacity: _uiOpacity, child: SizedBox(
        height: maxH.clamp(0.0, 500.0),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          if (_isLandscape)
            _btn(icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              label: _isPlaying ? '暂停' : '播放', color: Colors.white, onTap: _togglePlayPause),
          _btn(icon: v.isLiked ? Icons.favorite : Icons.favorite_border,
            label: v.isLiked ? '已收藏' : '收藏', color: v.isLiked ? Colors.red : Colors.white, onTap: _toggleLike),
          _btn(icon: v.isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
            label: v.isDisliked ? '已踩' : '踩', color: v.isDisliked ? Colors.blue : Colors.white, onTap: _toggleDislike),
          if (!_isLandscape)
            _btn(icon: _loopSingle ? Icons.repeat_one : Icons.repeat,
              label: _loopSingle ? '单视频循环' : '自动下一个', color: _loopSingle ? Colors.amber : Colors.white, onTap: _toggleLoop),
          if (_isLandscape) ...[
            _btn(icon: _isLandscape ? Icons.stay_current_portrait : Icons.stay_current_landscape,
              label: _isLandscape ? '竖屏' : '横屏', color: Colors.white, onTap: _toggleOrientation),
            _btn(icon: Icons.camera_alt_outlined, label: '截图', color: Colors.white, onTap: _takeScreenshot),
          ],
          _btn(icon: Icons.info_outline, label: '信息', color: Colors.white, onTap: _showInfo),
        ]),
      )),
    );
  }

  Widget _btn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(onTap: onTap,
      child: Column(children: [Icon(icon, color: color, size: 32), const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11))]));
  }

  Widget _buildProgress() {
    final totalMs = _dur.inMilliseconds.toDouble();
    final curMs = _pos.inMilliseconds.toDouble();
    final val = totalMs > 0 ? (curMs / totalMs).clamp(0.0, 1.0) : 0.0;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final bottomOffset = _isLandscape ? (bottomPad + 16) : 80.0;
    return Positioned(left: 0, right: 0, bottom: bottomOffset,
      child: Opacity(opacity: _uiOpacity, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Text(_fmtDur(_pos), style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Expanded(child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white, inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white, overlayColor: Colors.white24),
            child: Slider(value: val, onChangeStart: (_) => _onSeekStart(),
              onChanged: _onSeekChanged, onChangeEnd: _onSeekEnd),
          )),
          Text(_fmtDur(_dur), style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      )),
    );
  }

  Widget _buildBottomInfo() {
    final v = _playList.videos[_currentIndex];
    return Positioned(left: 12, bottom: 20, right: 12,
      child: Opacity(opacity: _uiOpacity, child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Builder(builder: (_) {
                String dn = v.fileName;
                final di = dn.lastIndexOf('.');
                if (di > 0) dn = dn.substring(0, di);
                if (dn.length > 30) dn = '${dn.substring(0, 27)}...';
                return Text(dn, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis);
              }),
              const SizedBox(height: 4),
              Text('${v.formattedSize}  |  ${v.filePath}',
                style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
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
      )),
    );
  }

  Widget _buildSeekPreview() {
    final delta = _seekTarget - _seekStartPosition;
    final deltaSec = delta.inSeconds;
    final icon = deltaSec >= 0
        ? Icons.fast_forward_rounded
        : Icons.fast_rewind_rounded;
    final sign = deltaSec >= 0 ? '+' : '';
    return Positioned(
      top: _screenHeight * 0.3,
      left: 0, right: 0,
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
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _buildLandscapeCenterControls() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _centerCtrlBtn(
            icon: Icons.replay_10_rounded,
            onTap: () {
              final target = _pos - const Duration(seconds: 10);
              _controllers[_currentIndex]?.seekTo(target < Duration.zero ? Duration.zero : target);
            },
          ),
          const SizedBox(width: 48),
          GestureDetector(
            onTap: _togglePlayPause,
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white.withOpacity(0.85),
              size: 64,
            ),
          ),
          const SizedBox(width: 48),
          _centerCtrlBtn(
            icon: Icons.forward_10_rounded,
            onTap: () {
              final target = _pos + const Duration(seconds: 10);
              final max = _dur;
              _controllers[_currentIndex]?.seekTo(target > max ? max : target);
            },
          ),
        ],
      ),
    );
  }

  Widget _centerCtrlBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: Colors.white.withOpacity(0.85), size: 48),
    );
  }

  Widget _buildLandscapeFloatingSwitchButton() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 16,
      bottom: bottomPad + 60,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 110,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: _currentIndex > 0
                      ? () => _pageController.animateToPage(_currentIndex - 1,
                          duration: const Duration(milliseconds: 300), curve: Curves.easeOut)
                      : null,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    child: Icon(Icons.skip_previous_rounded,
                        color: _currentIndex > 0 ? Colors.white : Colors.white38,
                        size: 16),
                  ),
                ),
                Text(
                  '${_currentIndex + 1}/${_playList.videos.length}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
                GestureDetector(
                  onTap: _currentIndex < _playList.videos.length - 1
                      ? () => _pageController.animateToPage(_currentIndex + 1,
                          duration: const Duration(milliseconds: 300), curve: Curves.easeOut)
                      : null,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    child: Icon(Icons.skip_next_rounded,
                        color: _currentIndex < _playList.videos.length - 1
                            ? Colors.white
                            : Colors.white38,
                        size: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPauseIcon() {
    if (_isPlaying || _isLandscape) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Center(child: Container(width: 72, height: 72,
        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(36)),
        child: const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 44))),
    );
  }

  List<Widget> _buildHearts() => _doubleTapIcons.map((p) =>
    _HeartAnim(key: Key(p.toString()), position: p, onDone: () => _doubleTapIcons.remove(p))).toList();

  // 修复：页码指示器支持任意数量视频，用比例显示
  final ScrollController _indicatorScrollCtrl = ScrollController();

  Widget _buildIndicator() {
    final total = _playList.videos.length;
    if (total <= 1) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final bottomPad = mq.padding.bottom;
    final safeH = mq.size.height - topPad - bottomPad;
    final rightPad = _isLandscape ? 52.0 : 8.0;
    final dotH = total <= 30 ? 8.0 : (total <= 80 ? 5.0 : 3.0);
    final activeH = dotH * 2;
    final vMargin = 1.0;
    final maxH = safeH * 0.7;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_indicatorScrollCtrl.hasClients) return;
      final itemH = dotH + vMargin * 2;
      final target = (_currentIndex * itemH - maxH / 2 + itemH / 2)
          .clamp(0.0, _indicatorScrollCtrl.position.maxScrollExtent);
      _indicatorScrollCtrl.animateTo(target,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });

    return Positioned(
      right: rightPad,
      top: topPad + (safeH - maxH) / 2,
      child: SizedBox(
        height: maxH,
        width: 12,
        child: ListView.builder(
          controller: _indicatorScrollCtrl,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: total,
          itemBuilder: (_, i) {
            final active = i == _currentIndex;
            return Container(
              width: 3,
              height: active ? activeH : dotH,
              margin: EdgeInsets.symmetric(vertical: vMargin),
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.white30,
                borderRadius: BorderRadius.circular(2)),
            );
          },
        ),
      ),
    );
  }
}

class _HeartAnim extends StatefulWidget {
  final Offset position;
  final VoidCallback onDone;
  const _HeartAnim({super.key, required this.position, required this.onDone});
  @override
  State<_HeartAnim> createState() => _HeartAnimState();
}

class _HeartAnimState extends State<_HeartAnim> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  double _rot = pi / 10 * (2 * Random().nextDouble() - 1);
  // 参照原版：appearDuration=0.1, dismissDuration=0.6（60%时开始消失，800ms总时长）
  static const double _appearEnd = 0.1;
  static const double _dismissStart = 0.6;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _ac.addListener(() => setState(() {}));
    _ac.forward().then((_) => widget.onDone());
  }
  @override
  void dispose() { _ac.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext c) {
    final v = _ac.value;
    // 透明度：快速出现 → 保持 → 较快消失
    final op = v < _appearEnd
        ? 0.9 / _appearEnd * v
        : (v < _dismissStart
            ? 0.9
            : (0.9 - (v - _dismissStart) / (1.0 - _dismissStart)).clamp(0.0, 1.0));
    // 缩放：弹出 → 稳定 → 轻微放大淡出
    final sc = v <= 0.4
        ? 0.6 + v / 0.4 * 0.5
        : (v <= _dismissStart ? 1.1 : 1 + (v - _dismissStart) / (1.0 - _dismissStart) * 0.4);
    const sz = 120.0;
    return Positioned(left: widget.position.dx - sz / 2, top: widget.position.dy - sz,
      child: Transform.rotate(angle: _rot, child: Opacity(opacity: op,
        child: Transform.scale(alignment: Alignment.bottomCenter, scale: sc,
          child: ShaderMask(blendMode: BlendMode.srcATop,
            shaderCallback: (b) => const RadialGradient(center: Alignment(0, 0),
              colors: [Color(0xffEF6F6F), Color(0xffF03E3E)]).createShader(b),
            child: const Icon(Icons.favorite, size: sz, color: Colors.white))))));
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
              Positioned(
                  bottom: 6,
                  child: Container(
                      width: 8,
                      height: 100,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4)))),
              Positioned(
                  bottom: 6,
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

/// 边缘区域垂直滑动识别器（左15%/右15% → 亮度/音量）
class _EdgeVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  final bool Function(Offset position) isEdgeZone;
  _EdgeVerticalDragRecognizer({required this.isEdgeZone});

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (event is PointerDownEvent && !isEdgeZone(event.position)) return false;
    return super.isPointerAllowed(event);
  }
}

/// 中间区域垂直滑动识别器（中间70% → 翻页）
class _MiddleVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  final bool Function(Offset position) isMiddleZone;
  _MiddleVerticalDragRecognizer({required this.isMiddleZone});

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (event is PointerDownEvent && !isMiddleZone(event.position)) return false;
    return super.isPointerAllowed(event);
  }
}