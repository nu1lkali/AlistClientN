import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/favorite_folder.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/favorite_helper.dart';
import 'package:alist/util/user_controller.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 收藏夹左侧面板（用于收藏页主从布局）
class FavoriteFolderPanel extends StatefulWidget {
  final int? selectedFolderId; // null = 全部收藏
  final ValueChanged<int?> onFolderSelected;

  const FavoriteFolderPanel({
    Key? key,
    required this.selectedFolderId,
    required this.onFolderSelected,
  }) : super(key: key);

  @override
  State<FavoriteFolderPanel> createState() => _FavoriteFolderPanelState();
}

class _FavoriteFolderPanelState extends State<FavoriteFolderPanel> {
  final AlistDatabaseController _db = Get.find();
  final UserController _userController = Get.find();
  List<FavoriteFolder> _folders = [];

  @override
  void initState() {
    super.initState();
    _ensureAndLoadFolders();
  }

  Future<void> _ensureAndLoadFolders() async {
    await FavoriteHelper.ensureDefaultFolder();
    final user = _userController.user.value;
    final folders =
        await _db.favoriteFolderDao.getAll(user.serverUrl, user.username) ?? [];
    if (mounted) setState(() => _folders = folders);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 260,
      color: scheme.surfaceVariant,
      child: Column(
        children: [
          // 标题
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Text('收藏夹', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  tooltip: '新建收藏夹',
                  onPressed: _showCreateDialog,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                // 全部收藏
                _buildItem(
                  icon: Icons.collections_rounded,
                  title: '全部收藏',
                  isSelected: widget.selectedFolderId == null,
                  onTap: () => widget.onFolderSelected(null),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                // 各收藏夹
                ..._folders.map((folder) => _buildFolderItem(folder)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderItem(FavoriteFolder folder) {
    final isSelected = widget.selectedFolderId == folder.id;
    final scheme = Theme.of(context).colorScheme;
    final configDefaultId = SpUtil.getInt(AlistConstant.favoriteDefaultFolderId);
    final isConfigDefault = folder.id == configDefaultId;

    return ListTile(
      leading: Icon(
        folder.isDefault ? Icons.star_rounded : Icons.folder_rounded,
        size: 22,
        color: folder.isDefault ? Colors.amber : scheme.primary,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? scheme.primary : null,
              ),
            ),
          ),
          if (isConfigDefault) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber, width: 0.8),
              ),
              child: const Text(
                '默认',
                style: TextStyle(fontSize: 10, color: Colors.amber, height: 1.4),
              ),
            ),
          ],
        ],
      ),
      selected: isSelected,
      selectedTileColor: scheme.primaryContainer.withOpacity(0.3),
      onTap: () => widget.onFolderSelected(folder.id),
      onLongPress: () => _showFolderMenu(folder),
    );
  }

  Widget _buildItem({
    required IconData icon,
    Color? iconColor,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, size: 22, color: iconColor ?? scheme.primary),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? scheme.primary : null,
        ),
      ),
      selected: isSelected,
      selectedTileColor: scheme.primaryContainer.withOpacity(0.3),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  void _showFolderMenu(FavoriteFolder folder) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(folder.name,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_rounded),
              title: const Text('设为默认收藏夹'),
              onTap: () {
                Navigator.pop(ctx);
                FavoriteHelper.setAsDefaultFolder(folder).then((_) {
                  _ensureAndLoadFolders();
                });
              },
            ),
            if (!folder.isDefault)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('删除收藏夹',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(folder);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog() async {
    final name = await _showNameInputDialog('新建收藏夹', '');
    if (name != null && name.isNotEmpty) {
      final user = _userController.user.value;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.favoriteFolderDao.insertFolder(FavoriteFolder(
        serverUrl: user.serverUrl,
        userId: user.username,
        name: name,
        isDefault: false,
        sort: _folders.length,
        createTime: now,
      ));
      SmartDialog.showToast('已创建收藏夹: $name');
      _ensureAndLoadFolders();
    }
  }

  void _showRenameDialog(FavoriteFolder folder) async {
    final name = await _showNameInputDialog('重命名收藏夹', folder.name);
    if (name != null && name.isNotEmpty && name != folder.name) {
      await FavoriteHelper.renameFolder(folder, name);
      SmartDialog.showToast('已重命名');
      _ensureAndLoadFolders();
    }
  }

  Future<String?> _showNameInputDialog(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '收藏夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(FavoriteFolder folder) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除收藏夹'),
        content: Text('删除「${folder.name}」？夹内文件将移至默认收藏夹，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              FavoriteHelper.deleteFolder(folder).then((success) {
                if (success) _ensureAndLoadFolders();
              });
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
