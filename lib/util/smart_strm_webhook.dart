import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:alist/entity/file_remove_req.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/log_utils.dart';
import 'package:dio/dio.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// SmartStrm 联动删除 Webhook 服务
///
/// 在 AList 中成功删除 .strm 文件后，向 SmartStrm 后端发送 Webhook，
/// 通知后端同步删除云端存储中的真实媒体文件。

/// Webhook 发送结果
class _WebhookSendResult {
  final bool ok;
  final bool pathMismatch;
  final String remotePath;
  final String expectedName;
  const _WebhookSendResult({
    required this.ok,
    required this.pathMismatch,
    required this.remotePath,
    required this.expectedName,
  });
}

class SmartStrmWebhook {
  static const String tag = "SmartStrmWebhook";

  /// 发送联动删除 Webhook（单个文件，带 toast/dialog 提示）
  ///
  /// [alistFilePath] AList 中的文件完整路径，如:
  ///   "/NAS/volume1/docker/smartstrm/strm/115/测试/(1集)_(1).(mp4).strm"
  ///   或 "/volume1/docker/smartstrm/strm/115/测试/(1集)_(1).(mp4).strm"
  ///
  /// 返回 true 表示发送成功，false 表示发送失败或被拦截。
  /// 成功时弹 toast；路径不匹配时弹醒目的 AlertDialog 警告。
  static Future<bool> sendDeleteWebhook(String alistFilePath) async {
    final r =
        await _sendDeleteWebhookInternal(alistFilePath, showToast: true);
    return r.ok;
  }

  /// 发送联动删除 Webhook（静默模式，不弹 toast/dialog）
  ///
  /// 与 [sendDeleteWebhook] 逻辑一致，但不弹任何 UI 提示，
  /// 适用于批量删除场景，由调用方统一汇总。
  ///
  /// 返回 true 表示发送成功，false 表示发送失败或被拦截。
  static Future<bool> sendDeleteWebhookSilently(String alistFilePath) async {
    final r =
        await _sendDeleteWebhookInternal(alistFilePath, showToast: false);
    return r.ok;
  }

