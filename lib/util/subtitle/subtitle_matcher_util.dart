import 'dart:io';

import 'package:alist/util/constant.dart';
import 'package:alist/util/subtitle/subtitle_controller.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/foundation.dart';

/// 本地字幕匹配工具
///
/// 根据视频文件名，在用户配置的本地字幕目录中查找同名 .srt 字幕文件。
/// 由 [SubtitleLoader] 在加载字幕时调用，使所有已集成字幕的播放器
/// （media_kit / 阿里云 / GSY 原生）都能按视频名自动加载本地字幕。
class SubtitleMatcherUtil {
  SubtitleMatcherUtil._();

  /// 根据视频文件名查找本地同名字幕。
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

    // 3. 剥离路径与后缀，得到视频基础名
    final base = _nameWithoutExt(_baseName(videoName));
    if (base.isEmpty) return null;

    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        SubtitleController.addLog('本地字幕目录不存在: $dirPath');
        return null;
      }

      // 4. 遍历目录，寻找同名 .srt（忽略大小写）
      final targetLow = '${base.toLowerCase()}.srt';
      await for (final ent in dir.list()) {
        if (ent is File) {
          if (_baseName(ent.path).toLowerCase() == targetLow) {
            SubtitleController.addLog('本地字幕匹配成功: ${ent.path}');
            return ent.path;
          }
        }
      }
      SubtitleController.addLog('本地字幕目录无同名 $base.srt');
    } catch (e) {
      debugPrint('SubtitleMatcherUtil: 查找异常 -> $e');
      SubtitleController.addLog('本地字幕查找异常: $e');
    }
    return null;
  }

  /// 取路径最后一段（兼容 / 与 \ 分隔符）
  static String _baseName(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  /// 剥离文件后缀
  static String _nameWithoutExt(String fileName) {
    final idx = fileName.lastIndexOf('.');
    return idx > 0 ? fileName.substring(0, idx) : fileName;
  }
}
