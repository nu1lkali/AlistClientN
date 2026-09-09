import 'package:alist/entity/emby_config.dart';
import 'package:alist/net/emby_api.dart';
import 'package:alist/screen/emby/emby_server_edit_dialog.dart';
import 'package:alist/util/emby_config_manager.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Emby 服务器配置管理页。
///
/// 支持：新增 / 编辑 / 删除 / 备注 / 选中当前主服务器 / 单项测试连接。
class EmbyServerManageScreen extends StatefulWidget {
  const EmbyServerManageScreen({super.key});

  @override
  State<EmbyServerManageScreen> createState() => _EmbyServerManageScreenState();
}

class _EmbyServerManageScreenState extends State<EmbyServerManageScreen> {
  String? _testingId; // 正在测试连接的服务器 id

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: const Text('Emby 服务器管理'),
        actions: [
          IconButton(
            tooltip: '新增服务器',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => showEmbyServerEditDialog(
              context,
              existing: null,
              onSaved: (draft) => _saveServer(null, draft),
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
                '支持配置多个 Emby 服务器，选中一个作为当前生效的主服务器；'
                '随机播放时将实时读取其协议/地址/密钥发起请求。',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            Expanded(child: Obx(() {
              // 订阅配置变更（新增/编辑/删除/选中都会自增 revision）
              EmbyConfigManager.revision.value;
              final servers = EmbyConfigManager.loadServers();
              if (servers.isEmpty) return _buildEmpty(scheme);
              final selectedId = EmbyConfigManager.selectedServerId;
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: servers.length,
                itemBuilder: (context, i) =>
                    _buildServerCard(scheme, servers[i], selectedId),
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
          Icon(Icons.dns_outlined, size: 64, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text('还没有配置服务器', style: TextStyle(color: scheme.outline)),
          const SizedBox(height: 4),
          Text('点击右上角 + 新增一个 Emby 服务器',
              style: TextStyle(fontSize: 12, color: scheme.outlineVariant)),
        ],
      ),
    );
  }

  Widget _buildServerCard(
      ColorScheme scheme, EmbyServerConfig s, String? selectedId) {
    final isSelected = s.id == selectedId;
    final remark = s.remark.isNotEmpty ? s.remark : '未命名服务器';
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
        onTap: () {
          EmbyConfigManager.selectServer(s.id);
        },
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
                            child: Text('主服务器',
                                style: TextStyle(
                                    fontSize: 10, color: scheme.primary)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${s.serverOrigin}\nAPI Key: ${_maskKey(s.apiKey)}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (_testingId == s.id)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  onSelected: (v) => _onMenu(s, v),
                  itemBuilder: (_) => [
                    if (!isSelected)
                      const PopupMenuItem(
                          value: 'select', child: Text('设为主服务器')),
                    const PopupMenuItem(
                        value: 'test', child: Text('测试连接')),
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    const PopupMenuItem(
                        value: 'delete', child: Text('删除')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(EmbyServerConfig s, String action) async {
    switch (action) {
      case 'select':
        EmbyConfigManager.selectServer(s.id);
        break;
      case 'test':
        await _testServer(s);
        break;
      case 'edit':
        showEmbyServerEditDialog(
          context,
          existing: s,
          onSaved: (draft) => _saveServer(s, draft),
        );
        break;
      case 'delete':
        await _confirmDelete(s);
        break;
    }
  }

  void _saveServer(EmbyServerConfig? existing, EmbyServerConfig draft) {
    // 修改了地址或密钥后，缓存的 userId 可能失效，清除以便下次重新获取
    if (existing != null &&
        (existing.baseUrl != draft.baseUrl || existing.apiKey != draft.apiKey)) {
      draft = draft.copyWith(clearUserId: true);
    }
    EmbyConfigManager.upsertServer(draft);
  }

  Future<void> _testServer(EmbyServerConfig s) async {
    setState(() => _testingId = s.id);
    try {
      final msg = await EmbyApi.testConnection(s);
      if (!mounted) return;
      _showResultDialog(true, msg);
    } on EmbyApiException catch (e) {
      if (!mounted) return;
      _showResultDialog(false, e.message);
    } catch (e) {
      if (!mounted) return;
      _showResultDialog(false, '测试连接失败：$e');
    } finally {
      if (mounted) setState(() => _testingId = null);
    }
  }

  void _showResultDialog(bool ok, String message) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(
          ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: ok ? Colors.green.shade600 : scheme.error,
          size: 36,
        ),
        title: Text(ok ? '连接成功' : '连接失败'),
        content: SelectableText(message,
            style: const TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(EmbyServerConfig s) async {
    final remark = s.remark.isNotEmpty ? s.remark : s.serverOrigin;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('删除服务器'),
        content: Text('确定删除服务器「$remark」吗？\n删除后不可恢复。'),
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
      EmbyConfigManager.deleteServer(s.id);
    }
  }

  String _maskKey(String key) {
    if (key.isEmpty) return '(未设置)';
    if (key.length <= 4) return '••••••';
    return '••••••${key.substring(key.length - 4)}';
  }
}
