/// 单条字幕数据模型
/// 包含字幕的起止时间和文本内容
class SubtitleItem {
  /// 字幕序号（来自 SRT 文件的序号，从 1 开始）
  final int index;

  /// 字幕开始时间（毫秒）
  final int startTimeMs;

  /// 字幕结束时间（毫秒）
  final int endTimeMs;

  /// 字幕文本内容（可能包含多行）
  final String text;

  const SubtitleItem({
    required this.index,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.text,
  });

  /// 格式化的开始时间（用于调试）
  String get startTimeFormatted => _formatMs(startTimeMs);

  /// 格式化的结束时间（用于调试）
  String get endTimeFormatted => _formatMs(endTimeMs);

  @override
  String toString() =>
      'SubtitleItem(#$index, $startTimeFormatted --> $endTimeFormatted, "$text")';

  /// 将毫秒转换为 HH:MM:SS,mmm 格式
  static String _formatMs(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')},'
        '${millis.toString().padLeft(3, '0')}';
  }
}