import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/disliked_video.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/database/table/file_viewing_record.dart';
import 'package:alist/database/table/video_viewing_record.dart';
import 'package:alist/entity/tiktok_play_list_model.dart';
import 'package:alist/util/alist_plugin.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/video_engine.dart';
import 'package:alist/util/subtitle/subtitle.dart';
import 'package:alist/widget/subtitle_view.dart';
import 'package:alist/util/log_utils.dart' as log;
import 'package:alist/util/stream_size_resolver.dart';
import 'package:alist/util/video_player_util.dart';
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

  VideoPlayerController? _controller; // 保留给 video_player 引擎
  VideoEngine? _engine; // 统一引擎接口
  late final SubtitleController _subtitleController;
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

  // 播放进度记忆
  VideoViewingRecord? _videoViewingRecord;
  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  static const _progressSaveInterval = Duration(seconds: 5);

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

  // Playlist filter
  bool _showPlaylistFilter = false;
  String _playlistFilter = '';
  final TextEditingController _playlistFilterController = TextEditingController();

  // Preload next video
  VideoPlayerController? _preloadController;
  int _preloadIdx = -1;
  Timer? _preloadTimer;

  // 后台 siblings 同步
  Timer? _playlistSyncTimer;

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
  static const double _defaultBrightness = 0.7;

  void _initBrightnessAndVolume() async {
    try {
      final saved = SpUtil.getDouble(AlistConstant.strmBrightness);
      if (saved != null && saved >= 0.1 && saved <= 1) {
        _currentBrightness = saved;
      } else {
        try {
          _currentBrightness = await ScreenBrightness().system;
        } catch (_) {
          try {
            _currentBrightness = await ScreenBrightness().current;
          } catch (_) {
            _currentBrightness = _defaultBrightness;
          }
        }
        if (_currentBrightness < 0.1) _currentBrightness = _defaultBrightness;
      }
    } catch (_) {
      _currentBrightness = _defaultBrightness;
    }
    try {
      ScreenBrightness().setScreenBrightness(_currentBrightness);
    } catch (_) {}
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
        _engine?.pause();
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
      // 全屏宽跳转时长随视频总时长自适应（短视频不会一拖到底，长视频不会拖一大段才几秒）
      final rangeMs =
          VideoPlayerUtil.seekRangeForDuration(_dur).inMilliseconds.toDouble();
      final deltaMs = (dx * rangeMs / _screenWidth).round();
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
      _engine?.seekTo(_seekTarget);
      if (_wasPlayingBeforeSeek) _engine?.play();
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
    _subtitleController = SubtitleController();
    WidgetsBinding.instance.addObserver(this);
    _playList = Get.arguments as TikTokPlayListModel;
    _currentIndex = _playList.initialIndex;
    _uiOpacity = SpUtil.getDouble(AlistConstant.tiktokUiOpacity, defValue: 1.0) ?? 1.0;

    _sortedVideos = List.from(_playList.videos);
    _updateVideoIndexMap();

    // 定期同步播放列表（后台 siblings 解析完成后会追加到 _playList.videos）
    // 首次延迟 500ms 后立即检查一次，之后每秒检查
    Future.delayed(const Duration(milliseconds: 500), _syncPlaylistFromSource);
    _playlistSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncPlaylistFromSource();
    });

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
    _subtitleController.clear();
    _progressTimer?.cancel();
    _landscapeHideTimer?.cancel();
    _preloadTimer?.cancel();
    _playlistSyncTimer?.cancel();
    _saveProgress(); // 退出时保存播放进度
    _engine?.dispose();
    _engine = null;
    _controller = null;
    _preloadController?.dispose();
    _preloadController = null;
    _playlistAnimController.dispose();
    _playlistFilterController.dispose();
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
  Future<void> _initController(int idx) async {
    if (idx < 0 || idx >= _playList.videos.length) return;
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      _engine?.dispose();
      _engine = null;
      _controller = null;
      if (mounted) setState(() {});

      final v = _playList.videos[idx];
      final url = v.videoUrl;
      if (url == null || url.isEmpty) {
        _isInitializing = false;
        return;
      }

      final httpHeaders = v.provider == 'BaiduNetdisk'
          ? <String, String>{'User-Agent': 'pan.baidu.com'}
          : <String, String>{};

      // 从 .strm 文件名推测远程视频格式，决定使用哪个解码引擎
      final remoteExt = _guessRemoteFormat(v.fileName);
      final ffmpegEnabled = SpUtil.getBool(AlistConstant.enableFfmpegSoftDecode, defValue: false) ?? false;
      final useMediaKit = ffmpegEnabled ||
          ['avi', 'wmv', 'rmvb', 'mpg', 'mpeg', 'vob', 'flv', 'divx', 'xvid', 'rm', 'asf', 'ogv', 'ogm'].contains(remoteExt);

      VideoEngine engine;
      if (useMediaKit) {
        final mkEngine = MediaKitEngine();
        mkEngine.createPlayer(); // 先创建 Player+VideoController，让 PlatformView 提前上树
        _engine = mkEngine;     // 立即设置，让 build 能渲染 Video widget
        if (mounted) setState(() {});
        await mkEngine.openMedia(url, httpHeaders: httpHeaders); // 再加载媒体
        engine = mkEngine;
      } else {
        final vpEngine = VideoPlayerEngine();
        await vpEngine.createFromNetwork(url, httpHeaders: httpHeaders);
        _controller = (vpEngine as VideoPlayerEngine).ctrl;
        engine = vpEngine;
        _engine = engine;
      }

      await engine.initialize();
      if (!mounted) {
        engine.dispose();
        _engine = null;
        _controller = null;
        _isInitializing = false;
        return;
      }

      engine.setLooping(_loopSingle);
      _isInitializing = false;

      // 加载上次播放进度并跳转
      if (!useMediaKit) {
        await _loadProgressAndSeek(idx, _controller!);
      }

      engine.play();
      _isPlaying = true;
      _recordViewing(idx);
      _startTimer();
      // 加载本地同名字幕（按视频名在字幕目录匹配 .srt）
      _subtitleController.loadSubtitle(remotePath: v.filePath, sign: v.sign);
      if (mounted) setState(() {});

      // Fetch real video size in background (non-blocking, cached)
      if (_playList.videos[idx].fileSize == null || _playList.videos[idx].fileSize! <= 0) {
        StreamSizeResolver.resolve(url).then((size) {
          if (size != null && size > 0 && mounted && _currentIndex == idx) {
            _playList.videos[idx].fileSize = size;
            _recordViewing(idx);
            if (mounted) setState(() {});
          }
        });
      }

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
    } catch (_) {}
  }

  void _disposePreload() {
    _preloadController?.dispose();
    _preloadController = null;
    _preloadIdx = -1;
  }

  /// 从 .strm 文件名推测远程视频格式
  /// "test.(avi).strm" → "avi", "movie.mp4.strm" → "mp4", "video.strm" → ""
  static String _guessRemoteFormat(String fileName) {
    // 去掉 .strm 后缀
    var name = fileName;
    if (name.toLowerCase().endsWith('.strm')) {
      name = name.substring(0, name.length - 5);
    }
    // 匹配结尾的 .(ext) 或 .ext
    final m = RegExp(r'\.\(?([a-zA-Z0-9]{2,5})\)?$').firstMatch(name);
    if (m != null) {
      return m.group(1)!.toLowerCase();
    }
    // 再试一次普通扩展名
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) {
      return name.substring(dot + 1).toLowerCase();
    }
    return '';
  }

  /// FFMPEG 软解：将播放路由到原生 PlayerActivity（IJK 内核）
  void _launchNativePlayer(int idx) async {
    try {
      final videosParams = <Map<String, String?>>[];
      for (final v in _playList.videos) {
        videosParams.add({
          "name": v.fileName,
          "remotePath": v.filePath,
          "url": v.videoUrl,
          "sign": v.sign,
          "provider": v.provider,
          "thumb": v.thumb,
          "size": v.fileSize?.toString(),
        });
      }
      final autoPipEnabled = SpUtil.getBool(AlistConstant.autoPipEnabled, defValue: true) ?? true;
      final ffmpegSoftDecode = SpUtil.getBool(AlistConstant.enableFfmpegSoftDecode, defValue: false) ?? false;
      await AlistPlugin.playVideoWithInternalPlayer(
        videosParams, idx, null, null,
        autoPipEnabled: autoPipEnabled,
        ffmpegSoftDecode: ffmpegSoftDecode,
      );
    } catch (e) {
      log.Log.e('StrmPlayer launchNative: $e');
    }
  }

  void _safePlay() {
    try {
      final engine = _engine;
      if (engine != null && engine.isInitialized) {
        engine.play();
        _isPlaying = true;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _safePause() {
    try {
      final engine = _engine;
      if (engine != null && engine.isInitialized) {
        engine.pause();
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

  // ═══════════════ 播放进度记忆 ═══════════════
  Future<void> _loadProgressAndSeek(int idx, VideoPlayerController ctrl) async {
    try {
      final v = _playList.videos[idx];
      final u = _userController.user.value;
      final record = await _database.videoViewingRecordDao
          .findRecordByPath(u.serverUrl, u.username, v.filePath);
      if (record != null && record.videoCurrentPosition > 0) {
        _videoViewingRecord = record;
        final seekTo = Duration(milliseconds: record.videoCurrentPosition);
        // 不跳到片尾（距结尾 3 秒内视为已看完）
        final duration = ctrl.value.duration;
        if (duration > Duration.zero &&
            seekTo >= duration - const Duration(seconds: 3)) {
          return;
        }
        await ctrl.seekTo(seekTo);
      } else {
        _videoViewingRecord = null;
      }
    } catch (_) {
      _videoViewingRecord = null;
    }
  }

  Future<void> _saveProgress() async {
    final engine = _engine;
    if (engine == null || !engine.isInitialized) return;
    final position = engine.position.inMilliseconds;
    final duration = engine.duration.inMilliseconds;
    if (duration <= 0) return;

    try {
      final v = _playList.videos[_currentIndex];
      final u = _userController.user.value;
      final existing = _videoViewingRecord;
      if (existing != null && existing.id != null) {
        _database.videoViewingRecordDao.updateRecord(VideoViewingRecord(
          id: existing.id,
          serverUrl: u.serverUrl,
          userId: u.username,
          videoSign: v.sign ?? '',
          path: v.filePath,
          videoDuration: duration,
          videoCurrentPosition: position,
        ));
      } else {
        final record = VideoViewingRecord(
          serverUrl: u.serverUrl,
          userId: u.username,
          videoSign: v.sign ?? '',
          path: v.filePath,
          videoDuration: duration,
          videoCurrentPosition: position,
        );
        final id = await _database.videoViewingRecordDao.insertRecord(record);
        _videoViewingRecord = VideoViewingRecord(
          id: id,
          serverUrl: record.serverUrl,
          userId: record.userId,
          videoSign: record.videoSign,
          path: record.path,
          videoDuration: record.videoDuration,
          videoCurrentPosition: record.videoCurrentPosition,
        );
      }
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
        final engine = _engine;
        if (engine != null && engine.isInitialized) {
          setState(() {
            _pos = engine.position;
            _dur = engine.duration;
          });
          _subtitleController.updatePosition(engine.position.inMilliseconds);

          // 定期保存播放进度
          final now = DateTime.now();
          if (now.difference(_lastProgressSave) >= _progressSaveInterval) {
            _lastProgressSave = now;
            _saveProgress();
          }

          if (engine.duration > Duration.zero &&
              engine.position >=
                  engine.duration -
                      const Duration(milliseconds: 500) &&
              !_completing) {
            _completing = true;
            _saveProgress();
            if (_loopSingle) {
              engine.seekTo(Duration.zero).then((_) {
                engine.play();
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

      _engine?.dispose();
      final vpEngine = VideoPlayerEngine();
      vpEngine.wrapController(ctrl);
      _engine = vpEngine;
      _controller = ctrl;
      _isInitializing = false;

      ctrl.setLooping(_loopSingle);
      ctrl.play();
      _isPlaying = true;
      _recordViewing(idx);
      _startTimer();
      _loadStates(idx);
      if (mounted) setState(() {});

      // 预加载阶段跳过了 size 获取，切换到该视频时补上
      final v = _playList.videos[idx];
      if ((v.fileSize == null || v.fileSize! <= 0) && v.videoUrl != null) {
        StreamSizeResolver.resolve(v.videoUrl!).then((size) {
          if (size != null && size > 0 && mounted && _currentIndex == idx) {
            v.fileSize = size;
            _recordViewing(idx);
            if (mounted) setState(() {});
          }
        });
      }

      _schedulePreload(idx);
    } else {
      _disposePreload();
      await _initController(idx);
      _loadStates(idx);
    }
  }

  void _togglePlayPause() {
    try {
      final engine = _engine;
      if (engine == null || !engine.isInitialized) return;
      if (_isPlaying) {
        engine.pause();
        _isPlaying = false;
        _cancelLandscapeAutoHide();
      } else {
        engine.play();
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
    _isLandscape = !_isLandscape;
    if (!_isLandscape) {
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
    if (mounted) setState(() {});
  }

  void _toggleLoop() {
    _loopSingle = !_loopSingle;
    try {
      _engine?.setLooping(_loopSingle);
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
        _engine
            ?.seekTo(Duration(milliseconds: (val * _dur.inMilliseconds).round()));
      }
    } catch (_) {}
    // 延迟 500ms 再恢复轮询，等待 seek 完成（WMV/ASF 等老格式 seek 慢，
    // 立即轮询会读到过渡态 position=0 或 duration，导致进度条跳到首/尾）
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _startTimer();
    });
  }

  // ═══════════════ Reload ═══════════════
  Future<void> _reloadAtCurrentFrame() async {
    final savedPos = _pos;
    final v = _playList.videos[_currentIndex];
    final url = v.videoUrl;
    if (url == null || url.isEmpty) return;

    final httpHeaders = v.provider == 'BaiduNetdisk'
        ? <String, String>{'User-Agent': 'pan.baidu.com'}
        : <String, String>{};

    _progressTimer?.cancel();
    SmartDialog.showLoading(msg: '重新加载中...');

    try {
      await _engine?.reload(url, savedPos, httpHeaders: httpHeaders);
      _startTimer();
      SmartDialog.dismiss();
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('重载失败');
    }
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

      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ui.Image image =
          await boundary.toImage(pixelRatio: devicePixelRatio);

      // 裁剪出视频实际渲染区域，去除 Center/AspectRatio 产生的透明填充
      ui.Image finalImage = image;
      final engine = _engine;
      if (engine != null && engine.isInitialized) {
        final videoAspectRatio = engine.aspectRatio;
        final imgW = image.width.toDouble();
        final imgH = image.height.toDouble();
        final boundaryAspectRatio = imgW / imgH;

        double cropX = 0, cropY = 0, cropW = imgW, cropH = imgH;

        if (videoAspectRatio > boundaryAspectRatio) {
          // 视频比屏幕更宽（横屏视频在竖屏中）—— 裁掉上下黑边
          cropH = imgW / videoAspectRatio;
          cropY = (imgH - cropH) / 2;
        } else {
          // 视频比屏幕更窄（竖屏视频在竖屏中）—— 裁掉左右黑边
          cropW = imgH * videoAspectRatio;
          cropX = (imgW - cropW) / 2;
        }

        if ((cropW - imgW).abs() > 1 || (cropH - imgH).abs() > 1) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, cropW, cropH));
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(cropX, cropY, cropW, cropH),
            Rect.fromLTWH(0, 0, cropW, cropH),
            Paint(),
          );
          final croppedImage = await recorder.endRecording().toImage(
            cropW.toInt(),
            cropH.toInt(),
          );
          image.dispose();
          finalImage = croppedImage;
        }
      }

      final ByteData? byteData =
          await finalImage.toByteData(format: ui.ImageByteFormat.png);
      finalImage.dispose();
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
  void _syncPlaylistFromSource() {
    if (!mounted) return;
    if (_sortedVideos.length != _playList.videos.length) {
      setState(() {
        _sortedVideos = List.from(_playList.videos);
        _updateVideoIndexMap();
      });
    }
  }

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

  void _syncCurrentIndexAfterSort(String currentPath) {
    final sortedIdx = _sortedVideos.indexWhere((v) => v.filePath == currentPath);
    if (sortedIdx >= 0) {
      _currentIndex = _videoIndexMap[sortedIdx] ?? sortedIdx;
    }
  }

  void _togglePlaylist() {
    if (_isPlaylistVisible) {
      _playlistAnimController.reverse();
      setState(() {
        _isPlaylistVisible = false;
        _showPlaylistFilter = false;
        _playlistFilter = '';
        _playlistFilterController.clear();
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
        _buildPortraitCenterControls(),
        if (!(_hideUI && _isLandscape)) _buildTopBar(),
        if (!_hideUI) _buildToolBar(),
        _buildProgress(),
        SubtitleView(controller: _subtitleController, bottomOffset: _isLandscape ? 60 : 150),
        if (!_hideUI && !_isLandscape) _buildBottomInfo(),
        if (!_hideUI && _playList.videos.length > 1 && !_isLandscape)
          _buildFloatingSwitchButton(),
        if (!_hideUI && _playList.videos.length > 1 && _isLandscape)
          _buildLandscapeFloatingSwitchButton(),
        if (!_hideUI && _isLandscape) _buildLandscapeCenterControls(),
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
    final engine = _engine;
    if (engine != null && engine.isInitialized) {
      // media_kit 引擎：Video 是 PlatformView，必须一直在树里，撑满
      if (engine is MediaKitEngine) {
        return Stack(
          fit: StackFit.expand,
          children: [
            engine.buildVideoWidget(),
            if (engine.isBuffering)
              const Center(
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
          ],
        );
      }
      // video_player 引擎保持原有布局
      if (_isLandscape) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: engine.videoSize.width,
              height: engine.videoSize.height,
              child: engine.buildVideoWidget(),
            ),
          ),
        );
      }
      return Center(
          child:
              AspectRatio(aspectRatio: engine.aspectRatio, child: engine.buildVideoWidget()));
    }
    return const Center(
        child: CircularProgressIndicator(
            color: Colors.white, strokeWidth: 2));
  }

  Widget _buildPauseIcon() {
    if (_isPlaying || _isLandscape || !_hideUI) return const SizedBox.shrink();
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

  Widget _buildPortraitCenterControls() {
    if (_isLandscape || _hideUI || _isPlaying) return const SizedBox.shrink();
    return Center(
      child: Opacity(
        opacity: _uiOpacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _centerCtrlBtn(
              icon: Icons.replay_10_rounded,
              onTap: () {
                final target = _pos - const Duration(seconds: 10);
                _engine?.seekTo(target < Duration.zero ? Duration.zero : target);
                setState(() {});
              },
              size: 44,
            ),
            const SizedBox(width: 28),
            GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(34)),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white70,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(width: 28),
            _centerCtrlBtn(
              icon: Icons.forward_10_rounded,
              onTap: () {
                final target = _pos + const Duration(seconds: 10);
                final max = _dur;
                _engine?.seekTo(target > max ? max : target);
                setState(() {});
              },
              size: 44,
            ),
          ],
        ),
      ),
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
                    _toolbarBtn(
                        icon: Icons.refresh_rounded,
                        label: '重载',
                        color: Colors.white,
                        onTap: _reloadAtCurrentFrame),
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
                        color: Colors.white.withOpacity(0.7), size: 20),
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
                GestureDetector(
                  onTap: _reloadAtCurrentFrame,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.refresh_rounded,
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

  Widget _buildLandscapeFloatingSwitchButton() {
    final sortedIdx = _getCurrentSortedIndex();
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
                  onTap: sortedIdx > 0
                      ? () {
                          final prev = _sortedVideos[sortedIdx - 1];
                          final origIdx = _playList.videos.indexWhere(
                              (v) => v.filePath == prev.filePath);
                          if (origIdx >= 0) _playAt(origIdx);
                        }
                      : null,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    child: Icon(Icons.skip_previous_rounded,
                        color: sortedIdx > 0
                            ? Colors.white
                            : Colors.white38,
                        size: 16),
                  ),
                ),
                Text(
                  '${sortedIdx + 1}/${_sortedVideos.length}',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
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
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    child: Icon(Icons.skip_next_rounded,
                        color:
                            sortedIdx < _sortedVideos.length - 1
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

  Widget _buildLandscapeCenterControls() {
    return Center(
      child: Opacity(
        opacity: _uiOpacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _centerCtrlBtn(
              icon: Icons.replay_10_rounded,
              onTap: () {
                final target = _pos - const Duration(seconds: 10);
                _engine?.seekTo(target < Duration.zero ? Duration.zero : target);
              },
            ),
            const SizedBox(width: 48),
            GestureDetector(
              onTap: _togglePlayPause,
              child: Icon(
                _isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
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
                _engine?.seekTo(target > max ? max : target);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _centerCtrlBtn({
    required IconData icon,
    required VoidCallback onTap,
    double size = 48,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: Colors.white.withOpacity(0.85), size: size),
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
    final filteredVideos = _playlistFilter.isEmpty
        ? _sortedVideos
        : _sortedVideos.where((v) {
            final nameWithoutExt = v.fileName.contains('.')
                ? v.fileName.substring(0, v.fileName.lastIndexOf('.'))
                : v.fileName;
            return nameWithoutExt.toLowerCase().contains(_playlistFilter.toLowerCase());
          }).toList();
    final drawerWidth = MediaQuery.of(context).size.width * 0.7;

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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: const BoxDecoration(
                    border: Border(
                        bottom:
                            BorderSide(color: Colors.white24))),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Text(
                            _playlistFilter.isEmpty
                                ? '播放列表 (${_getCurrentSortedIndex() + 1}/${_sortedVideos.length})'
                                : '筛选结果 (${filteredVideos.length})',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold))),
                    IconButton(
                        icon: Icon(
                            _showPlaylistFilter ? Icons.search_off : Icons.search,
                            color: Colors.white,
                            size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () {
                          setState(() {
                            _showPlaylistFilter = !_showPlaylistFilter;
                            if (!_showPlaylistFilter) {
                              _playlistFilter = '';
                              _playlistFilterController.clear();
                            }
                          });
                        }),
                    IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white,
                            size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: _togglePlaylist),
                  ]),
                  if (_showPlaylistFilter)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _playlistFilterController,
                            autofocus: true,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: '输入关键词筛选…',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Colors.white24),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Colors.blue),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.08),
                            ),
                            onSubmitted: (_) {
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _playlistFilter = _playlistFilterController.text;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 36,
                          child: FilledButton(
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _playlistFilter = _playlistFilterController.text;
                              });
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: const Text('确定', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ]),
                    ),
                ]),
              ),
              if (filteredVideos.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('没有匹配的视频', style: TextStyle(color: Colors.white38, fontSize: 14)),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredVideos.length,
                    itemBuilder: (_, idx) {
                      final item = filteredVideos[idx];
                      final originalIdx = _sortedVideos.indexOf(item);
                      final isPlaying = _playList.videos[_currentIndex].filePath == item.filePath;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        leading: Icon(
                            isPlaying
                                ? Icons.play_arrow
                                : Icons.video_file,
                            size: 18,
                            color: isPlaying
                                ? Colors.blue
                                : Colors.white70),
                        title: Text(
                          item.fileName,
                          style: TextStyle(
                              color:
                                  isPlaying ? Colors.blue : Colors.white,
                              fontSize: 12,
                              fontWeight: isPlaying
                                  ? FontWeight.bold
                                  : FontWeight.normal),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isPlaying
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius:
                                        BorderRadius.circular(4)),
                                child: const Text("播放中",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9)))
                            : null,
                        selected: isPlaying,
                        selectedTileColor:
                            Colors.blue.withOpacity(0.1),
                        onTap: () {
                          final mapIdx = _videoIndexMap[originalIdx] ?? originalIdx;
                          _togglePlaylist();
                          _playAt(mapIdx);
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
                                final currentPath = _playList.videos[_currentIndex].filePath;
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
                                _syncCurrentIndexAfterSort(currentPath);
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
                                final currentPath = _playList.videos[_currentIndex].filePath;
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
                                _syncCurrentIndexAfterSort(currentPath);
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
