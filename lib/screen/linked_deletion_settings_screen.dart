import 'package:alist/util/constant.dart';
import 'package:alist/util/smart_strm_webhook.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// 联动删除设置页面
///
/// 配置 SmartStrm 联动删除功能：启用后，当在 AList 中删除 .strm 文件时，
/// 自动向 SmartStrm 后端发送 Webhook，通知同步删除网盘中的真实媒体文件。
class LinkedDeletionSettingsScreen extends StatefulWidget {
  const LinkedDeletionSettingsScreen({super.key});

  @override
  State<LinkedDeletionSettingsScreen> createState() =>
      _LinkedDeletionSettingsScreenState();
}

class _LinkedDeletionSettingsScreenState
    extends State<LinkedDeletionSettingsScreen> {
  late bool _enabled;
  late bool _deleteThumbEnabled;
  late TextEditingController _webhookUrlController;
  late TextEditingController _strmDirController;

  @override
  void initState() {
    super.initState();
    _enabled = SpUtil.getBool(
          AlistConstant.linkedDeletionEnabled,
          defValue: false,
        ) ??
        false;
    _deleteThumbEnabled = SpUtil.getBool(
          AlistConstant.linkedDeletionDeleteThumb,
          defValue: false,
        ) ??
        false;
    _webhookUrlController = TextEditingController(
      text: SpUtil.getString(AlistConstant.linkedDeletionWebhookUrl) ?? '',
    );
    _strmDirController = TextEditingController(
      text: SpUtil.getString(AlistConstant.linkedDeletionStrmDir) ?? '',
    );
  }

  @override
  void dispose() {
    _webhookUrlController.dispose();
    _strmDirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlistScaffold(
      appbarTitle: const Text('联动删除'),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // ===== 高风险警告横幅 =====
          _buildWarningBanner(scheme),

          const SizedBox(height: 12),

          // ===== 功能总开关 =====
          _buildSectionHeader('功能开关', Icons.toggle_on_rounded, scheme),
          _SettingsCard(
            children: [
              SwitchListTile(
                title: const Text(
                  '启用联动删除 Webhook',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                subtitle: const Text(
                  '删除 .strm 文件时通知 SmartStrm 同步删除网盘文件',
                  style: TextStyle(fontSize: 12),
                ),
                value: _enabled,
                onChanged: (v) {
                  setState(() => _enabled = v);
                  SpUtil.putBool(AlistConstant.linkedDeletionEnabled, v);
                },
                secondary: _leadingIcon(scheme, isDark, Icons.delete_forever_rounded),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ===== 配置项 =====
          _buildSectionHeader('接口配置', Icons.settings_ethernet_rounded, scheme),
          _SettingsCard(
            children: [
              // Webhook URL 输入框
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    _leadingIcon(scheme, isDark, Icons.link_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Webhook 接口地址',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _enabled ? null : scheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _webhookUrlController,
                  enabled: _enabled,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'http://192.168.2.124:8024/webhook/xxxxxx',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: scheme.outline.withOpacity(0.6),
                    ),
                    suffixIcon: _webhookUrlController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 20, color: scheme.outline),
                            onPressed: () {
                              _webhookUrlController.clear();
                              SpUtil.putString(
                                AlistConstant.linkedDeletionWebhookUrl,
                                '',
                              );
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    SpUtil.putString(
                      AlistConstant.linkedDeletionWebhookUrl,
                      v.trim(),
                    );
                    setState(() {});
                  },
                ),
              ),

              const Divider(height: 1, indent: 68, endIndent: 16),

              // strm 目录输入框
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    _leadingIcon(scheme, isDark, Icons.folder_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '群晖 strm 目录',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _enabled ? null : scheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'NAS 上 SmartStrm 的 strm 文件存放根目录（绝对路径）',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _strmDirController,
                  enabled: _enabled,
                  decoration: InputDecoration(
                    hintText: '/volume1/docker/smartstrm/strm',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: scheme.outline.withOpacity(0.6),
                    ),
                    suffixIcon: _strmDirController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 20, color: scheme.outline),
                            onPressed: () {
                              _strmDirController.clear();
                              SpUtil.putString(
                                AlistConstant.linkedDeletionStrmDir,
                                '',
                              );
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    SpUtil.putString(
                      AlistConstant.linkedDeletionStrmDir,
                      v.trim(),
                    );
                    setState(() {});
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ===== 帧截图联动删除 =====
          _buildSectionHeader('附加选项', Icons.image_rounded, scheme),
          _SettingsCard(
            children: [
              SwitchListTile(
                title: const Text('同时删除帧截图文件',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                subtitle: const Text(
                    '删除 .strm 时同步删除同名的 .jpg / .png 刮削帧截图文件'),
                value: _deleteThumbEnabled,
                onChanged: (v) {
                  setState(() => _deleteThumbEnabled = v);
                  SpUtil.putBool(AlistConstant.linkedDeletionDeleteThumb, v);
                },
                secondary: _leadingIcon(scheme, isDark, Icons.image_not_supported_rounded),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ===== 测试 Webhook =====
          _buildSectionHeader('连通性测试', Icons.wifi_tethering_rounded, scheme),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '点击下方按钮发送测试通知，验证接口连通性。',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('发送测试 Webhook'),
                        onPressed: () => _onTestWebhook(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ===== 发送日志 =====
          _buildSectionHeader('发送日志', Icons.history_rounded, scheme),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '记录每次请求的 payload 与响应，便于排查。',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.visibility_rounded, size: 18),
                            label: const Text('查看日志'),
                            onPressed: () => _onViewLog(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('清空'),
                          onPressed: () => _onClearLog(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ===== 路径转换说明 =====
          _buildSectionHeader('路径转换说明', Icons.info_outline_rounded, scheme),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPathExample(
                      scheme,
                      'AList 路径（兼容格式1）',
                      'NAS/volume1/docker/smartstrm/strm/115/测试/(1集)_(1).(mp4).strm',
                      isDark,
                    ),
                    const SizedBox(height: 8),
                    _buildPathExample(
                      scheme,
                      'AList 路径（兼容格式2）',
                      '/volume1/docker/smartstrm/strm/115/测试/(1集)_(1).(mp4).strm',
                      isDark,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Icon(Icons.arrow_downward_rounded,
                          color: scheme.primary, size: 24),
                    ),
                    const SizedBox(height: 12),
                    _buildPathExample(
                      scheme,
                      '转换后的 Webhook Path',
                      '/volume1/docker/smartstrm/strm/115/测试/(1集)_(1).(mp4).strm',
                      isDark,
                      highlight: true,
                    ),
                    const SizedBox(height: 8),
                    _buildPathExample(
                      scheme,
                      'Webhook Item.Name',
                      '(1集)_(1).(mp4)',
                      isDark,
                      highlight: true,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ===== UI 测试 =====
          _buildSectionHeader('UI 测试（模拟数据）', Icons.bug_report_rounded, scheme),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使用模拟数据测试警告对话框 UI，不会发起真实请求。',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.warning_amber_rounded, size: 18),
                            label: const Text('单个路径异常'),
                            onPressed: () => SmartStrmWebhook.showTestSingleMismatch(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.dangerous_rounded, size: 18),
                            label: const Text('批量紧急中止'),
                            onPressed: () => SmartStrmWebhook.showTestBatchAbort(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ===== 感谢 SmartStrm =====
          _buildSectionHeader('致谢', Icons.favorite_rounded, scheme),
          _SettingsCard(
            children: [
              ListTile(
                leading: _leadingIcon(scheme, isDark, Icons.code_rounded),
                title: const Text(
                  'SmartStrm',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                subtitle: const Text(
                  '感谢 SmartStrm 作者提供的优秀工具\n点击访问 GitHub 项目主页',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: Icon(Icons.open_in_new_rounded,
                    size: 18, color: scheme.outline),
                onTap: () async {
                  final uri = Uri.parse('https://github.com/Cp0204/SmartStrm');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==================== 事件处理 ====================

  Future<void> _onTestWebhook() async {
    final url = SpUtil.getString(AlistConstant.linkedDeletionWebhookUrl) ?? '';
    if (url.isEmpty) {
      SmartDialog.showToast('请先配置 Webhook 接口地址');
      return;
    }

    SmartDialog.showLoading(msg: '发送测试 Webhook...');
    try {
      final result = await SmartStrmWebhook.sendTestWebhook();
      SmartDialog.dismiss();

      if (result.statusCode == 200) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
                SizedBox(width: 8),
                Text('测试成功'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Webhook 接口连通正常', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    result.body,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.5),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.error_rounded, color: Colors.red, size: 28),
                SizedBox(width: 8),
                Text('测试失败'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HTTP ${result.statusCode}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    result.body,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.5),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      SmartDialog.dismiss();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.error_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('连接失败'),
            ],
          ),
          content: SelectableText(
            '$e',
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }
  }

  void _onViewLog() async {
    final content = await SmartStrmWebhook.readLog();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    const Text('Webhook 发送日志',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_rounded, size: 22),
                      tooltip: '清空全部',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: ctx,
                          builder: (dCtx) => AlertDialog(
                            title: const Text('清空日志'),
                            content: const Text('确定要清空所有 Webhook 发送日志吗？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dCtx, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(dCtx, true),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red),
                                child: const Text('清空'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await SmartStrmWebhook.clearLog();
                          if (ctx.mounted) Navigator.pop(ctx);
                          SmartDialog.showToast('日志已清空');
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    content,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.6,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onClearLog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定要清空所有 Webhook 发送日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SmartStrmWebhook.clearLog();
      SmartDialog.showToast('日志已清空');
    }
  }

  /// 高风险警告横幅
  Widget _buildWarningBanner(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.red.shade700.withOpacity(0.15),
            Colors.orange.shade800.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.red.shade400.withOpacity(0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.red.shade500.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: Colors.red.shade400,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⚠️ 高风险功能警告',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade400,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '此功能会在删除本地 .strm 文件后，自动通知 SmartStrm 后端同步删除云端存储中对应的真实媒体大文件（可能几十 GB）。\n\n'
                  '• 删除操作不可撤销\n'
                  '• 需先部署配置 SmartStrm 后端服务才能使用\n'
                  '• 请务必确认 strm 目录配置正确\n'
                  '• 内置空路径保护机制，但是否启用仍需谨慎\n\n'
                  '启用前请先在测试环境验证路径解析是否正常。',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathExample(
    ColorScheme scheme,
    String label,
    String path,
    bool isDark, {
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: scheme.outline,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: highlight
                ? scheme.primary.withOpacity(0.08)
                : scheme.surfaceVariant.withOpacity(0.4),
            borderRadius: BorderRadius.circular(6),
            border: highlight
                ? Border.all(color: scheme.primary.withOpacity(0.3))
                : null,
          ),
          child: Text(
            path,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: highlight ? scheme.primary : scheme.onSurface,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _leadingIcon(ColorScheme scheme, bool isDark, IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withOpacity(0.8),
            scheme.primaryContainer.withOpacity(0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 20,
        color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary,
      ),
    );
  }
}

/// 统一卡片容器（与 settings_screen.dart 风格一致）
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: isDark ? 0 : 1,
      shadowColor: scheme.shadow.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: isDark ? scheme.surfaceVariant.withOpacity(0.3) : scheme.surface,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                indent: 68,
                endIndent: 16,
                color: scheme.outlineVariant.withOpacity(0.25),
              ),
          ],
        ],
      ),
    );
  }
}
