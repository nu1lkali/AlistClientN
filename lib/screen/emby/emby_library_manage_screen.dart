import 'package:alist/entity/emby_config.dart';
import 'package:alist/util/emby_config_manager.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Emby 媒体库（多媒体库）配置管理页。
///
/// 支持：新增 / 编辑 / 删除 / 备注 / 选中当前参与随机播放的目标媒体库。
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
            tooltip: '新增媒体库',
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
                '选中一个媒体库作为随机播放的目标作用域；'
                'ParentId 可在 Emby Web 点击该媒体库后从地址栏中获取。',
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
          Text('点击右上角 + 添加媒体库（如：电影库、短视频）',
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
}

/// 媒体库新增/编辑对话框：备注名 + parentId。
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNew = widget.existing == null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(isNew ? '新增媒体库' : '编辑媒体库'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                helperText: 'Emby Web 点击该媒体库后，从地址栏 details?id= 中获取',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_fieldError != null) ...[
              const SizedBox(height: 8),
              Text(_fieldError!,
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ],
          ],
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
