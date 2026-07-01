import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:charset/charset.dart';

import 'package:alist/entity/file_list_resp_entity.dart';
import 'package:alist/entity/lyric_line.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/file_utils.dart';
import 'package:dio/dio.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

enum LyricsLoadState { loading, success, noLyrics, error }

class LyricsController extends GetxController {
  // ── 可观察状态 ──
  final loadState = LyricsLoadState.loading.obs;
  final lyrics = <LyricLine>[].obs;
  final currentLineIndex = (-1).obs;
  final isDragging = false.obs;
  final errorMessage = ''.obs;

  // ── 滚动控制器 ──
  late final ScrollController lyricsScrollController;

  // ── 静态调试日志 ──
  static final RxList<String> debugLogs = <String>[].obs;
  static final RxInt debugLogVersion = 0.obs;
  static final RxMap<String, String> lastFetchInfo = <String, String>{}.obs;

  static void addLog(String msg) {
    final time = DateTime.now();
    final ts =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}.${time.millisecond.toString().padLeft(3, '0')}';
    final entry = '[$ts] $msg';
    debugPrint('[LRC] $entry');
    debugLogs.add(entry);
    while (debugLogs.length > 500) debugLogs.removeAt(0);
    debugLogVersion.value++;
  }

  static void clearDebugLogs() {
    debugLogs.clear();
    debugLogVersion.value++;
  }

  // ── 内部状态 ──
  int _localLineIndex = -1;
  Timer? _dragTimer;
  int _lastScrolledIndex = -1;
  DateTime _lastPositionUpdate = DateTime.now();
  bool _lyricsVisible = false;
  String? _cacheDirPath;
  String? get cacheDirPath => _cacheDirPath;
  double itemExtent = 48.0;
  String? _loadingPath;

  @override
  void onInit() {
    super.onInit();
    lyricsScrollController = ScrollController();
  }

  @override
  void onClose() {
    _dragTimer?.cancel();
    lyricsScrollController.dispose();
    super.onClose();
  }

  int get displayLineIndex =>
      isDragging.value ? _localLineIndex : currentLineIndex.value;

  // ═══════════════════════════════════════════════════════════════════════════
  // 歌词获取
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> fetchAndLoadLyrics(String audioRemotePath, String? audioSign) async {
    if (_loadingPath == audioRemotePath) { addLog('跳过重复加载'); return; }
    _loadingPath = audioRemotePath;

    addLog('===== 开始加载歌词 =====');
    addLog('audioPath: $audioRemotePath sign: ${audioSign ?? "(null)"}');
    lastFetchInfo.clear();
    lastFetchInfo['音频路径'] = audioRemotePath;
    lastFetchInfo['音频Sign'] = audioSign ?? '(null)';

    loadState.value = LyricsLoadState.loading;
    lyrics.clear();
    currentLineIndex.value = -1;

    try {
      final lrcPath = _buildLrcPath(audioRemotePath);
      if (lrcPath == null) { loadState.value = LyricsLoadState.noLyrics; _loadingPath = null; return; }
      addLog('目标 .lrc: $lrcPath');
      lastFetchInfo['LRC路径'] = lrcPath;

      // 缓存优先（带乱码检测：旧版代码用 String.fromCharCodes 存的缓存可能是乱码）
      final cached = await _readFromCache(lrcPath);
      if (cached != null) {
        addLog('缓存命中，长度=${cached.length}');
        addLog('缓存预览: ${cached.length > 200 ? "${cached.substring(0, 200)}..." : cached}');
        final parsed = _parseLrc(cached);
        addLog('缓存解析: ${parsed.length} 行');
        if (parsed.isNotEmpty && !_isContentGarbled(parsed)) {
          lyrics.assignAll(parsed); loadState.value = LyricsLoadState.success;
          _loadingPath = null; return;
        }
        addLog('⚠ 缓存无效或乱码，删除脏缓存，回退远程下载');
        await _deleteCache(lrcPath);
      }

      addLog('开始远程下载...');
      final content = await _downloadRemoteLrc(lrcPath, audioSign);
      if (content == null || content.trim().isEmpty) {
        loadState.value = LyricsLoadState.noLyrics; _loadingPath = null; return;
      }
      addLog('下载成功，长度=${content.length}');
      addLog('内容预览: ${content.length > 200 ? "${content.substring(0, 200)}..." : content}');

      await _writeToCache(lrcPath, content);
      final parsed = _parseLrc(content);
      addLog('解析: ${parsed.length} 行');
      if (parsed.isNotEmpty) {
        lyrics.assignAll(parsed); loadState.value = LyricsLoadState.success;
        lastFetchInfo['结果'] = '成功'; lastFetchInfo['行数'] = '${parsed.length}';
      } else {
        loadState.value = LyricsLoadState.noLyrics;
        lastFetchInfo['结果'] = '解析后无有效行';
      }
    } catch (e, stack) {
      addLog('❌ 异常: $e\n$stack');
      loadState.value = LyricsLoadState.error;
      errorMessage.value = e.toString();
      lastFetchInfo['结果'] = '异常: $e';
    }
    _loadingPath = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 位置追踪 & 滚动
  // ═══════════════════════════════════════════════════════════════════════════

  void updatePosition(Duration position) {
    if (lyrics.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastPositionUpdate).inMilliseconds < 150) return;
    _lastPositionUpdate = now;

    final idx = _findLineIndex(position);
    if (idx != currentLineIndex.value) currentLineIndex.value = idx;
    if (_lyricsVisible && !isDragging.value && idx >= 0) _autoScrollToLine(idx);
  }

  void setLyricsVisible(bool visible) {
    _lyricsVisible = visible;
    if (!visible) _lastScrolledIndex = -1;
  }

  void onUserScroll(int lineIndex) {
    if (lyrics.isEmpty) return;
    _dragTimer?.cancel();
    _localLineIndex = lineIndex.clamp(0, lyrics.length - 1);
    if (!isDragging.value) isDragging.value = true;
  }

  void onUserScrollEnd() {
    _dragTimer?.cancel();
    _dragTimer = Timer(const Duration(seconds: 3), () => returnToCurrent());
  }

  void returnToCurrent() {
    _dragTimer?.cancel();
    isDragging.value = false;
    _localLineIndex = -1;
    final idx = currentLineIndex.value;
    if (idx >= 0 && idx < lyrics.length && lyricsScrollController.hasClients) {
      final target = (idx * itemExtent) - (lyricsScrollController.position.viewportDimension / 2) + (itemExtent / 2);
      lyricsScrollController.animateTo(
        target.clamp(0.0, lyricsScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic,
      );
    }
  }

  void reset() {
    _dragTimer?.cancel(); _dragTimer = null;
    _localLineIndex = -1; _lastScrolledIndex = -1;
    _loadingPath = null;
    isDragging.value = false; currentLineIndex.value = -1;
    lyrics.clear(); loadState.value = LyricsLoadState.loading; errorMessage.value = '';
    if (lyricsScrollController.hasClients) lyricsScrollController.jumpTo(0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 远程下载（fs/list 一次获取目录文件列表 → 精确匹配 lrc → 下载）
  // ═══════════════════════════════════════════════════════════════════════════

  String? _buildLrcPath(String audioPath) {
    if (audioPath.isEmpty) return null;
    final lastDot = audioPath.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == audioPath.length - 1) return '$audioPath.lrc';
    return '${audioPath.substring(0, lastDot)}.lrc';
  }

  Future<String?> _downloadRemoteLrc(String lrcPath, String? audioSign) async {
    await _initCacheDir();
    final lastSlash = lrcPath.lastIndexOf('/');
    if (lastSlash < 0) return null;
    final parentDir = lrcPath.substring(0, lastSlash);
    final lrcFileName = lrcPath.substring(lastSlash + 1);
    final baseName = lrcFileName.substring(0, lrcFileName.lastIndexOf('.'));
    addLog('  fs/list: $parentDir');

    final files = await _listDirFiles(parentDir);
    if (files == null) { addLog('  fs/list 失败'); return null; }
    addLog('  目录共 ${files.length} 个文件');

    // 精确匹配
    for (final f in files) {
      if (f.name == lrcFileName) {
        addLog('  精确匹配: ${f.name}');
        return await _downloadWithSign(lrcPath, f.sign);
      }
    }
    // 模糊匹配（song.chs.lrc, song.ja.lrc...）
    for (final f in files) {
      final fn = f.name.toLowerCase();
      if (fn.startsWith('$baseName.') && fn.endsWith('.lrc')) {
        addLog('  模糊匹配: ${f.name}');
        final r = await _downloadWithSign('$parentDir/${f.name}', f.sign);
        if (r != null) return r;
      }
    }
    addLog('  目录中未找到任何 .lrc');
    return null;
  }

  Future<List<_LrcFileEntry>?> _listDirFiles(String dirPath) async {
    final c = Completer<List<_LrcFileEntry>?>();
    DioUtils.instance.requestNetwork<FileListRespEntity>(
      Method.post, 'fs/list',
      params: {'path': dirPath, 'password': '', 'page': 1, 'per_page': 0, 'refresh': false},
      onSuccess: (data) {
        if (data?.content == null) { c.complete(null); return; }
        c.complete(data!.content!.map((f) => _LrcFileEntry(f.name, f.sign)).toList());
      },
      onError: (code, msg) { addLog('    fs/list err: $code $msg'); c.complete(null); },
    );
    return c.future;
  }

  Future<String?> _downloadWithSign(String remotePath, String? sign) async {
    final url = await FileUtils.makeFileLink(remotePath, sign, toastShowTips: false);
    if (url == null || url.isEmpty) { addLog('    makeFileLink null'); return null; }
    addLog('    URL: $url');
    lastFetchInfo['下载URL'] = url;

    final token = SpUtil.getString(AlistConstant.token) ?? '';
    final svr = SpUtil.getString(AlistConstant.serverUrl) ?? '';
    final headers = <String, String>{};
    if (token.isNotEmpty && svr.isNotEmpty && url.startsWith(svr)) headers['Authorization'] = token;

    final ignoreSSL = SpUtil.getBool(AlistConstant.ignoreSSLError) ?? false;
    var result = await _httpGet(url, headers, ignoreSSL, false);
    if (result == null) result = await _httpGet(url, headers, ignoreSSL, true);
    if (result != null) {
      addLog('    ✅ ${result.length} 字符');
      lastFetchInfo['HTTP状态'] = '200 OK';
      lastFetchInfo['内容长度'] = '${result.length}';
    }
    return result;
  }

  Future<String?> _httpGet(String url, Map<String, String> headers, bool ignoreSSL, bool useSharedDio) async {
    try {
      final Dio dio;
      if (useSharedDio) {
        dio = DioUtils.instance.dio;
      } else {
        dio = Dio();
        dio.options.connectTimeout = const Duration(seconds: 10);
        dio.options.receiveTimeout = const Duration(seconds: 15);
        if (ignoreSSL) {
          (dio.httpClientAdapter as dynamic).onHttpClientCreate =
              (io.HttpClient c) { c.badCertificateCallback = (_, __, ___) => true; return c; };
        }
      }
      final r = await dio.get<List<int>>(url,
          options: Options(headers: headers, responseType: ResponseType.bytes, followRedirects: true));
      addLog('    HTTP ${r.statusCode}');
      if (r.statusCode == 200 && r.data != null) {
        final content = _decodeBytes(r.data!);
        if (content == null) return null;
        if (_isJsonError(content)) {
          addLog('    ⚠ JSON错误: ${content.length > 80 ? content.substring(0, 80) : content}');
          lastFetchInfo['HTTP状态'] = '200 but JSON error';
          return null;
        }
        return content;
      }
      lastFetchInfo['HTTP状态'] = '${r.statusCode}';
      return null;
    } on DioException catch (e) {
      addLog('    DioEx: ${e.type} ${e.response?.statusCode}');
      if (e.response?.statusCode == 404) return null;
      return null;
    } catch (e) { addLog('    异常: $e'); return null; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 编码处理
  // ═══════════════════════════════════════════════════════════════════════════

  /// 多编码尝试解码字节 → 字符串。
  ///
  /// 降级链：UTF-8 → Shift-JIS → GBK → EUC-JP → Latin-1
  /// 参照 txt_reader_screen 的乱码检测模式
  static String? _decodeBytes(List<int> bytes) {
    if (bytes.isEmpty) return null;

    final hex = bytes.take(30).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    addLog('    原始hex(前30字节): $hex');

    // ① BOM 检测
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      addLog('    编码: UTF-8 BOM');
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      addLog('    编码: UTF-16 LE BOM');
      return utf8.decode(bytes.sublist(2), allowMalformed: true);
    }

    // ② UTF-8 优先
    final utf8Str = utf8.decode(bytes, allowMalformed: true);
    final badCount = '�'.allMatches(utf8Str).length;
    if (badCount == 0) { addLog('    编码: UTF-8'); return utf8Str; }
    addLog('    UTF-8 有 $badCount 个替换字符');

    // ③ 逐个尝试 charset 包的编码（日文优先 Shift-JIS，中文优先 GBK）
    final candidates = <String, Function>{
      'Shift-JIS': () => shiftJis.decode(bytes),
      'GBK': () => gbk.decode(bytes),
      'EUC-JP': () => eucJp.decode(bytes),
    };
    for (final entry in candidates.entries) {
      try {
        final decoded = entry.value() as String;
        if (decoded.isEmpty) continue;
        final sb = '�'.allMatches(decoded).length;
        // 只要优于 UTF-8 就采纳
        if (sb < badCount) {
          addLog('    编码: ${entry.key} (替换字符:$sb vs UTF-8:$badCount)');
          addLog('    预览: ${decoded.length > 60 ? decoded.substring(0, 60) : decoded}');
          return decoded;
        }
      } catch (_) {}
    }

    // ④ UTF-8 少量替换字符可接受
    if (badCount < utf8Str.length * 0.1) {
      addLog('    编码: UTF-8（少量替换）');
      return utf8Str;
    }

    // ⑤ 最终降级 Latin-1（保留原始字节不丢失）
    addLog('    编码: 降级Latin-1');
    return latin1.decode(bytes);
  }

  static bool _isJsonError(String content) {
    final t = content.trim();
    return t.startsWith('{') && (t.contains('"code"') || t.contains('"message"') || t.contains('sign'));
  }

  /// 检测歌词内容是否为乱码（旧版 String.fromCharCodes 写入的脏缓存）。
  ///
  /// 判断依据：取前 20 行的歌词文本，如果大量字符落在 Latin-1 扩展区
  /// （U+0080-U+00FF，如 Â/Ã/© 等 Shift-JIS 被误解释为 UTF-8 的典型乱码特征），
  /// 则认为内容已损坏。
  static bool _isContentGarbled(List<LyricLine> lines) {
    if (lines.isEmpty) return true;
    int totalChars = 0;
    int garbledChars = 0;
    int linesChecked = 0;
    for (final line in lines) {
      if (linesChecked >= 20) break;
      if (line.content.isEmpty) continue;
      linesChecked++;
      for (final c in line.content.runes) {
        totalChars++;
        // Latin-1 扩展区 (U+0080-U+00FF)：高频乱码特征
        if (c >= 0x80 && c <= 0xFF) garbledChars++;
      }
    }
    if (totalChars == 0) return false;
    // 超过 30% 的字符是可疑 Latin-1 扩展字符 → 乱码
    final ratio = garbledChars / totalChars;
    if (ratio > 0.3) {
      addLog('    乱码检测: ${(ratio * 100).toStringAsFixed(0)}% 可疑字符 → 判定为乱码');
      return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 缓存
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _initCacheDir() async {
    if (_cacheDirPath != null) return;
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDirPath = '${appDir.path}/lyrics';
    final dir = io.Directory(_cacheDirPath!);
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  Future<String?> _readFromCache(String lrcPath) async {
    try {
      await _initCacheDir();
      final f = io.File('$_cacheDirPath/lrc_${lrcPath.hashCode.toRadixString(16)}.lrc');
      if (await f.exists()) return await f.readAsString();
    } catch (_) {}
    return null;
  }

  Future<void> _writeToCache(String lrcPath, String content) async {
    try {
      await _initCacheDir();
      await io.File('$_cacheDirPath/lrc_${lrcPath.hashCode.toRadixString(16)}.lrc')
          .writeAsString(content, flush: true);
    } catch (_) {}
  }

  Future<void> _deleteCache(String lrcPath) async {
    try {
      await _initCacheDir();
      final f = io.File('$_cacheDirPath/lrc_${lrcPath.hashCode.toRadixString(16)}.lrc');
      if (await f.exists()) { await f.delete(); addLog('已删除脏缓存'); }
    } catch (e) { addLog('删除缓存失败: $e'); }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LRC 解析 & 查找
  // ═══════════════════════════════════════════════════════════════════════════

  List<LyricLine> _parseLrc(String content) {
    final lines = <LyricLine>[];
    final timeRe = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    final metaRe = RegExp(r'\[(ti|ar|al|by|offset|la|re|ve|length):');

    for (final raw in content.split('\n')) {
      final t = raw.trim();
      if (t.isEmpty || metaRe.hasMatch(t)) continue;
      final matches = timeRe.allMatches(t).toList();
      if (matches.isEmpty) continue;

      final text = t.substring(matches.last.end).trim();
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final msStr = m.group(3);
        final ms = msStr != null ? int.parse(msStr.padRight(3, '0').substring(0, 3)) : 0;
        lines.add(LyricLine(startTime: Duration(minutes: min, seconds: sec, milliseconds: ms), endTime: Duration.zero, content: text));
      }
    }

    lines.sort((a, b) => a.startTime.compareTo(b.startTime));
    final deduped = <LyricLine>[];
    for (final l in lines) { if (deduped.isEmpty || deduped.last.startTime != l.startTime) deduped.add(l); }
    for (int i = 0; i < deduped.length; i++) {
      final end = i < deduped.length - 1 ? deduped[i + 1].startTime : const Duration(days: 365);
      deduped[i] = LyricLine(startTime: deduped[i].startTime, endTime: end, content: deduped[i].content);
    }
    return deduped;
  }

  int _findLineIndex(Duration pos) {
    if (lyrics.isEmpty) return -1;
    int lo = 0, hi = lyrics.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final l = lyrics[mid];
      if (pos < l.startTime) { hi = mid - 1; }
      else if (pos >= l.endTime) { lo = mid + 1; }
      else { return mid; }
    }
    if (hi < 0) return 0;
    if (lo >= lyrics.length) return lyrics.length - 1;
    return hi.clamp(0, lyrics.length - 1);
  }

  void _autoScrollToLine(int index) {
    if (!lyricsScrollController.hasClients) return;
    // padding 已经做了 vh/2 偏移，这里直接用 index * itemExtent 即可居中
    final target = (index * itemExtent)
        .clamp(0.0, lyricsScrollController.position.maxScrollExtent);

    final prev = _lastScrolledIndex;
    _lastScrolledIndex = index;

    if (prev == -1 || (index - prev).abs() > 1) {
      lyricsScrollController.animateTo(target,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    } else {
      lyricsScrollController.jumpTo(target);
    }
  }
}

class _LrcFileEntry { final String name, sign; const _LrcFileEntry(this.name, this.sign); }
