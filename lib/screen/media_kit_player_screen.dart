import 'dart:async';
import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/disliked_video.dart';
import 'package:alist/screen/disliked_videos_screen.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/screen/video_player_screen.dart';
import 'package:alist/util/alist_plugin.dart';
import 'package:alist/util/subtitle/subtitle.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/video_player_util.dart';
import 'package:alist/widget/subtitle_view.dart' as subtitle_widget;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

enum VerticalDragType { brightness, volume }
enum PlayerSheet { none, playbackSpeed, more, playlist }
enum PlayDirection { next, previous }
enum VideoFillMode { contain, cover, fill }

class MediaKitPlayerScreen extends StatefulWidget {
  const MediaKitPlayerScreen({super.key});
  @override
  State<MediaKitPlayerScreen> createState() => _MediaKitPlayerScreenState();
}

class _MediaKitPlayerScreenState extends State<MediaKitPlayerScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final List<Map<String, String?>> _videos;
  late int _index;
  late final Player _player;
  late final VideoController _controller;
  late final Map<String, String> _headers;
  final AlistDatabaseController _database = Get.find();

  bool _showControls = true;
  Timer? _hideTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _playbackError = false;
  // 记录上次播放方向，用于播放失败时决定跳过方向
  PlayDirection _lastPlayDirection = PlayDirection.next;
  StreamSubscription? _posSub, _durSub, _playSub, _bufSub, _errSub, _playAtSub, _compSub;
  // 播放重试计数器，同一个视频最多重试2次（共尝试3次）
  int _retryCount = 0;
  static const int _maxRetries = 2;
  bool _isDraggingSlider = false;
  bool _seeking = false;
  Duration _seekTarget = Duration.zero;
  Duration _seekStartPos = Duration.zero;
  double _horizontalDragStartX = 0;
  bool _isSwitching = false;
  late final AnimationController _playlistAnimationController;
  late final Animation<Offset> _playlistSlideAnimation;
  bool _isFullscreen = false, _isCapturing = false, _isFavorite = false, _isDisliked = false;

  // Playlist filter
  bool _showPlaylistFilter = false;
  String _playlistFilter = '';
  final TextEditingController _playlistFilterController = TextEditingController();
  VerticalDragType? _verticalDragType;
  bool _verticalDragging = false;
  double _systemVolumeValue = 0.5, _systemVolumeDragStartValue = 0.5;
  double _systemBrightnessValue = 0.5, _systemBrightnessDragStartValue = 0.5;
  double _verticalDragStartY = 0, _screenWidth = 0, _screenHeight = 0;
  bool _nameSortAscending = true, _sizeSortAscending = false;
  int _doubleTapSeekAmount = 0;
  bool _isDoubleTapSeekingLeft = false, _isDoubleTapSeekingRight = false;
  Timer? _doubleTapResetTimer;
  PlayerSheet _activeSheet = PlayerSheet.none;
  double _playbackSpeed = 1.0;
  bool _showSpeedIndicator = false;
  Timer? _speedIndicatorTimer;
  int _repeatMode = 0;
  bool _shuffleEnabled = false;
  bool _areControlsLocked = false;
  bool _showBrightnessSlider = false, _showVolumeSlider = false, _swapVolumeAndBrightness = false;
  VideoFillMode _videoFillMode = VideoFillMode.contain;
  late final SubtitleController _subtitleController;

  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.black,
      systemNavigationBarDividerColor: Colors.black,
      statusBarColor: Colors.transparent,
    ));
  }

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map<String, dynamic>;
    _videos = List<Map<String, String?>>.from(args['videos'] as List);
    _index = args['index'] as int? ?? 0;
    _headers = Map<String, String>.from(args['headers'] ?? {});
    _player = Player(configuration: const PlayerConfiguration(
      bufferSize: 64 * 1024 * 1024,
      // 加大分析时长，提升对老格式/未知格式容器的识别能力
      // libmpv 默认 5 秒，老视频容器可能需要更长
      protocolWhitelist: ['http', 'https', 'tcp', 'tls', 'rtmp', 'rtsp', 'data', 'file'],
    ));
    _controller = VideoController(_player);
    // 配置 libmpv 老格式兼容性选项
    _configureForOldFormats();
    _initBrightnessAndVolume();
    _checkFavoriteStatus();
    _checkDislikedStatus();
    _hideSystemUI();
    // 初始化字幕控制器
    _subtitleController = SubtitleController();
    WidgetsBinding.instance.addObserver(this);
    _posSub = _player.stream.position.listen((p) {
      if (mounted && !_isDraggingSlider) setState(() => _position = p);
      // 同步播放进度到字幕控制器
      _subtitleController.updatePosition(p.inMilliseconds);
    });
    _durSub = _player.stream.duration.listen((d) { if (mounted) setState(() => _duration = d); });
    _playSub = _player.stream.playing.listen((p) { if (mounted) setState(() => _playing = p); if (p) _startHideTimer(); });
    _bufSub = _player.stream.buffering.listen((b) { if (mounted) setState(() => _buffering = b); });
    _compSub = _player.stream.completed.listen((completed) {
      if (completed && mounted && _videos.length > 1) {
        if (_repeatMode == 1) _playAt(_index);
        else if (_index < _videos.length - 1) _playAt(_index + 1);
        else if (_repeatMode == 2) _playAt(0);
      }
    });
    _errSub = _player.stream.error.listen((error) {
      if (!mounted) return;
      // 网络流（如 .strm 解析出的远程 URL）需要更长的缓冲时间，
      // 1.5 秒内可能还在握手/缓冲，误判为播放失败会触发无意义的重试
      final currentUrl = _videos[_index]["url"] ?? "";
      final isNetworkStream = currentUrl.startsWith("http://") || currentUrl.startsWith("https://");
      final delayMs = isNetworkStream ? 8000 : 1500;
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        // 如果播放器仍在正常播放（position 在推进），说明是非致命错误，忽略
        if (_playing && _position.inMilliseconds > 0) return;
        setState(() { _playbackError = true; _buffering = false; _isSwitching = false; });
        // 先尝试重试当前视频（最多重试2次）
        if (_retryCount < _maxRetries) {
          _retryCount++;
          final delaySec = _retryCount;
          _showToast("播放出错，${delaySec}秒后重试($_retryCount/$_maxRetries)...");
          Future.delayed(Duration(seconds: delaySec), () {
            if (mounted) _playAt(_index);
          });
          return;
        }
        // 重试耗尽，跳过此视频
        _retryCount = 0;
        _showToast("播放失败，跳过此视频");
      // 根据上次播放方向决定跳过方向
      if (_lastPlayDirection == PlayDirection.next) {
        // 尝试播放下一个
        if (_index < _videos.length - 1) {
          _lastPlayDirection = PlayDirection.next;
          _playAt(_index + 1);
          return;
        }
        // 如果没有下一个，尝试播放上一个
        if (_index > 0) {
          _lastPlayDirection = PlayDirection.previous;
          _playAt(_index - 1);
          return;
        }
      } else {
        // 尝试播放上一个
        if (_index > 0) {
          _lastPlayDirection = PlayDirection.previous;
          _playAt(_index - 1);
          return;
        }
        // 如果没有上一个，尝试播放下一个
        if (_index < _videos.length - 1) {
          _lastPlayDirection = PlayDirection.next;
          _playAt(_index + 1);
          return;
        }
      }
      // 没有其他视频可选，关闭播放器
      _showToast("没有可播放的视频了");
      Get.back();
    }); // end Future.delayed
    }); // end listen
    WidgetsBinding.instance.addPostFrameCallback((_) => _playAt(_index));
    _playlistAnimationController = AnimationController(duration: const Duration(milliseconds: 250), vsync: this);
    _playlistSlideAnimation = Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _playlistAnimationController, curve: Curves.easeOutCubic));
  }

  void _configureForOldFormats() {
    try {
      final native = _player.platform as dynamic;

      // ==================== 硬件解码配置 ====================
      // 优先尝试硬解（GPU 解码远快于纯软解），失败自动回退软解
      // auto-safe 会自动跳过已知不兼容的硬解驱动，兼顾性能与兼容性
      native.setProperty('hwdec', 'auto-safe');

      // ==================== 视频解码容错配置 ====================
      native.setProperty('vd-lavc-dr', 'no');
      // 明确分配 4 个解码线程，避免 auto 策略对 WMV/ASF 只分 1~2 线程
      native.setProperty('vd-lavc-threads', '4');
      native.setProperty('vd-lavc-error-resilience', '1');

      // ==================== 容器格式探测配置 ====================
      // 增大分析时长到5秒，帮助识别老格式和复杂容器
      native.setProperty('demuxer-lavf-analyzeduration', '5000000');
      // 增大探测大小到50MB，覆盖更多格式场景
      native.setProperty('demuxer-lavf-probesize', '50000000');
      // 允许所有解封装器
      native.setProperty('demuxer-lavf-format', '');
      // 网络超时配置（使用 mpv 专有属性，确保兼容各底层桥接）
      native.setProperty('network-timeout', '30');

      // ==================== 缓存配置 ====================
      native.setProperty('cache', 'yes');
      // 网络流缓存 10 秒即可，30 秒过大导致内存压力 + 起播慢
      native.setProperty('cache-secs', '10');
      native.setProperty('demuxer-max-bytes', '50MiB');
      native.setProperty('demuxer-max-back-bytes', '10MiB');

      // ==================== 音频解码容错配置 ====================
      native.setProperty('ad-lavc-dr', 'no');
      native.setProperty('ad-lavc-codec-whitelist', '');
      native.setProperty('ad-lavc-err-detect', '0');
      native.setProperty('audio-file-auto', 'fuzzy');
      native.setProperty('audio-pitch-correction', 'yes');
      // 音频同步容错
      native.setProperty('audio-stream-silence', 'yes');
      native.setProperty('audio-wait-open', 'yes');

      // ==================== 同步与渲染配置 ====================
      // 视频跟音频时钟同步，避免画面卡住不动
      native.setProperty('video-sync', 'audio');
      // 精确 seek：对 WMV/ASF 无关键帧索引的容器尤为重要，seek 后更快恢复
      native.setProperty('hr-seek', 'yes');
      // 双端丢帧（decoder + vo），软解跟不上时平滑降帧而非冻住
      native.setProperty('framedrop', 'decoder+vo');

      // ==================== 字幕容错 ====================
      native.setProperty('sub-auto', 'fuzzy');
      native.setProperty('sub-codepage', 'auto');

      // ==================== 高分辨率视频兼容性 ====================
      // 确保视频不被错误的像素宽高比缩放（部分4K视频PAR异常导致画面过小）
      native.setProperty('correct-pts', 'yes');
      native.setProperty('video-aspect-override', '0');
      native.setProperty('video-unscaled', 'no');
    } catch (_) {
      // 非 NativePlayer 平台静默忽略
    }
  }

  Future<void> _initBrightnessAndVolume() async {
    try {
      try {
        _systemBrightnessValue = await ScreenBrightness().system;
      } catch (_) {
        _systemBrightnessValue = await ScreenBrightness().current;
      }
      if (_systemBrightnessValue < 0.1) _systemBrightnessValue = 1.0;
    } catch (_) { _systemBrightnessValue = 1.0; }
    try { _systemVolumeValue = await VolumeController().getVolume(); } catch (_) { _systemVolumeValue = 0.5; }
  }

  @override void didChangeMetrics() { Future.delayed(const Duration(milliseconds: 800), () { if (mounted) _hideSystemUI(); }); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) _hideSystemUI(); }

  @override
  void dispose() {
    _hideTimer?.cancel(); _doubleTapResetTimer?.cancel(); _speedIndicatorTimer?.cancel();
    _posSub?.cancel(); _durSub?.cancel(); _playSub?.cancel(); _bufSub?.cancel(); _errSub?.cancel(); _playAtSub?.cancel(); _compSub?.cancel();
    _subtitleController.clear();
    WidgetsBinding.instance.removeObserver(this);
    // Fully exit immersive mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
    if (_isFullscreen) SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    // 释放系统亮度控制权，恢复系统默认亮度调节
    try {
      ScreenBrightness().resetScreenBrightness();
    } catch (_) {}
    _player.dispose(); _playlistAnimationController.dispose(); _playlistFilterController.dispose();
    super.dispose();
  }

  void _playAt(int index) {
    if (index < 0 || index >= _videos.length) return;
    // 切换到新视频时重置重试计数
    if (index != _index) _retryCount = 0;
    _playAtSub?.cancel(); _playAtSub = null;
    setState(() { _index = index; _isSwitching = true; _buffering = true; _playbackError = false; _playbackSpeed = 1.0; });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      final url = _videos[index]["url"] ?? "";
      if (url.isEmpty) { _showToast("视频地址为空"); setState(() { _isSwitching = false; _buffering = false; }); return; }
      try {
        final httpHeaders = _headers.isNotEmpty ? _headers : null;
        _player.open(Media(url, httpHeaders: httpHeaders), play: true);
        // 尝试加载同名字幕文件（仅对本地文件生效）
        _loadSubtitleForCurrentVideo();
      } catch (e) {
        if (mounted) { setState(() { _playbackError = true; _isSwitching = false; _buffering = false; }); _showToast("播放失败: $e"); }
        return;
      }
      _closeSheetAndPanel(); _checkFavoriteStatus(); _checkDislikedStatus();
      // Combined conditions: video params ready + buffering finished + 150ms delay
      bool videoParamsReady = false;
      bool bufferingReady = false;
      void tryRemoveMask() {
        if (videoParamsReady && bufferingReady && mounted) {
          _playAtSub?.cancel();
          _playAtSub = null;
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) setState(() => _isSwitching = false);
          });
        }
      }
      _playAtSub = _player.stream.videoParams.listen((params) {
        if (params != null && (params.dw ?? 0) > 0 && (params.dh ?? 0) > 0) {
          videoParamsReady = true;
          tryRemoveMask();
        }
      });
      _bufSub?.cancel();
      _bufSub = _player.stream.buffering.listen((b) {
        if (!b) {
          bufferingReady = true;
          tryRemoveMask();
        }
      });
      // Safety net: remove mask after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (_playAtSub != null && mounted) {
          _playAtSub?.cancel();
          _playAtSub = null;
          if (mounted) setState(() => _isSwitching = false);
        }
      });
    });
  }

  /// 加载当前视频对应的字幕文件
  /// 仅对本地文件（localPath）有效，远程流媒体暂不支持同名字幕匹配
  void _loadSubtitleForCurrentVideo() {
    final localPath = _videos[_index]["localPath"];
    final remotePath = _videos[_index]["remotePath"];
    final sign = _videos[_index]["sign"];
    _subtitleController.loadSubtitle(
      videoPath: localPath,
      remotePath: remotePath,
      sign: sign,
    );
  }

  void _openSheet(PlayerSheet sheet) {
    if (_activeSheet == sheet) { _closeSheetAndPanel(); return; }
    setState(() { _activeSheet = sheet; _showControls = false; });
    if (sheet == PlayerSheet.playlist) _playlistAnimationController.forward();
    _startHideTimer();
  }

  void _closeSheetAndPanel() {
    setState(() { _activeSheet = PlayerSheet.none; _showControls = true; });
    _playlistAnimationController.reverse(); _startHideTimer();
  }
  void _hidePlaylist() { _showPlaylistFilter = false; _playlistFilter = ''; _playlistFilterController.clear(); _closeSheetAndPanel(); }

  Future<void> _setPlaybackSpeed(double speed) async {
    try {
      await _player.setRate(speed);
      if (mounted) setState(() => _playbackSpeed = speed);
      _showToast('${speed.toStringAsFixed(2)}x');
      setState(() => _showSpeedIndicator = true);
      _speedIndicatorTimer?.cancel();
      _speedIndicatorTimer = Timer(const Duration(seconds: 1), () { if (mounted) setState(() => _showSpeedIndicator = false); });
    } catch (_) {}
  }

  Future<void> _captureFrame() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final screenshot = await _controller.player.screenshot();
      if (screenshot == null) { _showToast("截图失败"); return; }
      final result = await ImageGallerySaver.saveImage(screenshot, quality: 100, name: "alist_${DateTime.now().millisecondsSinceEpoch}");
      _showToast(result['isSuccess'] == true ? "截图已保存到相册" : "保存失败");
    } catch (e) { _showToast("截图失败: $e"); }
    finally { setState(() => _isCapturing = false); }
  }

  void _showToast(String msg) { SmartDialog.showToast(msg); }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _activeSheet == PlayerSheet.none) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    if (_areControlsLocked) return;
    if (_activeSheet != PlayerSheet.none) { _closeSheetAndPanel(); return; }
    if (_showControls) { _hideTimer?.cancel(); setState(() => _showControls = false); }
    else { setState(() => _showControls = true); _startHideTimer(); }
  }

  void _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
    setState(() => _isFullscreen = !_isFullscreen); _hideSystemUI();
  }

  String _fmt(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours; final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _switchToNativePlayer() {
    _closeSheetAndPanel();
    final items = _videos.map((v) => VideoItem(name: v["name"] ?? "", localPath: v["localPath"], remotePath: v["remotePath"] ?? "", sign: v["sign"], provider: v["provider"], thumb: v["thumb"], size: int.tryParse(v["size"] ?? ""), modifiedMilliseconds: int.tryParse(v["modifiedMilliseconds"] ?? ""))).toList();
    _player.dispose(); VideoPlayerUtil.go(items, _index, null); Get.back();
  }

  void _checkFavoriteStatus() async {
    final remotePath = _videos[_index]["remotePath"] ?? ""; if (remotePath.isEmpty) return;
    try {
      final user = Get.find<UserController>().user.value;
      final fav = await _database.favoriteDao.findByPath(user.serverUrl, user.username, remotePath);
      if (mounted) setState(() => _isFavorite = fav != null);
    } catch (_) { if (mounted) setState(() => _isFavorite = false); }
  }

  void _toggleFavorite() async {
    final v = _videos[_index]; final rp = v["remotePath"] ?? ""; final nm = v["name"] ?? ""; if (rp.isEmpty) return;
    try {
      final user = Get.find<UserController>().user.value;
      if (_isFavorite) { await _database.favoriteDao.deleteByPath(user.serverUrl, user.username, rp); _showToast('已取消收藏'); }
      else {
        await _database.favoriteDao.insertRecord(Favorite(isDir: false, serverUrl: user.serverUrl, userId: user.username, remotePath: rp, name: nm, path: rp, size: int.tryParse(v["size"] ?? "0") ?? 0, sign: v["sign"], thumb: v["thumb"], modified: int.tryParse(v["modifiedMilliseconds"] ?? "0") ?? 0, provider: v["provider"] ?? "", createTime: DateTime.now().millisecondsSinceEpoch));
        _showToast('已添加到收藏');
      }
      if (mounted) setState(() => _isFavorite = !_isFavorite);
    } catch (e) { _showToast('操作失败: $e'); }
  }

  void _checkDislikedStatus() async {
    final remotePath = _videos[_index]["remotePath"] ?? ""; if (remotePath.isEmpty) return;
    try {
      final user = Get.find<UserController>().user.value;
      final disliked = await _database.dislikedVideoDao.findByPath(user.serverUrl, user.username, remotePath);
      if (mounted) setState(() => _isDisliked = disliked != null);
    } catch (_) { if (mounted) setState(() => _isDisliked = false); }
  }

  void _toggleDisliked() async {
    final v = _videos[_index]; final rp = v["remotePath"] ?? ""; final nm = v["name"] ?? ""; if (rp.isEmpty) return;
    try {
      final user = Get.find<UserController>().user.value;
      if (_isDisliked) {
        await _database.dislikedVideoDao.deleteByPath(user.serverUrl, user.username, rp);
        await DislikeLog.append('取消标记(MPV)', nm, rp, user.username, user.serverUrl);
        _showToast('已取消不喜欢标记');
      } else {
        await _database.dislikedVideoDao.insertRecord(DislikedVideo(
          serverUrl: user.serverUrl,
          userId: user.username,
          remotePath: rp,
          name: nm,
          path: rp,
          size: int.tryParse(v["size"] ?? "0") ?? 0,
          sign: v["sign"],
          thumb: v["thumb"],
          modified: int.tryParse(v["modifiedMilliseconds"] ?? "0") ?? 0,
          provider: v["provider"] ?? "",
          createTime: DateTime.now().millisecondsSinceEpoch,
        ));
        await DislikeLog.append('标记不喜欢(MPV)', nm, rp, user.username, user.serverUrl);
        _showToast('已标记为不喜欢');
      }
      if (mounted) setState(() => _isDisliked = !_isDisliked);
    } catch (e) { _showToast('操作失败: $e'); }
  }

  void _showVideoInfo() {
    final v = _videos[_index];
    showDialog(context: context, builder: (ctx) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text('视频信息'), content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _infoRow('文件名', v["name"] ?? "未知"), _infoRow('大小', _formatFileSize(int.tryParse(v["size"] ?? "") ?? 0)), _infoRow('时长', _fmt(_duration)), _infoRow('格式', v["name"]?.split('.').last.toUpperCase() ?? "未知"), if (v["provider"]?.isNotEmpty == true) _infoRow('存储源', v["provider"]!),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))]));
  }

  Widget _infoRow(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 80, child: Text('$l:', style: const TextStyle(fontWeight: FontWeight.bold))), Expanded(child: Text(v))]));
  String _formatFileSize(int b) { if (b < 1024) return '$b B'; if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB'; if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB'; return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB'; }

  int _naturalCompare(String a, String b) {
    final regExp = RegExp(r'(\d+)'); final aM = regExp.allMatches(a).toList(); final bM = regExp.allMatches(b).toList();
    int ai = 0, bi = 0, api = 0, bpi = 0;
    while (ai < a.length && bi < b.length) {
      if (api < aM.length && bpi < bM.length && aM[api].start == ai && bM[bpi].start == bi) {
        final aNum = int.tryParse(aM[api].group(0) ?? "") ?? 0; final bNum = int.tryParse(bM[bpi].group(0) ?? "") ?? 0;
        if (aNum != bNum) return aNum.compareTo(bNum); ai = aM[api].end; bi = bM[bpi].end; api++; bpi++;
      } else { final ac = a[ai].toLowerCase(); final bc = b[bi].toLowerCase(); if (ac != bc) return ac.compareTo(bc); ai++; bi++; }
    }
    if (ai < a.length) return 1; if (bi < b.length) return -1; return 0;
  }

  void _toggleRepeatMode() { setState(() { _repeatMode = (_repeatMode + 1) % 3; _showToast(['循环关闭', '单集循环', '列表循环'][_repeatMode]); }); }
  void _toggleShuffle() { setState(() { _shuffleEnabled = !_shuffleEnabled; _showToast(_shuffleEnabled ? '随机播放: 开' : '随机播放: 关'); }); }
  void _enterPictureInPicture() async { await AlistPlugin.enterPictureInPicture(); }

  Widget _buildVideoView() {
    switch (_videoFillMode) {
      case VideoFillMode.cover:
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller.player.state.width?.toDouble() ?? 1920,
              height: _controller.player.state.height?.toDouble() ?? 1080,
              child: Video(controller: _controller, controls: NoVideoControls),
            ),
          ),
        );
      case VideoFillMode.fill:
        return Video(controller: _controller, controls: NoVideoControls, fit: BoxFit.fill);
      case VideoFillMode.contain:
      default:
        return Video(controller: _controller, controls: NoVideoControls, fit: BoxFit.contain);
    }
  }

  void _toggleVideoFillMode() {
    final nextIndex = (VideoFillMode.values.indexOf(_videoFillMode) + 1) % VideoFillMode.values.length;
    setState(() => _videoFillMode = VideoFillMode.values[nextIndex]);
    _showToast(['适应', '填充', '拉伸'][nextIndex]);
  }

  // ========== Gestures ==========
  static const _systemGestureBottomMargin = 40.0;
  bool _ignoreCurrentGesture = false;

  void _onVerticalDragStart(DragStartDetails d) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final bottomThreshold = bottomInset > 0 ? bottomInset : _systemGestureBottomMargin;
    _ignoreCurrentGesture = d.localPosition.dy > _screenHeight - bottomThreshold;
    _verticalDragStartY = d.localPosition.dy;
    _verticalDragType = null;
    _verticalDragging = false;
  }
  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_ignoreCurrentGesture) return;
    if (!_verticalDragging) {
      _verticalDragging = true;
      if (d.localPosition.dx > _screenWidth / 2) { _verticalDragType = _swapVolumeAndBrightness ? VerticalDragType.brightness : VerticalDragType.volume; _systemVolumeDragStartValue = _systemVolumeValue; }
      else { _verticalDragType = _swapVolumeAndBrightness ? VerticalDragType.volume : VerticalDragType.brightness; _systemBrightnessDragStartValue = _systemBrightnessValue; }
    }
    final ratio = (_verticalDragStartY - d.localPosition.dy) / _screenHeight;
    if (_verticalDragType == VerticalDragType.brightness) { _systemBrightnessValue = (_systemBrightnessDragStartValue + ratio).clamp(0.0, 1.0); ScreenBrightness().setScreenBrightness(_systemBrightnessValue); setState(() { _showBrightnessSlider = true; _showVolumeSlider = false; }); }
    else { _systemVolumeValue = (_systemVolumeDragStartValue + ratio).clamp(0.0, 1.0); VolumeController().setVolume(_systemVolumeValue, showSystemUI: false); setState(() { _showVolumeSlider = true; _showBrightnessSlider = false; }); }
  }
  void _onVerticalDragEnd(DragEndDetails d) {
    if (_ignoreCurrentGesture) {
      _ignoreCurrentGesture = false;
      return;
    }
    _ignoreCurrentGesture = false;
    if (!_verticalDragging) _toggleControls();
    setState(() { _verticalDragging = false; _verticalDragType = null; });
    Future.delayed(const Duration(seconds: 1), () { if (mounted) setState(() { _showBrightnessSlider = false; _showVolumeSlider = false; }); });
  }
  void _onDoubleTap() { _player.playOrPause(); _startHideTimer(); }

  void _handleDoubleTapSeek(bool isRight) {
    _doubleTapResetTimer?.cancel();
    setState(() { if (isRight) { _doubleTapSeekAmount += 10; _isDoubleTapSeekingRight = true; _isDoubleTapSeekingLeft = false; } else { _doubleTapSeekAmount -= 10; _isDoubleTapSeekingLeft = true; _isDoubleTapSeekingRight = false; } });
    final target = _position + Duration(seconds: isRight ? 10 : -10);
    _player.seek(target.isNegative ? Duration.zero : (target > _duration ? _duration : target));
    _startHideTimer();
    _doubleTapResetTimer = Timer(const Duration(milliseconds: 800), () { if (mounted) setState(() { _doubleTapSeekAmount = 0; _isDoubleTapSeekingLeft = false; _isDoubleTapSeekingRight = false; }); });
  }

  // ============================================================
  @override
  Widget build(BuildContext context) {
    final title = _videos[_index]["name"] ?? "";
    final screenSize = MediaQuery.of(context).size; _screenWidth = screenSize.width; _screenHeight = screenSize.height;
    _isFullscreen = screenSize.width > screenSize.height;
    final hasSheet = _activeSheet != PlayerSheet.none;
    final showOverlay = _showControls || hasSheet;
    final isLive = _duration == Duration.zero;

    return WillPopScope(
      onWillPop: () async {
        if (hasSheet) { _closeSheetAndPanel(); return false; }
        if (_isFullscreen) { _toggleFullscreen(); return false; }
        return true;
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(systemNavigationBarColor: Colors.black, systemNavigationBarDividerColor: Colors.black, statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(children: <Widget>[
            Positioned.fill(child: _buildVideoView()),
            subtitle_widget.SubtitleView(controller: _subtitleController),
            if (_isSwitching) Positioned.fill(child: Container(color: Colors.black)),
            if (_areControlsLocked) Positioned.fill(child: GestureDetector(onTap: () {}, behavior: HitTestBehavior.opaque, child: Container(color: Colors.transparent))),
            if (!_areControlsLocked) Positioned.fill(child: GestureDetector(
              onVerticalDragStart: _onVerticalDragStart, onVerticalDragUpdate: _onVerticalDragUpdate, onVerticalDragEnd: _onVerticalDragEnd,
              onDoubleTap: _onDoubleTap, onTap: _toggleControls,
              onHorizontalDragStart: (d) {
                // Ignore drags starting within 24px of screen edges (for system back gesture)
                final dx = d.localPosition.dx;
                if (dx < 24 || dx > _screenWidth - 24) return;
                _horizontalDragStartX = dx;
                _seekStartPos = _position;
                _seeking = true;
              },
              onHorizontalDragUpdate: (d) {
                if (_duration == Duration.zero || !_seeking) return;
                final dx = d.localPosition.dx - _horizontalDragStartX;
                final rangeMs =
                    VideoPlayerUtil.seekRangeForDuration(_duration).inMilliseconds;
                var t = _position +
                    Duration(milliseconds: (dx / _screenWidth * rangeMs).round());
                if (t.isNegative) t = Duration.zero; if (t > _duration) t = _duration;
                setState(() { _seekTarget = t; });
              },
              onHorizontalDragEnd: (_) { if (_seeking) { _player.seek(_seekTarget); setState(() => _seeking = false); } },
              behavior: HitTestBehavior.opaque,
            )),
            if (_isDoubleTapSeekingLeft) _DoubleTapSeekIndicator(isForward: false, seekAmount: _doubleTapSeekAmount.abs()),
            if (_isDoubleTapSeekingRight) _DoubleTapSeekIndicator(isForward: true, seekAmount: _doubleTapSeekAmount.abs()),
            if (_seeking) Positioned(top: _screenHeight * 0.3, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_seekTarget < _seekStartPos ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, color: Colors.white, size: 28), const SizedBox(width: 8), Text(_fmt(_seekTarget), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600))])))),
            if (_showBrightnessSlider && _verticalDragging) Positioned(left: _swapVolumeAndBrightness ? null : 20, right: _swapVolumeAndBrightness ? 20 : null, top: 0, bottom: 0, child: Center(child: _VerticalSliderIndicator(icon: Icons.brightness_high_rounded, value: _systemBrightnessValue, color: Colors.amber))),
            if (_showVolumeSlider && _verticalDragging) Positioned(left: _swapVolumeAndBrightness ? 20 : null, right: _swapVolumeAndBrightness ? null : 20, top: 0, bottom: 0, child: Center(child: _VerticalSliderIndicator(icon: Icons.volume_up_rounded, value: _systemVolumeValue, color: Colors.blue))),
            if (_showSpeedIndicator) Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.only(bottom: 120), child: Text('${_playbackSpeed.toStringAsFixed(2)}x', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold))),
            AnimatedOpacity(opacity: showOverlay ? 1.0 : 0.0, duration: const Duration(milliseconds: 200), child: IgnorePointer(ignoring: !showOverlay, child: Stack(children: <Widget>[
              Column(children: [
                _buildTopBar(title),
                Expanded(child: Center(child: _buildCenterControls())),
                _buildBottomBar(isLive),
              ]),
              if (_videos.length > 1 && !_isFullscreen) Positioned(left: 16, bottom: 80 + MediaQuery.of(context).padding.bottom, child: Row(children: [
                _buildFloatingSwitchButton(),
                const SizedBox(width: 8),
                _buildFloatingDislikeButton(),
              ])),
              if (_videos.length <= 1 && !_isFullscreen) Positioned(left: 16, bottom: 80 + MediaQuery.of(context).padding.bottom, child: _buildFloatingDislikeButton()),
            ]))),
            if (_areControlsLocked) Positioned(left: 40, right: 40, bottom: 60, child: _SlideToUnlock(onUnlock: () { setState(() => _areControlsLocked = false); _startHideTimer(); })),
            if (hasSheet) _buildSheetOverlay(),
            if (_activeSheet == PlayerSheet.playlist) _buildPlaylistDrawer(),
          ]),
        ),
      ),
    );
  }

  Widget _buildTopBar(String title) => Container(
    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent])),
    child: Row(children: [
      _CircularButton(icon: Icons.arrow_back_rounded, alwaysEnabled: true, onPressed: () { if (_isFullscreen) _toggleFullscreen(); else Get.back(); }),
      Expanded(child: GestureDetector(onTap: _areControlsLocked ? null : () => _openSheet(PlayerSheet.playlist), child: Container(height: 36, margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(18)), child: Row(children: [
        
        Flexible(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
      ])))),

      _CircularButton(icon: _isFavorite ? Icons.favorite : Icons.favorite_border, iconColor: _isFavorite ? Colors.red : Colors.white, alwaysEnabled: true, onPressed: _areControlsLocked ? null : _toggleFavorite),
      _CircularButton(icon: Icons.more_vert_rounded, alwaysEnabled: true, onPressed: _areControlsLocked ? null : () => _openSheet(PlayerSheet.more)),
    ]),
  );

  Widget _buildCenterControls() => Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
    if (_videos.length > 1) _PlaybackButton(icon: Icons.skip_previous_rounded, size: 48, enabled: _index > 0, onPressed: () => _playAt(_index - 1)), const SizedBox(width: 16),
    _PlaybackButton(icon: Icons.replay_10_rounded, size: 40, onPressed: () { final tp = _position - const Duration(seconds: 10); _player.seek(tp.isNegative ? Duration.zero : tp); _startHideTimer(); }), const SizedBox(width: 8),
    _PlayPauseButton(isPlaying: _playing, onPressed: () { _player.playOrPause(); _startHideTimer(); }), const SizedBox(width: 8),
    _PlaybackButton(icon: Icons.forward_10_rounded, size: 40, onPressed: () { final tp = _position + const Duration(seconds: 10); _player.seek(tp > _duration ? _duration : tp); _startHideTimer(); }), const SizedBox(width: 16),
    if (_videos.length > 1) _PlaybackButton(icon: Icons.skip_next_rounded, size: 48, enabled: _index < _videos.length - 1, onPressed: () => _playAt(_index + 1)),
  ]);

  Widget _buildBottomBar(bool isLive) => Container(
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent])),
    padding: EdgeInsets.fromLTRB(16, 0, 16, 8 + MediaQuery.of(context).padding.bottom),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (!isLive) _NormalSeekBar(position: _position, duration: _duration, onSeek: (pos) { _isDraggingSlider = true; _hideTimer?.cancel(); setState(() => _position = pos); }, onSeekEnd: (pos) { _isDraggingSlider = false; _player.seek(pos); _startHideTimer(); }),
      Row(children: [
        if (!isLive) Expanded(child: GestureDetector(onTap: () => _openSheet(PlayerSheet.playbackSpeed), child: Padding(padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8), child: Text('${_fmt(_position)} / ${_fmt(_duration)}', style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'))))),
        _CircularButton(icon: _areControlsLocked ? Icons.lock : Icons.lock_open_rounded, iconColor: _areControlsLocked ? Colors.blue : Colors.white70, size: 32, onPressed: () { setState(() { _areControlsLocked = !_areControlsLocked; if (!_areControlsLocked) _showControls = true; }); _startHideTimer(); }),
        
        _CircularButton(icon: _playbackSpeed == 1.0 ? Icons.speed_rounded : Icons.speed_rounded, iconColor: _playbackSpeed != 1.0 ? Colors.blue : Colors.white70, size: 32, onPressed: () => _openSheet(PlayerSheet.playbackSpeed)),
        _CircularButton(icon: _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, size: 32, onPressed: _toggleFullscreen),
      ]),
    ]),
  );

  Widget _buildFloatingSwitchButton() => _FloatingSwitchButton(
    currentIndex: _index + 1, totalCount: _videos.length,
    onPrevious: () => _index > 0 ? _playAt(_index - 1) : _showToast('已经是第一个视频了'),
    onNext: () => _index < _videos.length - 1 ? _playAt(_index + 1) : _showToast('已经是最后一个视频了'),
  );

  Widget _buildFloatingDislikeButton() => GestureDetector(
    onTap: _toggleDisliked,
    child: Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Center(child: Icon(
        _isDisliked ? Icons.thumb_down : Icons.thumb_down_alt_outlined,
        color: _isDisliked ? Colors.red : Colors.white,
        size: 22,
      )),
    ),
  );

  Widget _buildSheetOverlay() => GestureDetector(onTap: _closeSheetAndPanel, child: Container(color: Colors.black54, child: Align(alignment: Alignment.bottomCenter, child: GestureDetector(onTap: () {}, child: Container(constraints: BoxConstraints(maxHeight: _screenHeight * 0.55), width: double.infinity, decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))), child: _activeSheet == PlayerSheet.playbackSpeed ? _buildSpeedSheet() : _activeSheet == PlayerSheet.more ? _buildMoreSheet() : const SizedBox.shrink())))));

  Widget _buildSpeedSheet() {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0];
    return _SheetContainer(title: '播放速度', onClose: _closeSheetAndPanel, child: GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 2.5, crossAxisSpacing: 8, mainAxisSpacing: 8), padding: const EdgeInsets.all(16), itemCount: speeds.length, itemBuilder: (_, i) {
      final s = speeds[i]; final active = (_playbackSpeed - s).abs() < 0.01;
      return GestureDetector(onTap: () { _setPlaybackSpeed(s); _closeSheetAndPanel(); }, child: Container(decoration: BoxDecoration(color: active ? Colors.blue.withOpacity(0.3) : Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: active ? Border.all(color: Colors.blue, width: 1.5) : null), child: Center(child: Text('${s}x', style: TextStyle(color: active ? Colors.blue : Colors.white, fontWeight: active ? FontWeight.bold : FontWeight.normal)))));
    }));
  }

  Widget _buildMoreSheet() => _SheetContainer(title: '更多', onClose: _closeSheetAndPanel, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
    _moreTile(_isDisliked ? Icons.thumb_down : Icons.thumb_down_alt_outlined, _isDisliked ? '取消不喜欢' : '标记不喜欢', _isDisliked ? '已标记' : null, () { _closeSheetAndPanel(); _toggleDisliked(); }),
    _moreTile(
      _videoFillMode == VideoFillMode.contain ? Icons.fit_screen_outlined
        : _videoFillMode == VideoFillMode.cover ? Icons.zoom_out_map_rounded
        : Icons.aspect_ratio_rounded,
      '画面模式',
      ['适应', '填充', '拉伸'][VideoFillMode.values.indexOf(_videoFillMode)],
      () { _closeSheetAndPanel(); _toggleVideoFillMode(); },
    ),
    _moreTile(Icons.swap_horiz_rounded, '交换亮度/音量位置', _swapVolumeAndBrightness ? '已交换' : null, () { setState(() => _swapVolumeAndBrightness = !_swapVolumeAndBrightness); _showToast(_swapVolumeAndBrightness ? '已交换' : '已恢复默认'); _closeSheetAndPanel(); }),
    _moreTile(Icons.camera_alt_rounded, '截图', null, () { _closeSheetAndPanel(); _captureFrame(); }),
    _moreTile(Icons.info_outline_rounded, '视频信息', null, () { _closeSheetAndPanel(); _showVideoInfo(); }),
  ])));

  Widget _moreTile(IconData i, String t, String? s, VoidCallback o) => ListTile(leading: Icon(i, color: Colors.white70), title: Text(t, style: const TextStyle(color: Colors.white)), subtitle: s != null ? Text(s, style: const TextStyle(color: Colors.blue, fontSize: 12)) : null, onTap: o);

  Widget _buildPlaylistDrawer() {
    final w = _screenWidth * 0.75;
    final filteredVideos = _playlistFilter.isEmpty
        ? _videos.asMap().entries.toList()
        : _videos.asMap().entries.where((e) {
            final name = e.value["name"] ?? "";
            final nameWithoutExt = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
            return nameWithoutExt.toLowerCase().contains(_playlistFilter.toLowerCase());
          }).toList();
    return Stack(children: <Widget>[
      GestureDetector(onTap: _hidePlaylist, child: Container(color: Colors.black54)),
      Positioned(right: 0, top: 0, bottom: 0, width: w, child: SlideTransition(position: _playlistSlideAnimation, child: Container(color: const Color(0xFF1E1E1E), child: SafeArea(child: Column(children: <Widget>[
        Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24))), child: Column(children: [
          Row(children: [
            Expanded(child: Text(_playlistFilter.isEmpty ? '播放列表 (${_index + 1}/${_videos.length})' : '筛选结果 (${filteredVideos.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(icon: Icon(_showPlaylistFilter ? Icons.search_off : Icons.search, color: Colors.white), onPressed: () { setState(() { _showPlaylistFilter = !_showPlaylistFilter; if (!_showPlaylistFilter) { _playlistFilter = ''; _playlistFilterController.clear(); } }); }),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _hidePlaylist),
          ]),
          if (_showPlaylistFilter)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _playlistFilterController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '输入关键词筛选…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blue)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                    ),
                    onSubmitted: (_) { FocusScope.of(context).unfocus(); setState(() { _playlistFilter = _playlistFilterController.text; }); },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () { FocusScope.of(context).unfocus(); setState(() { _playlistFilter = _playlistFilterController.text; }); },
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text('确定', style: TextStyle(fontSize: 13)),
                ),
              ]),
            ),
        ])),
        Expanded(child: ListView.builder(itemCount: filteredVideos.length, itemBuilder: (_, i) {
          final idx = filteredVideos[i].key; final item = filteredVideos[i].value; final name = item["name"] ?? ""; final isCur = idx == _index;
          return ListTile(leading: Icon(isCur ? Icons.play_arrow : Icons.video_file, color: isCur ? Colors.blue : Colors.white70), title: Text(name, style: TextStyle(color: isCur ? Colors.blue : Colors.white, fontWeight: isCur ? FontWeight.bold : FontWeight.normal), maxLines: 2, overflow: TextOverflow.ellipsis), trailing: isCur ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(4)), child: const Text("播放中", style: TextStyle(color: Colors.white, fontSize: 10))) : null, selected: isCur, selectedTileColor: Colors.blue.withOpacity(0.1), onTap: () { _hidePlaylist(); _playAt(idx); });
        })),
        Container(decoration: const BoxDecoration(color: Color(0x1AFFFFFF), border: Border(top: BorderSide(color: Colors.white24))), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _SortButton(icon: _nameSortAscending ? Icons.arrow_upward : Icons.arrow_downward, label: '名称${_nameSortAscending ? "↑" : "↓"}', onPressed: () { setState(() { final curPath = _videos[_index]["path"]; if (_nameSortAscending) { _videos.sort((a, b) => _naturalCompare(b["name"] ?? "", a["name"] ?? "")); _showToast('名称降序'); } else { _videos.sort((a, b) => _naturalCompare(a["name"] ?? "", b["name"] ?? "")); _showToast('名称升序'); } _nameSortAscending = !_nameSortAscending; final newIdx = _videos.indexWhere((v) => v["path"] == curPath); if (newIdx >= 0) _index = newIdx; }); }),
          _SortButton(icon: _sizeSortAscending ? Icons.arrow_upward : Icons.arrow_downward, label: '大小${_sizeSortAscending ? "↑" : "↓"}', onPressed: () { setState(() { final curPath = _videos[_index]["path"]; if (_sizeSortAscending) { _videos.sort((a, b) => (int.tryParse(b["size"] ?? "0") ?? 0).compareTo(int.tryParse(a["size"] ?? "0") ?? 0)); _showToast('大小降序'); } else { _videos.sort((a, b) => (int.tryParse(a["size"] ?? "0") ?? 0).compareTo(int.tryParse(b["size"] ?? "0") ?? 0)); _showToast('大小升序'); } _sizeSortAscending = !_sizeSortAscending; final newIdx = _videos.indexWhere((v) => v["path"] == curPath); if (newIdx >= 0) _index = newIdx; }); }),
          _SortButton(icon: Icons.shuffle, label: '随机', onPressed: () { setState(() { final curPath = _videos[_index]["path"]; _videos.shuffle(); final newIdx = _videos.indexWhere((v) => v["path"] == curPath); if (newIdx >= 0) _index = newIdx; }); _showToast('已打乱顺序'); }),
        ])),
      ]))))),
    ]);
  }
}

