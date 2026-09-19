/// 字幕匹配模式
enum SubtitleMatchMode {
  /// 精确查找：文件名完全一致（去掉后缀和语言标记，忽略大小写）
  exact,
  /// 模糊查找：提取番号核心ID，字幕文件名包含该ID即可（忽略符号与大小写）
  fuzzy,
  /// 双模式：先精确，精确未命中再模糊
  dual,
}

/// 模糊匹配的最低可接受分数（低于此值视为不匹配）
const int kFuzzyAcceptScore = 70;

/// 参与模糊比对的最短核心串长度：低于此长度只认「完全相等」，
/// 避免 "1.mp4" 这类短名被 "13333.srt" 包含命中
const int kMinCoreLength = 3;

/// 匹配结果（带评分，分数越高匹配度越好）
class _MatchResult {
  final String subtitleName;
  final int score;
  _MatchResult(this.subtitleName, this.score);
}

/// 视频文件与字幕文件的智能匹配工具
///
/// 核心设计：**双向提取 + 多策略评分**
/// - 从视频名和字幕名**双方**都提取核心标识ID（番号等）
/// - 双方ID一致即为强匹配；单侧ID被另一侧清洗名包含则为弱匹配
/// - 增强污染清洗：剥离分辨率、编码格式、来源标签等常见噪音
class SubtitleMatcher {
  SubtitleMatcher._();

  // ==========================================
  // --- 预编译正则表达式 ---
  // ==========================================

  // 1. 标准番号：字母 + 可选分隔符 + 数字 (如 MIAA-003, HEYZO 0608, GACHI569, NEOB-017)
  static final _regStandard = RegExp(r'([a-zA-Z]{2,10})[-_\s]?(\d{2,8})');
  // 2. 短前缀番号：字母1位 + 数字 + 连字符 + 数字 (如 T28-569)
  static final _regShortPrefix = RegExp(r'([a-zA-Z])(\d+)-(\d+)');
  // 3. 纯数字番号：数字4-8位 + 连字符 + 数字2-4位 (如 112215-01)
  static final _regNumeric = RegExp(r'(\d{4,8})-(\d{2,4})');
  // 4. 单字母番号：字母1位 + 数字3-8位 (如 n0123)
  static final _regSingleLetter = RegExp(r'([a-zA-Z])(\d{3,8})');
  // 5. FC2番号：FC2 + 可选PPV + 5-7位数字 (如 FC2-PPV-123456, FC2-123456)
  static final _regFC2 = RegExp(r'FC2[-_\s]?(?:PPV[-_\s]?)?(\d{5,7})', caseSensitive: false);
  // 6. IBW带z后缀番号：IBW-123z
  static final _regIBWz = RegExp(r'(IBW)[-_\s]?(\d{2,5}z)', caseSensitive: false);
  // 7. 东热n/k系列：N1234, K1234
  static final _regTokyoHotNK = RegExp(r'(?:^|[-_\s])([NK]\d{4})(?:$|[-_\s])', caseSensitive: false);
  // 8. R18番号：R18-123
  static final _regR18 = RegExp(r'R18[-_\s]?(\d{3})', caseSensitive: false);

  // --- 污染清洗正则 ---

  // 方括号内容 [xxx]
  static final _regBrackets = RegExp(r'\[[^\]]*\]');
  // 圆括号内容 (xxx)
  static final _regParentheses = RegExp(r'\([^\)]*\)');
  // 网址前缀 www.xxx.com@ 或 xxx@
  static final _regWebPrefix = RegExp(r'(?:www\.)?[a-zA-Z0-9._-]+@');
  // 纯数字域名前缀 123.xxx
  static final _regNumericDomain = RegExp(r'^\d+\.[a-zA-Z]+\b');
  // 首尾多余符号
  static final _regTrimSymbols = RegExp(r'^[._\-\s]+|[._\-\s]+$');

