import 'package:alist/util/subtitle/subtitle_model.dart';

/// 纯 Dart 实现的高性能 SRT 字幕文件解析器
///
/// SRT 格式示例：
/// ```
/// 1
/// 00:00:01,000 --> 00:00:04,000
/// Hello, World!
///
/// 2
/// 00:00:05,500 --> 00:00:08,200
/// This is line one
/// This is line two
/// ```
class SrtParser {
  SrtParser._();

  /// 解析 SRT 字符串内容，返回按时间排序的字幕列表
  ///
  /// [content] SRT 文件的完整字符串内容
  /// 解析后的字幕列表，按 startTimeMs 升序排列
  static List<SubtitleItem> parse(String content) {
    if (content.trim().isEmpty) return const [];

    final items = <SubtitleItem>[];

    // 按空行分割字幕块（兼容 \r\n 和 \n）
    // 使用正则匹配一个或多个连续空行作为分隔符
    final blocks = content.split(RegExp(r'\r?\n\r?\n|\r?\n\r?\n\r?\n?'));

    for (final block in blocks) {
      final item = _parseBlock(block);
      if (item != null) {
        items.add(item);
      }
    }

    // 按开始时间排序（通常 SRT 已有序，但以防万一）
    items.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));

    return items;
  }

  /// 解析单个字幕块
  /// 一个字幕块的格式为：
  ///   序号
  ///   开始时间 --> 结束时间
  ///   字幕文本（可能多行）
  static SubtitleItem? _parseBlock(String block) {
    final lines = block.split(RegExp(r'\r?\n'));
    if (lines.length < 2) return null;

    int lineIndex = 0;

    // 第一行：字幕序号（跳过空行）
    while (lineIndex < lines.length && lines[lineIndex].trim().isEmpty) {
      lineIndex++;
    }
    if (lineIndex >= lines.length) return null;

    final indexStr = lines[lineIndex].trim();
    final index = int.tryParse(indexStr);
    if (index == null) return null;
    lineIndex++;

    // 第二行：时间戳行
    while (lineIndex < lines.length && lines[lineIndex].trim().isEmpty) {
      lineIndex++;
    }
    if (lineIndex >= lines.length) return null;

    final timeLine = lines[lineIndex].trim();
    final timeRange = _parseTimeRange(timeLine);
    if (timeRange == null) return null;
    lineIndex++;

    // 剩余行：字幕文本内容
    final textBuffer = StringBuffer();
    while (lineIndex < lines.length) {
      final line = lines[lineIndex].trim();
      if (line.isNotEmpty) {
        if (textBuffer.isNotEmpty) {
          textBuffer.write('\n');
        }
        textBuffer.write(line);
      }
      lineIndex++;
    }

    final text = textBuffer.toString().trim();
    if (text.isEmpty) return null;

    return SubtitleItem(
      index: index,
      startTimeMs: timeRange.$1,
      endTimeMs: timeRange.$2,
      text: text,
    );
  }

  /// 解析时间戳行
  /// 格式: "00:01:20,000 --> 00:01:23,123"
  /// 支持逗号和句点作为毫秒分隔符
  static (int, int)? _parseTimeRange(String line) {
    // 匹配时间戳格式，支持 "," 和 "." 作为毫秒分隔符
    // 同时支持 SRT 标准格式和一些变体
    final pattern = RegExp(
      r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})',
    );
    final match = pattern.firstMatch(line);
    if (match == null) return null;

    try {
      final startMs = _timeToMs(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
      );
      final endMs = _timeToMs(
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
        int.parse(match.group(7)!),
        int.parse(match.group(8)!),
      );
      return (startMs, endMs);
    } catch (_) {
      return null;
    }
  }

  /// 将时/分/秒/毫秒转换为总毫秒数
  static int _timeToMs(int hours, int minutes, int seconds, int milliseconds) {
    return hours * 3600000 + minutes * 60000 + seconds * 1000 + milliseconds;
  }
}