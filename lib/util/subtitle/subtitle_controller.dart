import 'dart:async';

import 'package:alist/util/subtitle/srt_parser.dart';
import 'package:alist/util/subtitle/subtitle_loader.dart';
import 'package:alist/util/subtitle/subtitle_model.dart';
import 'package:alist/util/subtitle/subtitle_settings.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:get/get.dart';

/// 字幕控制器
/// 负责协调字幕的加载、解析、时间轴同步
/// 作为播放器与字幕渲染之间的中间层
class SubtitleController extends GetxController {
  /// 当前已解析的字幕列表（按时间排序）
  final RxList<SubtitleItem> _subtitles = <SubtitleItem>[].obs;

  /// 当前应该显示的字幕文本（无字幕时为空字符串）
  final RxString currentText = ''.obs;

  /// 字幕是否已成功加载
  final RxBool isLoaded = false.obs;

  /// 字幕加载中
  final RxBool isLoading = false.obs;

  /// 字幕加载失败的错误信息
  final RxString errorMsg = ''.obs;

  /// 上次查找的字幕索引缓存，用于优化二分查找
  int _lastFoundIndex = -1;

  /// 全局设置引用
  final SubtitleSettings _settings = SubtitleSettings.instance;

  /// 加载字幕文件并解析
  ///
  /// [videoPath] 视频文件的本地路径（可能为 null，远程视频没有本地路径）
  /// [remotePath] 视频在 Alist 服务器上的远程路径（如 /movies/abc.mp4）
  /// [sign] 签名（某些受保护的文件需要）
  Future<void> loadSubtitle({
    String? videoPath,
    String? remotePath,
    String? sign,
  }) async {
    // 重置状态
    _reset();

    // 始终记录调用（用于排查）
    addLog('loadSubtitle 被调用, enabled=${_settings.isSubtitleEnabled.value}');

    // 如果字幕功能未启用，直接返回
    if (!_settings.isSubtitleEnabled.value) {
      debugPrint('SubtitleController: 字幕功能未启用，跳过加载');
      addLog('字幕功能已关闭，跳过加载');
      return;
    }

    // 如果既没有本地路径也没有远程路径，无法加载
    if ((videoPath == null || videoPath.isEmpty) &&
        (remotePath == null || remotePath.isEmpty)) {
      debugPrint('SubtitleController: 无可用路径，跳过加载');
      addLog('无可用路径，跳过加载');
      return;
    }

    isLoading.value = true;
    addLog('开始搜索字幕...');
    if (videoPath != null && videoPath.isNotEmpty) addLog('本地: $videoPath');
    if (remotePath != null && remotePath.isNotEmpty) addLog('远程: $remotePath');

    try {
      // 1. 加载字幕内容（自动尝试本地文件 + 远程 HTTP 下载）
      final content = await SubtitleLoader.loadSubtitleContent(
        videoPath: videoPath,
        remotePath: remotePath,
        sign: sign,
      );

      if (content == null || content.isEmpty) {
        errorMsg.value = '未找到同名字幕文件';
        isLoading.value = false;
        addLog('未找到同名字幕文件 (.srt)');
        return;
      }

      // 2. 使用 compute 在 Isolate 中解析 SRT（避免阻塞 UI 线程）
      final items = await compute(SrtParser.parse, content);

      if (items.isEmpty) {
        errorMsg.value = '字幕文件内容为空或格式错误';
        isLoading.value = false;
        return;
      }

      _subtitles.assignAll(items);
      isLoaded.value = true;
      isLoading.value = false;
      _lastFoundIndex = -1;

      debugPrint('SubtitleController: 字幕加载成功 -> ${items.length} 条字幕');
      addLog('字幕加载成功! 共 ${items.length} 条');
    } catch (e) {
      debugPrint('SubtitleController: 字幕加载异常 -> $e');
      errorMsg.value = '字幕加载失败: $e';
      isLoading.value = false;
      addLog('字幕加载异常: $e');
    }
  }

