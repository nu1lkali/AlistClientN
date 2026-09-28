import 'package:alist/util/player/kernel_rule_settings.dart';
import 'package:alist/util/player/video_format.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 按格式指定播放内核。
///
/// ExoPlayer 硬解省电、起播快，但老容器（ASF/AVI/RMVB/MPEG…）它根本没有
/// 解封装器；libmpv 自带完整 FFmpeg 什么都能放，但软解更费电、起播也慢些。
/// 自动选路在绝大多数情况下够用，这里给「想自己说了算」的用户一个出口。
class KernelRuleSettingsScreen extends StatefulWidget {
  const KernelRuleSettingsScreen({super.key});

  @override
  State<KernelRuleSettingsScreen> createState() =>
      _KernelRuleSettingsScreenState();
}

class _KernelRuleSettingsScreenState extends State<KernelRuleSettingsScreen> {
  final KernelRuleSettings _s = KernelRuleSettings.instance;
  final TextEditingController _probeController = TextEditingController();
  bool _on = false;
  String _probeResult = '';

  @override
  void initState() {
    super.initState();
    _on = _s.enabled;
  }

  @override
  void dispose() {
    _probeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlistScaffold(
      appbarTitle: const Text('按格式指定内核'),
      appbarActions: [
        IconButton(
          icon: const Icon(Icons.restart_alt_rounded),
          tooltip: '恢复默认配置',
          onPressed: _confirmReset,
        ),
        IconButton(
          icon: const Icon(Icons.add_rounded),
          tooltip: '添加格式',
          onPressed: () => _showAddDialog(context),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _buildHelpCard(scheme),
          _buildMasterSwitch(scheme),
          _buildProbeCard(scheme),
          if (!_on)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '开关关闭中：下面这些规则暂不生效，播放器按自动选路走 '
                '（容器嗅探 + ExoPlayer 优先 + 失败回落 libmpv）。',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          _buildUnknownTile(scheme),
          _buildGroup(scheme, 'ExoPlayer（硬解，省电）', Icons.bolt_rounded,
              Colors.green, KernelChoice.exo),
          _buildGroup(scheme, 'libmpv（兼容内核，什么都能放）',
              Icons.graphic_eq_rounded, Colors.orange, KernelChoice.compat),
          _buildGroup(
              scheme, '自动（交给播放器判断）', Icons.auto_awesome_rounded,
              scheme.outline, KernelChoice.auto),
        ],
      ),
    );
  }

  // ═══════════════ 卡片 ═══════════════

