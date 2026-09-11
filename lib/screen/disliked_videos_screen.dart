import 'dart:async';
import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/disliked_video.dart';
import 'package:alist/entity/file_remove_req.dart';
import 'package:alist/entity/emby_config.dart';
import 'package:alist/entity/tiktok_play_list_model.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/net/emby_api.dart';
import 'package:alist/screen/video_player_screen.dart';
import 'package:alist/util/emby_config_manager.dart';
import 'package:alist/util/named_router.dart';
import 'package:alist/util/smart_strm_webhook.dart';
import 'package:alist/util/string_utils.dart';
import 'package:alist/util/user_controller.dart';
import 'package:alist/util/video_player_util.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class DislikeLog {
  static String _logPath = '';
  static Future<String> get logPath async {
    if (_logPath.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      _logPath = '${dir.path}/dislike_log.txt';
    }
    return _logPath;
  }

  static Future<void> append(String action, String name, String path, String user, String server) async {
    try {
      final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final line = '[$now] $action | name=$name | path=$path | user=$user | server=$server\n';
      final filePath = await logPath;
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(line, mode: FileMode.append);
    } catch (_) {}
  }

  static Future<String> read() async {
    try {
      final filePath = await logPath;
      final file = File(filePath);
      if (!await file.exists()) return '暂无日志';
      return await file.readAsString();
    } catch (_) {
      return '读取日志失败';
    }
  }
}

class DislikedVideosScreen extends StatefulWidget {
  const DislikedVideosScreen({super.key});

  @override
  State<DislikedVideosScreen> createState() => _DislikedVideosScreenState();
}

class _DislikedVideosScreenState extends State<DislikedVideosScreen> {
  final AlistDatabaseController _databaseController = Get.find();
  final UserController _userController = Get.find();

  /// AList（当前用户）不喜欢记录
  List<DislikedVideo> _alistItems = [];

  /// Emby 各服务器的不喜欢记录（serverId -> 记录）
  final Map<String, List<DislikedVideo>> _embyItems = {};

  final List<StreamSubscription<dynamic>> _subs = [];
  Worker? _embyRevisionWorker;

  /// 合并后的展示列表：AList 在前，Emby 在后
  List<DislikedVideo> get _displayItems =>
      [..._alistItems, ..._embyItems.values.expand((e) => e)];

  static bool _isEmbyItem(DislikedVideo item) =>
      item.provider == EmbyDislikeMark.provider;

  @override
  void initState() {
    super.initState();
    _resubscribe();
    // Emby 服务器增删/切换时重建订阅（媒体库/服务器配置在同一 revision 通知里）
    _embyRevisionWorker =
        ever(EmbyConfigManager.revision, (_) => _resubscribe());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _embyRevisionWorker?.dispose();
    super.dispose();
  }

  /// 订阅 AList 当前用户 + 各 Emby 服务器的不喜欢记录流。
  Future<void> _resubscribe() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _embyItems.clear();

    final user = _userController.user.value;
    _subs.add(
      _databaseController.dislikedVideoDao
          .list(user.serverUrl, user.username)
          .listen((rows) {
        _alistItems = rows ?? [];
        if (mounted) setState(() {});
      }),
    );

