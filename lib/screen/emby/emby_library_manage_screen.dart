import 'package:alist/entity/emby_config.dart';
import 'package:alist/net/emby_api.dart';
import 'package:alist/util/emby_config_manager.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Emby 媒体库（多媒体库）配置管理页。
///
/// 支持：
/// - 从当前 Emby 主服务器一键拉取全部媒体库（GET /Users/{userId}/Views），
///   展示 Id / Name / 类型，点选即可添加（无需手工查询 ParentId）；
/// - 新增 / 编辑 / 删除 / 备注 / 选中当前参与随机播放的目标媒体库；
/// - 手动填写 ParentId 时，可从服务器反查媒体库名称并自动填入备注。
class EmbyLibraryManageScreen extends StatefulWidget {
  const EmbyLibraryManageScreen({super.key});

  @override
  State<EmbyLibraryManageScreen> createState() =>
      _EmbyLibraryManageScreenState();
}

class _EmbyLibraryManageScreenState extends State<EmbyLibraryManageScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: const Text('媒体库管理'),
        actions: [
          IconButton(
            tooltip: '从服务器拉取媒体库',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: _pickFromServer,
          ),
          IconButton(
            tooltip: '手动新增媒体库',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => showEmbyLibraryEditDialog(
              context,
              existing: null,
              onSaved: _saveLibrary,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '点击右上角下载图标，从当前 Emby 主服务器拉取全部媒体库直接点选添加；'
                '也可手动新增。点列表项选中随机播放目标。',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            Expanded(child: Obx(() {
              // 订阅配置变更
              EmbyConfigManager.revision.value;
              final libraries = EmbyConfigManager.loadLibraries();
              if (libraries.isEmpty) return _buildEmpty(scheme);
              final selectedId = EmbyConfigManager.selectedLibraryId;
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: libraries.length,
                itemBuilder: (context, i) =>
                    _buildLibraryCard(scheme, libraries[i], selectedId),
              );
            })),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_library_outlined,
              size: 64, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text('还没有配置媒体库', style: TextStyle(color: scheme.outline)),
          const SizedBox(height: 4),
          Text('点右上角下载图标从服务器拉取，或点 + 手动添加',
              style: TextStyle(fontSize: 12, color: scheme.outlineVariant)),
        ],
      ),
    );
  }

  Widget _buildLibraryCard(
      ColorScheme scheme, EmbyLibraryConfig lib, String? selectedId) {
    final isSelected = lib.id == selectedId;
    final remark = lib.remark.isNotEmpty ? lib.remark : '未命名媒体库';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: isSelected
          ? scheme.primaryContainer.withOpacity(0.45)
          : scheme.surfaceVariant.withOpacity(0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected
              ? scheme.primary.withOpacity(0.6)
              : Colors.transparent,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => EmbyConfigManager.selectLibrary(lib.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected ? scheme.primary : scheme.outlineVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            remark,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('随机播放目标',
                                style: TextStyle(
                                    fontSize: 10, color: scheme.primary)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('ParentId: ${lib.parentId}',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (v) => _onMenu(lib, v),
                itemBuilder: (_) => [
                  if (!isSelected)
                    const PopupMenuItem(
                        value: 'select', child: Text('设为随机播放目标')),
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(EmbyLibraryConfig lib, String action) async {
    switch (action) {
      case 'select':
        EmbyConfigManager.selectLibrary(lib.id);
        break;
      case 'edit':
        showEmbyLibraryEditDialog(
          context,
          existing: lib,
          onSaved: _saveLibrary,
        );
        break;
      case 'delete':
        await _confirmDelete(lib);
        break;
    }
  }

  void _saveLibrary(EmbyLibraryConfig draft) {
    EmbyConfigManager.upsertLibrary(draft);
  }

  Future<void> _confirmDelete(EmbyLibraryConfig lib) async {
    final remark = lib.remark.isNotEmpty ? lib.remark : lib.parentId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('删除媒体库'),
        content: Text('确定删除媒体库「$remark」吗？\n删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消',
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
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
    if (ok == true) {
      EmbyConfigManager.deleteLibrary(lib.id);
    }
  }

  /// 从当前选中的 Emby 主服务器拉取全部媒体库，弹出选择对话框。
  Future<void> _pickFromServer() async {
    final server = EmbyConfigManager.selectedServer;
    if (server == null) {
      _showSnack(context, '请先在「Emby 服务器管理」中配置并选中主服务器');
      return;
    }
    if (!server.isValid) {
      _showSnack(context, '当前选中的服务器配置不完整（缺少地址或密钥）');
      return;
    }

    // 加载提示框
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Text('正在获取媒体库列表...', style: TextStyle(fontSize: 15)),
            ],
          ),
        ),
      ),
    );

    List<EmbyMediaLibrary> libs;
    String? errorText;
    try {
      libs = await EmbyApi.fetchMediaLibraries(server);
    } on EmbyApiException catch (e) {
      errorText = e.message;
      libs = const [];
    } catch (e) {
      errorText = '获取媒体库失败：$e';
      libs = const [];
    }

    if (context.mounted) Navigator.of(context).pop(); // 关闭加载框
    if (errorText != null) {
      if (context.mounted) _showSnack(context, errorText);
      return;
    }
    if (libs.isEmpty) {
      if (context.mounted) {
        _showSnack(context, '服务器「${_serverLabel(server)}」下暂无可添加的媒体库');
      }
      return;
    }

    if (!context.mounted) return;
    final addedCount = await showDialog<int>(
      context: context,
      builder: (_) => _LibraryPickerDialog(server: server, libraries: libs),
    );
    if (addedCount != null && addedCount > 0 && context.mounted) {
      _showSnack(context, '已添加 $addedCount 个媒体库');
    }
  }

  String _serverLabel(EmbyServerConfig server) =>
      server.remark.isNotEmpty ? server.remark : server.serverOrigin;
}

/// 媒体库选择对话框：展示服务器拉取到的全部媒体库，点击行即可添加到本地。
class _LibraryPickerDialog extends StatefulWidget {
  final EmbyServerConfig server;
  final List<EmbyMediaLibrary> libraries;

  const _LibraryPickerDialog({
    required this.server,
    required this.libraries,
  });

  @override
  State<_LibraryPickerDialog> createState() => _LibraryPickerDialogState();
}

class _LibraryPickerDialogState extends State<_LibraryPickerDialog> {
  late List<EmbyMediaLibrary>? _libs = widget.libraries;
  bool _loading = false;
  String? _error;
  int _addedCount = 0;

  /// 已在本地配置中的 parentId（含本次会话刚添加的，去重）
  late final Set<String> _localIds = EmbyConfigManager.loadLibraries()
      .map((e) => e.parentId)
      .toSet();

  String get _serverLabel => widget.server.remark.isNotEmpty
      ? widget.server.remark
      : widget.server.serverOrigin;

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final libs = await EmbyApi.fetchMediaLibraries(widget.server);
      if (!mounted) return;
      setState(() => _libs = libs);
    } on EmbyApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '刷新失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _add(EmbyMediaLibrary lib) {
    EmbyConfigManager.upsertLibrary(EmbyLibraryConfig(
      id: EmbyConfigManager.newId(),
      remark: lib.name,
      parentId: lib.id,
    ));
    setState(() {
      _localIds.add(lib.id);
      _addedCount++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final libs = _libs ?? const <EmbyMediaLibrary>[];
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Expanded(
              child: Text('选择媒体库',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _reload,
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('来源：$_serverLabel\n点击一行即可添加，已添加的不可重复添加',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_off_outlined,
                                  size: 40, color: scheme.outlineVariant),
                              const SizedBox(height: 8),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant)),
                              ),
                              TextButton.icon(
                                onPressed: _reload,
                                icon: const Icon(Icons.refresh_rounded,
                                    size: 18),
                                label: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : libs.isEmpty
                          ? Center(
                              child: Text('服务器下没有媒体库',
                                  style: TextStyle(color: scheme.outline)))
                          : ListView.separated(
                              itemCount: libs.length,
                              separatorBuilder: (_, __) => const Divider(
                                  height: 1, indent: 56),
                              itemBuilder: (context, i) {
                                final lib = libs[i];
                                final added = _localIds.contains(lib.id);
                                final icon =
                                    collectionIcon(lib.collectionType);
                                return ListTile(
                                  dense: true,
                                  leading: Icon(icon.$1,
                                      color: scheme.primary),
                                  title: Text(lib.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      '${collectionLabel(lib.collectionType)} · Id: ${lib.id}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant)),
                                  trailing: added
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: scheme.primary
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text('已添加',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: scheme.primary)),
                                        )
                                      : const Icon(Icons.add_circle_outline,
                                          size: 22),
                                  onTap: added ? null : () => _add(lib),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_addedCount),
          style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
          child: Text(_addedCount > 0 ? '完成（+$_addedCount）' : '完成'),
        ),
      ],
    );
  }
}

