import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/screen/video_player_screen.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/video_player_util.dart';
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
  final AlistDatabaseController _database = Get.find();

  bool _showControls = true;
  bool _showPlaylist = false;
  Timer? _hideTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _bufSub;

  bool _isDraggingSlider = false;
  bool _seeking = false;
  Duration _seekTarget = Duration.zero;
  Duration _seekStartPos = Duration.zero;
  double _horizontalDragStartX = 0;
  
  // 播放列表抽屉动画控制器
  late final AnimationController _playlistAnimationController;
  late final Animation<Offset> _playlistSlideAnimation;

  bool _isFullscreen = false;
  bool _isCapturing = false;

  bool _isFavorite = false;

  VerticalDragType? _verticalDragType;
  bool _verticalDragging = false;
  double _systemVolumeValue = 0.5;
  double _systemVolumeDragStartValue = 0.5;
  double _systemBrightnessValue = 0.5;
  double _systemBrightnessDragStartValue = 0.5;
  double _verticalDragStartY = 0;
  double _screenWidth = 0;
  double _screenHeight = 0;

  // 排序状态：true=升序，false=降序
  bool _nameSortAscending = true;
  bool _sizeSortAscending = false;

  bool _isWmvFormat(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return ["wmv", "asf", "asx", "wmx", "wvx"].contains(ext);
  }

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

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    _controller = VideoController(_player);

    _initBrightnessAndVolume();
    _checkFavoriteStatus();

    _hideSystemUI();
    WidgetsBinding.instance.addObserver(this);

    _posSub = _player.stream.position.listen((p) {
      if (mounted && !_isDraggingSlider) setState(() => _position = p);
    });
    _durSub = _player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _playSub = _player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
      if (p) {
        _startHideTimer();
      }
    });
    _bufSub = _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    });
    
    // 监听播放完成，自动切换到下一个视频
    _player.stream.completed.listen((completed) {
      if (completed && mounted && _videos.length > 1) {
        if (_index < _videos.length - 1) {
          _playAt(_index + 1);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _playAt(_index));
    
    // 初始化播放列表抽屉动画
    _playlistAnimationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _playlistSlideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _playlistAnimationController,
      curve: Curves.easeOutCubic,
    ));
  }

  Future<void> _initBrightnessAndVolume() async {
    try {
      _systemBrightnessValue = await ScreenBrightness().current;
    } catch (_) {
      _systemBrightnessValue = 0.5;
    }
    try {
      _systemVolumeValue = await VolumeController().getVolume();
    } catch (_) {
      _systemVolumeValue = 0.5;
    }
  }

  @override
  void didChangeMetrics() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _hideSystemUI();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _hideSystemUI();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _bufSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    _player.dispose();
    _playlistAnimationController.dispose();
    super.dispose();
  }

  void _playAt(int index) {
    if (index < 0 || index >= _videos.length) return;
    setState(() => _index = index);
    final video = _videos[index];
    final url = video["url"] ?? "";
    if (url.isNotEmpty) {
      _player.open(Media(url), play: true);
    }
    _hidePlaylist();
    _checkFavoriteStatus();
  }

  void _togglePlaylist() {
    if (_showPlaylist) {
      _playlistAnimationController.reverse();
      setState(() => _showPlaylist = false);
    } else {
      setState(() => _showPlaylist = true);
      _playlistAnimationController.forward();
    }
  }

  void _hidePlaylist() {
    _playlistAnimationController.reverse();
    setState(() => _showPlaylist = false);
  }

  Future<void> _captureFrame() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final screenshot = await _controller.player.screenshot();
      if (screenshot == null) {
        _showToast("截图失败");
        return;
      }

      final result = await ImageGallerySaver.saveImage(
        screenshot,
        quality: 100,
        name: "alist_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (result['isSuccess'] == true) {
        _showToast("截图已保存到相册");
      } else {
        _showToast("保存失败: ${result['errorMessage'] ?? '未知错误'}");
      }
    } catch (e) {
      _showToast("截图失败: $e");
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  void _showToast(String msg) {
    SmartDialog.showToast(msg);
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_showPlaylist) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_showControls) {
      _hideTimer?.cancel();
      setState(() => _showControls = false);
    } else {
      setState(() => _showControls = true);
      _startHideTimer();
    }
  }

  void _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    setState(() => _isFullscreen = !_isFullscreen);
    _hideSystemUI();
  }

  String _fmt(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _switchToNativePlayer() {
    _hidePlaylist();
    final items = _videos.map((v) {
      return VideoItem(
        name: v["name"] ?? "",
        localPath: v["localPath"],
        remotePath: v["remotePath"] ?? "",
        sign: v["sign"],
        provider: v["provider"],
        thumb: v["thumb"],
        size: int.tryParse(v["size"] ?? ""),
        modifiedMilliseconds: int.tryParse(v["modifiedMilliseconds"] ?? ""),
      );
    }).toList();
    
    _player.dispose();
    VideoPlayerUtil.go(items, _index, null);
    Get.back();
  }

  void _checkFavoriteStatus() async {
    final video = _videos[_index];
    final remotePath = video["remotePath"] ?? "";
    if (remotePath.isEmpty) return;
    
    try {
      final userController = Get.find<UserController>();
      final user = userController.user.value;
      final favorite = await _database.favoriteDao.findByPath(
        user.serverUrl,
        user.username,
        remotePath,
      );
      if (mounted) setState(() => _isFavorite = favorite != null);
    } catch (_) {
      if (mounted) setState(() => _isFavorite = false);
    }
  }

  void _toggleFavorite() async {
    final video = _videos[_index];
    final remotePath = video["remotePath"] ?? "";
    final name = video["name"] ?? "";
    if (remotePath.isEmpty) return;
    
    try {
      final userController = Get.find<UserController>();
      final user = userController.user.value;
      
      if (_isFavorite) {
        await _database.favoriteDao.deleteByPath(
          user.serverUrl,
          user.username,
          remotePath,
        );
        _showToast('已取消收藏');
      } else {
        await _database.favoriteDao.insertRecord(Favorite(
          isDir: false,
          serverUrl: user.serverUrl,
          userId: user.username,
          remotePath: remotePath,
          name: name,
          path: remotePath,
          size: int.tryParse(video["size"] ?? "0") ?? 0,
          sign: video["sign"],
          thumb: video["thumb"],
          modified: int.tryParse(video["modifiedMilliseconds"] ?? "0") ?? 0,
          provider: video["provider"] ?? "",
          createTime: DateTime.now().millisecondsSinceEpoch,
        ));
        _showToast('已添加到收藏');
      }
      if (mounted) setState(() => _isFavorite = !_isFavorite);
    } catch (e) {
      _showToast('操作失败: $e');
    }
  }

  void _showVideoInfo() {
    final video = _videos[_index];
    final size = int.tryParse(video["size"] ?? "") ?? 0;
    final modifiedMs = int.tryParse(video["modifiedMilliseconds"] ?? "") ?? 0;
    final modified = DateTime.fromMillisecondsSinceEpoch(modifiedMs);
    final duration = _duration;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('视频信息'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow('文件名', video["name"] ?? "未知"),
              _infoRow('大小', _formatFileSize(size)),
              _infoRow('时长', _fmt(duration)),
              _infoRow('格式', video["name"]?.split('.').last.toUpperCase() ?? "未知"),
              _infoRow('修改时间', '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')}'),
              if (video["provider"] != null && video["provider"]!.isNotEmpty)
                _infoRow('存储源', video["provider"]!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  // 自然排序比较函数（数字部分按数值大小比较）
  int _naturalCompare(String a, String b) {
    final regExp = RegExp(r'(\d+)');
    final aMatches = regExp.allMatches(a).toList();
    final bMatches = regExp.allMatches(b).toList();
    
    int aIndex = 0;
    int bIndex = 0;
    int aPartIndex = 0;
    int bPartIndex = 0;
    
    while (aIndex < a.length && bIndex < b.length) {
      if (aPartIndex < aMatches.length && bPartIndex < bMatches.length &&
          aMatches[aPartIndex].start == aIndex && bMatches[bPartIndex].start == bIndex) {
        // 数字部分
        final aNum = int.tryParse(aMatches[aPartIndex].group(0) ?? "") ?? 0;
        final bNum = int.tryParse(bMatches[bPartIndex].group(0) ?? "") ?? 0;
        if (aNum != bNum) return aNum.compareTo(bNum);
        aIndex = aMatches[aPartIndex].end;
        bIndex = bMatches[bPartIndex].end;
        aPartIndex++;
        bPartIndex++;
      } else {
        // 字符部分
        final aChar = a[aIndex].toLowerCase();
        final bChar = b[bIndex].toLowerCase();
        if (aChar != bChar) return aChar.compareTo(bChar);
        aIndex++;
        bIndex++;
      }
    }
    
    // 剩余部分比较
    if (aIndex < a.length) return 1;
    if (bIndex < b.length) return -1;
    return 0;
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _verticalDragStartY = details.localPosition.dy;
    _verticalDragType = null;
    _verticalDragging = false;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_verticalDragging) {
      _verticalDragging = true;
      if (details.localPosition.dx > _screenWidth / 2) {
        _verticalDragType = VerticalDragType.volume;
        _systemVolumeDragStartValue = _systemVolumeValue;
      } else {
        _verticalDragType = VerticalDragType.brightness;
        _systemBrightnessDragStartValue = _systemBrightnessValue;
      }
    }

    final dragDistance = _verticalDragStartY - details.localPosition.dy;
    final dragRatio = dragDistance / _screenHeight;
    
    if (_verticalDragType == VerticalDragType.brightness) {
      final newBrightness = (_systemBrightnessDragStartValue + dragRatio).clamp(0.0, 1.0);
      _systemBrightnessValue = newBrightness;
      ScreenBrightness().setScreenBrightness(newBrightness);
    } else {
      final newVolume = (_systemVolumeDragStartValue + dragRatio).clamp(0.0, 1.0);
      _systemVolumeValue = newVolume;
      VolumeController().setVolume(newVolume);
    }
    setState(() {});
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_verticalDragging) {
      _toggleControls();
    }
    setState(() {
      _verticalDragging = false;
      _verticalDragType = null;
    });
  }

  void _onDoubleTap() {
    _player.playOrPause();
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final video = _videos[_index];
    final title = video["name"] ?? "";
    final isLive = _duration == Duration.zero;
    final screenSize = MediaQuery.of(context).size;
    _screenWidth = screenSize.width;
    _screenHeight = screenSize.height;
    _isFullscreen = screenSize.width > screenSize.height;
    final playlistWidth = _screenWidth * 0.75;

    return WillPopScope(
      onWillPop: () async {
        if (_isFullscreen) { _toggleFullscreen(); return false; }
        if (_showPlaylist) { _hidePlaylist(); return false; }
        return true;
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.black,
          systemNavigationBarDividerColor: Colors.black,
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // 视频层
              Positioned.fill(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                ),
              ),

              // 手势层
              Positioned.fill(
                child: GestureDetector(
                  onVerticalDragStart: _onVerticalDragStart,
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: _onVerticalDragEnd,
                  onDoubleTap: _onDoubleTap,
                  onTap: _toggleControls,
                  onHorizontalDragStart: (details) {
                    _horizontalDragStartX = details.localPosition.dx;
                    _seekStartPos = _position;
                    _seeking = false;
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_duration == Duration.zero) return;
                    // 计算滑动距离：向右滑为正（快进），向左滑为负（快退）
                    final dx = details.localPosition.dx - _horizontalDragStartX;
                    final screenW = _screenWidth;
                    // 每屏宽度对应视频总时长
                    final seekDelta = (dx / screenW) * _duration.inMilliseconds;
                    var target = _position + Duration(milliseconds: seekDelta.round());
                    if (target.isNegative) target = Duration.zero;
                    if (target > _duration) target = _duration;
                    setState(() {
                      _seeking = true;
                      _seekTarget = target;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_seeking) {
                      _player.seek(_seekTarget);
                      setState(() => _seeking = false);
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                ),
              ),

              // 加载指示器 - 显示在播放按钮下方
              if (_buffering && !_seeking && !_playing)
                Positioned(
                  left: 0,
                  right: 0,
                  top: _screenHeight * 0.5 + 40, // 播放按钮下方
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),

              // 拖动指示器
              if (_seeking)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _seekTarget < _seekStartPos
                              ? Icons.fast_rewind_rounded
                              : Icons.fast_forward_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _fmt(_seekTarget),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 垂直滑动指示器
              if (_verticalDragging && _verticalDragType != null)
                Positioned(
                  top: _screenHeight * 0.3,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _VerticalDragIndicator(
                      type: _verticalDragType!,
                      value: _verticalDragType == VerticalDragType.brightness 
                          ? _systemBrightnessValue 
                          : _systemVolumeValue,
                    ),
                  ),
                ),

              // 控制面板层（包括悬浮切换按钮）
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: SafeArea(
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            // 顶部栏
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.black87, Colors.transparent],
                                ),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                                    onPressed: () {
                                      if (_isFullscreen) {
                                        _toggleFullscreen();
                                      } else {
                                        Get.back();
                                      }
                                    },
                                  ),
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                                      color: _isFavorite ? Colors.red : Colors.white,
                                    ),
                                    onPressed: _toggleFavorite,
                                    tooltip: '收藏',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.info_outline, color: Colors.white),
                                    onPressed: _showVideoInfo,
                                    tooltip: '视频信息',
                                  ),
                                  IconButton(
                                    icon: _isCapturing
                                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Icon(Icons.photo_camera, color: Colors.white),
                                    onPressed: _isCapturing ? null : _captureFrame,
                                    tooltip: '截图',
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.playlist_play, color: _showPlaylist ? Colors.blue : Colors.white),
                                    onPressed: _togglePlaylist,
                                    tooltip: '播放列表',
                                  ),
                                ],
                              ),
                            ),

                            // 中间控制栏
                            Expanded(
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      iconSize: 48,
                                      icon: Icon(Icons.skip_previous_rounded, color: _index > 0 ? Colors.white : Colors.white.withOpacity(0.3)),
                                      onPressed: _index > 0 ? () { _playAt(_index - 1); _startHideTimer(); } : null,
                                    ),
                                    const SizedBox(width: 16),
                                    IconButton(
                                      iconSize: 64,
                                      icon: Icon(_playing ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, color: Colors.white),
                                      onPressed: () {
                                        _player.playOrPause();
                                        _startHideTimer();
                                      },
                                    ),
                                    const SizedBox(width: 16),
                                    IconButton(
                                      iconSize: 48,
                                      icon: Icon(Icons.skip_next_rounded, color: _index < _videos.length - 1 ? Colors.white : Colors.white.withOpacity(0.3)),
                                      onPressed: _index < _videos.length - 1 ? () { _playAt(_index + 1); _startHideTimer(); } : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 底部栏
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Colors.black87, Colors.transparent],
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 进度条
                                  if (!isLive)
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 2,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                        activeTrackColor: Colors.white,
                                        inactiveTrackColor: Colors.white.withOpacity(0.3),
                                        thumbColor: Colors.white,
                                        overlayColor: Colors.white.withOpacity(0.2),
                                      ),
                                      child: Slider(
                                        value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                                        min: 0,
                                        max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                                        onChangeStart: (_) {
                                          _isDraggingSlider = true;
                                          _hideTimer?.cancel();
                                        },
                                        onChanged: (v) {
                                          setState(() => _position = Duration(milliseconds: v.toInt()));
                                        },
                                        onChangeEnd: (v) {
                                          _isDraggingSlider = false;
                                          _player.seek(Duration(milliseconds: v.toInt()));
                                          _startHideTimer();
                                        },
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      const Spacer(),
                                      if (!isLive)
                                        Text('${_fmt(_position)} / ${_fmt(_duration)}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                                        onPressed: _toggleFullscreen,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // 左下角悬浮便捷切换按钮
                        if (_videos.length > 1)
                          Positioned(
                            left: 8,
                            bottom: _isFullscreen ? 60 : 80,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.skip_previous_rounded, color: _index > 0 ? Colors.white : Colors.white38),
                                    onPressed: _index > 0 ? () { _playAt(_index - 1); } : null,
                                    iconSize: 32,
                                    tooltip: '上一个',
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      '${_index + 1}/${_videos.length}',
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.skip_next_rounded, color: _index < _videos.length - 1 ? Colors.white : Colors.white38),
                                    onPressed: _index < _videos.length - 1 ? () { _playAt(_index + 1); } : null,
                                    iconSize: 32,
                                    tooltip: '下一个',
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // 播放列表抽屉（带动画）
              AnimatedBuilder(
                animation: _playlistAnimationController,
                builder: (context, child) {
                  if (_playlistAnimationController.value == 0 && !_showPlaylist) {
                    return const SizedBox.shrink();
                  }
                  return Stack(
                    children: [
                      // 背景遮罩（带淡入淡出动画）
                      GestureDetector(
                        onTap: _hidePlaylist,
                        child: FadeTransition(
                          opacity: _playlistAnimationController,
                          child: Container(color: Colors.black54),
                        ),
                      ),
                      // 抽屉面板（带滑入滑出动画）
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: playlistWidth,
                        child: SlideTransition(
                          position: _playlistSlideAnimation,
                          child: Container(
                            color: const Color(0xFF1E1E1E),
                            child: SafeArea(
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: const BoxDecoration(
                                      border: Border(bottom: BorderSide(color: Colors.white24)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            '播放列表',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close, color: Colors.white),
                                          onPressed: _hidePlaylist,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: _videos.length,
                                      itemBuilder: (context, idx) {
                                        final item = _videos[idx];
                                        final name = item["name"] ?? "";
                                        final isCurrent = idx == _index;
                                        final isWmv = _isWmvFormat(name);

                                        return ListTile(
                                          leading: Icon(
                                            isCurrent ? Icons.play_arrow : Icons.video_file,
                                            color: isCurrent ? Colors.blue : Colors.white70,
                                          ),
                                          title: Text(
                                            name,
                                            style: TextStyle(
                                              color: isCurrent ? Colors.blue : Colors.white,
                                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: isWmv
                                              ? const Text("WMV 格式", style: TextStyle(color: Colors.orange, fontSize: 12))
                                              : null,
                                          trailing: isCurrent
                                              ? Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text("播放中", style: TextStyle(color: Colors.white, fontSize: 10)),
                                                )
                                              : null,
                                          selected: isCurrent,
                                          selectedTileColor: Colors.blue.withOpacity(0.1),
                                          onTap: () => _playAt(idx),
                                        );
                                      },
                                    ),
                                  ),
                                  // 底部排序按钮栏
                                  Container(
                                    decoration: const BoxDecoration(
                                      color: Color(0x1AFFFFFF),
                                      border: Border(top: BorderSide(color: Colors.white24)),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _SortButton(
                                          icon: _nameSortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                          label: '名称${_nameSortAscending ? "↑" : "↓"}',
                                          onPressed: () {
                                            setState(() {
                                              if (_nameSortAscending) {
                                                _videos.sort((a, b) => _naturalCompare(b["name"] ?? "", a["name"] ?? ""));
                                                _showToast('名称降序');
                                              } else {
                                                _videos.sort((a, b) => _naturalCompare(a["name"] ?? "", b["name"] ?? ""));
                                                _showToast('名称升序');
                                              }
                                              _nameSortAscending = !_nameSortAscending;
                                            });
                                          },
                                        ),
                                        _SortButton(
                                          icon: _sizeSortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                          label: '大小${_sizeSortAscending ? "↑" : "↓"}',
                                          onPressed: () {
                                            setState(() {
                                              if (_sizeSortAscending) {
                                                _videos.sort((a, b) => (int.tryParse(b["size"] ?? "0") ?? 0).compareTo(int.tryParse(a["size"] ?? "0") ?? 0));
                                                _showToast('大小降序');
                                              } else {
                                                _videos.sort((a, b) => (int.tryParse(a["size"] ?? "0") ?? 0).compareTo(int.tryParse(b["size"] ?? "0") ?? 0));
                                                _showToast('大小升序');
                                              }
                                              _sizeSortAscending = !_sizeSortAscending;
                                            });
                                          },
                                        ),
                                        _SortButton(
                                          icon: Icons.shuffle,
                                          label: '随机',
                                          onPressed: () {
                                            setState(() {
                                              _videos.shuffle();
                                            });
                                            _showToast('已打乱顺序');
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalDragIndicator extends StatelessWidget {
  final VerticalDragType type;
  final double value;

  const _VerticalDragIndicator({
    required this.type,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            type == VerticalDragType.brightness
                ? (value < 0.3 ? Icons.brightness_low : value > 0.7 ? Icons.brightness_high : Icons.brightness_medium)
                : (value < 0.3 ? Icons.volume_mute : Icons.volume_up),
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            '${(value * 100).toInt()}%',
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 150,
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SortButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
