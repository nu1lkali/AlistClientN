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
    ),
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
