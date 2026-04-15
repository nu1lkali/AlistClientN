import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/database/table/video_viewing_record.dart';
import 'package:alist/l10n/intl_keys.dart';
import 'package:alist/util/file_utils.dart';
import 'package:alist/util/lock_caching_audio_source.dart';
import 'package:alist/util/user_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:audio_service/audio_service.dart' show AudioService;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'dart:io' as io;

class AudioPlayerScreen extends StatefulWidget {
  AudioPlayerScreen({Key? key}) : super(key: key);

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen>
    with TickerProviderStateMixin {
  late AnimationController _discController;
  late AnimationController _stylusController;
  late Animation<double> _stylusAnimation;

  final List<AudioItem> _audios = Get.arguments["audios"] ?? [];
  final int _index = Get.arguments["index"] ?? 0;
  late AudioPlayerScreenController _controller;

  @override
  void initState() {
    super.initState();
    // 隐藏底部导航小白条（沉浸式）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _controller =
        Get.put(AudioPlayerScreenController(audios: _audios, index: _index));

    _discController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _discController.reset();
          _discController.forward();
        }
      });

    _stylusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _stylusAnimation =
        Tween<double>(begin: -0.03, end: -0.10).animate(_stylusController);

    ever(_controller._playing, (bool playing) {
      if (playing) {
        _discController.forward();
        _stylusController.reverse();
      } else {
        _discController.stop();
        _stylusController.forward();
      }
    });
  }

  @override
  void dispose() {
    // 离开页面恢复系统UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _discController.dispose();
    _stylusController.dispose();
    super.dispose();
  }

  Widget _buildCoverImage() {
    return Obx(() {
      final bytes = _controller.coverArtBytes.value;
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: bytes != null
            ? Image.memory(
                bytes,
                key: ValueKey(bytes.hashCode),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              )
            : Image.asset(
                'assets/images/cover.jpg',
                key: const ValueKey('default_cover'),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // 第1层：背景封面图（全屏）
          _buildCoverImage(),

          // 第2层：磨砂模糊遮罩
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              color: Colors.black.withOpacity(0.4),
              width: double.infinity,
              height: double.infinity,
            ),
          ),

          // 第3层：AppBar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
              iconTheme: const IconThemeData(color: Colors.white, opacity: 1.0),
              actionsIconTheme: const IconThemeData(color: Colors.white, opacity: 1.0),
              title: Obx(() => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _controller._name.value,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_controller._artist.value.isNotEmpty)
                        Text(
                          _controller._artist.value,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  )),
              actions: [
                Obx(() => IconButton(
                      icon: Icon(
                        _controller.isFavorite.value
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _controller.isFavorite.value
                            ? Colors.red
                            : Colors.white,
                      ),
                      tooltip:
                          _controller.isFavorite.value ? '取消收藏' : '收藏',
                      onPressed: _controller.toggleFavorite,
                    )),
              ],
            ),
          ),

          // 第4层：主内容（从AppBar下方开始）
          Positioned(
            top: statusBarHeight + kToolbarHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              children: [
                // 黑胶唱片区域
                Expanded(
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      // 旋转唱片
                      Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          margin: const EdgeInsets.only(top: 40),
                          child: RotationTransition(
                            turns: _discController,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset('assets/images/vinyl_disc.png',
                                    width: 280),
                                Obx(() {
                                  final bytes =
                                      _controller.coverArtBytes.value;
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(90),
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 600),
                                      child: bytes != null
                                          ? Image.memory(bytes,
                                              key: ValueKey(bytes.hashCode),
                                              width: 180,
                                              height: 180,
                                              fit: BoxFit.cover)
                                          : Image.asset(
                                              'assets/images/cover.jpg',
                                              key: const ValueKey('default_disc'),
                                              width: 180,
                                              height: 180,
                                              fit: BoxFit.cover),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 唱针
                      Align(
                        alignment: const Alignment(0.25, -1),
                        child: RotationTransition(
                          turns: _stylusAnimation,
                          alignment: const Alignment(-0.7, -0.82),
                          child: Image.asset('assets/images/vinyl_stylus.png',
                              width: 100),
                        ),
                      ),
                    ],
                  ),
                ),

                // 进度条
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Obx(() => _buildSlider()),
                ),

                // 控制按钮
                _buildButtons(context),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider() {
    if (!_controller._prepared.value) {
      return const SizedBox(height: 50);
    }

    double duration = _controller._duration.value.inMilliseconds.toDouble();
    double currentValue = _controller._seekPos.value > 0
        ? _controller._seekPos.value
        : _controller._currentPos.value.inMilliseconds.toDouble();
    currentValue = currentValue.clamp(0.0, max(duration, 1));

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white30,
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: currentValue,
            min: 0.0,
            max: max(duration, 1),
            onChanged: (v) {
              _controller._seekPos.value = v;
            },
            onChangeEnd: (v) {
              _controller._currentPos.value = Duration(milliseconds: v.toInt());
              _controller._audioPlayer.seek(_controller._currentPos.value);
              _controller._seekPos.value = -1;
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _duration2String(_controller._seekPos.value > 0
                    ? Duration(
                        milliseconds: _controller._seekPos.value.toInt())
                    : _controller._currentPos.value),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                _duration2String(_controller._duration.value),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 循环模式
          Obx(() => IconButton(
                iconSize: 28,
                color: Colors.white,
                icon: _buildPlayModeIcon(_controller._playMode.value),
                onPressed: _controller._changePlayMode,
              )),
          // 上一首
          Obx(() => IconButton(
                iconSize: 40,
                color: Colors.white,
                icon: const Icon(Icons.skip_previous),
                onPressed: _controller._playMode.value == PlayMode.single ||
                        _controller._audios.length <= 1
                    ? null
                    : _controller._playPrevious,
              )),
          // 播放/暂停
          Obx(() => _buildPlayPauseButton()),
          // 下一首
          Obx(() => IconButton(
                iconSize: 40,
                color: Colors.white,
                icon: const Icon(Icons.skip_next),
                onPressed: _controller._playMode.value == PlayMode.single ||
                        _controller._audios.length <= 1
                    ? null
                    : _controller._playNext,
              )),
          // 播放列表（用 queue_music 视觉上更饱满）
          IconButton(
            iconSize: 28,
            color: Colors.white,
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => _showPlayerList(context),
          ),
          // 定时暂停
          Obx(() {
            final active = _controller.sleepTimerRemaining.value != null ||
                _controller.sleepAfterTrack.value;
            return IconButton(
              iconSize: 28,
              color: active ? Colors.orangeAccent : Colors.white,
              icon: const Icon(Icons.bedtime_outlined),
              tooltip: '定时暂停',
              onPressed: () => _showSleepTimerSheet(context),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPlayModeIcon(PlayMode mode) {
    if (mode == PlayMode.list) return const Icon(Icons.repeat);
    if (mode == PlayMode.single) return const Icon(Icons.repeat_one);
    return const Icon(Icons.shuffle);
  }

  Widget _buildPlayPauseButton() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        iconSize: 40,
        color: Colors.white,
        icon: Icon(_controller._playing.value ? Icons.pause : Icons.play_arrow),
        onPressed: _controller._playOrPause,
      ),
    );
  }

  String _duration2String(Duration duration) {
    if (duration.inMilliseconds < 0) return "00:00";
    String twoDigits(int n) => n >= 10 ? "$n" : "0$n";
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    int inHours = duration.inHours;
    return inHours > 0
        ? "$inHours:$twoDigitMinutes:$twoDigitSeconds"
        : "$twoDigitMinutes:$twoDigitSeconds";
  }

  void _showPlayerList(BuildContext context) {
    if (_controller._audios.isEmpty) return;
    var scrollController = AutoScrollController();
    showModalBottomSheet(
        context: context,
        builder: (context) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Text(
                  "${Intl.audioPlayListDialog_title.tr}(${_controller._audios.length})",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(child: Obx(() => _playList(scrollController))),
            ],
          );
        });

    Future.delayed(const Duration(milliseconds: 200)).then((_) {
      scrollController.scrollToIndex(_controller._index,
          duration: const Duration(milliseconds: 50),
          preferPosition: AutoScrollPosition.begin);
    });
  }

  void _showSleepTimerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题 + 倒计时
                Row(
                  children: [
                    Text('定时关闭', style: Theme.of(ctx).textTheme.titleMedium),
                    const Spacer(),
                    Obx(() {
                      final remaining = _controller.sleepTimerRemaining.value;
                      final afterTrack = _controller.sleepAfterTrack.value;
                      if (remaining != null) {
                        final h = remaining.inHours.toString().padLeft(2, '0');
                        final m = (remaining.inMinutes % 60).toString().padLeft(2, '0');
                        final s = (remaining.inSeconds % 60).toString().padLeft(2, '0');
                        return Text('$h:$m:$s',
                            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold));
                      }
                      if (afterTrack) {
                        return Text('播完停止',
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                color: Colors.orangeAccent));
                      }
                      return const SizedBox.shrink();
                    }),
                    // 开关：有定时时显示，点击取消
                    Obx(() {
                      final active = _controller.sleepTimerRemaining.value != null ||
                          _controller.sleepAfterTrack.value;
                      if (!active) return const SizedBox.shrink();
                      return Switch(
                        value: true,
                        activeColor: Colors.red,
                        onChanged: (_) {
                          _controller.cancelSleepTimer();
                          setSheetState(() {});
                        },
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 16),
                // 快捷分钟选项（一行均匀分布）
                Obx(() {
                  final presets = [10, 20, 30, 45, 60, 90];
                  final remaining = _controller.sleepTimerRemaining.value;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: presets.map((min) {
                      final isSelected = remaining != null &&
                          (remaining.inMinutes - min).abs() <= 1 &&
                          !_controller.sleepAfterTrack.value;
                      return GestureDetector(
                        onTap: () {
                          _controller.startSleepTimer(min);
                          setSheetState(() {});
                        },
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.red
                                : Theme.of(ctx).colorScheme.surfaceVariant,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('$min',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.white : null)),
                              Text('min',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: isSelected ? Colors.white70 : null)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }),
                const SizedBox(height: 12),
                // 自定义按钮
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showCustomTimerDialog(context);
                    },
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('自定义时长'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const Divider(),
                // 播完整首再停
                Obx(() => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('播完整首音频再停止播放'),
                      value: _controller.sleepAfterTrack.value,
                      onChanged: (v) {
                        _controller.toggleSleepAfterTrack(v ?? false);
                        setSheetState(() {});
                      },
                    )),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCustomTimerDialog(BuildContext context) {
    int hours = 0;
    int minutes = 10;
    const itemH = 44.0;
    final hourCtrl = FixedExtentScrollController(initialItem: hours);
    final minCtrl = FixedExtentScrollController(initialItem: minutes);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: const Text('自定义关闭'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 选中行高亮 + 两个滚轮 + 冒号
                SizedBox(
                  height: itemH * 3,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 高亮条
                      Positioned(
                        top: itemH,
                        left: 0,
                        right: 0,
                        height: itemH,
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      // 滚轮行
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 小时
                          _buildWheelPicker(
                            controller: hourCtrl,
                            min: 0, max: 23,
                            itemH: itemH,
                            selectedColor: scheme.primary,
                            onChanged: (v) => setDialogState(() => hours = v),
                          ),
                          // 单位标签
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text('时', style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                          ),
                          // 分钟
                          _buildWheelPicker(
                            controller: minCtrl,
                            min: 0, max: 59,
                            itemH: itemH,
                            selectedColor: scheme.primary,
                            onChanged: (v) => setDialogState(() => minutes = v),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text('分', style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 预览
                Text(
                  '${hours.toString().padLeft(2, '0')} 小时 ${minutes.toString().padLeft(2, '0')} 分钟后暂停',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final total = hours * 60 + minutes;
                  if (total > 0) _controller.startSleepTimer(total);
                  Navigator.pop(ctx);
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWheelPicker({
    required FixedExtentScrollController controller,
    required int min,
    required int max,
    required double itemH,
    required Color selectedColor,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 64,
      height: itemH * 3,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: itemH,
        perspective: 0.003,
        diameterRatio: 2.0,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) => onChanged(min + i),
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: max - min + 1,
          builder: (ctx, i) {
            final selected = controller.hasClients &&
                controller.selectedItem == i;
            return Center(
              child: Text(
                (min + i).toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? selectedColor : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  ListView _playList(AutoScrollController scrollController) {
    return ListView.separated(
      controller: scrollController,
      itemBuilder: (context, index) =>
          _buildPlayListItem(scrollController, context, index),
      separatorBuilder: (context, index) => const Divider(),
      itemCount: _controller._audios.length,
    );
  }

  Widget _buildPlayListItem(AutoScrollController scrollController,
      BuildContext context, int index) {
    var isPlayingIndex = _controller._index == index;
    return AutoScrollTag(
      key: ValueKey(_controller._audios[index]),
      controller: scrollController,
      index: index,
      child: ListTile(
        title: Text(_controller._audios[index].name,
            style: isPlayingIndex
                ? TextStyle(color: Theme.of(context).colorScheme.primary)
                : const TextStyle()),
        onTap: () {
          Navigator.pop(context);
          if (_controller._index == index) {
            _controller._playOrPause();
          } else {
            _controller._play(index);
          }
        },
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _controller._remove(index),
        ),
      ),
    );
  }
}

class AudioPlayerScreenController extends GetxController {
  final RxList<AudioItem> _audios;
  int _index;
  final _playMode = PlayMode.list.obs;

  AudioPlayerScreenController(
      {required List<AudioItem> audios, required int index})
      : _audios = audios.obs,
        _index = index {
    if (_audios.isNotEmpty) {
      _name.value = _audios[_index].name;
    }
  }

  final _audioPlayer = AudioPlayer();
  final CancelToken _cancelToken = CancelToken();
  final _name = "".obs;
  final _artist = "".obs; // 艺术家信息（从音频元数据读取）
  late ConcatenatingAudioSource _playList;

  final _duration = const Duration().obs;
  final _currentPos = const Duration().obs;
  final _playing = false.obs;
  final _prepared = false.obs;
  final _seekPos = (-1.0).obs;

  final Rx<Uint8List?> coverArtBytes = Rx<Uint8List?>(null);
  int _coverFetchIndex = -1;

  // 收藏状态
  final isFavorite = false.obs;

  // 定时暂停
  final sleepTimerRemaining = Rx<Duration?>(null);
  final sleepAfterTrack = false.obs;
  Timer? _sleepTimer;
  bool _pendingPauseAfterTrack = false; // 倒计时到0且勾了播完停止，等曲目结束

  // 播完停止：暂存被移除的其他曲目（index -> AudioItem），key 为原始位置
  List<_StashedItem>? _stashedItems;

  // 静态封面缓存，跨页面实例保留，key = remotePath
  static final Map<String, Uint8List> _coverCache = {};
  // 静态艺术家缓存，与封面缓存同步
  static final Map<String, String> _artistCache = {};

  List<StreamSubscription> streamSubscriptions = [];
  DateTime _lastSaveTime = DateTime.now();

  @override
  void onInit() {
    super.onInit();
    if (_index < 0 || _index >= _audios.length) _index = 0;
    // Android 13+ 需要运行时申请通知权限，才能显示媒体通知栏
    Permission.notification.request();
    _createPlayListAndPlay();

    streamSubscriptions.add(_audioPlayer.durationStream.listen((event) {
      if (event != null) _duration.value = event;
    }));

    streamSubscriptions.add(_audioPlayer.positionStream.listen((event) {
      _currentPos.value = event;
      if (_duration.value.inMilliseconds < _currentPos.value.inMilliseconds) {
        _currentPos.value = _duration.value;
      }
      final now = DateTime.now();
      if (now.difference(_lastSaveTime).inSeconds >= 10) {
        _lastSaveTime = now;
        _saveProgress(_index);
      }
    }));

    streamSubscriptions.add(_audioPlayer.sequenceStateStream.listen((event) {
      if (event != null && _audios.isNotEmpty) {
        final prevIndex = _index;
        final newIndex = event.currentIndex;
        if (newIndex != prevIndex) {
          _saveProgress(prevIndex);
          _index = newIndex;
          _name.value = _audios[_index].name;
          // 先查缓存，有缓存直接显示，不闪烁默认封面
          final cached = _coverCache[_audios[_index].remotePath];
          if (cached != null) {
            coverArtBytes.value = cached.isNotEmpty ? cached : null;
            _artist.value = _artistCache[_audios[_index].remotePath] ?? '';
          } else {
            // 没缓存才清空，触发加载
            _artist.value = '';
            coverArtBytes.value = null;
            _fetchCoverArt(_index);
          }
          _checkFavoriteStatus(_index);
        } else {
          _index = newIndex;
          _name.value = _audios[_index].name;
        }
      }
    }));

    streamSubscriptions.add(_audioPlayer.playerStateStream.listen((state) {
      if (state.playing) {
        _prepared.value = true;
        _playing.value = true;
      } else {
        _playing.value = false;
      }
      // 曲目播完（processingState == completed 是切歌前的最后时机）
      if (state.processingState == ProcessingState.completed) {
        if (_playMode.value == PlayMode.single) return; // 单曲循环交给 LoopMode.one
        // sleepAfterTrack 勾选时列表只剩当前一首，completed 后不会切歌，直接 pause 即可
        if (sleepAfterTrack.value || _pendingPauseAfterTrack) {
          _pendingPauseAfterTrack = false;
          _audioPlayer.pause();
          return;
        }
        _playNext();
      }
    }));
  }

  void _createPlayListAndPlay() async {
    var sources = <AudioSource>[];
    for (var audio in _audios) {
      var uri = await FileUtils.makeFileLink(audio.remotePath, audio.sign);
      if (uri != null) sources.add(await _audioToUri(uri, audio));
    }
    _playList = ConcatenatingAudioSource(
      useLazyPreparation: true,
      shuffleOrder: DefaultShuffleOrder(),
      children: sources,
    );
    await _audioPlayer.setAudioSource(_playList, initialIndex: _index);
    await _audioPlayer.setLoopMode(LoopMode.all);
    await _restoreProgress(_index);
    final firstAudio = _audios[_index];
    if (_coverCache.containsKey(firstAudio.remotePath)) {
      final cached = _coverCache[firstAudio.remotePath]!;
      coverArtBytes.value = cached.isNotEmpty ? cached : null;
      _artist.value = _artistCache[firstAudio.remotePath] ?? '';
    } else {
      _fetchCoverArt(_index);
    }
    _checkFavoriteStatus(_index);
  }

  Future<AudioSource> _audioToUri(String uri, AudioItem audio) async {
    final mediaItem = MediaItem(id: audio.remotePath, title: audio.name);
    if (audio.localPath == null || audio.localPath!.isEmpty) {
      AlistDatabaseController databaseController = Get.find();
      UserController userController = Get.find();
      var user = userController.user.value;
      var record = await databaseController.downloadRecordRecordDao
          .findRecordByRemotePath(user.serverUrl, user.username, audio.remotePath);
      if (record != null && io.File(record.localPath).existsSync()) {
        audio.localPath = record.localPath;
      }
    }
    if (audio.localPath != null && audio.localPath!.isNotEmpty) {
      return ProgressiveAudioSource(Uri.file(audio.localPath!), tag: mediaItem);
    } else {
      if (GetPlatform.isDesktop) {
        return ProgressiveAudioSource(Uri.parse(uri), tag: mediaItem);
      } else if (audio.provider == "BaiduNetdisk") {
        return AlistLockCachingAudioSource(Uri.parse(uri),
            headers: {"User-Agent": "pan.baidu.com"}, tag: mediaItem);
      } else {
        return AudioSource.uri(Uri.parse(uri), tag: mediaItem);
      }
    }
  }

  Future<void> _fetchCoverArt(int index) async {
    if (index < 0 || index >= _audios.length) return;
    _coverFetchIndex = index;
    final audio = _audios[index];

    // 先查缓存，有就直接显示，不闪烁
    if (_coverCache.containsKey(audio.remotePath)) {
      final cached = _coverCache[audio.remotePath]!;
      coverArtBytes.value = cached.isNotEmpty ? cached : null;
      _artist.value = _artistCache[audio.remotePath] ?? '';
      return;
    }

    try {
      Metadata? meta;
      if (audio.localPath != null && audio.localPath!.isNotEmpty) {
        meta = await MetadataRetriever.fromFile(io.File(audio.localPath!));
      } else {
        final uri = await FileUtils.makeFileLink(audio.remotePath, audio.sign);
        if (uri != null) {
          final tmpDir = await getTemporaryDirectory();
          final tmpFile = io.File(
              '${tmpDir.path}/cover_${audio.remotePath.hashCode.abs()}.tmp');
          try {
            final resp = await Dio().get<List<int>>(uri,
                options: Options(
                  responseType: ResponseType.bytes,
                  headers: {'Range': 'bytes=0-524287'},
                  receiveTimeout: const Duration(seconds: 10),
                ));
            if (resp.data != null) {
              await tmpFile.writeAsBytes(resp.data!, flush: true);
              meta = await MetadataRetriever.fromFile(tmpFile);
            }
          } finally {
            if (await tmpFile.exists()) await tmpFile.delete();
          }
        }
      }
      if (_coverFetchIndex != index) return;
      final art = (meta?.albumArt != null && meta!.albumArt!.isNotEmpty)
          ? meta.albumArt!
          : null;
      // 读取艺术家信息
      final artists = meta?.trackArtistNames;
      final artistStr = (artists != null && artists.isNotEmpty)
          ? artists.join(' / ')
          : '';
      _artist.value = artistStr;
      _artistCache[audio.remotePath] = artistStr;
      if (art != null) {
        _coverCache[audio.remotePath] = art;
        coverArtBytes.value = art;
        // 把封面写到临时文件，更新通知栏 MediaItem 的 artUri
        _updateNotificationArt(index, art, audio);
      } else {
        _coverCache[audio.remotePath] = Uint8List(0);
        coverArtBytes.value = null;
      }
    } catch (_) {
      // 加载失败时才清空，不要在加载中途清空
      if (_coverFetchIndex == index) {
        _coverCache[audio.remotePath] = Uint8List(0);
        coverArtBytes.value = null;
      }
    }
  }

  /// 封面加载完成后更新通知栏封面
  Future<void> _updateNotificationArt(int index, Uint8List art, AudioItem audio) async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final artFile = io.File('${tmpDir.path}/cover_${audio.remotePath.hashCode.abs()}.jpg');
      await artFile.writeAsBytes(art);
      final artUri = artFile.uri;

      if (index >= _playList.length) return;

      final newTag = MediaItem(
        id: audio.remotePath,
        title: audio.name,
        artist: _artistCache[audio.remotePath] ?? '',
        artUri: artUri,
      );

      if (index == _index) {
        // 当前曲目：直接通过 AudioService 更新 MediaItem，不动 playlist，不打断播放
        try {
          await AudioService.customAction('updateMediaItem', {
            'id': newTag.id,
            'title': newTag.title,
            'artist': newTag.artist ?? '',
            'artUri': artUri.toString(),
          });
        } catch (_) {
          // customAction 不支持时降级：替换 source 并 seek 回原位
          final pos = _audioPlayer.position;
          final playing = _audioPlayer.playing;
          AudioSource newSource = await _buildSource(audio, newTag);
          await _playList.removeAt(index);
          await _playList.insert(index, newSource);
          await _audioPlayer.seek(pos, index: index);
          if (playing) _audioPlayer.play();
        }
      } else {
        // 非当前曲目：直接替换，不影响播放
        AudioSource newSource = await _buildSource(audio, newTag);
        await _playList.removeAt(index);
        await _playList.insert(index, newSource);
      }
    } catch (_) {}
  }

  Future<AudioSource> _buildSource(AudioItem audio, MediaItem tag) async {
    if (audio.localPath != null && audio.localPath!.isNotEmpty) {
      return ProgressiveAudioSource(Uri.file(audio.localPath!), tag: tag);
    }
    final uri = await FileUtils.makeFileLink(audio.remotePath, audio.sign);
    if (uri == null) return AudioSource.uri(Uri.parse(''), tag: tag);
    if (audio.provider == "BaiduNetdisk") {
      return AlistLockCachingAudioSource(Uri.parse(uri),
          headers: {"User-Agent": "pan.baidu.com"}, tag: tag);
    }
    return AudioSource.uri(Uri.parse(uri), tag: tag);
  }

  Future<void> _checkFavoriteStatus(int index) async {    if (index < 0 || index >= _audios.length) return;
    final audio = _audios[index];
    final user = Get.find<UserController>().user.value;
    final db = Get.find<AlistDatabaseController>();
    final record = await db.favoriteDao
        .findByPath(user.serverUrl, user.username, audio.remotePath);
    isFavorite.value = record != null;
  }

  Future<void> toggleFavorite() async {
    if (_index < 0 || _index >= _audios.length) return;
    final audio = _audios[_index];
    final user = Get.find<UserController>().user.value;
    final db = Get.find<AlistDatabaseController>();

    if (isFavorite.value) {
      await db.favoriteDao
          .deleteByPath(user.serverUrl, user.username, audio.remotePath);
      isFavorite.value = false;
      SmartDialog.showToast('已取消收藏');
    } else {
      await db.favoriteDao.insertRecord(Favorite(
        isDir: false,
        serverUrl: user.serverUrl,
        userId: user.username,
        remotePath: audio.remotePath,
        path: audio.remotePath,
        name: audio.name,
        size: audio.size,
        sign: audio.sign,
        thumb: null,
        modified: 0,
        provider: audio.provider ?? '',
        createTime: DateTime.now().millisecondsSinceEpoch,
      ));
      isFavorite.value = true;
      SmartDialog.showToast('已添加到收藏');
    }
  }

  void _playNext() {    _currentPos.value = const Duration(milliseconds: 0);
    if (_playMode.value == PlayMode.single) {
      // 单曲循环：重播当前
      _audioPlayer.seek(const Duration(milliseconds: 0));
      if (!_audioPlayer.playing) _audioPlayer.play();
      return;
    }
    if (_audioPlayer.hasNext) {
      _audioPlayer.seekToNext();
    } else {
      // 已是最后一首，回到第一首（random模式随机）
      final nextIndex = _playMode.value == PlayMode.random
          ? Random().nextInt(_audios.length)
          : 0;
      _audioPlayer.seek(const Duration(milliseconds: 0), index: nextIndex);
    }
    if (!_audioPlayer.playing) _audioPlayer.play();
  }

  void _playPrevious() {
    _currentPos.value = const Duration(milliseconds: 0);
    if (_playMode.value == PlayMode.single) {
      _audioPlayer.seek(const Duration(milliseconds: 0));
      if (!_audioPlayer.playing) _audioPlayer.play();
      return;
    }
    if (_audioPlayer.hasPrevious) {
      _audioPlayer.seekToPrevious();
    } else {
      final prevIndex = _playMode.value == PlayMode.random
          ? Random().nextInt(_audios.length)
          : _audios.length - 1;
      _audioPlayer.seek(const Duration(milliseconds: 0), index: prevIndex);
    }
    if (!_audioPlayer.playing) _audioPlayer.play();
  }

  void _playOrPause() async {
    if (_playing.value) {
      await _audioPlayer.pause();
    } else {
      if (_duration.value.inMilliseconds <= _currentPos.value.inMilliseconds) {
        await _audioPlayer.seek(const Duration(milliseconds: 0));
      }
      await _audioPlayer.play();
    }
  }

  void _play(int index) {
    final prevIndex = _index;
    _index = index;
    _currentPos.value = const Duration(milliseconds: 0);
    _audioPlayer.seek(Duration.zero, index: index);
    // 主动更新封面，不依赖 sequenceStateStream
    if (index != prevIndex) {
      _name.value = _audios[index].name;
      final cached = _coverCache[_audios[index].remotePath];
      if (cached != null) {
        coverArtBytes.value = cached.isNotEmpty ? cached : null;
        _artist.value = _artistCache[_audios[index].remotePath] ?? '';
      } else {
        _artist.value = '';
        coverArtBytes.value = null;
        _fetchCoverArt(index);
      }
      _checkFavoriteStatus(index);
    }
  }

  void _remove(int index) {
    if (_audios.length <= 1) {
      SmartDialog.showToast(Intl.audioPlayListDialog_tips_deleteTheLast.tr);
      return;
    }
    if (_index == index) _playNext();
    _playList.removeAt(index);
    _audios.removeAt(index);
  }

  void _changePlayMode() {
    if (_playMode.value == PlayMode.single) {
      _playMode.value = PlayMode.list;
      SmartDialog.showToast(Intl.audioPlayerScreen_btn_sequence.tr);
      _audioPlayer.setLoopMode(LoopMode.all);
      _audioPlayer.setShuffleModeEnabled(false);
    } else if (_playMode.value == PlayMode.list) {
      _playMode.value = PlayMode.random;
      SmartDialog.showToast(Intl.audioPlayerScreen_btn_shuffle.tr);
      _audioPlayer.setLoopMode(LoopMode.all);
      _audioPlayer.setShuffleModeEnabled(true);
    } else {
      _playMode.value = PlayMode.single;
      _audioPlayer.setLoopMode(LoopMode.one);
      SmartDialog.showToast(Intl.audioPlayerScreen_btn_repeatOne.tr);
    }
  }

  void _saveProgress(int index) {
    if (index < 0 || index >= _audios.length) return;
    final pos = _currentPos.value.inMilliseconds;
    final dur = _duration.value.inMilliseconds;
    if (dur <= 0) return;
    final audio = _audios[index];
    final db = Get.find<AlistDatabaseController>();
    final user = Get.find<UserController>().user.value;
    db.videoViewingRecordDao
        .findRecordByPath(user.baseUrl, user.username, audio.remotePath)
        .then((record) {
      final newRecord = VideoViewingRecord(
        id: record?.id,
        serverUrl: user.baseUrl,
        userId: user.username,
        videoSign: audio.sign ?? '',
        path: audio.remotePath,
        videoCurrentPosition: pos,
        videoDuration: dur,
      );
      if (record == null) {
        db.videoViewingRecordDao.insertRecord(newRecord);
      } else {
        db.videoViewingRecordDao.updateRecord(newRecord);
      }
    });
  }

  Future<void> _restoreProgress(int index) async {
    if (index < 0 || index >= _audios.length) return;
    final audio = _audios[index];
    final db = Get.find<AlistDatabaseController>();
    final user = Get.find<UserController>().user.value;
    final record = await db.videoViewingRecordDao
        .findRecordByPath(user.baseUrl, user.username, audio.remotePath);
    if (record != null &&
        record.videoCurrentPosition > 0 &&
        record.videoDuration > 0 &&
        record.videoCurrentPosition / record.videoDuration < 0.98) {
      await _audioPlayer.seek(
          Duration(milliseconds: record.videoCurrentPosition),
          index: index);
    }
    _audioPlayer.play();
  }

  @override
  void onClose() {
    super.onClose();
    _cancelToken.cancel();
    _saveProgress(_index);
    _sleepTimer?.cancel();
    _audioPlayer.stop().then((_) => _audioPlayer.dispose());
    for (var s in streamSubscriptions) {
      s.cancel();
    }
    streamSubscriptions = [];
  }

  // ── 定时暂停 ──────────────────────────────────────────────────────────────

  /// 开启定时暂停，[minutes] 分钟后暂停（不影响 sleepAfterTrack）
  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    final total = Duration(minutes: minutes);
    sleepTimerRemaining.value = total;

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final remaining = sleepTimerRemaining.value;
      if (remaining == null || remaining.inSeconds <= 0) {
        t.cancel();
        sleepTimerRemaining.value = null;
        if (sleepAfterTrack.value) {
          // 勾了播完停止：设标记，等当前曲目播完再暂停
          _pendingPauseAfterTrack = true;
        } else {
          // 没勾：立即暂停
          _audioPlayer.pause();
        }
        return;
      }
      sleepTimerRemaining.value = remaining - const Duration(seconds: 1);
    });
  }

  /// 切换"播完整首再停"（独立于倒计时）
  void toggleSleepAfterTrack(bool value) {
    sleepAfterTrack.value = value;
    if (value) {
      // 勾选：把当前项以外的所有曲目从播放列表移除并暂存
      _stashOtherTracks();
    } else {
      // 取消：恢复暂存的曲目
      _restoreStashedTracks();
    }
  }

  /// 把当前播放项以外的曲目暂存并从列表移除
  void _stashOtherTracks() {
    if (_audios.length <= 1) return;
    final stashed = <_StashedItem>[];
    // 从后往前移除，避免 index 偏移
    for (int i = _audios.length - 1; i >= 0; i--) {
      if (i != _index) {
        stashed.add(_StashedItem(originalIndex: i, audio: _audios[i]));
        _playList.removeAt(i);
        _audios.removeAt(i);
      }
    }
    // 移除后当前项一定在 index 0
    _index = 0;
    _stashedItems = stashed;
    // 切到 LoopMode.off，防止单首播完后循环
    _audioPlayer.setLoopMode(LoopMode.off);
  }

  /// 恢复暂存的曲目（按原始位置插回）
  void _restoreStashedTracks() async {
    final stashed = _stashedItems;
    if (stashed == null || stashed.isEmpty) return;
    _stashedItems = null;

    // 记住当前正在播放的曲目，恢复后重新找它的 index
    final currentAudio = _audios.isNotEmpty ? _audios[_index] : null;

    // 按 originalIndex 升序排列，依次插回
    stashed.sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
    for (final item in stashed) {
      final audio = item.audio;
      final uri = await FileUtils.makeFileLink(audio.remotePath, audio.sign);
      if (uri == null) continue;
      final source = await _audioToUri(uri, audio);
      final insertAt = item.originalIndex.clamp(0, _audios.length);
      _audios.insert(insertAt, audio);
      await _playList.insert(insertAt, source);
    }

    // 恢复后重新定位当前曲目的 index
    if (currentAudio != null) {
      final newIndex = _audios.indexWhere(
          (a) => a.remotePath == currentAudio.remotePath);
      if (newIndex >= 0) _index = newIndex;
    }
    // 恢复 LoopMode
    if (_playMode.value == PlayMode.single) {
      _audioPlayer.setLoopMode(LoopMode.one);
    } else {
      _audioPlayer.setLoopMode(LoopMode.all);
    }
  }

  /// 取消所有定时（倒计时 + 播完停止）
  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepTimerRemaining.value = null;
    if (sleepAfterTrack.value) {
      sleepAfterTrack.value = false;
      _restoreStashedTracks();
    }
    sleepAfterTrack.value = false;
    _pendingPauseAfterTrack = false;
  }
}

enum PlayMode { single, list, random }

class AudioItem {
  final String name;
  String? localPath;
  final String remotePath;
  final String? sign;
  final String? provider;
  final int size;

  AudioItem({
    required this.name,
    this.localPath,
    required this.remotePath,
    this.sign,
    this.provider,
    this.size = 0,
  });
}

/// 暂存被移除的曲目，记录原始位置
class _StashedItem {
  final int originalIndex;
  final AudioItem audio;
  _StashedItem({required this.originalIndex, required this.audio});
}

// ══════════════════════════════════════════════════════════════════════════════
// Bujuan 风格音频播放器 UI（新 UI，复用 AudioPlayerScreenController）
// ══════════════════════════════════════════════════════════════════════════════

class AudioPlayerScreenV2 extends StatefulWidget {
  const AudioPlayerScreenV2({Key? key}) : super(key: key);

  @override
  State<AudioPlayerScreenV2> createState() => _AudioPlayerScreenV2State();
}

class _AudioPlayerScreenV2State extends State<AudioPlayerScreenV2> {
  final List<AudioItem> _audios = Get.arguments["audios"] ?? [];
  final int _index = Get.arguments["index"] ?? 0;
  late AudioPlayerScreenController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        Get.put(AudioPlayerScreenController(audios: _audios, index: _index));
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── 主体布局 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverSize = MediaQuery.of(context).size.width - 48.0;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildTopBar(context),
            const SizedBox(height: 32),
            Center(child: _buildCoverArea(coverSize)),
            const SizedBox(height: 16),
            _buildTitleArea(scheme),
            const Spacer(),
            _buildProgressSection(scheme),
            const SizedBox(height: 4),
            _buildControls(scheme),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── 顶部栏：返回 + 收藏 ───────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: () => Get.back(),
          ),
          const Spacer(),
          // 收藏
          Obx(() => IconButton(
                icon: Icon(
                  _controller.isFavorite.value
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _controller.isFavorite.value ? Colors.red : null,
                ),
                onPressed: _controller.toggleFavorite,
              )),
        ],
      ),
    );
  }

  // ── 封面大图（圆角卡片，无唱片/唱针）────────────────────────────────────

  Widget _buildCoverArea(double size) {
    return Obx(() {
      final bytes = _controller.coverArtBytes.value;
      // 核心修复点：外层套一个 Center，防止父容器强制拉伸 SizedBox
      return Center(
        child: SizedBox(
          width: 280,
          height: 280,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: bytes != null
                  ? Image.memory(
                      bytes,
                      key: ValueKey(bytes.hashCode),
                      width: size,
                      height: size,
                      // BoxFit.cover 会填满正方形并裁剪多余部分，不会拉伸
                      fit: BoxFit.cover, 
                    )
                  : Image.asset(
                      'assets/images/cover.jpg',
                      key: const ValueKey('v2_cover_default'),
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
        ),
      );
    });
  }

  // ── 标题 + 艺术家 ─────────────────────────────────────────────────────────

  Widget _buildTitleArea(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
      child: Obx(() => Column(
            children: [
              Text(
                _controller._name.value,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (_controller._artist.value.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _controller._artist.value,
                  style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          )),
    );
  }

  // ── 曲线进度条 ────────────────────────────────────────────────────────────

  Widget _buildProgressSection(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Obx(() {
        if (!_controller._prepared.value) return const SizedBox(height: 60);
        final dur = _controller._duration.value.inMilliseconds.toDouble();
        final cur = _controller._seekPos.value > 0
            ? _controller._seekPos.value
            : _controller._currentPos.value.inMilliseconds.toDouble();
        final progress = dur > 0 ? (cur / dur).clamp(0.0, 1.0) : 0.0;

        return Column(
          children: [
            SizedBox(
              height: 40,
              child: _CurvedProgressBar(
                progress: progress,
                activeColor: scheme.primary,
                inactiveColor: scheme.primary.withOpacity(0.2),
                onChanged: (v) {
                  _controller._seekPos.value = dur * v;
                },
                onChangeEnd: (v) {
                  final pos = Duration(milliseconds: (dur * v).toInt());
                  _controller._currentPos.value = pos;
                  _controller._audioPlayer.seek(pos);
                  _controller._seekPos.value = -1;
                },
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _dur2Str(_controller._seekPos.value > 0
                      ? Duration(milliseconds: _controller._seekPos.value.toInt())
                      : _controller._currentPos.value),
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant),
                ),
                Text(
                  _dur2Str(_controller._duration.value),
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }

  // ── 控制按钮：循环模式 | 上一首 | 播放/暂停 | 下一首 | 定时关闭 ──────────

  Widget _buildControls(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 循环模式
          Obx(() => IconButton(
                iconSize: 26,
                icon: _playModeIcon(_controller._playMode.value),
                onPressed: _controller._changePlayMode,
              )),
          // 上一首
          Obx(() => IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: _controller._playMode.value == PlayMode.single ||
                        _controller._audios.length <= 1
                    ? null
                    : _controller._playPrevious,
              )),
          // 播放/暂停 — 大圆按钮，用主题色填充
          Obx(() => GestureDetector(
                onTap: _controller._playOrPause,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _controller._playing.value
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: scheme.onPrimary,
                    size: 36,
                  ),
                ),
              )),
          // 下一首
          Obx(() => IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: _controller._playMode.value == PlayMode.single ||
                        _controller._audios.length <= 1
                    ? null
                    : _controller._playNext,
              )),
          // 播放列表
          IconButton(
            iconSize: 26,
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => _showV2PlayerList(Get.context!),
          ),
          // 定时关闭
          Obx(() {
            final active = _controller.sleepTimerRemaining.value != null ||
                _controller.sleepAfterTrack.value;
            return IconButton(
              iconSize: 26,
              color: active ? Colors.orangeAccent : null,
              icon: const Icon(Icons.bedtime_outlined),
              onPressed: () => _showV2SleepTimerSheet(Get.context!),
            );
          }),
        ],
      ),
    );
  }

  Widget _playModeIcon(PlayMode mode) {
    if (mode == PlayMode.list) return const Icon(Icons.repeat);
    if (mode == PlayMode.single) return const Icon(Icons.repeat_one);
    return const Icon(Icons.shuffle);
  }

  String _dur2Str(Duration d) {
    if (d.inMilliseconds < 0) return "00:00";
    String two(int n) => n >= 10 ? "$n" : "0$n";
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return d.inHours > 0 ? "${d.inHours}:$m:$s" : "$m:$s";
  }

  void _showV2PlayerList(BuildContext context) {
    if (_controller._audios.isEmpty) return;
    final scrollController = AutoScrollController();
    showModalBottomSheet(
        context: context,
        builder: (context) => Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Text(
                  "${Intl.audioPlayListDialog_title.tr}(${_controller._audios.length})",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                  child: Obx(() => ListView.separated(
                        controller: scrollController,
                        itemCount: _controller._audios.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (ctx, i) {
                          final isPlaying = _controller._index == i;
                          return AutoScrollTag(
                            key: ValueKey(_controller._audios[i]),
                            controller: scrollController,
                            index: i,
                            child: ListTile(
                              title: Text(_controller._audios[i].name,
                                  style: isPlaying
                                      ? TextStyle(
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .primary)
                                      : null),
                              onTap: () {
                                Navigator.pop(context);
                                if (_controller._index == i) {
                                  _controller._playOrPause();
                                } else {
                                  _controller._play(i);
                                }
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => _controller._remove(i),
                              ),
                            ),
                          );
                        },
                      ))),
            ]));
    Future.delayed(const Duration(milliseconds: 200)).then((_) {
      scrollController.scrollToIndex(_controller._index,
          duration: const Duration(milliseconds: 50),
          preferPosition: AutoScrollPosition.begin);
    });
  }

  void _showV2SleepTimerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('定时关闭', style: Theme.of(ctx).textTheme.titleMedium),
                const Spacer(),
                Obx(() {
                  final r = _controller.sleepTimerRemaining.value;
                  if (r != null) {
                    return Text(
                        '${r.inHours.toString().padLeft(2, '0')}:${(r.inMinutes % 60).toString().padLeft(2, '0')}:${(r.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold));
                  }
                  if (_controller.sleepAfterTrack.value) {
                    return Text('播完停止',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.orangeAccent));
                  }
                  return const SizedBox.shrink();
                }),
                Obx(() {
                  final active =
                      _controller.sleepTimerRemaining.value != null ||
                          _controller.sleepAfterTrack.value;
                  if (!active) return const SizedBox.shrink();
                  return Switch(
                      value: true,
                      activeColor: Colors.red,
                      onChanged: (_) {
                        _controller.cancelSleepTimer();
                        setSheetState(() {});
                      });
                }),
              ]),
              const SizedBox(height: 16),
              Obx(() {
                final presets = [10, 20, 30, 45, 60, 90];
                final r = _controller.sleepTimerRemaining.value;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: presets.map((min) {
                    final sel = r != null &&
                        (r.inMinutes - min).abs() <= 1 &&
                        !_controller.sleepAfterTrack.value;
                    return GestureDetector(
                      onTap: () {
                        _controller.startSleepTimer(min);
                        setSheetState(() {});
                      },
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: sel
                              ? Colors.red
                              : Theme.of(ctx).colorScheme.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$min',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: sel ? Colors.white : null)),
                            Text('min',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: sel ? Colors.white70 : null)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              }),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showV2CustomTimerDialog(context);
                  },
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('自定义时长'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const Divider(),
              Obx(() => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('播完整首歌再停止播放'),
                    value: _controller.sleepAfterTrack.value,
                    onChanged: (v) {
                      _controller.toggleSleepAfterTrack(v ?? false);
                      setSheetState(() {});
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showV2CustomTimerDialog(BuildContext context) {
    int hours = 0;
    int minutes = 10;
    const itemH = 44.0;
    final hourCtrl = FixedExtentScrollController(initialItem: hours);
    final minCtrl = FixedExtentScrollController(initialItem: minutes);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: const Text('自定义关闭'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: itemH * 3,
                  child: Stack(alignment: Alignment.center, children: [
                    Positioned(
                      top: itemH,
                      left: 0,
                      right: 0,
                      height: itemH,
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _v2WheelPicker(
                            controller: hourCtrl,
                            min: 0,
                            max: 23,
                            itemH: itemH,
                            selectedColor: scheme.primary,
                            onChanged: (v) => set(() => hours = v)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text('时',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: scheme.onSurfaceVariant)),
                        ),
                        _v2WheelPicker(
                            controller: minCtrl,
                            min: 0,
                            max: 59,
                            itemH: itemH,
                            selectedColor: scheme.primary,
                            onChanged: (v) => set(() => minutes = v)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text('分',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: scheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Text(
                  '${hours.toString().padLeft(2, '0')} 小时 ${minutes.toString().padLeft(2, '0')} 分钟后暂停',
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final total = hours * 60 + minutes;
                  if (total > 0) _controller.startSleepTimer(total);
                  Navigator.pop(ctx);
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _v2WheelPicker({
    required FixedExtentScrollController controller,
    required int min,
    required int max,
    required double itemH,
    required Color selectedColor,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 64,
      height: itemH * 3,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: itemH,
        perspective: 0.003,
        diameterRatio: 2.0,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) => onChanged(min + i),
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: max - min + 1,
          builder: (ctx, i) {
            final sel =
                controller.hasClients && controller.selectedItem == i;
            return Center(
              child: Text(
                (min + i).toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  color: sel ? selectedColor : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── 曲线进度条 ────────────────────────────────

class _CurvedProgressBar extends StatefulWidget {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double> onChangeEnd;

  const _CurvedProgressBar({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<_CurvedProgressBar> createState() => _CurvedProgressBarState();
}

class _CurvedProgressBarState extends State<_CurvedProgressBar> {
  double _local = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _local = widget.progress;
  }

  @override
  void didUpdateWidget(covariant _CurvedProgressBar old) {
    super.didUpdateWidget(old);
    if (!_dragging && old.progress != widget.progress) {
      setState(() => _local = widget.progress);
    }
  }

  void _update(Offset pos, Size size) {
    final v = (pos.dx / size.width).clamp(0.0, 1.0);
    setState(() => _local = v);
    widget.onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final prog = _dragging ? _local : widget.progress;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox;
        setState(() { _dragging = true; });
        _update(d.localPosition, box.size);
      },
      onTapUp: (d) {
        final v = _local;
        setState(() => _dragging = false);
        widget.onChangeEnd(v);
      },
      onHorizontalDragStart: (d) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (d) {
        final box = context.findRenderObject() as RenderBox;
        _update(d.localPosition, box.size);
      },
      onHorizontalDragEnd: (_) {
        final v = _local;
        setState(() => _dragging = false);
        widget.onChangeEnd(v);
      },
      child: CustomPaint(
        size: Size(double.infinity, 40),
        painter: _CurvedProgressPainter(
          progress: prog,
          activeColor: widget.activeColor,
          inactiveColor: widget.inactiveColor,
        ),
      ),
    );
  }
}

class _CurvedProgressPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _CurvedProgressPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  Path _wavePath(Size size) {
    final path = Path();
    path.moveTo(0, size.height / 2);
    path.quadraticBezierTo(
        size.width / 4, -size.height / 3, size.width / 2, size.height / 2);
    path.quadraticBezierTo(
        3 * size.width / 4, size.height + size.height / 3, size.width, size.height / 2);
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final prog = progress.clamp(0.0, 1.0);
    final fullPath = _wavePath(size);

    // 背景轨道
    canvas.drawPath(
      fullPath,
      Paint()
        ..color = inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // 已播放部分
    final metrics = fullPath.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final metric = metrics.first;
      final activePath = metric.extractPath(0, metric.length * prog);
      canvas.drawPath(
        activePath,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );

      // 拖动圆点
      if (prog > 0) {
        final tangent = metric.getTangentForOffset(metric.length * prog);
        if (tangent != null) {
          canvas.drawCircle(tangent.position, 6,
              Paint()..color = Colors.white..style = PaintingStyle.fill);
          canvas.drawCircle(tangent.position, 6,
              Paint()..color = activeColor..style = PaintingStyle.stroke..strokeWidth = 2);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CurvedProgressPainter old) =>
      old.progress != progress || old.activeColor != activeColor;
}

// ── 波形进度条（内联，无需额外依赖）──────────────────────────────────────────

class _WaveformProgressWidget extends StatefulWidget {
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final Color? thumbColor;
  final ValueChanged<double> onChangeEnd;

  const _WaveformProgressWidget({
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    this.thumbColor,
    required this.onChangeEnd,
  });

  @override
  State<_WaveformProgressWidget> createState() =>
      _WaveformProgressWidgetState();
}

class _WaveformProgressWidgetState extends State<_WaveformProgressWidget> {
  late final List<double> _samples;
  bool _dragging = false;
  double _local = 0;

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    _samples = List.generate(150, (_) => 0.1 + rnd.nextDouble() * 0.8);
    _local = widget.progress;
  }

  @override
  void didUpdateWidget(covariant _WaveformProgressWidget old) {
    super.didUpdateWidget(old);
    if (!_dragging && old.progress != widget.progress) {
      setState(() => _local = widget.progress);
    }
  }

  double _toProgress(double dx, double w) => (dx / w).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final prog = _dragging ? _local : widget.progress;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (d) =>
            setState(() { _dragging = true; _local = _toProgress(d.localPosition.dx, w); }),
        onTapUp: (_) { final v = _local; setState(() => _dragging = false); widget.onChangeEnd(v); },
        onPanStart: (d) =>
            setState(() { _dragging = true; _local = _toProgress(d.localPosition.dx, w); }),
        onPanUpdate: (d) =>
            setState(() => _local = _toProgress(d.localPosition.dx, w)),
        onPanEnd: (_) { final v = _local; setState(() => _dragging = false); widget.onChangeEnd(v); },
        child: CustomPaint(
          size: Size(w, h),
          painter: _WaveformPainter(
            progress: prog,
            playedColor: widget.playedColor,
            unplayedColor: widget.unplayedColor,
            thumbColor: widget.thumbColor,
            samples: _samples,
          ),
        ),
      );
    });
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final Color? thumbColor;
  final List<double> samples;

  _WaveformPainter({
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.samples,
    this.thumbColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const bw = 2.0, sp = 4.0, total = bw + sp;
    final maxBars = (size.width / total).floor();
    final count = samples.length.clamp(0, maxBars);
    final prog = progress.clamp(0.0, 1.0);
    for (int i = 0; i < count; i++) {
      final bh = samples[i] * size.height * 0.8;
      final left = i * total;
      final top = (size.height - bh) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, bw, bh), const Radius.circular(3)),
        Paint()
          ..color =
              i <= (count * prog).floor() ? playedColor : unplayedColor
          ..style = PaintingStyle.fill,
      );
    }
    if (prog > 0 && prog < 1) {
      final px = (count * prog) * total;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(px - 1.5, 0, 3, size.height),
            const Radius.circular(3)),
        Paint()
          ..color = thumbColor ?? playedColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress || old.playedColor != playedColor;
}
