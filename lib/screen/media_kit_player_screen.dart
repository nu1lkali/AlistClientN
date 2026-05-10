import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/screen/video_player_screen.dart';
import 'package:alist/util/alist_plugin.dart';
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
  
  // 视频切换时的遮罩状态 - 用于消除闪烁
  bool _isSwitching = false;
  
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

  // 双击快进状态
  int _doubleTapSeekAmount = 0;
  bool _isDoubleTapSeekingLeft = false;
  bool _isDoubleTapSeekingRight = false;
  Timer? _doubleTapResetTimer;

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
    _doubleTapResetTimer?.cancel();
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
    setState(() {
      _index = index;
      _isSwitching = true;
      _buffering = true;
    });
    
    // 延迟执行视频切换，让遮罩先显示
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      final video = _videos[index];
      final url = video["url"] ?? "";
      if (url.isNotEmpty) {
        _player.open(Media(url), play: true);
      }
      _hidePlaylist();
      _checkFavoriteStatus();
      
      // 新视频开始播放后移除遮罩
      _player.stream.playing.listen((playing) {
        if (playing && mounted) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              setState(() => _isSwitching = false);
            }
          });
        }
      });
    });
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

  // 双击快进/快退处理
  void _handleDoubleTapSeek(bool isRight) {
    _doubleTapResetTimer?.cancel();
    
    setState(() {
      if (isRight) {
        _doubleTapSeekAmount += 10;
        _isDoubleTapSeekingRight = true;
        _isDoubleTapSeekingLeft = false;
      } else {
        _doubleTapSeekAmount -= 10;
        _isDoubleTapSeekingLeft = true;
        _isDoubleTapSeekingRight = false;
      }
    });

    // 执行快进/快退
    final newPos = _position + Duration(seconds: _doubleTapSeekAmount > 0 ? 10 : -10);
    _player.seek(newPos.isNegative ? Duration.zero : (newPos > _duration ? _duration : newPos));
    
    _startHideTimer();

    // 重置双击状态
    _doubleTapResetTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _doubleTapSeekAmount = 0;
          _isDoubleTapSeekingLeft = false;
          _isDoubleTapSeekingRight = false;
        });
      }
    });
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
    
    // 计算按钮区域
    final buttonAreaWidth = _screenWidth * 0.25; // 25% 宽度用于快进/快退区域

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

              // 视频切换遮罩 - 消除切换时的闪烁
              if (_isSwitching)
                Positioned.fill(
                  child: Container(color: Colors.black),
                ),

              // 手势层 - 双击快进/快退区域
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

              // 双击快进/快退指示器
              if (_isDoubleTapSeekingLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: buttonAreaWidth,
                  child: _DoubleTapSeekIndicator(isForward: false, seekAmount: _doubleTapSeekAmount.abs()),
                ),
              
              if (_isDoubleTapSeekingRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: buttonAreaWidth,
                  child: _DoubleTapSeekIndicator(isForward: true, seekAmount: _doubleTapSeekAmount.abs()),
                ),

              // 加载指示器 - 显示在播放按钮下方
              if (_buffering && !_seeking && !_playing)
                Positioned(
                  left: 0,
                  right: 0,
                  top: _screenHeight * 0.5 + 60, // 播放按钮下方
                  child: Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black54,
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // 拖动指示器 - 显示在顶部偏下位置
              if (_seeking)
                Positioned(
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
                ),

              // 垂直滑动指示器 - mpvEx风格的滑块
              if (_verticalDragging && _verticalDragType != null)
                Positioned(
                  left: _verticalDragType == VerticalDragType.brightness ? 20 : null,
                  right: _verticalDragType == VerticalDragType.volume ? 20 : null,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _VerticalSliderIndicator(
                      type: _verticalDragType!,
                      value: _verticalDragType == VerticalDragType.brightness 
                          ? _systemBrightnessValue 
                          : _systemVolumeValue,
                    ),
                  ),
                ),

              // 控制面板层
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
                            // 顶部栏 - mpvEx风格
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.8),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Row(
                                children: [
                                  // 返回按钮 - 圆形设计
                                  _CircularButton(
                                    icon: Icons.arrow_back,
                                    onPressed: () {
                                      if (_isFullscreen) {
                                        _toggleFullscreen();
                                      } else {
                                        Get.back();
                                      }
                                    },
                                  ),
                                  
                                  // 播放列表信息和标题 - 简化为只显示文件名
                                  Expanded(
                                    child: Container(
                                      height: 36,
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_videos.length > 1) ...[
                                            GestureDetector(
                                              onTap: _showVideoInfo,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                margin: const EdgeInsets.only(right: 8),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.withOpacity(0.5),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '${_index + 1}/${_videos.length}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                          Flexible(
                                            child: Text(
                                              title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontFamily: 'monospace',
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  
                                  // 收藏按钮
                                  _CircularButton(
                                    icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                                    iconColor: _isFavorite ? Colors.red : Colors.white,
                                    onPressed: _toggleFavorite,
                                  ),
                                  
                                  // 截图按钮
                                  _CircularButton(
                                    icon: _isCapturing ? Icons.hourglass_empty : Icons.photo_camera,
                                    onPressed: _isCapturing ? null : _captureFrame,
                                  ),
                                  
                                  // 播放列表按钮
                                  _CircularButton(
                                    icon: Icons.playlist_play,
                                    iconColor: _showPlaylist ? Colors.blue : Colors.white,
                                    onPressed: _togglePlaylist,
                                  ),
                                ],
                              ),
                            ),

                            // 中间控制栏
                            Expanded(
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // 上一首
                                    if (_videos.length > 1)
                                      _PlaybackButton(
                                        icon: Icons.skip_previous_rounded,
                                        size: 48,
                                        enabled: _index > 0,
                                        onPressed: () {
                                          _playAt(_index - 1);
                                          _startHideTimer();
                                        },
                                      ),
                                    
                                    const SizedBox(width: 16),
                                    
                                    // 后退10秒
                                    _PlaybackButton(
                                      icon: Icons.replay_10_rounded,
                                      size: 40,
                                      onPressed: () {
                                        final newPos = _position - const Duration(seconds: 10);
                                        _player.seek(newPos.isNegative ? Duration.zero : newPos);
                                        _startHideTimer();
                                      },
                                    ),
                                    
                                    const SizedBox(width: 8),
                                    
                                    // 播放/暂停按钮 - 大圆形按钮，带阴影
                                    _PlayPauseButton(
                                      isPlaying: _playing,
                                      onPressed: () {
                                        _player.playOrPause();
                                        _startHideTimer();
                                      },
                                    ),
                                    
                                    const SizedBox(width: 8),
                                    
                                    // 前进10秒
                                    _PlaybackButton(
                                      icon: Icons.forward_10_rounded,
                                      size: 40,
                                      onPressed: () {
                                        final newPos = _position + const Duration(seconds: 10);
                                        _player.seek(newPos > _duration ? _duration : newPos);
                                        _startHideTimer();
                                      },
                                    ),
                                    
                                    const SizedBox(width: 16),
                                    
                                    // 下一首
                                    if (_videos.length > 1)
                                      _PlaybackButton(
                                        icon: Icons.skip_next_rounded,
                                        size: 48,
                                        enabled: _index < _videos.length - 1,
                                        onPressed: () {
                                          _playAt(_index + 1);
                                          _startHideTimer();
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            // 底部栏 - mpvEx风格
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.8),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 进度条 - 普通Slider风格
                                  if (!isLive)
                                    _NormalSeekBar(
                                      position: _position,
                                      duration: _duration,
                                      onSeek: (pos) {
                                        _isDraggingSlider = true;
                                        _hideTimer?.cancel();
                                        setState(() => _position = pos);
                                      },
                                      onSeekEnd: (pos) {
                                        _isDraggingSlider = false;
                                        _player.seek(pos);
                                        _startHideTimer();
                                      },
                                    ),
                                  
                                  Row(
                                    children: [
                                      // 时间显示
                                      if (!isLive)
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: Text(
                                              '${_fmt(_position)} / ${_fmt(_duration)}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                          ),
                                        ),
                                      
                                      // 全屏按钮
                                      _CircularButton(
                                        icon: _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                        size: 36,
                                        onPressed: _toggleFullscreen,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        
                                // 悬浮切换按钮 - 左下角（竖屏时显示）
                                if (_videos.length > 1 && !_isFullscreen)
                                  Positioned(
                                    left: 16,
                                    bottom: 80,
                                    child: _FloatingSwitchButton(
                                      currentIndex: _index + 1,
                                      totalCount: _videos.length,
                                      onPrevious: () {
                                        if (_index > 0) {
                                          _playAt(_index - 1);
                                        } else {
                                          _showToast('已经是第一个视频了');
                                        }
                                      },
                                      onNext: () {
                                        if (_index < _videos.length - 1) {
                                          _playAt(_index + 1);
                                        } else {
                                          _showToast('已经是最后一个视频了');
                                        }
                                      },
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

// mpvEx风格的圆形按钮
class _CircularButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onPressed;
  final double size;

  const _CircularButton({
    required this.icon,
    this.iconColor,
    this.onPressed,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.15),
        ),
        child: Center(
          child: Icon(
            icon,
            color: iconColor ?? Colors.white,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }
}

// mpvEx风格的播放按钮
class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.black.withOpacity(0.4),
              Colors.transparent,
            ],
            stops: const [0.0, 1.0],
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.2),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
      ),
    );
  }
}

// mpvEx风格的播放控制按钮
class _PlaybackButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool enabled;
  final VoidCallback onPressed;

  const _PlaybackButton({
    required this.icon,
    required this.size,
    this.enabled = true,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.15),
        ),
        child: Center(
          child: Icon(
            icon,
            color: enabled ? Colors.white : Colors.white38,
            size: size * 0.6,
          ),
        ),
      ),
    );
  }
}