  /// 更新当前播放位置，触发字幕匹配
  ///
  /// [positionMs] 当前播放位置（毫秒）
  /// 此方法会被高频调用（每秒数十次），使用二分查找优化
  void updatePosition(int positionMs) {
    if (_subtitles.isEmpty) return;

    final subtitle = _findSubtitleAt(positionMs);
    if (subtitle != null) {
      if (currentText.value != subtitle.text) {
        currentText.value = subtitle.text;
      }
    } else {
      if (currentText.value.isNotEmpty) {
        currentText.value = '';
      }
    }
  }

  /// 使用二分查找在字幕列表中找到当前时间点对应的字幕
  ///
  /// 时间复杂度 O(log n)，适合高频调用场景
  /// 使用了 _lastFoundIndex 缓存优化连续调用场景
  SubtitleItem? _findSubtitleAt(int positionMs) {
    final subs = _subtitles;
    if (subs.isEmpty) return null;

    // 优化：先检查上次找到的位置附近（播放进度通常是连续的）
    if (_lastFoundIndex >= 0 && _lastFoundIndex < subs.length) {
      final lastItem = subs[_lastFoundIndex];
      // 仍在同一条字幕的时间范围内
      if (positionMs >= lastItem.startTimeMs &&
          positionMs < lastItem.endTimeMs) {
        return lastItem;
      }
      // 检查下一条字幕（自然过渡到下一条）
      final nextIdx = _lastFoundIndex + 1;
      if (nextIdx < subs.length) {
        final nextItem = subs[nextIdx];
        if (positionMs >= nextItem.startTimeMs &&
            positionMs < nextItem.endTimeMs) {
          _lastFoundIndex = nextIdx;
          return nextItem;
        }
      }
      // 检查上一条字幕（用户回退）
      final prevIdx = _lastFoundIndex - 1;
      if (prevIdx >= 0) {
        final prevItem = subs[prevIdx];
        if (positionMs >= prevItem.startTimeMs &&
            positionMs < prevItem.endTimeMs) {
          _lastFoundIndex = prevIdx;
          return prevItem;
        }
      }
    }

    // 缓存未命中，使用二分查找
    return _binarySearch(positionMs);
  }

  /// 二分查找：找到 startTimeMs <= positionMs 的最大索引
  /// 然后检查该字幕是否包含当前时间点
  SubtitleItem? _binarySearch(int positionMs) {
    final subs = _subtitles;
    int low = 0;
    int high = subs.length - 1;
    int candidate = -1;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final item = subs[mid];

      if (item.startTimeMs <= positionMs) {
        candidate = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (candidate < 0) {
      _lastFoundIndex = -1;
      return null;
    }

    final found = subs[candidate];
    if (positionMs >= found.startTimeMs && positionMs < found.endTimeMs) {
      _lastFoundIndex = candidate;
      return found;
    }

    _lastFoundIndex = candidate;
    return null;
  }

  /// 重置控制器状态
  void _reset() {
    _subtitles.clear();
    currentText.value = '';
    isLoaded.value = false;
    isLoading.value = false;
    errorMsg.value = '';
    _lastFoundIndex = -1;
  }

  /// 字幕日志（供设置页面查看）
  static final RxList<String> logs = <String>[].obs;

  /// 添加一条日志（public，供 SubtitleLoader 调用）
  static void addLog(String msg) {
    final time = DateTime.now();
    final ts = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    logs.add('[$ts] $msg');
    // 保留最近 200 条
    if (logs.length > 200) {
      logs.removeRange(0, logs.length - 200);
    }
  }

  /// 完全清理（退出播放器时调用）
  void clear() {
    _reset();
  }

  /// 获取已加载的字幕条数（用于调试/UI显示）
  int get subtitleCount => _subtitles.length;

  /// 获取字幕列表的只读副本（用于调试）
  List<SubtitleItem> get subtitles => List.unmodifiable(_subtitles);
}