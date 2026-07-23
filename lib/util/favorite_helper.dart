import 'package:alist/database/alist_database_controller.dart';
import 'package:alist/database/table/favorite.dart';
import 'package:alist/database/table/favorite_folder.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/user_controller.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 收藏统一入口：处理"默认收藏夹"逻辑与"弹窗选夹"逻辑
class FavoriteHelper {
  FavoriteHelper._();

  static final AlistDatabaseController _db = Get.find();
  static final UserController _userController = Get.find();

  /// 确保当前用户至少有一个默认收藏夹，返回默认夹（如果没有则创建）
  static Future<FavoriteFolder> ensureDefaultFolder() async {
    final user = _userController.user.value;
    var defaultFolder = await _db.favoriteFolderDao.findDefault(
        user.serverUrl, user.username);
    if (defaultFolder != null) return defaultFolder;

    // 没有默认夹 → 创建一个
    final now = DateTime.now().millisecondsSinceEpoch;
    final folder = FavoriteFolder(
      serverUrl: user.serverUrl,
      userId: user.username,
      name: '默认收藏夹',
      isDefault: true,
      sort: 0,
      createTime: now,
    );
    final id = await _db.favoriteFolderDao.insertFolder(folder);
    return FavoriteFolder(
      id: id,
      serverUrl: folder.serverUrl,
      userId: folder.userId,
      name: folder.name,
      isDefault: folder.isDefault,
      sort: folder.sort,
      createTime: folder.createTime,
    );
  }

  /// 判断是否启用了默认收藏夹
  static bool isUseDefaultFolderEnabled() {
    return SpUtil.getBool(AlistConstant.favoriteUseDefaultFolder,
        defValue: false) ?? false;
  }

  /// 获取配置的默认收藏夹 ID
  static int? getConfiguredDefaultFolderId() {
    return SpUtil.getInt(AlistConstant.favoriteDefaultFolderId);
  }

  /// 添加收藏的统一入口。
  /// - 如果启用了默认收藏夹且默认夹有效 → 直接收藏到该夹
  /// - 否则 → 弹出选择收藏夹 Dialog
  ///
  /// [onComplete] 回调返回是否收藏成功（true=已收藏, false=用户取消）
  static Future<bool> addFavorite(
    BuildContext? context, {
    required bool isDir,
    required String remotePath,
    required String name,
    required String path,
    required int size,
    String? sign,
    String? thumb,
    required int modified,
    required String provider,
  }) async {
    final user = _userController.user.value;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 先检查是否已收藏（避免重复）
    final existing = await _db.favoriteDao.findByPath(
        user.serverUrl, user.username, path);
    if (existing != null) {
      SmartDialog.showToast('已经在收藏夹中了');
      return false;
    }

    int? folderId;

    if (isUseDefaultFolderEnabled()) {
      // 启用了默认收藏夹
      final configuredId = getConfiguredDefaultFolderId();
      if (configuredId != null) {
        final folder =
            await _db.favoriteFolderDao.findById(configuredId);
        if (folder != null) {
          folderId = folder.id;
        }
      }
      // 配置的夹不存在了 → 回退到默认夹
      if (folderId == null) {
        final defaultFolder = await ensureDefaultFolder();
        folderId = defaultFolder.id;
        // 更新配置指向默认夹
        SpUtil.putInt(AlistConstant.favoriteDefaultFolderId, defaultFolder.id!);
      }
    } else {
      // 未启用默认夹 → 弹窗选择
      if (context == null) {
        // 无 context（原生侧调用）→ 回退到默认夹
        final defaultFolder = await ensureDefaultFolder();
        folderId = defaultFolder.id;
      } else {
        folderId = await _showFolderPickerDialog(context);
        if (folderId == null) {
          return false; // 用户取消
        }
      }
    }

    await _db.favoriteDao.insertRecord(Favorite(
      isDir: isDir,
      serverUrl: user.serverUrl,
      userId: user.username,
      remotePath: remotePath,
      name: name,
      path: path,
      size: size,
      sign: sign,
      thumb: thumb,
      modified: modified,
      provider: provider,
      createTime: now,
      folderId: folderId,
    ));

    SmartDialog.showToast('已收藏');
    return true;
  }

