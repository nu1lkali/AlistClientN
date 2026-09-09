/// 播放器标题用的文件名处理。
///
/// 仅剥离「常见视频文件扩展名」（如 .mp4/.mkv），避免把包含多个点号
/// 的名称（如 www.98t.la@视频名、Emby 直链名）误当扩展名截断。
library;

const Set<String> _knownVideoExts = {
  '.mp4', '.mkv', '.avi', '.flv', '.mov', '.wmv', '.m4v', '.webm',
  '.ts', '.rmvb', '.rm', '.3gp', '.mpg', '.mpeg', '.vob', '.ogv',
  '.divx', '.iso', '.m2ts', '.tp', '.f4v',
};

/// 若 [fileName] 以常见视频扩展名结尾则去掉该扩展名，否则原样返回。
String stripKnownVideoExtension(String fileName) {
  final lower = fileName.toLowerCase();
  for (final ext in _knownVideoExts) {
    if (lower.endsWith(ext) && fileName.length > ext.length) {
      return fileName.substring(0, fileName.length - ext.length);
    }
  }
  return fileName;
}