/// 媒体库新增/编辑对话框：备注名 + parentId，支持从服务器反查媒体库名称。
class EmbyLibraryEditDialog extends StatefulWidget {
  final EmbyLibraryConfig? existing;
  const EmbyLibraryEditDialog({super.key, this.existing});

  @override
  State<EmbyLibraryEditDialog> createState() => _EmbyLibraryEditDialogState();
}

class _EmbyLibraryEditDialogState extends State<EmbyLibraryEditDialog> {
  late final TextEditingController _remarkCtrl;
  late final TextEditingController _parentIdCtrl;
  String? _fieldError;
  bool _queryingName = false;
  String? _queryNameOk;
  String? _queryNameErr;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _remarkCtrl = TextEditingController(text: e?.remark ?? '');
    _parentIdCtrl = TextEditingController(text: e?.parentId ?? '');
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    _parentIdCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final parentId = _parentIdCtrl.text.trim();
    if (parentId.isEmpty) {
      setState(() => _fieldError = '请填写 ParentId（媒体库 Id）');
      return;
    }
    Navigator.of(context).pop(EmbyLibraryConfig(
      id: widget.existing?.id ?? EmbyConfigManager.newId(),
      remark: _remarkCtrl.text.trim(),
      parentId: parentId,
    ));
  }

  /// 用 ParentId 请求 GET /Users/{userId}/Items/{itemId} 反查媒体库名称。
  Future<void> _queryNameFromServer() async {
    final parentId = _parentIdCtrl.text.trim();
    final server = EmbyConfigManager.selectedServer;
    if (parentId.isEmpty) {
      setState(() {
        _fieldError = '请先填写 ParentId 再查询名称';
        _queryNameOk = null;
        _queryNameErr = null;
      });
      return;
    }
    if (server == null || !server.isValid) {
      setState(() {
        _fieldError = '请先在「Emby 服务器管理」配置并选中主服务器';
        _queryNameOk = null;
        _queryNameErr = null;
      });
      return;
    }
    setState(() {
      _queryingName = true;
      _fieldError = null;
      _queryNameOk = null;
      _queryNameErr = null;
    });
    try {
      final name = await EmbyApi.fetchMediaLibraryName(server, parentId);
      if (!mounted) return;
      if (_remarkCtrl.text.trim().isEmpty) {
        _remarkCtrl.text = name;
      }
      setState(() => _queryNameOk = '媒体库名称：$name${_remarkCtrl.text == name ? '（已填入备注名）' : ''}');
    } on EmbyApiException catch (e) {
      if (!mounted) return;
      setState(() => _queryNameErr = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _queryNameErr = '查询失败：$e');
    } finally {
      if (mounted) setState(() => _queryingName = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = widget.existing == null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(isNew ? '新增媒体库' : '编辑媒体库'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _remarkCtrl,
                decoration: const InputDecoration(
                  labelText: '备注名（可选）',
                  hintText: '如：电影库、短视频',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _parentIdCtrl,
                keyboardType: TextInputType.text,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'ParentId（媒体库 Id）',
                  hintText: '如：1115732',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _queryingName ? null : _queryNameFromServer,
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.primary,
                  side: BorderSide(color: scheme.primary.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: _queryingName
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search_rounded, size: 18),
                label: Text(_queryingName ? '查询中...' : '从服务器查询名称'),
              ),
              if (_queryNameOk != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 16, color: Colors.green.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_queryNameOk!,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade600,
                              height: 1.4)),
                    ),
                  ],
                ),
              ],
              if (_queryNameErr != null) ...[
                const SizedBox(height: 8),
                Text(_queryNameErr!,
                    style: TextStyle(fontSize: 12, color: scheme.error)),
              ],
              if (_fieldError != null) ...[
                const SizedBox(height: 8),
                Text(_fieldError!,
                    style: TextStyle(fontSize: 12, color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 便捷入口：弹出媒体库编辑对话框，保存成功后执行 [onSaved]。
Future<void> showEmbyLibraryEditDialog(
  BuildContext context, {
  EmbyLibraryConfig? existing,
  required void Function(EmbyLibraryConfig draft) onSaved,
}) async {
  final draft = await showDialog<EmbyLibraryConfig>(
    context: context,
    builder: (_) => EmbyLibraryEditDialog(existing: existing),
  );
  if (draft != null) onSaved(draft);
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

/// 按 Emby CollectionType 返回 (图标, 中文标签)。
(IconData, String) collectionIcon(String? type) {
  switch (type) {
    case 'movies':
      return (Icons.movie_outlined, '电影');
    case 'tvshows':
      return (Icons.tv_outlined, '剧集');
    case 'music':
      return (Icons.music_note_outlined, '音乐');
    case 'homevideos':
      return (Icons.videocam_outlined, '家庭视频');
    case 'books':
      return (Icons.menu_book_outlined, '图书');
    case 'playlists':
      return (Icons.queue_music_outlined, '播放列表');
    case 'boxsets':
      return (Icons.collections_bookmark_outlined, '合集');
    case 'mixed':
      return (Icons.video_library_outlined, '混合');
    default:
      return (Icons.folder_outlined, '媒体库');
  }
}

String collectionLabel(String? type) => collectionIcon(type).$2;
