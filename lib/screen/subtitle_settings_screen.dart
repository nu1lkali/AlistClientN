import 'package:alist/util/named_router.dart';
import 'package:alist/util/subtitle/subtitle_controller.dart';
import 'package:alist/util/subtitle/subtitle_matcher.dart';
import 'package:alist/util/subtitle/subtitle_settings.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 外挂字幕设置页面
/// 包含开关和日志查看功能
class SubtitleSettingsScreen extends StatelessWidget {
  const SubtitleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AlistScaffold(
      appbarTitle: const Text('外挂字幕'),
      body: const _SubtitleSettingsBody(),
    );
  }
}

class _SubtitleSettingsBody extends StatelessWidget {
  const _SubtitleSettingsBody();

  @override
  Widget build(BuildContext context) {
    final settings = SubtitleSettings.instance;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        // 匹配模式卡片
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: isDark ? 0 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: isDark
              ? scheme.surfaceVariant.withOpacity(0.3)
              : scheme.surface,
          child: Column(
            children: [
              Obx(() {
                final mode = settings.subtitleMatchMode.value;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.secondaryContainer.withOpacity(0.8),
                          scheme.secondaryContainer.withOpacity(0.5),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.search_rounded, size: 20,
                        color: isDark ? Colors.white.withOpacity(0.9) : scheme.secondary),
                  ),
                  title: const Text('字幕查找模式', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  subtitle: Text(_modeDescription(mode), style: const TextStyle(fontSize: 11)),
                  trailing: _buildModeChip(mode, settings, scheme, isDark),
                );
              }),
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('示例', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: scheme.primary)),
                    const SizedBox(height: 4),
                    Text(
                      '视频: www.98T.la@HEYZO-0806_iris2.mp4\n'
                      '字幕: HEYZO-0806.srt\n'
                      '→ 精确查找: ✗ 不匹配\n'
                      '→ 模糊查找: ✓ 提取番号 HEYZO-0806 匹配',
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace', height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // 字幕样式入口卡片
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: isDark ? 0 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: isDark
              ? scheme.surfaceVariant.withOpacity(0.3)
              : scheme.surface,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.tertiaryContainer.withOpacity(0.8),
                    scheme.tertiaryContainer.withOpacity(0.5),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.palette_rounded, size: 20,
                  color: isDark ? Colors.white.withOpacity(0.9) : scheme.tertiary),
            ),
            title: const Text('字幕样式自定义',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            subtitle: const Text('字体大小、颜色、描边、背景等', style: TextStyle(fontSize: 11)),
            trailing: Icon(Icons.chevron_right_rounded,
                color: scheme.outlineVariant, size: 22),
            onTap: () => Get.toNamed(NamedRouter.subtitleStyleSettings),
          ),
        ),

        const SizedBox(height: 8),

        // 说明卡片
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: isDark ? 0 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: isDark
              ? scheme.surfaceVariant.withOpacity(0.3)
              : scheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text('说明', style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: scheme.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• 播放视频时，自动在同目录下查找同名 .srt 字幕文件\n'
                  '• 对于远程视频，会通过 Alist API 下载并缓存字幕\n'
                  '• 缓存的字幕文件存储在 app 本地，避免重复下载\n'
                  '• 字幕在 Flutter 层统一渲染，ExoPlayer 和 MPV 内核样式一致',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.6),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // 日志卡片
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: isDark ? 0 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: isDark
              ? scheme.surfaceVariant.withOpacity(0.3)
              : scheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.bug_report_outlined, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('字幕加载日志', style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: scheme.primary)),
                    ),
                    Obx(() {
                      // 同时读取 logVersion 确保 Obx 在日志变化时重建
                      final _ = SubtitleController.logVersion.value;
                      return Text('${SubtitleController.logs.length} 条',
                          style: TextStyle(fontSize: 11, color: scheme.outline));
                    }),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () {
                        SubtitleController.logs.clear();
                        SubtitleController.logVersion.value++;
                      },
                      tooltip: '清空日志',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              Obx(() {
                // 同时读取 logVersion 确保 Obx 在日志变化时重建
                final _ = SubtitleController.logVersion.value;
                final logs = SubtitleController.logs;
                if (logs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('暂无日志\n播放视频后此处会显示字幕加载过程',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: scheme.outlineVariant)),
                    ),
                  );
                }
                return SizedBox(
                  height: 220,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final log = logs[logs.length - 1 - i]; // 最新的在最上面
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          log,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: log.contains('成功') || log.contains('找到')
                                ? Colors.green.shade300
                                : log.contains('异常') || log.contains('失败') || log.contains('未找到')
                                    ? Colors.red.shade300
                                    : scheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  /// 模式描述文本
  static String _modeDescription(SubtitleMatchMode mode) {
    switch (mode) {
      case SubtitleMatchMode.exact:
        return '文件名完全一致才匹配（去掉后缀，忽略大小写）';
      case SubtitleMatchMode.fuzzy:
        return '提取番号核心ID，字幕名包含该ID即匹配';
      case SubtitleMatchMode.dual:
        return '先精确查找，未命中再模糊查找（推荐）';
    }
  }

  /// 构建模式选择弹出菜单
  static Widget _buildModeChip(SubtitleMatchMode mode, SubtitleSettings settings,
      ColorScheme scheme, bool isDark) {
    final labels = {SubtitleMatchMode.exact: '精确', SubtitleMatchMode.fuzzy: '模糊', SubtitleMatchMode.dual: '双模式'};
    return ActionChip(
      label: Text(labels[mode]!, style: TextStyle(fontSize: 12,
          color: isDark ? Colors.white.withOpacity(0.9) : scheme.onSecondaryContainer)),
      backgroundColor: isDark
          ? scheme.secondaryContainer.withOpacity(0.5)
          : scheme.secondaryContainer.withOpacity(0.7),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onPressed: () {
        // 循环切换模式
        final nextIndex = (mode.index + 1) % SubtitleMatchMode.values.length;
        settings.setSubtitleMatchMode(SubtitleMatchMode.values[nextIndex]);
      },
    );
  }
}