// mpvEx风格的波浪进度条
class _WaveSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Function(Duration) onSeek;
  final Function(Duration) onSeekEnd;

  const _WaveSeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onSeekEnd,
  });

  @override
  State<_WaveSeekBar> createState() => _WaveSeekBarState();
}

class _WaveSeekBarState extends State<_WaveSeekBar> with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  double _dragValue = 0;
  late AnimationController _waveController;
  
  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.duration.inMilliseconds > 0
        ? widget.position.inMilliseconds / widget.duration.inMilliseconds
        : 0.0;
    
    final displayProgress = _isDragging ? _dragValue : progress;

    return GestureDetector(
      onHorizontalDragStart: (details) {
        setState(() {
          _isDragging = true;
          _dragValue = (details.localPosition.dx / context.size!.width).clamp(0.0, 1.0);
        });
        widget.onSeek(Duration(milliseconds: (_dragValue * widget.duration.inMilliseconds).round()));
      },
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragValue = (details.localPosition.dx / context.size!.width).clamp(0.0, 1.0);
        });
        widget.onSeek(Duration(milliseconds: (_dragValue * widget.duration.inMilliseconds).round()));
      },
      onHorizontalDragEnd: (details) {
        final duration = Duration(milliseconds: (_dragValue * widget.duration.inMilliseconds).round());
        widget.onSeekEnd(duration);
        setState(() {
          _isDragging = false;
        });
      },
      onTapDown: (details) {
        final tapProgress = (details.localPosition.dx / context.size!.width).clamp(0.0, 1.0);
        final duration = Duration(milliseconds: (tapProgress * widget.duration.inMilliseconds).round());
        widget.onSeekEnd(duration);
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AnimatedBuilder(
          animation: _waveController,
          builder: (context, child) {
            return CustomPaint(
              size: const Size(double.infinity, 48),
              painter: _WaveSeekBarPainter(
                progress: displayProgress,
                wavePhase: _waveController.value * 2 * 3.14159,
                isPaused: false,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WaveSeekBarPainter extends CustomPainter {
  final double progress;
  final double wavePhase;
  final bool isPaused;

  _WaveSeekBarPainter({
    required this.progress,
    required this.wavePhase,
    required this.isPaused,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final strokeWidth = 4.0;
    final waveAmplitude = isPaused ? 2.0 : 6.0;
    final waveLength = 80.0;

    final playedPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final unplayedPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final playedPath = Path();
    final unplayedPath = Path();
    
    final progressX = size.width * progress;
    final animatedPhase = wavePhase;

    // 绘制已播放部分（波浪效果）
    if (progress > 0) {
      playedPath.moveTo(0, centerY);
      for (double x = 0; x <= progressX; x += 2) {
        final waveOffset = isPaused ? 0.0 : 
            waveAmplitude * (x / waveLength * 2 * 3.14159 + animatedPhase).remainder(2 * 3.14159) / (2 * 3.14159) * 2 - 1;
        final y = centerY + waveOffset;
        if (x == 0) {
          playedPath.moveTo(x, y);
        } else {
          playedPath.lineTo(x, y);
        }
      }
      canvas.drawPath(playedPath, playedPaint);
    }

    // 绘制未播放部分
    if (progress < 1) {
      unplayedPath.moveTo(progressX, centerY);
      for (double x = progressX; x <= size.width; x += 2) {
        final waveOffset = isPaused ? 0.0 : 
            waveAmplitude * (x / waveLength * 2 * 3.14159 + animatedPhase).remainder(2 * 3.14159) / (2 * 3.14159) * 2 - 1;
        final y = centerY + waveOffset;
        unplayedPath.lineTo(x, y);
      }
      canvas.drawPath(unplayedPath, unplayedPaint);
    }

    // 绘制进度点
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(progressX, centerY), strokeWidth + 2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _WaveSeekBarPainter oldDelegate) {
    return oldDelegate.progress != progress || 
           oldDelegate.wavePhase != wavePhase || 
           oldDelegate.isPaused != isPaused;
  }
}

// mpvEx风格的垂直滑块指示器
class _VerticalSliderIndicator extends StatelessWidget {
  final VerticalDragType type;
  final double value;

  const _VerticalSliderIndicator({
    required this.type,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (value * 100).toInt();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$percentage%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // 垂直滑块
          Container(
            width: 24,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // 背景轨道
                Container(
                  width: 8,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // 进度填充
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 8,
                    height: 100 * value,
                    decoration: BoxDecoration(
                      color: type == VerticalDragType.brightness 
                          ? Colors.amber 
                          : Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Icon(
            type == VerticalDragType.brightness
                ? (value < 0.3 ? Icons.brightness_low : value > 0.7 ? Icons.brightness_high : Icons.brightness_medium)
                : (value < 0.3 ? Icons.volume_mute : Icons.volume_up),
            color: Colors.white,
            size: 28,
          ),
        ],
      ),
    );
  }
}

// 双击快进/快退指示器
class _DoubleTapSeekIndicator extends StatefulWidget {
  final bool isForward;
  final int seekAmount;

  const _DoubleTapSeekIndicator({
    required this.isForward,
    required this.seekAmount,
  });

  @override
  State<_DoubleTapSeekIndicator> createState() => _DoubleTapSeekIndicatorState();
}

class _DoubleTapSeekIndicatorState extends State<_DoubleTapSeekIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _alphas;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 750),
      );
    });

    _alphas = _controllers.map((controller) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    // 错开启动动画
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisAlignment: widget.isForward ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!widget.isForward) const SizedBox(width: 20),
          if (!widget.isForward)
            ...List.generate(3, (index) {
              return AnimatedBuilder(
                animation: _alphas[index],
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(widget.isForward ? 10 : -10, 0),
                    child: Opacity(
                      opacity: _alphas[index].value,
                      child: Icon(
                        widget.isForward 
                            ? Icons.keyboard_arrow_right 
                            : Icons.keyboard_arrow_left,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              );
            }),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.isForward ? '+${widget.seekAmount}' : '-${widget.seekAmount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (widget.isForward)
            ...List.generate(3, (index) {
              return AnimatedBuilder(
                animation: _alphas[index],
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(-10, 0),
                    child: Opacity(
                      opacity: _alphas[index].value,
                      child: Icon(
                        Icons.keyboard_arrow_right,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              );
            }),
          if (widget.isForward) const SizedBox(width: 20),
        ],
      ),
    );
  }
}

// 垂直拖动指示器
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

// 普通SeekBar进度条 - 替换波浪进度条
class _NormalSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Function(Duration) onSeek;
  final Function(Duration) onSeekEnd;

  const _NormalSeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onSeekEnd,
  });

  @override
  State<_NormalSeekBar> createState() => _NormalSeekBarState();
}

