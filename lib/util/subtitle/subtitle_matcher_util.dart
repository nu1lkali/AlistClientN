import 'dart:io';

import 'package:alist/util/constant.dart';
import 'package:alist/util/subtitle/subtitle_controller.dart';
import 'package:alist/util/subtitle/subtitle_matcher.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/foundation.dart';

/// 本地字幕匹配工具
///
/// 根据视频文件名，在用户配置的本地字幕目录中查找字幕文件。
/// 支持三种匹配模式：精确查找、模糊查找、双模式（先精确后模糊）。
/// 由 [SubtitleLoader] 在加载字幕时调用，使所有已集成字幕的播放器
/// （media_kit / 阿里云 / GSY 原生）都能按视频名自动加载本地字幕。
class SubtitleMatcherUtil {
  SubtitleMatcherUtil._();

  /// 支持的字幕扩展名
  static const _subtitleExts = ['.srt', '.ass', '.vtt', '.ssa', '.sub'];

  /// 根据视频文件名查找本地字幕。
  ///
  /// [videoName] 视频文件名，可带路径或后缀，如 "/movies/复仇者联盟.mp4"
  /// 或 "复仇者联盟.mp4"。函数内部只取最后一段并剥离后缀。
  ///
  /// 返回本地字幕文件的绝对路径（如 /storage/.../复仇者联盟.srt），
  /// 未开启、未配置目录、目录不可访问或未找到时返回 null。
  static Future<String?> findLocalSubtitle(String? videoName) async {
    if (videoName == null || videoName.isEmpty) return null;

    // 1. 检查总开关
    final enabled = SpUtil.getBool(AlistConstant.enableLocalSubtitle) ?? false;
    if (!enabled) return null;

    // 2. 检查目录路径有效性
    final dirPath = SpUtil.getString(AlistConstant.localSubtitlePath) ?? '';
    if (dirPath.isEmpty) return null;

    // 3. 读取匹配模式
    final modeIndex = SpUtil.getInt(AlistConstant.subtitleMatchMode) ?? 2; // 默认双模式
    final mode = SubtitleMatchMode.values[modeIndex.clamp(0, SubtitleMatchMode.values.length - 1)];

    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        SubtitleController.addLog('本地字幕目录不存在: $dirPath');
        return null;
      }

      // 4. 收集目录中所有字幕文件
      final subtitleFiles = <String>[];
      await for (final ent in dir.list()) {
        if (ent is File) {
          final ext = _getExtension(ent.path).toLowerCase();
          if (_subtitleExts.contains(ext)) {
            subtitleFiles.add(_baseName(ent.path));
          }
        }
      }

      if (subtitleFiles.isEmpty) {
        SubtitleController.addLog('本地字幕目录无字幕文件');
        return null;
      }

      // 5. 使用 SubtitleMatcher 查找匹配
      final matched = SubtitleMatcher.findMatchedSubtitles(videoName, subtitleFiles, mode);

      if (matched.isEmpty) {
        final videoId = SubtitleMatcher.extractId(videoName);
        final subIds = subtitleFiles.map((s) => SubtitleMatcher.extractId(s)).toList();
        SubtitleController.addLog('本地字幕未匹配 (模式: ${_modeLabel(mode)})');
        SubtitleController.addLog('  视频ID: $videoId, 字幕池ID: $subIds');
        return null;
      }

      // 6. 找到匹配，返回优先级最高的字幕文件路径
      // findMatchedSubtitles 已按匹配分数+格式优先级排序
      if (matched.length > 1) {
        SubtitleController.addLog('匹配到${matched.length}个字幕，按优先级排序: $matched');
      }
      final bestMatch = matched.first;
      final matchScore = SubtitleMatcher.fuzzyMatchScore(videoName, bestMatch);
      SubtitleController.addLog('最佳匹配: $bestMatch (分数: $matchScore)');
      // 查找实际文件路径（可能扩展名不同）
      await for (final ent in dir.list()) {
        if (ent is File) {
          final baseName = _baseName(ent.path);
          if (baseName.toLowerCase() == bestMatch.toLowerCase()) {
            SubtitleController.addLog('本地字幕匹配成功 (模式: ${_modeLabel(mode)}): ${ent.path}');
            return ent.path;
          }
        }
      }

      SubtitleController.addLog('本地字幕匹配成功但文件未找到: $bestMatch');
    } catch (e) {
      debugPrint('SubtitleMatcherUtil: 查找异常 -> $e');
      SubtitleController.addLog('本地字幕查找异常: $e');
    }
    return null;
  }

  /// 模式标签
  static String _modeLabel(SubtitleMatchMode mode) {
    switch (mode) {
      case SubtitleMatchMode.exact:
        return '精确';
      case SubtitleMatchMode.fuzzy:
        return '模糊';
      case SubtitleMatchMode.dual:
        return '双模式';
    }
  }

  /// 取路径最后一段（兼容 / 与 \ 分隔符）
  static String _baseName(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  /// 获取文件扩展名（含点号，如 .srt）
  static String _getExtension(String path) {
    final base = _baseName(path);
    final idx = base.lastIndexOf('.');
    return idx >= 0 ? base.substring(idx) : '';
  }
}