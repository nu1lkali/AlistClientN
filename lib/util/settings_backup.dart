import 'dart:convert';
import 'dart:io';

import 'package:alist/util/emby_config_manager.dart';
import 'package:alist/util/log_utils.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置备份（导出 / 导入）。
///
/// 导出：将 SharedPreferences 中的全部设置项（播放器、界面、Emby 随机播放、
/// .strm、字幕等）序列化为 JSON 文件。优先写入**公共 Download/AlistBackup/**
/// （需要“所有文件访问”权限时会主动申请），失败则回退 App 专属目录；
/// 同时支持一键复制 JSON 文本（便于跨设备粘贴导入）。
///
/// 导入：两种方式
/// 1. 自动扫描：列出 Download/AlistBackup 与 App 目录下的备份（可单个删除）；
/// 2. 手动选择：用文件选择器在手机存储中挑选任意 .json 备份；
/// 另外也支持从剪贴板粘贴 JSON。校验后写回 SharedPreferences 并刷新 Emby 配置订阅。
///
/// 说明：AList 服务器账号、收藏、观看记录等存储在 SQLite 数据库中，不属于
/// 设置项，本备份不包含它们。

const String _backupPrefix = 'alist_settings_backup_';
const String _payloadType = 'alist_settings_backup';
const String _backupFolder = 'AlistBackup';
const String _publicDownloadPath = '/storage/emulated/0/Download';

// ───────────────────────── 目录与权限 ─────────────────────────