  // --- 新增：分辨率/编码/来源等常见污染标签 ---
  // 分辨率: 1080p, 720p, 480p, 2160p, 4K, FHD, HD, UHD, SD
  static final _regResolution = RegExp(
    r'(?:^|[-_\s.])'
    r'(?:4K|UHD|FHD|HD|SD|1080[pi]|720[pi]|480[pi]|2160[pi])'
    r'(?:$|[-_\s.])',
    caseSensitive: false,
  );
  // 编码格式: x264, h264, x265, h265, HEVC, AVC, AV1, VP9, MPEG4
  static final _regCodec = RegExp(
    r'(?:^|[-_\s.])'
    r'(?:x264|h\.?264|x265|h\.?265|hevc|avc|av1|vp9|mpeg4?|mpeg2?)'
    r'(?:$|[-_\s.])',
    caseSensitive: false,
  );
  // 来源/格式: WEB-DL, BluRay, BDRip, BRRip, HDTV, WEBRip, HDRip, DVDRip, DVD, REMUX, NF, AMZN, DSNP, HMAX, DSNP
  static final _regSource = RegExp(
    r'(?:^|[-_\s.])'
    r'(?:WEB[-._]?DL|BluRay|BDRip|BRRip|HDTV|WEBRip|HDRip|DVDRip|REMUX|DVD|NF|AMZN|DSNP|HMAX|Disney|Netflix|Amazon)'
    r'(?:$|[-_\s.])',
    caseSensitive: false,
  );
  // 音频格式: AAC, FLAC, DTS, AC3, DD5.1, Atmos, TrueHD
  static final _regAudio = RegExp(
    r'(?:^|[-_\s.])'
    r'(?:AAC|FLAC|DTS|AC3|DD5\.1|Atmos|TrueHD|DDP?5\.1|DD\+?)'
    r'(?:$|[-_\s.])',
    caseSensitive: false,
  );
  // 色深/位深: 10bit, 8bit, 12bit, HDR, SDR, DolbyVision, DV
  static final _regBitDepth = RegExp(
    r'(?:^|[-_\s.])'
    r'(?:10bit|8bit|12bit|HDR|SDR|DolbyVision|DV|HDR10|HDR10\+|HLG|DoVi)'
    r'(?:$|[-_\s.])',
    caseSensitive: false,
  );
  // 常见中文污染标签（不需要分隔符，中文常直接紧贴番号）
  // 如 "neob-017中文字幕" → 去掉"中文字幕" → "neob-017"
  static final _regChinesePollution = RegExp(
    r'(?:中文字幕|繁体字幕|简体字幕|中英双字|双语字幕|中日字幕|中文字幕组|字幕组|字幕|中出|无码|有码|无修正|破解|破解版|高清|全集|完整版|精选|合集|番号|封面|'
    r'测试|样本|预览|试看|抢先|先行|泄漏|流出|限定|特典|初回|通常|独占|配信|'
    r'無碼|無修正|破解版|中文|繁体|简体|英文|日文|韩文|'
    r'自压|转载|整理|合成|压制|修复|增强)',
  );
  // 常见英文污染标签 (字幕相关): sub, subs, subtitle, subtitles, subbed
  static final _regSubLabel = RegExp(
    r'(?:^|[-_\s.])'
    r'(?:sub|subs|subtitle|subtitles|subbed|cc)'
    r'(?:$|[-_\s.])',
    caseSensitive: false,
  );

  // 连字符分隔的语言标记（如 -zh-CN, -zh-TW, -en, -ja 等）
  static final _regHyphenLangTag = RegExp(r'-[a-zA-Z]{1,4}(?:-[a-zA-Z0-9]{2,4})?$');

  /// 已知的扩展名及语言/编码标记（迭代剥离，解决多重后缀问题）
  static const _stripExtensions = {
    // 视频常见格式
    '.mp4', '.mkv', '.avi', '.wmv', '.flv', '.mov', '.webm', '.rmvb', '.ts', '.m4v',
    // 字幕常见格式
    '.srt', '.ass', '.vtt', '.ssa', '.sub',
    // 常见字幕语言、版本标识（带点号匹配）
    '.chs', '.cht', '.chi', '.gb', '.big5', '.chinese', '.cthd', '.csht',
    '.eng', '.en', '.jpn', '.ja', '.kor', '.ko', '.utf8',
    // 扩展语言标记（ISO 639-1 双字母代码 + 常见组合）
    '.zh', '.zh-cn', '.zh-tw', '.zh-hk', '.zh-sg', '.zh-mo',
    '.fr', '.fre', '.de', '.ger', '.es', '.spa', '.pt', '.por',
    '.it', '.ita', '.ru', '.rus', '.ar', '.ara', '.hi', '.hin',
    '.th', '.tha', '.vi', '.vie', '.id', '.ind', '.ms', '.may',
    '.nl', '.nld', '.pl', '.pol', '.sv', '.swe', '.da', '.dan',
    '.fi', '.fin', '.no', '.nor', '.hu', '.hun', '.cs', '.ces',
    '.ro', '.ron', '.bg', '.bul', '.hr', '.hrv', '.sk', '.slk',
    '.uk', '.ukr', '.he', '.heb', '.el', '.ell', '.tr', '.tur',
    '.ca', '.cat', '.en-us', '.en-gb', '.en-au', '.en-ca',
    // 常见的非标准后缀
    '.tc', '.sc',  // traditional/simplified Chinese shorthand
  };