class _NormalSeekBarState extends State<_NormalSeekBar> {
  bool _isDragging = false;
  double _dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final progress = widget.duration.inMilliseconds > 0
        ? widget.position.inMilliseconds / widget.duration.inMilliseconds
        : 0.0;
    
    final displayProgress = _isDragging ? _dragValue : progress;
    final clampedProgress = displayProgress.clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragStart: (details) {
        setState(() {
          _isDragging = true;
          _dragValue = (details.localPosition.dx / context.size!.width).clamp(0.0, 1.0);
        });
        widget.onSeek(Duration(milliseconds: (_dragValue * widget.duration.inMilliseconds).round()));
      },
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragValue = (details.localPosition.dx / context.size!.width).clamp(0.0, 1.0);
        });
        widget.onSeek(Duration(milliseconds: (_dragValue * widget.duration.inMilliseconds).round()));
      },
      onHorizontalDragEnd: (details) {
        final duration = Duration(milliseconds: (_dragValue * widget.duration.inMilliseconds).round());
        widget.onSeekEnd(duration);
        setState(() {
          _isDragging = false;
        });
      },
      onTapDown: (details) {
        final tapProgress = (details.localPosition.dx / context.size!.width).clamp(0.0, 1.0);
        final duration = Duration(milliseconds: (tapProgress * widget.duration.inMilliseconds).round());
        widget.onSeekEnd(duration);
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            final dotPosition = trackWidth * clampedProgress;
            
            return Stack(
              alignment: Alignment.center,
              children: [
                // 底部轨道 - 未播放部分
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 顶部轨道 - 已播放部分
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: dotPosition,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 进度点 - 居中显示，不超出边界
                Positioned(
                  left: (dotPosition - 8).clamp(0.0, trackWidth - 16),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// 悬浮切换按钮 - 用于单手操作快速切换视频（磨砂设计）
class _FloatingSwitchButton extends StatelessWidget {
  final int currentIndex;
  final int totalCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _FloatingSwitchButton({
    required this.currentIndex,
    required this.totalCount,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 上一个按钮 - 不紧贴边缘
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: GestureDetector(
                onTap: onPrevious,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: const Icon(
                    Icons.skip_previous_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            // 索引显示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '$currentIndex / $totalCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // 下一个按钮 - 不紧贴边缘
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: onNext,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: const Icon(
                    Icons.skip_next_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