  /// 批量发送联动删除 Webhook（静默汇总 + 路径异常立即中止）
  ///
  /// 每批 3 条并发。一旦检测到任何路径不匹配，立即中止后续发送，
  /// 防止后端异常时灾难性地误删整个网盘。
  ///
  /// 返回 (成功数, 失败数, 已跳过数, 是否因路径异常中止)。
  static Future<({
    int success,
    int fail,
    int skipped,
    bool aborted,
    ({String expected, String actual})? mismatch
  })> sendBatchDeleteWebhooks(List<String> paths) async {
    int success = 0;
    int fail = 0;
    int skipped = 0;
    ({String expected, String actual})? mismatch;

    const batchSize = 3;
    for (var i = 0; i < paths.length; i += batchSize) {
      final batch = paths.skip(i).take(batchSize).toList();
      final results = await Future.wait(
        batch.map((p) => _sendDeleteWebhookInternal(p, showToast: false)),
      );
      for (final r in results) {
        if (r.ok && r.pathMismatch) {
          // 路径异常！立即标记并中止后续发送
          mismatch = (expected: r.expectedName, actual: r.remotePath);
          success++; // 这个请求本身"成功"了，但路径不对
          break;
        } else if (r.ok) {
          success++;
        } else {
          fail++;
        }
      }
      // 检测到异常，立即停止
      if (mismatch != null) {
        // 计算剩余未发送的数量
        final remainingInBatch = batch.length - results.length;
        final remainingAfter = paths.length - (i + batch.length);
        skipped = remainingInBatch + remainingAfter;
        break;
      }
      if (i + batchSize < paths.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    // 路径异常时弹醒目的中止对话框
    if (mismatch != null) {
      _showAbortDialog(mismatch, success, fail, skipped);
    }

    return (
      success: success,
      fail: fail,
      skipped: skipped,
      aborted: mismatch != null,
      mismatch: mismatch
    );
  }

  /// 批量删除遇到路径异常 → 立即中止的醒目警告对话框
  static void _showAbortDialog(
    ({String expected, String actual}) mismatch,
    int success,
    int fail,
    int skipped,
  ) {
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.dangerous_rounded,
                color: Colors.red.shade700, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('🛑 联动删除已紧急中止',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('检测到 SmartStrm 后端返回的删除路径与预期不符，'
                '已立即中止后续所有请求，防止灾难性误删！',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            // 异常详情
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('触发异常的请求:',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  _mismatchRow('预期', mismatch.expected),
                  const SizedBox(height: 4),
                  _mismatchRow('实际', mismatch.actual),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 统计
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已发送 $success 个 | 失败 $fail 个 | 已阻止 $skipped 个',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
                '请立即检查 SmartStrm 的回收站恢复误删数据，'
                '并排查后端异常后再重新操作。',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700),
            onPressed: () => SmartDialog.dismiss(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  /// 核心发送逻辑（内部方法）
  ///
  /// [showToast] 为 true 时成功/失败/路径异常都会弹 toast，false 则静默返回。
  static Future<_WebhookSendResult> _sendDeleteWebhookInternal(
      String alistFilePath,
      {required bool showToast}) async {
    final fileName = _extractFileNameWithoutStrm(alistFilePath);

    // 1. 检查功能开关
    final enabled =
        SpUtil.getBool(AlistConstant.linkedDeletionEnabled, defValue: false) ??
            false;
    if (!enabled) {
      await _logSkip(fileName, '功能开关未开启');
      return const _WebhookSendResult(
          ok: false, pathMismatch: false, remotePath: '', expectedName: '');
    }

    // 2. 获取配置
    final webhookUrl =
        SpUtil.getString(AlistConstant.linkedDeletionWebhookUrl) ?? '';
    if (webhookUrl.isEmpty) {
      await _logSkip(fileName, 'Webhook URL 未配置');
      return const _WebhookSendResult(
          ok: false, pathMismatch: false, remotePath: '', expectedName: '');
    }

    final strmDir = SpUtil.getString(
          AlistConstant.linkedDeletionStrmDir,
          defValue: '',
        ) ??
        '';
    if (strmDir.isEmpty) {
      await _logSkip(fileName, 'strm 目录未配置');
      return const _WebhookSendResult(
          ok: false, pathMismatch: false, remotePath: '', expectedName: '');
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
      return const _WebhookSendResult(
          ok: false, pathMismatch: false, remotePath: '', expectedName: '');
    }

    // 5. 从转换后的路径重新提取准确文件名
    final payloadFileName = _extractFileNameWithoutStrm(transformedPath);

    // 6. 构建 JSON 载荷（高保真 Emby Webhook 格式）
    final dateStr = _formatUtcTimestamp(DateTime.now().toUtc());

    final payload = {
      "Title": "媒体库删除: $payloadFileName",
      "Description": "ALClientN 联动删除: $payloadFileName",
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
      "Server": _serverInfo,
    };

    LogUtil.d('[$tag] 发送联动删除 Webhook:\n  URL: $webhookUrl\n  Payload: ${jsonEncode(payload)}',
        tag: tag);

    // 7. 发送请求 + 写日志
    final result =
        await _doPost(webhookUrl, payload, '联动删除', payloadFileName);
    if (showToast) {
      if (result.ok && result.pathMismatch) {
        _showPathMismatchDialog(payloadFileName, result.remotePath);
      } else if (result.ok) {
        SmartDialog.showToast('联动删除通知已发送');
      } else {
        SmartDialog.showToast('联动删除通知发送失败');
      }
    }
    return result;
  }

  /// 弹出路径不匹配的警告对话框（醒目提醒用户检查回收站）
  static void _showPathMismatchDialog(
      String expectedName, String actualRemotePath) {
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 28),
            const SizedBox(width: 8),
            const Text('⚠️ 联动删除路径异常',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SmartStrm 后端返回的删除路径与预期不符，'
                '可能误删了其他文件或目录！',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _mismatchRow('预期删除', expectedName),
                  const SizedBox(height: 8),
                  _mismatchRow('实际删除', actualRemotePath),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('请立即检查 SmartStrm 的回收站，恢复误删数据。',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600),
            onPressed: () => SmartDialog.dismiss(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  // ==================== UI 测试入口（模拟数据，不发送真实请求） ====================

  /// 测试：弹出单个文件路径异常警告对话框（模拟数据）
  static void showTestSingleMismatch() {
    _showPathMismatchDialog('test-video.(mp4)', '/media/videos');
  }

  /// 测试：弹出批量中止对话框（模拟数据）
  static void showTestBatchAbort() {
    _showAbortDialog(
      (expected: 'test-video.(mp4)', actual: '/media/videos'),
      5, 1, 12,
    );
  }

  static Widget _mismatchRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  /// 自动生成一个持久化的虚拟 Server ID（首次生成后存入 SpUtil，后续复用）
  static String _serverId() {
    const key = 'smartstrm_virtual_server_id';
    var id = SpUtil.getString(key);
    if (id != null && id.isNotEmpty) return id;
    // 生成 32 位随机 hex 字符串
    final r = Random();
    id = List.generate(32, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
    SpUtil.putString(key, id);
    return id;
  }

  /// Server 信息（自动生成，非真实 Emby 服务器）
  static Map<String, String> get _serverInfo => {
    "Name": "ALClientN_Virtual",
    "Id": _serverId(),
    "Version": "1.0.0",
  };

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
      "Server": _serverInfo,
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

  /// Webhook 发送结果
  /// [ok] 是否成功, [pathMismatch] 远端删除路径是否与预期不符,
  /// [remotePath] 服务端返回的 remote_path
  /// 实际执行 HTTP POST 并写日志
  static Future<_WebhookSendResult> _doPost(
    String webhookUrl,
    Map<String, dynamic> payload,
    String logAction,
    String logDetail,
  ) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
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

      // 判断成功: HTTP 200 且响应体的 success 字段为 true
      bool ok = response.statusCode == 200;
      bool pathMismatch = false;
      String remotePath = '';
      final expectedName = payload['Item']?['Name']?.toString() ?? '';

      if (response.data is Map) {
        final data = response.data as Map;
        if (data.containsKey('success')) {
          ok = data['success'] == true;
        }
        // 检查 remote_path 是否与预期一致：远端路径应当以预期的文件名结尾
        // SmartStrm 后端返回真实文件名，Item.Name 是 strm 文件名去后缀。
        // 归一化：取 remote_path 最后一段，把 .ext 转回 .(ext) 再比较。
        remotePath = data['remote_path']?.toString() ?? '';
        if (ok && remotePath.isNotEmpty && expectedName.isNotEmpty) {
          final actualFileName = remotePath.split('/').last;
          pathMismatch = _normalizeBackendFileName(actualFileName) != expectedName;
        }
      }

      await _logResult(ok, logAction, logDetail, payload,
          response.statusCode ?? -1, '${response.data}');
      if (pathMismatch) {
        final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
        await _appendLog(
            '[$ts] ⚠️ 路径异常！请求: $expectedName, 远端实际删除: $remotePath');
      }
      return _WebhookSendResult(
          ok: ok,
          pathMismatch: pathMismatch,
          remotePath: remotePath,
          expectedName: expectedName);
    } catch (e) {
      LogUtil.e('[$tag] 发送 Webhook 失败: $e', tag: tag);
      await _logResult(false, logAction, logDetail, payload, -1, '$e');
      final expectedName =
          payload['Item']?['Name']?.toString() ?? '';
      return _WebhookSendResult(
          ok: false,
          pathMismatch: false,
          remotePath: '',
          expectedName: expectedName);
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
  /// 将后端返回的真实文件名归一化为 strm 风格：.mp4 → .(mp4)
  ///
  /// 例如: "video.mp4" → "video.(mp4)"
  static String _normalizeBackendFileName(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == fileName.length - 1) return fileName;
    final nameWithoutExt = fileName.substring(0, lastDot);
    final ext = fileName.substring(lastDot + 1);
    return '$nameWithoutExt.($ext)';
  }

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