// ======== Widgets ========
class _SheetContainer extends StatelessWidget {
  final String title; final VoidCallback onClose; final Widget child;
  const _SheetContainer({required this.title, required this.onClose, required this.child});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.fromLTRB(20, 16, 12, 16), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24))), child: Row(children: [Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: onClose)])), child]);
}

class _CircularButton extends StatelessWidget {
  final IconData icon; final Color? iconColor; final VoidCallback? onPressed; final double size; final bool alwaysEnabled;
  const _CircularButton({required this.icon, this.iconColor, this.onPressed, this.size = 40, this.alwaysEnabled = false});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onPressed, child: Container(width: size, height: size, margin: const EdgeInsets.all(4), decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.15)), child: Center(child: Icon(icon, color: iconColor ?? Colors.white, size: size * 0.5))));
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying; final VoidCallback onPressed;
  const _PlayPauseButton({required this.isPlaying, required this.onPressed});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onPressed, child: Container(width: 72, height: 72, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.2), border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5)), child: Center(child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 40))));
}

class _PlaybackButton extends StatelessWidget {
  final IconData icon; final double size; final bool enabled; final VoidCallback onPressed;
  const _PlaybackButton({required this.icon, required this.size, this.enabled = true, required this.onPressed});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: enabled ? onPressed : null, child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.15)), child: Center(child: Icon(icon, color: enabled ? Colors.white : Colors.white38, size: size * 0.6))));
}

