/// 字幕匹配模式
enum SubtitleMatchMode {
  /// 精确查找：文件名完全一致（去掉后缀和语言标记，忽略大小写）
  exact,
  /// 模糊查找：提取番号核心ID，字幕文件名包含该ID即可（忽略符号与大小写）
  fuzzy,
  /// 双模式：先精确，精确未命中再模糊
  dual,
}

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

  // 用于模糊比对时完全抹平噪音符号（连字符、下划线、空格）的正则
  static final _regFlatten = RegExp(r'[-_\s]');

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

    // 8. 无法提取番号时，返回深度清洗后的名称
    return name;
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

  /// 精确匹配：安全剥离后缀和语言标记后，文件名是否完全一致（忽略大小写）
  static bool isExactMatch(String videoName, String subtitleName) {
    final videoBase = _nameWithoutExt(_baseName(videoName)).toLowerCase();
    final subBase = _nameWithoutExt(_baseName(subtitleName)).toLowerCase();
    return videoBase == subBase;
  }

  /// 模糊匹配：从视频和字幕**双方**提取核心ID，进行多策略比对
  ///
  /// 匹配策略（按优先级）：
  /// 1. 双方番号ID完全一致 → 强匹配
  /// 2. 一方番号ID被另一方清洗名包含 → 中等匹配
  /// 3. 双方清洗名互相包含 → 弱匹配
  static bool isFuzzyMatch(String videoName, String subtitleName) {
    final score = fuzzyMatchScore(videoName, subtitleName);
    return score >= 80;
  }

  /// 计算模糊匹配分数（0 = 不匹配，分数越高匹配度越好）
  ///
  /// 评分规则：
  /// - 双方番号ID完全一致: 100分
  /// - 一方番号ID被另一方清洗名包含: 80分
  /// - 双方清洗名互相包含（短名被长名包含）: 60分
  /// - 双方任一ID互相包含: 50分
  static int fuzzyMatchScore(String videoName, String subtitleName) {
    // 1. 从双方提取番号ID
    final videoId = extractId(videoName).replaceAll(_regFlatten, '').toUpperCase();
    final subId = extractId(subtitleName).replaceAll(_regFlatten, '').toUpperCase();

    // 2. 双方清洗后的名称（用于包含检测）
    final videoClean = _deepClean(_nameWithoutExt(_baseName(videoName)))
        .replaceAll(_regFlatten, '').toUpperCase();
    final subClean = _deepClean(_nameWithoutExt(_baseName(subtitleName)))
        .replaceAll(_regFlatten, '').toUpperCase();

    // 3. 策略1：双方番号ID完全一致（最强匹配）
    if (videoId.isNotEmpty && subId.isNotEmpty && videoId == subId) {
      return 100;
    }

    // 4. 策略2：双方所有ID中有任意一对一致
    if (videoId.isNotEmpty && subId.isNotEmpty) {
      final videoAllIds = extractAllIds(videoName)
          .map((id) => id.replaceAll(_regFlatten, '').toUpperCase())
          .toSet();
      final subAllIds = extractAllIds(subtitleName)
          .map((id) => id.replaceAll(_regFlatten, '').toUpperCase())
          .toSet();
      if (videoAllIds.intersection(subAllIds).isNotEmpty) {
        return 95;
      }
    }

    // 5. 策略3：一方番号ID被另一方清洗名包含
    if (videoId.isNotEmpty && subClean.contains(videoId)) {
      return 80;
    }
    if (subId.isNotEmpty && videoClean.contains(subId)) {
      return 80;
    }

    // 6. 策略4：双方清洗名互相包含（短名被长名包含）
    if (videoClean.isNotEmpty && subClean.isNotEmpty) {
      if (videoClean.length >= subClean.length && videoClean.contains(subClean)) {
        return 60;
      }
      if (subClean.length >= videoClean.length && subClean.contains(videoClean)) {
        return 60;
      }
    }

    // 7. 策略5：双方任一ID被对方清洗名包含（宽松匹配）
    if (videoId.isNotEmpty && subClean.contains(videoId)) {
      return 50;
    }
    if (subId.isNotEmpty && videoClean.contains(subId)) {
      return 50;
    }

    return 0;
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

  /// 从字幕池中查找匹配的字幕列表（已按优先级排序）
  static List<String> findMatchedSubtitles(
    String videoName,
    List<String> subtitlePool,
    SubtitleMatchMode mode,
  ) {
    if (videoName.isEmpty || subtitlePool.isEmpty) return [];

    List<String> results = [];
    switch (mode) {
      case SubtitleMatchMode.exact:
        results = subtitlePool.where((sub) => isExactMatch(videoName, sub)).toList();
        break;
      case SubtitleMatchMode.fuzzy:
        results = _fuzzyMatchSorted(videoName, subtitlePool);
        break;
      case SubtitleMatchMode.dual:
        final exactResults = subtitlePool.where((sub) => isExactMatch(videoName, sub)).toList();
        if (exactResults.isNotEmpty) {
          results = exactResults;
          break;
        }
        results = _fuzzyMatchSorted(videoName, subtitlePool);
        break;
    }

    return prioritizeSubtitles(results);
  }

  /// 模糊匹配并按匹配分数排序（分数高的排前面）
  static List<String> _fuzzyMatchSorted(String videoName, List<String> subtitlePool) {
    final scored = <_MatchResult>[];
    for (final sub in subtitlePool) {
      final score = fuzzyMatchScore(videoName, sub);
      if (score >= 80) {
        scored.add(_MatchResult(sub, score));
      }
    }
    // 按分数降序排序
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((r) => r.subtitleName).toList();
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