  /// 弹出收藏夹选择 Dialog（含"新建收藏夹"入口）
  /// 返回选中的 folderId，用户取消返回 null
  static Future<int?> _showFolderPickerDialog(BuildContext context) async {
    final user = _userController.user.value;
    final folders =
        await _db.favoriteFolderDao.getAll(user.serverUrl, user.username) ??
            [];

    // 确保至少有默认夹
    if (folders.isEmpty) {
      final defaultFolder = await ensureDefaultFolder();
      folders.add(defaultFolder);
    }

    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('选择收藏夹'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: folders.length,
                itemBuilder: (ctx, index) {
                  final folder = folders[index];
                  return ListTile(
                    leading: Icon(folder.isDefault
                        ? Icons.star_rounded
                        : Icons.folder_rounded),
                    title: Text(folder.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx, folder.id);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('取消'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final name = await _showCreateFolderDialog(ctx);
                  if (name != null && name.isNotEmpty) {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    final id = await _db.favoriteFolderDao.insertFolder(
                      FavoriteFolder(
                        serverUrl: user.serverUrl,
                        userId: user.username,
                        name: name,
                        isDefault: false,
                        sort: folders.length,
                        createTime: now,
                      ),
                    );
                    if (ctx.mounted) Navigator.pop(ctx, id);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('新建收藏夹'),
              ),
            ],
          );
        });
      },
    );
  }

  /// 新建收藏夹名称输入框
  static Future<String?> _showCreateFolderDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建收藏夹'),
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

  /// 删除收藏夹：将夹内文件移到默认夹，然后删除该夹。
  /// 默认夹不允许删除。
  static Future<bool> deleteFolder(FavoriteFolder folder) async {
    if (folder.isDefault) {
      SmartDialog.showToast('默认收藏夹不能删除');
      return false;
    }

    final user = _userController.user.value;
    final defaultFolder = await ensureDefaultFolder();

    // 将该夹内所有收藏移到默认夹
    await _db.favoriteDao.moveAllToFolder(folder.id!, defaultFolder.id!);

    // 删除收藏夹
    await _db.favoriteFolderDao.deleteFolder(folder);

    // 如果删除的是配置的默认夹，更新配置
    final configuredId = getConfiguredDefaultFolderId();
    if (configuredId == folder.id) {
      SpUtil.putInt(
          AlistConstant.favoriteDefaultFolderId, defaultFolder.id!);
    }

    SmartDialog.showToast('已删除收藏夹，内容已移至默认收藏夹');
    return true;
  }

  /// 重命名收藏夹
  static Future<void> renameFolder(FavoriteFolder folder, String newName) async {
    await _db.favoriteFolderDao.updateFolder(FavoriteFolder(
      id: folder.id,
      serverUrl: folder.serverUrl,
      userId: folder.userId,
      name: newName,
      isDefault: folder.isDefault,
      sort: folder.sort,
      createTime: folder.createTime,
    ));
  }

  /// 设为默认收藏夹（同时更新设置）
  static Future<void> setAsDefaultFolder(FavoriteFolder folder) async {
    final user = _userController.user.value;
    // 先清除所有夹的默认标记
    await _db.favoriteFolderDao.clearDefault(user.serverUrl, user.username);
    // 设置新默认夹
    await _db.favoriteFolderDao.setDefault(folder.id!);
    // 更新 SpUtil
    SpUtil.putBool(AlistConstant.favoriteUseDefaultFolder, true);
    SpUtil.putInt(AlistConstant.favoriteDefaultFolderId, folder.id!);
    SmartDialog.showToast('已设置「${folder.name}」为默认收藏夹');
  }

  /// 静默添加收藏（不弹窗，始终用默认夹）。用于批量/原生侧场景。
  static Future<bool> addFavoriteSilent({
    required bool isDir,
    required String remotePath,
    required String name,
    required String path,
    required int size,
    String? sign,
    String? thumb,
    required int modified,
    required String provider,
  }) async {
    final user = _userController.user.value;
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await _db.favoriteDao.findByPath(
        user.serverUrl, user.username, path);
    if (existing != null) return false;

    final defaultFolder = await ensureDefaultFolder();
    await _db.favoriteDao.insertRecord(Favorite(
      isDir: isDir,
      serverUrl: user.serverUrl,
      userId: user.username,
      remotePath: remotePath,
      name: name,
      path: path,
      size: size,
      sign: sign,
      thumb: thumb,
      modified: modified,
      provider: provider,
      createTime: now,
      folderId: defaultFolder.id,
    ));
    return true;
  }

  /// 移动一条收藏到其他收藏夹
  static Future<void> moveFavoriteToFolder(
      Favorite favorite, int targetFolderId) async {
    await _db.favoriteDao.moveToFolder(favorite.id!, targetFolderId);
    SmartDialog.showToast('已移动到其他收藏夹');
  }
}