  Widget _buildHelpCard(ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: scheme.surfaceVariant.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '默认关闭，关闭时播放器的选路行为与以前完全一致。\n'
              '开启后按下面的清单决定内核：老格式（WMV/AVI/RMVB/MPEG…）走 libmpv，'
              '常见格式（MP4/MKV/MOV…）走 ExoPlayer。\n'
              '文件名认不出格式时（随机名、abcdef.(wmv).strm 之类的怪名字）'
              '单独按「识别不出格式时」那一行的设置走。',
              style: TextStyle(
                  fontSize: 12.5, height: 1.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildMasterSwitch(ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        secondary: Icon(Icons.tune_rounded, color: scheme.primary),
        title: const Text('启用按格式指定内核'),
        subtitle: Text(
          _on ? '已启用 · 规则生效中' : '已关闭 · 由播放器自动选路',
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
        value: _on,
        onChanged: (v) {
          _s.setEnabled(v);
          setState(() => _on = v);
        },
      ),
    );
  }

  /// 文件名识别测试：让「探测不出格式」这件事看得见。
  Widget _buildProbeCard(ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.search_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text('识别测试',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _probeController,
            decoration: InputDecoration(
              hintText: '粘贴一个文件名，如 abcdef.(wmv).strm',
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                tooltip: '识别',
                onPressed: _runProbe,
              ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _runProbe(),
          ),
          if (_probeResult.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_probeResult,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: scheme.onSurfaceVariant)),
          ],
        ]),
      ),
    );
  }

  void _runProbe() {
    final name = _probeController.text.trim();
    if (name.isEmpty) return;
    final probe = probeVideoFormat(name);
    final key = probe.ok ? probe.ext! : KernelRuleSettings.unknownKey;
    final choice = _s.ruleOf(key);
    final srcText = const {
      'bracket': '括号里的扩展名',
      'name': '文件名末尾扩展名',
      'url': 'URL 路径',
    }[probe.source];
    setState(() {
      _probeResult = probe.ok
          ? '识别为 .${probe.ext}（来源：$srcText）\n'
              '${_on ? '将使用：${choice.label}' : '当前开关关闭 → 自动选路'}'
          : '识别不出格式 → 走「识别不出格式时」的设置：${choice.label}\n'
              '（自动 = 读文件头嗅探真实容器，再决定 Exo 还是 libmpv）';
    });
  }

  // ═══════════════ 规则行 ═══════════════

  /// 探测不出格式时的兜底规则（键为 [KernelRuleSettings.unknownKey]）。
  Widget _buildUnknownTile(ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.help_outline_rounded, color: scheme.primary),
            title: const Text('识别不出格式时'),
            subtitle: const Text(
                '随机文件名 / 无扩展名 / 认不出的怪名字，默认「自动」：'
                '读文件头嗅探真实容器，仍判断不了就 Exo 优先、失败回落 libmpv',
                style: TextStyle(fontSize: 11.5, height: 1.4)),
          ),
          const SizedBox(height: 6),
          _ChoiceChips(
            value: _s.ruleOf(KernelRuleSettings.unknownKey),
            enabled: _on,
            onChanged: (c) => _apply(KernelRuleSettings.unknownKey, c),
          ),
        ]),
      ),
    );
  }

  Widget _buildGroup(ColorScheme scheme, String title, IconData icon,
      Color color, KernelChoice group) {
    final keys = _allKeys().where((k) => _s.ruleOf(k) == group).toList();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(width: 6),
            Text('${keys.length}',
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          ]),
          const SizedBox(height: 4),
          if (keys.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('（空）',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            )
          else
            for (final k in keys) _buildRuleRow(scheme, k),
        ]),
      ),
    );
  }

  Widget _buildRuleRow(ColorScheme scheme, String key) {
    final isPreset = KernelRuleSettings.defaultKeys.contains(key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 74,
          child: Text('.$key',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: _on ? scheme.onSurface : scheme.outline)),
        ),
        Expanded(
          child: _ChoiceChips(
            value: _s.ruleOf(key),
            enabled: _on,
            compact: true,
            onChanged: (c) => _apply(key, c),
          ),
        ),
        if (!isPreset)
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: scheme.outline),
            tooltip: '删除该格式',
            onPressed: () async {
              await _s.removeRule(key);
              if (mounted) setState(() {});
            },
          ),
      ]),
    );
  }

  Future<void> _apply(String key, KernelChoice c) async {
    await _s.setRule(key, c);
    if (mounted) setState(() {});
  }

  /// 展示用的全部键：预置清单 + 用户自定义 - 「识别不出格式」那个键。
  List<String> _allKeys() {
    final keys = <String>{
      ...KernelRuleSettings.defaultKeys,
      ..._s.rules.keys,
    }..remove(KernelRuleSettings.unknownKey);
    final list = keys.toList();
    final order = KernelRuleSettings.defaultKeys;
    list.sort((a, b) {
      final ia = order.indexOf(a);
      final ib = order.indexOf(b);
      final pa = ia < 0 ? 1 : 0;
      final pb = ib < 0 ? 1 : 0;
      if (pa != pb) return pa.compareTo(pb);
      return pa == 0 ? ia.compareTo(ib) : a.compareTo(b);
    });
    return list;
  }

  // ═══════════════ 添加 / 重置 ═══════════════

  void _showAddDialog(BuildContext context) {
    final controller = TextEditingController();
    var choice = KernelChoice.compat;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('添加格式'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '扩展名，如 wmv（不用加点）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              _ChoiceChips(
                value: choice,
                enabled: true,
                onChanged: (c) => setDialogState(() => choice = c),
              ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () async {
                  final ext = controller.text
                      .trim()
                      .toLowerCase()
                      .replaceAll(RegExp(r'^\.+'), '');
                  if (ext.isEmpty) return;
                  if (!RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext)) {
                    SmartDialog.showToast('扩展名只能是 1~5 位字母或数字');
                    return;
                  }
                  await _s.setRule(ext, choice);
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  setState(() {});
                },
                child: const Text('添加'),
              ),
            ],
          );
        });
      },
    );
  }

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认配置'),
        content: const Text('把所有格式恢复成预置配置：老格式走 libmpv，'
            '常见格式走 ExoPlayer，识别不出格式时自动。\n自定义的格式会被移除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await _s.resetToDefault();
              if (!mounted) return;
              Navigator.pop(ctx);
              setState(() {});
              SmartDialog.showToast('已恢复默认配置');
            },
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }
}

/// 三选一：自动 / Exo / MPV。
class _ChoiceChips extends StatelessWidget {
  const _ChoiceChips({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.compact = false,
  });

  final KernelChoice value;
  final ValueChanged<KernelChoice> onChanged;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      children: [
        for (final c in KernelChoice.values)
          ChoiceChip(
            label: Text(compact ? c.shortLabel : c.label,
                style: TextStyle(
                    fontSize: compact ? 11.5 : 12.5,
                    color: value == c
                        ? scheme.onPrimary
                        : (enabled
                            ? scheme.onSurface
                            : scheme.outline.withOpacity(0.6)))),
            selected: value == c,
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            backgroundColor: scheme.surfaceVariant.withOpacity(enabled ? 0.5 : 0.25),
            selectedColor: enabled ? scheme.primary : scheme.outline.withOpacity(0.5),
            side: BorderSide.none,
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 12, vertical: compact ? 2 : 6),
            onSelected: enabled ? (_) => onChanged(c) : null,
          ),
      ],
    );
  }
}
