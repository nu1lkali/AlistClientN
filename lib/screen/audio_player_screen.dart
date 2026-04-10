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
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
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
          var item = event.currentSource?.tag as MediaItem?;
          if (item?.id == _audios[_index].remotePath) {
            _name.value = _audios[_index].name;
            _artist.value = ''; // 切歌时先清空，等元数据加载
            final cached = _coverCache[_audios[_index].remotePath];
            if (cached != null) {
              coverArtBytes.value = cached.isNotEmpty ? cached : null;
              _artist.value = _artistCache[_audios[_index].remotePath] ?? '';
            } else {
              _fetchCoverArt(_index);
            }
            _checkFavoriteStatus(_index);
          }
        } else {
          _index = newIndex;
          var item = event.currentSource?.tag as MediaItem?;
          if (item?.id == _audios[_index].remotePath) {
            _name.value = _audios[_index].name;
          }
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
      // list模式播完最后一首循环回第一首，single/random由LoopMode处理
      if (state.processingState == ProcessingState.completed &&
          _playMode.value == PlayMode.list) {
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
      // 同步存入艺术家缓存（无论有没有封面都缓存，避免重复请求）
      _artistCache[audio.remotePath] = artistStr;
      if (art != null) {
        _coverCache[audio.remotePath] = art;
        coverArtBytes.value = art;
      } else {
        // 没有封面也标记已查询过，下次直接用缓存
        _coverCache[audio.remotePath] = Uint8List(0);
        coverArtBytes.value = null;
      }
    } catch (_) {
      if (_coverFetchIndex == index) coverArtBytes.value = null;
    }
  }

  Future<void> _checkFavoriteStatus(int index) async {
    if (index < 0 || index >= _audios.length) return;
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
    _index = index;
    _currentPos.value = const Duration(milliseconds: 0);
    _audioPlayer.seek(Duration.zero, index: index);
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
      _audioPlayer.setLoopMode(LoopMode.all); // list模式：循环播放
      _audioPlayer.setShuffleModeEnabled(false);
    } else if (_playMode.value == PlayMode.list) {
      _playMode.value = PlayMode.random;
      SmartDialog.showToast(Intl.audioPlayerScreen_btn_shuffle.tr);
      _audioPlayer.setLoopMode(LoopMode.all); // random模式：循环
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
    _audioPlayer.stop().then((_) => _audioPlayer.dispose());
    for (var s in streamSubscriptions) {
      s.cancel();
    }
    streamSubscriptions = [];
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