class _NormalSeekBar extends StatefulWidget {
  final Duration position, duration; final Function(Duration) onSeek, onSeekEnd;
  const _NormalSeekBar({required this.position, required this.duration, required this.onSeek, required this.onSeekEnd});
  @override
  State<_NormalSeekBar> createState() => _NormalSeekBarState();
}
class _NormalSeekBarState extends State<_NormalSeekBar> {
  bool _d = false; double _v = 0;
  @override
  Widget build(BuildContext c) {
    final p = widget.duration.inMilliseconds > 0 ? widget.position.inMilliseconds / widget.duration.inMilliseconds : 0.0;
    final dp = (_d ? _v : p).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) { setState(() { _d = true; _v = (d.localPosition.dx / context.size!.width).clamp(0.0, 1.0); }); widget.onSeek(Duration(milliseconds: (_v * widget.duration.inMilliseconds).round())); },
      onHorizontalDragUpdate: (d) { setState(() { _v = (d.localPosition.dx / context.size!.width).clamp(0.0, 1.0); }); widget.onSeek(Duration(milliseconds: (_v * widget.duration.inMilliseconds).round())); },
      onHorizontalDragEnd: (_) { widget.onSeekEnd(Duration(milliseconds: (_v * widget.duration.inMilliseconds).round())); setState(() => _d = false); },
      onTapDown: (d) { final tp = (d.localPosition.dx / context.size!.width).clamp(0.0, 1.0); widget.onSeekEnd(Duration(milliseconds: (tp * widget.duration.inMilliseconds).round())); },
      child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 16), child: LayoutBuilder(builder: (_, ct) {
        final tw = ct.maxWidth, dot = tw * dp;
        return Stack(alignment: Alignment.center, children: [
          Container(height: 4, decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          Align(alignment: Alignment.centerLeft, child: Container(width: dot, height: 4, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))),
          Positioned(left: (dot - 8).clamp(0.0, tw - 16), child: Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]))),
        ]);
      })),
    );
  }
}

