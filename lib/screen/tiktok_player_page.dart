import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/disliked_video.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/util/favorite_helper.dart';
import 'package:alist/database/table/file_viewing_record.dart';
import 'package:alist/entity/emby_config.dart';
import 'package:alist/entity/tiktok_play_list_model.dart';
import 'package:alist/net/emby_api.dart';
import 'package:alist/util/emby_config_manager.dart';
import 'package:alist/util/file_title.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/log_utils.dart' as log;
import 'package:alist/util/subtitle/subtitle.dart';
import 'package:alist/util/video_player_util.dart';
import 'package:alist/widget/network_speed_indicator.dart';
import 'package:alist/widget/subtitle_view.dart';
import 'package:alist/widget/tiktok_video_info_sheet.dart';
import 'package:alist/util/stream_size_resolver.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/video_fit_mode.dart';
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
  /// 实时下载速度徽标总开关（关闭后所有采样与 UI 都不再构建）
  static const bool _enableNetworkSpeed = true;
  late final TikTokPlayListModel _playList;
  late PageController _pageController;
  late int _currentIndex;

  final Map<int, VideoPlayerController> _controllers = {};
  final Set<int> _initializingIndexes = {};
  bool _isPlaying = false;
  bool _isLandscape = false;
  /// 横屏全屏的画面适配方式（在 [build] 中同步自 SpUtil）
  LandscapeFitMode _fitMode = LandscapeFitMode.auto;
  // 循环模式: 0=自动下一个, 1=播完即停止, 2=单视频循环
  int _loopMode = 0;
  final List<Offset> _doubleTapIcons = [];

  // 预加载1个前后视频，但切换时立即释放所有旧控制器
  static const int _preloadRange = 1;
  static const int _cacheRange = 1;
  bool _hideUI = false;
  bool _manualHideUI = false; // 竖屏下用户手动点击隐藏按钮
  bool _hideHintShown = false; // 「怎么把控件找回来」的提示只弹一次

  final AlistDatabaseController _database = Get.find();
  final UserController _userController = Get.find();

  final Map<int, bool> _pendingFav = {};
  final Map<int, bool> _pendingDislike = {};

  // ── Emby 收藏 / 不喜欢（fromEmby 入口）：进入时一次性拉取，O(1) 查询 ──
  final Set<String> _embyFavoriteIds = {};
  final Set<String> _embyDislikeIds = {}; // 本地“不喜欢”标记的 Emby itemId
  bool _embyFavLoaded = false;
  final Set<int> _embyFavBusy = {}; // 正在请求的索引（点击防抖，收藏/踩共用）
  EmbyServerConfig? _embyServer;

  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  late final SubtitleController _subtitleController;
  Timer? _progressTimer;
  final GlobalKey _repaintKey = GlobalKey();

  /// 控件透明度
  double _uiOpacity = 1.0;

  Timer? _landscapeHideTimer;
  static const _landscapeAutoHide = Duration(seconds: 2);

  /// 竖屏中间那一行（−10s / 播放 / +10s）的「醒着」标记。
  ///
  /// 它正好压在画面正中央的主视觉上，常驻会挡主体，所以改成**按需浮出、
  /// 2 秒自动淡出**（见 [_wakeCenterRow]）。只有这行是自动消失的，
  /// 顶栏 / 右侧工具栏 / 底部进度条都在边缘，保持原来的显隐规则不动。
  bool _centerRowAwake = false;
  /// 进页面后的**一次性引导**：第一次起播露 2 秒让人知道有 ±10s 这两个键，
  /// 之后切页不再露——已经知道了就没必要每次都挡一下。
  bool _centerRowIntroShown = false;
  Timer? _centerRowFadeTimer;
  static const _centerRowLinger = Duration(seconds: 2);
  static const _centerRowFade = Duration(milliseconds: 260);

  /// 实时下载速度（字节/秒）：**活跃下载段**的速率，见 [_calcNetworkSpeed]。
  double _networkSpeed = 0;
  /// 真正显示出来的速度：在 [_networkSpeed] 之上再加一层死区，末位数字才不乱跳。
  double _displaySpeed = 0;
  /// 当前「活跃下载段」的起点字节数 / 起点时刻；null 表示现在没有在下载
  double _segStartBytes = 0;
  DateTime? _segStartAt;
  /// 最近一次检测到缓冲增长的时刻
  DateTime? _lastGrowAt;
  /// 最近一次结算出速度的时刻，用来判断读数是否已经过期
  DateTime? _lastSpeedUpdateAt;
  /// 上一次的累计字节数，用来识别缓冲回退（seek / 换源）
  double _lastCumBytes = 0;
  Duration _lastBufferedEnd = Duration.zero;
  DateTime _lastSpeedSample = DateTime.now();
  DateTime _loadStartTime = DateTime.now();
  /// 文件大小未知时的假设码率 ≈ 5 Mbps，用于估算「缓冲秒数 → 字节数」
  static const double _fallbackBitrateBps = 625000.0;
  /// 速度上限（125 MB/s）：超过即视为跨视频 / 跨 seek 的异常跳变，直接丢弃
  static const double _maxSpeedBps = 125 * 1024 * 1024.0;
  /// 静默超过这么久，就认为「这一段下载结束了」，可以结算速率
  static const int _segSilentMs = 700;
  /// 短于这个时长的段只含一两个采样点（可能刚好跨越了停止时刻），不采信
  static const int _segMinMs = 200;
  /// 连续下载超过这么久就先结算一次，免得起播冲刺期要等到停下来才出数
  static const int _segMaxMs = 1500;
  /// 超过这么久没有新的下载段：判定缓冲已满 / 停止下载 → 归零，徽标消失
  static const int _speedStaleMs = 3000;
  /// 显示死区：新值和当前显示值相差不到 8% 就不刷新数字
  static const double _speedDeadband = 0.08;
  /// 新段速率的融合权重（段速率本身已经是平均值，不用太保守）
  static const double _speedEmaAlpha = 0.45;

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

  // —— 水平滑动：进度调节 / 边缘返回 ——
  // 屏幕最左/右边缘热区内的横滑优先当作“返回上一级”（兼容系统侧滑返回习惯），
  // 其余位置横滑才是拖动进度条。
  static const double _edgeBackZone = 42.0; // 左右边缘热区宽度（逻辑像素）
  static const double _edgeBackTrigger = 64.0; // 触发返回所需的最小向内位移
  /// 横拖的「精调区」占屏宽比例：这一小段行程只走 ±10 秒，方便对准台词/画面
  static const double _fineSeekZoneRatio = 0.2;
  /// 精调区对应的毫秒数
  static const int _fineSeekRangeMs = 10000;
  double? _horizontalStartDx;
  bool _edgeBackCandidate = false;

  void _onHorizontalDragStart(DragStartDetails details) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final bottomThreshold = bottomInset > 0 ? bottomInset : _systemGestureBottomMargin;
    if (details.globalPosition.dy > _screenHeight - bottomThreshold) return;
    _horizontalStartDx = details.globalPosition.dx;
    final w = _screenWidth;
    _edgeBackCandidate = (_horizontalStartDx! <= _edgeBackZone) ||
        (_horizontalStartDx! >= w - _edgeBackZone);
    if (_edgeBackCandidate) return; // 让给“返回”手势
    _seekStartX = details.globalPosition.dx;
    _seekStartPosition = _pos;
    _isSeeking = true;
    _wasPlayingBeforeSeek = _isPlaying;
    _controllers[_currentIndex]?.pause();
    _progressTimer?.cancel();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_edgeBackCandidate) {
      final dx = details.globalPosition.dx - _horizontalStartDx!;
      final fromLeft = _horizontalStartDx! <= _edgeBackZone;
      // 从左侧边缘向右滑 / 从右侧边缘向左滑 => 返回上一级
      final inwardReached = fromLeft ? dx > _edgeBackTrigger : -dx > _edgeBackTrigger;
      if (inwardReached) {
        _handleEdgeBack();
      }
      return;
    }
    if (!_isSeeking) return;
    final dx = details.globalPosition.dx - _seekStartX;
    final totalMs = _dur.inMilliseconds.toDouble();
    if (totalMs <= 0) return;
    final deltaMs = _seekDeltaMs(dx, totalMs).round();
    final targetMs = (_seekStartPosition.inMilliseconds + deltaMs).clamp(0, totalMs.toInt());
    setState(() => _seekTarget = Duration(milliseconds: targetMs));
  }

  /// 横拖位移 → 时间偏移。
  ///
  /// 以前全屏宽只对应 `VideoPlayerUtil.seekRangeForDuration()` 给的一小段
  ///（短片才 15 秒），手指从最左划到最右也才走这么点，明显不合理。
  /// 现在改成 YouTube 那种两段灵敏度：
  /// - **起步 [_fineSeekZoneRatio] 行程**是精调区，只走 ±10 秒，用来对准台词/画面；
  /// - **剩下的行程**线性铺满整片，一次拖到底就是一整部片子。
  /// 短视频里精调区最多只占总时长的 10%，不会把行程吃光。
  double _seekDeltaMs(double dx, double totalMs) {
    final w = _screenWidth;
    if (w <= 0) return 0;
    final fineW = w * _fineSeekZoneRatio;
    final fineMs = min(_fineSeekRangeMs.toDouble(), totalMs * 0.1);
    final absDx = dx.abs();
    if (absDx <= fineW) {
      return (dx / fineW) * fineMs;
    }
    final restMs = (totalMs - fineMs).clamp(0.0, totalMs).toDouble();
    final restW = (w - fineW).clamp(1.0, w).toDouble();
    final sign = dx < 0 ? -1.0 : 1.0;
    return sign * (fineMs + (absDx - fineW) / restW * restMs);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_edgeBackCandidate) {
      // 未达到触发阈值：既未返回也未进入进度调节
      _edgeBackCandidate = false;
      _horizontalStartDx = null;
      return;
    }
    if (!_isSeeking) return;
    _controllers[_currentIndex]?.seekTo(_seekTarget);
    if (_wasPlayingBeforeSeek) _controllers[_currentIndex]?.play();
    _resetSpeedSample();
    _startTimer();
    setState(() => _isSeeking = false);
  }

  /// 边缘滑动手势触发：退出播放器返回上一级。
  void _handleEdgeBack() {
    _edgeBackCandidate = false;
    _horizontalStartDx = null;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    _subtitleController = SubtitleController();
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
    if (_playList.fromEmby) _loadEmbyFavorites();
    _startTimer();
  }

  @override
  void dispose() {
    _subtitleController.clear();
    _progressTimer?.cancel();
    _landscapeHideTimer?.cancel();
    _indicatorFadeTimer?.cancel();
    _centerRowFadeTimer?.cancel();
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
            final ok = await FavoriteHelper.addFavoriteSilent(
              isDir: false,
              remotePath: v.filePath, name: v.fileName, path: v.filePath,
              size: v.fileSize ?? 0, sign: v.sign, thumb: v.thumb,
              modified: v.modifiedMilliseconds ?? 0, provider: v.provider ?? '',
            );
            if (!ok) { v.isLiked = false; if (mounted) setState(() {}); }
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
          // 采样必须先于 setState，否则新速度要等下一帧才刷出来（肉眼可见延迟）
          if (_enableNetworkSpeed) _calcNetworkSpeed(c);
          // 滑动调整进度期间，不从播放器读取位置，避免覆盖预览进度导致闪烁
          setState(() { _pos = c.value.position; _dur = c.value.duration; });
          _subtitleController.updatePosition(c.value.position.inMilliseconds);
          if (c.value.duration > Duration.zero &&
              c.value.position >= c.value.duration - const Duration(milliseconds: 500) &&
              !_completing) {
            _completing = true;
            if (_loopMode == 2) {
              // 单视频循环
              c.seekTo(Duration.zero).then((_) { c.play(); _completing = false; });
            } else if (_loopMode == 0 && !_isLandscape && _currentIndex < _playList.videos.length - 1) {
              // 自动下一个
              _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut)
                  .then((_) => _completing = false);
            } else {
              // 播完即停止（或已是最后一个/横屏中）
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
    // Emby 来源的收藏 / 不喜欢状态由内存集合统一维护（不查 AList 本地库）
    if (_playList.fromEmby) {
      _applyEmbyState(idx);
      if (mounted) setState(() {});
      return;
    }
    try {
      final v = _playList.videos[idx];
      final u = _userController.user.value;
      v.isLiked = (await _database.favoriteDao.findByPath(u.serverUrl, u.username, v.filePath)) != null;
      v.isDisliked = (await _database.dislikedVideoDao.findByPath(u.serverUrl, u.username, v.filePath)) != null;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  // ═══════════════ Emby Favorite / Dislike ═══════════════

  /// 把内存中的收藏 / 不喜欢集合同步到某个视频项的 UI 状态（O(1)）。
  void _applyEmbyState(int idx) {
    if (idx < 0 || idx >= _playList.videos.length) return;
    final v = _playList.videos[idx];
    final id = v.embyItemId;
    if (id == null || id.isEmpty) return;
    // 收藏集合尚未加载完成时不改写，避免把乐观更新/未知状态清零
    if (!_embyFavLoaded) return;
    v.isLiked = _embyFavoriteIds.contains(id);
    v.isDisliked = _embyDislikeIds.contains(id);
  }

  /// 进入播放器时只请求一次收藏 Id；同时从本地库读取 Emby 不喜欢标记。
  ///
  /// 之后切换视频时通过 set 查询状态（O(1)），避免逐条请求打爆服务器。
  Future<void> _loadEmbyFavorites() async {
    final server = _embyServer ?? EmbyConfigManager.selectedServer;
    if (server == null || !server.isValid) return;
    _embyServer = server;
    try {
      // 本地“不喜欢”记录（纯本地查询，无网络开销）
      await _loadEmbyDislikeIds(server);
      final ids = await EmbyApi.fetchFavoriteIds(server);
      if (!mounted) return;
      _embyFavoriteIds
        ..clear()
        ..addAll(ids);
      _embyFavLoaded = true;
      _applyEmbyState(_currentIndex);
      if (mounted) setState(() {});
    } catch (e) {
      // 收藏状态拉取失败不影响播放，仅记录
      log.Log.e('loadEmbyFavorites: $e');
    }
  }

  /// 读取本地 disliked_video 表中该 Emby 服务器的不喜欢记录（provider='Emby'）。
  Future<void> _loadEmbyDislikeIds(EmbyServerConfig server) async {
    try {
      final rows = await _database.dislikedVideoDao
          .list(server.id, EmbyDislikeMark.userId)
          .first;
      _embyDislikeIds
        ..clear()
        ..addAll((rows ?? []).map((e) => e.remotePath));
    } catch (e) {
      log.Log.e('loadEmbyDislikeIds: $e');
    }
  }

  /// Emby 收藏切换（爱心）：乐观更新 → 调接口 → 用服务端状态校正；失败回滚。
  Future<void> _toggleEmbyFavorite() async {
    final idx = _currentIndex;
    if (idx < 0 || idx >= _playList.videos.length) return;
    final v = _playList.videos[idx];
    final itemId = v.embyItemId;
    if (itemId == null || itemId.isEmpty) return;
    if (_embyFavBusy.contains(idx)) return; // 防抖：同一条目请求未回来前忽略重复点击

    final server = _embyServer ?? EmbyConfigManager.selectedServer;
    if (server == null || !server.isValid) return;

    final target = !v.isLiked; // 目标状态
    _embyFavBusy.add(idx);
    // 乐观更新
    v.isLiked = target;
    if (target) _embyFavoriteIds.add(itemId);
    if (mounted) setState(() {});
    try {
      final confirmed = await EmbyApi.setFavorite(server, itemId,
          favorite: target);
      if (confirmed) {
        _embyFavoriteIds.add(itemId);
      } else {
        _embyFavoriteIds.remove(itemId);
      }
      v.isLiked = confirmed;
      if (mounted) setState(() {});
    } on EmbyApiException catch (e) {
      // 回滚
      v.isLiked = !target;
      if (target) {
        _embyFavoriteIds.remove(itemId);
      } else {
        _embyFavoriteIds.add(itemId);
      }
      if (mounted) {
        setState(() {});
        SmartDialog.showToast(e.message);
      }
    } catch (e) {
      v.isLiked = !target;
      if (target) {
        _embyFavoriteIds.remove(itemId);
      } else {
        _embyFavoriteIds.add(itemId);
      }
      if (mounted) {
        setState(() {});
        SmartDialog.showToast('操作失败：$e');
      }
    } finally {
      _embyFavBusy.remove(idx);
    }
  }

  /// Emby “踩”（不喜欢）：写入/移除本地的“不喜欢列表”记录（不请求服务器）。
  ///
  /// 与收藏互斥：踩下时若已收藏，会同步取消 Emby 收藏。
  /// 真正的“删除媒体”动作在「不喜欢列表」中执行（DELETE /Items?Ids=）。
  Future<void> _toggleEmbyDislike() async {
    final idx = _currentIndex;
    if (idx < 0 || idx >= _playList.videos.length) return;
    final v = _playList.videos[idx];
    final itemId = v.embyItemId;
    if (itemId == null || itemId.isEmpty) return;
    if (_embyFavBusy.contains(idx)) return; // 防抖（与收藏共用）

    final server = _embyServer ?? EmbyConfigManager.selectedServer;
    if (server == null || !server.isValid) return;

    final target = !v.isDisliked;
    _embyFavBusy.add(idx);
    try {
      if (target) {
        // 与收藏互斥：踩下时取消 Emby 收藏
        if (v.isLiked) {
          v.isLiked = false;
          _embyFavoriteIds.remove(itemId);
          try {
            await EmbyApi.setFavorite(server, itemId, favorite: false);
          } catch (e) {
            log.Log.e('unfavorite-on-dislike: $e');
          }
        }
        // 写本地不喜欢记录（provider 标记 Emby 来源，remote_path 存 itemId）
        final exists = await _database.dislikedVideoDao
            .findByPath(server.id, EmbyDislikeMark.userId, itemId);
        if (exists == null) {
          await _database.dislikedVideoDao.insertRecord(DislikedVideo(
            serverUrl: server.id,
            userId: EmbyDislikeMark.userId,
            remotePath: itemId,
            name: v.fileName,
            path: v.fileName,
            size: v.fileSize ?? 0,
            sign: null,
            thumb: v.thumb,
            modified: v.modifiedMilliseconds ?? 0,
            provider: EmbyDislikeMark.provider,
            createTime: DateTime.now().millisecondsSinceEpoch,
          ));
        }
        _embyDislikeIds.add(itemId);
        v.isDisliked = true;
      } else {
        await _database.dislikedVideoDao
            .deleteByPath(server.id, EmbyDislikeMark.userId, itemId);
        _embyDislikeIds.remove(itemId);
        v.isDisliked = false;
      }
      if (mounted) setState(() {});
      SmartDialog.showToast(target ? '已加入不喜欢列表' : '已取消不喜欢');
    } catch (e) {
      // 回滚
      v.isDisliked = !target;
      if (mounted) {
        setState(() {});
        SmartDialog.showToast('操作失败：$e');
      }
    } finally {
      _embyFavBusy.remove(idx);
    }
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
  /// 加载当前视频的同名本地字幕（按视频名在字幕目录匹配 .srt）
  void _loadSubtitleForCurrent() {
    if (_currentIndex < 0 || _currentIndex >= _playList.videos.length) return;
    final v = _playList.videos[_currentIndex];
    _subtitleController.loadSubtitle(remotePath: v.filePath, sign: v.sign);
  }

  Future<void> _safeInitCtrl(int idx) async {
    if (idx < 0 || idx >= _playList.videos.length) return;
    if (_controllers.containsKey(idx) || _initializingIndexes.contains(idx)) return;
    if (_initializingIndexes.length >= 2) return;
    _initializingIndexes.add(idx);
    if (idx == _currentIndex) _loadStartTime = DateTime.now();
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
      ctrl.setLooping(_loopMode == 2);
      _controllers[idx] = ctrl;
      _initializingIndexes.remove(idx);
      if (idx == _currentIndex) {
        ctrl.play(); _isPlaying = true; _recordViewing(idx); _loadSubtitleForCurrent();
        if (_enableNetworkSpeed) {
          final loadElapsed = DateTime.now().difference(_loadStartTime);
          final fs = v.fileSize;
          final b = ctrl.value.buffered;
          final durMs = ctrl.value.duration.inMilliseconds.toDouble();
          if (loadElapsed.inMilliseconds > 300 && b.isNotEmpty && durMs > 0) {
            // 起播瞬间的种子值：初始化完成时**实际已缓冲**的字节数 / 起播耗时。
            // 只用于让徽标在第一个下载段结算前就有数，随后会被段速率替换。
            // （这里不能用「整片大小 / 起播耗时」：起播往往只下载了整片的一小段，
            //  那样会高估好几倍，一进来就顶到 125 MB/s 的上限。）
            double bps = _fallbackBitrateBps;
            if (fs != null && fs > 0) bps = fs * 1000.0 / durMs;
            final cum = b.last.end.inMilliseconds / 1000.0 * bps;
            _networkSpeed = (cum / (loadElapsed.inMilliseconds / 1000.0))
                .clamp(0.0, _maxSpeedBps);
            _displaySpeed = _networkSpeed;
            _lastCumBytes = cum; // 对齐基准，免得下一帧被误判成缓冲回退
            _lastBufferedEnd = b.last.end;
            _lastSpeedSample = DateTime.now();
            _lastSpeedUpdateAt = DateTime.now(); // 起算「读数过期」的倒计时
          }
        }
      }
      if (mounted) setState(() {});
      // 进页面后只引导一次：第一次起播露 2 秒让人知道有 ±10s，之后不再露
      if (idx == _currentIndex && !_centerRowIntroShown) {
        _centerRowIntroShown = true;
        _wakeCenterRow();
      }

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
    _dismissCenterRow(); // 从后台回来继续播 → 同样不留中间那一行
  }

  void _safePause() {
    try { final c = _controllers[_currentIndex]; if (c != null && c.value.isInitialized) { c.pause(); _isPlaying = false; if (mounted) setState(() {}); } } catch (_) {}
  }

  /// 重置网速采样基线：切换视频 / 拖动进度后必须调用，
  /// 否则会把「跨视频」「跨 seek」的缓冲跳变算成成千上万的假峰值。
  void _resetSpeedSample() {
    _networkSpeed = 0;
    _displaySpeed = 0;
    _clearSpeedSegment();
    _lastSpeedUpdateAt = null;
    _lastCumBytes = 0;
    _lastBufferedEnd = Duration.zero;
    _lastSpeedSample = DateTime.now();
  }

  /// 网速徽标当前是否需要占用布局。
  ///
  /// 低于 1 KB/s（缓冲已追平播放进度、或已整片缓存）就不再显示，
  /// 免得长期挂一个 "0 B/s" 白占版面。
  bool _speedVisible() => _enableNetworkSpeed && _displaySpeed >= 1024;

  /// 结束当前「活跃下载段」的记账（不结算，只是丢弃）。
  void _clearSpeedSegment() {
    _segStartAt = null;
    _segStartBytes = 0;
    _lastGrowAt = null;
  }

  /// 把一个段速率融合进当前读数。
  void _settleSpeedSegment(double segSpeed) {
    _networkSpeed = _networkSpeed <= 0
        ? segSpeed
        : _networkSpeed + (segSpeed - _networkSpeed) * _speedEmaAlpha;
    _lastSpeedUpdateAt = DateTime.now();
    _updateDisplaySpeed();
  }

  /// 实时下载速度：**只统计「活跃下载段」**。
  ///
  /// 关键前提：播放器是「下一小段就停」的策略——缓冲到阈值就暂停下载，等播放
  /// 消费掉一段再继续。所以**不能**拿长时间平均当网速：那样会把「停下来不动」
  /// 的时间也摊进去，实测只有真实带宽的几分之一（真跑 5 MB/s 却显示 300 KB/s）。
  ///
  /// 这里的做法：把连续有增长的一段时间记为一个「下载段」，段结束时用
  /// 「段内新增字节 / 段内时长」结算——这段时间里确实一直在下，所以得到的就是
  /// 别的播放器 / 下载工具显示的那个带宽读数。段速率本身已经是平均值，天然不抖。
  void _calcNetworkSpeed(VideoPlayerController ctrl) {
    try {
      final buffered = ctrl.value.buffered;
      if (buffered.isEmpty) return;

      final end = buffered.last.end;
      final now = DateTime.now();

      // 拖动进度期间缓冲区间会整体跳变，这一段样本不参与计算
      if (_isSeeking) {
        _lastBufferedEnd = end;
        _lastSpeedSample = now;
        _clearSpeedSegment();
        return;
      }

      // 每「音视频秒」对应的字节数
      double bytesPerSecOfVideo = _fallbackBitrateBps;
      final durMs = ctrl.value.duration.inMilliseconds.toDouble();
      if (durMs > 0) {
        final fs = _playList.videos[_currentIndex].fileSize;
        if (fs != null && fs > 0) bytesPerSecOfVideo = fs * 1000.0 / durMs;
      }
      // 累计已下载字节数：缓冲到的位置 × 每秒字节数
      final cumBytes = end.inMilliseconds / 1000.0 * bytesPerSecOfVideo;

      if (cumBytes + 1024 < _lastCumBytes) {
        // 缓冲位置回退（seek / 换源），旧数据整体作废
        _networkSpeed = 0;
        _displaySpeed = 0;
        _clearSpeedSegment();
      }

      final prevCum = _lastCumBytes;
      final grew = cumBytes - prevCum > 1.0;
      if (grew) {
        // 增长发生在「上一帧 → 现在」之间，所以段的起点取上一帧时刻
        _segStartAt ??= _lastSpeedSample;
        if (_segStartBytes == 0) _segStartBytes = prevCum;
        _lastGrowAt = now;

        // 连续下载太久（起播冲刺）就先结算一次，别等到停下来才出数
        final segMs = now.difference(_segStartAt!).inMilliseconds;
        if (segMs >= _segMaxMs) {
          final segBytes = cumBytes - _segStartBytes;
          if (segBytes > 0) {
            _settleSpeedSegment(
                (segBytes * 1000.0 / segMs).clamp(0.0, _maxSpeedBps));
          }
          _segStartAt = now;
          _segStartBytes = cumBytes;
        }
      }
      _lastCumBytes = cumBytes;
      _lastBufferedEnd = end;
      _lastSpeedSample = now;

      // 静默够久 → 这一段下载结束了，结算它
      if (!grew && _segStartAt != null && _lastGrowAt != null &&
          now.difference(_lastGrowAt!).inMilliseconds >= _segSilentMs) {
        final segMs = _lastGrowAt!.difference(_segStartAt!).inMilliseconds;
        final segBytes = cumBytes - _segStartBytes;
        if (segMs >= _segMinMs && segBytes > 0) {
          _settleSpeedSegment(
              (segBytes * 1000.0 / segMs).clamp(0.0, _maxSpeedBps));
        }
        _clearSpeedSegment();
      }

      // 太久没有新的下载段：缓冲已满 / 整片已缓存，读数过期 → 归零
      if (_networkSpeed > 0 &&
          _lastSpeedUpdateAt != null &&
          now.difference(_lastSpeedUpdateAt!).inMilliseconds > _speedStaleMs) {
        _networkSpeed = 0;
        _displaySpeed = 0;
      }
    } catch (_) {}
  }

  /// 显示死区：新值和正在显示的值相差不到 [_speedDeadband] 就维持原数字。
  /// 归零 / 起步这类大跳变直接放行，免得卡住不动。
  void _updateDisplaySpeed() {
    final v = _networkSpeed;
    if (_displaySpeed <= 0 || v <= 0) {
      _displaySpeed = v;
      return;
    }
    if ((v - _displaySpeed).abs() / _displaySpeed > _speedDeadband) {
      _displaySpeed = v;
    }
  }

  // ═══════════════ Gesture: Single Tap (delayed) + Double Tap ═══════════════
  Offset _lastTapDownPos = Offset.zero;

  /// 双击按下：记录坐标，供红心飘动特效定位（onDoubleTap 本身不带位置）。
  void _onDoubleTapDown(TapDownDetails d) {
    _lastTapDownPos = d.globalPosition;
  }

  /// 左右各 30% 是「双击跳 10 秒」区，中间 40% 留给双击点赞。
  static const double _doubleTapSeekZone = 0.30;
  static const int _doubleTapSeekStep = 10;
  final List<_SeekRipple> _seekRipples = <_SeekRipple>[];
  int _rippleSeconds = 0;
  bool _rippleLeft = false;
  DateTime? _rippleAt;

  /// 双击**分区域**：屏幕左右各 [_doubleTapSeekZone] → 快退 / 快进 10 秒，
  /// 中间 40% → 原来的双击点赞。
  ///
  /// 这是把中间那一行彻底从"播放中"撤掉的配套：播放时画面上不再有任何
  /// ±10s 控件，想跳就双击屏幕两侧（YouTube / B 站同一套肌肉记忆），
  /// 反馈只是一闪而过的涟漪（[_SeekRippleAnim]），不占画面、不挡主体。
  ///
  /// 与单击共存：GestureDetector 同时声明 onTap 与 onDoubleTap 后，Flutter 的
  /// 手势竞技场会自动把单击判定延迟到双击超时之后——双击只会走这里，
  /// 不会误触发一次播放/暂停。
  void _onDoubleTap() {
    final pos = _lastTapDownPos;
    final w = _screenWidth;
    if (w <= 0 || _dur <= Duration.zero) {
      _doubleTapLike(pos); // 还没拿到时长，跳不了秒，退回点赞
      return;
    }
    if (pos.dx <= w * _doubleTapSeekZone) {
      _seekByDoubleTap(-_doubleTapSeekStep, left: true, pos: pos);
    } else if (pos.dx >= w * (1 - _doubleTapSeekZone)) {
      _seekByDoubleTap(_doubleTapSeekStep, left: false, pos: pos);
    } else {
      _doubleTapLike(pos);
    }
  }

  /// 双击左右两侧：跳 [_doubleTapSeekStep] 秒，并在那一侧冒一个涟漪。
  ///
  /// 700ms 内连击同一侧会累加（10 → 20 → 30 秒），涟漪上的数字跟着涨，
  /// 跟 YouTube 一样：连点几下就能一次跳很远，不用等动画播完再点。
  void _seekByDoubleTap(int delta, {required bool left, required Offset pos}) {
    final now = DateTime.now();
    final chain = _rippleAt != null &&
        now.difference(_rippleAt!) < const Duration(milliseconds: 700) &&
        _rippleLeft == left;
    _rippleSeconds = chain ? _rippleSeconds + delta : delta;
    _rippleLeft = left;
    _rippleAt = now;
    _seekBy(delta);
    if (!mounted) return;
    setState(() {
      _seekRipples.removeWhere((r) => r.left == left); // 同侧只留最新的那个
      _seekRipples.add(_SeekRipple(UniqueKey(), pos, left, _rippleSeconds));
    });
  }

  /// 双击中间区域：红心飘动特效 + 切换收藏。
  void _doubleTapLike(Offset pos) {
    // Emby 来源：双击 = 爱心特效 + 切换 Emby 收藏
    if (_playList.fromEmby) {
      if (mounted) setState(() => _doubleTapIcons.add(pos));
      _toggleEmbyFavorite();
      return;
    }
    if (mounted) setState(() => _doubleTapIcons.add(pos));
    final v = _playList.videos[_currentIndex];
    v.isLiked = !v.isLiked;
    if (v.isLiked && v.isDisliked) v.isDisliked = false;
    _pendingFav[_currentIndex] = v.isLiked;
    if (v.isLiked) _pendingDislike[_currentIndex] = false;
    if (mounted) setState(() {});
  }

  List<Widget> _buildSeekRipples() => _seekRipples
      .map((r) => _SeekRippleAnim(
            key: r.key,
            position: r.pos,
            left: r.left,
            seconds: r.seconds,
            onDone: () {
              if (mounted) setState(() => _seekRipples.remove(r));
            },
          ))
      .toList();

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
      // 方向决定生死：恢复播放**立刻收起**（用户这时要的是接着看，画面上
      // 不该再留东西，哪怕 2 秒也嫌挡）；暂停则常驻，见 [_wakeCenterRow]。
      if (_isPlaying) _dismissCenterRow();
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
        // 保险①：竖屏隐藏后，单击屏幕一律恢复控件（不再区分自动/手动）。
        // 这一击只做「恢复 UI」，不触发播放/暂停 —— 否则想找回界面的人
        // 会被顺手暂停掉，手感很别扭（抖音也是这个行为）。
        _hideUI = false;
        _manualHideUI = false;
        // 显式恢复控件 → 顺手把中间一行也叫出来（这一次确实是想看点什么）
        _wakeCenterRow();
      } else {
        // 播放/暂停本身就能决定中间一行：暂停常驻、恢复播放立刻收起
        _togglePlayPause();
      }
    }
    if (mounted) setState(() {});
  }

  /// 唤出竖屏中间那一行（−10s / 播放键 / +10s），并在**播放中**启动 2 秒倒计时。
  ///
  /// 现在只剩两个唤出时机，都是「用户确实想看界面」的时刻：
  /// - **进页面后的第一次起播**：露 2 秒做引导（[_centerRowIntroShown] 只放一次，
  ///   之后切页不再露 —— 已经知道有这两个键了，没必要每次都挡一下）；
  /// - **隐藏后恢复控件**：这一下是用户主动要找回界面；
  /// - **暂停**：见下，直接长亮。
  ///
  /// 播放中途的手势（拖进度、横拖 seek、调亮度/音量）**不再唤出它**，
  /// 恢复播放更是 [_dismissCenterRow] 立刻收起 —— 那时用户正在看画面，
  /// 凭空冒出来两个圆只会挡住主体；要跳秒就双击屏幕两侧。
  void _wakeCenterRow() {
    _centerRowFadeTimer?.cancel();
    if (!mounted) return;
    if (!_centerRowAwake) setState(() => _centerRowAwake = true);
    if (!_isPlaying) return; // 暂停中长亮，不倒计时
    _centerRowFadeTimer = Timer(_centerRowLinger, () {
      _centerRowFadeTimer = null;
      if (!mounted || !_isPlaying) return; // 这 2 秒里要是被暂停了，就继续留着
      setState(() => _centerRowAwake = false);
    });
  }

  /// 立刻收起中间那一行：不等 2 秒，直接走 [_centerRowFade] 淡出。
  ///
  /// 用在「恢复播放」上——点了继续播放就说明想接着看，画面上不该再留任何东西，
  /// 哪怕 2 秒的停留也是白占。想再用 ±10s 就再点一下屏幕（那一击会顺带暂停，
  /// 整行随即常驻，见 [_buildCenterControls]）。
  void _dismissCenterRow() {
    _centerRowFadeTimer?.cancel();
    _centerRowFadeTimer = null;
    if (!mounted || !_centerRowAwake) return;
    setState(() => _centerRowAwake = false);
  }

  void _cancelCenterRowFade() {
    _centerRowFadeTimer?.cancel();
    _centerRowFadeTimer = null;
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
    _loopMode = (_loopMode + 1) % 3;
    try { _controllers[_currentIndex]?.setLooping(_loopMode == 2); } catch (_) {}
    if (mounted) setState(() {});
    final labels = ['自动下一个', '播完即停止', '单视频循环'];
    SmartDialog.showToast(labels[_loopMode]);
  }

  void _toggleLike() {
    // Emby 来源：爱心按钮走 Emby 收藏接口
    if (_playList.fromEmby) {
      _toggleEmbyFavorite();
      return;
    }
    final v = _playList.videos[_currentIndex];
    v.isLiked = !v.isLiked;
    if (v.isLiked && v.isDisliked) v.isDisliked = false;
    _pendingFav[_currentIndex] = v.isLiked;
    if (v.isLiked) _pendingDislike[_currentIndex] = false;
    if (mounted) setState(() {});
  }

  void _toggleDislike() {
    // Emby 来源：踩 = 写入本地“不喜欢列表”（与 Emby 收藏互斥）
    if (_playList.fromEmby) {
      _toggleEmbyDislike();
      return;
    }
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
    _resetSpeedSample();
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
    final mq = MediaQuery.of(context);
    // 高度上限按「去掉系统安全区后的可用高度」计算：横屏可用高度只有 ~360dp，
    // 若直接取屏幕高度的比例，BottomSheet 总高会超出屏幕，顶部几行被裁掉
    final maxSheetHeight =
        (mq.size.height - mq.padding.top - mq.padding.bottom) * 0.96;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      isScrollControlled: true,
      // maxWidth 640 与 Material 3 的 BottomSheet 默认约束保持一致
      constraints: BoxConstraints(maxWidth: 640, maxHeight: maxSheetHeight),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => TiktokVideoInfoSheet(
        video: v,
        fromEmby: _playList.fromEmby,
        position: '${_currentIndex + 1} / ${_playList.videos.length}',
      ),
    );
  }

  /// 拖动预览里的偏移量：1 分钟内显示 +12s，超过则显示 +12:34，
  /// 免得长视频拖一下冒出一串四位数秒。
  String _fmtSeekDelta(Duration d) {
    final totalMs = d.inMilliseconds;
    final s = totalMs.abs() ~/ 1000;
    final sign = totalMs < 0 ? '-' : '+';
    if (s < 60) return '$sign${s}s';
    final m = s ~/ 60;
    return '$sign$m:${(s % 60).toString().padLeft(2, '0')}';
  }

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
    // 设置页改过之后回到播放页能立即生效
    _fitMode = LandscapeFitModeHelper.read();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        _buildGestureLayer(),
        // 横屏：画面全屏铺满，控件全部收进可唤起的浮动 HUD；
        // 竖屏：顶栏 / 右侧工具栏 / 底部进度条 + 屏幕正中那一行三件套。
        if (_isLandscape)
          Positioned.fill(child: _buildLandscapeHud())
        else ...[
          if (!_hideUI) _buildTopBar(),
          if (!_hideUI) _buildToolBar(),
          if (!_hideUI) _buildProgress(),
          // 竖屏专属：中央一行「−10s ⏵ +10s」，播放键已并入这一行
          if (!_hideUI) _buildCenterControls(),
        ],
        SubtitleView(controller: _subtitleController, bottomOffset: _isLandscape ? 84 : 150),
        if (!_hideUI && !_isLandscape) _buildBottomInfo(),
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
        // 双击跳秒时的涟漪：只在操作的那一瞬间出现，600 多毫秒就散掉，
        // 放在 hearts 之后，跟红心一样不参与命中测试、不受 _hideUI 影响
        ..._buildSeekRipples(),
        // 页码指示器自身承担「休眠态」：隐藏控件时它淡化留守并兼作恢复入口，
        // 不额外新造控件，避免同一个位置出现两套视觉语言
        if (_pageIndicatorEnabled()) _buildIndicator(),
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
        // 单击（播放/暂停）与双击（红心特效）共存：
        // 声明 onDoubleTap 后，单击会在双击超时后才触发，二者不互抢
        onDoubleTapDown: _onDoubleTapDown,
        onDoubleTap: _onDoubleTap,
        child: _buildPageView(),
      ),
    );
  }

  void _onPageChanged(int idx) {
    _flushPending();
    _centerRowAwake = false; // 换页先收起：新视频开头挡着主体最难受
    _cancelCenterRowFade();
    try { _controllers[_currentIndex]?.pause(); } catch (_) {}
    _currentIndex = idx;
    _isPlaying = false;
    _pos = Duration.zero;
    _dur = Duration.zero;
    _resetSpeedSample(); // 换视频后旧缓冲区间作废，否则会冒出一个假峰值
    _loadSubtitleForCurrent();
    _disposeOutOfRange(idx);
    if (mounted) setState(() {});
    final c = _controllers[idx];
    if (c != null && c.value.isInitialized) {
      c.play();
      _isPlaying = true;
      _recordViewing(idx);
      // 切页后不再重复引导：[_centerRowIntroShown] 在第一次起播时已经放过一次
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
        return _buildLandscapeVideo(video, c.value.size);
      }
      return Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: video));
    }
    return const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2));
  }

  /// 横屏全屏时的画面适配，具体行为由 [_fitMode] 决定（见 [LandscapeFitMode]）。
  ///
  /// 自适应模式用「物理像素」把视频和屏幕放在同一尺度上比较：
  /// - 铺满所需的缩放倍数 > 1：说明要把视频放大才铺得满，画质会发虚；
  /// - 裁切比例 > [LandscapeFitMode.autoMaxCropRatio]：说明铺满会切掉贴底的硬字幕。
  /// 命中任一条就退化为等比完整显示（宁可留黑边，也不糊、不切内容）。
  Widget _buildLandscapeVideo(Widget video, Size videoSize) {
    return LayoutBuilder(builder: (ctx, constraints) {
      // 用 item 的真实约束而不是 MediaQuery：分屏 / 自由窗口下两者并不相等
      final dpr = MediaQuery.of(ctx).devicePixelRatio;
      final needW = constraints.maxWidth * dpr / videoSize.width;
      final needH = constraints.maxHeight * dpr / videoSize.height;
      final fillScale = max(needW, needH); // 铺满整屏所需的缩放倍数
      final keepRatio = min(needW, needH) / fillScale; // 铺满时还能看到的画面比例

      final fit = switch (_fitMode) {
        LandscapeFitMode.cover => BoxFit.cover,
        LandscapeFitMode.contain => BoxFit.contain,
        LandscapeFitMode.fill => BoxFit.fill,
        LandscapeFitMode.auto =>
          (fillScale <= 1.0 &&
                  keepRatio >= 1.0 - LandscapeFitMode.autoMaxCropRatio)
              ? BoxFit.cover
              : BoxFit.contain,
      };
      return SizedBox.expand(
        child: FittedBox(
          fit: fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
              width: videoSize.width, height: videoSize.height, child: video),
        ),
      );
    });
  }

  /// 横屏 HUD 上的画面适配快切：按 自适应 → 铺满裁剪 → 完整显示 → 拉伸填满 循环。
  void _cycleFitMode() {
    final next = LandscapeFitMode
        .values[(_fitMode.index + 1) % LandscapeFitMode.values.length];
    _fitMode = next;
    LandscapeFitModeHelper.write(next);
    setState(() {});
    SmartDialog.showToast('画面适配：${next.label}');
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
          // 实时网速：紧跟页码。放这里既避开底部拥挤区，又不用自己管显隐
          if (_speedVisible()) ...[
            const SizedBox(width: 8),
            _buildSpeedBadge(),
          ],
          const Spacer(),
          // 竖屏顶栏的显隐开关（横屏改用点击屏幕，见 [_buildLandscapeHud]）
          IconButton(
            icon: Icon(_hideUI ? Icons.visibility : Icons.visibility_off,
                color: Colors.white, size: 22),
            onPressed: () {
              setState(() {
                _hideUI = !_hideUI;
                _manualHideUI = _hideUI;
              });
              if (_hideUI) _notifyHideHint(); // 保险③：第一次隐藏时告诉人怎么找回来
            },
          ),
        ]),
      )),
    ));
  }

  /// 隐藏控件后怎么找回来。文案跟着页码指示器走：开着就补一句「点右侧圆点」。
  /// 每次进播放页只提示一次，不打扰。
  void _notifyHideHint() {
    if (_hideHintShown) return;
    _hideHintShown = true;
    final tail = _pageIndicatorEnabled() ? '，或点右侧页码圆点' : '';
    SmartDialog.showToast('控件已隐藏 · 点屏幕任意位置即可恢复$tail');
  }

  /// 竖屏右侧竖向工具栏：收藏 / 踩 / 循环 / 信息。
  ///
  /// 横屏不再使用它——横屏的同类按钮由 [_buildLandscapeHud] 的浮动层承担。
  Widget _buildToolBar() {
    final screenH = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;
    const bottomOffset = 160.0;
    final maxH = screenH - topPad - bottomOffset - 20;

    final buttons = <Widget>[
      _buildFavoriteButton(),
      _buildDislikeButton(),
      _btn(
          icon: _loopMode == 2
              ? Icons.repeat_one
              : _loopMode == 1
                  ? Icons.stop_rounded
                  : Icons.repeat,
          label: ['自动下一个', '播完即停止', '单视频循环'][_loopMode],
          color: _loopMode != 0 ? Colors.amber : Colors.white,
          onTap: _toggleLoop),
      _btn(
          icon: Icons.info_outline,
          label: '信息',
          color: Colors.white,
          onTap: _showInfo),
    ];

    final spaced = <Widget>[];
    for (var i = 0; i < buttons.length; i++) {
      if (i > 0) spaced.add(const SizedBox(height: 16));
      spaced.add(buttons[i]);
    }
    spaced.add(const SizedBox(height: 4));

    return Positioned(right: 12, bottom: bottomOffset,
      child: Opacity(opacity: _uiOpacity, child: SizedBox(
        height: maxH.clamp(0.0, 500.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: spaced,
        ),
      )),
    );
  }

  /// 「收藏」按钮：Emby 来源走 Emby 收藏接口，其余走本地收藏库（均带动效）。
  /// 竖屏工具栏与横屏右侧胶囊共用。
  Widget _buildFavoriteButton() {
    final v = _playList.videos[_currentIndex];
    return _HeartBtn(
      liked: v.isLiked,
      label: v.isLiked ? '已收藏' : '收藏',
      onTap: _playList.fromEmby ? _toggleEmbyFavorite : _toggleLike,
    );
  }

  /// 「踩」按钮：Emby 来源写入本地“不喜欢列表”，其余写入本地不喜欢库。
  /// 竖屏工具栏与横屏右侧胶囊共用。
  Widget _buildDislikeButton() {
    final v = _playList.videos[_currentIndex];
    return _btn(
      icon: v.isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
      label: v.isDisliked ? '已踩' : '踩',
      color: v.isDisliked ? Colors.blue : Colors.white,
      onTap: _playList.fromEmby ? _toggleEmbyDislike : _toggleDislike,
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
    final bottomOffset = 80.0;
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

  /// 竖屏**屏幕正中一行的三件套**：`−10s ⏵ +10s`。
  ///
  /// 位置：还是以中间播放键为轴对称排开（MX Player / VLC 的经典布局）。
  ///
  /// 但它压在画面正中央，所以**播放中一律不出现**。整行的出现时机收敛成三条：
  /// - **暂停时**：常驻（画面静止不挡内容，而这时正是要按这两个键的时刻）；
  /// - **进页面第一次起播**：露 2 秒做一次引导（[_centerRowIntroShown]）；
  /// - **隐藏后恢复控件**：用户主动要看界面；
  /// 恢复播放由 [_dismissCenterRow] **立刻收起**，一秒都不多留。
  /// 播放中要跳秒改走**双击屏幕左右两侧**（见 [_onDoubleTap]）。
  ///
  /// 一行的尺寸是 256×72；隐藏时用 [IgnorePointer] 把点击还给手势层，
  /// 手指照样能单击暂停、双击跳秒。
  ///
  /// 显隐：仍然挂在 build() 的 `if (!_hideUI)` 上，整体透明度还是 [_uiOpacity]，
  /// 这一层额外叠的是「按需浮出」开关，跟原来的规则互不冲突。
  Widget _buildCenterControls() {
    // 暂停时 `_isPlaying == false` → 长亮：画面静止时它不挡内容，
    // 而这正是用户最需要看清这两个按钮的时刻。
    final awake = _centerRowAwake || !_isPlaying;
    return Positioned.fill(
      child: Center(
        child: AnimatedOpacity(
          opacity: awake ? _uiOpacity : 0.0,
          duration: _centerRowFade,
          curve: Curves.easeOut,
          child: IgnorePointer(
            ignoring: !awake,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _seekStepButton(icon: Icons.replay_10, seconds: -10),
              const SizedBox(width: 40),
              _buildCenterSlot(),
              const SizedBox(width: 40),
              _seekStepButton(icon: Icons.forward_10, seconds: 10),
            ]),
          ),
        ),
      ),
    );
  }

  /// ±10s 按钮本体。视觉详见 [_SeekStepIcon]，这里只负责接线。
  Widget _seekStepButton({required IconData icon, required int seconds}) {
    return _SeekStepIcon(icon: icon, onTap: () => _seekBy(seconds));
  }

  String _fmtSpeed(double bps) {
    if (bps < 1024) return '${bps.toInt()} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toInt()} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  /// 实时下载速度徽标（⬇ 1.2 MB/s）。
  ///
  /// 位置选在「顶栏页码旁」而不是底部文件信息行的原因：
  /// 底部那行已经有文件路径 + 文件大小，再加网速会被 ellipsis 截掉，
  /// 而且右侧工具栏（bottom 160 起）和进度条（bottom 80）已经很挤；
  /// 顶栏中间是唯一的空白区，且横竖屏都对应同一处，切换后视线不需要重新找。
  ///
  /// 显隐：本组件没有任何自己的 Timer / Controller，纯跟随所在浮层
  /// —— 竖屏由 [_buildTopBar] 的 `if (!_hideUI)` + Opacity 控制，
  /// 横屏由 [_buildLandscapeHud] 的 AnimatedOpacity 淡入淡出，
  /// 因此天然符合原有的控件显隐规则。
  Widget _buildSpeedBadge({bool compact = false}) {
    if (!_speedVisible()) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 7, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(compact ? 0.4 : 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.14), width: 0.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.downloading_rounded,
            color: const Color(0xFF4FC3F7), size: compact ? 11 : 12),
        const SizedBox(width: 3),
        Text(_fmtSpeed(_displaySpeed),
            style: TextStyle(
                color: const Color(0xFF4FC3F7),
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace')),
      ]),
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
                // 仅剥离常见视频扩展名（含域名/多点的名称不会被误截），超长交给 ellipsis 截断
                final dn = stripKnownVideoExtension(v.fileName);
                return Text(dn, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis);
              }),
              const SizedBox(height: 4),
              // 网速已移到顶栏徽标（[_buildSpeedBadge]），此处只留 大小 | 路径，避免被截断
              Row(children: [
                // Emby 直链来源的 filePath 与文件名重复，只显示大小；其余显示 大小 | 路径
                Expanded(
                  child: Text(
                    _playList.fromEmby
                        ? '${v.formattedSize}'
                        : '${v.formattedSize}  |  ${v.filePath}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ]),
          ),
          // 竖屏专属：切横屏 / 截图（横屏由 HUD 底部 / 顶部浮层提供）
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
      )),
    );
  }

  Widget _buildSeekPreview() {
    final delta = _seekTarget - _seekStartPosition;
    final icon = delta.inMilliseconds >= 0
        ? Icons.fast_forward_rounded
        : Icons.fast_rewind_rounded;
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
            Text('${_fmtDur(_seekTarget)}  (${_fmtSeekDelta(delta)})',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ═══════════════ 横屏沉浸式 HUD ═══════════════

  /// 横屏浮动控制层（Overlay HUD）。
  ///
  /// 画面本身已全屏铺满（见 [_buildVideoItem]），所有控件默认隐藏；
  /// 点击屏幕任意位置淡入上下浮层（[_onScreenTap]），播放中静止
  /// [_landscapeAutoHide] 后自动淡出（[_startLandscapeAutoHide]）。
  /// 右侧「收藏 / 踩」胶囊不随显隐消失，只降低不透明度，保持随时可点。
  Widget _buildLandscapeHud() {
    return AnimatedOpacity(
      opacity: _hideUI ? 0.0 : _uiOpacity,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: _hideUI,
        child: Stack(children: [
          _buildLandscapeTopBar(),
          _buildLandscapeBottomBar(),
          _buildLandscapeSideActions(),
        ]),
      ),
    );
  }

  /// 顶部浮层：返回 / 标题 + 播放位置 / 系统时间 · 截图 · 信息。
  Widget _buildLandscapeTopBar() {
    final v = _playList.videos[_currentIndex];
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.78), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 6, 22),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 22),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stripKnownVideoExtension(v.fileName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${_currentIndex + 1} / ${_playList.videos.length}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.65),
                                fontSize: 11)),
                        // 与竖屏保持同一处（页码旁），旋转后视线不用来回找
                        if (_speedVisible()) ...[
                          const SizedBox(width: 6),
                          _buildSpeedBadge(compact: true),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(_fmtClock(DateTime.now()),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 13)),
              const SizedBox(width: 4),
              _hudBarButton(Icons.camera_alt_outlined, '截图', _takeScreenshot),
              _hudBarButton(Icons.info_outline, '信息', _showInfo),
            ]),
          ),
        ),
      ),
    );
  }

  /// 底部浮层：快退10s / 播放暂停 / 快进10s · 进度条与时间 · 上一个 / 下一个 · 切回竖屏。
  Widget _buildLandscapeBottomBar() {
    final totalMs = _dur.inMilliseconds.toDouble();
    final curMs = _pos.inMilliseconds.toDouble();
    final val = totalMs > 0 ? (curMs / totalMs).clamp(0.0, 1.0) : 0.0;
    final hasPrev = _currentIndex > 0;
    final hasNext = _currentIndex < _playList.videos.length - 1;
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.82), Colors.transparent],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 26, 8, 2),
            child: Row(children: [
              _hudBarButton(
                  Icons.replay_10_rounded, '快退 10 秒', () => _seekBy(-10)),
              _hudBarButton(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  _isPlaying ? '暂停' : '播放',
                  _togglePlayPause,
                  size: 32),
              _hudBarButton(
                  Icons.forward_10_rounded, '快进 10 秒', () => _seekBy(10)),
              const SizedBox(width: 10),
              Text(_fmtDur(_pos),
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
                    onChangeEnd: _onSeekEnd,
                  ),
                ),
              ),
              Text(_fmtDur(_dur),
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(width: 6),
              _hudBarButton(Icons.skip_previous_rounded, '上一个',
                  hasPrev ? () => _goToPage(_currentIndex - 1) : null),
              _hudBarButton(Icons.skip_next_rounded, '下一个',
                  hasNext ? () => _goToPage(_currentIndex + 1) : null),
              _hudBarButton(
                  _fitMode.icon, '画面适配：${_fitMode.label}', _cycleFitMode),
              _hudBarButton(
                  Icons.screen_rotation_rounded, '竖屏', _toggleOrientation),
            ]),
          ),
        ),
      ),
    );
  }

  /// 右侧半透明竖向胶囊：收藏 / 踩。
  ///
  /// HUD 隐藏时只把不透明度降到 0.32（不彻底消失、不拦截点击），
  /// 既不遮挡画面核心区域，又能随时收藏 / 踩。
  Widget _buildLandscapeSideActions() {
    return Positioned(
      right: 10, top: 0, bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _hideUI ? 0.32 : _uiOpacity,
          duration: const Duration(milliseconds: 260),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFavoriteButton(),
                const SizedBox(height: 8),
                _buildDislikeButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// HUD 通用按钮：固定 42x42 点击区，禁用态（[onTap] 为 null）自动转半透明。
  Widget _hudBarButton(IconData icon, String tip, VoidCallback? onTap,
      {double size = 22}) {
    if (onTap == null) {
      return SizedBox(
        width: 42,
        height: 42,
        child: Center(child: Icon(icon, size: size, color: Colors.white24)),
      );
    }
    return IconButton(
      tooltip: tip,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(42, 42),
        maximumSize: const Size(42, 42),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: size, color: Colors.white),
      onPressed: onTap,
    );
  }

  /// 相对当前进度快进 / 快退（秒）。
  void _seekBy(int seconds) {
    try {
      final target = _pos + Duration(seconds: seconds);
      var clamped = target < Duration.zero ? Duration.zero : target;
      if (_dur > Duration.zero && clamped > _dur) clamped = _dur;
      _controllers[_currentIndex]?.seekTo(clamped);
      _resetSpeedSample();
      if (mounted) setState(() => _pos = clamped);
      // 不用在这里 _wakeCenterRow()：暂停时整行本来就长亮，
      // 而播放中根本不该把这行叫出来（要跳秒请双击屏幕两侧）。
    } catch (_) {}
  }

  /// 切到第 [idx] 个视频（对应原来的上一个 / 下一个）。
  void _goToPage(int idx) {
    if (idx < 0 || idx >= _playList.videos.length) return;
    _pageController.animateToPage(idx,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  /// 顶部浮层的系统时间（HH:mm）——进度定时器刷新时顺带重建即保持最新。
  String _fmtClock(DateTime now) =>
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  /// 中央一行**正中间那一格**：暂停时是播放键，播放中是等宽空位。
  ///
  /// 留空位而不是让它整个消失，是为了让左右两个 ±10s 永远对称——
  /// 否则三角形一出现 / 一消失，两边按钮就会左右跳一下，很难看。
  Widget _buildCenterSlot() {
    if (_isPlaying || _isLandscape) return const SizedBox(width: 72, height: 72);
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(width: 72, height: 72,
        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(36)),
        child: const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 44)),
    );
  }

  List<Widget> _buildHearts() => _doubleTapIcons.map((p) =>
    _HeartAnim(key: Key(p.toString()), position: p, onDone: () => _doubleTapIcons.remove(p))).toList();

  // 修复：页码指示器支持任意数量视频，用比例显示

  /// 页码指示器开关。
  ///
  /// 原来写成 `SpUtil.getBool(k) ?? true`，那句 `?? true` 是**永远走不到的死代码**：
  /// sp_util 的 getBool 签名是 `static bool? getBool(String key, {bool? defValue = false})`，
  /// 也就是「key 从来没写过」时它返回的是 false 而不是 null —— 结果就是默认关闭，
  /// 而且外面怎么都救不回来。这里改成先用 haveKey 判断是否真的存过。
  bool _pageIndicatorEnabled() {
    final key = AlistConstant.showTiktokPageIndicator;
    if (SpUtil.haveKey(key) != true) return true; // 从未设置过 → 默认开启
    return SpUtil.getBool(key) ?? false;
  }

  final ScrollController _indicatorScrollCtrl = ScrollController();

  // ═════════ 页码指示器：拖动选片 ═════════
  /// 正在指示器上拖动选片（此时整条指示器提亮，跟休眠态区分开）。
  bool _scrubbing = false;
  /// 手指当前落在第几个（−1 = 没有）。松手就跳到这个。
  int _scrubIndex = -1;
  /// 手指在指示条内的纵向位置，气泡跟着它走。
  double _scrubDy = 0;
  /// 触感节流：大列表一次能划过几百个，不节流会疯狂震动。
  DateTime? _lastScrubHaptic;
  /// 跨度超过这个数就别动画了（PageView 一路闪过去反而卡），直接落位。
  static const int _pageJumpThreshold = 20;

  /// 指示器**命中区**的宽度。圆点本身只有 3~6px 宽，照着它做热区手指根本按不到，
  /// 所以热区外扩到 28，再用 Align 把圆点贴回原来那一侧（左/右边缘），
  /// 视觉位置一像素不动，但手指有 28px 可落脚。
  static const double _indicatorHitWidth = 28.0;

  /// 手指位置 → 下标。**按密度分两档**（这是大列表能用得下去的关键）：
  ///
  /// - **看得全**（`total * itemH <= maxH`）：绝对映射，手指底下哪个点就是哪个，
  ///   所见即所得，不用解释；
  /// - **看不全**（长列表，点被压到 3px）：改**比例映射** —— 整条高度 = 整个
  ///   播放列表，`index = 手指高度占比 × (total-1)`。一次拖动就能从第一个到
  ///   最后一个，跟拖滚动条一样；再密的列表也不需要"边缘加速"那套补丁。
  int _scrubIndexFor(
      double dy, double itemH, double maxH, int total, bool dense) {
    if (total <= 0) return 0;
    if (dense) {
      final f = maxH <= 0 ? 0.0 : (dy / maxH).clamp(0.0, 1.0);
      return (f * (total - 1)).round();
    }
    final offset =
        _indicatorScrollCtrl.hasClients ? _indicatorScrollCtrl.offset : 0.0;
    return itemH <= 0 ? 0 : ((dy + offset) / itemH).floor().clamp(0, total - 1);
  }

  void _scrubHaptic() {
    final now = DateTime.now();
    if (_lastScrubHaptic != null &&
        now.difference(_lastScrubHaptic!) < const Duration(milliseconds: 70)) {
      return;
    }
    _lastScrubHaptic = now;
    HapticFeedback.selectionClick();
  }

  void _onIndicatorDragStart(double dy, double itemH, double maxH, int total,
      bool dense) {
    _scrubDy = dy;
    _lastScrubHaptic = null;
    _scrubHaptic();
    setState(() {
      _scrubbing = true;
      _scrubIndex = _scrubIndexFor(dy, itemH, maxH, total, dense);
    });
  }

  void _onIndicatorDragUpdate(
      double dy, double itemH, double maxH, int total, bool dense) {
    _scrubDy = dy;
    final i = _scrubIndexFor(dy, itemH, maxH, total, dense);
    if (i != _scrubIndex) {
      setState(() => _scrubIndex = i);
      _scrubHaptic(); // 每划过一个点给一下，手感像滚轮
    }
  }

  void _endIndicatorDrag() {
    final target = _scrubIndex;
    if (mounted) {
      setState(() {
        _scrubbing = false;
        _scrubIndex = -1;
      });
    }
    if (target < 0 || target == _currentIndex) return;
    // 跨度太大时动画反而会从几千个页面上一路闪过去（既慢又卡），直接落位更干净
    if ((target - _currentIndex).abs() > _pageJumpThreshold) {
      try {
        _pageController.jumpToPage(target);
      } catch (_) {
        _goToPage(target);
      }
    } else {
      _goToPage(target);
    }
  }

  void _cancelIndicatorDrag() {
    if (mounted) {
      setState(() {
        _scrubbing = false;
        _scrubIndex = -1;
      });
    }
  }

  /// 竖屏/横屏通用的页码点指示器，四态：
  ///
  /// - **活跃态**（控件可见）：白点 + 半透明白点，正常亮度；
  /// - **休眠态**（控件隐藏后）：不新增任何控件，指示器自己淡到 35% 留守，
  ///   继续告诉用户"现在在第几个"，同时兼作恢复入口——点它跟点屏幕一样能唤回控件；
  /// - **拖动态**（手指按住上下划）：整条强制提亮到 100%（休眠态下也要看清在选第几个），
  ///   手指底下那个点变粗变亮、其余压暗到 16%，松手即跳到对应视频；
  /// - **气泡态**（拖动中）：跟着手指浮出「下标 / 总数 + 文件名」，见 [_buildScrubBubble]。
  ///
  /// 大列表（几百集）靠 [_scrubIndexFor] 的**比例映射**兜底：整条高度 = 整个播放列表，
  /// 一次拖动就能从第一集划到最后一集，不用"边缘加速"之类的补丁。
  ///
  /// 之所以不另做一个「恢复把手」：那会在同一块右边缘塞进两套视觉语言，
  /// 而且和这里的圆点位置几乎重叠，看着很脏。一个元素多种状态最干净。
  Widget _buildIndicator() {
    final total = _playList.videos.length;
    if (total <= 1) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final bottomPad = mq.padding.bottom;
    final safeH = mq.size.height - topPad - bottomPad;
    // 横屏时右侧边缘留给「收藏 / 踩」胶囊，页码点指示器移到左边缘
    final dotH = total <= 30 ? 8.0 : (total <= 80 ? 5.0 : 3.0);
    final activeH = dotH * 2;
    final vMargin = 1.0;
    final itemH = dotH + vMargin * 2;
    final maxH = safeH * 0.7;
    // 一眼排不下 → 整条当滚动条用（比例映射），见 [_scrubIndexFor]
    final dense = total * itemH > maxH;
    final boxTop = topPad + (safeH - maxH) / 2;
    final pickedH = (dotH * 2.6).clamp(dotH * 2, 22.0).toDouble();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _indicatorScrollCtrl;
      if (!c.hasClients) return;
      final anchor = (_scrubbing && dense) ? _scrubIndex : _currentIndex;
      final target = (anchor * itemH - maxH / 2 + itemH / 2)
          .clamp(0.0, c.position.maxScrollExtent);
      // 目标没变就别动：原来这里每帧都起一次 animateTo，长列表下纯烧帧
      if ((target - c.offset).abs() < 0.5) return;
      if (_scrubbing && dense) {
        c.jumpTo(target); // 拖动中要跟手，不能走动画
      } else {
        c.animateTo(target,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });

    final dormant = _hideUI; // 控件隐藏 → 指示器进入休眠态

    return Stack(children: [
      Positioned(
        left: _isLandscape ? 6.0 : null,
        right: _isLandscape ? null : 8.0,
        top: boxTop,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // 与点屏幕保持同一套语义：显示态=播放/暂停，隐藏态=唤回控件。
          // 顺带修掉一个老问题：原来点这块区域会被 ListView 吃掉，不触发任何操作。
          onTap: _onScreenTap,
          onVerticalDragStart: (d) => _onIndicatorDragStart(
              d.localPosition.dy, itemH, maxH, total, dense),
          onVerticalDragUpdate: (d) => _onIndicatorDragUpdate(
              d.localPosition.dy, itemH, maxH, total, dense),
          onVerticalDragEnd: (_) => _endIndicatorDrag(),
          onVerticalDragCancel: _cancelIndicatorDrag,
          child: AnimatedOpacity(
            // 拖动时强制提亮：休眠态（35%）下也得看清自己在选第几个
            opacity: (_scrubbing || !dormant) ? 1.0 : 0.35,
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              // 命中区加宽到 28（原来 12，手指太难按），圆点本身仍贴在原处：
              // 用 Align 把 12 宽的 ListView 靠到原来那一侧，视觉位置一像素不差
              height: maxH,
              width: _indicatorHitWidth,
              child: Align(
                alignment: _isLandscape
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: SizedBox(
                  width: 12,
                  child: ListView.builder(
                    controller: _indicatorScrollCtrl,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: total,
                    itemBuilder: (_, i) {
                      final active = i == _currentIndex;
                      final picked = _scrubbing && i == _scrubIndex;
                      // 竖向 ListView 给子项的是「宽度紧约束」（= 上面 SizedBox 的 12），
                      // 不套 Center 的话这里的 width:3 会被直接无视，每个点都会被拉成
                      // 12px 宽的白块，看起来就是一整条粗柱子而不是点——这也是
                      // 「明明开了却看不出有指示器」的元凶之一。
                      return Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 130),
                          curve: Curves.easeOut,
                          width: picked ? 6 : 3,
                          height: picked ? pickedH : (active ? activeH : dotH),
                          margin: EdgeInsets.symmetric(vertical: vMargin),
                          decoration: BoxDecoration(
                            color: picked
                                ? Colors.white
                                : (active
                                    ? Colors.white
                                    : (_scrubbing
                                        ? Colors.white.withOpacity(0.16)
                                        : Colors.white30)),
                            borderRadius: BorderRadius.circular(2),
                            // 只给选中点加一点点暗晕，亮画面上也立得出来
                            boxShadow: picked
                                ? [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.5),
                                        blurRadius: 6)
                                  ]
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      if (_scrubbing && _scrubIndex >= 0)
        _buildScrubBubble(boxTop, topPad, bottomPad),
    ]);
  }

  /// 拖动选片时跟着手指的气泡：**下标 / 总数**，下面再带一行文件名。
  ///
  /// 长列表里点只有 3px，光看圆点根本不知道选到了第几个，全靠这个气泡；
  /// 一行文件名则让"我要找的是那一集"变成看得见的事，不用松手去试。
  Widget _buildScrubBubble(double boxTop, double topPad, double bottomPad) {
    final mq = MediaQuery.of(context);
    final v = _playList.videos[_scrubIndex];
    final top = (boxTop + _scrubDy - 24.0)
        .clamp(topPad + 8.0, mq.size.height - bottomPad - 72.0);
    final gap = 8.0 + _indicatorHitWidth + 6.0;
    return Positioned(
      top: top,
      right: _isLandscape ? null : gap,
      left: _isLandscape ? gap : null,
      child: IgnorePointer(
        ignoring: true, // 纯提示，绝不能吃掉正在进行的拖动
        child: Container(
          constraints: const BoxConstraints(maxWidth: 168),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: _isLandscape
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Text('${_scrubIndex + 1} / ${_playList.videos.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(stripKnownVideoExtension(v.fileName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 工具栏爱心按钮：空心 ↔ 红心，收藏瞬间“弹跳放大 + 外围星光闪烁”。
///
/// 设计说明（对齐抖音手感）：
/// - 弹跳：520ms 内 easeOutCubic 冲到 1.35 倍，再用 easeOutBack 回落 1.0（带过冲回弹）；
/// - 星光：8 颗四角星沿半径 14→30 扩散并淡出，同时一圈红色光环扩张淡出，形成“bling”感；
/// - 取消收藏：只做回弹，不喷星光（语义更自然）；
/// - 触感：收藏成功时 HapticFeedback.lightImpact()。
class _HeartBtn extends StatefulWidget {
  final bool liked;
  final String label;
  final VoidCallback onTap;

  const _HeartBtn({
    required this.liked,
    required this.label,
    required this.onTap,
  });

  @override
  State<_HeartBtn> createState() => _HeartBtnState();
}

class _HeartBtnState extends State<_HeartBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
  bool _burst = false; // 本次动画是否喷星光（仅“收藏”时）

  @override
  void didUpdateWidget(covariant _HeartBtn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.liked != oldWidget.liked) {
      _burst = widget.liked;
      _c.forward(from: 0);
      if (widget.liked) {
        try {
          HapticFeedback.lightImpact();
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liked = widget.liked;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          // 0 → 0.6：冲到 1.35 倍；0.6 → 1：过冲回落到 1.0
          final bounce = t <= 0
              ? 1.0
              : (t < 0.6
                  ? 1 + 0.35 * Curves.easeOutCubic.transform(t / 0.6)
                  : 1.35 -
                      0.35 * Curves.easeOutBack.transform((t - 0.6) / 0.4));
          return Column(children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none, // 允许星光溢出按钮范围
                children: [
                  if (_burst && t > 0 && t < 1)
                    Positioned.fill(
                      child:
                          CustomPaint(painter: _SparklePainter(progress: t)),
                    ),
                  Transform.scale(scale: bounce, child: _icon(liked)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(widget.label,
                style: TextStyle(
                    color: liked ? Colors.red : Colors.white, fontSize: 11)),
          ]);
        },
      ),
    );
  }

  Widget _icon(bool liked) {
    if (!liked) {
      return const Icon(Icons.favorite_border, color: Colors.white, size: 32);
    }
    // 红心：径向渐变 + 外发光，与“飘心”特效风格统一
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x55FF3B30), blurRadius: 10, spreadRadius: 1),
        ],
      ),
      child: ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (b) => const RadialGradient(
          center: Alignment(0, -0.25),
          colors: [Color(0xFFFF8A80), Color(0xFFE53935)],
        ).createShader(b),
        child: const Icon(Icons.favorite, color: Colors.white, size: 32),
      ),
    );
  }
}

/// 爱心外围星光：8 颗四角星 + 一圈扩散光环，随进度扩散并淡出。
class _SparklePainter extends CustomPainter {
  final double progress;

  const _SparklePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final t = progress.clamp(0.0, 1.0);
    // 前 12% 留给爱心弹出，星光稍后出现
    final p = ((t - 0.12) / 0.88).clamp(0.0, 1.0);
    if (p <= 0 || p >= 1) return;
    final fade = (1 - p) * (p < 0.25 ? p / 0.25 : 1.0);
    final radius = 14 + 16 * Curves.easeOutCubic.transform(p);

    // 光环
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * (1 - p) + 0.4
        ..color = const Color(0xFFFF5252).withOpacity(0.55 * fade),
    );

    // 星光：8 颗四角星，交替大小形成闪烁节奏
    final starPaint = Paint()
      ..color = const Color(0xFFFFD54F).withOpacity(0.95 * fade);
    for (var i = 0; i < 8; i++) {
      final angle = i * (2 * pi / 8) + 0.35;
      final dist = radius * (0.85 + 0.15 * ((i % 3) / 2));
      final pos = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final r = (2.6 * (1 - p) + 0.6) * (i.isEven ? 1.0 : 0.7);
      _drawSparkle(canvas, pos, r, starPaint);
    }
  }

  /// 四角星（十字形）路径
  void _drawSparkle(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r * 1.8)
      ..quadraticBezierTo(c.dx + r * 0.28, c.dy - r * 0.28, c.dx + r * 1.8, c.dy)
      ..quadraticBezierTo(c.dx + r * 0.28, c.dy + r * 0.28, c.dx, c.dy + r * 1.8)
      ..quadraticBezierTo(c.dx - r * 0.28, c.dy + r * 0.28, c.dx - r * 1.8, c.dy)
      ..quadraticBezierTo(c.dx - r * 0.28, c.dy - r * 0.28, c.dx, c.dy - r * 1.8)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.progress != progress;
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
    // 蹦出 + 外围星光：星光在爱心弹出后出现，随之后半段淡出
    final sparkleProgress = (v / 0.75).clamp(0.0, 1.0);
    return Positioned(left: widget.position.dx - sz / 2, top: widget.position.dy - sz,
      child: Transform.rotate(angle: _rot, child: Opacity(opacity: op,
        child: SizedBox(
          width: sz,
          height: sz,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (v < 0.75)
                Positioned.fill(
                  child: Transform.scale(
                    scale: 1.35, // 星光比爱心略大一圈，形成外圈闪烁
                    child: CustomPaint(
                        painter: _SparklePainter(progress: sparkleProgress)),
                  ),
                ),
              Transform.scale(alignment: Alignment.bottomCenter, scale: sc,
                child: ShaderMask(blendMode: BlendMode.srcATop,
                  shaderCallback: (b) => const RadialGradient(center: Alignment(0, 0),
                    colors: [Color(0xffEF6F6F), Color(0xffF03E3E)]).createShader(b),
                  child: const Icon(Icons.favorite, size: sz, color: Colors.white))),
            ],
          ),
        ))));
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

