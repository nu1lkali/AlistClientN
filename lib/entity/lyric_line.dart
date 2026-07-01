/// 单行歌词数据模型
///
/// 包含该行的起始时间、结束时间（由下一行的起始时间推算）以及歌词文本内容。
/// startTime 和 endTime 用于定位当前播放进度对应的歌词行。
class LyricLine {
  /// 该行歌词的起始时间
  final Duration startTime;

  /// 该行歌词的结束时间（下一行的 startTime，最后一行使用一个极大值）
  final Duration endTime;

  /// 歌词文本内容（可能为空字符串，表示纯音乐间奏）
  final String content;

  const LyricLine({
    required this.startTime,
    required this.endTime,
    required this.content,
  });

  /// 该行是否为纯音乐行（无歌词文本）
  bool get isInstrumental => content.trim().isEmpty;

  @override
  String toString() =>
      'LyricLine(start: $startTime, end: $endTime, content: "$content")';
}
