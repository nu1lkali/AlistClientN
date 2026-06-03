import 'dart:io';

import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/disliked_video.dart';
import 'package:alist/entity/file_remove_req.dart';
import 'package:alist/net/dio_utils.dart';
import 'package:alist/screen/video_player_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final user = _userController.user.value;
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
      body: StreamBuilder<List<DislikedVideo>?>(
        stream: _databaseController.dislikedVideoDao.list(
          user.serverUrl,
          user.username,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];
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
              return Slidable(
                key: ValueKey(item.remotePath),
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
                  leading: const Icon(Icons.videocam_rounded),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(item.remotePath),
                  onTap: () => _preview(items, i),
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

    List<DislikedVideo> playlistItems;
    int playIndex;

    if (allItems.length <= maxPlaylistSize) {
      // 全部加入播放列表，顺序不变，index为选中项的index
      playlistItems = allItems;
      playIndex = selectedIndex;
    } else {
      // 以选中视频为起点往后加载，不足200个时往前补充
      int end = (selectedIndex + maxPlaylistSize) > allItems.length
          ? allItems.length
          : selectedIndex + maxPlaylistSize;
      int start = (end - maxPlaylistSize) < 0 ? 0 : end - maxPlaylistSize;
      playlistItems = allItems.sublist(start, end);
      playIndex = selectedIndex - start;
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

  Future<void> _unmark(DislikedVideo item) async {
    final user = _userController.user.value;
    await _databaseController.dislikedVideoDao
        .deleteByPath(user.serverUrl, user.username, item.remotePath);
    await DislikeLog.append('取消标记', item.name, item.remotePath, user.username, user.serverUrl);
    SmartDialog.showToast('已取消标记');
  }

  Future<void> _deleteSingle(DislikedVideo item) async {
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
            .deleteByPath(user.serverUrl, user.username, item.remotePath);
        SmartDialog.dismiss();
        DislikeLog.append('删除文件', item.name, item.remotePath, user.username, user.serverUrl);
        SmartDialog.showToast('删除成功');
      },
      onError: (_, msg) {
        DislikeLog.append('删除失败', item.name, item.remotePath, user.username, user.serverUrl);
        SmartDialog.dismiss();
        SmartDialog.showToast('删除失败: $msg');
      },
    );
  }

  Future<void> _unmarkAll() async {
    final user = _userController.user.value;
    final dao = _databaseController.dislikedVideoDao;
    final items = await dao.list(user.serverUrl, user.username).first;
    if (items == null || items.isEmpty) {
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
      await dao.deleteByPath(user.serverUrl, user.username, item.remotePath);
      await DislikeLog.append('批量取消标记', item.name, item.remotePath, user.username, user.serverUrl);
    }
    SmartDialog.showToast('已取消全部标记 (${items.length} 个)');
  }

  Future<void> _deleteAll() async {
    final user = _userController.user.value;
    final dao = _databaseController.dislikedVideoDao;
    final items = await dao.list(user.serverUrl, user.username).first;
    if (items == null || items.isEmpty) {
      SmartDialog.showToast('列表为空');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认全部删除'),
        content:
            Text('确定要删除列表中的 ${items.length} 个视频文件吗？\n\n此操作不可撤销。'),
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

    SmartDialog.showLoading(msg: '批量删除中...');
    int successCount = 0;
    int failCount = 0;

    for (final item in items) {
      final fileName = item.remotePath.substringAfterLast("/") ?? "";
      final dir = item.remotePath.substringBeforeLast("/$fileName") ?? "/";
      final req = FileRemoveReq();
      req.dir = dir.isEmpty ? "/" : dir;
      req.names = [fileName];

      await DioUtils.instance.requestNetwork<String?>(
        Method.post, 'fs/remove',
        params: req.toJson(),
        onSuccess: (_) {
          successCount++;
          dao.deleteByPath(user.serverUrl, user.username, item.remotePath);
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
        '删除完成: 成功 $successCount 个${failCount > 0 ? ', 失败 $failCount 个' : ''}');
  }
}