import 'dart:convert';
import 'dart:io';

import 'package:alist/entity/file_remove_req.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/log_utils.dart';
import 'package:dio/dio.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// SmartStrm 联动删除 Webhook 服务
///
/// 在 AList 中成功删除 .strm 文件后，向 SmartStrm 后端发送高保真 Emby 格式 Webhook，
/// 通知后端同步删除 115 网盘中的真实媒体文件。
class SmartStrmWebhook {
  static const String tag = "SmartStrmWebhook";

  /// 发送联动删除 Webhook
  ///
  /// [alistFilePath] AList 中的文件完整路径，如:
  ///   "/NAS/volume1/docker/smartstrm/strm/115/测试/(1集)_(1).(mp4).strm"
  ///   或 "/volume1/docker/smartstrm/strm/115/测试/(1集)_(1).(mp4).strm"
  ///
  /// 返回 true 表示发送成功，false 表示发送失败或被拦截。
  static Future<bool> sendDeleteWebhook(String alistFilePath) async {
    final fileName = _extractFileNameWithoutStrm(alistFilePath);

    // 1. 检查功能开关
    final enabled =
        SpUtil.getBool(AlistConstant.linkedDeletionEnabled, defValue: false) ??
            false;
    if (!enabled) {
      await _logSkip(fileName, '功能开关未开启');
      return false;
    }

    // 2. 获取配置
    final webhookUrl =
        SpUtil.getString(AlistConstant.linkedDeletionWebhookUrl) ?? '';
    if (webhookUrl.isEmpty) {
      await _logSkip(fileName, 'Webhook URL 未配置');
      return false;
    }

    final strmDir = SpUtil.getString(
          AlistConstant.linkedDeletionStrmDir,
          defValue: '',
        ) ??
        '';
    if (strmDir.isEmpty) {
      await _logSkip(fileName, 'strm 目录未配置');
      return false;
    }

    // 3. 路径转换
    final transformedPath = _transformPath(alistFilePath, strmDir);

    // 4. 空路径保护 —— 绝对拦截，防止误删整个网盘
    if (_isPathTooShort(transformedPath)) {
      LogUtil.e('[$tag] 解析后的路径为空或仅为根目录，已拦截！原路径: $alistFilePath',
          tag: tag);
      await _logSkip(fileName, '路径异常被拦截 ($transformedPath)');
      SmartDialog.showToast(
        '【安全拦截】解析后的 strm 路径异常（$transformedPath），'
        '已阻止联动删除请求，防止误删网盘数据！',
      );
      return false;
    }

    // 5. 从转换后的路径重新提取准确文件名
    final payloadFileName = _extractFileNameWithoutStrm(transformedPath);

    // 6. 构建 JSON 载荷（高保真 Emby Webhook 格式）
    final dateStr = _formatUtcTimestamp(DateTime.now().toUtc());

    final payload = {
      "Title": "媒体库删除: $payloadFileName",
      "Description": "AlistClientN 联动删除: $payloadFileName",
      "Date": dateStr,
      "Event": "library.deleted",
      "Severity": "Warning",
      "User": {"Name": "Admin"},
      "Item": {
        "Name": payloadFileName,
        "Path": transformedPath,
        "Type": "Movie",
        "MediaType": "Video",
      },
      "Server": {
        "Name": "AlistClient_Virtual",
        "Id": "55d1d9a5b63e4549aa9fbbe74a76db8c",
        "Version": "4.9.3.0",
      },
    };

    LogUtil.d('[$tag] 发送联动删除 Webhook:\n  URL: $webhookUrl\n  Payload: ${jsonEncode(payload)}',
        tag: tag);

    // 7. 发送请求 + 写日志
    final ok = await _doPost(webhookUrl, payload, '联动删除', payloadFileName);
    if (ok) {
      SmartDialog.showToast('联动删除通知已发送');
    }
    return ok;
  }