    for (final server in EmbyConfigManager.loadServers()) {
      _subs.add(
        _databaseController.dislikedVideoDao
            .list(server.id, EmbyDislikeMark.userId)
            .listen((rows) {
          _embyItems[server.id] = rows ?? [];
          if (mounted) setState(() {});
        }),
      );
    }
  }

  EmbyServerConfig? _embyServerOf(DislikedVideo item) {
    final servers = EmbyConfigManager.loadServers();
    final idx = servers.indexWhere((s) => s.id == item.serverUrl);
    return idx >= 0 ? servers[idx] : null;
  }

  String _embyServerName(DislikedVideo item) {
    final server = _embyServerOf(item);
    if (server == null) return 'Emby（配置已删除）';
    return server.remark.isNotEmpty ? server.remark : server.serverOrigin;
  }

  @override
  Widget build(BuildContext context) {
    return AlistScaffold(
      appbarTitle: const Text('不喜欢视频列表'),
      appbarActions: [
        IconButton(
          icon: const Icon(Icons.article_outlined),
          tooltip: '查看日志',
          onPressed: () => _showLog(context),
        ),
        IconButton(
          icon: const Icon(Icons.thumb_up_alt_rounded),
          tooltip: '取消全部标记（不删除文件）',
          onPressed: () => _unmarkAll(),
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep_rounded, size: 28),
          tooltip: '全部删除（删除文件）',
          onPressed: () => _deleteAll(),
        ),
      ],
      body: Builder(
        builder: (context) {
          final items = _displayItems;
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.thumb_down_alt_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    '还没有标记不喜欢的视频',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final item = items[i];
              final isEmby = _isEmbyItem(item);
              return Slidable(
                key: ValueKey('${item.serverUrl}|${item.remotePath}'),
                endActionPane: ActionPane(
                  motion: const BehindMotion(),
                  extentRatio: 0.5,
                  children: [
                    SlidableAction(
                      onPressed: (_) => _unmark(item),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      label: '取消',
                    ),
                    SlidableAction(
                      onPressed: (_) => _deleteSingle(item),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      label: '删除',
                    ),
                  ],
                ),
                child: ListTile(
                  leading: Icon(
                    isEmby ? Icons.movie_filter_rounded : Icons.videocam_rounded,
                    color: isEmby
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    isEmby
                        ? 'Emby · ${_embyServerName(item)} · Id: ${item.remotePath}'
                        : item.remotePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isEmby
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Emby',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.primary)),
                        )
                      : null,
                  onTap: () => isEmby
                      ? _previewEmby(item)
                      : _preview(_alistItems, _alistItems.indexOf(item)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showLog(BuildContext context) async {
    final content = await DislikeLog.read();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    const Text('操作日志', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '清空日志',
                      onPressed: () async {
                        try {
                          final path = await DislikeLog.logPath;
                          await File(path).writeAsString('');
                          if (ctx.mounted) Navigator.pop(ctx);
                          SmartDialog.showToast('日志已清空');
                        } catch (_) {
                          SmartDialog.showToast('清空失败');
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    content,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _preview(List<DislikedVideo> allItems, int selectedIndex) {
    const int maxPlaylistSize = 200;
    if (allItems.isEmpty) return;
    final safeIndex = selectedIndex < 0 ? 0 : selectedIndex;

    List<DislikedVideo> playlistItems;
    int playIndex;

    if (allItems.length <= maxPlaylistSize) {
      // 全部加入播放列表，顺序不变，index为选中项的index
      playlistItems = allItems;
      playIndex = safeIndex;
    } else {
      // 以选中视频为起点往后加载，不足200个时往前补充
      int end = (safeIndex + maxPlaylistSize) > allItems.length
          ? allItems.length
          : safeIndex + maxPlaylistSize;
      int start = (end - maxPlaylistSize) < 0 ? 0 : end - maxPlaylistSize;
      playlistItems = allItems.sublist(start, end);
      playIndex = safeIndex - start;
    }

    final videos = playlistItems.map((item) => VideoItem(
      name: item.name,
      remotePath: item.remotePath,
      sign: item.sign,
      provider: item.provider,
      thumb: item.thumb,
      size: item.size,
      modifiedMilliseconds: item.modified,
    )).toList();

    VideoPlayerUtil.go(videos, playIndex, null);
  }

  /// 预览 Emby 条目：用 Emby 直链进入“视界流”（单条播放）。
  void _previewEmby(DislikedVideo item) {
    final server = _embyServerOf(item);
    if (server == null || !server.isValid) {
      SmartDialog.showToast('对应的 Emby 服务器配置已被删除，无法播放');
      return;
    }
    final streamUrl = EmbyApi.buildStreamUrl(server, item.remotePath);
    final video = TikTokVideoItem(
      id: streamUrl,
      fileName: item.name,
      videoUrl: streamUrl,
      filePath: item.name,
      thumb: item.thumb,
      embyItemId: item.remotePath,
    );
    Get.toNamed(
      NamedRouter.tiktokPlayer,
      arguments: TikTokPlayListModel(
        videos: [video],
        initialIndex: 0,
        recordHistory: false,
        fromEmby: true,
      ),
    );
  }

  Future<void> _unmark(DislikedVideo item) async {
    await _databaseController.dislikedVideoDao
        .deleteByPath(item.serverUrl, item.userId, item.remotePath);
    await DislikeLog.append(
        '取消标记', item.name, item.remotePath, item.userId, item.serverUrl);
    SmartDialog.showToast('已取消标记');
  }

  Future<void> _deleteSingle(DislikedVideo item) async {
    if (_isEmbyItem(item)) {
      await _deleteEmbyItem(item);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除文件 "${item.name}" 吗？\n\n此操作不可撤销，文件将被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final fileName = item.remotePath.substringAfterLast("/") ?? "";
    final dir = item.remotePath.substringBeforeLast("/$fileName") ?? "/";
    final req = FileRemoveReq();
    req.dir = dir.isEmpty ? "/" : dir;
    req.names = [fileName];

    SmartDialog.showLoading(msg: '删除中...');
    final user = _userController.user.value;
    await DioUtils.instance.requestNetwork<String?>(
      Method.post, 'fs/remove',
      params: req.toJson(),
      onSuccess: (_) {
        _databaseController.dislikedVideoDao
            .deleteByPath(item.serverUrl, item.userId, item.remotePath);
        SmartDialog.dismiss();
        DislikeLog.append('删除文件', item.name, item.remotePath, user.username, user.serverUrl);
        SmartDialog.showToast('删除成功');
        // 联动删除：仅对 .strm 文件发送 Webhook + 删除帧截图
        if (SmartStrmWebhook.isStrmFile(item.name)) {
          SmartStrmWebhook.sendDeleteWebhook(item.remotePath);
          SmartStrmWebhook.deleteAssociatedThumbnails(item.remotePath);
        }
      },
      onError: (_, msg) {
        DislikeLog.append('删除失败', item.name, item.remotePath, user.username, user.serverUrl);
        SmartDialog.dismiss();
        SmartDialog.showToast('删除失败: $msg');
      },
    );
  }

  /// Emby 条目删除：调用 DELETE /Items/{Id} 从服务器（媒体库 + 物理文件）删除，
  /// 成功后移除本地不喜欢记录；不触碰 AList 删除与 .strm webhook 逻辑。
  Future<void> _deleteEmbyItem(DislikedVideo item) async {
    final server = _embyServerOf(item);
    if (server == null || !server.isValid) {
      SmartDialog.showToast('对应的 Emby 服务器配置已被删除，无法删除该媒体');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除（Emby）'),
        content: Text(
            '将通过 Emby 接口删除媒体 "${item.name}"：\n'
            '• 从媒体库移除\n'
            '• 同时删除服务器上的媒体文件\n\n'
            '此操作需要管理员权限的 API Key，且不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    SmartDialog.showLoading(msg: '正在从 Emby 删除...');
    try {
      await EmbyApi.deleteItem(server, item.remotePath);
      await _databaseController.dislikedVideoDao
          .deleteByPath(item.serverUrl, item.userId, item.remotePath);
      SmartDialog.dismiss();
      DislikeLog.append(
          '删除Emby媒体', item.name, item.remotePath, item.userId, item.serverUrl);
      SmartDialog.showToast('已从 Emby 删除');
    } catch (e) {
      SmartDialog.dismiss();
      DislikeLog.append(
          '删除Emby媒体失败', item.name, item.remotePath, item.userId, item.serverUrl);
      SmartDialog.showToast(e.toString());
    }
  }

  Future<void> _unmarkAll() async {
    final items = _displayItems;
    if (items.isEmpty) {
      SmartDialog.showToast('列表为空');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认取消全部标记'),
        content: Text('确定要取消 ${items.length} 个视频的不喜欢标记吗？（不会删除文件）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final item in items) {
      await _databaseController.dislikedVideoDao
          .deleteByPath(item.serverUrl, item.userId, item.remotePath);
      await DislikeLog.append(
          '批量取消标记', item.name, item.remotePath, item.userId, item.serverUrl);
    }
    SmartDialog.showToast('已取消全部标记 (${items.length} 个)');
  }

  Future<void> _deleteAll() async {
    final items = _displayItems;
    if (items.isEmpty) {
      SmartDialog.showToast('列表为空');
      return;
    }

    final embyCount = items.where(_isEmbyItem).length;
    final alistCount = items.length - embyCount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认全部删除'),
        content: Text(
            '确定要删除列表中的 ${items.length} 个视频吗？\n\n'
            '• AList 条目（$alistCount 个）：删除服务器文件\n'
            '• Emby 条目（$embyCount 个）：通过 Emby 接口删除媒体与文件\n\n'
            '此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // ── 1) Emby 条目：按服务器分组，使用批量接口 DELETE /Items?Ids= ──
    var embyOk = 0;
    var embyFail = 0;
    if (embyCount > 0) {
      SmartDialog.showLoading(msg: '正在从 Emby 删除...');
      final byServer = <String, List<DislikedVideo>>{};
      for (final item in items.where(_isEmbyItem)) {
        byServer.putIfAbsent(item.serverUrl, () => []).add(item);
      }
      for (final entry in byServer.entries) {
        final server = _embyServerOf(entry.value.first);
        if (server == null || !server.isValid) {
          embyFail += entry.value.length;
          continue;
        }
        final ids = entry.value.map((e) => e.remotePath).toList();
        try {
          await EmbyApi.deleteItems(server, ids);
          embyOk += entry.value.length;
          for (final item in entry.value) {
            await _databaseController.dislikedVideoDao
                .deleteByPath(item.serverUrl, item.userId, item.remotePath);
            DislikeLog.append('批量删除Emby媒体', item.name, item.remotePath,
                item.userId, item.serverUrl);
          }
        } catch (e) {
          embyFail += entry.value.length;
          for (final item in entry.value) {
            DislikeLog.append('批量删除Emby媒体失败', item.name, item.remotePath,
                item.userId, item.serverUrl);
          }
        }
      }
      SmartDialog.dismiss();
    }

    // ── 2) AList 条目：保持原有删除 + 联动 Webhook 逻辑 ──
    final alistItems = items.where((e) => !_isEmbyItem(e)).toList();
    if (alistItems.isNotEmpty) {
      SmartDialog.showLoading(msg: '批量删除中...');
      int successCount = 0;
      int failCount = 0;
      final strmPaths = <String>[];
      final user = _userController.user.value;

      for (final item in alistItems) {
        final fileName = item.remotePath.substringAfterLast("/") ?? "";
        final dir = item.remotePath.substringBeforeLast("/$fileName") ?? "/";
        final req = FileRemoveReq();
        req.dir = dir.isEmpty ? "/" : dir;
        req.names = [fileName];

        if (SmartStrmWebhook.isStrmFile(item.name)) {
          strmPaths.add(item.remotePath);
        }

        await DioUtils.instance.requestNetwork<String?>(
          Method.post, 'fs/remove',
          params: req.toJson(),
          onSuccess: (_) {
            successCount++;
            _databaseController.dislikedVideoDao
                .deleteByPath(item.serverUrl, item.userId, item.remotePath);
            DislikeLog.append('批量删除', item.name, item.remotePath, user.username, user.serverUrl);
          },
          onError: (_, __) {
            failCount++;
            DislikeLog.append('批量删除失败', item.name, item.remotePath, user.username, user.serverUrl);
          },
        );
      }

      SmartDialog.dismiss();
      SmartDialog.showToast(
          'AList 删除完成: 成功 $successCount 个${failCount > 0 ? ', 失败 $failCount 个' : ''}');

      // 联动删除：后台批量发送 Webhook + 帧截图，汇总后统一弹 toast
      if (strmPaths.isNotEmpty) {
        _sendBatchWebhooksWithSummary(strmPaths);
      }
    }

    if (embyCount > 0) {
      SmartDialog.showToast(
          'Emby 删除完成: 成功 $embyOk 个${embyFail > 0 ? ', 失败 $embyFail 个' : ''}');
    }
  }

  /// 后台批量发送联动删除 Webhook + 帧截图，完成后统一弹 toast 汇总
  void _sendBatchWebhooksWithSummary(List<String> paths) async {
    final result = await SmartStrmWebhook.sendBatchDeleteWebhooks(paths);
    // 仅对已成功发送的删除帧截图（跳过被中止的）
    final effectiveCount = result.success + result.fail;
    for (var i = 0; i < effectiveCount && i < paths.length; i++) {
      await SmartStrmWebhook.deleteAssociatedThumbnails(paths[i]);
    }
    // 路径异常中止时，dialog 已由 sendBatchDeleteWebhooks 内部弹出，不再弹 toast
    if (result.aborted) return;
    if (result.success > 0 && result.fail == 0) {
      SmartDialog.showToast('联动删除通知: 全部成功 (${result.success}个)');
    } else if (result.success > 0 && result.fail > 0) {
      SmartDialog.showToast(
          '联动删除通知: 成功 ${result.success} 个, 失败 ${result.fail} 个');
    } else if (result.success == 0 && result.fail > 0) {
      SmartDialog.showToast('联动删除通知: 全部失败 (${result.fail}个)');
    }
  }
}