class _FloatingSwitchButton extends StatelessWidget {
  final int currentIndex, totalCount; final VoidCallback onPrevious, onNext;
  const _FloatingSwitchButton({required this.currentIndex, required this.totalCount, required this.onPrevious, required this.onNext});
  @override
  Widget build(BuildContext context) => Container(width: 130, height: 48, decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.2))), child: ClipRRect(borderRadius: BorderRadius.circular(23), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    GestureDetector(onTap: onPrevious, child: Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.1)), child: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 20))),
    Text('$currentIndex / $totalCount', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
    GestureDetector(onTap: onNext, child: Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.1)), child: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 20))),
  ])));
}

class _SortButton extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onPressed;
  const _SortButton({required this.icon, required this.label, required this.onPressed});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 24), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white, fontSize: 12))])));
}

class _DoubleTapSeekIndicator extends StatefulWidget {
  final bool isForward; final int seekAmount;
  const _DoubleTapSeekIndicator({required this.isForward, required this.seekAmount});
  @override
  State<_DoubleTapSeekIndicator> createState() => _DoubleTapSeekIndicatorState();
}
class _DoubleTapSeekIndicatorState extends State<_DoubleTapSeekIndicator> with TickerProviderStateMixin {
  late List<AnimationController> _ctrls; late List<Animation<double>> _alphas;
  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 750)));
    _alphas = _ctrls.map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();
    for (int i = 0; i < 3; i++) Future.delayed(Duration(milliseconds: i * 150), () { if (mounted) _ctrls[i].repeat(reverse: true); });
  }
  @override
  void dispose() { for (var c in _ctrls) c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Center(child: Row(mainAxisAlignment: widget.isForward ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
    if (!widget.isForward) const SizedBox(width: 20),
    if (!widget.isForward) ...List.generate(3, (i) => AnimatedBuilder(animation: _alphas[i], builder: (_, __) => Transform.translate(offset: Offset(-10, 0), child: Opacity(opacity: _alphas[i].value, child: const Icon(Icons.keyboard_arrow_left, color: Colors.white, size: 32))))),
    const SizedBox(width: 8),
    Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(8)), child: Text(widget.isForward ? '+${widget.seekAmount}' : '-${widget.seekAmount}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
    if (widget.isForward) ...List.generate(3, (i) => AnimatedBuilder(animation: _alphas[i], builder: (_, __) => Transform.translate(offset: const Offset(-10, 0), child: Opacity(opacity: _alphas[i].value, child: const Icon(Icons.keyboard_arrow_right, color: Colors.white, size: 32))))),
    if (widget.isForward) const SizedBox(width: 20),
  ]));
}

