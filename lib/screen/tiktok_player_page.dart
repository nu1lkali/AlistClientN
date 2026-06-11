import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/disliked_video.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/entity/tiktok_play_list_model.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/log_utils.dart' as log;
import 'package:alist/util/user_controller.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock/wakelock.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playList = Get.arguments as TikTokPlayListModel;
    _currentIndex = _playList.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _uiOpacity = SpUtil.getDouble(AlistConstant.tiktokUiOpacity, defValue: 1.0) ?? 1.0;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    Wakelock.enable();

    _safeInitCtrl(_currentIndex);
    _preloadNearby(_currentIndex);
    _loadStates(_currentIndex);
    _startTimer();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _flushPending();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _controllers.values) {
      try { c.dispose(); } catch (_) {}
    }
    _controllers.clear();
    try { _pageController.dispose(); } catch (_) {}
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Wakelock.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _safePause();
    else if (state == AppLifecycleState.resumed) _safePlay();
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
          setState(() { _pos = c.value.position; _dur = c.value.duration; });
          if (c.value.duration > Duration.zero &&
              c.value.position >= c.value.duration - const Duration(milliseconds: 500) &&
              !_completing) {
            _completing = true;
            if (_loopSingle) {
              c.seekTo(Duration.zero).then((_) { c.play(); _completing = false; });
            } else if (_currentIndex < _playList.videos.length - 1) {
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

  // ═══════════════ Controller Management ═══════════════
  Future<void> _safeInitCtrl(int idx) async {
    if (idx < 0 || idx >= _playList.videos.length) return;
    if (_controllers.containsKey(idx) || _initializingIndexes.contains(idx)) return;
    _initializingIndexes.add(idx);
    try {
      final v = _playList.videos[idx];
      if (v.videoUrl == null || v.videoUrl!.isEmpty) {
        final url = await FileUtils.makeFileLink(v.filePath, v.sign);
        if (url == null || url.isEmpty) { _initializingIndexes.remove(idx); return; }
        v.videoUrl = url;
      }
      if (!mounted) { _initializingIndexes.remove(idx); return; }
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(v.videoUrl!),
        httpHeaders: v.provider == 'BaiduNetdisk' ? {'User-Agent': 'pan.baidu.com'} : {},
      );
      await ctrl.initialize();
      ctrl.setLooping(_loopSingle);
      if (!mounted) { try { ctrl.dispose(); } catch (_) {} _initializingIndexes.remove(idx); return; }
      _controllers[idx] = ctrl;
      _initializingIndexes.remove(idx);
      if (idx == _currentIndex) { ctrl.play(); _isPlaying = true; }
      if (mounted) setState(() {});
    } catch (e) {
      log.Log.e('initCtrl[$idx]: $e');
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
      if (_isPlaying) { c.pause(); _isPlaying = false; } else { c.play(); _isPlaying = true; }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _toggleOrientation() {
    if (_isLandscape) SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    else SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _isLandscape = !_isLandscape;
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
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) { SmartDialog.dismiss(); SmartDialog.showToast('截图失败'); return; }
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) { SmartDialog.dismiss(); SmartDialog.showToast('截图失败'); return; }
      final result = await ImageGallerySaver.saveImage(
        byteData.buffer.asUint8List(), quality: 100,
        name: "alist_${DateTime.now().millisecondsSinceEpoch}",
      );
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        RepaintBoundary(key: _repaintKey, child: Stack(children: [_buildPageView(), _buildPauseIcon()])),
        _buildTopBar(),
        if (!_hideUI) _buildToolBar(),
        if (!_hideUI) _buildProgress(),
        if (!_hideUI && !_isLandscape) _buildBottomInfo(),
        ..._buildHearts(),
        if (!_hideUI) _buildIndicator(),
      ]),
    );
  }

  Widget _buildPageView() {
    return GestureDetector(
      onDoubleTapDown: (details) {
        // 始终播放动效，在点击位置弹出
        if (mounted) setState(() => _doubleTapIcons.add(details.globalPosition));
        final v = _playList.videos[_currentIndex];
        // 只有未收藏时才设置为收藏，已收藏时不做toggle
        if (!v.isLiked) {
          v.isLiked = true;
          if (v.isDisliked) v.isDisliked = false;
          _pendingFav[_currentIndex] = true;
          _pendingDislike[_currentIndex] = false;
          if (mounted) setState(() {});
        }
      },
      onTap: _togglePlayPause,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _playList.videos.length,
        onPageChanged: (idx) {
          _flushPending();
          // 暂停旧视频
          try { _controllers[_currentIndex]?.pause(); } catch (_) {}
          _currentIndex = idx;
          _isPlaying = false;
          _pos = Duration.zero;
          _dur = Duration.zero;
          // 释放超出缓存范围的控制器（保留预加载的）
          _disposeOutOfRange(idx);
          if (mounted) setState(() {});
          // 当前视频已预加载则直接播放，否则初始化
          final c = _controllers[idx];
          if (c != null && c.value.isInitialized) {
            c.play();
            _isPlaying = true;
            if (mounted) setState(() {});
          } else {
            _safeInitCtrl(idx);
          }
          _preloadNearby(idx);
          _loadStates(idx);
        },
        itemBuilder: (context, idx) {
          final c = _controllers[idx];
          if (c != null && c.value.isInitialized) {
            return Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)));
          }
          return const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2));
        },
      ),
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
          IconButton(
            icon: Icon(_hideUI ? Icons.visibility : Icons.visibility_off,
                color: Colors.white, size: 22),
            onPressed: () { setState(() => _hideUI = !_hideUI); },
          ),
        ]),
      )),
    ));
  }

  Widget _buildToolBar() {
    final v = _playList.videos[_currentIndex];
    return Positioned(right: 12, bottom: _isLandscape ? 100 : 160,
      child: Opacity(opacity: _uiOpacity, child: Column(children: [
        _btn(icon: v.isLiked ? Icons.favorite : Icons.favorite_border,
          label: v.isLiked ? '已收藏' : '收藏', color: v.isLiked ? Colors.red : Colors.white, onTap: _toggleLike),
        const SizedBox(height: 20),
        _btn(icon: v.isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
          label: v.isDisliked ? '已踩' : '踩', color: v.isDisliked ? Colors.blue : Colors.white, onTap: _toggleDislike),
        const SizedBox(height: 20),
        _btn(icon: _loopSingle ? Icons.repeat_one : Icons.repeat,
          label: _loopSingle ? '单曲循环' : '自动下一个', color: _loopSingle ? Colors.amber : Colors.white, onTap: _toggleLoop),
        const SizedBox(height: 20),
        _btn(icon: _isLandscape ? Icons.stay_current_portrait : Icons.stay_current_landscape,
          label: _isLandscape ? '竖屏' : '横屏', color: Colors.white, onTap: _toggleOrientation),
        const SizedBox(height: 20),
        _btn(icon: Icons.camera_alt_outlined, label: '截图', color: Colors.white, onTap: _takeScreenshot),
        const SizedBox(height: 20),
        _btn(icon: Icons.info_outline, label: '信息', color: Colors.white, onTap: _showInfo),
      ])),
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
    return Positioned(left: 0, right: 0, bottom: _isLandscape ? 30 : 80,
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
    return Positioned(left: 12, bottom: 20, right: 80,
      child: Opacity(opacity: _uiOpacity, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      ])),
    );
  }

  Widget _buildPauseIcon() {
    if (_isPlaying) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Center(child: Container(width: 72, height: 72,
        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(36)),
        child: const Icon(Icons.pause_rounded, color: Colors.white70, size: 44))),
    );
  }

  List<Widget> _buildHearts() => _doubleTapIcons.map((p) =>
    _HeartAnim(key: Key(p.toString()), position: p, onDone: () => _doubleTapIcons.remove(p))).toList();

  // 修复：页码指示器支持任意数量视频，用比例显示
  Widget _buildIndicator() {
    final total = _playList.videos.length;
    if (total <= 1) return const SizedBox.shrink();
    final maxH = MediaQuery.of(context).size.height * 0.5;
    final dotH = total <= 20 ? 8.0 : (total <= 50 ? 5.0 : 3.0);
    final activeH = dotH * 2;
    return Positioned(right: 8, top: MediaQuery.of(context).size.height / 2 - maxH / 2,
      child: SizedBox(height: maxH, child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i == _currentIndex;
          return Container(width: 3, height: active ? activeH : dotH,
            margin: EdgeInsets.symmetric(vertical: active ? 1 : 0.5),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white30,
              borderRadius: BorderRadius.circular(2)));
        }),
      )),
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