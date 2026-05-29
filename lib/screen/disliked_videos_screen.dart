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
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

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
      appbarTitle: const Text('不喜欢列表'),
      appbarActions: [
        IconButton(
          icon: const Icon(Icons.delete_sweep_rounded),
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
              return ListTile(
                leading: const Icon(Icons.videocam_rounded),
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(item.remotePath),
                onTap: () => _preview(item),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.thumb_up_alt_rounded),
                      tooltip: '取消标记',
                      onPressed: () => _unmark(item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: '删除文件',
                      onPressed: () => _deleteSingle(item),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _preview(DislikedVideo item) {
    final video = VideoItem(
      name: item.name,
      remotePath: item.remotePath,
      sign: item.sign,
      provider: item.provider,
      thumb: item.thumb,
      size: item.size,
      modifiedMilliseconds: item.modified,
    );
    VideoPlayerUtil.go([video], 0, null);
  }

  Future<void> _unmark(DislikedVideo item) async {
    final user = _userController.user.value;
    await _databaseController.dislikedVideoDao
        .deleteByPath(user.serverUrl, user.username, item.remotePath);
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
    await DioUtils.instance.requestNetwork<String?>(
      Method.post, 'fs/remove',
      params: req.toJson(),
      onSuccess: (_) {
        final user = _userController.user.value;
        _databaseController.dislikedVideoDao
            .deleteByPath(user.serverUrl, user.username, item.remotePath);
        SmartDialog.dismiss();
        SmartDialog.showToast('删除成功');
      },
      onError: (_, msg) {
        SmartDialog.dismiss();
        SmartDialog.showToast('删除失败: $msg');
      },
    );
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
        },
        onError: (_, __) {
          failCount++;
        },
      );
    }

    SmartDialog.dismiss();
    SmartDialog.showToast(
        '删除完成: 成功 $successCount 个${failCount > 0 ? ', 失败 $failCount 个' : ''}');
  }
}