/// 请求存储权限：Android 11+ 申请“所有文件访问”，Android ≤10 申请存储权限。
Future<bool> _requestStoragePermission() async {
  if (!Platform.isAndroid) return false;
  try {
    var sdk = 0;
    try {
      sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (_) {}
    if (sdk >= 30) {
      if (await Permission.manageExternalStorage.isGranted) return true;
      final st = await Permission.manageExternalStorage.request();
      return st.isGranted;
    }
    if (await Permission.storage.isGranted) return true;
    final st = await Permission.storage.request();
    return st.isGranted;
  } catch (_) {
    return false;
  }
}

/// 公共 Download/AlistBackup 目录（写入探测通过才返回）。
///
/// [requestPermission] 为 true 时，首次探测失败会申请权限后重试。
Future<Directory?> _publicBackupDir({bool requestPermission = true}) async {
  if (!Platform.isAndroid) return null;

  Directory? probe() {
    try {
      final dir = Directory('$_publicDownloadPath/$_backupFolder');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File('${dir.path}/.write_test');
      f.writeAsStringSync('ok');
      f.deleteSync();
      return dir;
    } catch (_) {
      return null;
    }
  }

  var dir = probe();
  if (dir != null) return dir;
  if (!requestPermission) return null;
  if (await _requestStoragePermission()) dir = probe();
  return dir;
}

/// App 专属目录（无需权限，始终可用）。
Future<Directory> _privateBackupDir() async {
  Directory base;
  try {
    base = (await getExternalStorageDirectory()) ??
        await getApplicationDocumentsDirectory();
  } catch (_) {
    base = await getApplicationDocumentsDirectory();
  }
  final dir = Directory('${base.path}/$_backupFolder');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// 导出目标目录：优先公共 Download，回退 App 专属目录。
Future<(Directory, bool)> _resolveExportDir() async {
  final pub = await _publicBackupDir();
  if (pub != null) return (pub, true);
  return (await _privateBackupDir(), false);
}

/// 收集可导入的备份文件（两个目录合并，按修改时间倒序，同路径去重）。
Future<List<File>> _listBackupFiles() async {
  final dirs = <Directory>[];
  final pub = await _publicBackupDir(requestPermission: false);
  if (pub != null) dirs.add(pub);
  dirs.add(await _privateBackupDir());

  final seen = <String>{};
  final files = <File>[];
  for (final d in dirs) {
    try {
      for (final f in d.listSync().whereType<File>().where(_isBackupFile)) {
        if (seen.add(f.path)) files.add(f);
      }
    } catch (e) {
      Log.e('list backup dir ${d.path}: $e');
    }
  }
  files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  return files;
}

bool _isBackupFile(File f) {
  final name = f.path.split(Platform.pathSeparator).last;
  return name.startsWith(_backupPrefix) && name.endsWith('.json');
}

String _nowStamp() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${two(n.month)}${two(n.day)}_'
      '${two(n.hour)}${two(n.minute)}${two(n.second)}';
}

String _formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 文件位置标签：Download / App 目录
String _locationLabel(File f) =>
    f.path.contains('/Download/') ? 'Download' : 'App 目录';

/// 文件选择器的初始目录：优先 Download/AlistBackup。
Directory? _pickerInitialDirectory() {
  try {
    final backup = Directory('$_publicDownloadPath/$_backupFolder');
    if (backup.existsSync()) return backup;
    final download = Directory(_publicDownloadPath);
    if (download.existsSync()) return download;
  } catch (_) {}
  return null;
}

// ───────────────────────── 导出 ─────────────────────────

Future<void> exportSettings(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final data = <String, dynamic>{};
  for (final key in prefs.getKeys()) {
    data[key] = prefs.get(key);
  }

  // 导出前先确认
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('导出配置'),
      content: Text(
          '将把全部设置项（共 ${data.length} 项：播放器、界面、Emby 随机播放、'
          '.strm、字幕等）导出为 JSON 备份。\n\n'
          '保存位置：Download/AlistBackup/（若无法写入会申请“所有文件访问”权限，'
          '被拒绝时回退到 App 专属目录）。\n\n确定导出吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('取消',
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
          child: const Text('导出'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final payload = <String, dynamic>{
    'app': 'AlistClientN',
    'type': _payloadType,
    'formatVersion': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'count': data.length,
    'data': data,
  };
  final json = const JsonEncoder.withIndent('  ').convert(payload);

  String? savedPath;
  bool isPublic = false;
  String? errorText;
  try {
    final (dir, pub) = await _resolveExportDir();
    isPublic = pub;
    final file = File('${dir.path}/$_backupPrefix${_nowStamp()}.json');
    await file.writeAsString(json);
    savedPath = file.path;
  } catch (e) {
    errorText = '$e';
  }
  Log.d('settings export: ${savedPath ?? errorText} (download=$isPublic)');

  if (!context.mounted) return;
  final scheme = Theme.of(context).colorScheme;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('导出配置'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              errorText != null
                  ? '写入文件失败：$errorText\n仍可复制下面的 JSON 文本自行保存'
                  : isPublic
                      ? '已导出 ${data.length} 项设置到 Download 文件夹：\n$savedPath'
                      : '已导出 ${data.length} 项设置到 App 专属目录（未能写入 Download，'
                          '可在系统设置中授予本应用“所有文件访问”权限后重试）：\n$savedPath',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: errorText == null ? scheme.onSurface : scheme.error),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surfaceVariant.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    json,
                    style:
                        const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: json));
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            _showSnack(context, 'JSON 已复制到剪贴板');
          },
          child: const Text('复制 JSON'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

// ───────────────────────── 导入 ─────────────────────────

Future<void> importSettings(BuildContext context) async {
  final files = await _listBackupFiles();

  if (!context.mounted) return;
  final choice = await showDialog<_ImportSource>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('导入配置'),
        children: [
          if (files.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('未自动扫描到备份文件，可“手动选择文件”或从剪贴板导入。',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('自动扫描到 ${files.length} 个备份，可点右侧图标删除多余的',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ),
            for (final f in List<File>.from(files))
              ListTile(
                dense: true,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(
                  f.path.split(Platform.pathSeparator).last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_locationLabel(f)} · ${(f.statSync().size / 1024).toStringAsFixed(1)} KB'
                  ' · ${_formatTime(f.statSync().modified)}',
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: '删除此备份',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    final ok = await _confirmDeleteBackup(ctx, f);
                    if (ok != true) return;
                    try {
                      if (f.existsSync()) f.deleteSync();
                      setDialogState(() => files.remove(f));
                      if (context.mounted) {
                        _showSnack(context, '已删除备份');
                      }
                    } catch (e) {
                      if (context.mounted) _showSnack(context, '删除失败：$e');
                    }
                  },
                ),
                onTap: () => Navigator.of(ctx).pop(_ImportSource.file(f)),
              ),
          ],
          const Divider(height: 1),
          // 手动选择文件（文件选择器，可在任意目录挑选 .json 备份）
          SimpleDialogOption(
            onPressed: () => _pickBackupFileManually(ctx, context),
            child: const ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.folder_open_rounded),
              title: Text('手动选择文件…'),
            ),
          ),
          // 从剪贴板导入
          SimpleDialogOption(
            onPressed: () async {
              final clip = await Clipboard.getData(Clipboard.kTextPlain);
              final text = clip?.text;
              if (!ctx.mounted) return;
              if (text == null || text.trim().isEmpty) {
                Navigator.of(ctx).pop();
                _showSnack(context, '剪贴板里没有文本内容');
                return;
              }
              Navigator.of(ctx).pop(_ImportSource.clipboard(text));
            },
            child: const ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.content_paste_rounded),
              title: Text('从剪贴板导入 JSON'),
            ),
          ),
        ],
      ),
    ),
  );

  if (choice == null || !context.mounted) return;

  // 读取 JSON 文本
  String jsonText;
  if (choice.file != null) {
    try {
      jsonText = await choice.file!.readAsString();
    } catch (e) {
      if (context.mounted) _showSnack(context, '读取备份文件失败：$e');
      return;
    }
  } else {
    jsonText = choice.clipboardText ?? '';
  }

  // 解析
  Map<String, dynamic> data;
  String? exportedAt;
  try {
    final decoded = jsonDecode(jsonText);
    data = _extractData(decoded);
    if (decoded is Map && decoded['exportedAt'] is String) {
      exportedAt = decoded['exportedAt'] as String;
    }
  } catch (e) {
    if (context.mounted) _showSnack(context, '备份内容解析失败：$e');
    return;
  }
  if (data.isEmpty) {
    if (context.mounted) _showSnack(context, '备份内容为空，未导入任何配置');
    return;
  }

  if (!context.mounted) return;
  // 覆盖确认
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('导入配置'),
      content: Text(
          '将导入 ${data.length} 项设置${exportedAt != null ? '（导出于 $exportedAt）' : ''}，'
          '并覆盖当前同名配置。\n\n确定继续吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('取消',
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
          child: const Text('导入'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final count = await _applyData(data);
  // 通知 Emby 配置订阅刷新（媒体库/服务器选中项等）
  EmbyConfigManager.revision.value++;
  if (!context.mounted) return;
  _showSnack(context, '已导入 $count 项配置（部分设置重启 App 后完全生效）');
}

/// 手动选择备份文件：打开文件选择器（默认定位到 Download/AlistBackup）。
Future<void> _pickBackupFileManually(
    BuildContext dialogCtx, BuildContext pageContext) async {
  try {
    final picked = await FilesystemPicker.openDialog(
      context: dialogCtx,
      fsType: FilesystemType.file,
      title: '选择配置备份文件',
      pickText: '导入此文件',
      rootDirectory: Directory('/storage/emulated/0'),
      directory: _pickerInitialDirectory(),
      allowedExtensions: const ['.json'],
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
      theme: FilesystemPickerTheme(
        topBar: FilesystemPickerTopBarThemeData(
          titleTextStyle: const TextStyle(fontSize: 16),
          iconTheme: const IconThemeData(size: 20),
        ),
        fileList: FilesystemPickerFileListThemeData(
          textScaleFactor: 0.9,
          iconSize: 24,
          folderTextStyle: const TextStyle(fontSize: 14),
        ),
      ),
    );
    if (!dialogCtx.mounted) return;
    if (picked == null || picked.isEmpty) return; // 用户取消：留在导入对话框
    Navigator.of(dialogCtx).pop(_ImportSource.file(File(picked)));
  } catch (e) {
    if (dialogCtx.mounted) _showSnack(pageContext, '打开文件选择器失败：$e');
  }
}

Future<bool?> _confirmDeleteBackup(BuildContext context, File f) {
  final name = f.path.split(Platform.pathSeparator).last;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('删除备份'),
      content: Text('确定删除备份文件「$name」吗？\n删除后不可恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('取消',
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('删除'),
        ),
      ],
    ),
  );
}