  /// 用于匹配点号分隔的复合语言标记（如 .zh-CN, .en-US）
  /// 注意：此正则在 _nameWithoutExt 中与 _stripExtensions 配合使用，
  /// 专门处理 _stripExtensions 无法覆盖的复合语言标记
  /// 限制语言代码为 2-3 字母，避免误匹配 .Love .Part 等长单词
  static final _regDotLangTag = RegExp(r'\.([a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,4})?)$');

  // ==========================================
  // --- 核心方法：标识提取 ---
  // ==========================================

  /// 清洗文件名：剥离路径、多重扩展名、语言标记和常见污染标签
  ///
  /// 综合了 [_baseName] + [_nameWithoutExt] + [_deepClean] 的完整清洗流程。
  /// 例如: "[Thz.la]neob-017中文字幕.ja.srt" → "neob-017"
  ///        "www.98T.la@HEYZO-0806_iris2.mp4" → "heyzo-0806_iris2"
  static String cleanName(String fileName) {
    return _deepClean(_nameWithoutExt(_baseName(fileName)));
  }

  /// 从文件名中提取番号核心ID（返回标准的 "字母-数字" 或 "纯数字-数字" 格式）
  ///
  /// 保留旧名 [extractVideoId] 作为别名，保证向后兼容
  static String extractVideoId(String videoName) => extractId(videoName);

  /// 从文件名中提取核心标识ID
  ///
  /// 适用于视频和字幕双方，提取逻辑一致：
  /// 1. 先清洗污染（广告、分辨率、编码等标签）
  /// 2. 再用正则提取番号（参考 JavSp 算法，支持 FC2/IBW-z/东热等特殊番号）
  static String extractId(String fileName) {
    var name = _nameWithoutExt(_baseName(fileName));
    if (name.isEmpty) return '';

    name = _deepClean(name);

    // 0. FC2 番号（优先匹配，如 FC2-PPV-123456, FC2-123456）
    final fc2Match = _regFC2.firstMatch(name);
    if (fc2Match != null) {
      return 'FC2-${fc2Match.group(1)!}';
    }

    // 1. IBW带z后缀番号（如 IBW-123z，需在标准番号之前匹配）
    final ibwMatch = _regIBWz.firstMatch(name);
    if (ibwMatch != null) {
      return '${ibwMatch.group(1)!.toUpperCase()}-${ibwMatch.group(2)!}';
    }

    // 2. 标准番号（兼容了空格和无缝拼接，如 HEYZO 0608, NEOB-017, MIAA-003）
    final standardMatch = _regStandard.firstMatch(name);
    if (standardMatch != null) {
      return '${standardMatch.group(1)!.toUpperCase()}-${standardMatch.group(2)!}';
    }

    // 3. 短前缀番号：T28-569
    final shortPrefixMatch = _regShortPrefix.firstMatch(name);
    if (shortPrefixMatch != null) {
      return '${shortPrefixMatch.group(1)!.toUpperCase()}${shortPrefixMatch.group(2)!}-${shortPrefixMatch.group(3)!}';
    }

    // 4. 纯数字番号：112215-01
    final numericMatch = _regNumeric.firstMatch(name);
    if (numericMatch != null) {
      return '${numericMatch.group(1)!}-${numericMatch.group(2)!}';
    }

    // 5. 东热n/k系列：N1234, K1234
    final nkMatch = _regTokyoHotNK.firstMatch(name);
    if (nkMatch != null) {
      return nkMatch.group(1)!.toUpperCase();
    }

    // 6. R18番号：R18-123
    final r18Match = _regR18.firstMatch(name);
    if (r18Match != null) {
      return 'R18-${r18Match.group(1)!}';
    }

    // 7. 单字母番号：n0123 (排除 x264/h265 干扰)
    final singleLetterMatch = _regSingleLetter.firstMatch(name);
    if (singleLetterMatch != null) {
      final letter = singleLetterMatch.group(1)!.toLowerCase();
      if (letter != 'x' && letter != 'h') {
        return '${singleLetterMatch.group(1)!.toUpperCase()}${singleLetterMatch.group(2)!}';
      }
    }

    // 8. 无法提取番号时返回空串。
    //    旧实现这里退化成「返回整个清洗名」，于是 "1.mp4" 的 ID 变成 "1"，
    //    再被 "13333.srt" 的 contains 判定命中（"13333".contains("1")）→ 误匹配。
    //    提取失败就是没有番号，返回空，交由词元/相似度策略处理。
    return '';
  }