/// ±10s 快进 / 快退按钮本体。
///
/// 它不再常驻，而是跟着中间那一行一起被 [_wakeCenterRow] 叫出来，
/// 停留 2 秒后随整行淡出（见 `_buildCenterControls` 里的 AnimatedOpacity）。
/// 正因为只露脸一小会儿，这里才敢保留圆形底盘 —— 短暂出现时「看得清」
/// 比「不抢眼」重要；填充取比常驻版本淡一档的 black38。
///
/// 按下时有 0.86 缩放 + 55% 透明度的回弹反馈（用 TweenAnimationBuilder，
/// 不依赖较高版本才有的 AnimatedScale，也不需要 AnimationController）。
class _SeekStepIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SeekStepIcon({required this.icon, required this.onTap});

  @override
  State<_SeekStepIcon> createState() => _SeekStepIconState();
}

class _SeekStepIconState extends State<_SeekStepIcon> {
  bool _pressed = false;

  static const double _minScale = 0.86;
  static const double _minOpacity = 0.55;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1.0, end: _pressed ? _minScale : 1.0),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        builder: (context, scale, child) {
          // scale: 1.0 ↔ 0.86 → 归一化成 0..1 的按压进度，顺带驱动透明度
          final t = ((scale - _minScale) / (1.0 - _minScale)).clamp(0.0, 1.0);
          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: _minOpacity + (1.0 - _minOpacity) * t,
              child: child,
            ),
          );
        },
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            // 恢复圆形底：因为它只在被叫出来的 2 秒里露脸（见 [_wakeCenterRow]），
            // 短暂出现时"看得清"比"不抢眼"重要；填充取 black38，比常驻时的
            // black45 淡一档，配 60% 的整体透明度，落在画面上已经很轻了。
            color: Colors.black38,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(widget.icon, color: const Color(0xF2FFFFFF), size: 26),
        ),
      ),
    );
  }
}