  /// 格式化 UTC 时间戳为 Emby 风格: "2026-07-07T01:26:33.2186940Z"
  static String _formatUtcTimestamp(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}"
        "T${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}.${(dt.millisecond * 10000).toString().padLeft(7, '0')}Z";
  }

  // ==================== 测试 Webhook ====================

  /// 发送测试 Webhook，验证连通性
  ///
  /// 使用 Emby 标准的 `system.notificationtest` 事件格式，
  /// 返回 HTTP 状态码和响应体文本。
  static Future<({int statusCode, String body})> sendTestWebhook() async {
    final webhookUrl =
        SpUtil.getString(AlistConstant.linkedDeletionWebhookUrl) ?? '';
    if (webhookUrl.isEmpty) {
      throw Exception('Webhook URL 未配置');
    }

    final now = DateTime.now().toUtc();
    final dateStr = _formatUtcTimestamp(now);

    final payload = {
      "Title": "Test Notification",
      "Description": "Test Notification Description",
      "Date": dateStr,
      "Event": "system.notificationtest",
      "Severity": "Info",
      "Server": {
        "Name": "AlistClient_Virtual",
        "Id": "55d1d9a5b63e4549aa9fbbe74a76db8c",
        "Version": "4.9.3.0",
      },
    };

    LogUtil.d('[$tag] 发送测试 Webhook:\n  URL: $webhookUrl\n  Payload: ${jsonEncode(payload)}',
        tag: tag);

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));

    final response = await dio.post(
      webhookUrl,
      data: payload,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'AlistClientN-SmartStrm/1.0',
        },
      ),
    );

    return (statusCode: response.statusCode ?? -1, body: '${response.data}');
  }

  // ==================== 发送日志（文件持久化） ====================

  static String? _cachedLogPath;
  /// 最多保留 300 行日志
  static const int _maxLogLines = 300;

  static Future<String> get _logPath async {
    if (_cachedLogPath != null) return _cachedLogPath!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedLogPath = '${dir.path}/smartstrm_webhook_log.txt';
    return _cachedLogPath!;
  }

  /// 追加日志并自动裁剪旧记录
  static Future<void> _appendLog(String line) async {
    try {
      final path = await _logPath;
      final file = File(path);
      await file.parent.create(recursive: true);

      if (await file.exists()) {
        final old = await file.readAsLines();
        old.add(line);
        // 只保留最后 _maxLogLines 行
        final trimmed = old.length > _maxLogLines
            ? old.sublist(old.length - _maxLogLines)
            : old;
        await file.writeAsString('${trimmed.join('\n')}\n');
      } else {
        await file.writeAsString('$line\n');
      }
    } catch (_) {}
  }

  /// 跳过发送时写日志
  static Future<void> _logSkip(String detail, String reason) async {
    final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    await _appendLog('[$ts] ⏭️ 跳过 | $detail | 原因: $reason');
  }

  /// 发送完成时写日志（含 payload 和响应）
  static Future<void> _logResult(bool success, String action, String detail,
      Map<String, dynamic> payload, int statusCode, String responseBody) async {
    final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final icon = success ? '✅' : '❌';
    await _appendLog('[$ts] $icon $action | $detail | HTTP $statusCode');
    await _appendLog('[$ts]   📤 Payload: ${jsonEncode(payload)}');
    await _appendLog('[$ts]   📥 Response: $responseBody');
  }

  /// 读取全部日志
  static Future<String> readLog() async {
    try {
      final path = await _logPath;
      final file = File(path);
      if (!await file.exists()) return '暂无日志';
      return await file.readAsString();
    } catch (_) {
      return '读取日志失败';
    }
  }

  /// 清空日志
  static Future<void> clearLog() async {
    try {
      final path = await _logPath;
      await File(path).writeAsString('');
    } catch (_) {}
  }

  // ==================== 核心发送逻辑 ====================

  /// 实际执行 HTTP POST 并写日志
  static Future<bool> _doPost(
    String webhookUrl,
    Map<String, dynamic> payload,
    String logAction,
    String logDetail,
  ) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      final response = await dio.post(
        webhookUrl,
        data: payload,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'AlistClientN-SmartStrm/1.0',
          },
        ),
      );

      LogUtil.d('[$tag] Webhook 响应: status=${response.statusCode}, body=${response.data}',
          tag: tag);

      final ok = response.statusCode == 200;
      await _logResult(ok, logAction, logDetail, payload,
          response.statusCode ?? -1, '${response.data}');
      return ok;
    } catch (e) {
      LogUtil.e('[$tag] 发送 Webhook 失败: $e', tag: tag);
      await _logResult(false, logAction, logDetail, payload, -1, '$e');
      return false;
    }
  }

  /// 判断文件是否为 .strm 文件
  static bool isStrmFile(String fileName) {
    return fileName.toLowerCase().endsWith('.strm');
  }

  // ==================== 帧截图联动删除 ====================

  /// 同步删除 strm 文件对应的帧截图（同名不同后缀 .jpg / .png）
  ///
  /// 仅在开关 [AlistConstant.linkedDeletionDeleteThumb] 开启时执行。
  /// 失败静默，不阻塞主流程。
  static Future<void> deleteAssociatedThumbnails(String strmFilePath) async {
    final enabled = SpUtil.getBool(
          AlistConstant.linkedDeletionDeleteThumb,
          defValue: false,
        ) ??
        false;
    if (!enabled) return;

    final dir = strmFilePath.contains('/')
        ? strmFilePath.substring(0, strmFilePath.lastIndexOf('/'))
        : '/';
    final baseName = _extractFileNameWithoutStrm(strmFilePath);
    final candidates = ['$baseName.jpg', '$baseName.png'];

    for (final thumbName in candidates) {
      try {
        final req = FileRemoveReq();
        req.dir = dir.isEmpty ? '/' : dir;
        req.names = [thumbName];
        await DioUtils.instance.requestNetwork<String?>(
          Method.post,
          'fs/remove',
          params: req.toJson(),
          onSuccess: (_) {
            LogUtil.d('[$tag] 已删除帧截图: $thumbName', tag: tag);
          },
          onError: (code, msg) {
            LogUtil.d('[$tag] 删除帧截图跳过 (code=$code): $thumbName', tag: tag);
          },
        );
      } catch (_) {}
    }
  }

  /// 将 AList 文件路径转换为 NAS 上的真实 strm 文件绝对路径
  ///
  /// 核心思路:
  ///   用户配置的是 NAS 上 strm 根目录的绝对路径, 如 `/volume1/docker/smartstrm/strm`。
  ///   AList 路径里包含了 strm 目录结构, 但前面可能套了任意层挂载前缀:
  ///     "/NASABCD/群晖/volume1/docker/smartstrm/strm/115/测试/file.strm"
  ///     "/volume1/docker/smartstrm/strm/115/测试/file.strm"
  ///     "/MyServer/strm_vault/strm/115/测试/file.strm"   (只匹配后缀)
  ///
  ///   我们需要找到 "配置目录" 在 "AList 路径" 中的锚点, 然后:
  ///     真实路径 = 配置目录 + 锚点之后的内容
  ///
  /// 采用渐进式匹配 —— 先全量, 后逐段缩减, 最后只匹配一个尾段,
  /// 确保无论用户怎么命名 AList 挂载前缀都能命中。
  static String _transformPath(String alistPath, String configuredStrmDir) {
    // ---------- 规范化 ----------
    var normalized = alistPath.replaceAll('\\', '/');
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }

    var configDir = configuredStrmDir.replaceAll('\\', '/');
    if (configDir.endsWith('/')) {
      configDir = configDir.substring(0, configDir.length - 1);
    }
    if (!configDir.startsWith('/')) {
      configDir = '/$configDir';
    }

    final configSegments =
        configDir.split('/').where((s) => s.isNotEmpty).toList();
    final pathSegments =
        normalized.split('/').where((s) => s.isNotEmpty).toList();

    if (configSegments.isEmpty || pathSegments.isEmpty) {
      return '$configDir$normalized';
    }

    // ---- 层级 1: 字符串精确匹配（最快） ----
    int index = normalized.indexOf(configDir);
    if (index >= 0) {
      return normalized.substring(index);
    }

    // ---- 层级 2: 全量段数组匹配（挂载前缀恰好是整段） ----
    // 例: ["NASABCD", "群晖", "volume1", "docker", "smartstrm", "strm", ...]
    //     在 i=2 处匹配到 ["volume1","docker","smartstrm","strm"]
    if (pathSegments.length >= configSegments.length) {
      for (int i = 0; i <= pathSegments.length - configSegments.length; i++) {
        if (_segmentsEqual(pathSegments, i, configSegments)) {
          return '/${pathSegments.sublist(i).join('/')}';
        }
      }
    }

    // ---- 层级 3: 渐进后缀匹配（核心兼容层） ----
    // 从少 1 段开始, 逐步缩减到只匹配 2 段, 防止不同命名导致失配。
    // 例: configDir = "/volume1/docker/smartstrm/strm" (4 段)
    //     尝试匹配 ["docker","smartstrm","strm"] → ["smartstrm","strm"] → ["strm"]
    for (int matchLen = configSegments.length - 1; matchLen >= 2; matchLen--) {
      final suffix = configSegments.sublist(configSegments.length - matchLen);
      // 从后往前搜, 优先匹配路径中靠后的位置
      for (int i = pathSegments.length - matchLen; i >= 0; i--) {
        if (_segmentsEqual(pathSegments, i, suffix)) {
          // 匹配成功! 锚点之后的 relative 拼到配置目录上
          final after =
              i + matchLen < pathSegments.length
                  ? '/${pathSegments.sublist(i + matchLen).join('/')}'
                  : '';
          return '$configDir$after';
        }
      }
    }

    // ---- 层级 4: 末段匹配（最宽松, 只匹配最后一个目录名如 "strm"） ----
    final lastCfg = configSegments.last;
    for (int i = pathSegments.length - 1; i >= 0; i--) {
      if (pathSegments[i] == lastCfg) {
        final after =
            i + 1 < pathSegments.length
                ? '/${pathSegments.sublist(i + 1).join('/')}'
                : '';
        return '$configDir$after';
      }
    }

    // ---- 层级 5: 彻底失配, 保底拼接 ----
    return '$configDir$normalized';
  }

  /// 判断 pathSegs 从 startIdx 开始的子数组是否与 matchSegs 完全相等
  static bool _segmentsEqual(
      List<String> pathSegs, int startIdx, List<String> matchSegs) {
    if (startIdx + matchSegs.length > pathSegs.length) return false;
    for (int j = 0; j < matchSegs.length; j++) {
      if (pathSegs[startIdx + j] != matchSegs[j]) return false;
    }
    return true;
  }

  /// 空路径保护：防止解析出空路径或根路径导致误删
  static bool _isPathTooShort(String path) {
    if (path.isEmpty) return true;
    // 去除首尾空白
    final trimmed = path.trim();
    if (trimmed.isEmpty) return true;
    // 仅 "/" 或仅包含 "/" 和空白
    if (trimmed == '/') return true;
    // 去掉末尾 .strm 后判断: 如果去掉 .strm 后只剩 "/" 或少于2个有效段，也拦截
    final withoutStrm = trimmed.replaceAll(RegExp(r'\.strm$', caseSensitive: false), '');
    final segments =
        withoutStrm.split('/').where((s) => s.trim().isNotEmpty).toList();
    if (segments.length < 2) return true;
    return false;
  }

  /// 从完整路径中提取不含 .strm 后缀的文件名
  ///
  /// 例如: "/volume1/.../测试/(1集)_(1).(mp4).strm" → "(1集)_(1).(mp4)"
  static String _extractFileNameWithoutStrm(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return '';
    var fileName = segments.last;
    // 去掉 .strm 后缀（大小写不敏感）
    if (fileName.toLowerCase().endsWith('.strm')) {
      fileName = fileName.substring(0, fileName.length - 5);
    }
    return fileName;
  }
}
