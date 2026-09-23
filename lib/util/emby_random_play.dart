import 'package:alist/entity/emby_config.dart';
import 'package:alist/entity/tiktok_play_list_model.dart';
import 'package:alist/net/emby_api.dart';
import 'package:alist/util/emby_config_manager.dart';
import 'package:alist/util/named_router.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 使用当前选中的 Emby 服务器与媒体库执行一次随机抽取，成功后跳转“视界流”。
///
/// 流程 ：
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

  final isAllLibraries = library.isAllLibraries;

  // 「全部媒体库」虚拟项：取参与抽取的真实媒体库（已排除用户取消勾选的）
  final allTargets = isAllLibraries
      ? EmbyConfigManager.allLibrariesTargetsOf(server.id)
      : const <EmbyLibraryConfig>[];
  if (isAllLibraries && allTargets.isEmpty) {
    final total =
        EmbyConfigManager.librariesOf(server.id).where((e) => e.isValid).length;
    _showSnack(
        context,
        total > 0
            ? '已排除全部媒体库，请在「选择媒体库」中至少保留一个参与'
            : '当前服务器还没有可用的媒体库，请到「媒体库管理」添加');
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
            Text(
                isAllLibraries
                    ? '正在随机抽取全部媒体库视频...'
                    : '正在随机抽取媒体库视频...',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(
                isAllLibraries
                    ? '$serverName · 全部媒体库（${allTargets.length} 个库）'
                    : '$serverName · $libraryName',
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
    videos = isAllLibraries
        ? await EmbyApi.fetchRandomVideosFromAllLibraries(
            server: server,
            libraries: allTargets,
          )
        : await EmbyApi.fetchRandomVideos(
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

  // 默认选中当前配置的媒体库（含「全部媒体库」虚拟项），其次第一个
  final candidateIds = <String>{
    for (final lib in libraries) lib.id,
    EmbyLibraryConfig.allLibrariesId,
  };
  String currentId = EmbyConfigManager.selectedLibraryId ?? '';
  if (!candidateIds.contains(currentId)) {
    currentId = libraries.first.id;
  }

  // 记住一个真实媒体库，供「全部媒体库」模式一键切回单选使用
  String lastSingleId =
      EmbyConfigManager.selectedLibraryId ?? currentId;
  if (lastSingleId == EmbyLibraryConfig.allLibrariesId ||
      !candidateIds.contains(lastSingleId)) {
    lastSingleId = libraries.first.id;
  }

  // 被排除在「全部媒体库」之外的媒体库（本地暂存，点“保存并播放”后落盘）
  final excludedIds = <String>{
    for (final lib in libraries)
      if (lib.excludeFromAll) lib.id,
  };

  final picked = await showDialog<EmbyLibraryConfig>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      // 列表滚动控制器放在 StatefulBuilder 之外：局部 setState 不会重建它，
      // 滚动位置在切换模式时也能保留
      final scrollController = ScrollController();
      return StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          // 弹窗整体收窄一圈（左右各 30），但内部文字维持 17/15：
          // 靠压缩内边距与控件占位来保证正文宽度，而不是靠缩小字号
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
          contentPadding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          title: Row(
            children: [
              // 标题图标：`video_library` 是 Material 里「影音库」的标准符号
              // （轮播出一格胶片 + 书本轮廓），比 video_library_outlined 更有实体感，
              // 用主色 + 浅色底衬出一个圆角chip，跟右边的齿轮形成「标题 / 操作」分区。
              Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.video_library_rounded,
                    size: 18, color: scheme.onPrimaryContainer),
              ),
              const Expanded(
                child: Text('选择媒体库',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Emby 配置',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 34, height: 34),
                icon: Icon(Icons.settings_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
                // 先关掉本弹窗再跳转，返回时不会残留遮罩层
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Get.toNamed(NamedRouter.embyServerManage);
                },
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListTileTheme.merge(
              horizontalTitleGap: 8,
              minLeadingWidth: 32,
              minVerticalPadding: 6,
              visualDensity: const VisualDensity(horizontal: -2),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 上半区：媒体库列表，限高后在弹窗内部滚动
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: _libraryListMaxHeight(ctx)),
                    child: _buildLibraryPicker(
                      libraries,
                      () => currentId,
                      (v) => setDialogState(() {
                        currentId = v!;
                        if (currentId != EmbyLibraryConfig.allLibrariesId) {
                          lastSingleId = currentId;
                        }
                      }),
                      excludedIds,
                      (id, excluded) => setDialogState(() => excluded
                          ? excludedIds.add(id)
                          : excludedIds.remove(id)),
                      scrollController,
                    ),
                  ),
                  // 下半区：「全部媒体库」开关锁在这里，不随列表滚动，
                  // 滚到任何位置都能直接切换模式
                  const Divider(height: 1),
                  _allLibrariesCheckbox(
                    () => currentId,
                    (v) => setDialogState(() {
                      currentId = v!;
                      if (currentId != EmbyLibraryConfig.allLibrariesId) {
                        lastSingleId = currentId;
                      }
                    }),
                    // 取消勾选「全部媒体库」时回退到的单库
                    lastSingleId,
                    total: libraries.length,
                    participating: libraries.length - excludedIds.length,
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          actions: [
            // 两个按钮共用同一份基准样式（圆角沿用全局 theme 的 12dp），
            // 只在填充形态与配色上区分层级：实心 > 描边；
            // 用 Expanded 等分宽度，避免出现高矮/宽窄不一致
            SizedBox(
              width: double.maxFinite,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: _dialogButtonBase().copyWith(
                        foregroundColor:
                            MaterialStatePropertyAll(scheme.onSurfaceVariant),
                        side: MaterialStatePropertyAll(
                            BorderSide(color: scheme.outlineVariant)),
                      ),
                      child: const Text('取消',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        // 「全部媒体库」至少要有一个库参与，否则没有可抽取的内容
                        if (currentId == EmbyLibraryConfig.allLibrariesId) {
                          final participating =
                              libraries.length - excludedIds.length;
                          if (participating <= 0) {
                            _showSnack(ctx, '「全部媒体库」至少需要保留 1 个媒体库参与');
                            return;
                          }
                          for (final lib in libraries) {
                            final excluded = excludedIds.contains(lib.id);
                            if (lib.excludeFromAll != excluded) {
                              EmbyConfigManager.setLibraryExcludedFromAll(
                                  lib.id, excluded);
                            }
                          }
                          Navigator.of(ctx)
                              .pop(EmbyLibraryConfig.allLibraries(server.id));
                          return;
                        }
                        final idx =
                            libraries.indexWhere((e) => e.id == currentId);
                        if (idx >= 0) Navigator.of(ctx).pop(libraries[idx]);
                      },
                      style: _dialogButtonBase().copyWith(
                        // 浅蓝实心 + 深蓝文字，既有强调色又不刺眼
                        backgroundColor: const MaterialStatePropertyAll(
                            Color(0xFFBBDEFB)),
                        foregroundColor: const MaterialStatePropertyAll(
                            Color(0xFF0D47A1)),
                      ),
                      child: const Text('保存并播放',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
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

/// 弹窗底部操作按钮的统一基准样式。
///
/// 三个按钮（保存并播放 / 单库模式 / 取消）共用同一份形状、高度与字号，
/// 各自只 `copyWith` 覆盖配色，避免不同 `styleFrom` 参数造成高矮宽窄不齐。
/// 圆角 12dp 与全局 `main.dart` 里的 filledButtonTheme 保持一致。
ButtonStyle _dialogButtonBase() {
  return ButtonStyle(
    shape: MaterialStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    padding: const MaterialStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    ),
    // 宽度由外层 Expanded 决定，这里只锁定高度
    minimumSize: const MaterialStatePropertyAll(Size(0, 44)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const MaterialStatePropertyAll(
      TextStyle(fontSize: _kActionTextSize, fontWeight: FontWeight.w600),
    ),
  );
}

/// 弹窗内文字统一比 M3 默认大半档，比之前收小一档：
/// 列表行是滚动区里密度最高的内容，17/15 在窄弹窗里偏满，
/// 收到 16/13.5 后一屏能多放一行，标题与 ParentId 仍清晰。
const double _kItemTitleSize = 16;
const double _kItemSubtitleSize = 13.5;
const double _kActionTextSize = 15;

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

/// 媒体库列表最大高度：媒体库多时列表内部滚动，弹窗不会被撑到顶满屏幕。
double _libraryListMaxHeight(BuildContext context) {
  final h = MediaQuery.of(context).size.height * 0.4;
  return h > 300 ? 300 : (h < 160 ? 160 : h);
}

/// 媒体库选择列表：只负责上方**可滚动**的真实媒体库行；
/// 「全部媒体库」开关由调用方锁在列表下方，不参与滚动。
///
/// 选中「全部媒体库」时，每个真实媒体库只留左侧参与勾选框，用于指定
/// 该库**是否参与**全库随机（取消勾选即从全库抽取中排除）；
/// 单库模式下则是左侧单选框。
Widget _buildLibraryPicker(
  List<EmbyLibraryConfig> libraries,
  String Function() groupValue,
  ValueChanged<String?> onChanged,
  Set<String> excludedIds,
  void Function(String id, bool excluded) onIncludeChanged,
  ScrollController scrollController,
) {
  // 「全部媒体库」模式下不显示单选框：每行只留左侧参与勾选框，
  // 正文拿到的宽度更大，标题/ParentId 都不会被截断
  final pickIncludes = groupValue() == EmbyLibraryConfig.allLibrariesId;

  Widget row(EmbyLibraryConfig lib) => pickIncludes
      ? _libraryIncludeTile(
          lib,
          included: !excludedIds.contains(lib.id),
          onChanged: (v) => onIncludeChanged(lib.id, !(v ?? true)),
        )
      : _libraryRadio(lib, groupValue, onChanged);

  // 外层 ConstrainedBox 限高后内容超出即在弹窗内滚动；
  // 控制器显式传给 Scrollbar，保证滚动条能拿到滚动位置
  return Scrollbar(
    controller: scrollController,
    child: ListView.builder(
      controller: scrollController,
      shrinkWrap: true,
      itemCount: libraries.length,
      itemBuilder: (c, i) => row(libraries[i]),
    ),
  );
}

/// 「全部媒体库」开关：勾上进入排除模式（各库行变成参与勾选框），
/// 取消勾选即回到单库模式（各库行变回单选框，选中 [fallbackId]）。
///
/// [total] 媒体库总数，[participating] 实际参与数（可能被用户手动排除一部分）。
Widget _allLibrariesCheckbox(
  String Function() groupValue,
  ValueChanged<String?> onChanged,
  String fallbackId, {
  required int total,
  required int participating,
}) {
  final excludedCount = total - participating;
  return CheckboxListTile(
    value: groupValue() == EmbyLibraryConfig.allLibrariesId,
    controlAffinity: ListTileControlAffinity.leading,
    title: const Text(EmbyLibraryConfig.allLibrariesRemark,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(
        excludedCount > 0
            ? '共 $total 个库，参与 $participating 个，已排除 $excludedCount 个'
            : '勾选后从全部 $total 个媒体库各抽取一批',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: _kItemSubtitleSize)),
    onChanged: (v) => onChanged(
        (v ?? false) ? EmbyLibraryConfig.allLibrariesId : fallbackId),
  );
}

/// 「全部媒体库」模式下的媒体库行：只有左侧参与勾选框，不再叠加单选框。
///
/// 行内的点击区域整体用于切换“是否参与”，右侧不再占用 radio 的宽度，
/// 标题与 ParentId 因此能拿到接近满宽的可用宽度。
Widget _libraryIncludeTile(
  EmbyLibraryConfig lib, {
  required bool included,
  required ValueChanged<bool?> onChanged,
}) {
  final remark = lib.remark.isNotEmpty ? lib.remark : '未命名媒体库';
  return CheckboxListTile(
    value: included,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(remark,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: _kItemTitleSize)),
    subtitle: Text('ParentId: ${lib.parentId}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: _kItemSubtitleSize)),
    onChanged: onChanged,
  );
}

Widget _libraryRadio(
  EmbyLibraryConfig lib,
  String Function() groupValue,
  ValueChanged<String?> onChanged,
) {
  final remark = lib.remark.isNotEmpty ? lib.remark : '未命名媒体库';
  return RadioListTile<String>(
    value: lib.id,
    groupValue: groupValue(),
    // 与「全部媒体库」开关、全库模式下的参与勾选框统一靠左，
    // 切换模式时控件不会左右跳
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(remark,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: _kItemTitleSize)),
    subtitle: Text('ParentId: ${lib.parentId}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: _kItemSubtitleSize)),
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