class _ImportSource {
  final File? file;
  final String? clipboardText;
  const _ImportSource.file(this.file) : clipboardText = null;
  const _ImportSource.clipboard(this.clipboardText) : file = null;
}

/// 兼容两种格式：完整备份 payload（含 data 字段）或裸的设置 map。
Map<String, dynamic> _extractData(dynamic decoded) {
  if (decoded is! Map) {
    throw const FormatException('不是有效的 JSON 对象');
  }
  final raw = decoded['data'];
  final source = raw is Map ? raw : decoded;
  return source.map((k, v) => MapEntry(k.toString(), v));
}

Future<int> _applyData(Map<String, dynamic> data) async {
  final prefs = await SharedPreferences.getInstance();
  var count = 0;
  for (final entry in data.entries) {
    final v = entry.value;
    try {
      if (v is String) {
        await prefs.setString(entry.key, v);
      } else if (v is bool) {
        await prefs.setBool(entry.key, v);
      } else if (v is int) {
        await prefs.setInt(entry.key, v);
      } else if (v is double) {
        await prefs.setDouble(entry.key, v);
      } else if (v is List) {
        await prefs.setStringList(
            entry.key, v.map((e) => e.toString()).toList());
      } else {
        continue; // 未知类型跳过
      }
      count++;
    } catch (e) {
      Log.e('import "${entry.key}" failed: $e');
    }
  }
  return count;
}

void _showSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 4),
  ));
}