/// 一次「双击跳秒」的记录，只用来给涟漪定位（动画播完就被移除）。
class _SeekRipple {
  final Key key;
  final Offset pos;
  final bool left;
  final int seconds;
  const _SeekRipple(this.key, this.pos, this.left, this.seconds);
}

/// 双击屏幕左右侧时的**涟漪反馈**（YouTube / B 站同款）。
///
/// 存在感被刻意压到最低：只在手指离开的那一侧冒出来一个半透明圆，
/// 620ms 内「弹出 → 停一下 → 散掉」，结束即自我移除，不常驻、不挡主体。
/// 连续双击时由外部把 seconds 累加好传进来（10 → 20 → 30 秒）。
class _SeekRippleAnim extends StatefulWidget {
  final Offset position;
  final bool left;
  final int seconds;
  final VoidCallback onDone;
  const _SeekRippleAnim(
      {super.key,
      required this.position,
      required this.left,
      required this.seconds,
      required this.onDone});

  @override
  State<_SeekRippleAnim> createState() => _SeekRippleAnimState();
}

class _SeekRippleAnimState extends State<_SeekRippleAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
      duration: const Duration(milliseconds: 620), vsync: this);

  static const double _appearEnd = 0.18; // 弹出段
  static const double _holdEnd = 0.55; // 保持段结束，之后淡出
  static const double _size = 88.0;

  @override
  void initState() {
    super.initState();
    _ac.addListener(() {
      if (mounted) setState(() {});
    });
    _ac.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _ac.value;
    final op = v < _appearEnd
        ? v / _appearEnd
        : (v < _holdEnd
            ? 1.0
            : (1.0 - (v - _holdEnd) / (1.0 - _holdEnd)).clamp(0.0, 1.0));
    final sc = v < _appearEnd
        ? 0.85 + 0.15 * (v / _appearEnd)
        : 1.0 + 0.08 * ((v - _appearEnd) / (1.0 - _appearEnd));
    final size = MediaQuery.of(context).size;
    // 贴着那一侧固定放，纵向跟着手指落点，再夹进安全区避免顶到状态栏/进度条
    final x = widget.left ? 20.0 : (size.width - _size - 20.0);
    final maxY = (size.height - 180.0).clamp(80.0, size.height);
    final y = (widget.position.dy - _size / 2).clamp(80.0, maxY);
    return Positioned(
      left: x,
      top: y,
      child: IgnorePointer(
        ignoring: true, // 纯反馈，绝不能吃掉手势
        child: Opacity(
          opacity: op,
          child: Transform.scale(
            scale: sc,
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.42),
                shape: BoxShape.circle,
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        widget.left
                            ? Icons.fast_rewind_rounded
                            : Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 30),
                    const SizedBox(height: 2),
                    Text('${widget.seconds.abs()} 秒',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}