class _VerticalSliderIndicator extends StatelessWidget {
  final IconData icon; final double value; final Color color;
  const _VerticalSliderIndicator({required this.icon, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(16)), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, color: color, size: 28), const SizedBox(height: 8),
    Text('${(value * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
    Container(width: 24, height: 120, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Stack(alignment: Alignment.bottomCenter, children: [
      Container(width: 8, height: 100, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(4))),
      Positioned(bottom: 0, child: Container(width: 8, height: 100 * value, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)))),
    ])),
  ]));
}

class _SlideToUnlock extends StatefulWidget {
  final VoidCallback onUnlock;
  const _SlideToUnlock({required this.onUnlock});
  @override
  State<_SlideToUnlock> createState() => _SlideToUnlockState();
}
class _SlideToUnlockState extends State<_SlideToUnlock> {
  double _p = 0.0;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragUpdate: (d) { setState(() { _p = (d.localPosition.dx / context.size!.width).clamp(0.0, 1.0); }); if (_p >= 0.85) { widget.onUnlock(); setState(() => _p = 0.0); } },
    onHorizontalDragEnd: (_) => setState(() => _p = 0.0),
    child: Container(height: 48, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(24)), child: Stack(children: [
      Center(child: Text('滑动解锁', style: TextStyle(color: Colors.white.withOpacity(1 - _p), fontSize: 14))),
      Align(alignment: Alignment.centerLeft, child: Container(margin: const EdgeInsets.all(4), width: 40 + (_p * 200), height: 40, decoration: BoxDecoration(color: Colors.blue.withOpacity(0.7), borderRadius: BorderRadius.circular(20)), child: Center(child: Icon(_p > 0.5 ? Icons.lock_open_rounded : Icons.lock_rounded, color: Colors.white, size: 20)))),
    ])),
  );
}