  /// 从文件名中提取所有可能的番号核心ID
  ///
  /// 与 [extractId] 不同，此方法返回所有匹配到的ID列表，
  /// 适用于文件名中包含多个番号片段的场景。
  static List<String> extractAllIds(String fileName) {
    var name = _nameWithoutExt(_baseName(fileName));
    if (name.isEmpty) return [];

    name = _deepClean(name);
    final ids = <String>[];
    final seen = <String>{};

    // FC2番号
    for (final m in _regFC2.allMatches(name)) {
      final id = 'FC2-${m.group(1)!}';
      if (seen.add(id)) ids.add(id);
    }

    // IBW带z后缀番号
    for (final m in _regIBWz.allMatches(name)) {
      final id = '${m.group(1)!.toUpperCase()}-${m.group(2)!}';
      if (seen.add(id)) ids.add(id);
    }

    // 标准番号
    for (final m in _regStandard.allMatches(name)) {
      final id = '${m.group(1)!.toUpperCase()}-${m.group(2)!}';
      if (seen.add(id)) ids.add(id);
    }

    // 短前缀番号
    for (final m in _regShortPrefix.allMatches(name)) {
      final id = '${m.group(1)!.toUpperCase()}${m.group(2)!}-${m.group(3)!}';
      if (seen.add(id)) ids.add(id);
    }

    // 纯数字番号
    for (final m in _regNumeric.allMatches(name)) {
      final id = '${m.group(1)!}-${m.group(2)!}';
      if (seen.add(id)) ids.add(id);
    }

    // 东热n/k系列
    for (final m in _regTokyoHotNK.allMatches(name)) {
      final id = m.group(1)!.toUpperCase();
      if (seen.add(id)) ids.add(id);
    }

    // R18番号
    for (final m in _regR18.allMatches(name)) {
      final id = 'R18-${m.group(1)!}';
      if (seen.add(id)) ids.add(id);
    }

    // 单字母番号
    for (final m in _regSingleLetter.allMatches(name)) {
      final letter = m.group(1)!.toLowerCase();
      if (letter != 'x' && letter != 'h') {
        final id = '${m.group(1)!.toUpperCase()}${m.group(2)!}';
        if (seen.add(id)) ids.add(id);
      }
    }

    return ids;
  }

  // ==========================================
  // --- 文件名特征抽取（新版匹配的核心） ---
  // ==========================================

  /// 剧集信息（季/集），任一端缺失都为 null
  static final _regSeasonEpisode =
      RegExp(r's(\d{1,2})[.\-\s_]?e(\d{1,3})(?![0-9])', caseSensitive: false);
  static final _regEpisodeOnly =
      RegExp(r'(?:^|[^a-z])e[p]?[.\-\s_]?(\d{1,3})(?![0-9])', caseSensitive: false);
  static final _regSeasonOnly =
      RegExp(r'(?:^|[^a-z])s[e]?[.\-\s_]?(\d{1,2})(?![0-9])', caseSensitive: false);
  static final _regCjkEpisode = RegExp(r'第\s*(\d{1,3})\s*[集话]');
  /// 归一化核心串：只保留字母、数字、中文，其余符号全部丢弃
  static final _regKeepChars = RegExp(r'[^a-z0-9\u4e00-\u9fff]');
  /// 词元切分：英文单词 / 数字串 / 单个汉字
  static final _regToken = RegExp(r'[a-z]+|\d+|[\u4e00-\u9fff]');
  static final _regPureDigits = RegExp(r'^\d+$');

  /// 解析文件名特征（清洗 → 归一化 → 抽番号/剧集/词元）
  static _NameFeatures _featuresOf(String fileName) {
    final cleaned = _deepClean(_nameWithoutExt(_baseName(fileName)));
    // 点号视为分隔符，让 "HEYZO.0806" 也能命中番号正则
    final idSource = cleaned.replaceAll('.', ' ');
    final core = cleaned.toLowerCase().replaceAll(_regKeepChars, '');

    return _NameFeatures(
      core: core,
      ids: extractAllIds(idSource)
          .map((e) => e.toLowerCase().replaceAll(_regKeepChars, ''))
          .where((e) => e.isNotEmpty)
          .toList(),
      tokens: _regToken.allMatches(core).map((m) => m.group(0)!).toSet(),
      season: _seasonOf(cleaned),
      episode: _episodeOf(cleaned),
    );
  }

