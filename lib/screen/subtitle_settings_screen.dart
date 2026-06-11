import 'package:alist/util/subtitle/subtitle_controller.dart';
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
        // 开关卡片
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: isDark ? 0 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: isDark
              ? scheme.surfaceVariant.withOpacity(0.3)
              : scheme.surface,
          child: Obx(() => SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            secondary: Container(
              width: 40, height: 40,
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
              child: Icon(Icons.subtitles_rounded, size: 20,
                  color: isDark ? Colors.white.withOpacity(0.9) : scheme.primary),
            ),
            title: const Text('启用外挂字幕', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            subtitle: const Text('自动加载同名 SRT 字幕文件（支持本地和远程）',
                style: TextStyle(fontSize: 11)),
            value: settings.isSubtitleEnabled.value,
            onChanged: (v) => settings.setSubtitleEnabled(v),
          )),
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
                    Obx(() => Text('${SubtitleController.logs.length} 条',
                        style: TextStyle(fontSize: 11, color: scheme.outline))),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => SubtitleController.logs.clear(),
                      tooltip: '清空日志',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              Obx(() {
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
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
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
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}