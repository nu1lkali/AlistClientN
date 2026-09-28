/// 视频格式的探测与归一化。
///
/// 网盘 / Emby 直链里的文件名远没有「xxx.mp4」这么规矩，常见三种变体：
/// - `abcdef.(wmv).strm`：真实扩展名被括号包起来（多为绕过网盘的扩展名检查）；
/// - `movie.mkv.strm`：外面套一层 .strm 壳（Emby / Infuse 的直链描述文件）；
/// - `8f3c9a1e2b`：彻底没有扩展名（随机名 / 加密名）。
///
/// 只按 `lastIndexOf('.')` 取扩展名会把上面三种全判错（.strm 既不在清单里，
/// 也不是真实容器）。这里统一先「去壳 → 再取真实扩展名」，都不行才退回 URL。
/// 认识的视频扩展名（小写、不含点）。
///
/// 用途有两个：① 判定一段尾巴到底算不算扩展名（排除随机串 / 版本号）；
/// ② 括号写法里只有命中本集合才认（`movie.mp4.(1)` 里的 `(1)` 不是格式）。
const Set<String> kKnownVideoExts = <String>{
  // ExoPlayer 硬解体验最好的一批
  'mp4', 'm4v', 'mov', 'mkv', 'webm', '3gp', '3g2', 'ogv', 'ogm',
  // Windows Media / ASF
  'wmv', 'wm', 'asf', 'asx', 'wmx', 'wvx', 'wtv', 'dvr-ms',
  // AVI / DivX / Xvid
  'avi', 'divx', 'xvid', 'nsv',
  // RealMedia
  'rmvb', 'rm', 'ra', 'ram',
  // MPEG-PS / Program Stream
  'mpg', 'mpeg', 'mpe', 'm1v', 'm2v', 'mp2', 'vcd', 'vob', 'dat',
  // MPEG-TS 家族
  'ts', 'm2ts', 'mts', 'm2t', 'tp', 'trp',
  // FLV 家族
  'flv', 'f4v',
  // ISO 镜像（DVD / BD 原盘）
  'iso',
};

/// 默认走 ExoPlayer 的格式清单（供设置页的预置配置使用）。
///
/// 与之对应的「走 libmpv 兼容内核」清单在 tiktok_playback_core.dart 的
/// kCompatFormatsHandledByMediaKit 里，两份合起来就是预置的默认配置。
const Set<String> kExoFriendlyFormats = <String>{
  'mp4', 'm4v', 'mov', 'mkv', 'webm', '3gp', '3g2', 'ogv', 'ogm',
};

/// 「壳」扩展名：不是真实容器，探测时先一层层剥掉。
const Set<String> kShellVideoExts = <String>{'strm'};

/// 探测结果。
class VideoFormatProbe {
  const VideoFormatProbe({this.ext, this.source = ''});

  /// 探测到的扩展名（小写、不含点）；null = 没探测出来。
  final String? ext;

  /// 线索来源：`bracket`（括号内）/ `name`（文件名）/ `url` / ''（没探测到）。
  final String source;

  bool get ok => ext != null;

  @override
  String toString() => ok ? '$ext($source)' : 'unknown';
}

/// 剥掉壳扩展名与路径，取末尾那一段当作扩展名。
String? tailExt(String input) {
  final dot = input.lastIndexOf('.');
  if (dot <= 0 || dot == input.length - 1) return null;
  final e = input.substring(dot + 1).toLowerCase();
  // 太长 / 含路径分隔符 / 不是纯格式字符 → 多半是随机串，不是扩展名
  // （长度上限放宽到 8 是为了 dvr-ms 这种带连字符的，反正最后还要命中已知清单）
  if (e.length > 8) return null;
  if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)?$').hasMatch(e)) return null;
  return e;
}

/// 从文件名（必要时再退回 URL）把真实格式挖出来。
///
/// 顺序：**括号写法 → 去壳后的末尾扩展名 → URL 路径**。
/// 三步都失败返回 [VideoFormatProbe.ok] == false，由上层走自动兜底
/// （容器嗅探 + Exo 优先 + 失败回落 libmpv）。
VideoFormatProbe probeVideoFormat(String fileName, {String? url}) {
  // ① 括号写法：abcdef.(wmv).strm / aaaaaaa.(wmv)
  //    取最后一个命中已知格式的括号（`movie.mp4.(1)` 这种重复下载的序号不算）
  String? bracket;
  for (final m in RegExp(r'\.\(([A-Za-z0-9]{1,5})\)').allMatches(fileName)) {
    final e = (m.group(1) ?? '').toLowerCase();
    if (kKnownVideoExts.contains(e)) bracket = e;
  }
  if (bracket != null) return VideoFormatProbe(ext: bracket, source: 'bracket');

  // ② 一层层剥掉 .strm 之类的壳，再取末尾扩展名
  var name = fileName.trim();
  // 先去掉重复下载标记 `movie.mp4.(1)`：括号里是数字而不是格式，不剥掉会挡住真扩展名
  while (true) {
    final dup = RegExp(r'\.\(\d{1,3}\)$').firstMatch(name);
    if (dup == null) break;
    name = name.substring(0, dup.start);
  }
  while (true) {
    final e = tailExt(name);
    if (e == null || !kShellVideoExts.contains(e)) break;
    name = name.substring(0, name.lastIndexOf('.'));
  }
  final nameExt = tailExt(name);
  if (nameExt != null && kKnownVideoExts.contains(nameExt)) {
    return VideoFormatProbe(ext: nameExt, source: 'name');
  }

  // ③ 文件名彻底没线索 → 看 URL（直链名是随机串，但路径末尾常带格式）
  if (url != null && url.isNotEmpty) {
    final path = url.split('?').first.split('#').first;
    final urlExt = tailExt(path);
    if (urlExt != null && kKnownVideoExts.contains(urlExt)) {
      return VideoFormatProbe(ext: urlExt, source: 'url');
    }
  }
  return const VideoFormatProbe();
}