  static int? _seasonOf(String cleaned) {
    final se = _regSeasonEpisode.firstMatch(cleaned);
    if (se != null) return int.tryParse(se.group(1)!);
    final s = _regSeasonOnly.firstMatch(cleaned);
    return s == null ? null : int.tryParse(s.group(1)!);
  }

  static int? _episodeOf(String cleaned) {
    final se = _regSeasonEpisode.firstMatch(cleaned);
    if (se != null) return int.tryParse(se.group(2)!);
    final e = _regEpisodeOnly.firstMatch(cleaned);
    if (e != null) return int.tryParse(e.group(1)!);
    final cjk = _regCjkEpisode.firstMatch(cleaned);
    return cjk == null ? null : int.tryParse(cjk.group(1)!);
  }

  /// 数值相等比较（忽略前导零）："01" == "1"，"0806" == "806"
  static bool _numEq(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    final na = int.tryParse(a);
    final nb = int.tryParse(b);
    if (na != null && nb != null) return na == nb;
    return a == b;
  }

  /// 词元拼接串（用于把 "miaa"+"003" 还原成 "miaa003" 做边界包含判断）
  static String _joinedTokens(Set<String> tokens) => tokens.join();

  /// 带边界的包含判断：needle 在 haystack 中，且两侧不直接粘连字母/数字
  static bool _containsBounded(String haystack, String needle) {
    if (needle.isEmpty || haystack.isEmpty) return false;
    final idx = haystack.indexOf(needle);
    if (idx < 0) return false;
    final before = idx > 0 ? haystack[idx - 1] : '';
    final afterIdx = idx + needle.length;
    final after = afterIdx < haystack.length ? haystack[afterIdx] : '';
    const alnum = 'abcdefghijklmnopqrstuvwxyz0123456789';
    if (before.isNotEmpty && alnum.contains(before)) return false;
    if (after.isNotEmpty && alnum.contains(after)) return false;
    return true;
  }

