import 'package:alist/util/search_filter_helper.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class SearchFilterSettingsScreen extends StatefulWidget {
  const SearchFilterSettingsScreen({super.key});

  @override
  State<SearchFilterSettingsScreen> createState() =>
      _SearchFilterSettingsScreenState();
}

class _SearchFilterSettingsScreenState
    extends State<SearchFilterSettingsScreen> {
  List<SearchFilterRule> _rules = [];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  void _loadRules() {
    setState(() {
      _rules = SearchFilterHelper.getAllRules();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlistScaffold(
      appbarTitle: const Text('搜索过滤'),
      appbarActions: [
        IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: '添加规则',
          onPressed: () => _showAddEditDialog(context, null),
        ),
      ],
      body: _rules.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.filter_list_off_rounded,
                      size: 72, color: scheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    '暂无过滤规则',
                    style: TextStyle(fontSize: 16, color: scheme.outline),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击右上角 + 添加过滤路径',
                    style: TextStyle(fontSize: 13, color: scheme.outlineVariant),
                  ),
                  const SizedBox(height: 16),
                  _buildHelpCard(context),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _buildHelpCard(context),
                const SizedBox(height: 4),
                for (int i = 0; i < _rules.length; i++)
                  _buildRuleItem(context, i, _rules[i]),
              ],
            ),
    );
  }

  Widget _buildHelpCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: scheme.surfaceVariant.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '设置过滤路径后，该路径及其子文件夹中的文件将不会出现在文件列表和搜索结果中。\n\n'
                '例如设置 /nas/xxx/abcd，则 /nas/xxx/abcd 及其下方所有文件都会被过滤，但 /nas/xxx 不受影响。',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleItem(BuildContext context, int index, SearchFilterRule rule) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey('${rule.path}_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('确认删除'),
            content: Text('确定要删除过滤规则\n"${rule.path}"\n吗？'),
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
      },
      onDismissed: (_) async {
        await SearchFilterHelper.deleteRule(index);
        _loadRules();
        SmartDialog.showToast('已删除');
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: isDark ? 0 : 1,
        color: isDark
            ? scheme.surfaceVariant.withOpacity(0.3)
            : scheme.surface,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primaryContainer.withOpacity(0.8),
                  scheme.primaryContainer.withOpacity(0.5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.folder_off_rounded,
              size: 22,
              color: isDark
                  ? Colors.white.withOpacity(0.9)
                  : scheme.primary,
            ),
          ),
          title: Text(
            rule.path,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: rule.remark.isNotEmpty
              ? Text(rule.remark,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: '过滤搜索结果',
                    child: SizedBox(
                      width: 36, height: 24,
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: Switch(
                          value: rule.filterInSearch,
                          onChanged: (value) async {
                            rule.filterInSearch = value;
                            await SearchFilterHelper.updateRule(index, rule);
                            _loadRules();
                          },
                        ),
                      ),
                    ),
                  ),
                  Text('搜索', style: TextStyle(fontSize: 9, color: scheme.outline)),
                ],
              ),
              const SizedBox(width: 2),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: '过滤文件列表',
                    child: SizedBox(
                      width: 36, height: 24,
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: Switch(
                          value: rule.filterInFileList,
                          onChanged: (value) async {
                            rule.filterInFileList = value;
                            await SearchFilterHelper.updateRule(index, rule);
                            _loadRules();
                          },
                        ),
                      ),
                    ),
                  ),
                  Text('列表', style: TextStyle(fontSize: 9, color: scheme.outline)),
                ],
              ),
              const SizedBox(width: 2),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    color: scheme.outlineVariant, size: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (action) {
                  if (action == 'edit') {
                    _showAddEditDialog(context, index);
                  } else if (action == 'delete') {
                    _confirmDelete(index, rule);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(int index, SearchFilterRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除'),
        content: Text('确定要删除过滤规则\n"${rule.path}"\n吗？'),
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
    if (confirmed == true) {
      await SearchFilterHelper.deleteRule(index);
      _loadRules();
      SmartDialog.showToast('已删除');
    }
  }

  void _showAddEditDialog(BuildContext context, int? editIndex) {
    final isEdit = editIndex != null;
    final existingRule =
        isEdit ? _rules[editIndex!] : null;

    final pathController =
        TextEditingController(text: existingRule?.path ?? '');
    final remarkController =
        TextEditingController(text: existingRule?.remark ?? '');

    showDialog(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isEdit ? '编辑过滤规则' : '添加过滤规则'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pathController,
                autofocus: !isEdit,
                decoration: InputDecoration(
                  labelText: '过滤路径',
                  hintText: '/nas/xxx/abcd',
                  prefixIcon: const Icon(Icons.folder_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarkController,
                decoration: InputDecoration(
                  labelText: '备注（可选）',
                  hintText: '例如：工作文件',
                  prefixIcon: const Icon(Icons.note_alt_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: scheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '该路径及其子目录下的所有文件都将被过滤',
                        style: TextStyle(
                            fontSize: 12, color: scheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final pathText = pathController.text.trim();
                if (pathText.isEmpty) {
                  SmartDialog.showToast('请输入过滤路径');
                  return;
                }

                // 确保路径以 / 开头
                var normalizedPath = pathText;
                if (!normalizedPath.startsWith('/')) {
                  normalizedPath = '/$normalizedPath';
                }
                // 去除末尾 /
                while (normalizedPath.endsWith('/') &&
                    normalizedPath.length > 1) {
                  normalizedPath = normalizedPath.substring(
                      0, normalizedPath.length - 1);
                }

                final newRule = SearchFilterRule(
                  path: normalizedPath,
                  remark: remarkController.text.trim(),
                  enabled: existingRule?.enabled ?? true,
                );

                if (isEdit) {
                  await SearchFilterHelper.updateRule(editIndex!, newRule);
                  SmartDialog.showToast('已更新');
                } else {
                  // 检查是否重复
                  final existing =
                      SearchFilterHelper.getAllRules();
                  if (existing
                      .any((r) => r.path == normalizedPath)) {
                    SmartDialog.showToast('该路径已存在');
                    return;
                  }
                  await SearchFilterHelper.addRule(newRule);
                  SmartDialog.showToast('已添加');
                }

                if (ctx.mounted) Navigator.pop(ctx);
                _loadRules();
              },
              child: Text(isEdit ? '保存' : '添加'),
            ),
          ],
        );
      },
    );
  }
}