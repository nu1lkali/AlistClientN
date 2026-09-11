import 'package:alist/entity/emby_config.dart';
import 'package:alist/entity/tiktok_play_list_model.dart';
import 'package:alist/net/emby_api.dart';
import 'package:alist/util/emby_config_manager.dart';
import 'package:alist/util/named_router.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 使用当前选中的 Emby 服务器与媒体库执行一次随机抽取，成功后跳转“视界流”。
///
/// 流程（对标 cs.py）：
/// 1. 实时读取当前选中的服务器/媒体库配置（切换后无需重启 App）；
/// 2. 弹出加载提示框“正在随机抽取媒体库视频...”；
/// 3. 异步请求（内部自动处理 GET /Users 获取 userId、GET /Users/{id}/Items 随机抽取）；
/// 4. 成功关闭加载框并跳转 TikTok 播放器（视界流）；失败以 SnackBar 友好提示。
Future<void> startEmbyRandomPlay(BuildContext context) async {
  final server = EmbyConfigManager.selectedServer;
  final library = EmbyConfigManager.selectedLibrary;

  if (server == null || library == null) {
    _showSnack(context,
        '尚未配置 Emby 服务器或媒体库，请先前往「设置 → Emby 随机播放」完成配置');
    return;
  }
  if (!server.isValid) {
    _showSnack(context, '当前选中的 Emby 服务器配置不完整（缺少地址或密钥），请检查');
    return;
  }
  if (!library.isValid) {
    _showSnack(context, '当前选中的媒体库缺少 ParentId，请检查媒体库配置');
    return;
  }

  final serverName =
      server.remark.isNotEmpty ? server.remark : server.serverOrigin;
  final libraryName =
      library.remark.isNotEmpty ? library.remark : library.parentId;

  // 加载提示框
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WillPopScope(
      onWillPop: () async => false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 18),
            const Text('正在随机抽取媒体库视频...',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text('$serverName · $libraryName',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      ),
    ),
  );

  List<TikTokVideoItem>? videos;
  String? errorText;
  try {
    videos = await EmbyApi.fetchRandomVideos(
      server: server,
      library: library,
    );
  } on EmbyApiException catch (e) {
    errorText = e.message;
  } catch (e) {
    errorText = '随机播放失败：$e';
  }

  // 关闭加载框
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  if (errorText != null) {
    if (context.mounted) _showSnack(context, errorText);
    return;
  }

  final list = videos ?? const <TikTokVideoItem>[];
  if (list.isEmpty) {
    if (context.mounted) _showSnack(context, '未抽取到可播放的视频，请稍后重试');
    return;
  }

  // 无缝传递并跳转“视界流”（类抖音上下滑动播放器）
  Get.toNamed(
    NamedRouter.tiktokPlayer,
    arguments: TikTokPlayListModel(
      videos: list,
      initialIndex: 0,
      recordHistory: false,
      fromEmby: true,
    ),
  );
}

/// 首页随机播放按钮「长按」：弹窗选择一个媒体库，
/// 保存后持久化为当前随机播放目标（设置页“媒体库管理”同步高亮），
/// 并立即按所选媒体库执行一次随机播放。
Future<void> startEmbyRandomPlayWithLibraryPick(BuildContext context) async {
  final server = EmbyConfigManager.selectedServer;
  if (server == null || !server.isValid) {
    _showSnack(context,
        '请先在「设置 → Emby 随机播放 → 服务器管理」配置并选中主服务器');
    return;
  }

  // 只列当前主服务器下的媒体库（媒体库与服务器绑定）
  final libraries = EmbyConfigManager.librariesOf(server.id);
  if (libraries.isEmpty) {
    _showSnack(context,
        '当前服务器还没有媒体库，请到「媒体库管理」用下载图标从服务器拉取');
    return;
  }

  // 默认选中当前配置的媒体库，其次第一个
  String currentId = EmbyConfigManager.selectedLibraryId ?? '';
  if (!libraries.any((e) => e.id == currentId)) {
    currentId = libraries.first.id;
  }

  final picked = await showDialog<EmbyLibraryConfig>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('选择媒体库'),
          content: SizedBox(
            width: double.maxFinite,
            child: libraries.length > 6
                ? ListView.builder(
                    shrinkWrap: true,
                    itemCount: libraries.length,
                    itemBuilder: (c, i) =>
                        _libraryRadio(libraries[i], () => currentId,
                            (v) => setDialogState(() => currentId = v!)),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final lib in libraries)
                        _libraryRadio(lib, () => currentId,
                            (v) => setDialogState(() => currentId = v!)),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  Text('取消', style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            FilledButton(
              onPressed: () {
                final idx = libraries.indexWhere((e) => e.id == currentId);
                if (idx >= 0) Navigator.of(ctx).pop(libraries[idx]);
              },
              style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              child: const Text('保存并播放'),
            ),
          ],
        ),
      );
    },
  );

  if (picked == null) return;
  if (!context.mounted) return;

  // 持久化选中目标：设置页“媒体库管理”列表与随机播放目标同步更新
  EmbyConfigManager.selectLibrary(picked.id);
  // 按刚选中的媒体库立即随机播放
  await startEmbyRandomPlay(context);
}

/// 首页「随机播放收藏」：从 Emby 收藏中随机抽取一批视频进入“视界流”。
///
/// GET /Users/{userId}/Items?Filters=IsFavorite&SortBy=Random&Recursive=true
///   &IncludeItemTypes=Video,Movie&Limit={limit}
/// 收藏为空或请求失败时以 SnackBar 友好提示。
Future<void> startEmbyFavoriteRandomPlay(BuildContext context) async {
  final server = EmbyConfigManager.selectedServer;
  if (server == null || !server.isValid) {
    _showSnack(context,
        '请先在「设置 → Emby 随机播放 → 服务器管理」配置并选中主服务器');
    return;
  }

  // 加载提示框
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WillPopScope(
      onWillPop: () async => false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 18),
            const Text('正在随机抽取收藏视频...',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(
                server.remark.isNotEmpty ? server.remark : server.serverOrigin,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      ),
    ),
  );

  List<TikTokVideoItem>? videos;
  String? errorText;
  try {
    videos = await EmbyApi.fetchFavoriteVideos(server: server);
  } on EmbyApiException catch (e) {
    errorText = e.message;
  } catch (e) {
    errorText = '随机播放收藏失败：$e';
  }

  // 关闭加载框
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  if (errorText != null) {
    if (context.mounted) _showSnack(context, errorText);
    return;
  }

  final list = videos ?? const <TikTokVideoItem>[];
  if (list.isEmpty) {
    if (context.mounted) {
      _showSnack(context, '收藏列表为空，请先在 Emby 中收藏一些视频');
    }
    return;
  }

  Get.toNamed(
    NamedRouter.tiktokPlayer,
    arguments: TikTokPlayListModel(
      videos: list,
      initialIndex: 0,
      recordHistory: false,
      fromEmby: true,
    ),
  );
}

Widget _libraryRadio(
  EmbyLibraryConfig lib,
  String Function() groupValue,
  ValueChanged<String?> onChanged,
) {
  final remark = lib.remark.isNotEmpty ? lib.remark : '未命名媒体库';
  return RadioListTile<String>(
    dense: true,
    value: lib.id,
    groupValue: groupValue(),
    title: Text(remark, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('ParentId: ${lib.parentId}',
        maxLines: 1, overflow: TextOverflow.ellipsis),
    onChanged: onChanged,
  );
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