  /// Dice 二元文法相似度（0~1），中英文通用
  static double _dice(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a.length < 2 || b.length < 2) return a == b ? 1.0 : 0.0;
    final ba = _bigrams(a);
    final bb = _bigrams(b);
    var common = 0;
    for (final g in ba) {
      if (bb.remove(g)) common++;
    }
    return 2.0 * common / (ba.length + bb.length);
  }

  static List<String> _bigrams(String s) {
    final list = <String>[];
    for (var i = 0; i < s.length - 1; i++) {
      list.add(s.substring(i, i + 2));
    }
    return list;
  }

  // ==========================================
  // --- 污染清洗 ---
  // ==========================================

  /// 深度清洗：去除广告、分辨率、编码、来源等污染标签
  ///
  /// 相比旧版 [_cleanPrefix]，增加了对分辨率/编码/来源等标签的剥离，
  /// 使得提取番号时不受这些噪音干扰。
  static String _deepClean(String name) {
    var result = name;

    // 第1步：去除方括号和圆括号内容（广告、标签组）
    result = result.replaceAll(_regBrackets, '');
    result = result.replaceAll(_regParentheses, '');

    // 第2步：去除网址前缀
    result = result.replaceAll(_regWebPrefix, '');
    result = result.replaceAll(_regNumericDomain, '');

    // 第3步：去除中文污染标签（直接替换为空，中文常紧贴番号无分隔符）
    // 如 "neob-017中文字幕" → "neob-017"
    result = result.replaceAll(_regChinesePollution, '');

    // 第4步：去除分辨率标签（1080p, 720p, 4K, FHD, HD 等）
    result = _removeTag(result, _regResolution);

    // 第5步：去除编码格式标签（x264, h265, HEVC 等）
    result = _removeTag(result, _regCodec);

    // 第6步：去除来源标签（WEB-DL, BluRay 等）
    result = _removeTag(result, _regSource);

    // 第7步：去除音频标签（AAC, DTS, Atmos 等）
    result = _removeTag(result, _regAudio);

    // 第8步：去除色深/位深标签（10bit, HDR, DV 等）
    result = _removeTag(result, _regBitDepth);

    // 第9步：去除字幕标签（sub, subtitle 等）
    result = _removeTag(result, _regSubLabel);

    // 第10步：清理首尾多余符号 + 合并连续分隔符
    result = result.trim();
    result = result.replaceAll(RegExp(r'[-_\s]{2,}'), '_');
    result = result.replaceAll(_regTrimSymbols, '');

    return result;
  }

  /// 安全移除标签正则匹配到的内容，保留分隔符位置的整洁
  static String _removeTag(String input, RegExp pattern) {
    // 将匹配到的标签替换为空，但需处理边界分隔符
    var result = input;
    // 直接替换匹配内容为空（正则已包含边界分隔符的处理）
    result = result.replaceAll(pattern, '_');
    // 清理可能产生的连续下划线
    result = result.replaceAll(RegExp(r'_{2,}'), '_');
    return result;
  }

  // ==========================================
  // --- 匹配方法 ---
  // ==========================================

  /// 精确匹配：剥离后缀和语言标记后文件名一致（忽略大小写与分隔符差异）
  static bool isExactMatch(String videoName, String subtitleName) {
    final videoBase = _nameWithoutExt(_baseName(videoName)).toLowerCase();
    final subBase = _nameWithoutExt(_baseName(subtitleName)).toLowerCase();
    if (videoBase == subBase) return true;
    // 容忍分隔符/符号差异："Movie Name" 与 "Movie.Name"
    return _featuresOf(videoName).core == _featuresOf(subtitleName).core;
  }

  /// 模糊匹配：是否达到可接受分数（[kFuzzyAcceptScore]）
  static bool isFuzzyMatch(String videoName, String subtitleName) {
    return fuzzyMatchScore(videoName, subtitleName) >= kFuzzyAcceptScore;
  }

  /// 计算匹配分数（0 = 不匹配，越高越好）
  ///
  /// 新版评分（**不再用子串包含判断数字**，避免 "1.mp4" 命中 "13333.srt"）：
  /// - 100：归一化核心串完全一致
  /// - 95 ：双方番号一致
  /// - 92/88：单侧番号，另一侧核心串等于/词元边界包含该番号
  /// - 90 ：双方都是纯数字且数值相等
  /// - 85 ：核心串互相包含（字幕名比视频名多一段常见后缀）
  /// - 80 ：词元集合包含
  /// - 70~90：Dice 相似度兜底（要求存在公共锚点词元）
  static int fuzzyMatchScore(String videoName, String subtitleName) {
    final v = _featuresOf(videoName);
    final s = _featuresOf(subtitleName);
    if (v.core.isEmpty || s.core.isEmpty) return 0;

    // 0. 核心串过短（如 "1"、"12"）：只认完全相等，杜绝短串被长串包含
    final shorter = v.core.length <= s.core.length ? v.core : s.core;
    if (shorter.length < kMinCoreLength) {
      return v.core == s.core ? 100 : 0;
    }

    // 1. 核心串完全一致
    if (v.core == s.core) return 100;

    // 2. 剧集硬约束：双方都解析出集号且不一致 → 直接判定不是同一集
    if (v.episode != null && s.episode != null && v.episode != s.episode) {
      return 0;
    }
    if (v.season != null && s.season != null && v.season != s.season) {
      return 0;
    }

    // 3. 番号：双方都有 → 必须一致；只有一方有 → 看另一侧能否还原该番号
    if (v.ids.isNotEmpty && s.ids.isNotEmpty) {
      return _idsIntersect(v.ids, s.ids) ? 95 : 0;
    }
    if (v.ids.isNotEmpty || s.ids.isNotEmpty) {
      final withId = v.ids.isNotEmpty ? v : s;
      final other = v.ids.isNotEmpty ? s : v;
      var best = 0;
      for (final id in withId.ids) {
        if (other.core == id) return 92;
        if (_containsBounded(other.core, id) ||
            _containsBounded(_joinedTokens(other.tokens), id)) {
          best = best < 88 ? 88 : best;
          continue;
        }
        // 番号的数字部分独立出现（如 HEYZO-0806 vs 0806.srt）：只给低分，
        // 需要配合词元证据才可能过线，避免纯数字误命中
        final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length >= 3 && other.numbers.any((n) => _numEq(n, digits))) {
          best = best < 62 ? 62 : best;
        }
      }
      return best;
    }

    // 4. 纯数字：必须数值相等，**绝不做子串包含**
    final vDigits = _regPureDigits.hasMatch(v.core);
    final sDigits = _regPureDigits.hasMatch(s.core);
    if (vDigits || sDigits) {
      final digits = vDigits ? v.core : s.core;
      final other = vDigits ? s : v;
      if (vDigits && sDigits) return _numEq(v.core, s.core) ? 90 : 0;
      if (digits.length < 3) return 0;
      return other.numbers.any((n) => _numEq(n, digits)) ? 85 : 0;
    }

    // 5. 核心串包含：字幕名 = 视频名 + 额外标记（年份、版本等）
    if (v.core.contains(s.core) || s.core.contains(v.core)) {
      return 85;
    }

    // 6. 词元集合包含（英文/中文混排场景）
    final small = v.tokens.length <= s.tokens.length ? v : s;
    final big = small == v ? s : v;
    if (small.tokens.isNotEmpty && small.tokens.every(big.tokens.contains)) {
      final hasAnchor =
          small.tokens.any((t) => t.length >= 3) || small.tokens.length >= 2;
      if (hasAnchor) return 80;
    }

    // 7. 相似度兜底：Dice ≥ 0.7 且存在长度≥2的公共锚点词元
    final sim = _dice(v.core, s.core);
    final anchor = v.tokens.intersection(s.tokens).any((t) => t.length >= 2);
    if (sim >= 0.7 && anchor) {
      return (60 + sim * 30).round().clamp(kFuzzyAcceptScore, 90);
    }

    return 0;
  }

  static bool _idsIntersect(List<String> a, List<String> b) {
    for (final id in a) {
      if (b.contains(id)) return true;
    }
    return false;
  }

  /// 字幕格式优先级权重
  static const _formatPriority = {'.srt': 0, '.ass': 1, '.vtt': 2, '.ssa': 3, '.sub': 4};

  /// 对匹配到的字幕列表按优先级排序
  /// 规则：1. 格式优先 (.srt > .ass)  2. 同格式选文件名最短的（越接近原始名越纯净）
  static List<String> prioritizeSubtitles(List<String> matchedSubtitles) {
    if (matchedSubtitles.length <= 1) return matchedSubtitles;
    final sorted = List<String>.from(matchedSubtitles);
    sorted.sort((a, b) {
      final extA = _getExtension(a).toLowerCase();
      final extB = _getExtension(b).toLowerCase();
      final priA = _formatPriority[extA] ?? 99;
      final priB = _formatPriority[extB] ?? 99;

      if (priA != priB) return priA.compareTo(priB);

      final nameA = _nameWithoutExt(_baseName(a));
      final nameB = _nameWithoutExt(_baseName(b));
      return nameA.length.compareTo(nameB.length);
    });
    return sorted;
  }

  /// 从字幕池中查找匹配的字幕列表
  ///
  /// 返回顺序：**匹配分数降序** → 格式优先级 → 文件名长度升序。
  /// （旧实现先用分数排序、再用 prioritizeSubtitles 重排，分数顺序被覆盖掉，
  ///  会出现 80 分的 .srt 压过 100 分的 .ass 的情况。）
  static List<String> findMatchedSubtitles(
    String videoName,
    List<String> subtitlePool,
    SubtitleMatchMode mode,
  ) {
    if (videoName.isEmpty || subtitlePool.isEmpty) return [];

    final scored = <_MatchResult>[];
    switch (mode) {
      case SubtitleMatchMode.exact:
        for (final sub in subtitlePool) {
          if (isExactMatch(videoName, sub)) {
            scored.add(_MatchResult(sub, 100));
          }
        }
        break;
      case SubtitleMatchMode.fuzzy:
        scored.addAll(_scoredMatches(videoName, subtitlePool));
        break;
      case SubtitleMatchMode.dual:
        final exact = <_MatchResult>[];
        for (final sub in subtitlePool) {
          if (isExactMatch(videoName, sub)) {
            exact.add(_MatchResult(sub, 100));
          }
        }
        if (exact.isNotEmpty) {
          scored.addAll(exact);
          break;
        }
        scored.addAll(_scoredMatches(videoName, subtitlePool));
        break;
    }

    _sortScored(scored);
    return scored.map((r) => r.subtitleName).toList();
  }

  /// 逐个计算分数并过滤掉低于阈值的
  static List<_MatchResult> _scoredMatches(
      String videoName, List<String> subtitlePool) {
    final scored = <_MatchResult>[];
    for (final sub in subtitlePool) {
      final score = fuzzyMatchScore(videoName, sub);
      if (score >= kFuzzyAcceptScore) {
        scored.add(_MatchResult(sub, score));
      }
    }
    return scored;
  }

  /// 排序：分数降序 → 格式优先级 → 文件名长度升序
  static void _sortScored(List<_MatchResult> scored) {
    scored.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      final priA = _formatPriority[_getExtension(a.subtitleName).toLowerCase()] ?? 99;
      final priB = _formatPriority[_getExtension(b.subtitleName).toLowerCase()] ?? 99;
      if (priA != priB) return priA.compareTo(priB);
      final lenA = _nameWithoutExt(_baseName(a.subtitleName)).length;
      final lenB = _nameWithoutExt(_baseName(b.subtitleName)).length;
      return lenA.compareTo(lenB);
    });
  }

  // ==========================================
  // --- 工具方法 ---
  // ==========================================

  /// 取路径最后一段文件名（兼容 / 与 \ 分隔符）
  static String _baseName(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  /// 安全剥离文件多重后缀（带安全锁，防止未知异常引发死循环）
  ///
  /// 剥离顺序：
  /// 1. 先迭代剥离点号分隔的已知扩展名和语言标记（如 .srt, .chs）
  /// 2. 再剥离末尾的连字符语言标记（如 -zh-CN, -en, -ja）
  static String _nameWithoutExt(String fileName) {
    var name = fileName;
    var lastLength = name.length;

    // 阶段1：剥离点号分隔的扩展名和语言标记
    while (true) {
      final dotIdx = name.lastIndexOf('.');
      if (dotIdx <= 0) break;
      final ext = name.substring(dotIdx).toLowerCase();
      if (_stripExtensions.contains(ext)) {
        name = name.substring(0, dotIdx);
        if (name.length >= lastLength) break;
        lastLength = name.length;
      } else if (_regDotLangTag.hasMatch(name.substring(dotIdx))) {
        // 动态匹配复合语言标记（如 .zh-CN, .en-US 等不在 _stripExtensions 中的）
        name = name.substring(0, dotIdx);
        if (name.length >= lastLength) break;
        lastLength = name.length;
      } else {
        break;
      }
    }

    // 阶段2：剥离连字符分隔的语言标记（如 -zh-CN, -zh-TW, -en, -ja）
    // 最多剥离3层，防止误切番号中的连字符数字部分
    for (var i = 0; i < 3; i++) {
      final match = _regHyphenLangTag.firstMatch(name);
      if (match != null) {
        final tag = match.group(0)!.toLowerCase();
        // 确保是语言标记而非番号数字部分
        if (_isHyphenLangTag(tag)) {
          name = name.substring(0, name.length - match.group(0)!.length);
        } else {
          break;
        }
      } else {
        break;
      }
    }

    return name;
  }

  /// 判断连字符后缀是否为语言标记而非番号数字部分
  static bool _isHyphenLangTag(String tag) {
    final content = tag.substring(1).toLowerCase();
    const knownLangTags = {
      'zh', 'zh-cn', 'zh-tw', 'zh-hk', 'zh-sg', 'zh-mo',
      'en', 'en-us', 'en-gb', 'en-au', 'en-ca',
      'ja', 'jpn', 'ko', 'kor', 'fr', 'fre', 'de', 'ger',
      'es', 'spa', 'pt', 'por', 'it', 'ita', 'ru', 'rus',
      'ar', 'ara', 'hi', 'hin', 'th', 'tha', 'vi', 'vie',
      'id', 'ind', 'ms', 'may', 'nl', 'nld', 'pl', 'pol',
      'sv', 'swe', 'da', 'dan', 'fi', 'fin', 'no', 'nor',
      'hu', 'hun', 'cs', 'ces', 'ro', 'ron', 'bg', 'bul',
      'hr', 'hrv', 'sk', 'slk', 'uk', 'ukr', 'he', 'heb',
      'el', 'ell', 'tr', 'tur', 'ca', 'cat',
      'chs', 'cht', 'chi', 'gb', 'big5', 'chinese', 'cthd', 'csht', 'utf8',
    };
    if (knownLangTags.contains(content)) return true;
    final firstSegment = content.split('-').first;
    if (firstSegment.isNotEmpty && firstSegment.length <= 4 &&
        RegExp(r'^[a-zA-Z]+$').hasMatch(firstSegment)) {
      return true;
    }
    return false;
  }

  /// 获取文件最末尾的扩展名（含点号，如 .srt）
  static String _getExtension(String fileName) {
    final idx = fileName.lastIndexOf('.');
    return idx >= 0 ? fileName.substring(idx) : '';
  }
}

/// 文件名解析出来的比对特征（[SubtitleMatcher] 内部使用）
class _NameFeatures {
  /// 归一化核心串：清洗后只保留字母/数字/中文，如 "MIAA-003" → "miaa003"
  final String core;

  /// 结构化番号（严格提取，提取不到就是空列表，不再退化成整名）
  final List<String> ids;

  /// 词元集合：英文单词 / 数字串 / 单个汉字
  final Set<String> tokens;

  /// 季 / 集（解析不到为 null）
  final int? season;
  final int? episode;

  _NameFeatures({
    required this.core,
    required this.ids,
    required this.tokens,
    this.season,
    this.episode,
  });

  /// 其中的纯数字词元（用于严格的数值比较）
  Set<String> get numbers =>
      tokens.where((t) => RegExp(r'^\d+$').hasMatch(t)).toSet();
}